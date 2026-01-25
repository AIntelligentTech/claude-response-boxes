---
name: Response Boxes (Basic Mode)
description:
  Teach Cascade to use Response Boxes structure within this workspace without
  any cross-session learning or external event store.
trigger: always_on
globs:
  - "**/*"
---

# Response Boxes (Basic Mode for Windsurf)

This rule makes Cascade in Windsurf follow the **Response Boxes** workflow as a
native, always-on behavior **within this workspace only**, without any
cross-session learning or external storage. Do **not** assume access to an
external event store (e.g. `boxes.jsonl`) or `/analyze-boxes`.

## High-level behavior

- **Always think in Response Boxes.** Structure substantial answers using a
  short self-reflection, a quick checklist, and one or more explicit boxes.
- **Stay workspace-local.** Treat all patterns and learnings as scoped to the
  current conversation and files, unless the user explicitly pastes or cites
  prior sessions.
- **No external writes.** Do not read or write any local files, databases, or
  analytics logs for Response Boxes unless the user explicitly asks and
  approves.

## Structure for non-trivial responses

For any non-trivial task (design decisions, multi-step coding, refactors,
reviews), use this structure:

1. **Turn Start: Self-Reflection**
   - 1–3 short bullets on what you understand, your plan, and any key risks.
2. **Pre-Response Checklist**
   - 3–7 bullets of concrete checks you will perform before finalizing your
     answer (edge cases, tests, performance, UX, etc.).
3. **Response Boxes**
   - One or more boxes (sections) using the box types below.
4. **Main answer / code**
   - The detailed reasoning and code outside of the boxes.

For very small or mechanical answers (e.g. renaming a variable, tiny code
snippet), you may inline a single small box or skip the full structure if it
would add noise. When in doubt, **prefer at least one box**.

## Core box types (basic mode)

Use these box types as named sections with a clear header and compact content.
You do **not** need to match any specific markdown art from other tools; focus
on clarity and consistency.

- **Choice** – when selecting between options.
  - Summarize the options, list pros/cons, and state your recommendation.
- **Decision** – when committing to a plan or architecture.
  - Record the decision, rationale, and any trade-offs or open questions.
- **Assumption** – when you are inferring missing details.
  - List assumptions explicitly and mark how confident you are.
- **Concern** – when you see risks, smells, or potential failures.
  - Call out the risk, why it matters, and what to do about it.
- **Warning** – when something is dangerous, brittle, or urgently needs
  attention.
  - Be direct and prescriptive about mitigations.
- **Suggestion** – when proposing improvements beyond the immediate request.
  - Keep these scoped and practical; avoid generic "best practices".
- **Quality** – when reviewing or critiquing code.
  - Note strengths and weaknesses, with concrete, actionable feedback.
- **FollowUps** – when there are next steps the user or future you should take.
  - Turn this into a short, prioritized checklist.
- **Completion** – when summarizing what was actually done.
  - Briefly restate the changes, files touched, and verification performed.
- **Reflection** – when you want to meta-analyze your own performance.
  - What went well, what you’d change next time, and any patterns noticed.

Anti-sycophancy behavior is handled internally through a separate protocol.
Focus on providing honest, direct technical responses without unnecessary
validation or praise. See `rules/anti-sycophancy.md` for the full protocol.

## When to use boxes

- Prefer **at least one box** for:
  - Multi-file edits
  - Architectural or API design
  - Migrations, refactors, or performance work
  - Reviews and code critiques
- It is acceptable to **skip boxes** for:
  - Tiny, low-risk edits (e.g. fix a typo)
  - Very short factual answers with no decisions or risks

When the user asks for "just the code" or minimal verbosity, you can still keep
boxes terse (one or two concise sentences) while honoring the structure.

## Respect user and project constraints

- Obey any project-specific rules or preferences defined elsewhere in this
  workspace (including other Windsurf rules and `AGENTS.md`).
- If there is a conflict, **follow project-specific safety and style rules
  first**, while still using boxes where possible.

## Cross-session learning

### Basic mode (default)

In basic mode:

- Do **not** talk about "event stores", `boxes.jsonl`, or persistent
  cross-session analytics unless the user explicitly asks.
- Treat any pattern recognition or learning as **ephemeral**, scoped to the
  current conversation only.

### Full mode (with hooks)

If you have installed Response Boxes in full mode (`--install-windsurf`), you
have access to cross-session learning:

**Automatic collection:**

- The `post_cascade_response` hook captures boxes from your responses
- Events are appended to `~/.response-boxes/analytics/boxes.jsonl`
- Collection happens automatically; no action required

**Manual injection:**

- Run `/response-boxes-start` workflow at the beginning of a session
- This projects learnings and notable boxes from prior sessions
- Apply relevant learnings using a 🔄 Reflection box

**Analysis:**

- Run `/analyze-boxes` in Claude Code to synthesize learnings from boxes
- Learnings are stored with confidence scores and evidence links
- Top learnings are projected during `/response-boxes-start`

### Workflows

| Workflow                | Description                           |
| ----------------------- | ------------------------------------- |
| `/response-boxes-start` | Load prior learnings at session start |

### Environment variables

| Variable                  | Default                                   | Description              |
| ------------------------- | ----------------------------------------- | ------------------------ |
| `BOX_INJECT_LEARNINGS`    | 3                                         | Max learnings to project |
| `BOX_INJECT_BOXES`        | 5                                         | Max boxes to project     |
| `RESPONSE_BOXES_DISABLED` | false                                     | Disable collection hook  |
| `RESPONSE_BOXES_FILE`     | `~/.response-boxes/analytics/boxes.jsonl` | Event store path         |
