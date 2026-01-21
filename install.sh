#!/usr/bin/env bash
#
# Claude Response Boxes - Installer v2.1
#
# A metacognitive annotation system for Claude Code responses with
# active enforcement via hooks.
#
# QUICK INSTALL (user-level, recommended):
#   curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash
#
# PROJECT-LEVEL INSTALL:
#   curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash -s -- --project
#
# MANUAL INSTALL:
#   git clone https://github.com/AIntelligentTech/claude-response-boxes.git
#   cd claude-response-boxes && ./install.sh [--user|--project]
#
# INSTALLATION SCOPES:
#   --user      Install to ~/.claude/ (DEFAULT, applies to all projects)
#   --project   Install to ./.claude/ (applies to current project only)
#
# OPTIONS:
#   --no-hooks      Skip hook configuration (rules only)
#   --hooks-only    Only configure hooks (skip rules/scripts)
#   --uninstall     Remove installed components
#   --help          Show this help
#
# ANALYTICS STORAGE:
#   Box records are ALWAYS stored at ~/.claude/analytics/boxes.jsonl regardless
#   of installation scope. This enables cross-project learning while maintaining
#   project distinction via the git_remote field in each record.
#
# WHAT THIS DOES:
#   1. Copies rules to <target>/rules/
#   2. Copies hooks to <target>/hooks/
#   3. Copies scripts to ~/.claude/scripts/ (always user-level)
#   4. Copies config to ~/.claude/config/ (always user-level)
#   5. Creates ~/.claude/analytics/ for box tracking (always user-level)
#   6. Adds snippet to <target>/CLAUDE.md (with backup)
#   7. Configures hooks in <target>/settings.json
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

REPO_URL="https://github.com/AIntelligentTech/claude-response-boxes"
RAW_URL="https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main"
VERSION="2.1.0"

# Installation targets
USER_CLAUDE_DIR="${HOME}/.claude"
PROJECT_CLAUDE_DIR="./.claude"

# Default to user-level installation
INSTALL_SCOPE="user"
CLAUDE_DIR="${USER_CLAUDE_DIR}"

# Installation options
INSTALL_HOOKS=true
INSTALL_RULES=true
UNINSTALL=false

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
info()  { echo -e "${BLUE}ℹ${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✖${NC} $*" >&2; }

header() {
    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}        Claude Response Boxes - Installation v${VERSION}${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Argument Parsing
# ─────────────────────────────────────────────────────────────────────────────

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --user)        INSTALL_SCOPE="user"; CLAUDE_DIR="${USER_CLAUDE_DIR}"; shift ;;
            --project)     INSTALL_SCOPE="project"; CLAUDE_DIR="${PROJECT_CLAUDE_DIR}"; shift ;;
            --no-hooks)    INSTALL_HOOKS=false; shift ;;
            --hooks-only)  INSTALL_RULES=false; shift ;;
            --uninstall)   UNINSTALL=true; shift ;;
            --help|-h)     show_help; exit 0 ;;
            *)             warn "Unknown option: $1"; shift ;;
        esac
    done
}

show_help() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//' | head -45
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Detect if running from curl pipe or local clone
detect_source() {
    if [[ -f "./rules/response-boxes.md" ]]; then
        SOURCE="local"
        SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    else
        SOURCE="remote"
        SOURCE_DIR=""
    fi
}

# Download file from remote or copy from local
get_file() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"

    if [[ "${SOURCE}" == "local" ]]; then
        cp "${SOURCE_DIR}/${src}" "$dst"
    else
        curl -sSL "${RAW_URL}/${src}" -o "$dst"
    fi
}

# Backup file if it exists
backup_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$file" "$backup"
        info "Backed up: $(basename "$file")"
    fi
}

# Check if snippet already exists in CLAUDE.md
snippet_exists() {
    local file="$1"
    if [[ -f "$file" ]] && grep -q "PRE-RESPONSE CHECKLIST" "$file"; then
        return 0
    fi
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Installation Steps
# ─────────────────────────────────────────────────────────────────────────────

install_rules() {
    log "Installing rules to ${CLAUDE_DIR}/rules/..."
    mkdir -p "${CLAUDE_DIR}/rules"
    get_file "rules/response-boxes.md" "${CLAUDE_DIR}/rules/response-boxes.md"
    log "  → ${CLAUDE_DIR}/rules/response-boxes.md"
}

install_hooks() {
    log "Installing hooks to ${CLAUDE_DIR}/hooks/..."
    mkdir -p "${CLAUDE_DIR}/hooks"

    local hooks=(
        "collect-boxes.sh"
        "validate-response.sh"
        "enforce-reminder.sh"
        "inject-context.sh"
    )

    for hook in "${hooks[@]}"; do
        get_file "hooks/${hook}" "${CLAUDE_DIR}/hooks/${hook}"
        chmod +x "${CLAUDE_DIR}/hooks/${hook}"
        log "  → ${CLAUDE_DIR}/hooks/${hook}"
    done
}

install_scripts() {
    # Scripts are ALWAYS installed at user level for cross-project use
    log "Installing scripts to ${USER_CLAUDE_DIR}/scripts/ (user-level)..."
    mkdir -p "${USER_CLAUDE_DIR}/scripts"

    local scripts=(
        "analyze-boxes.sh"
        "score-boxes.sh"
        "session-end-analyze.sh"
    )

    for script in "${scripts[@]}"; do
        get_file "scripts/${script}" "${USER_CLAUDE_DIR}/scripts/${script}"
        chmod +x "${USER_CLAUDE_DIR}/scripts/${script}"
        log "  → ${USER_CLAUDE_DIR}/scripts/${script}"
    done
}

install_config() {
    # Config is ALWAYS installed at user level
    log "Installing configuration to ${USER_CLAUDE_DIR}/config/ (user-level)..."
    mkdir -p "${USER_CLAUDE_DIR}/config"

    get_file "config/scoring-weights.json" "${USER_CLAUDE_DIR}/config/scoring-weights.json"
    log "  → ${USER_CLAUDE_DIR}/config/scoring-weights.json"

    # Also copy claude-md-snippet.md for reference
    get_file "config/claude-md-snippet.md" "${USER_CLAUDE_DIR}/config/claude-md-snippet.md"
    log "  → ${USER_CLAUDE_DIR}/config/claude-md-snippet.md"
}

install_analytics_dir() {
    # Analytics are ALWAYS stored at user level for cross-project learning
    log "Creating analytics directory at ${USER_CLAUDE_DIR}/analytics/ (user-level)..."
    mkdir -p "${USER_CLAUDE_DIR}/analytics"
    touch "${USER_CLAUDE_DIR}/analytics/.gitkeep"
    log "  → ${USER_CLAUDE_DIR}/analytics/"

    if [[ "$INSTALL_SCOPE" == "project" ]]; then
        info "Box records from this project will be stored at:"
        info "  ${USER_CLAUDE_DIR}/analytics/boxes.jsonl"
        info "Project distinction maintained via git_remote field in each record."
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
        info "Response Box System (v2) already in CLAUDE.md, skipping..."
        return
    fi

    # Check for old v1 snippet and offer to upgrade
    if [[ -f "$claude_md" ]] && grep -q "Response Box System" "$claude_md" && ! grep -q "PRE-RESPONSE CHECKLIST" "$claude_md"; then
        warn "Found v1 Response Box snippet in CLAUDE.md"
        info "Please manually update to v2 format from:"
        info "  ${USER_CLAUDE_DIR}/config/claude-md-snippet.md"
        return
    fi

    log "Adding snippet to CLAUDE.md..."

    # Create CLAUDE.md if it doesn't exist
    if [[ ! -f "$claude_md" ]]; then
        echo "# ${scope_label} Claude Code Configuration" > "$claude_md"
        echo "" >> "$claude_md"
    else
        backup_if_exists "$claude_md"
    fi

    # Append the v2 snippet
    if [[ "${SOURCE}" == "local" ]]; then
        cat "${SOURCE_DIR}/config/claude-md-snippet.md" >> "$claude_md"
    else
        curl -sSL "${RAW_URL}/config/claude-md-snippet.md" >> "$claude_md"
    fi

    log "  → Added v2 snippet to ${claude_md}"
}

configure_hooks() {
    local settings_file="${CLAUDE_DIR}/settings.json"
    local hooks_path

    # Determine hook paths based on installation scope
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        hooks_path="~/.claude/hooks"
    else
        hooks_path="./.claude/hooks"
    fi

    log "Configuring hooks in settings.json..."

    # Create settings.json if it doesn't exist
    if [[ ! -f "$settings_file" ]]; then
        echo '{}' > "$settings_file"
    fi

    backup_if_exists "$settings_file"

    # Add hook configuration using jq
    if command -v jq &>/dev/null; then
        # Note: Scripts are always at user level, hooks depend on scope
        local hook_config
        hook_config=$(cat <<EOF
{
    "hooks": {
        "Stop": [
            {
                "matcher": "",
                "hooks": [
                    {
                        "type": "command",
                        "command": "${hooks_path}/validate-response.sh",
                        "timeout": 5
                    },
                    {
                        "type": "command",
                        "command": "~/.claude/scripts/session-end-analyze.sh -q",
                        "timeout": 30
                    }
                ]
            }
        ],
        "PostToolUse": [
            {
                "matcher": "",
                "hooks": [
                    {
                        "type": "command",
                        "command": "${hooks_path}/enforce-reminder.sh",
                        "timeout": 2
                    }
                ]
            }
        ]
    }
}
EOF
)

        # Merge with existing settings (preserving other configurations)
        local current
        current=$(cat "$settings_file")

        # Check if hooks already exist
        if echo "$current" | jq -e '.hooks.Stop' &>/dev/null; then
            warn "Existing Stop hooks found in settings.json"
            info "Please manually merge hook configuration from:"
            info "  See docs/architecture-v2.md for hook configuration"
        else
            echo "$current" | jq --argjson hooks "$hook_config" '. * $hooks' > "${settings_file}.tmp"
            mv "${settings_file}.tmp" "$settings_file"
            log "  → Hooks configured in ${settings_file}"
        fi
    else
        warn "jq not found - cannot auto-configure hooks"
        info "Please manually add hooks to ${settings_file}"
        info "See docs/architecture-v2.md for configuration"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Uninstall
# ─────────────────────────────────────────────────────────────────────────────

uninstall() {
    echo ""
    echo -e "${BOLD}Uninstalling Claude Response Boxes from ${CLAUDE_DIR}...${NC}"
    echo ""

    local files_to_remove=(
        "${CLAUDE_DIR}/rules/response-boxes.md"
        "${CLAUDE_DIR}/hooks/collect-boxes.sh"
        "${CLAUDE_DIR}/hooks/validate-response.sh"
        "${CLAUDE_DIR}/hooks/enforce-reminder.sh"
        "${CLAUDE_DIR}/hooks/inject-context.sh"
    )

    # Only remove user-level scripts/config if uninstalling from user scope
    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        files_to_remove+=(
            "${USER_CLAUDE_DIR}/scripts/analyze-boxes.sh"
            "${USER_CLAUDE_DIR}/scripts/score-boxes.sh"
            "${USER_CLAUDE_DIR}/scripts/session-end-analyze.sh"
            "${USER_CLAUDE_DIR}/config/scoring-weights.json"
            "${USER_CLAUDE_DIR}/config/claude-md-snippet.md"
        )
    fi

    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm "$file"
            log "Removed: $file"
        fi
    done

    warn "Note: CLAUDE.md snippet and settings.json hooks NOT removed"
    info "Manually remove the Response Box System section from CLAUDE.md"
    info "Manually remove hooks from settings.json"

    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        warn "Note: Analytics data preserved at ${USER_CLAUDE_DIR}/analytics/"
        info "Remove manually if no longer needed: rm -rf ${USER_CLAUDE_DIR}/analytics/"
    fi

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

    info "Source: ${SOURCE}"
    info "Installation scope: ${INSTALL_SCOPE}"
    info "Target directory: ${CLAUDE_DIR}"
    info "Analytics storage: ${USER_CLAUDE_DIR}/analytics/ (always user-level)"
    echo ""

    if [[ "$INSTALL_RULES" == "true" ]]; then
        install_rules
        install_scripts
        install_config
        install_analytics_dir
        install_claude_md_snippet
    fi

    if [[ "$INSTALL_HOOKS" == "true" ]]; then
        install_hooks
        configure_hooks
    fi

    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}Installation complete!${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ "$INSTALL_SCOPE" == "user" ]]; then
        echo "Installed at USER level (applies to all projects):"
        echo "  • Rules:     ~/.claude/rules/response-boxes.md"
        echo "  • Hooks:     ~/.claude/hooks/ (4 enforcement hooks)"
        echo "  • Scripts:   ~/.claude/scripts/ (3 analysis scripts)"
        echo "  • Config:    ~/.claude/config/scoring-weights.json"
        echo "  • Analytics: ~/.claude/analytics/boxes.jsonl"
    else
        echo "Installed at PROJECT level (applies to this project only):"
        echo "  • Rules:     ./.claude/rules/response-boxes.md"
        echo "  • Hooks:     ./.claude/hooks/ (4 enforcement hooks)"
        echo ""
        echo "Shared resources (user-level, all projects):"
        echo "  • Scripts:   ~/.claude/scripts/ (3 analysis scripts)"
        echo "  • Config:    ~/.claude/config/scoring-weights.json"
        echo "  • Analytics: ~/.claude/analytics/boxes.jsonl"
        echo ""
        info "Project distinction maintained via git_remote field in box records."
    fi

    echo ""
    echo "Enforcement active:"
    echo "  • Stop hook validates responses before completion"
    echo "  • PostToolUse hook injects reminders"
    echo "  • Session-end analysis scores and indexes boxes"
    echo ""
    echo "Next steps:"
    echo "  1. Review: less ${CLAUDE_DIR}/rules/response-boxes.md"
    echo "  2. Start a new Claude Code session"
    echo "  3. Boxes are now ENFORCED, not just documented"
    echo ""
    echo "Documentation: ${REPO_URL}"
    echo ""
}

main "$@"
