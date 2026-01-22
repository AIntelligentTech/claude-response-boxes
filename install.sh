#!/usr/bin/env bash
#
# Claude Response Boxes - Installer v4.0
#
# A metacognitive annotation system for Claude Code responses with
# cross-session learning capabilities.
#
# QUICK INSTALL (user-level):
#   curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash
#
# PROJECT-LEVEL INSTALL:
#   curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash -s -- --project
#
# OPTIONS:
#   --user           Install to ~/.claude/ (DEFAULT)
#   --project        Install to ./.claude/ (current project only)
#   --uninstall      Remove installed components
#   --dry-run, -n    Print actions without modifying files
#   --force, -f      Overwrite modified files managed by this installer
#   --cleanup-legacy Remove legacy v3 artifacts (script/index) if present
#   --help, -h       Show this help
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

RAW_URL="https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main"
VERSION="4.0.0"

USER_CLAUDE_DIR="${HOME}/.claude"
PROJECT_CLAUDE_DIR="./.claude"

INSTALL_SCOPE="user"
CLAUDE_DIR="${USER_CLAUDE_DIR}"
UNINSTALL=false
DRY_RUN=false
FORCE=false
CLEANUP_LEGACY=false

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
    echo -e "${BOLD}        Claude Response Boxes v${VERSION}${NC}"
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
            --help|-h)   show_help; exit 0 ;;
            *)           warn "Unknown option: $1"; shift ;;
        esac
    done
}

show_help() {
    cat <<'EOF'
Claude Response Boxes - Installer

USAGE:
  curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash
  curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash -s -- --project

OPTIONS:
  --user         Install to ~/.claude/ (DEFAULT)
  --project      Install to ./.claude/ (current project only)
  --uninstall    Remove installed components
  --dry-run, -n  Print actions without modifying files
  --force, -f    Overwrite modified files managed by this installer
  --cleanup-legacy  Remove legacy v3 artifacts (script/index) if present
  --help, -h     Show this help
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
    [[ -f "${dir}/output-styles/response-box.md" ]] || return 1
    [[ -f "${dir}/rules/response-boxes.md" ]] || return 1
    [[ -f "${dir}/hooks/inject-context.sh" ]] || return 1
    [[ -f "${dir}/hooks/session-processor.sh" ]] || return 1
    [[ -f "${dir}/skills/analyze-boxes/SKILL.md" ]] || return 1
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
        curl -fsSL "${RAW_URL}/${src}" -o "$tmp"
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

    local boxes_file="${USER_CLAUDE_DIR}/analytics/boxes.jsonl"
    if [[ -f "$boxes_file" ]] && [[ -s "$boxes_file" ]]; then
        if head -c 1 "$boxes_file" 2>/dev/null | grep -q '^\['; then
            warn "Analytics store is JSON array (expected JSONL): ~/.claude/analytics/boxes.jsonl"
        elif check_jq; then
            if jq -s 'length' "$boxes_file" &>/dev/null; then
                local max_schema
                max_schema=$(jq -s -r '[.[] | (.schema_version // 0)] | max // 0' "$boxes_file" 2>/dev/null || echo "0")
                if [[ -n "$max_schema" ]] && [[ "$max_schema" != "null" ]] && [[ "$max_schema" -gt 1 ]]; then
                    warn "Analytics schema version ${max_schema} is newer than this installer/hook set supports"
                fi
            else
                warn "Analytics store is not valid JSON lines: ~/.claude/analytics/boxes.jsonl"
            fi
        fi
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

    if [[ -f "${USER_CLAUDE_DIR}/rules/response-boxes.md" ]]; then
        log "User rules: present"
    fi
    if [[ -f "${PROJECT_CLAUDE_DIR}/rules/response-boxes.md" ]]; then
        log "Project rules: present"
    fi
}

snippet_exists() {
    local file="$1"
    if [[ -f "$file" ]] && grep -q "Response Box System" "$file"; then
        return 0
    fi
    return 1
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
    install_managed_file "output-styles/response-box.md" "${USER_CLAUDE_DIR}/output-styles/response-box.md"
}

install_rules() {
    log "Installing rules..."
    install_managed_file "rules/response-boxes.md" "${CLAUDE_DIR}/rules/response-boxes.md"
}

install_hooks() {
    log "Installing hooks..."
    install_managed_file "hooks/inject-context.sh" "${USER_CLAUDE_DIR}/hooks/inject-context.sh" "+x"

    install_managed_file "hooks/session-processor.sh" "${USER_CLAUDE_DIR}/hooks/session-processor.sh" "+x"
}

install_skills() {
    log "Installing skills..."
    install_managed_file "skills/analyze-boxes/SKILL.md" "${USER_CLAUDE_DIR}/skills/analyze-boxes/SKILL.md"
}

create_analytics_dir() {
    log "Creating analytics directory..."
    run_cmd mkdir -p "${USER_CLAUDE_DIR}/analytics"
    log "  → ~/.claude/analytics/"
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

    if snippet_exists "$claude_md"; then
        info "Response Box snippet already in CLAUDE.md, skipping..."
        return
    fi

    log "Adding snippet to CLAUDE.md..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Would update: $claude_md"
        return 0
    fi

    if [[ ! -f "$claude_md" ]]; then
        echo "# ${scope_label} Claude Code Configuration" > "$claude_md"
        echo "" >> "$claude_md"
    else
        backup_if_exists "$claude_md"
    fi

    if [[ "${SOURCE}" == "local" ]]; then
        cat "${SOURCE_DIR}/config/claude-md-snippet.md" >> "$claude_md"
    else
        curl -fsSL "${RAW_URL}/config/claude-md-snippet.md" >> "$claude_md"
    fi

    log "  → Added snippet to ${claude_md}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Uninstall
# ─────────────────────────────────────────────────────────────────────────────

uninstall() {
    echo ""
    echo -e "${BOLD}Uninstalling Claude Response Boxes...${NC}"
    echo ""

    local files_to_remove=(
        "${CLAUDE_DIR}/rules/response-boxes.md"
    )

    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        files_to_remove+=(
            "${USER_CLAUDE_DIR}/output-styles/response-box.md"
            "${USER_CLAUDE_DIR}/hooks/inject-context.sh"
            "${USER_CLAUDE_DIR}/hooks/session-processor.sh"
            "${USER_CLAUDE_DIR}/skills/analyze-boxes/skill.md"
            "${USER_CLAUDE_DIR}/skills/analyze-boxes/SKILL.md"
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
    info "To remove collected boxes: rm -rf ~/.claude/analytics/"

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

    if [[ "$CLEANUP_LEGACY" == "true" ]]; then
        echo ""
        info "Cleaning up legacy v3 artifacts..."
        cleanup_legacy_user
    fi

    # Hook and analytics installation (user-level only)
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        echo ""
        info "Installing cross-session learning components..."
        install_hooks
        install_skills
        create_analytics_dir

        if check_jq; then
            register_hooks
        else
            warn "Skipping hook registration (jq not available)"
            info "Manually add hooks to ~/.claude/settings.json"
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
    echo "  • Rules:        ${CLAUDE_DIR}/rules/response-boxes.md"
    echo "  • CLAUDE.md:    Updated with pre-response checklist"
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        echo "  • Hooks:        ~/.claude/hooks/"
        echo "  • Skills:       ~/.claude/skills/analyze-boxes/"
        echo "  • Analytics:    ~/.claude/analytics/"
    fi
    echo ""
    echo "Activate:"
    echo "  /output-style response-box"
    echo ""
    echo "Or set as default in ~/.claude/settings.json:"
    echo "  { \"outputStyle\": \"response-box\" }"
    echo ""
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        echo "Cross-session learning:"
        echo "  Boxes are automatically collected at session end"
        echo "  High-value learnings are injected at session start"
        echo "  Run analysis in Claude Code: /analyze-boxes"
        echo ""
    fi
}

main "$@"
