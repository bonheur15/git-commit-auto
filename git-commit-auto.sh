#!/bin/bash
#
# git-commit-auto
#
# Generates a commit message using the Gemini API based on staged changes
# and performs the commit.
#
# Usage:
#   git-commit-auto             - Creates a new commit from staged changes.
#   git-commit-auto regenerate  - Regenerates the message for the last commit and amends it.
#
# Dependencies:
# - curl: For making API requests.
# - jq: For parsing JSON responses.
# - git: For obvious reasons.
#
# Setup:
# 1. Place this script in your PATH (e.g., /usr/local/bin/git-commit-auto).
# 2. Make it executable: chmod +x /usr/local/bin/git-commit-auto
# 3. Set your API key as an environment variable:
#    export GEMINI_API_KEY="YOUR_API_KEY_HERE"
#    (Add this to your ~/.bashrc or ~/.zshrc)

set -e
set -o pipefail

# --- Configuration ---
MODEL="gemini-2.5-flash-lite"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"
SYSTEM_PROMPT="You are an expert programmer and commit message generator.
Your task is to write a concise and informative commit message for the given code diff.
The message MUST strictly follow the Conventional Commits specification.
It must be a single line, starting with a type (e.g., FEAT:, FIX:, REFACTOR:, DOCS:, STYLE:, TEST:, CHORE:), followed by a short description.
Do NOT include any extra text, explanations, or markdown formatting (like \`\`\`).
Just provide the single-line commit message."

# --- Helper Functions ---

# Function to check for required command-line tools
check_dependencies() {
    if [ -z "$GEMINI_API_KEY" ]; then
        echo "Error: GEMINI_API_KEY environment variable is not set."
        echo "Please set it before running this script."
        exit 1
    fi
    if ! command -v curl &> /dev/null; then
        echo "Error: curl is not installed. Please install it to continue."
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Please install it to continue."
        exit 1
    fi
}

# Function to generate a commit message from a git diff
generate_commit_message() {
    local git_diff="$1"

    if [ -z "$git_diff" ]; then
        echo "No changes found to generate a commit message."
        exit 0
    fi

    local json_payload
    json_payload=$(jq -n \
        --arg system_prompt "$SYSTEM_PROMPT" \
        --arg diff "$git_diff" \
        '{
            "systemInstruction": { "parts": [{ "text": $system_prompt }] },
            "contents": [{ "parts": [{ "text": ("Here is the diff:\n\n" + $diff) }] }],
            "generationConfig": {
                "temperature": 0.5,
                "maxOutputTokens": 100
            }
        }')

    echo "Contacting Gemini to generate commit message..."

    local response
    local max_retries=3
    local retry_delay=1
    for ((i=0; i<max_retries; i++)); do
        response=$(curl -s -X POST "${API_URL}?key=${GEMINI_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$json_payload")

        if echo "$response" | jq -e '.candidates[0].content.parts[0].text' > /dev/null; then
            break
        fi

        echo "Warning: API call failed or returned an unexpected response. Retrying in ${retry_delay}s..."
        echo "Response: $response"
        sleep $retry_delay
        retry_delay=$((retry_delay * 2))

        if [ $i -eq $((max_retries - 1)) ]; then
            echo "Error: Max retries reached. Failed to get a response from Gemini."
            exit 1
        fi
    done

    local commit_message
    commit_message=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' |
        sed 's/^```//; s/```$//' |
        sed 's/^[ \t]*//; s/[ \t]*$//' |
        head -n 1
    )

    if [ -z "$commit_message" ]; then
        echo "Error: Failed to parse a valid commit message from the AI response."
        echo "Raw Response: $response"
        exit 1
    fi

    echo "$commit_message"
}

# --- Main Logic ---

main() {
    check_dependencies

    if [ "$1" == "regenerate" ]; then
        echo "Regenerating last commit message..."
        # Get the diff from the last commit
        local git_diff
        git_diff=$(git diff HEAD~1..HEAD)
        
        local new_commit_message
        new_commit_message=$(generate_commit_message "$git_diff")
        
        echo "Generated Message: $new_commit_message"
        echo "Amending previous commit..."
        
        git commit --amend -m "$new_commit_message"
        
        echo "Commit amended successfully!"
    else
        # Default behavior: create a new commit from staged changes
        local git_diff
        git_diff=$(git diff --staged)

        if [ -z "$git_diff" ]; then
            echo "No staged changes found. Did you forget to 'git add'?"
            exit 0
        fi
        
        local commit_message
        commit_message=$(generate_commit_message "$git_diff")

        echo "Generated Message: $commit_message"
        echo "Committing..."

        git commit -m "$commit_message"

        echo "Commit successful!"
    fi
}

# Execute the main function with all script arguments
main "$@"
