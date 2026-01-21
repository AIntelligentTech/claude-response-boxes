#!/usr/bin/env bash
#
# collect-boxes.sh - Extract response boxes from Claude output
#
# This script parses Claude's response for box patterns and records them
# to ~/.claude/analytics/boxes.jsonl for analysis.
#
# USAGE:
#   As a Claude Code hook (PostToolUse or similar):
#     echo "$RESPONSE_TEXT" | ./collect-boxes.sh
#
#   Manual testing:
#     cat response.txt | ./collect-boxes.sh
#
# ENVIRONMENT VARIABLES:
#   CLAUDE_SESSION_ID   - Session identifier (auto-generated if not set)
#   PROJECT_ID          - Override project identifier (optional)
#   BOX_ANALYTICS_FILE  - Override output file (default: ~/.claude/analytics/boxes.jsonl)
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

ANALYTICS_DIR="${HOME}/.claude/analytics"
ANALYTICS_FILE="${BOX_ANALYTICS_FILE:-${ANALYTICS_DIR}/boxes.jsonl}"

# Box patterns to detect (emoji at start of line)
# Note: These are the standard box emojis from the spec
BOX_PATTERNS='⚖️|🎯|💭|📊|↩️|⚠️|💡|🚨|🪞|✅|📋|🏁'

# ─────────────────────────────────────────────────────────────────────────────
# Context Gathering (git-based, portable)
# ─────────────────────────────────────────────────────────────────────────────

get_session_id() {
    if [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
        echo "${CLAUDE_SESSION_ID}"
    else
        # Generate a session ID based on timestamp + random
        echo "auto-$(date +%Y%m%d%H%M%S)-$$"
    fi
}

get_git_remote() {
    if git rev-parse --git-dir &>/dev/null; then
        # Get remote URL and clean it up
        local remote
        remote=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ -n "$remote" ]]; then
            # Remove protocol prefix and .git suffix
            echo "$remote" | sed -E 's|^(https?://\|git@)||; s|:|/|; s|\.git$||'
        else
            echo "local/$(basename "$(pwd)")"
        fi
    else
        # Not a git repo - use PROJECT_ID or directory name
        echo "${PROJECT_ID:-local/$(basename "$(pwd)")}"
    fi
}

get_git_branch() {
    if git rev-parse --git-dir &>/dev/null; then
        git branch --show-current 2>/dev/null || echo "detached"
    else
        echo "none"
    fi
}

get_relative_path() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        echo ""
        return
    fi

    if git rev-parse --git-dir &>/dev/null; then
        # Convert to git-root-relative path
        local git_root
        git_root=$(git rev-parse --show-toplevel 2>/dev/null)
        if [[ -n "$git_root" ]] && [[ "$file" == "$git_root"* ]]; then
            echo "${file#$git_root/}"
        else
            basename "$file"
        fi
    else
        basename "$file"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Box Parsing
# ─────────────────────────────────────────────────────────────────────────────

# Map emoji to box type
emoji_to_type() {
    local emoji="$1"
    case "$emoji" in
        "⚖️") echo "Choice" ;;
        "🎯") echo "Decision" ;;
        "💭") echo "Assumption" ;;
        "📊") echo "Confidence" ;;
        "↩️") echo "Pushback" ;;
        "⚠️") echo "Concern" ;;
        "💡") echo "Suggestion" ;;
        "🚨") echo "Warning" ;;
        "🪞") echo "Sycophancy" ;;
        "✅") echo "Quality" ;;
        "📋") echo "FollowUps" ;;
        "🏁") echo "Completion" ;;
        *) echo "Unknown" ;;
    esac
}

# Parse a single box block and extract fields
parse_box() {
    local box_text="$1"
    local box_type="$2"

    # Extract fields based on **Field:** pattern
    local fields="{}"

    # Common field extraction
    while IFS= read -r line; do
        if [[ "$line" =~ ^\*\*([^:]+):\*\*[[:space:]]*(.+)$ ]]; then
            local field_name="${BASH_REMATCH[1]}"
            local field_value="${BASH_REMATCH[2]}"
            # Lowercase field name, replace spaces with underscores
            field_name=$(echo "$field_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
            # Escape quotes in value
            field_value=$(echo "$field_value" | sed 's/"/\\"/g')
            fields=$(echo "$fields" | jq --arg k "$field_name" --arg v "$field_value" '. + {($k): $v}')
        fi
    done <<< "$box_text"

    echo "$fields"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Processing
# ─────────────────────────────────────────────────────────────────────────────

process_response() {
    local response="$1"
    local timestamp
    timestamp=$(date -Iseconds)

    # Gather context once
    local session_id git_remote git_branch
    session_id=$(get_session_id)
    git_remote=$(get_git_remote)
    git_branch=$(get_git_branch)

    # Track turn number (simple increment based on existing records in session)
    local turn_number=1
    if [[ -f "$ANALYTICS_FILE" ]]; then
        local count
        count=$(grep -c "\"session_id\":\"${session_id}\"" "$ANALYTICS_FILE" 2>/dev/null) || count=0
        turn_number=$((count + 1))
    fi

    # Find all boxes in the response
    local in_box=false
    local current_emoji=""
    local current_box=""
    local boxes_found=0

    while IFS= read -r line; do
        # Check for box start (emoji followed by type and dashes)
        if [[ "$line" =~ ^(⚖️|🎯|💭|📊|↩️|⚠️|💡|🚨|🪞|✅|📋|🏁)[[:space:]].*─+ ]]; then
            # If we were already in a box, save the previous one
            if [[ "$in_box" == "true" ]] && [[ -n "$current_box" ]]; then
                save_box "$current_emoji" "$current_box" "$timestamp" "$session_id" "$git_remote" "$git_branch" "$turn_number"
                boxes_found=$((boxes_found + 1))
            fi

            # Start new box
            current_emoji="${BASH_REMATCH[1]}"
            current_box=""
            in_box=true
        elif [[ "$line" =~ ^─+$ ]] && [[ "$in_box" == "true" ]]; then
            # End of box (closing dashes)
            if [[ -n "$current_box" ]]; then
                save_box "$current_emoji" "$current_box" "$timestamp" "$session_id" "$git_remote" "$git_branch" "$turn_number"
                boxes_found=$((boxes_found + 1))
            fi
            in_box=false
            current_box=""
            current_emoji=""
        elif [[ "$in_box" == "true" ]]; then
            # Inside a box - accumulate content
            current_box+="$line"$'\n'
        fi
    done <<< "$response"

    # Handle case where box wasn't closed
    if [[ "$in_box" == "true" ]] && [[ -n "$current_box" ]]; then
        save_box "$current_emoji" "$current_box" "$timestamp" "$session_id" "$git_remote" "$git_branch" "$turn_number"
        boxes_found=$((boxes_found + 1))
    fi

    if [[ $boxes_found -gt 0 ]]; then
        echo "[collect-boxes] Recorded $boxes_found box(es) to $ANALYTICS_FILE" >&2
    fi
}

save_box() {
    local emoji="$1"
    local box_content="$2"
    local timestamp="$3"
    local session_id="$4"
    local git_remote="$5"
    local git_branch="$6"
    local turn_number="$7"

    local box_type
    box_type=$(emoji_to_type "$emoji")

    local fields
    fields=$(parse_box "$box_content" "$box_type")

    # Build the JSON record
    local record
    record=$(jq -n \
        --arg ts "$timestamp" \
        --arg type "$box_type" \
        --argjson fields "$fields" \
        --arg session_id "$session_id" \
        --arg git_remote "$git_remote" \
        --arg git_branch "$git_branch" \
        --argjson turn_number "$turn_number" \
        '{
            ts: $ts,
            type: $type,
            fields: $fields,
            context: {
                session_id: $session_id,
                git_remote: $git_remote,
                git_branch: $git_branch,
                turn_number: $turn_number
            }
        }')

    # Ensure analytics directory exists
    mkdir -p "$(dirname "$ANALYTICS_FILE")"

    # Append to JSONL file
    echo "$record" >> "$ANALYTICS_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Check for jq
    if ! command -v jq &>/dev/null; then
        echo "[collect-boxes] Error: jq is required but not installed" >&2
        exit 1
    fi

    # Read response from stdin or argument
    local response
    if [[ $# -gt 0 ]]; then
        response="$1"
    elif [[ ! -t 0 ]]; then
        response=$(cat)
    else
        echo "Usage: echo \"\$RESPONSE\" | $0" >&2
        echo "   or: $0 \"response text\"" >&2
        exit 1
    fi

    if [[ -n "$response" ]]; then
        process_response "$response"
    fi
}

main "$@"
exit 0
