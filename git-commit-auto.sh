#!/bin/bash
#
# git-commit-auto
#
# Generates a commit message using the Gemini API based on staged changes.
# It attempts to use the primary model first. If that fails 3 times,
# it switches to the next model in the list.
#
# Usage:
#   git-commit-auto             - Creates a new commit from staged changes.
#   git-commit-auto push        - Creates a new commit and pushes it.
#   git-commit-auto regenerate  - Regenerates the message for the last commit and amends it.

set -e
set -o pipefail

# --- Configuration ---

# List of models to try in order.
MODELS=("gemini-2.5-flash-lite" "gemini-2.5-flash" "gemini-3-flash-preview")

# Updated Prompt for Multi-line support
SYSTEM_PROMPT="You are an expert programmer and commit message generator.
Your task is to write a concise and informative commit message for the given code diff.

Rules:
1. STRICTLY follow the Conventional Commits specification.
2. The first line must be the 'Subject': a type (FEAT, FIX, REFACTOR, DOCS, CHORE, etc) and a short summary.
3. If the changes are trivial (e.g., small typo fix, single file style change), keep it to ONE line only.
4. If the changes are significant, complex, or affect multiple files:
   - Leave one empty line after the Subject.
   - Add a 'Body' with a bulleted list (-) explaining WHAT changed and WHY.
5. Do NOT include markdown formatting like \`\`\` or bold headers like '**Description:**'.
6. Just output the raw commit message text."

# --- Helper Functions ---

check_dependencies() {
    if [ -z "$GEMINI_API_KEY" ]; then
        echo "Error: GEMINI_API_KEY environment variable is not set."
        echo "Please set it before running this script."
        exit 1
    fi
    for cmd in curl jq git; do
        if ! command -v $cmd &> /dev/null; then
            echo "Error: $cmd is not installed. Please install it to continue."
            exit 1
        fi
    done
}

generate_commit_message() {
    local git_diff="$1"

    # Print to stderr so it doesn't get captured in the variable
    if [ -z "$git_diff" ]; then
        echo "No changes found to generate a commit message." >&2
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
                "temperature": 0.4,
                "maxOutputTokens": 800
            }
        }')

    local response
    local max_retries_per_model=3
    local commit_message=""

    # --- Outer Loop: Iterate through Models ---
    for model in "${MODELS[@]}"; do
        # IMPORTANT: >&2 ensures this prints to screen, not to the variable
        echo "Attempting to generate with model: $model..." >&2

        local api_url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent"
        local retry_delay=1
        local model_success=false

        # --- Inner Loop: Retries for the specific Model ---
        for ((i=0; i<max_retries_per_model; i++)); do
            response=$(curl -s -X POST "${api_url}?key=${GEMINI_API_KEY}" \
                -H "Content-Type: application/json" \
                -d "$json_payload")

            # 1. Check if we got a valid candidate response
            if echo "$response" | jq -e '.candidates[0].content.parts[0].text' > /dev/null; then
                model_success=true
                break # Success! Break inner retry loop
            fi

            # 2. DEBUGGING: logic for failure
            echo "Warning: $model failed (Attempt $((i+1))/$max_retries_per_model)." >&2

            # Try to parse the specific error message from JSON
            local error_msg
            error_msg=$(echo "$response" | jq -r '.error.message' 2>/dev/null)

            if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
                echo -e "\033[31mAPI Error:\033[0m $error_msg" >&2
            else
                # If not valid JSON or no error message, print raw response (truncated)
                echo -e "\033[31mRaw Response:\033[0m $(echo "$response" | head -c 200)..." >&2
            fi

            echo "Retrying in ${retry_delay}s..." >&2
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
        done

        if [ "$model_success" = true ]; then
            # Extract message, remove code blocks, strip leading/trailing whitespace
            commit_message=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' |
                sed 's/^```[a-z]*//; s/```$//' |
                sed 's/^[ \t]*//; s/[ \t]*$//'
            )
            break # Success! Break outer model loop
        else
            echo "Error: All attempts failed for $model. Switching to next model..." >&2
        fi
    done

    if [ -z "$commit_message" ]; then
        echo "CRITICAL ERROR: Failed to generate commit message using all available models." >&2
        exit 1
    fi

    # Only this line should be printed to stdout (for capture)
    echo "$commit_message"
}

# --- Main Logic ---

main() {
    check_dependencies

    if [ "$1" == "regenerate" ]; then
        local git_diff
        git_diff=$(git diff HEAD~1..HEAD)
        local new_commit_message
        new_commit_message=$(generate_commit_message "$git_diff")

        echo "------------------------------------------------"
        echo -e "New Message Preview:\n\n$new_commit_message"
        echo "------------------------------------------------"

        echo "Amending previous commit..."
        git commit --amend -m "$new_commit_message"
        echo "Commit amended successfully!"
    else
        local git_diff
        git_diff=$(git diff --staged)
        if [ -z "$git_diff" ]; then
            echo "No staged changes found. Did you forget to 'git add'?"
            exit 0
        fi

        local commit_message
        commit_message=$(generate_commit_message "$git_diff")

        # Preview the message before committing
        echo "------------------------------------------------"
        echo -e "Commit Message Preview:\n\n$commit_message"
        echo "------------------------------------------------"

        git commit -m "$commit_message"
        echo "Commit successful!"

        if [ "$1" == "push" ]; then
            echo "Pushing to remote..."
            git push
            echo "Push successful!"
        fi
    fi
}

main "$@"
