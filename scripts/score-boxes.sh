#!/usr/bin/env bash
#
# score-boxes.sh - Score boxes by importance for prioritization
#
# Calculates importance scores for boxes based on type, context, and recency.
# Used by session-end-analyze.sh for indexing high-value boxes.
#
# USAGE:
#   ./score-boxes.sh [OPTIONS] < boxes.json
#   ./score-boxes.sh [OPTIONS] -f FILE
#
# OPTIONS:
#   -h, --help          Show this help
#   -f, --file FILE     Input file (default: stdin)
#   -w, --weights FILE  Scoring weights file (default: ~/.claude/config/scoring-weights.json)
#   -r, --repo REPO     Current repository (for context scoring)
#   -j, --json          Output as JSON (default)
#   -t, --threshold N   Only output boxes with score >= N
#
# OUTPUT:
#   JSON array of boxes with added 'score' and 'score_breakdown' fields
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

WEIGHTS_FILE="${HOME}/.claude/config/scoring-weights.json"
INPUT_FILE=""
CURRENT_REPO=""
THRESHOLD=0

# Default weights (used if weights file not found)
DEFAULT_WEIGHTS='{
  "base_scores": {
    "Reflection": 90, "Warning": 90, "Pushback": 85, "Assumption": 80,
    "Choice": 70, "Completion": 70, "Concern": 65, "Confidence": 60,
    "Decision": 55, "Sycophancy": 50, "Suggestion": 45, "Quality": 40, "FollowUps": 35
  },
  "context_multipliers": {
    "same_repository": 1.5, "last_7_days": 1.3, "last_30_days": 1.1
  },
  "recency_decay": {"half_life_days": 90, "min_multiplier": 0.5}
}'

# ─────────────────────────────────────────────────────────────────────────────
# Argument Parsing
# ─────────────────────────────────────────────────────────────────────────────

show_help() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//' | head -20
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)      show_help ;;
            -f|--file)      INPUT_FILE="$2"; shift 2 ;;
            -w|--weights)   WEIGHTS_FILE="$2"; shift 2 ;;
            -r|--repo)      CURRENT_REPO="$2"; shift 2 ;;
            -t|--threshold) THRESHOLD="$2"; shift 2 ;;
            *)              echo "Unknown option: $1"; exit 1 ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Scoring Functions
# ─────────────────────────────────────────────────────────────────────────────

load_weights() {
    if [[ -f "$WEIGHTS_FILE" ]]; then
        cat "$WEIGHTS_FILE"
    else
        echo "$DEFAULT_WEIGHTS"
    fi
}

score_boxes() {
    local boxes="$1"
    local weights="$2"
    local current_repo="$3"
    local threshold="$4"
    local now
    now=$(date +%s)

    # Use jq to score each box
    echo "$boxes" | jq --argjson weights "$weights" \
                       --arg current_repo "$current_repo" \
                       --argjson now "$now" \
                       --argjson threshold "$threshold" '
        # Helper function to normalize timestamp (handle +00:00 and Z formats)
        def normalize_ts($ts):
            $ts | gsub("\\+00:00$"; "Z") | gsub("\\+[0-9][0-9]:[0-9][0-9]$"; "Z");

        # Helper function to calculate days since timestamp
        def days_since($ts):
            (($now - (normalize_ts($ts) | fromdateiso8601)) / 86400) | floor;

        # Helper function to calculate recency decay
        def recency_decay($days):
            $weights.recency_decay as $rd |
            if $rd.half_life_days > 0 then
                [1.0 - ($days / $rd.half_life_days) * 0.5, $rd.min_multiplier] | max
            else
                1.0
            end;

        # Score a single box
        def score_box:
            . as $box |
            ($box.type // "Unknown") as $type |
            ($weights.base_scores[$type] // 40) as $base |

            # Calculate type-specific bonuses
            (
                if $type == "Assumption" and ($box.fields.corrected // false) then 30
                elif $type == "Sycophancy" and (($box.fields.rating | tonumber? // 10) < 7) then 40
                elif $type == "Completion" and ($box.fields.gaps // "" | length > 0) then 20
                elif $type == "Quality" and (($box.fields.rating | tonumber? // 10) < 7) then 20
                else 0
                end
            ) as $type_bonus |

            # Calculate context multipliers
            (
                (if ($box.context.git_remote // "") == $current_repo and $current_repo != "" then 1.5 else 1.0 end) *
                (
                    days_since($box.ts) as $days |
                    if $days <= 7 then 1.3
                    elif $days <= 30 then 1.1
                    else 1.0
                    end
                )
            ) as $context_mult |

            # Calculate recency decay
            (days_since($box.ts) | recency_decay(.)) as $decay |

            # Final score
            (($base + $type_bonus) * $context_mult * $decay | round) as $final_score |

            $box + {
                score: $final_score,
                score_breakdown: {
                    base: $base,
                    type_bonus: $type_bonus,
                    context_multiplier: ($context_mult | . * 100 | round / 100),
                    recency_decay: ($decay | . * 100 | round / 100),
                    days_old: days_since($box.ts)
                }
            };

        # Process all boxes
        if type == "array" then
            map(score_box) | map(select(.score >= $threshold)) | sort_by(-.score)
        else
            [score_box] | map(select(.score >= $threshold))
        end
    '
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not installed" >&2
        exit 1
    fi

    parse_args "$@"

    # Load input
    local boxes
    if [[ -n "$INPUT_FILE" ]]; then
        if [[ ! -f "$INPUT_FILE" ]]; then
            echo "Error: Input file not found: $INPUT_FILE" >&2
            exit 1
        fi
        boxes=$(cat "$INPUT_FILE")
    elif [[ ! -t 0 ]]; then
        boxes=$(cat)
    else
        echo "Error: No input provided" >&2
        echo "Usage: echo '[...]' | $0 or $0 -f FILE" >&2
        exit 1
    fi

    # Load weights
    local weights
    weights=$(load_weights)

    # Score boxes
    score_boxes "$boxes" "$weights" "$CURRENT_REPO" "$THRESHOLD"
}

main "$@"
