# Cross-Agent Compatibility Guide

**Version:** 1.0.1 **Last Updated:** 2026-01-30 **Status:** Living Document

This document provides comprehensive compatibility information for Response
Boxes across AI coding agents, including capability matrices, implementation
strategies, and integration patterns.

---

## Overview

Response Boxes is designed to work across multiple AI coding agents. Each agent
has different extension mechanisms, which affects what level of functionality is
achievable.

### Support Tiers

| Tier         | Description                                 | Agents                  |
| ------------ | ------------------------------------------- | ----------------------- |
| **Full**     | Automatic collection + injection + analysis | Claude Code, OpenCode   |
| **Enhanced** | Automatic collection + manual injection     | Windsurf                |
| **Basic**    | Automatic collection + manual injection     | Cursor, Aider, Continue |
| **Minimal**  | Prompt-only guidance (no persistence)       | Any LLM via AGENTS.md   |

---

## Agent Capability Matrix

### Core Features

| Feature                     | Claude Code | OpenCode        | Windsurf    | Cursor     |
| --------------------------- | ----------- | --------------- | ----------- | ---------- |
| **Box Taxonomy (12 types)** | ✅ Full     | ✅ Full         | ✅ Full     | ✅ Full    |
| **Output Style**            | ✅ Native   | ⚠️ Instructions | ⚠️ Rules    | ⚠️ Rules   |
| **Automatic Collection**    | ✅ Hook     | ✅ Plugin       | ✅ Hook     | ✅ Hook    |
| **Automatic Injection**     | ✅ Hook     | ✅ Plugin       | ❌ Workflow | ❌ Manual  |
| **Event Store**             | ✅ JSONL    | ✅ Shared       | ✅ Shared   | ✅ Shared  |
| **/analyze-boxes Skill**    | ✅ Native   | ⚠️ Reuse        | ⚠️ Reuse    | ⚠️ Reuse   |
| **Cross-Session Learning**  | ✅ Full     | ✅ Full         | ⚠️ Partial  | ⚠️ Partial |

### Extension Mechanisms

| Mechanism                 | Claude Code          | OpenCode            | Windsurf                 | Cursor                |
| ------------------------- | -------------------- | ------------------- | ------------------------ | --------------------- |
| **SessionStart Hook**     | ✅ Yes               | ✅ Plugin           | ❌ No                    | ❌ No                 |
| **SessionEnd Hook**       | ✅ Yes               | ✅ Plugin           | ❌ No                    | ❌ No                 |
| **Response Capture Hook** | ✅ PostToolUse       | ✅ message.updated  | ✅ post_cascade_response | ✅ afterAgentResponse |
| **Context Injection**     | ✅ additionalContext | ✅ system.transform | ❌ None                  | ❌ None               |
| **Response Modification** | ❌ No                | ❌ No               | ❌ No                    | ❌ No                 |
| **Skills/Commands**       | ✅ Full              | ✅ Full             | ✅ Skills + workflows    | ✅ Skills (2.4+)       |
| **Rules System**          | ✅ .claude/rules     | ✅ AGENTS.md        | ✅ .windsurf/rules       | ✅ .cursor/rules      |

---

## Detailed Agent Profiles

### Claude Code

**Status:** Full Support (Reference Implementation)

**Version Requirements:** Any recent version (hooks introduced in 2024)

**Extension Points:**

- `SessionStart` hook - Injects cross-session context
- `SessionEnd` hook - Collects boxes from transcript
- `.claude/skills/` - Native skill support
- `.claude/rules/` - Behavioral rules
- Output styles - Native format guidance

**Key Files:**

```
agents/claude-code/
├── hooks/
│   ├── inject-context.sh      # SessionStart → projects learnings
│   └── session-processor.sh   # SessionEnd → emits BoxCreated
├── output-styles/
│   └── response-box.md        # Box format specification
├── rules/
│   └── response-boxes.md      # Full 400+ line spec
├── skills/
│   └── analyze-boxes/SKILL.md # AI-powered analysis
└── config/
    └── claude-md-snippet.md   # CLAUDE.md integration
```

**Limitations:** None - full implementation

---

### OpenCode

**Status:** Full Support

**Version Requirements:** v1.1.34+ (January 2026)

**Extension Points:**

- `message.updated` event - Real-time message tracking
- `experimental.chat.system.transform` - System prompt injection (with
  sessionID)
- `chat.headers` - HTTP header modification (stable)
- `.opencode/skills/` - Native skill support
- `AGENTS.md` / `opencode.json` instructions - Static context

**Key Files:**

```
agents/opencode/
├── plugins/
│   └── response-boxes.plugin.ts  # Full plugin implementation
├── skills/
│   └── analyze-boxes/SKILL.md    # Native skill (planned)
└── instructions/
    └── response-boxes.md         # Static output style (planned)
```

**API Stability:**

| API                     | Status       | Notes                     |
| ----------------------- | ------------ | ------------------------- |
| `message.updated`       | Stable       | Primary capture mechanism |
| `chat.system.transform` | Experimental | With sessionID (Jan 2026) |
| `chat.headers`          | Stable       | New Jan 2026              |
| `session.compacting`    | Experimental | Preserve state on compact |

**Implementation Notes:**

- Plugin shares event store with Claude Code at
  `~/.response-boxes/analytics/boxes.jsonl`
- Injection happens once per session via system prompt transform
- Collection happens on every assistant message update
- Skill discovery via AGENTS.md fallback to .claude/skills/

**Limitations:**

- No native output style (must use instructions)
- Relies on experimental API for injection

---

### Windsurf (Cascade)

**Status:** Enhanced Support (Automatic Collection, Manual Injection)

**Version Requirements:** v1.12.41+ (December 2025, Wave 13)

**Extension Points:**

- `post_cascade_response` hook - Captures full model output
- `.windsurf/workflows/` - Slash-command workflows
- `.windsurf/skills/` - Skills (auto-invoked or manually invoked via @skill-name)
- `.windsurf/rules/` - Behavioral rules (12k char limit)
- Memories - NOT programmatically accessible

**Key Files:**

```
agents/windsurf/
├── hooks/
│   └── hooks.json               # Hook configuration (planned)
│   └── windsurf-collector.sh    # Collection script (planned)
├── workflows/
│   └── response-boxes-start.md  # Manual injection workflow (planned)
└── rules/
    └── response-boxes.md        # Basic mode rules (exists)
```

**Hook Data Access:**

| Hook                    | Input Data         | Can Modify?       | Can Return Context? |
| ----------------------- | ------------------ | ----------------- | ------------------- |
| `pre_user_prompt`       | User prompt        | ❌ Exit code only | ❌ No               |
| `post_cascade_response` | Full trajectory    | ❌ No             | ❌ No               |
| `pre_write_code`        | File path, content | ❌ Exit code only | ❌ No               |
| `post_write_code`       | File path, result  | ❌ No             | ❌ No               |

**Implementation Strategy:**

1. **Collection (Automatic)**
   - Use `post_cascade_response` to capture boxes
   - Parse response text for box patterns
   - Emit `BoxCreated` events to shared store

2. **Injection (Manual Workflow)**
   - Create `/response-boxes-start` workflow
   - Workflow reads event store, projects learnings
   - Displays formatted context block
   - User invokes at session start

3. **Static Guidance**
   - Install rules file with box taxonomy
   - Rules provide always-on guidance
   - 6,000 char limit per rule file

**Limitations:**

- No automatic injection (hooks cannot return context)
- Memories not programmable
- Rules have character limits
- User must invoke workflow manually

**Workarounds:**

- Train user habit: always start with `/response-boxes-start`
- Rules provide persistent baseline guidance
- Workflow provides dynamic context on demand

---

### Cursor

**Status:** Basic Support (Automatic Collection, Manual Injection)

**Version Requirements:** v2.4+ for skills (January 2026); hooks exist earlier but skills are the recommended injection surface

**Extension Points:**

- `afterAgentResponse` hook - Observes assistant text
- `afterAgentThought` hook - Observes thinking blocks
- `.cursor/skills/` - Skills (stable in Cursor 2.4+)
- `.cursor/rules/` - Rules (.md, .mdc)

**Key Files:**

```
agents/cursor/
├── hooks/
│   └── hooks.json              # Hook configuration (planned)
│   └── cursor-collector.sh     # Collection script (planned)
├── skills/
│   └── response-boxes-context/ # Manual context skill (planned)
└── rules/
    └── response-boxes.mdc      # Basic mode rules (exists)
```

**Hook Capabilities:**

| Hook                 | Purpose          | Input                   | Output         |
| -------------------- | ---------------- | ----------------------- | -------------- |
| `afterAgentResponse` | Capture response | `{ text: "..." }`       | `{}` (ignored) |
| `afterAgentThought`  | Capture thinking | `{ text, duration_ms }` | `{}` (ignored) |
| `beforeSubmitPrompt` | Observe prompt   | User message            | Partial        |
| `preToolUse`         | Before tool      | Tool details            | Can modify     |
| `postToolUse`        | After tool       | Tool result             | Can modify     |

**Critical Limitation:** Response hooks are observation-only. Unlike tool hooks
which support `updated_input`/`updated_output`, response hooks return empty JSON
with no modification capability.

**No Session Lifecycle Hooks:** Cursor does not provide:

- `sessionStart` / `sessionEnd` events
- Mechanism to inject context at session start
- Way to persist state across sessions via hooks

**Implementation Strategy:**

1. **Collection (Automatic)**
   - Use `afterAgentResponse` to capture responses
   - Parse for box patterns
   - Emit `BoxCreated` events

2. **Injection (Manual Skill)**
   - Create `/response-boxes-context` skill
   - User invokes to see prior learnings
   - Skill displays formatted context block
   - User references in subsequent prompts

3. **Static Guidance**
   - Install `.cursor/rules/response-boxes.mdc`
   - Provides always-on box taxonomy guidance

**Limitations:**

- No automatic injection possible
- No session lifecycle hook equivalent to Claude’s SessionStart injection
- Cannot modify agent context programmatically
- User must manually invoke context skill

---

## Shared Event Store

All agents share a common event store for cross-agent learning:

```
~/.response-boxes/
└── analytics/
    └── boxes.jsonl     # Append-only event log
```

### Event Types

| Event               | Purpose                      | Emitter        |
| ------------------- | ---------------------------- | -------------- |
| `BoxCreated`        | Record a box from a response | All collectors |
| `BoxEnriched`       | Add metadata to a box        | Analysis skill |
| `LearningCreated`   | Synthesize a pattern         | Analysis skill |
| `LearningUpdated`   | Update learning confidence   | Analysis skill |
| `EvidenceLinked`    | Connect box to learning      | Analysis skill |
| `AnalysisCompleted` | Mark analysis run            | Analysis skill |

### Cross-Agent Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Claude Code    │     │    OpenCode     │     │    Windsurf     │
│  (Full Mode)    │     │  (Full Mode)    │     │ (Enhanced Mode) │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │  BoxCreated           │  BoxCreated           │  BoxCreated
         ▼                       ▼                       ▼
    ┌────────────────────────────────────────────────────────┐
    │              ~/.response-boxes/analytics/boxes.jsonl    │
    │                     (Shared Event Store)                │
    └────────────────────────────────────────────────────────┘
         │                       │                       │
         │  Project on           │  Project on           │  Project on
         │  SessionStart         │  SessionStart         │  Workflow
         ▼                       ▼                       ▼
    ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
    │  Auto-inject    │     │  Auto-inject    │     │  Display        │
    │  to context     │     │  to context     │     │  to user        │
    └─────────────────┘     └─────────────────┘     └─────────────────┘
```

---

## Integration with Cross-Agent Compatibility Engine (CACE)

The sibling project `../cross-agent-compatibility-engine` provides tools for
converting Response Boxes components between agents.

### Converting Skills

```bash
# Convert Claude skill to Windsurf workflow
cace convert agents/claude-code/skills/analyze-boxes/SKILL.md --to windsurf

# Convert with loss reporting
cace convert agents/claude-code/skills/analyze-boxes/SKILL.md --to cursor --comments
```

### Capability Mapping

CACE defines mappings for Response Boxes features:

| Source Feature    | Claude | OpenCode | Windsurf  | Cursor   |
| ----------------- | ------ | -------- | --------- | -------- |
| `context: fork`   | ✅     | ❌ Lost  | ❌ Lost   | ❌ Lost  |
| `allowed-tools`   | ✅     | ✅       | ❌ Lost   | ❌ Lost  |
| `$ARGUMENTS`      | ✅     | ✅       | ⚠️ Prose  | ⚠️ Prose |
| `auto-invocation` | ✅     | ✅       | ⚠️ Manual | ❌ Lost  |

### ComponentSpec for Response Boxes

Response Boxes components can be represented in CACE's canonical IR:

```typescript
{
  id: "response-boxes-analyze",
  version: { major: 1, minor: 0, patch: 0 },
  componentType: "skill",
  intent: {
    summary: "AI-powered analysis of response boxes",
    purpose: "Identify patterns, create learnings, link evidence",
    whenToUse: "When boxes have accumulated and need synthesis"
  },
  activation: {
    mode: "manual",
    safetyLevel: "safe"
  },
  invocation: {
    slashCommand: "analyze-boxes",
    userInvocable: true
  },
  execution: {
    context: "main",
    allowedTools: ["Read", "Grep", "Glob", "Bash"]
  },
  capabilities: {
    needsFilesystem: true,
    needsShell: true,
    providesAnalysis: true
  }
}
```

---

## Installation Modes

### Full Mode (Claude Code, OpenCode)

```bash
# Claude Code
./install.sh --agent claude-code --user

# OpenCode
./install.sh --agent opencode --user
```

Installs:

- Hooks/plugins for automatic collection
- Hooks/plugins for automatic injection
- Skills for analysis
- Rules/output styles for guidance
- Event store initialization

### Enhanced Mode (Windsurf)

```bash
./install.sh --agent windsurf --user
```

Installs:

- Hook for automatic collection
- Workflow for manual injection
- Rules for guidance
- Event store initialization

### Basic Mode (Cursor)

```bash
./install.sh --agent cursor --user
```

Installs:

- Hook for automatic collection
- Skill for manual context display
- Rules for guidance
- Event store initialization

### Prompt-Only Mode (Any Agent)

```bash
./install.sh --agent universal --project
```

Installs:

- AGENTS.md with box taxonomy
- No persistence, no hooks
- Within-session guidance only

---

## Troubleshooting

### Common Issues

#### Boxes not being collected

**Symptoms:** `boxes.jsonl` not updating after responses

**Check:**

1. Hook/plugin is installed: `ls ~/.response-boxes/hooks/` or check plugin
   config
2. Hook permissions: `chmod +x ~/.response-boxes/hooks/*.sh`
3. jq is available: `which jq`
4. Hook is registered: Check agent's hook configuration

**Debug:**

```bash
# Check if hooks are firing
export DEBUG_RESPONSE_BOXES=1
# Run agent and check stderr
```

#### Learnings not injecting

**Symptoms:** No cross-session context appearing

**Check:**

1. Event store has content: `wc -l ~/.response-boxes/analytics/boxes.jsonl`
2. Injection hook is registered
3. `BOX_INJECT_DISABLED` is not set

**Debug:**

```bash
# Manually test injection
~/.response-boxes/hooks/inject-context.sh < /dev/null
```

#### Skill not found

**Symptoms:** `/analyze-boxes` not recognized

**Check:**

1. Skill is installed: `ls ~/.claude/skills/analyze-boxes/` or equivalent
2. Agent supports skills
3. Skill file has correct frontmatter

---

## Version History

| Version | Date       | Changes                             |
| ------- | ---------- | ----------------------------------- |
| 1.0.0   | 2026-01-24 | Initial comprehensive documentation |

---

## References

### Official Documentation

- [Claude Code Hooks](https://docs.anthropic.com/claude-code/hooks)
- [OpenCode Plugins](https://opencode.ai/docs/plugins/)
- [Windsurf Cascade Hooks](https://docs.windsurf.com/windsurf/cascade/hooks)
- [Cursor Hooks](https://cursor.com/docs/agent/hooks)

### Related Projects

- [Cross-Agent Compatibility Engine](../cross-agent-compatibility-engine)
- [OpenCode Session Metadata Plugin](https://github.com/crayment/opencode-session-metadata)

### Research Sources

- [Cursor 1.7 Hooks Overview (InfoQ)](https://www.infoq.com/news/2025/10/cursor-hooks/)
- [Windsurf SWE-1.5 & Cascade Hooks Guide](https://www.digitalapplied.com/blog/windsurf-swe-1-5-cascade-hooks-november-2025)
- [Builder.io: Cursor vs Claude Code](https://www.builder.io/blog/cursor-vs-claude-code)
