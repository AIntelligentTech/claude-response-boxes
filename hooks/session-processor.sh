#!/usr/bin/env bash
#
# session-processor.sh - SessionEnd hook for box event emission
#
# Processes the session transcript to extract response boxes and emit
# BoxCreated events to the event store.
#
# HOOK TYPE: SessionEnd
#
# INPUT (stdin JSON):
#   {
#     "session_id": "abc123",
#     "transcript_path": "/path/to/transcript.jsonl",
#     "cwd": "/path/to/project",
#     "reason": "logout|clear|prompt_input_exit|other"
#   }
#
# OUTPUT: None (SessionEnd hooks don't inject context)
#
# EXIT CODES:
#   0 - Always (processing is best-effort, never blocks)
#
# EVENT STORE:
#   ~/.claude/analytics/boxes.jsonl - Append-only event log
#
# EVENTS EMITTED:
#   BoxCreated - One per box found in the transcript
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

ANALYTICS_DIR="${HOME}/.claude/analytics"
BOXES_FILE="${ANALYTICS_DIR}/boxes.jsonl"

SCHEMA_VERSION=1

# Initial scores by box type (used for base scoring)
# AI analysis can later adjust these via BoxEnriched events
declare -A INITIAL_SCORES=(
    ["Reflection"]=90
    ["Warning"]=90
    ["Pushback"]=85
    ["Assumption"]=80
    ["Choice"]=70
    ["Completion"]=70
    ["Concern"]=65
    ["Confidence"]=60
    ["Decision"]=55
    ["Sycophancy"]=50
    ["Suggestion"]=45
    ["Quality"]=40
    ["FollowUps"]=35
)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

log() {
    echo "[session-processor] $*" >&2
}

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
        "🔄") echo "Reflection" ;;
        *) echo "Unknown" ;;
    esac
}

get_initial_score() {
    local type="$1"
    echo "${INITIAL_SCORES[$type]:-40}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Transcript Processing
# ─────────────────────────────────────────────────────────────────────────────

extract_assistant_messages() {
    local transcript="$1"

    if [[ ! -f "$transcript" ]]; then
        return
    fi

    # Handle both JSON array and JSONL formats
    if head -1 "$transcript" 2>/dev/null | grep -q '^\['; then
        # JSON array format
        jq -r '.[] | select(.type == "assistant") | .content // ""' "$transcript" 2>/dev/null
    else
        # JSONL format
        jq -r 'select(.type == "assistant") | .content // ""' "$transcript" 2>/dev/null
    fi
}

parse_boxes_from_content() {
    local content="$1"
    local session_id="$2"
    local git_remote="$3"
    local git_branch="$4"
    local timestamp="$5"

    local turn_number=0
    local in_box=false
    local current_emoji=""
    local current_box=""

    while IFS= read -r line; do
        # Check for box start
        if [[ "$line" =~ ^(⚖️|🎯|💭|📊|↩️|⚠️|💡|🚨|🪞|✅|📋|🏁|🔄)[[:space:]].*─+ ]]; then
            # Save previous box if exists
            if [[ "$in_box" == "true" ]] && [[ -n "$current_box" ]]; then
                emit_box_created "$current_emoji" "$current_box" "$session_id" "$git_remote" "$git_branch" "$timestamp" "$turn_number"
            fi

            current_emoji="${BASH_REMATCH[1]}"
            current_box=""
            in_box=true
            turn_number=$((turn_number + 1))

        elif [[ "$line" =~ ^─+$ ]] && [[ "$in_box" == "true" ]]; then
            # End of box
            if [[ -n "$current_box" ]]; then
                emit_box_created "$current_emoji" "$current_box" "$session_id" "$git_remote" "$git_branch" "$timestamp" "$turn_number"
            fi
            in_box=false
            current_box=""
            current_emoji=""

        elif [[ "$in_box" == "true" ]]; then
            # Inside box - accumulate content
            current_box+="$line"$'\n'
        fi
    done <<< "$content"

    # Handle unclosed box
    if [[ "$in_box" == "true" ]] && [[ -n "$current_box" ]]; then
        emit_box_created "$current_emoji" "$current_box" "$session_id" "$git_remote" "$git_branch" "$timestamp" "$turn_number"
    fi
}

emit_box_created() {
    local emoji="$1"
    local box_content="$2"
    local session_id="$3"
    local git_remote="$4"
    local git_branch="$5"
    local timestamp="$6"
    local turn_number="$7"

    local box_type
    box_type=$(emoji_to_type "$emoji")

    local initial_score
    initial_score=$(get_initial_score "$box_type")

    # Parse fields from box content
    local fields="{}"
    while IFS= read -r line; do
        if [[ "$line" =~ ^\*\*([^:]+):\*\*[[:space:]]*(.+)$ ]]; then
            local field_name="${BASH_REMATCH[1]}"
            local field_value="${BASH_REMATCH[2]}"
            # Normalize field name (lowercase, underscores)
            field_name=$(echo "$field_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
            # Escape quotes for JSON
            field_value=$(echo "$field_value" | sed 's/"/\\"/g')
            fields=$(echo "$fields" | jq --arg k "$field_name" --arg v "$field_value" '. + {($k): $v}')
        fi
    done <<< "$box_content"

    # Build BoxCreated event
    # ID format: sess_{session_id}_{turn_number}
    local box_id="sess_${session_id}_${turn_number}"

    local event
    event=$(jq -c -n \
        --arg event "BoxCreated" \
        --arg id "$box_id" \
        --arg ts "$timestamp" \
        --arg box_type "$box_type" \
        --argjson fields "$fields" \
        --arg session_id "$session_id" \
        --arg git_remote "$git_remote" \
        --arg git_branch "$git_branch" \
        --argjson turn_number "$turn_number" \
        --argjson initial_score "$initial_score" \
        --argjson schema_version "$SCHEMA_VERSION" \
        '{
            event: $event,
            id: $id,
            ts: $ts,
            schema_version: $schema_version,
            box_type: $box_type,
            fields: $fields,
            context: {
                session_id: $session_id,
                git_remote: $git_remote,
                git_branch: $git_branch,
                turn_number: $turn_number
            },
            initial_score: $initial_score
        }')

    # Append to event store
    echo "$event" >> "$BOXES_FILE"

    # Echo for caller to count
    echo "$event"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Check dependencies
    if ! command -v jq &>/dev/null; then
        log "jq not available, skipping session processing"
        exit 0
    fi

    # Ensure analytics directory exists
    mkdir -p "$ANALYTICS_DIR"

    if [[ -f "$BOXES_FILE" ]] && [[ -s "$BOXES_FILE" ]]; then
        if head -c 1 "$BOXES_FILE" 2>/dev/null | grep -q '^\['; then
            log "Analytics event store is JSON array, expected JSONL. Back up $BOXES_FILE and migrate to JSONL before continuing."
            exit 0
        fi

        if ! jq -s 'length' "$BOXES_FILE" &>/dev/null; then
            log "Analytics event store is not valid JSON lines. Back up $BOXES_FILE and repair or reset to restore collection."
            exit 0
        fi

        local max_schema_version
        max_schema_version=$(jq -s -r '[.[] | (.schema_version // 0)] | max // 0' "$BOXES_FILE" 2>/dev/null || echo "0")
        if [[ -n "$max_schema_version" ]] && [[ "$max_schema_version" != "null" ]] && [[ "$max_schema_version" -gt "$SCHEMA_VERSION" ]]; then
            log "Analytics schema version ${max_schema_version} is newer than this collector supports. Update Claude Response Boxes to restore collection."
            exit 0
        fi
    fi

    # Read input from stdin
    local input
    input=$(cat)

    # Extract session info
    local session_id transcript_path cwd
    session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
    transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
    cwd=$(echo "$input" | jq -r '.cwd // empty')

    if [[ -z "$transcript_path" ]] || [[ ! -f "$transcript_path" ]]; then
        log "No transcript available, skipping"
        exit 0
    fi

    # Get git context
    local git_remote="" git_branch=""
    if [[ -n "$cwd" ]] && [[ -d "$cwd" ]]; then
        git_remote=$(cd "$cwd" && git remote get-url origin 2>/dev/null | sed -E 's|^(https?://\|git@)||; s|:|/|; s|\.git$||' || echo "")
        git_branch=$(cd "$cwd" && git branch --show-current 2>/dev/null || echo "")
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log "Processing session $session_id..."

    # Extract all assistant messages
    local content
    content=$(extract_assistant_messages "$transcript_path")

    if [[ -z "$content" ]]; then
        log "No assistant messages found"
        exit 0
    fi

    # Parse boxes and emit events
    local box_count=0
    while IFS= read -r event_json; do
        if [[ -n "$event_json" ]]; then
            box_count=$((box_count + 1))
        fi
    done < <(parse_boxes_from_content "$content" "$session_id" "$git_remote" "$git_branch" "$timestamp")

    if [[ "$box_count" -eq 0 ]]; then
        log "No boxes found in session"
        exit 0
    fi

    log "Emitted $box_count BoxCreated events"
    exit 0
}

main "$@"
