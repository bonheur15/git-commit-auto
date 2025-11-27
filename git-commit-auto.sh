#!/bin/bash
#
# git-commit-auto
#
# Generates a commit message using the Gemini API based on staged changes
# and performs the commit.
#
# Usage:
#   git-commit-auto             - Creates a new commit from staged changes.
#   git-commit-auto push        - Creates a new commit and pushes it.
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

        echo "Warning: Gemini API call failed. Retrying in ${retry_delay}s..." >&2
        sleep $retry_delay
        retry_delay=$((retry_delay * 2))

        if [ $i -eq $((max_retries - 1)) ]; then
            echo "Error: Failed to get a response from Gemini after multiple retries." >&2
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
        echo "Error: Failed to parse a valid commit message from Gemini's response." >&2
        exit 1
    fi

    echo "$commit_message"
}

# --- Main Logic ---

# Function to update the changelog
update_changelog() {
    local commit_message="$1"
    local force_create="$2"
    local changelog_file="CHANGELOG.md"
    local date_header="## $(date +%Y-%m-%d)"

    if [ ! -f "$changelog_file" ]; then
        if [ "$force_create" = true ]; then
            echo "Creating $changelog_file..."
            echo -e "# Changelog\n" > "$changelog_file"
        else
            return 0
        fi
    fi

    # Check if today's header exists
    if grep -Fq "$date_header" "$changelog_file"; then
        # Insert message after the date header
        local temp_file=$(mktemp)
        awk -v header="$date_header" -v msg="- $commit_message" '
            $0 == header { print; print msg; next }
            { print }
        ' "$changelog_file" > "$temp_file" && mv "$temp_file" "$changelog_file"
    else
        # Insert new date header and message
        local temp_file=$(mktemp)
        if grep -q "^# Changelog" "$changelog_file"; then
             awk -v header="$date_header" -v msg="- $commit_message" '
                /^# Changelog/ { print; print ""; print header; print msg; next }
                { print }
            ' "$changelog_file" > "$temp_file" && mv "$temp_file" "$changelog_file"
        else
            # File exists but does not start with # Changelog
            echo -e "$date_header\n- $commit_message" | cat - "$changelog_file" > "$temp_file" && mv "$temp_file" "$changelog_file"
        fi
    fi

    echo "Updated $changelog_file"
}

main() {
    check_dependencies

    local regenerate_flag=false
    local push_flag=false
    local changelog_flag=false

    for arg in "$@"; do
        case "$arg" in
            regenerate) regenerate_flag=true ;;
            push)       push_flag=true ;;
            changelog)  changelog_flag=true ;;
        esac
    done

    if [ "$regenerate_flag" = true ]; then

        # Get the diff from the last commit
        local git_diff
        git_diff=$(git diff HEAD~1..HEAD)

        local new_commit_message
        new_commit_message=$(generate_commit_message "$git_diff")

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

        git commit -m "$commit_message"

        echo "Commit successful!"

        update_changelog "$commit_message" "$changelog_flag"

        if [ "$push_flag" = true ]; then
            echo "Pushing to remote..."
            git push
            echo "Push successful!"
        fi
    fi
}

# Execute the main function with all script arguments
main "$@"
