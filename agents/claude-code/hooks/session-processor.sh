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
#   ~/.response-boxes/analytics/boxes.jsonl - Append-only event log
#
# EVENTS EMITTED:
#   BoxCreated - One per box found in the transcript
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

DEFAULT_BASE_DIR="${HOME}/.response-boxes"
DEFAULT_ANALYTICS_DIR="${DEFAULT_BASE_DIR}/analytics"
DEFAULT_BOXES_FILE="${DEFAULT_ANALYTICS_DIR}/boxes.jsonl"
LEGACY_BOXES_FILE="${HOME}/.claude/analytics/boxes.jsonl"

ANALYTICS_DIR="${RESPONSE_BOXES_ANALYTICS_DIR:-${DEFAULT_ANALYTICS_DIR}}"
BOXES_FILE="${RESPONSE_BOXES_FILE:-${DEFAULT_BOXES_FILE}}"

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

legacy_store_is_valid_jsonl() {
    local file="$1"
    if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
        return 1
    fi

    if head -c 1 "$file" 2>/dev/null | grep -q '^\['; then
        return 1
    fi

    jq -s 'length' "$file" &>/dev/null
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
        if [[ "$line" =~ ^(⚖️|🎯|💭|📊|↩️|⚠️|💡|🚨|✅|📋|🏁|🔄)[[:space:]].*─+ ]]; then
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
    mkdir -p "$(dirname "$BOXES_FILE")"

    # One-way compatibility migration: if legacy exists and canonical doesn't,
    # and legacy looks like valid JSONL, then copy it.
    if [[ ! -f "$BOXES_FILE" ]] && legacy_store_is_valid_jsonl "$LEGACY_BOXES_FILE"; then
        log "Migrating legacy analytics store to canonical location"
        cp "$LEGACY_BOXES_FILE" "$BOXES_FILE"
    fi

    local input
    input="$(cat 2>/dev/null || echo '{}')"

    local session_id transcript_path cwd reason
    session_id="$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null || echo "")"
    transcript_path="$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")"
    cwd="$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || echo "")"
    reason="$(echo "$input" | jq -r '.reason // ""' 2>/dev/null || echo "")"

    if [[ -z "$session_id" || -z "$transcript_path" ]]; then
        log "Missing session_id or transcript_path in input; skipping"
        exit 0
    fi

    local git_remote=""
    local git_branch=""
    if [[ -n "$cwd" ]] && command -v git &>/dev/null; then
        if git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
            git_remote="$(git -C "$cwd" config --get remote.origin.url 2>/dev/null || echo "")"
            git_branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
        fi
    fi

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local content
    content="$(extract_assistant_messages "$transcript_path" 2>/dev/null || echo "")"

    if [[ -z "$content" ]]; then
        log "No assistant messages found in transcript; nothing to process"
        exit 0
    fi

    local count
    count="$(parse_boxes_from_content "$content" "$session_id" "$git_remote" "$git_branch" "$timestamp" | wc -l | tr -d ' ')"

    log "Emitted $count BoxCreated events for session $session_id (reason: $reason)"
}

main "$@"
