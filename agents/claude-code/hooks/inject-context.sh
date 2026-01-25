#!/usr/bin/env bash
#
# inject-context.sh - SessionStart hook for cross-session learning
#
# Projects learnings and high-value boxes from the event store and
# injects them as context for the new session.
#
# HOOK TYPE: SessionStart
#
# INPUT (stdin JSON):
#   {
#     "session_id": "abc123",
#     "cwd": "/path/to/project",
#     "source": "startup|resume|clear|compact"
#   }
#
# OUTPUT (stdout JSON):
#   {
#     "hookSpecificOutput": {
#       "additionalContext": "PRIOR SESSION LEARNINGS:\n..."
#     }
#   }
#
# EXIT CODES:
#   0 - Always (context injection is optional, never blocks)
#
# ENVIRONMENT:
#   BOX_INJECT_LEARNINGS - Number of learnings to inject (default: 3)
#   BOX_INJECT_BOXES     - Number of boxes to inject (default: 5)
#   BOX_INJECT_DISABLED  - Set to "true" to disable injection
#   BOX_RECENCY_DECAY    - Weekly decay factor (default: 0.95)
#
# EVENT STORE:
#   ~/.response-boxes/analytics/boxes.jsonl - Append-only event log
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

SUPPORTED_SCHEMA_VERSION=1

INJECT_LEARNINGS="${BOX_INJECT_LEARNINGS:-3}"
INJECT_BOXES="${BOX_INJECT_BOXES:-5}"
RECENCY_DECAY="${BOX_RECENCY_DECAY:-0.95}"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

log() {
    echo "[inject-context] $*" >&2
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

output_context() {
    local context="$1"
    jq -n --arg ctx "$context" '{
        "hookSpecificOutput": {
            "additionalContext": $ctx
        }
    }'
}

output_empty() {
    echo '{}'
}

# ─────────────────────────────────────────────────────────────────────────────
# Projection Functions
# ─────────────────────────────────────────────────────────────────────────────

# Project learnings from events, applying updates
project_learnings() {
    local current_repo="$1"
    local now_epoch="$2"
    local decay="$3"

    jq -s --arg repo "$current_repo" --argjson now "$now_epoch" --argjson decay "$decay" '
        def normalize_box:
            if ((.event // "") == "") then
                {
                    event: "BoxCreated",
                    id: (if ((.context.session_id // "") != "") and ((.context.turn_number // null) != null) then
                            ("sess_" + (.context.session_id | tostring) + "_" + (.context.turn_number | tostring))
                         else
                            ("legacy_" + (((.ts // "") + "_" + (.type // .box_type // "Unknown")) | gsub("[^A-Za-z0-9_]+"; "_")))
                         end),
                    ts: (.ts // "1970-01-01T00:00:00Z"),
                    box_type: (.box_type // .type // "Unknown"),
                    fields: (.fields // {}),
                    context: (.context // {}),
                    initial_score: (.initial_score // 50),
                    schema_version: (.schema_version // 0)
                }
            else
                . + {
                    box_type: (.box_type // .type // "Unknown"),
                    fields: (.fields // {}),
                    context: (.context // {}),
                    initial_score: (.initial_score // 50),
                    schema_version: (.schema_version // 1)
                }
            end;

        # Collect all events by type
        (map(select(.event == "LearningCreated"))) as $created |
        (map(select(.event == "LearningUpdated"))) as $updates |
        (map(select(.event == "EvidenceLinked"))) as $evidence |
        (map(select((.event // "BoxCreated") == "BoxCreated")) |
         map(normalize_box) |
         map({key: .id, value: (.context.git_remote // "")}) |
         from_entries) as $box_repo_by_id |

        # Process each LearningCreated
        $created | map(. as $learning |
            # Apply all updates in order
            ($updates | map(select(.learning_id == $learning.id)) | sort_by(.ts) |
             reduce .[] as $u ($learning; . + $u.updates)) as $updated |

            # Collect evidence
            ($evidence | map(select(.learning_id == $learning.id)) |
             map({box_id, strength, relationship})) as $ev |

            # Calculate evidence factor
            ($ev | if length > 0 then
                (map(
                    .strength * (
                        if .relationship == "supports" then 1.0
                        elif .relationship == "tangential" then 0.3
                        elif .relationship == "contradicts" then -0.5
                        else 0
                        end
                    )
                ) | add / length)
            else 0.5 end) as $evidence_factor |

            # Calculate recency factor (weeks since creation)
            (($now - (($updated.ts // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+"; "") | fromdateiso8601)) / 604800) as $weeks |
            (pow($decay; $weeks)) as $recency_factor |

            # Effective confidence
            (($updated.confidence // 0.5) * (0.5 + $evidence_factor * 0.5) * $recency_factor) as $effective |

            # Repo relevance boost
            ((if ($updated.scope // "") == "repo" and ($repo != "") and ($ev | any($box_repo_by_id[.box_id] == $repo)) then 1.5 else 1.0 end)) as $repo_boost |

            $updated + {
                evidence_count: ($ev | length),
                effective_confidence: $effective,
                relevance_score: ($effective * $repo_boost)
            }
        ) |

        # Sort by level (meta-learnings first) then relevance
        sort_by([-(.level // 0), -(.relevance_score // 0)])
    ' "$BOXES_FILE" 2>/dev/null || echo '[]'
}

# Project boxes from events, applying enrichments
# Note: Sycophancy boxes are filtered out as anti-sycophancy is now an internal protocol
project_boxes() {
    local current_repo="$1"
    local now_epoch="$2"
    local decay="$3"
    local min_score="${4:-60}"

    jq -s --arg repo "$current_repo" --argjson now "$now_epoch" --argjson decay "$decay" --argjson min "$min_score" '
        def normalize_box:
            if ((.event // "") == "") then
                {
                    event: "BoxCreated",
                    id: (if ((.context.session_id // "") != "") and ((.context.turn_number // null) != null) then
                            ("sess_" + (.context.session_id | tostring) + "_" + (.context.turn_number | tostring))
                         else
                            ("legacy_" + (((.ts // "") + "_" + (.type // .box_type // "Unknown")) | gsub("[^A-Za-z0-9_]+"; "_")))
                         end),
                    ts: (.ts // "1970-01-01T00:00:00Z"),
                    box_type: (.box_type // .type // "Unknown"),
                    fields: (.fields // {}),
                    context: (.context // {}),
                    initial_score: (.initial_score // 50),
                    schema_version: (.schema_version // 0)
                }
            else
                . + {
                    box_type: (.box_type // .type // "Unknown"),
                    fields: (.fields // {}),
                    context: (.context // {}),
                    initial_score: (.initial_score // 50),
                    schema_version: (.schema_version // 1)
                }
            end;

        # Collect events (filter out Sycophancy boxes - anti-sycophancy is now internal)
        (map(select((.event // "BoxCreated") == "BoxCreated")) | map(normalize_box) | map(select(.box_type != "Sycophancy"))) as $boxes |
        (map(select(.event == "BoxEnriched"))) as $enrichments |

        # Process each box
        $boxes | map(. as $box |
            # Apply enrichments
            ($enrichments | map(select(.box_id == $box.id)) | sort_by(.ts) |
             reduce .[] as $e ($box; . + $e.updates)) as $enriched |

            # Get current score (enriched or initial)
            (($enriched.score // $enriched.initial_score // 50)) as $score |

            # Calculate recency factor
            (($now - (($enriched.ts // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+"; "") | fromdateiso8601)) / 604800) as $weeks |
            (pow($decay; $weeks)) as $recency_factor |

            # Effective score with recency
            ($score * $recency_factor) as $effective_score |

            # Repo relevance boost
            ((if $enriched.context.git_remote == $repo and $repo != "" then 1.5 else 1.0 end)) as $repo_boost |

            $enriched + {
                effective_score: $effective_score,
                relevance_score: ($effective_score * $repo_boost),
                age_weeks: $weeks
            }
        ) |

        # Filter by minimum effective score and sort
        map(select(.effective_score >= $min)) |
        sort_by(-.relevance_score)
    ' "$BOXES_FILE" 2>/dev/null || echo '[]'
}

# ─────────────────────────────────────────────────────────────────────────────
# Formatting
# ─────────────────────────────────────────────────────────────────────────────

format_learnings() {
    local learnings="$1"
    local count="$2"

    echo "$learnings" | jq -r --argjson n "$count" '
        .[0:$n] | map("• [" + ((.effective_confidence // 0.0) | tostring) + "] " + (.insight // "") +
            if (.scope // "") == "repo" then " (repo-specific)" else "" end) | .[]
    '
}

format_boxes() {
    local boxes="$1"
    local count="$2"

    echo "$boxes" | jq -r --argjson n "$count" '
        .[0:$n] | map("• " + (.box_type // "Unknown") + ": " + ((.fields.summary // .fields.title // .fields.what // .fields.issue // .fields.idea // .fields.request // "(no summary)") | tostring) +
            (if (.context.git_remote // "") != "" then " [" + (.context.git_remote | tostring) + "]" else "" end) +
            (if (.age_weeks // 0) > 0 then " (" + ((.age_weeks | tonumber) | floor | tostring) + " weeks ago)" else "" end)) | .[]
    '
}

build_context_block() {
    local learnings="$1"
    local boxes="$2"

    {
        echo "## Patterns (from cross-session analysis)"
        echo "$learnings"
        echo ""
        echo "## Recent Notable Boxes"
        echo "$boxes"
    } | sed '/^$/N;/^\n$/D'
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Read hook input
    local input
    input="$(cat 2>/dev/null || echo '{}')"

    # Check for disable flag
    if [[ "${BOX_INJECT_DISABLED:-false}" == "true" ]] || [[ "${RESPONSE_BOXES_DISABLED:-false}" == "true" ]]; then
        log "Injection disabled via environment variable"
        output_empty
        exit 0
    fi

    # Check dependencies
    if ! command -v jq &>/dev/null; then
        log "jq not available, skipping context injection"
        output_empty
        exit 0
    fi

    # Ensure analytics directory exists (for potential legacy migration)
    mkdir -p "$ANALYTICS_DIR"

    # One-way compatibility migration: if legacy exists and canonical doesn't,
    # and legacy looks like valid JSONL, then copy it.
    if [[ ! -f "$BOXES_FILE" ]] && legacy_store_is_valid_jsonl "$LEGACY_BOXES_FILE"; then
        log "Migrating legacy analytics store to canonical location"
        cp "$LEGACY_BOXES_FILE" "$BOXES_FILE"
    fi

    if [[ ! -f "$BOXES_FILE" ]] || [[ ! -s "$BOXES_FILE" ]]; then
        log "No analytics store found at $BOXES_FILE (or file is empty)"
        output_empty
        exit 0
    fi

    local cwd
    cwd="$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || echo "")"

    local git_remote=""
    if [[ -n "$cwd" ]] && command -v git &>/dev/null; then
        if git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
            git_remote="$(git -C "$cwd" config --get remote.origin.url 2>/dev/null || echo "")"
        fi
    fi

    local now_epoch
    now_epoch="$(date +%s)"

    local learnings
    learnings="$(project_learnings "$git_remote" "$now_epoch" "$RECENCY_DECAY")"

    local boxes
    boxes="$(project_boxes "$git_remote" "$now_epoch" "$RECENCY_DECAY" 60)"

    if [[ -z "$learnings" || "$learnings" == "[]" ]] && [[ -z "$boxes" || "$boxes" == "[]" ]]; then
        log "No relevant learnings or boxes to inject"
        output_empty
        exit 0
    fi

    local learnings_text
    learnings_text="$(format_learnings "$learnings" "$INJECT_LEARNINGS")"

    local boxes_text
    boxes_text="$(format_boxes "$boxes" "$INJECT_BOXES")"

    local context_block
    context_block="$(build_context_block "$learnings_text" "$boxes_text")"

    output_context "$context_block"
}

main "$@"
