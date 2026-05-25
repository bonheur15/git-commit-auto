#!/bin/bash
#
# git-commit-auto
#
# Generates commit messages using Gemini API based on staged changes.
# Supports automatic splitting for large staged changes.
#
# Usage:
#   git-commit-auto                 - Commit staged changes.
#   git-commit-auto push            - Commit and push.
#   git-commit-auto regenerate      - Regenerate and amend last commit message.
#   git-commit-auto changelog       - Commit and append message to CHANGELOG.md.
#   git-commit-auto split           - Force split staged files into multiple commits.
#   git-commit-auto no-split        - Disable auto split for this run.
#   git-commit-auto version         - Show version and release timestamp.
#   git-commit-auto check-update    - Check if a newer script version is available.
#   git-commit-auto update          - Download and replace script with latest version.
#   git-commit-auto help            - Show command help.

set -e
set -o pipefail

# --- Release Metadata ---
SCRIPT_VERSION="1.1.0"
SCRIPT_RELEASED_AT="2026-02-14T00:00:00Z"
UPDATE_URL="https://git-auto.hubfly.cloud/git-commit-auto.sh"

# --- Configuration ---
MODELS=("gemini-2.5-flash-lite" "gemini-2.5-flash" "gemini-3-flash-preview")

# Large commit split heuristics
BIG_COMMIT_FILE_THRESHOLD=8
BIG_COMMIT_LINE_THRESHOLD=500
SPLIT_CHUNK_SIZE=4

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

print_help() {
    cat <<'HELP'
git-commit-auto commands:
  (no args)       Commit staged changes with AI-generated message
  push            Commit then push
  regenerate      Regenerate and amend last commit message
  changelog       Append generated message(s) to CHANGELOG.md
  split           Force split staged files into multiple commits
  no-split        Disable automatic split behavior for this run
  dry-run         Preview generated message(s), do not commit
  version         Show script version and release timestamp
  check-update    Check if remote script has a newer version
  update          Download latest script and replace current script
  help            Show this help

You can combine arguments, for example:
  git commit-auto split push changelog
HELP
}

is_valid_semver() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

version_greater() {
    local a="$1"
    local b="$2"
    [ "$(printf '%s\n' "$a" "$b" | sort -V | tail -n1)" = "$a" ] && [ "$a" != "$b" ]
}

get_remote_version() {
    local tmp
    tmp=$(mktemp)
    curl -fsSL "$UPDATE_URL" -o "$tmp"
    local remote_version
    remote_version=$(sed -n 's/^SCRIPT_VERSION="\(.*\)"$/\1/p' "$tmp" | head -n 1)
    local remote_released_at
    remote_released_at=$(sed -n 's/^SCRIPT_RELEASED_AT="\(.*\)"$/\1/p' "$tmp" | head -n 1)

    if [ -z "$remote_version" ]; then
        remote_version="unknown"
    fi
    if [ -z "$remote_released_at" ]; then
        remote_released_at="unknown"
    fi

    echo "$remote_version|$remote_released_at|$tmp"
}

check_update() {
    check_basic_dependencies
    local data
    data=$(get_remote_version)
    local remote_version remote_released_at tmp
    remote_version=$(echo "$data" | cut -d'|' -f1)
    remote_released_at=$(echo "$data" | cut -d'|' -f2)
    tmp=$(echo "$data" | cut -d'|' -f3)

    if [ "$remote_version" = "unknown" ]; then
        echo "Remote script does not expose version metadata yet."
        echo "Local version:  $SCRIPT_VERSION ($SCRIPT_RELEASED_AT)"
        rm -f "$tmp"
        return 0
    fi

    if ! is_valid_semver "$SCRIPT_VERSION" || ! is_valid_semver "$remote_version"; then
        echo "Local version:  $SCRIPT_VERSION ($SCRIPT_RELEASED_AT)"
        echo "Remote version: $remote_version ($remote_released_at)"
        echo "Warning: non-semver version format detected; cannot compare reliably."
        rm -f "$tmp"
        return 0
    fi

    if version_greater "$remote_version" "$SCRIPT_VERSION"; then
        echo "Update available."
        echo "Local version:  $SCRIPT_VERSION ($SCRIPT_RELEASED_AT)"
        echo "Remote version: $remote_version ($remote_released_at)"
    else
        echo "You are up to date."
        echo "Local version:  $SCRIPT_VERSION ($SCRIPT_RELEASED_AT)"
        echo "Remote version: $remote_version ($remote_released_at)"
    fi

    rm -f "$tmp"
}

run_update() {
    check_basic_dependencies

    local script_path
    script_path="${BASH_SOURCE[0]}"

    local data
    data=$(get_remote_version)
    local remote_version remote_released_at tmp
    remote_version=$(echo "$data" | cut -d'|' -f1)
    remote_released_at=$(echo "$data" | cut -d'|' -f2)
    tmp=$(echo "$data" | cut -d'|' -f3)

    chmod +x "$tmp"

    if cmp -s "$tmp" "$script_path"; then
        echo "Already on latest script content ($SCRIPT_VERSION)."
        rm -f "$tmp"
        return 0
    fi

    if cp "$tmp" "$script_path"; then
        chmod +x "$script_path"
        echo "Updated successfully."
        echo "Installed: $script_path"
        echo "Previous version: $SCRIPT_VERSION ($SCRIPT_RELEASED_AT)"
        if [ "$remote_version" = "unknown" ]; then
            echo "New version:      unknown (remote script has no metadata yet)"
        else
            echo "New version:      $remote_version ($remote_released_at)"
        fi
        rm -f "$tmp"
        return 0
    fi

    rm -f "$tmp"
    echo "Error: Failed to write updated script to $script_path" >&2
    echo "Try running with sufficient permissions for that location." >&2
    return 1
}

check_basic_dependencies() {
    for cmd in curl git; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: $cmd is not installed. Please install it to continue."
            exit 1
        fi
    done
}

check_ai_dependencies() {
    check_basic_dependencies
    for cmd in jq; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: $cmd is not installed. Please install it to continue."
            exit 1
        fi
    done

    if [ -z "$GEMINI_API_KEY" ]; then
        echo "Error: GEMINI_API_KEY environment variable is not set."
        echo "Please set it before running AI commit generation."
        exit 1
    fi
}

generate_commit_message() {
    local git_diff="$1"

    if [ -z "$git_diff" ]; then
        echo "No changes found to generate a commit message." >&2
        exit 0
    fi

    # Truncate very large diffs to avoid argument length and API limit issues
    local max_diff_len=200000
    if [ ${#git_diff} -gt $max_diff_len ]; then
        git_diff="${git_diff:0:$max_diff_len}\n\n... [diff truncated to ${max_diff_len} chars due to size]"
    fi

    local json_payload
    json_payload=$(printf '%s' "$git_diff" | jq -Rs \
        --arg system_prompt "$SYSTEM_PROMPT" \
        '{
            "systemInstruction": { "parts": [{ "text": $system_prompt }] },
            "contents": [{ "parts": [{ "text": ("Here is the diff:\n\n" + .) }] }],
            "generationConfig": {
                "temperature": 0.4,
                "maxOutputTokens": 800
            }
        }')

    local response
    local max_retries_per_model=3
    local commit_message=""

    for model in "${MODELS[@]}"; do
        echo "Attempting to generate with model: $model..." >&2

        local api_url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent"
        local retry_delay=1
        local model_success=false

        for ((i=0; i<max_retries_per_model; i++)); do
            response=$(printf '%s' "$json_payload" | curl -s -X POST "${api_url}?key=${GEMINI_API_KEY}" \
                -H "Content-Type: application/json" \
                -d @-)

            if echo "$response" | jq -e '.candidates[0].content.parts[0].text' > /dev/null; then
                model_success=true
                break
            fi

            echo "Warning: $model failed (Attempt $((i+1))/$max_retries_per_model)." >&2

            local error_msg
            error_msg=$(echo "$response" | jq -r '.error.message' 2>/dev/null)

            if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
                echo -e "\033[31mAPI Error:\033[0m $error_msg" >&2
            else
                echo -e "\033[31mRaw Response:\033[0m $(echo "$response" | head -c 200)..." >&2
            fi

            echo "Retrying in ${retry_delay}s..." >&2
            sleep "$retry_delay"
            retry_delay=$((retry_delay * 2))
        done

        if [ "$model_success" = true ]; then
            commit_message=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text' |
                sed 's/^```[a-z]*//; s/```$//' |
                sed 's/^[ \t]*//; s/[ \t]*$//'
            )
            break
        else
            echo "Error: All attempts failed for $model. Switching to next model..." >&2
        fi
    done

    if [ -z "$commit_message" ]; then
        echo "CRITICAL ERROR: Failed to generate commit message using all available models." >&2
        exit 1
    fi

    echo "$commit_message"
}

update_changelog() {
    local commit_message="$1"
    local force_create="$2"
    local changelog_file="CHANGELOG.md"
    local date_header="## $(date +%Y-%m-%d)"

    # Changelog updates are opt-in only.
    if [ "$force_create" != true ]; then
        return 0
    fi

    if [ ! -f "$changelog_file" ]; then
        echo "Creating $changelog_file..."
        echo -e "# Changelog\n" > "$changelog_file"
    fi

    if grep -Fq "$date_header" "$changelog_file"; then
        local temp_file
        temp_file=$(mktemp)
        awk -v header="$date_header" -v msg="- $commit_message" '
            $0 == header { print; print msg; next }
            { print }
        ' "$changelog_file" > "$temp_file" && mv "$temp_file" "$changelog_file"
    else
        local temp_file
        temp_file=$(mktemp)
        if grep -q "^# Changelog" "$changelog_file"; then
             awk -v header="$date_header" -v msg="- $commit_message" '
                /^# Changelog/ { print; print ""; print header; print msg; next }
                { print }
            ' "$changelog_file" > "$temp_file" && mv "$temp_file" "$changelog_file"
        else
            echo -e "$date_header\n- $commit_message" | cat - "$changelog_file" > "$temp_file" && mv "$temp_file" "$changelog_file"
        fi
    fi

    echo "Updated $changelog_file"
}

has_partially_staged_files() {
    local staged unstaged
    staged=$(git diff --cached --name-only | sort -u)
    unstaged=$(git diff --name-only | sort -u)

    if [ -z "$staged" ] || [ -z "$unstaged" ]; then
        return 1
    fi

    if comm -12 <(printf '%s\n' "$staged") <(printf '%s\n' "$unstaged") | grep -q .; then
        return 0
    fi

    return 1
}

is_big_staged_commit() {
    local staged_files_count
    staged_files_count=$(git diff --cached --name-only | wc -l | tr -d ' ')

    local changed_lines
    changed_lines=$(git diff --cached --numstat | awk '{
        add=$1; del=$2;
        if (add == "-") add=0;
        if (del == "-") del=0;
        sum += add + del;
    } END { print sum + 0 }')

    if [ "$staged_files_count" -gt "$BIG_COMMIT_FILE_THRESHOLD" ] || [ "$changed_lines" -gt "$BIG_COMMIT_LINE_THRESHOLD" ]; then
        return 0
    fi

    return 1
}

commit_current_staged() {
    local changelog_flag="$1"
    local dry_run_flag="$2"

    local git_diff
    git_diff=$(git diff --staged)
    if [ -z "$git_diff" ]; then
        echo "No staged changes found. Did you forget to 'git add'?"
        return 0
    fi

    local commit_message
    commit_message=$(generate_commit_message "$git_diff")

    echo "------------------------------------------------"
    echo -e "Commit Message Preview:\n\n$commit_message"
    echo "------------------------------------------------"

    if [ "$dry_run_flag" = true ]; then
        echo "Dry run enabled: commit was not created."
        return 0
    fi

    git commit -m "$commit_message"
    echo "Commit successful!"

    update_changelog "$commit_message" "$changelog_flag"
}

commit_split_staged() {
    local push_flag="$1"
    local changelog_flag="$2"
    local dry_run_flag="$3"

    if has_partially_staged_files; then
        echo "Error: split mode does not support partially staged files." >&2
        echo "Stage full files or use 'no-split' for a single commit." >&2
        exit 1
    fi

    local staged_files
    mapfile -t staged_files < <(git diff --cached --name-only)

    local total_files=${#staged_files[@]}
    if [ "$total_files" -eq 0 ]; then
        echo "No staged changes found. Did you forget to 'git add'?"
        return 0
    fi

    local total_commits=$(( (total_files + SPLIT_CHUNK_SIZE - 1) / SPLIT_CHUNK_SIZE ))
    echo "Splitting staged changes: $total_files files into $total_commits commits (chunk size: $SPLIT_CHUNK_SIZE)."

    git restore --staged :/

    local i=0
    local batch=1
    while [ "$i" -lt "$total_files" ]; do
        local chunk=("${staged_files[@]:i:SPLIT_CHUNK_SIZE}")
        git add -- "${chunk[@]}"

        echo "\nBatch $batch/$total_commits files:"
        printf '  - %s\n' "${chunk[@]}"

        local git_diff
        git_diff=$(git diff --staged)

        if [ -z "$git_diff" ]; then
            echo "Skipping empty batch."
            i=$((i + SPLIT_CHUNK_SIZE))
            batch=$((batch + 1))
            continue
        fi

        local commit_message
        commit_message=$(generate_commit_message "$git_diff")

        echo "------------------------------------------------"
        echo -e "Commit Message Preview (batch $batch):\n\n$commit_message"
        echo "------------------------------------------------"

        if [ "$dry_run_flag" = false ]; then
            git commit -m "$commit_message"
            echo "Batch $batch committed successfully."
            update_changelog "$commit_message" "$changelog_flag"
        else
            echo "Dry run enabled: batch $batch was not committed."
        fi

        i=$((i + SPLIT_CHUNK_SIZE))
        batch=$((batch + 1))
    done

    if [ "$push_flag" = true ] && [ "$dry_run_flag" = false ]; then
        echo "Pushing to remote..."
        git push
        echo "Push successful!"
    fi
}

main() {
    local regenerate_flag=false
    local push_flag=false
    local changelog_flag=false
    local split_flag=false
    local no_split_flag=false
    local dry_run_flag=false

    local cmd="commit"

    for arg in "$@"; do
        case "$arg" in
            regenerate)
                cmd="regenerate"
                regenerate_flag=true
                ;;
            push)
                push_flag=true
                ;;
            changelog)
                changelog_flag=true
                ;;
            split)
                split_flag=true
                ;;
            no-split)
                no_split_flag=true
                ;;
            dry-run)
                dry_run_flag=true
                ;;
            version)
                cmd="version"
                ;;
            check-update)
                cmd="check-update"
                ;;
            update)
                cmd="update"
                ;;
            help|-h|--help)
                cmd="help"
                ;;
            "")
                ;;
            *)
                echo "Error: Unknown argument '$arg'"
                echo
                print_help
                exit 1
                ;;
        esac
    done

    case "$cmd" in
        help)
            print_help
            ;;
        version)
            echo "git-commit-auto $SCRIPT_VERSION"
            echo "Released: $SCRIPT_RELEASED_AT"
            ;;
        check-update)
            check_update
            ;;
        update)
            run_update
            ;;
        regenerate)
            if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
                echo "Error: This command must be run inside a git repository." >&2
                exit 1
            fi

            check_ai_dependencies

            local git_diff
            git_diff=$(git diff HEAD~1..HEAD)
            local new_commit_message
            new_commit_message=$(generate_commit_message "$git_diff")

            echo "------------------------------------------------"
            echo -e "New Message Preview:\n\n$new_commit_message"
            echo "------------------------------------------------"

            if [ "$dry_run_flag" = true ]; then
                echo "Dry run enabled: commit amend was not performed."
                exit 0
            fi

            echo "Amending previous commit..."
            git commit --amend -m "$new_commit_message"
            echo "Commit amended successfully!"

            if [ "$push_flag" = true ]; then
                echo "Pushing amended commit..."
                git push --force-with-lease
                echo "Push successful!"
            fi
            ;;
        commit)
            if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
                echo "Error: This command must be run inside a git repository." >&2
                exit 1
            fi

            if git diff --cached --quiet; then
                echo "No staged changes found. Did you forget to 'git add'?"
                exit 0
            fi

            check_ai_dependencies

            local do_split=false
            if [ "$no_split_flag" = true ]; then
                do_split=false
            elif [ "$split_flag" = true ]; then
                do_split=true
            elif is_big_staged_commit; then
                do_split=true
            fi

            if [ "$do_split" = true ]; then
                commit_split_staged "$push_flag" "$changelog_flag" "$dry_run_flag"
            else
                commit_current_staged "$changelog_flag" "$dry_run_flag"

                if [ "$push_flag" = true ] && [ "$dry_run_flag" = false ]; then
                    echo "Pushing to remote..."
                    git push
                    echo "Push successful!"
                fi
            fi
            ;;
    esac
}

main "$@"
