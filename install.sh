#!/usr/bin/env bash
#
# Agent Response Boxes - Installer v5.0
#
# A metacognitive annotation system for AI coding agents with
# cross-session learning capabilities.
#
# QUICK INSTALL (user-level):
#   curl -sSL https://raw.githubusercontent.com/AIntelligentTech/agent-response-boxes/main/install.sh | bash
#
# PROJECT-LEVEL INSTALL:
#   curl -sSL https://raw.githubusercontent.com/AIntelligentTech/agent-response-boxes/main/install.sh | bash -s -- --project
#
# OPTIONS:
#   --user               Install to ~/.claude/ (DEFAULT)
#   --project            Install to ./.claude/ (current project only)
#   --uninstall          Remove installed components
#   --dry-run, -n        Print actions without modifying files
#   --force, -f          Overwrite modified files managed by this installer
#   --cleanup-legacy     Remove legacy v3 artifacts (script/index) if present
#   --install-opencode   Also install OpenCode plugin (response-boxes) to ~/.config/opencode/plugin
#   --help, -h           Show this help
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

PRIMARY_RAW_URL="https://raw.githubusercontent.com/AIntelligentTech/agent-response-boxes/main"
# Back-compat while the repo is being renamed on GitHub.
LEGACY_RAW_URL="https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main"
RAW_URL="${PRIMARY_RAW_URL}"
VERSION="0.8.0"

USER_CLAUDE_DIR="${HOME}/.claude"
PROJECT_CLAUDE_DIR="./.claude"

USER_OPENCODE_PLUGIN_DIR="${HOME}/.config/opencode/plugin"

INSTALL_SCOPE="user"
CLAUDE_DIR="${USER_CLAUDE_DIR}"
UNINSTALL=false
DRY_RUN=false
FORCE=false
CLEANUP_LEGACY=false
INSTALL_OPENCODE_PLUGIN=false
INSTALL_MODE="full"
INSTALL_WINDSURF_BASIC=false
INSTALL_WINDSURF_FULL=false
INSTALL_CURSOR_BASIC=false
INSTALL_CURSOR_ENHANCED=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────

log()   { echo -e "${GREEN}✓${NC} $*"; }

cleanup_legacy_user() {
    if [[ "$INSTALL_SCOPE" != "user" ]]; then
        return 0
    fi

    local legacy_files=(
        "${USER_CLAUDE_DIR}/scripts/analyze-boxes.sh"
        "${USER_CLAUDE_DIR}/analytics/box-index.json"
    )

    local did_any=false
    for f in "${legacy_files[@]}"; do
        if [[ -f "$f" ]]; then
            did_any=true
            if [[ "$DRY_RUN" == "true" ]]; then
                info "Would remove legacy file: $f"
            else
                backup_if_exists "$f"
                rm "$f"
                log "Removed legacy file: $f"
            fi
        fi
    done

    if [[ "$did_any" == "false" ]]; then
        info "No legacy v3 artifacts found"
    fi
}
info()  { echo -e "${BLUE}ℹ${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✖${NC} $*" >&2; }

header() {
    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}        Agent Response Boxes v${VERSION}${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Argument Parsing
# ─────────────────────────────────────────────────────────────────────────────

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --user)      INSTALL_SCOPE="user"; CLAUDE_DIR="${USER_CLAUDE_DIR}"; shift ;;
            --project)   INSTALL_SCOPE="project"; CLAUDE_DIR="${PROJECT_CLAUDE_DIR}"; shift ;;
            --uninstall) UNINSTALL=true; shift ;;
            --dry-run|-n) DRY_RUN=true; shift ;;
            --force|-f)   FORCE=true; shift ;;
            --cleanup-legacy) CLEANUP_LEGACY=true; shift ;;
            --basic)     INSTALL_MODE="basic"; shift ;;
            --install-opencode) INSTALL_OPENCODE_PLUGIN=true; shift ;;
            --install-windsurf-basic) INSTALL_WINDSURF_BASIC=true; shift ;;
            --install-windsurf) INSTALL_WINDSURF_FULL=true; shift ;;
            --install-cursor-basic) INSTALL_CURSOR_BASIC=true; shift ;;
            --install-cursor) INSTALL_CURSOR_ENHANCED=true; shift ;;
            --help|-h)   show_help; exit 0 ;;
            *)           warn "Unknown option: $1"; shift ;;
        esac
    done
}

show_help() {
    cat <<'EOF'
Agent Response Boxes - Installer

USAGE:
  curl -sSL https://raw.githubusercontent.com/AIntelligentTech/agent-response-boxes/main/install.sh | bash
  curl -sSL https://raw.githubusercontent.com/AIntelligentTech/agent-response-boxes/main/install.sh | bash -s -- --project

OPTIONS:
  --user             Install to ~/.claude/ (DEFAULT)
  --project          Install to ./.claude/ (current project only)
  --uninstall        Remove installed components
  --dry-run, -n      Print actions without modifying files
  --force, -f        Overwrite modified files managed by this installer
  --cleanup-legacy   Remove legacy v3 artifacts (script/index) if present
  --basic            Install prompt-only mode (no hooks/analytics/skills/plugins)
  --install-opencode Also install the OpenCode response-boxes plugin (user-level)
  --install-windsurf-basic
                     Install Response Boxes basic-mode rule for Windsurf
  --install-windsurf Install Response Boxes full mode for Windsurf (hooks + workflow)
  --install-cursor-basic
                     Install Response Boxes basic-mode rule for Cursor (project-level)
  --install-cursor   Install Response Boxes enhanced mode for Cursor (hooks + skill)
  --help, -h         Show this help
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

detect_source() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
    if [[ -n "$script_dir" ]] && is_local_source_dir "$script_dir"; then
        SOURCE="local"
        SOURCE_DIR="$script_dir"
        return 0
    fi

    if is_local_source_dir "$(pwd)"; then
        SOURCE="local"
        SOURCE_DIR="$(pwd)"
        return 0
    fi

    SOURCE="remote"
    SOURCE_DIR=""
}

is_local_source_dir() {
    local dir="$1"
    # Preferred (build-time) layout: committed outputs/ tree.
    local outputs_base="${dir}/outputs/claude/.claude"
    if [[ -f "${outputs_base}/output-styles/response-box.md" ]] \
        && [[ -f "${outputs_base}/hooks/inject-context.sh" ]] \
        && [[ -f "${outputs_base}/hooks/session-processor.sh" ]] \
        && [[ -f "${outputs_base}/skills/analyze-boxes/SKILL.md" ]]; then
        return 0
    fi

    # Source layout: agents/ tree with progressive disclosure.
    local base="${dir}/agents/claude-code"
    [[ -f "${base}/output-styles/response-box.md" ]] || return 1
    [[ -f "${base}/rules/core/response-boxes.md" ]] || return 1
    [[ -f "${base}/references/response-boxes.md" ]] || return 1
    [[ -f "${base}/hooks/inject-context.sh" ]] || return 1
    [[ -f "${base}/hooks/session-processor.sh" ]] || return 1
    [[ -f "${base}/skills/analyze-boxes/SKILL.md" ]] || return 1
    return 0
}

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] $*"
        return 0
    fi
    "$@"
}

file_looks_managed() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return 1
    fi

    case "$(basename "$file")" in
        response-box.md)
            grep -q "^# Response Box System" "$file" 2>/dev/null && return 0
            ;;
        response-boxes.md)
            grep -q "^# Response Box System" "$file" 2>/dev/null && return 0
            ;;
        inject-context.sh)
            grep -q "inject-context\.sh - SessionStart hook" "$file" 2>/dev/null && return 0
            ;;
        session-processor.sh)
            grep -q "session-processor\.sh - SessionEnd hook" "$file" 2>/dev/null && return 0
            ;;
        SKILL.md)
            grep -q "^name: analyze-boxes$" "$file" 2>/dev/null && return 0
            ;;
    esac

    grep -q "agent-response-boxes" "$file" 2>/dev/null && return 0
    grep -q "claude-response-boxes" "$file" 2>/dev/null && return 0
    grep -q "Claude Response Boxes" "$file" 2>/dev/null && return 0

    return 1
}

fetch_to_temp() {
    local src="$1"
    local tmp
    tmp="$(mktemp)"

    if [[ "${SOURCE}" == "local" ]]; then
        cp "${SOURCE_DIR}/${src}" "$tmp"
    else
        # Prefer the new repo name, but fall back during transition.
        if ! curl -fsSL "${PRIMARY_RAW_URL}/${src}" -o "$tmp"; then
            curl -fsSL "${LEGACY_RAW_URL}/${src}" -o "$tmp"
        fi
    fi

    echo "$tmp"
}

install_managed_file() {
    local src="$1"
    local dst="$2"
    local mode="${3:-}"

    run_cmd mkdir -p "$(dirname "$dst")"

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ ! -f "$dst" ]]; then
            info "Would install: $dst"
            return 0
        fi

        local tmp
        tmp="$(fetch_to_temp "$src")"
        if cmp -s "$tmp" "$dst"; then
            rm -f "$tmp"
            info "Up-to-date: $dst"
            return 0
        fi

        rm -f "$tmp"
        if file_looks_managed "$dst"; then
            info "Would update: $dst"
        else
            if [[ "$FORCE" == "true" ]]; then
                warn "Would overwrite (forced): $dst"
            else
                warn "Would skip (not managed; use --force): $dst"
            fi
        fi

        return 0
    fi

    local tmp
    tmp="$(fetch_to_temp "$src")"

    if [[ -f "$dst" ]] && cmp -s "$tmp" "$dst"; then
        rm -f "$tmp"
        info "Up-to-date: $dst"
        return 0
    fi

    if [[ -f "$dst" ]] && [[ "$FORCE" != "true" ]] && ! file_looks_managed "$dst"; then
        rm -f "$tmp"
        warn "Skipping modified file (use --force): $dst"
        return 0
    fi

    if [[ -f "$dst" ]]; then
        backup_if_exists "$dst"
    fi

    mv "$tmp" "$dst"
    if [[ -n "$mode" ]]; then
        chmod "$mode" "$dst"
    fi
    log "  → $dst"
}

get_file() {
    local src="$1"
    local dst="$2"

    install_managed_file "$src" "$dst"
}

backup_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d-%H%M%S)"
        run_cmd cp "$file" "$backup"
        info "Backed up: $(basename "$file")"
    fi
}

report_status() {
    echo ""
    info "Existing installation status:"

    if [[ -f "${USER_CLAUDE_DIR}/output-styles/response-box.md" ]]; then
        log "User output style: present"
    else
        warn "User output style: missing"
    fi

    if [[ -f "${USER_CLAUDE_DIR}/hooks/inject-context.sh" ]]; then
        log "User SessionStart hook script: present"
    else
        warn "User SessionStart hook script: missing"
    fi

    if [[ -f "${USER_CLAUDE_DIR}/hooks/session-processor.sh" ]]; then
        log "User SessionEnd hook script: present"
    else
        warn "User SessionEnd hook script: missing"
    fi

    if [[ -f "${USER_CLAUDE_DIR}/skills/analyze-boxes/SKILL.md" ]]; then
        log "User skill (/analyze-boxes): present"
    else
        warn "User skill (/analyze-boxes): missing"
    fi

    if [[ -f "${USER_CLAUDE_DIR}/scripts/analyze-boxes.sh" ]]; then
        warn "Legacy v3 script detected: ~/.claude/scripts/analyze-boxes.sh"
    fi

    if [[ -f "${USER_CLAUDE_DIR}/analytics/box-index.json" ]]; then
        warn "Legacy v3 index detected: ~/.claude/analytics/box-index.json"
    fi

    local canonical_boxes_file="${HOME}/.response-boxes/analytics/boxes.jsonl"
    local legacy_boxes_file="${USER_CLAUDE_DIR}/analytics/boxes.jsonl"

    if [[ -f "$canonical_boxes_file" ]] && [[ -s "$canonical_boxes_file" ]]; then
        if head -c 1 "$canonical_boxes_file" 2>/dev/null | grep -q '^\['; then
            warn "Analytics store is JSON array (expected JSONL): ${canonical_boxes_file}"
        elif check_jq; then
            if jq -s 'length' "$canonical_boxes_file" &>/dev/null; then
                local max_schema
                max_schema=$(jq -s -r '[.[] | (.schema_version // 0)] | max // 0' "$canonical_boxes_file" 2>/dev/null || echo "0")
                if [[ -n "$max_schema" ]] && [[ "$max_schema" != "null" ]] && [[ "$max_schema" -gt 1 ]]; then
                    warn "Analytics schema version ${max_schema} is newer than this installer/hook set supports"
                fi
            else
                warn "Analytics store is not valid JSON lines: ${canonical_boxes_file}"
            fi
        fi
    elif [[ -f "$legacy_boxes_file" ]] && [[ -s "$legacy_boxes_file" ]]; then
        warn "Legacy analytics store detected: ${legacy_boxes_file}"
        info "On next hook run, it will be copied to: ${canonical_boxes_file}"
    fi

    if [[ -f "${USER_CLAUDE_DIR}/settings.json" ]] && check_jq; then
        if jq -e '
            (.hooks | if type == "object" then . else {} end) as $hooks |
            ($hooks.SessionStart // []) as $ss |
            ($ss | if type == "array" then . else [] end) |
            any(.[]?; ((.hooks // []) | if type == "array" then . else [] end) |
                any(.[]?; (.command? // "") | contains("inject-context.sh")))
        ' "${USER_CLAUDE_DIR}/settings.json" &>/dev/null; then
            log "settings.json SessionStart: registered"
        else
            warn "settings.json SessionStart: not registered"
        fi

        if jq -e '
            (.hooks | if type == "object" then . else {} end) as $hooks |
            ($hooks.SessionEnd // []) as $se |
            ($se | if type == "array" then . else [] end) |
            any(.[]?; ((.hooks // []) | if type == "array" then . else [] end) |
                any(.[]?; (.command? // "") | contains("session-processor.sh")))
        ' "${USER_CLAUDE_DIR}/settings.json" &>/dev/null; then
            log "settings.json SessionEnd: registered"
        else
            warn "settings.json SessionEnd: not registered"
        fi
    fi

    if [[ -f "${USER_CLAUDE_DIR}/rules/core/response-boxes.md" ]]; then
        log "User rules (core summary): present"
    fi
    if [[ -f "${USER_CLAUDE_DIR}/references/response-boxes.md" ]]; then
        log "User references (full spec): present"
    fi
    if [[ -f "${PROJECT_CLAUDE_DIR}/rules/core/response-boxes.md" ]]; then
        log "Project rules (core summary): present"
    fi
}

snippet_exists() {
    local file="$1"
    if [[ -f "$file" ]] && grep -Eq '^#{2,6}[[:space:]]+Response Box System([[:space:]].*)?$' "$file"; then
        return 0
    fi
    return 1
}

replace_snippet_block() {
    local claude_md="$1"
    local snippet_file="$2"
    local tmp_out
    tmp_out="$(mktemp)"

    awk -v snip="$snippet_file" '
        function print_snippet_body() {
            # Insert snippet content but preserve the existing CLAUDE.md heading line.
            # Skip snippet front-matter separator and its own heading.
            skip_separator = 1
            while ((getline line < snip) > 0) {
                if (skip_separator == 1 && line ~ /^---[[:space:]]*$/) {
                    continue
                }
                skip_separator = 0
                if (line ~ /^##[[:space:]]+Response Box System([[:space:]].*)?$/) {
                    continue
                }
                print line
            }
            close(snip)
        }
        BEGIN { in_block = 0; replaced = 0 }
        {
            if (in_block == 0 && replaced == 0 && $0 ~ /^#{2,6}[[:space:]]+Response Box System([[:space:]].*)?$/) {
                in_block = 1
                replaced = 1
                # Preserve the existing heading line (may include suffix like (MANDATORY)).
                print $0
                print_snippet_body()
                next
            }

            if (in_block == 1) {
                # Prefer a tight end marker that matches the current snippet template.
                if ($0 ~ /^[[:space:]]*Skip.*boxes for:/) {
                    in_block = 0
                    next
                }

                # Fallback: end the block at the next top-level section.
                if ($0 ~ /^#+[[:space:]]+/ && $0 !~ /^#{2,6}[[:space:]]+Response Box System([[:space:]].*)?$/) {
                    in_block = 0
                } else {
                    next
                }
            }

            print $0
        }
    ' "$claude_md" > "$tmp_out"

    mv "$tmp_out" "$claude_md"
}

check_jq() {
    if ! command -v jq &>/dev/null; then
        warn "jq not found - hooks require jq for JSON processing"
        warn "Install: brew install jq (macOS) or apt install jq (Linux)"
        return 1
    fi
    return 0
}

check_curl() {
    if ! command -v curl &>/dev/null; then
        error "curl not found - required to install from remote source"
        return 1
    fi
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Installation
# ─────────────────────────────────────────────────────────────────────────────

install_output_style() {
    log "Installing output style..."
    install_managed_file "outputs/claude/.claude/output-styles/response-box.md" "${USER_CLAUDE_DIR}/output-styles/response-box.md"
}

install_rules() {
    log "Installing rules..."
    # Compact core summary (always loaded)
    run_cmd mkdir -p "${CLAUDE_DIR}/rules/core"
    install_managed_file "agents/claude-code/rules/core/response-boxes.md" "${CLAUDE_DIR}/rules/core/response-boxes.md"

    # Full spec (loaded on demand via reference pointer)
    run_cmd mkdir -p "${CLAUDE_DIR}/references"
    install_managed_file "agents/claude-code/references/response-boxes.md" "${CLAUDE_DIR}/references/response-boxes.md"
}

install_hooks() {
    log "Installing hooks..."
    install_managed_file "outputs/claude/.claude/hooks/inject-context.sh" "${USER_CLAUDE_DIR}/hooks/inject-context.sh" "+x"

    install_managed_file "outputs/claude/.claude/hooks/session-processor.sh" "${USER_CLAUDE_DIR}/hooks/session-processor.sh" "+x"
}

install_skills() {
    log "Installing skills..."
    install_managed_file "outputs/claude/.claude/skills/analyze-boxes/SKILL.md" "${USER_CLAUDE_DIR}/skills/analyze-boxes/SKILL.md"
}

create_analytics_dir() {
    log "Creating analytics directory..."
    run_cmd mkdir -p "${HOME}/.response-boxes/analytics"
    log "  → ~/.response-boxes/analytics/"
}

register_hooks() {
    local settings_file="${USER_CLAUDE_DIR}/settings.json"

    log "Registering hooks in settings.json..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Would ensure settings.json exists: $settings_file"
        info "Would ensure SessionStart includes: ~/.claude/hooks/inject-context.sh"
        info "Would ensure SessionEnd includes: ~/.claude/hooks/session-processor.sh"
        return 0
    fi

    if [[ ! -f "$settings_file" ]]; then
        echo '{}' > "$settings_file"
    fi

    local start_present
    local end_present
    start_present=$(jq -e '
        (.hooks | if type == "object" then . else {} end) as $hooks |
        ($hooks.SessionStart // []) as $ss |
        ($ss | if type == "array" then . else [] end) |
        any(.[]?; ((.hooks // []) | if type == "array" then . else [] end) |
            any(.[]?; (.command? // "") | contains("inject-context.sh")))
    ' "$settings_file" &>/dev/null && echo "true" || echo "false")

    end_present=$(jq -e '
        (.hooks | if type == "object" then . else {} end) as $hooks |
        ($hooks.SessionEnd // []) as $se |
        ($se | if type == "array" then . else [] end) |
        any(.[]?; ((.hooks // []) | if type == "array" then . else [] end) |
            any(.[]?; (.command? // "") | contains("session-processor.sh")))
    ' "$settings_file" &>/dev/null && echo "true" || echo "false")

    if [[ "$start_present" == "true" ]] && [[ "$end_present" == "true" ]]; then
        info "Hooks already registered"
        return 0
    fi

    backup_if_exists "$settings_file"

    if [[ "$start_present" != "true" ]]; then
        if jq --arg cmd "~/.claude/hooks/inject-context.sh" '
            .hooks = (if (.hooks | type) == "object" then .hooks else {} end) |
            .hooks.SessionStart = (
                if (.hooks.SessionStart | type) == "array" then .hooks.SessionStart
                elif .hooks.SessionStart == null then []
                else []
                end
            ) |
            if (
                .hooks.SessionStart |
                any(.[]?; ((.hooks // []) | if type == "array" then . else [] end) |
                    any(.[]?; (.command? // "") | contains("inject-context.sh")))
            ) then .
            else .hooks.SessionStart += [{"hooks": [{"type": "command", "command": $cmd}]}] end
        ' "$settings_file" > "${settings_file}.tmp"; then
            mv "${settings_file}.tmp" "$settings_file"
            log "  → Added SessionStart hook"
        else
            rm -f "${settings_file}.tmp"
            error "Failed to update settings.json for SessionStart hook"
            return 1
        fi
    fi

    if [[ "$end_present" != "true" ]]; then
        if jq --arg cmd "~/.claude/hooks/session-processor.sh" '
            .hooks = (if (.hooks | type) == "object" then .hooks else {} end) |
            .hooks.SessionEnd = (
                if (.hooks.SessionEnd | type) == "array" then .hooks.SessionEnd
                elif .hooks.SessionEnd == null then []
                else []
                end
            ) |
            if (
                .hooks.SessionEnd |
                any(.[]?; ((.hooks // []) | if type == "array" then . else [] end) |
                    any(.[]?; (.command? // "") | contains("session-processor.sh")))
            ) then .
            else .hooks.SessionEnd += [{"hooks": [{"type": "command", "command": $cmd}]}] end
        ' "$settings_file" > "${settings_file}.tmp"; then
            mv "${settings_file}.tmp" "$settings_file"
            log "  → Added SessionEnd hook"
        else
            rm -f "${settings_file}.tmp"
            error "Failed to update settings.json for SessionEnd hook"
            return 1
        fi
    fi
}

install_claude_md_snippet() {
    local claude_md="${CLAUDE_DIR}/CLAUDE.md"
    local scope_label
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        scope_label="Global"
    else
        scope_label="Project"
    fi

    local snippet_tmp
    snippet_tmp="$(fetch_to_temp "outputs/claude/.claude/config/claude-md-snippet.md")"

    if snippet_exists "$claude_md"; then
        log "Updating Response Box snippet in CLAUDE.md..."
    else
        log "Adding snippet to CLAUDE.md..."
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        if snippet_exists "$claude_md"; then
            info "Would replace snippet block in: $claude_md"
        else
            info "Would append snippet to: $claude_md"
        fi
        rm -f "$snippet_tmp"
        return 0
    fi

    if [[ ! -f "$claude_md" ]]; then
        echo "# ${scope_label} Claude Code Configuration" > "$claude_md"
        echo "" >> "$claude_md"
    else
        backup_if_exists "$claude_md"
    fi

    if snippet_exists "$claude_md"; then
        replace_snippet_block "$claude_md" "$snippet_tmp"
        log "  → Updated snippet in ${claude_md}"
    else
        cat "$snippet_tmp" >> "$claude_md"
        log "  → Added snippet to ${claude_md}"
    fi

    rm -f "$snippet_tmp"
}

install_opencode_plugin() {
    if [[ "$INSTALL_SCOPE" != "user" ]]; then
        info "OpenCode plugin is user-level only; skipping for project scope"
        return 0
    fi

    if [[ "$INSTALL_OPENCODE_PLUGIN" != "true" ]]; then
        return 0
    fi

    log "Installing OpenCode plugin..."
    install_managed_file "outputs/opencode/.opencode/plugins/response-boxes.plugin.ts" "${USER_OPENCODE_PLUGIN_DIR}/response-boxes.plugin.ts"
}

install_windsurf_basic() {
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        # Support both the documented Codeium/Windsurf location and a Codium-based
        # Windsurf Next config root under ~/.codium/.windsurf-next/.
        local global_targets=(
            "${HOME}/.codeium/windsurf/memories/global_rules.md"
            "${HOME}/.codium/.windsurf-next/memories/global_rules.md"
        )

        if [[ "$DRY_RUN" == "true" ]]; then
            for global_rules in "${global_targets[@]}"; do
                if [[ -f "$global_rules" ]]; then
                    info "Would append Response Boxes (basic mode) rule to Windsurf global rules: $global_rules"
                else
                    info "Would create Windsurf global rules file with Response Boxes (basic mode) rule: $global_rules"
                fi
            done
            return 0
        fi

        local tmp_template
        tmp_template="$(fetch_to_temp "outputs/windsurf/.windsurf/rules/response-boxes.md")"

        for global_rules in "${global_targets[@]}"; do
            run_cmd mkdir -p "$(dirname "$global_rules")"

            if [[ -f "$global_rules" ]] && grep -q "Response Boxes (Basic Mode" "$global_rules" 2>/dev/null; then
                info "Windsurf Response Boxes basic-mode rule already present in: $global_rules; skipping"
                continue
            fi

            backup_if_exists "$global_rules"

            {
                if [[ -f "$global_rules" ]]; then
                    cat "$global_rules"
                    echo ""
                    echo ""
                fi

                # Append the body of the template (strip YAML frontmatter if present).
                awk '
                    BEGIN { in_front = 0 }
                    NR == 1 && $0 ~ /^---[[:space:]]*$/ { in_front = 1; next }
                    in_front == 1 {
                        if ($0 ~ /^---[[:space:]]*$/) { in_front = 0; next }
                        next
                    }
                    { print }
                ' "$tmp_template"
            } > "${global_rules}.tmp"

            mv "${global_rules}.tmp" "$global_rules"
            log "  → Installed Windsurf basic-mode rule into ${global_rules}"
        done

        rm -f "$tmp_template"
    else
        # Project-level: install a dedicated rule file under .windsurf/rules/
        local dst=".windsurf/rules/response-boxes.md"
        log "Installing Windsurf basic-mode rule into project: ${dst}"
        install_managed_file "outputs/windsurf/.windsurf/rules/response-boxes.md" "$dst"
    fi
}

install_cursor_basic() {
    local dst=".cursor/rules/response-boxes.mdc"

    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "Cursor basic-mode rules are project-level only; run installer with --project --install-cursor-basic in each repository where you want them."
            return 0
        fi

        warn "Cursor basic-mode rules are project-level only; no user-level rules file will be installed automatically."
        info "Re-run this installer with --project --install-cursor-basic in repositories where you want Cursor Response Boxes rules."
        return 0
    fi

    log "Installing Cursor basic-mode rule into project: ${dst}"
    install_managed_file "outputs/cursor/.cursor/rules/response-boxes.mdc" "$dst"
}

install_cursor_enhanced() {
    if [[ "$INSTALL_SCOPE" != "user" ]]; then
        info "Cursor enhanced mode is user-level only; skipping for project scope"
        return 0
    fi

    log "Installing Cursor enhanced mode (hooks + skill)..."

    # Create directories
    local cursor_hooks_dir="${HOME}/.response-boxes/hooks"
    run_cmd mkdir -p "$cursor_hooks_dir"

    # Install the collector hook script
    install_managed_file "outputs/cursor/.cursor/hooks/cursor-collector.sh" "${cursor_hooks_dir}/cursor-collector.sh" "+x"

    # Cursor hooks.json needs to be in project-level .cursor/hooks/
    # We'll install the template to the response-boxes directory for reference
    install_managed_file "outputs/cursor/.cursor/hooks/hooks.json" "${HOME}/.response-boxes/cursor-hooks.json"

    # Install the skill to user-level (Cursor can read from ~/.cursor/skills/)
    local cursor_skills_dir="${HOME}/.cursor/skills/response-boxes-context"
    run_cmd mkdir -p "$cursor_skills_dir"
    install_managed_file "outputs/cursor/.cursor/skills/response-boxes-context/SKILL.md" "${cursor_skills_dir}/SKILL.md"

    log "Cursor enhanced mode installation complete"
    info "IMPORTANT: Cursor hooks are project-level. Copy ~/.response-boxes/cursor-hooks.json"
    info "          to .cursor/hooks/hooks.json in each project where you want collection."
    info "Run /response-boxes-context in Cursor to see prior learnings."
}

install_windsurf_full() {
    if [[ "$INSTALL_SCOPE" != "user" ]]; then
        info "Windsurf full mode is user-level only; skipping for project scope"
        return 0
    fi

    log "Installing Windsurf full mode (hooks + workflow)..."

    # Create directories
    local windsurf_hooks_dir="${HOME}/.response-boxes/hooks"
    local windsurf_workflow_dir

    # Support both Codeium and Codium Windsurf locations
    local windsurf_config_dirs=(
        "${HOME}/.codeium/windsurf"
        "${HOME}/.codium/.windsurf-next"
    )

    run_cmd mkdir -p "$windsurf_hooks_dir"

    # Install the collector hook script
    install_managed_file "outputs/windsurf/.windsurf/hooks/windsurf-collector.sh" "${windsurf_hooks_dir}/windsurf-collector.sh" "+x"

    # Install hooks.json and workflow to each Windsurf config location that exists
    for config_dir in "${windsurf_config_dirs[@]}"; do
        if [[ -d "$config_dir" ]] || [[ "$DRY_RUN" == "true" ]]; then
            # Install hooks.json
            local hooks_dir="${config_dir}/hooks"
            run_cmd mkdir -p "$hooks_dir"

            if [[ "$DRY_RUN" == "true" ]]; then
                info "Would install Windsurf hooks.json to: ${hooks_dir}/hooks.json"
            else
                # Create hooks.json with correct path
                cat > "${hooks_dir}/hooks.json" << EOF
{
  "hooks": {
    "post_cascade_response": {
      "command": "${windsurf_hooks_dir}/windsurf-collector.sh",
      "description": "Collect response boxes from Cascade responses"
    }
  }
}
EOF
                log "  → Installed hooks.json to ${hooks_dir}/hooks.json"
            fi

            # Install workflow
            windsurf_workflow_dir="${config_dir}/workflows"
            run_cmd mkdir -p "$windsurf_workflow_dir"
            install_managed_file "outputs/windsurf/.windsurf/workflows/response-boxes-start.md" "${windsurf_workflow_dir}/response-boxes-start.md"
        fi
    done

    # Also install the enhanced rules
    install_windsurf_basic

    log "Windsurf full mode installation complete"
    info "Run /response-boxes-start in Windsurf to load prior learnings"
}

# ─────────────────────────────────────────────────────────────────────────────
# Uninstall
# ─────────────────────────────────────────────────────────────────────────────

uninstall() {
    echo ""
    echo -e "${BOLD}Uninstalling Agent Response Boxes...${NC}"
    echo ""

    local files_to_remove=(
        "${CLAUDE_DIR}/rules/core/response-boxes.md"
        "${CLAUDE_DIR}/references/response-boxes.md"
        # Legacy flat files from pre-0.7.0
        "${CLAUDE_DIR}/rules/response-boxes.md"
        "${CLAUDE_DIR}/rules/anti-sycophancy.md"
    )

    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        files_to_remove+=(
            "${USER_CLAUDE_DIR}/output-styles/response-box.md"
            "${USER_CLAUDE_DIR}/hooks/inject-context.sh"
            "${USER_CLAUDE_DIR}/hooks/session-processor.sh"
            "${USER_CLAUDE_DIR}/skills/analyze-boxes/skill.md"
            "${USER_CLAUDE_DIR}/skills/analyze-boxes/SKILL.md"
            "${USER_OPENCODE_PLUGIN_DIR}/response-boxes.plugin.ts"
        )
    fi

    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "Would remove: $file"
            else
                rm "$file"
                log "Removed: $file"
            fi
        fi
    done

    # Remove hooks from settings.json (user-level only)
    local settings_file="${USER_CLAUDE_DIR}/settings.json"
    if [[ "$INSTALL_SCOPE" == "user" ]] && [[ -f "$settings_file" ]] && check_jq; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "Would remove hook registrations from: $settings_file"
        else
            backup_if_exists "$settings_file"

            jq '
                if .hooks.SessionStart then
                    .hooks.SessionStart |= (
                        map(
                            if (.hooks | type) == "array" then
                                .hooks |= map(select(((.command? // "") | contains("inject-context.sh")) | not))
                            else . end
                        ) |
                        map(select((.hooks | type) != "array" or (.hooks | length) > 0))
                    )
                else . end
            ' "$settings_file" > "${settings_file}.tmp" && mv "${settings_file}.tmp" "$settings_file"

            jq '
                if .hooks.SessionEnd then
                    .hooks.SessionEnd |= (
                        map(
                            if (.hooks | type) == "array" then
                                .hooks |= map(select(((.command? // "") | contains("session-processor.sh")) | not))
                            else . end
                        ) |
                        map(select((.hooks | type) != "array" or (.hooks | length) > 0))
                    )
                else . end
            ' "$settings_file" > "${settings_file}.tmp" && mv "${settings_file}.tmp" "$settings_file"

            log "Removed hooks from settings.json"
        fi
    fi

    warn "Note: CLAUDE.md snippet NOT removed"
    info "Manually remove the Response Box System section from CLAUDE.md"

    warn "Note: Analytics data NOT removed"
    info "To remove collected boxes: rm -rf ~/.response-boxes/analytics/"

    echo ""
    log "Uninstall complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    if [[ "$UNINSTALL" == "true" ]]; then
        uninstall
        exit 0
    fi

    header
    detect_source

    if [[ "$SOURCE" == "remote" ]]; then
        check_curl
    fi

    info "Source: ${SOURCE}"
    info "Scope: ${INSTALL_SCOPE}"
    info "Target: ${CLAUDE_DIR}"
    info "Mode:   ${INSTALL_MODE}"
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "Dry-run mode enabled (no files will be modified)"
    fi
    if [[ "$FORCE" == "true" ]]; then
        warn "Force mode enabled (will overwrite managed files)"
    fi
    echo ""

    report_status

    # Check dependencies
    if ! check_jq; then
        warn "Continuing without hook registration..."
        echo ""
    fi

    # Core installation
    install_output_style
    install_rules
    install_claude_md_snippet

    # Optional basic-mode installations for other agents (prompt-only)
    if [[ "$INSTALL_WINDSURF_BASIC" == "true" ]]; then
        echo ""
        info "Installing Windsurf basic-mode integration..."
        install_windsurf_basic
    fi

    if [[ "$INSTALL_CURSOR_BASIC" == "true" ]]; then
        echo ""
        info "Installing Cursor basic-mode integration..."
        install_cursor_basic
    fi

    # Windsurf full mode (hooks + workflow)
    if [[ "$INSTALL_WINDSURF_FULL" == "true" ]]; then
        echo ""
        info "Installing Windsurf full-mode integration..."
        install_windsurf_full
    fi

    # Cursor enhanced mode (hooks + skill)
    if [[ "$INSTALL_CURSOR_ENHANCED" == "true" ]]; then
        echo ""
        info "Installing Cursor enhanced-mode integration..."
        install_cursor_enhanced
    fi

    if [[ "$CLEANUP_LEGACY" == "true" ]]; then
        echo ""
        info "Cleaning up legacy v3 artifacts..."
        cleanup_legacy_user
    fi

    # Hook and analytics installation (user-level only)
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        if [[ "$INSTALL_MODE" == "basic" ]]; then
            echo ""
            info "Basic mode selected: skipping hooks, skills, analytics directory, and OpenCode plugin (prompt-only installation)."
        else
            echo ""
            info "Installing cross-session learning components (full mode)..."
            install_hooks
            install_skills
            create_analytics_dir

            if check_jq; then
                register_hooks
            else
                warn "Skipping hook registration (jq not available)"
                info "Manually add hooks to ~/.claude/settings.json"
            fi

            # Optional: install OpenCode plugin when requested.
            install_opencode_plugin
        fi
    else
        info "Note: Hooks and analytics are user-level only"
    fi

    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}Installation complete!${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo "Installed:"
    echo "  • Output Style: ~/.claude/output-styles/response-box.md"
    echo "  • Rules:        ${CLAUDE_DIR}/rules/core/response-boxes.md (compact)"
    echo "  • References:   ${CLAUDE_DIR}/references/response-boxes.md (full spec)"
    echo "  • CLAUDE.md:    Updated with pre-response checklist"
    if [[ "$INSTALL_SCOPE" == "user" ]] && [[ "$INSTALL_MODE" == "full" ]]; then
        echo "  • Hooks:        ~/.claude/hooks/"
        echo "  • Skills:       ~/.claude/skills/analyze-boxes/"
        echo "  • Analytics:    ~/.response-boxes/analytics/"
    fi
    echo ""
    echo "Activate:"
    echo "  /output-style response-box"
    echo ""
    echo "Or set as default in ~/.claude/settings.json:"
    echo "  { \"outputStyle\": \"response-box\" }"
    echo ""
    if [[ "$INSTALL_SCOPE" == "user" ]] && [[ "$INSTALL_MODE" == "full" ]]; then
        echo "Cross-session learning:"
        echo "  Boxes are automatically collected at session end"
        echo "  High-value learnings are injected at session start"
        echo "  Run analysis in Claude Code: /analyze-boxes"
        echo ""
    fi
}

main "$@"
