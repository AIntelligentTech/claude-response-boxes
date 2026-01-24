---
name: response-boxes-context
description:
  Display prior session learnings and notable boxes for manual reference
---

# /response-boxes-context

This skill projects learnings and notable boxes from prior sessions for you to
reference in Cursor. Because Cursor hooks cannot inject context automatically,
run this skill at the start of a session to see cross-session learnings.

## Usage

Type `/response-boxes-context` to see prior session context.

## What It Does

1. **Read the event store** at `~/.response-boxes/analytics/boxes.jsonl`
2. **Project top learnings** sorted by confidence and recency
3. **Project notable boxes** from recent sessions
4. **Display context block** for you to reference

## Instructions

When this skill is invoked:

1. Read the file `~/.response-boxes/analytics/boxes.jsonl`
2. Parse each line as JSON
3. Separate events by type:
   - `LearningCreated` events → learnings
   - `BoxCreated` events → boxes
4. Sort learnings by confidence (descending), then by timestamp (most recent)
5. Sort boxes by timestamp (most recent first)
6. Display the top 3 learnings and top 5 boxes

## Output Format

```
PRIOR SESSION LEARNINGS (from Response Boxes):

Patterns (AI-synthesized learnings)
• [0.92] User prefers Zod for validation over Yup
• [0.85] This project uses functional patterns consistently
• [0.78] Always check for rate limiting on public endpoints

Recent notable boxes
• Warning: No authentication on DELETE endpoint [github.com/user/api]
• Assumption: Using TypeScript based on tsconfig.json [github.com/user/repo]
• Choice: Selected PostgreSQL over SQLite for production [github.com/user/app]

Apply relevant learnings using a 🔄 Reflection box in your response.
```

## Configuration

Environment variables:

| Variable               | Default                                   | Description              |
| ---------------------- | ----------------------------------------- | ------------------------ |
| `BOX_INJECT_LEARNINGS` | 3                                         | Max learnings to display |
| `BOX_INJECT_BOXES`     | 5                                         | Max boxes to display     |
| `RESPONSE_BOXES_FILE`  | `~/.response-boxes/analytics/boxes.jsonl` | Event store location     |

## Integration Notes

### Collection (Automatic)

If you have installed the Cursor collection hook, boxes are automatically
captured from your responses and appended to the event store. No action
required.

### Injection (Manual)

Cursor hooks are observation-only and cannot inject context into prompts. Use
this skill manually at session start to see prior learnings.

### Analysis

Run `/analyze-boxes` in Claude Code to synthesize learnings from boxes.
Learnings created there will appear when you run this skill.

## Troubleshooting

**No output?**

- Check that `~/.response-boxes/analytics/boxes.jsonl` exists
- Ensure you have completed sessions with Response Boxes enabled
- Run `/analyze-boxes` in Claude Code to create learnings

**Outdated learnings?**

- Run `/analyze-boxes` to process recent boxes into learnings
- Learnings use recency decay; older ones may have lower confidence

## See Also

- Response Boxes rules: `.cursor/rules/response-boxes.mdc`
- Architecture documentation: `docs/architecture.md`
- Cross-agent compatibility: `docs/cross-agent-compatibility.md`
