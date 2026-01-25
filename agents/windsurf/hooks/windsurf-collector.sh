#!/usr/bin/env bash
#
# windsurf-collector.sh - Post-cascade response hook for Windsurf
#
# Captures response boxes from Cascade responses and emits BoxCreated events
# to the shared event store at ~/.response-boxes/analytics/boxes.jsonl
#
# Input: JSON via stdin with trajectory_id, execution_id, and response content
#
# Environment variables:
#   RESPONSE_BOXES_FILE     Override default boxes file location
#   RESPONSE_BOXES_DISABLED Set to "true" to disable collection
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

DEFAULT_BOXES_FILE="${HOME}/.response-boxes/analytics/boxes.jsonl"
BOXES_FILE="${RESPONSE_BOXES_FILE:-$DEFAULT_BOXES_FILE}"
SCHEMA_VERSION=1

# ─────────────────────────────────────────────────────────────────────────────
# Early exit checks
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${RESPONSE_BOXES_DISABLED:-false}" == "true" ]]; then
    exit 0
fi

if ! command -v jq &>/dev/null; then
    # jq is required for JSON parsing
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Read input from stdin
# ─────────────────────────────────────────────────────────────────────────────

input="$(cat)"

if [[ -z "$input" ]]; then
    exit 0
fi

# Extract response text and metadata from Windsurf hook payload
response_text="$(echo "$input" | jq -r '.tool_info.response // .response // ""' 2>/dev/null || echo "")"
trajectory_id="$(echo "$input" | jq -r '.trajectory_id // ""' 2>/dev/null || echo "")"
execution_id="$(echo "$input" | jq -r '.execution_id // ""' 2>/dev/null || echo "")"

if [[ -z "$response_text" ]]; then
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Box extraction
# ─────────────────────────────────────────────────────────────────────────────

# Extract boxes from response text using pattern matching
# Matches: emoji + BoxType + dashes (at least 10)
extract_boxes() {
    local text="$1"
    local boxes=()

    # Use awk to extract box blocks
    echo "$text" | awk '
        BEGIN { in_box = 0; box_type = ""; box_content = "" }

        # Match box header: emoji + type + dashes
        /^.+[[:space:]]+[A-Za-z][A-Za-z ]*[[:space:]]+[-─]{10,}/ {
            if (in_box && box_type != "") {
                # Output previous box
                print box_type "\t" box_content
            }
            # Extract box type (second word after emoji)
            match($0, /[A-Za-z][A-Za-z ]*/)
            box_type = substr($0, RSTART, RLENGTH)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", box_type)
            box_content = ""
            in_box = 1
            next
        }

        # Match box footer (just dashes)
        /^[-─]{40,}$/ {
            if (in_box && box_type != "") {
                print box_type "\t" box_content
                box_type = ""
                box_content = ""
                in_box = 0
            }
            next
        }

        # Accumulate content if in a box
        in_box {
            if (box_content != "") box_content = box_content "\\n"
            box_content = box_content $0
        }

        END {
            if (in_box && box_type != "") {
                print box_type "\t" box_content
            }
        }
    '
}

# Parse field values from box content
parse_fields() {
    local content="$1"
    echo "$content" | grep -oE '\*\*[^*]+\*\*:[^*]+' | while read -r field; do
        key=$(echo "$field" | sed -E 's/\*\*([^*]+)\*\*:.*/\1/' | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
        value=$(echo "$field" | sed -E 's/\*\*[^*]+\*\*:[[:space:]]*//')
        echo "\"$key\":\"$value\""
    done | paste -sd, -
}

# Calculate initial score based on box type
calculate_score() {
    local box_type="$1"
    case "$box_type" in
        Reflection|Warning|Pushback|Assumption)
            echo 85
            ;;
        Choice|Completion|Concern|Confidence|Decision)
            echo 60
            ;;
        Suggestion|Quality|"Follow Ups"|FollowUps)
            echo 40
            ;;
        *)
            echo 50
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Process boxes and emit events
# ─────────────────────────────────────────────────────────────────────────────

# Ensure analytics directory exists
mkdir -p "$(dirname "$BOXES_FILE")"

# Generate session ID
session_id="${trajectory_id:-ws_$(date +%s)}"
now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Extract and process boxes
box_index=0
while IFS=$'\t' read -r box_type box_content; do
    if [[ -z "$box_type" ]]; then
        continue
    fi

    # Parse fields from content
    fields_json=$(parse_fields "$box_content")
    if [[ -z "$fields_json" ]]; then
        fields_json="{}"
    else
        fields_json="{$fields_json}"
    fi

    # Calculate score
    score=$(calculate_score "$box_type")

    # Generate unique ID
    box_id="ws_${session_id}_${EPOCHSECONDS:-$(date +%s)}_${box_index}"

    # Build context
    context_json=$(jq -n \
        --arg source "windsurf_hook" \
        --arg session_id "$session_id" \
        --arg trajectory_id "$trajectory_id" \
        --arg execution_id "$execution_id" \
        --arg agent "Windsurf" \
        '{
            source: $source,
            session_id: $session_id,
            trajectory_id: $trajectory_id,
            execution_id: $execution_id,
            agent: $agent
        }')

    # Emit BoxCreated event
    event_json=$(jq -n \
        --arg event "BoxCreated" \
        --arg id "$box_id" \
        --arg ts "$now_iso" \
        --arg box_type "$box_type" \
        --argjson fields "$fields_json" \
        --argjson context "$context_json" \
        --argjson score "$score" \
        --argjson schema_version "$SCHEMA_VERSION" \
        '{
            event: $event,
            id: $id,
            ts: $ts,
            box_type: $box_type,
            fields: $fields,
            context: $context,
            initial_score: $score,
            schema_version: $schema_version
        }')

    echo "$event_json" >> "$BOXES_FILE"

    box_index=$((box_index + 1))
done < <(extract_boxes "$response_text")

exit 0
