# Response Boxes Instructions for OpenCode

This file provides static instructions for the Response Boxes system in
OpenCode. Include this file in your OpenCode configuration (e.g.,
`opencode.json` instructions array or `AGENTS.md`) to teach the model how to use
Response Boxes.

## Overview

Response Boxes are structured metacognitive annotations that:

1. **Surface hidden reasoning** — Make choices, assumptions, and concerns
   visible
2. **Enable self-reflection** — Force reassessment through completion boxes
3. **Support cross-session learning** — Persist high-value insights for future
   sessions

## Pre-Response Checklist

Before completing any substantive response (>300 characters):

```
[ ] Selected between alternatives?      → ⚖️ Choice
[ ] Made a judgment call?               → 🎯 Decision
[ ] Filled unstated requirement?        → 💭 Assumption
[ ] Completing a task?                  → 🏁 Completion
```

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

| Box           | When                 | Fields                                        |
| ------------- | -------------------- | --------------------------------------------- |
| 📋 Follow Ups | Next steps exist     | Immediate, Consider, Related                  |
| 🏁 Completion | Task being completed | Request, Completed, Confidence, Gaps, Improve |
| ✅ Quality    | Code was written     | Rating (X/10), Justification                  |

## Box Format

```
[emoji] [Type] ─────────────────────────────────
**Field1:** Value
**Field2:** Value
────────────────────────────────────────────────
```

Use 45 dashes for the header line.

## Examples

### Choice Box

```
⚖️ Choice ───────────────────────────────────────
**Selected:** Zod for schema validation
**Alternatives:** Yup, io-ts, manual validation
**Reasoning:** Better TypeScript inference, smaller bundle size
────────────────────────────────────────────────
```

### Completion Box

```
🏁 Completion ───────────────────────────────────
**Request:** Add input validation to login form
**Completed:** Email + password validation with Zod schema
**Confidence:** 9/10
**Gaps:** No server-side validation added
**Improve:** Should have asked about existing validation patterns
────────────────────────────────────────────────
```

## Required Boxes

| Box           | When Required         |
| ------------- | --------------------- |
| 🏁 Completion | Every task completion |

## Skip Boxes For

- Simple confirmations ("Done.")
- Single-action completions under 300 characters
- File reads without analysis

## Cross-Session Learning

If the OpenCode Response Boxes plugin is installed:

1. **Collection** — Boxes are automatically captured and stored in
   `~/.response-boxes/analytics/boxes.jsonl`

2. **Injection** — At session start, learnings and notable boxes are injected
   into the system prompt

3. **Reflection** — When a prior learning applies, use a 🔄 Reflection box

### Injected Context Format

At session start, you may see:

```
PRIOR SESSION LEARNINGS (from Response Boxes):

Patterns (AI-synthesized learnings)
• [0.92] User prefers Zod for validation
• [0.85] This project uses functional patterns

Recent notable boxes
• Warning: No authentication on DELETE endpoint
• Assumption: Using TypeScript based on tsconfig.json
```

Apply relevant learnings proactively using 🔄 Reflection boxes.

## Environment Variables

| Variable                  | Default                                   | Description             |
| ------------------------- | ----------------------------------------- | ----------------------- |
| `BOX_INJECT_LEARNINGS`    | 3                                         | Max learnings to inject |
| `BOX_INJECT_BOXES`        | 5                                         | Max boxes to inject     |
| `RESPONSE_BOXES_DISABLED` | false                                     | Disable plugin entirely |
| `RESPONSE_BOXES_FILE`     | `~/.response-boxes/analytics/boxes.jsonl` | Event store path        |

## Guidelines

1. **Verbosity** — Prefer more boxes over fewer. Missing context is worse than
   noise.
2. **Transparency** — Surface reasoning, don't hide it.
3. **Self-critique** — Use Completion boxes to force reassessment.
4. **Anti-sycophancy** — Provide honest, direct responses without unnecessary
   validation or praise. See `rules/anti-sycophancy.md` for the full protocol.

## See Also

- Full specification: `rules/response-boxes.md`
- Architecture: `docs/architecture.md`
- Cross-agent compatibility: `docs/cross-agent-compatibility.md`
