# Claude Response Boxes

> A metacognitive annotation system for Claude Code that surfaces hidden
> reasoning and enables continuous learning across sessions.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-4.0.0-green.svg)](https://github.com/AIntelligentTech/claude-response-boxes/releases)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-blueviolet.svg)](https://claude.ai/claude-code)

---

## What Are Response Boxes?

Response boxes are structured annotations that make AI reasoning transparent.
Every significant choice, assumption, and judgment is explicitly documented
using a consistent format.

```text
⚖️ Choice ───────────────────────────────────────
**Selected:** Zod for schema validation
**Alternatives:** Yup, io-ts, manual validation
**Reasoning:** Better TypeScript inference, smaller bundle size
────────────────────────────────────────────────

🏁 Completion ───────────────────────────────────
**Request:** Add input validation to login form
**Completed:** Email + password validation with Zod schema
**Confidence:** 9/10
**Gaps:** No server-side validation added
**Improve:** Should have asked about existing validation patterns
────────────────────────────────────────────────

🪞 Sycophancy ───────────────────────────────────
**Rating:** 10/10
**Check:** Direct technical response, no unnecessary validation
────────────────────────────────────────────────
```

---

## Why Use Response Boxes?

### 1. Transparency

Hidden reasoning leads to misalignment. When Claude chooses between libraries,
makes assumptions about requirements, or decides on an approach, those decisions
are now visible and reviewable.

### 2. Self-Reflection

The completion box forces Claude to reassess its work before finishing. "Did I
actually address the request? What gaps remain? How could I have done better?"

### 3. Cross-Session Learning

High-value boxes (corrected assumptions, validated choices, warnings that proved
right) are collected and injected into future sessions. Claude learns from past
mistakes.

### 4. Anti-Sycophancy

The mandatory sycophancy check at the end of every substantive response forces
explicit evaluation: "Am I providing genuine value or just validating?"

---

## System Architecture

The system operates in three layers:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RESPONSE BOX SYSTEM                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LAYER 1: PROMPT GUIDANCE                                                    │
│  ├── output-styles/response-box.md    Active during sessions                │
│  ├── rules/response-boxes.md          Complete specification                │
│  └── config/claude-md-snippet.md      Minimal CLAUDE.md integration         │
│                                                                              │
│  LAYER 2: DATA PERSISTENCE (Hooks)                                           │
│  ├── SessionStart: inject-context.sh   Load prior learnings                 │
│  └── SessionEnd: session-processor.sh  Collect and emit box events          │
│                                                                              │
│  LAYER 3: ANALYTICS                                                          │
│  └── skills/analyze-boxes/SKILL.md     AI-powered analysis skill            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Metacognition Loop

**Within-session:** At each turn start, Claude reviews prior boxes for
corrections, gaps, or learnings to apply.

**Cross-session:** High-value boxes and synthesized learnings are projected from
the event store and injected as context at the start of new sessions, enabling
Claude to learn from past mistakes.

---

## Box Types

### Inline Boxes (at point of relevance)

| Box           | When                        | Fields                            |
| ------------- | --------------------------- | --------------------------------- |
| ⚖️ Choice     | Selected between 2+ options | Selected, Alternatives, Reasoning |
| 🎯 Decision   | Made a judgment call        | What, Reasoning                   |
| 💭 Assumption | Filled unstated requirement | What, Basis                       |
| ⚠️ Concern    | Potential risk to flag      | Issue, Impact, Mitigation         |
| 🚨 Warning    | Serious risk                | Risk, Likelihood, Consequence     |
| 📊 Confidence | Uncertainty <90%            | Claim, Level (X/10), Basis        |
| ↩️ Pushback   | Disagree with direction     | Position, Reasoning               |
| 💡 Suggestion | Optional improvement        | Idea, Benefit                     |
| 🔄 Reflection | Applied prior learning      | Prior, Learning, Application      |

### End Boxes (max 3, in order)

| Box           | When                     | Fields                                        |
| ------------- | ------------------------ | --------------------------------------------- |
| 📋 Follow Ups | Next steps exist         | Immediate, Consider, Related                  |
| 🏁 Completion | Task being completed     | Request, Completed, Confidence, Gaps, Improve |
| ✅ Quality    | Code was written         | Rating (X/10), Justification                  |
| 🪞 Sycophancy | **Always** (substantive) | Rating (X/10), Check                          |

---

## Installation

### Quick Install (User-Level)

```bash
curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash
```

This installs:

- Output style and rules
- SessionStart/SessionEnd hooks for cross-session learning
- Analysis skill (`/analyze-boxes`)
- CLAUDE.md snippet with pre-response checklist

### Project-Level Install

```bash
curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash -s -- --project
```

Installs rules to project `.claude/` directory only. Hooks, skills, and
analytics remain user-level.

### Installer Options

```bash
# Preview changes without modifying files
curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash -s -- --dry-run

# Overwrite managed files
curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash -s -- --force

# Remove legacy v3 artifacts (if present)
curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash -s -- --cleanup-legacy
```

### Installer Coverage

- **Detection**: Reports what is already installed (user-level and project-level)
- **Safety**: Backs up files before modifying them
- **Scope-aware**: `--project` installs/uninstalls only project rules; hooks/analytics remain user-level
- **Idempotent**: Re-running install is safe; unchanged files are skipped

### Activate

```bash
/output-style response-box
```

Or set as default in `~/.claude/settings.json`:

```json
{
  "outputStyle": "response-box"
}
```

### Dependencies

- **jq** — Required for hooks (JSON processing)
- **bash** — Hooks are bash scripts
- **git** — Optional, for repository context in box metadata

---

## What Gets Installed

### User-Level (`~/.claude/`)

```text
~/.claude/
├── output-styles/
│   └── response-box.md           # Active output style
├── rules/
│   └── response-boxes.md         # Complete specification
├── hooks/
│   ├── inject-context.sh         # SessionStart: load prior boxes
│   └── session-processor.sh      # SessionEnd: collect and emit box events
├── skills/
│   └── analyze-boxes/
│       └── SKILL.md              # /analyze-boxes skill
└── analytics/
    └── boxes.jsonl               # Event store (created on first use)
```

### Project-Level (`.claude/`)

```text
.claude/
├── rules/
│   └── response-boxes.md         # Full specification
└── CLAUDE.md                     # Updated with snippet
```

---

## Cross-Session Learning

### How It Works

1. **Collection** — At session end, `session-processor.sh` parses the transcript
   for response boxes and appends `BoxCreated` events to the event store.

2. **Synthesis** — When you run `/analyze-boxes`, Claude proposes and (with your
   approval) appends learning events (e.g. `LearningCreated`, `EvidenceLinked`).

3. **Injection** — At session start, `inject-context.sh` loads relevant boxes
   and learnings via projection from the event store and injects them as
   context. If new boxes exist since the last analysis run, it also injects a
   one-line reminder to run `/analyze-boxes`.

### Automation vs Manual Steps

- **Automated**
  - SessionEnd collects boxes and appends `BoxCreated` events
  - SessionStart injects projected learnings/boxes and the “unanalyzed” reminder
- **Manual**
  - You run `/analyze-boxes` and approve any changes written to the event store

### Analytics Compatibility

- **Legacy support**: Older `boxes.jsonl` lines missing `.event` are treated as `BoxCreated`.
- **Versioning**: New `BoxCreated` events include `schema_version`.
- **Guardrail**: If the event store contains a newer schema version than the hooks support,
  the hook injects a clear “update required” message instead of producing incorrect context.
- **Recovery**: If the event store becomes corrupted or is not JSONL, the hooks will inject a
  diagnostic message. Back up `~/.claude/analytics/boxes.jsonl` and repair/reset it to restore
  collection/injection.

### Scoring

Boxes are scored by type, prioritizing actionable learnings:

| Tier   | Types                                             | Score |
| ------ | ------------------------------------------------- | ----- |
| High   | Reflection, Warning, Pushback, Assumption         | 80-90 |
| Medium | Choice, Completion, Concern, Confidence, Decision | 55-70 |
| Low    | Sycophancy, Suggestion, Quality, FollowUps        | 35-50 |

### What Gets Injected

At session start, you may see:

```text
PRIOR SESSION LEARNINGS (high-value boxes from previous sessions):

- Assumption: Assumed "TypeScript" (USER CORRECTED) [github.com/user/repo]
- Choice: Chose Zod over Yup (USER PREFERRED ALTERNATIVE) [github.com/user/repo]
- Warning: DELETE endpoint has no authentication [github.com/org/api]

Review these before responding. Apply relevant learnings using 🔄 Reflection box.
```

---

## Manual Analysis

Run AI-powered analysis in Claude Code:

```bash
/analyze-boxes
```

This will:

- Identify patterns across recent boxes
- Propose learnings with confidence scoring
- Link evidence (boxes) to learnings
- Append approved events back into the event store

### Manual Gaps / Limitations

- **Analysis is nondeterministic**
  - `/analyze-boxes` is AI-driven pattern recognition. Results can differ across runs.
  - Always review proposed events before approving writes to the event store.
- **Hooks do not auto-run analysis**
  - The SessionStart hook only injects a reminder when new boxes exist.
  - You still run `/analyze-boxes` manually.

---

## Pre-Response Checklist

Before completing any substantive response:

```text
[ ] Selected between alternatives?      → ⚖️ Choice
[ ] Made a judgment call?               → 🎯 Decision
[ ] Filled unstated requirement?        → 💭 Assumption
[ ] Completing a task?                  → 🏁 Completion
[ ] Substantive response?               → 🪞 Sycophancy (always)
```

---

## When to Use Each Box

### Always Required

- 🪞 **Sycophancy** — Every substantive response (>300 chars)
- 🏁 **Completion** — Every task completion

### Use When Applicable

- ⚖️ **Choice** — Actively chose between viable alternatives
- 🎯 **Decision** — Made judgment without comparing options
- 💭 **Assumption** — Filled in unstated requirements
- ⚠️ **Concern** — Identified potential issue

### Use When Needed

- 📊 **Confidence** — Meaningful uncertainty (<90%)
- ↩️ **Pushback** — Genuine disagreement with direction
- 💡 **Suggestion** — Optional improvement not requested
- 🚨 **Warning** — Serious risk requiring attention
- 🔄 **Reflection** — Applying learning from prior turn/session
- ✅ **Quality** — Significant code was written
- 📋 **Follow Ups** — Clear next steps exist

### Skip Boxes For

- Simple confirmations ("Done.")
- Single-action completions under 300 characters
- File reads without analysis

---

## Configuration

### Environment Variables

| Variable               | Default | Description                         |
| ---------------------- | ------- | ----------------------------------- |
| `BOX_INJECT_LEARNINGS` | 3       | Max learnings to inject at start    |
| `BOX_INJECT_BOXES`     | 5       | Max boxes to inject at start        |
| `BOX_INJECT_DISABLED`  | false   | Set to "true" to disable injection  |
| `BOX_RECENCY_DECAY`    | 0.95    | Weekly decay factor                 |

### Settings

Hook registration in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/inject-context.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/session-processor.sh"
          }
        ]
      }
    ]
  }
}
```

---

## Uninstall

```bash
curl -sSL https://raw.githubusercontent.com/AIntelligentTech/claude-response-boxes/main/install.sh | bash -s -- --uninstall
```

This removes:

- Output style and rules files
- Hooks and skills
- Hook registrations from settings.json

Not removed:

- CLAUDE.md snippet (manual removal)
- Analytics data (`~/.claude/analytics/`)

---

## Documentation

- **[Architecture](docs/architecture.md)** — Technical architecture, design
  decisions, and data structures
- **[Rules](rules/response-boxes.md)** — Complete box specifications and usage
  guidelines

---

## Contributing

Contributions welcome. Please see [CONTRIBUTING.md](CONTRIBUTING.md).

1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Open a Pull Request

---

## License

[MIT](LICENSE) — Use freely, attribution appreciated.

---

Made with care by [AIntelligentTech](https://github.com/AIntelligentTech)
