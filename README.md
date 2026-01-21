# Claude Response Boxes

> A metacognitive annotation system for Claude Code — structured transparency
> into AI reasoning, decisions, and self-assessment with **active enforcement**.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.1.0-green.svg)](https://github.com/AIntelligentTech/claude-response-boxes/releases)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet.svg)](https://claude.ai/claude-code)

---

## What's New in v2.1

- **User vs Project Installation** — Install system-wide or per-project
- **Centralized Analytics** — All boxes stored at user level with project
  distinction
- **Git-Based Project Identification** — Automatic project tracking via
  `git_remote`

| v2.0                      | v2.1                                 |
| ------------------------- | ------------------------------------ |
| User-level only           | User OR project-level installation   |
| Single installation scope | Flexible scope with shared analytics |
| Basic project tracking    | Robust git_remote-based distinction  |

---

## Highlights

- **Enforced Compliance** — Stop hook blocks responses missing required boxes
- **Transparent Reasoning** — See choices, assumptions, decisions inline
- **Anti-Sycophancy** — Built-in self-assessment prevents hollow validation
- **Self-Improvement Loop** — Session-end analysis with headless Claude
- **Cross-Session Learning** — High-value boxes injected at session start
- **Cross-Project Analytics** — Centralized storage with project distinction
- **Box Scoring** — Prioritize important learnings automatically
- **Zero Config** — One-line install, works immediately

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           RESPONSE BOX LIFECYCLE v2.1                               │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│  SESSION START                                                                      │
│  ┌───────────────────────────────────────────────────────────────────────────────┐ │
│  │  inject-context.sh loads high-value prior boxes from box-index.json           │ │
│  │  Prioritizes boxes from current repository (same git_remote)                  │ │
│  └───────────────────────────────────────────────────────────────────────────────┘ │
│                                       │                                             │
│                                       ▼                                             │
│  DURING SESSION                                                                     │
│  ┌───────────────────────────────────────────────────────────────────────────────┐ │
│  │  1. CLAUDE.md pre-response checklist guides box usage                         │ │
│  │  2. enforce-reminder.sh injects reminders every 3rd tool call                 │ │
│  │  3. collect-boxes.sh parses responses → boxes.jsonl (with git_remote)         │ │
│  └───────────────────────────────────────────────────────────────────────────────┘ │
│                                       │                                             │
│                                       ▼                                             │
│  STOP (before completion)                                                           │
│  ┌───────────────────────────────────────────────────────────────────────────────┐ │
│  │  validate-response.sh:                                                        │ │
│  │  • Substantive response (>300 chars)? Check for 🪞 Sycophancy box            │ │
│  │  • No reasoning patterns AND no inline boxes? BLOCK with feedback            │ │
│  │  • Missing required elements? Exit code 2 → Claude must fix                  │ │
│  └───────────────────────────────────────────────────────────────────────────────┘ │
│                                       │                                             │
│                                       ▼                                             │
│  SESSION END                                                                        │
│  ┌───────────────────────────────────────────────────────────────────────────────┐ │
│  │  session-end-analyze.sh:                                                      │ │
│  │  • Score boxes by importance (type, context, recency)                        │ │
│  │  • Update box-index.json with high-value boxes (score ≥60)                   │ │
│  │  • Optional: Run headless Claude for deep pattern analysis                   │ │
│  └───────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Install

**User-level (recommended, applies to all projects):**

```bash
curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash
```

**Project-level (applies to current project only):**

```bash
curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash -s -- --project
```

Or clone and install locally:

```bash
git clone https://github.com/AIntelligentTech/claude-response-boxes.git
cd claude-response-boxes
./install.sh [--user|--project]
```

**Requirements:** `jq` (for analytics and hook configuration), `bash 4+`

---

## Installation Scopes

The system supports two installation scopes:

| Scope       | Target Directory | Applies To                 | Use Case                   |
| ----------- | ---------------- | -------------------------- | -------------------------- |
| **User**    | `~/.claude/`     | All projects (system-wide) | Personal development setup |
| **Project** | `./.claude/`     | Current project only       | Team-shared project config |

### What Goes Where

| Component     | User Install | Project Install | Why                                   |
| ------------- | ------------ | --------------- | ------------------------------------- |
| Rules         | `~/.claude/` | `./.claude/`    | Scope-specific enforcement            |
| Hooks         | `~/.claude/` | `./.claude/`    | Scope-specific hooks                  |
| Scripts       | `~/.claude/` | `~/.claude/`    | Always user-level (shared utilities)  |
| Config        | `~/.claude/` | `~/.claude/`    | Always user-level (shared settings)   |
| **Analytics** | `~/.claude/` | `~/.claude/`    | **Always user-level** (cross-project) |

### Project Distinction in Analytics

Box records are **always** stored at `~/.claude/analytics/boxes.jsonl`
regardless of installation scope. Project distinction is maintained via the
`git_remote` field in each record:

```json
{
  "ts": "2026-01-21T12:00:00Z",
  "type": "Choice",
  "fields": { "selected": "Option A", "alternatives": "Option B" },
  "context": {
    "git_remote": "github.com/org/my-project",
    "git_branch": "main",
    "session_id": "abc123"
  }
}
```

This enables:

- Cross-project learning (patterns apply across all your work)
- Project-specific filtering (`analyze-boxes.sh -r github.com/org/my-project`)
- Same-repo prioritization in session-start injection

---

## Installation Options

```bash
./install.sh              # User-level (default, recommended)
./install.sh --user       # Explicit user-level
./install.sh --project    # Project-level (current directory)
./install.sh --no-hooks   # Rules only (no enforcement)
./install.sh --hooks-only # Hooks only (skip rules)
./install.sh --uninstall  # Remove components
```

---

## What It Does

After installation, Claude Code responses are ENFORCED to include structured
boxes:

```
⚖️ Choice ───────────────────────────────────────
**Selected:** Haiku model
**Alternatives:** Sonnet, Opus
**Reasoning:** Cost-effective for analysis-only task
────────────────────────────────────────────────
```

**If you forget a required box, the Stop hook blocks completion:**

```
═══════════════════════════════════════════════════════════════
  RESPONSE VALIDATION FAILED
═══════════════════════════════════════════════════════════════

Missing required elements:
  ✗ 🪞 Sycophancy box (required for all substantive responses)

Add the missing elements before completing your response.
═══════════════════════════════════════════════════════════════
```

---

## Box Types

### Inline Boxes (at point of relevance)

| Emoji | Type       | When to Use                      |
| ----- | ---------- | -------------------------------- |
| ⚖️    | Choice     | Selected between 2+ alternatives |
| 🎯    | Decision   | Made a judgment call             |
| 💭    | Assumption | Filled unstated requirement      |
| 🔄    | Reflection | Applied learning from prior box  |
| 📊    | Confidence | Claim with uncertainty (<90%)    |
| ↩️    | Pushback   | Disagrees with user direction    |
| ⚠️    | Concern    | Potential risk to flag           |
| 💡    | Suggestion | Optional improvement             |
| 🚨    | Warning    | Serious risk requiring attention |

### End-of-Response Boxes (max 3, in order)

| Emoji | Type       | When to Use                          |
| ----- | ---------- | ------------------------------------ |
| 📋    | Follow Ups | Next steps exist for user            |
| 🏁    | Completion | Task being completed (forces review) |
| ✅    | Quality    | Code was written                     |
| 🪞    | Sycophancy | **Always** (substantive responses)   |

---

## Box Scoring System

Boxes are scored by importance for prioritization and context injection:

| Box Type      | Base Score | High-Value Triggers            |
| ------------- | ---------- | ------------------------------ |
| 🔄 Reflection | 90         | References a correction        |
| 🚨 Warning    | 90         | Always high (safety)           |
| ↩️ Pushback   | 85         | Shows healthy challenge        |
| 💭 Assumption | 80         | User corrected it (+30)        |
| ⚖️ Choice     | 70         | User chose differently (+25)   |
| 🏁 Completion | 70         | Has gaps or improvements (+20) |

**Context multipliers:** Same repo (1.5x), Last 7 days (1.3x), Part of
correction sequence (1.6x)

Customize weights in `~/.claude/config/scoring-weights.json`.

---

## Self-Improvement Loop

### Session-End Analysis

When Claude Code stops, `session-end-analyze.sh` automatically:

1. Extracts boxes from the session
2. Scores each by importance
3. Updates `box-index.json` with high-value boxes
4. Optionally runs headless Claude for deep analysis

**Enable deep analysis:**

```bash
export BOX_DEEP_ANALYSIS=true
```

### Session-Start Injection

When a new session starts, `inject-context.sh`:

1. Loads high-value boxes from the index
2. **Prioritizes boxes from the same repository** (1.5x relevance boost)
3. Injects them as context (e.g., prior assumptions, corrections)

**Disable injection:**

```bash
export BOX_INJECT_DISABLED=true
```

---

## Analytics

### Manual Analysis

```bash
# Full analysis (all projects)
~/.claude/scripts/analyze-boxes.sh

# Last 7 days
~/.claude/scripts/analyze-boxes.sh -d 7

# Specific project (by git remote)
~/.claude/scripts/analyze-boxes.sh -r github.com/org/repo

# JSON output
~/.claude/scripts/analyze-boxes.sh -j | jq .
```

### Backfill Unscored Boxes

```bash
~/.claude/scripts/session-end-analyze.sh --all
```

### Key Metrics

| Metric                  | Insight                                  |
| ----------------------- | ---------------------------------------- |
| Confidence distribution | Consistently uncertain or overconfident? |
| Assumption frequency    | What gets assumed most often?            |
| Pushback rate           | Is Claude challenging appropriately?     |
| Sycophancy scores       | Tracking anti-sycophancy compliance      |
| Completion confidence   | Task reassessment quality                |
| Boxes by repository     | Which projects generate most learnings?  |

---

## File Structure

### User-Level Installation (default)

```
~/.claude/
├── rules/
│   └── response-boxes.md          # Full specification with enforcement
├── hooks/
│   ├── collect-boxes.sh           # Parse responses → boxes.jsonl
│   ├── validate-response.sh       # Stop hook validation
│   ├── enforce-reminder.sh        # PostToolUse reminder injection
│   └── inject-context.sh          # SessionStart context injection
├── scripts/
│   ├── analyze-boxes.sh           # Interactive analysis
│   ├── score-boxes.sh             # Score boxes by importance
│   └── session-end-analyze.sh     # Session-end analysis + indexing
├── config/
│   ├── scoring-weights.json       # Customizable scoring weights
│   └── claude-md-snippet.md       # CLAUDE.md snippet reference
├── analytics/                     # ALWAYS at user level
│   ├── boxes.jsonl                # Raw box storage (all projects)
│   ├── box-index.json             # High-value box index
│   └── session-analyses.jsonl     # Deep analysis results
└── CLAUDE.md                      # Global instructions
```

### Project-Level Installation

```
./.claude/                         # Project-specific
├── rules/
│   └── response-boxes.md          # Project rules
├── hooks/
│   ├── collect-boxes.sh           # Project hooks
│   ├── validate-response.sh
│   ├── enforce-reminder.sh
│   └── inject-context.sh
├── settings.json                  # Project hook configuration
└── CLAUDE.md                      # Project instructions

~/.claude/                         # Shared (user-level)
├── scripts/                       # Shared utilities
├── config/                        # Shared configuration
└── analytics/                     # Centralized storage (all projects)
    └── boxes.jsonl                # Contains git_remote for distinction
```

---

## Configuration

### Environment Variables

| Variable                | Default                           | Description                        |
| ----------------------- | --------------------------------- | ---------------------------------- |
| `BOX_ANALYTICS_FILE`    | `~/.claude/analytics/boxes.jsonl` | Override storage location          |
| `BOX_VALIDATION_STRICT` | `false`                           | Require reasoning in all responses |
| `BOX_DEEP_ANALYSIS`     | `false`                           | Enable headless Claude analysis    |
| `BOX_INJECT_DISABLED`   | `false`                           | Disable session-start injection    |
| `BOX_INJECT_COUNT`      | `5`                               | Number of boxes to inject          |
| `PROJECT_ID`            | (auto-detected)                   | Override project identifier        |

### Manual Hook Configuration

If auto-configuration fails, add to your settings.json:

**User-level (`~/.claude/settings.json`):**

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/validate-response.sh",
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
            "command": "~/.claude/hooks/enforce-reminder.sh",
            "timeout": 2
          }
        ]
      }
    ]
  }
}
```

**Project-level (`./.claude/settings.json`):**

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/validate-response.sh",
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
            "command": "./.claude/hooks/enforce-reminder.sh",
            "timeout": 2
          }
        ]
      }
    ]
  }
}
```

---

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md).

**Quick start:**

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-box`)
3. Commit changes (`git commit -m 'Add amazing box type'`)
4. Push to branch (`git push origin feature/amazing-box`)
5. Open a Pull Request

---

## License

[MIT](LICENSE) — Use freely, attribution appreciated.

---

## Acknowledgments

- Inspired by structured thinking frameworks and metacognitive research
- Built for use with [Claude Code](https://claude.ai/claude-code) by Anthropic

---

<p align="center">
  <sub>Made with care by <a href="https://github.com/AIntelligentTech">AIntelligentTech</a></sub>
</p>
