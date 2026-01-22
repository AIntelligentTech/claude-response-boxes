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
#   ~/.claude/analytics/boxes.jsonl - Append-only event log
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

ANALYTICS_DIR="${HOME}/.claude/analytics"
BOXES_FILE="${ANALYTICS_DIR}/boxes.jsonl"

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

        # Collect events
        (map(select((.event // "BoxCreated") == "BoxCreated")) | map(normalize_box)) as $boxes |
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
        .[0:$n] | map(
            (if .effective_confidence >= 0.8 then "[HIGH]"
             elif .effective_confidence >= 0.6 then "[MEDIUM]"
             else "[LOW]" end) as $level |
            (if .scope == "repo" then " (repo-specific)" else "" end) as $scope |
            (if (.level // 0) > 0 then " [meta-learning]" else "" end) as $meta |

            "• " + $level + " " + .insight + $scope + $meta +
            " (" + ((.effective_confidence * 100) | floor | tostring) + "% confidence, " +
            (.evidence_count | tostring) + " evidence)"
        ) | join("\n")
    '
}

format_boxes() {
    local boxes="$1"
    local count="$2"

    echo "$boxes" | jq -r --argjson n "$count" '
        .[0:$n] | map(
            (if .age_weeks < 1 then "today"
             elif .age_weeks < 2 then "1 week ago"
             else ((.age_weeks | floor | tostring) + " weeks ago")
             end) as $age |

            "• " + .box_type + ": " +
            (if .box_type == "Assumption" then
                "Assumed \"" + (.fields.what // "N/A") + "\""
            elif .box_type == "Choice" then
                "Chose " + (.fields.selected // "N/A") + " over " + (.fields.alternatives // "N/A")
            elif .box_type == "Warning" then
                (.fields.risk // "N/A")
            elif .box_type == "Pushback" then
                "Pushed back on: " + (.fields.position // "N/A")
            elif .box_type == "Reflection" then
                "Applied: " + (.fields.learning // .fields.application // "N/A")
            elif .box_type == "Completion" and .fields.gaps then
                "Gap noted: " + (.fields.gaps // "N/A")
            else
                (.fields | to_entries | .[0:2] | map("\(.key): \(.value)") | join(", "))
            end) +
            " [" + (.context.git_remote // "local") + "] (" + $age + ")"
        ) | join("\n")
    '
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Check if disabled
    if [[ "${BOX_INJECT_DISABLED:-false}" == "true" ]]; then
        output_empty
        exit 0
    fi

    # Check dependencies
    if ! command -v jq &>/dev/null; then
        log "jq not available, skipping context injection"
        output_empty
        exit 0
    fi

    # Check if event store exists
    if [[ ! -f "$BOXES_FILE" ]]; then
        output_empty
        exit 0
    fi

    if ! jq -s 'length' "$BOXES_FILE" &>/dev/null; then
        output_context "PRIOR SESSION LEARNINGS:\n\nAnalytics event store is not valid JSON lines. Back up ~/.claude/analytics/boxes.jsonl and repair or reset to restore cross-session injection."
        exit 0
    fi

    local max_schema_version
    max_schema_version=$(jq -s -r '[.[] | (.schema_version // 0)] | max // 0' "$BOXES_FILE" 2>/dev/null || echo "0")
    if [[ -z "$max_schema_version" ]] || [[ "$max_schema_version" == "null" ]]; then
        max_schema_version=0
    fi
    if [[ "$max_schema_version" -gt "$SUPPORTED_SCHEMA_VERSION" ]]; then
        output_context "PRIOR SESSION LEARNINGS:\n\nAnalytics schema version ${max_schema_version} is newer than this hook supports. Update Claude Response Boxes to restore cross-session injection."
        exit 0
    fi

    # Read input from stdin
    local input
    input=$(cat)

    # Extract current working directory
    local cwd
    cwd=$(echo "$input" | jq -r '.cwd // empty')

    # Get current repository
    local current_repo=""
    if [[ -n "$cwd" ]] && [[ -d "$cwd" ]]; then
        current_repo=$(cd "$cwd" && git remote get-url origin 2>/dev/null | sed -E 's|^(https?://\|git@)||; s|:|/|; s|\.git$||' || echo "")
    fi

    # Get current epoch time
    local now_epoch
    now_epoch=$(date +%s)

    # Check for unanalyzed boxes since last analysis
    local last_analysis_epoch
    last_analysis_epoch=$(jq -s -r '
        def ts_epoch($v):
            ($v // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+"; "") | fromdateiso8601;
        ([.[] | select(.event == "AnalysisCompleted")] | sort_by(.ts)) as $runs |
        if ($runs | length) > 0 then
            ts_epoch($runs[-1].through_ts // $runs[-1].ts)
        else
            ts_epoch("1970-01-01T00:00:00Z")
        end
    ' "$BOXES_FILE" 2>/dev/null || echo "0")
    if [[ -z "$last_analysis_epoch" ]] || [[ "$last_analysis_epoch" == "null" ]]; then
        last_analysis_epoch=0
    fi

    local unanalyzed_count
    unanalyzed_count=$(jq -s --argjson since "$last_analysis_epoch" '
        def ts_epoch($v):
            ($v // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+"; "") | fromdateiso8601;
        [.[] | select(((.event // "BoxCreated") == "BoxCreated") and (ts_epoch(.ts) > $since))] | length
    ' "$BOXES_FILE" 2>/dev/null || echo "0")
    if [[ "$unanalyzed_count" == "null" ]] || [[ -z "$unanalyzed_count" ]]; then
        unanalyzed_count=0
    fi

    # Project learnings
    local learnings
    learnings=$(project_learnings "$current_repo" "$now_epoch" "$RECENCY_DECAY")

    local learning_count
    learning_count=$(echo "$learnings" | jq 'length')

    # Project boxes
    local boxes
    boxes=$(project_boxes "$current_repo" "$now_epoch" "$RECENCY_DECAY" 60)

    local box_count
    box_count=$(echo "$boxes" | jq 'length')

    # Build context if we have data
    if [[ "$learning_count" -eq 0 ]] && [[ "$box_count" -eq 0 ]] && [[ "$unanalyzed_count" -eq 0 ]]; then
        output_empty
        exit 0
    fi

    local context_parts=()

    if [[ "$unanalyzed_count" -gt 0 ]]; then
        context_parts+=("Unanalyzed response boxes detected (${unanalyzed_count}). Run /analyze-boxes to update learnings.")
        context_parts+=("")
    fi

    # Add learnings section if available
    if [[ "$learning_count" -gt 0 ]]; then
        local formatted_learnings
        formatted_learnings=$(format_learnings "$learnings" "$INJECT_LEARNINGS")
        if [[ -n "$formatted_learnings" ]] && [[ "$formatted_learnings" != "null" ]]; then
            context_parts+=("## Patterns (from cross-session analysis)")
            context_parts+=("$formatted_learnings")
            context_parts+=("")
        fi
    fi

    # Add boxes section if available
    if [[ "$box_count" -gt 0 ]]; then
        local formatted_boxes
        formatted_boxes=$(format_boxes "$boxes" "$INJECT_BOXES")
        if [[ -n "$formatted_boxes" ]] && [[ "$formatted_boxes" != "null" ]]; then
            context_parts+=("## Recent Notable Boxes")
            context_parts+=("$formatted_boxes")
            context_parts+=("")
        fi
    fi

    # Assemble final context
    if [[ ${#context_parts[@]} -gt 0 ]]; then
        local context_text
        context_text="PRIOR SESSION LEARNINGS:

$(printf '%s\n' "${context_parts[@]}")
Review and apply using 🔄 Reflection where relevant."

        output_context "$context_text"
        log "Injected $learning_count learnings and $box_count boxes (unanalyzed: $unanalyzed_count)"
    else
        output_empty
    fi

    exit 0
}

main "$@"
