# Response Boxes Architecture

**Version:** 0.6.0

This document defines the technical architecture of the Response Box System, an
event-sourced metacognitive framework for AI coding agents.

---

## Overview

The Response Box System provides:

1. **Transparent reasoning** — Structured boxes surface hidden decisions
2. **Within-session metacognition** — Boxes make assumptions/choices explicit in
   the same thread, enabling immediate self-correction while context is fresh
3. **Cross-session self-learning** — High-signal boxes persist as an event log;
   analysis converts them into durable patterns that can be reinjected later
4. **Continuous refinement** — AI-powered analysis synthesizes higher-level
   insights and updates them as new evidence arrives

The knowledge model is intentionally three-tier:

- **Boxes** — Raw, turn-level evidence captured during a session
- **Learnings** — Patterns synthesized from many boxes (typically `level: 0`)
- **Meta-learnings** — Higher-level principles that synthesize multiple
  learnings (typically `level: 1+`)

For operational setup and workflow guidance (output style, rules, CLAUDE.md,
hooks, and skill design), see **Best Practices: Integrating with Claude Code**
in the project `README.md`.

---

## Multi-Agent Architecture

Response Boxes supports multiple AI coding agents through a shared event store.
Each agent has adapters appropriate to its extension capabilities.

### Agent Support Matrix

| Agent       | Version Required | Collection            | Injection            | Analysis  |
| ----------- | ---------------- | --------------------- | -------------------- | --------- |
| Claude Code | Any              | ✅ SessionEnd hook    | ✅ SessionStart hook | ✅ Native |
| OpenCode    | v1.1.34+         | ✅ Plugin event       | ✅ System transform  | ✅ Native |
| Windsurf    | v1.12.41+        | ✅ post_cascade hook  | ⚠️ Manual workflow   | ⚠️ Via CC |
| Cursor      | v1.7+            | ✅ afterAgentResponse | ⚠️ Manual skill      | ⚠️ Via CC |

### Cross-Agent Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MULTI-AGENT RESPONSE BOXES                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ Claude Code  │  │   OpenCode   │  │   Windsurf   │  │    Cursor    │    │
│  │              │  │              │  │              │  │              │    │
│  │ SessionEnd   │  │ message.     │  │ post_cascade │  │ afterAgent   │    │
│  │ Hook         │  │ updated      │  │ _response    │  │ Response     │    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
│         │                 │                 │                 │            │
│         │   BoxCreated    │   BoxCreated    │   BoxCreated    │ BoxCreated │
│         ▼                 ▼                 ▼                 ▼            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                ~/.response-boxes/analytics/boxes.jsonl               │   │
│  │                     (Shared Append-Only Event Store)                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│         │                 │                 │                 │            │
│         │   Project &     │   Project &     │                 │            │
│         │   Inject        │   Inject        │                 │            │
│         ▼                 ▼                 ▼                 ▼            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ SessionStart │  │ system.      │  │ /response-   │  │ /response-   │    │
│  │ Hook         │  │ transform    │  │ boxes-start  │  │ boxes-       │    │
│  │ (auto)       │  │ (auto)       │  │ (manual)     │  │ context      │    │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Plugin/Hook API Stability

| Agent       | API                     | Stability    | Notes                    |
| ----------- | ----------------------- | ------------ | ------------------------ |
| Claude Code | SessionStart/SessionEnd | Stable       | Core hook mechanism      |
| OpenCode    | message.updated         | Stable       | Primary capture          |
| OpenCode    | chat.system.transform   | Experimental | SessionID added Jan 2026 |
| OpenCode    | chat.headers            | Stable       | Session correlation      |
| Windsurf    | post_cascade_response   | Stable       | Observation only         |
| Cursor      | afterAgentResponse      | Stable       | Observation only         |

### Analysis Workflow (Cross-Agent)

```
User runs /analyze-boxes in Claude Code (or OpenCode)
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  Load all events from boxes.jsonl │
    │  (includes boxes from ALL agents) │
    └───────────────┬───────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  AI Analysis: Identify patterns   │
    │  across all agents and sessions   │
    └───────────────┬───────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  User approves proposed learnings │
    └───────────────┬───────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  Append learning events to store  │
    │  (available to ALL agents)        │
    └───────────────────────────────────┘
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    EVENT-SOURCED RESPONSE BOX SYSTEM                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      LAYER 1: PROMPT GUIDANCE                        │    │
│  │                                                                      │    │
│  │  agents/claude-code/output-styles/response-box.md    agents/claude-code/rules/response-boxes.md           │
│  │  ├─ Turn Start Self-Reflection    ├─ Complete box specifications   │    │
│  │  ├─ Learning Context Handling     ├─ Metacognition protocol        │    │
│  │  ├─ Box Quick Reference           ├─ Usage guidelines              │    │
│  │  └─ Pre-Response Checklist        └─ Anti-patterns                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                       │                                      │
│                                       ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      LAYER 2: EVENT STORE                            │    │
│  │                                                                      │    │
│  │                    boxes.jsonl (append-only)                         │    │
│  │  ┌─────────────────────────────────────────────────────────────┐    │    │
│  │  │ BoxCreated ──▶ EvidenceLinked ──▶ LearningCreated           │    │    │
│  │  │      │              │                   │                    │    │    │
│  │  │      ▼              ▼                   ▼                    │    │    │
│  │  │ BoxEnriched    LearningLinked     LearningUpdated           │    │    │
│  │  │                     │                                        │    │    │
│  │  │                     ▼                                        │    │    │
│  │  │              AnalysisCompleted                               │    │    │
│  │  └─────────────────────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                       │                                      │
│            ┌──────────────────────────┼──────────────────────────┐          │
│            │                          │                          │          │
│            ▼                          ▼                          ▼          │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐      │
│  │   SessionEnd     │    │   SessionStart   │    │  /analyze-boxes  │      │
│  │   Hook           │    │   Hook           │    │  Skill           │      │
│  │                  │    │                  │    │                  │      │
│  │ Emit BoxCreated  │    │ Project state    │    │ AI-powered       │      │
│  │ events from      │    │ Inject learnings │    │ pattern analysis │      │
│  │ transcript       │    │ + top boxes      │    │ Creates/updates  │      │
│  │                  │    │                  │    │ learnings        │      │
│  └──────────────────┘    └──────────────────┘    └──────────────────┘      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Event Store Design

### Core Principle

The system follows an **event sourcing** pattern:

- `boxes.jsonl` is an append-only event log (single source of truth)
- Current state is derived by **projecting** events
- Events are immutable facts; corrections are new events
- Relationships are explicit events, not embedded references

### Event Types

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EVENT TAXONOMY                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ENTITY EVENTS (create entities)                                             │
│  ├── BoxCreated        Box from session transcript                          │
│  └── LearningCreated   Pattern/insight from analysis                        │
│                                                                              │
│  RELATIONSHIP EVENTS (connect entities)                                      │
│  ├── EvidenceLinked    Box ↔ Learning (with strength + relationship)        │
│  └── LearningLinked    Learning ↔ Learning (hierarchy/synthesis)            │
│                                                                              │
│  MUTATION EVENTS (update entities)                                           │
│  ├── BoxEnriched       Add metadata to box (score, validation)              │
│  └── LearningUpdated   Update learning (confidence, insight refinement)     │
│                                                                              │
│  SYSTEM EVENTS (track processing)                                            │
│  └── AnalysisCompleted Marks analysis run completion                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Event Schemas

### BoxCreated

Emitted by `session-processor.sh` at session end.

```json
{
  "event": "BoxCreated",
  "id": "sess_abc123_5",
  "ts": "2026-01-21T10:00:00Z",
  "schema_version": 1,
  "box_type": "Assumption",
  "fields": {
    "what": "Using TypeScript",
    "basis": "tsconfig.json exists"
  },
  "context": {
    "session_id": "abc123",
    "git_remote": "github.com/user/repo",
    "git_branch": "main",
    "turn_number": 5
  },
  "initial_score": 80
}
```

| Field            | Type   | Description                               |
| ---------------- | ------ | ----------------------------------------- |
| `event`          | string | Always "BoxCreated"                       |
| `id`             | string | Unique box ID: `sess_{session_id}_{turn}` |
| `ts`             | string | ISO 8601 timestamp                        |
| `schema_version` | number | Schema version for this event             |
| `box_type`       | string | Choice, Assumption, Warning, etc.         |
| `fields`         | object | Extracted fields from box content         |
| `context`        | object | Session and repository context            |
| `initial_score`  | number | Base score from box type (40-90)          |

### LearningCreated

Emitted by `/analyze-boxes` skill.

```json
{
  "event": "LearningCreated",
  "id": "learning_001",
  "ts": "2026-01-21T15:00:00Z",
  "insight": "User consistently prefers Zod for schema validation",
  "confidence": 0.85,
  "scope": "global",
  "tags": ["validation", "typescript", "libraries"],
  "level": 0
}
```

| Field        | Type   | Description                             |
| ------------ | ------ | --------------------------------------- |
| `event`      | string | Always "LearningCreated"                |
| `id`         | string | Unique learning ID: `learning_{number}` |
| `ts`         | string | ISO 8601 timestamp                      |
| `insight`    | string | Human-readable learning statement       |
| `confidence` | number | 0.0-1.0 confidence score                |
| `scope`      | string | "global" or "repo"                      |
| `tags`       | array  | Categorization tags                     |
| `level`      | number | 0 = base learning, 1+ = meta-learning   |

### EvidenceLinked

Connects a box to a learning with relationship metadata.

```json
{
  "event": "EvidenceLinked",
  "id": "link_001",
  "ts": "2026-01-21T15:00:00Z",
  "learning_id": "learning_001",
  "box_id": "sess_abc123_5",
  "strength": 0.9,
  "relationship": "supports"
}
```

| Field          | Type   | Description                                |
| -------------- | ------ | ------------------------------------------ |
| `event`        | string | Always "EvidenceLinked"                    |
| `id`           | string | Unique link ID                             |
| `ts`           | string | ISO 8601 timestamp                         |
| `learning_id`  | string | Target learning                            |
| `box_id`       | string | Source box                                 |
| `strength`     | number | 0.0-1.0 evidence strength                  |
| `relationship` | string | "supports", "contradicts", or "tangential" |

**Relationship types:**

- `supports` — Box provides positive evidence for the learning
- `contradicts` — Box provides counter-evidence (weakens learning)
- `tangential` — Box is related but not direct evidence

### LearningLinked

Connects learnings in a hierarchy (meta-learnings).

```json
{
  "event": "LearningLinked",
  "id": "llink_001",
  "ts": "2026-01-21T16:00:00Z",
  "parent_learning_id": "learning_010",
  "child_learning_id": "learning_001",
  "relationship": "synthesizes"
}
```

| Field                | Type   | Description                               |
| -------------------- | ------ | ----------------------------------------- |
| `event`              | string | Always "LearningLinked"                   |
| `id`                 | string | Unique link ID                            |
| `ts`                 | string | ISO 8601 timestamp                        |
| `parent_learning_id` | string | Higher-level learning                     |
| `child_learning_id`  | string | Component learning                        |
| `relationship`       | string | "synthesizes", "refines", or "supersedes" |

**Relationship types:**

- `synthesizes` — Parent combines multiple child learnings
- `refines` — Parent is a more specific version of child
- `supersedes` — Parent replaces child (child is outdated)

### BoxEnriched

Updates box metadata without modifying the original.

```json
{
  "event": "BoxEnriched",
  "id": "enrich_001",
  "ts": "2026-01-21T15:00:00Z",
  "box_id": "sess_abc123_5",
  "updates": {
    "score": 95,
    "validated": true,
    "validation_reason": "Consistent with learning_001"
  }
}
```

| Field     | Type   | Description            |
| --------- | ------ | ---------------------- |
| `event`   | string | Always "BoxEnriched"   |
| `id`      | string | Unique enrichment ID   |
| `ts`      | string | ISO 8601 timestamp     |
| `box_id`  | string | Target box             |
| `updates` | object | Fields to add/override |

### LearningUpdated

Updates learning metadata.

```json
{
  "event": "LearningUpdated",
  "id": "lupdate_001",
  "ts": "2026-01-21T16:00:00Z",
  "learning_id": "learning_001",
  "updates": {
    "confidence": 0.92,
    "insight": "User prefers Zod for validation in all TypeScript projects"
  }
}
```

| Field         | Type   | Description              |
| ------------- | ------ | ------------------------ |
| `event`       | string | Always "LearningUpdated" |
| `id`          | string | Unique update ID         |
| `ts`          | string | ISO 8601 timestamp       |
| `learning_id` | string | Target learning          |
| `updates`     | object | Fields to update         |

### AnalysisCompleted

Marks the end of an analysis run.

```json
{
  "event": "AnalysisCompleted",
  "id": "analysis_001",
  "ts": "2026-01-21T15:00:00Z",
  "through_ts": "2026-01-21T14:30:00Z",
  "stats": {
    "boxes_analyzed": 47,
    "learnings_created": 3,
    "learnings_updated": 2,
    "links_created": 12
  }
}
```

---

## Projection Functions

### Compatibility and Breaking Changes

- **Legacy support**: Older analytics lines that omit `event`/`id`/`box_type`
  are treated as legacy BoxCreated data and normalized during projection.
- **Schema guardrail**: Hooks refuse to project if they see an event
  `schema_version` newer than they support, and inject a clear “please update”
  message rather than producing incorrect context.

### Automation vs Manual Steps

- **Automated (hooks)**
  - SessionEnd automatically emits `BoxCreated` events (best-effort)
  - SessionStart automatically injects projected learnings/boxes
  - SessionStart injects a one-line reminder when unanalyzed boxes exist
- **Manual (human-in-the-loop)**
  - `/analyze-boxes` is user-invoked
  - Proposed events are reviewed and approved by the user before appending
  - Analysis is nondeterministic (LLM pattern recognition); results may vary
    run-to-run

Current state is derived by projecting events.

### Project a Box

```bash
project_box() {
    local box_id="$1"
    jq -s --arg id "$box_id" '
        # Get BoxCreated event
        (map(select(.event == "BoxCreated" and .id == $id)) | .[0]) as $created |

        # Get all enrichments, merge in order
        (map(select(.event == "BoxEnriched" and .box_id == $id)) |
         sort_by(.ts) |
         reduce .[] as $e ({}; . + $e.updates)) as $enrichments |

        # Get linked learnings
        (map(select(.event == "EvidenceLinked" and .box_id == $id)) |
         map({learning_id, strength, relationship})) as $links |

        # Combine
        $created + $enrichments + {linked_learnings: $links}
    ' boxes.jsonl
}
```

### Project a Learning

```bash
project_learning() {
    local learning_id="$1"
    jq -s --arg id "$learning_id" '
        # Get LearningCreated event
        (map(select(.event == "LearningCreated" and .id == $id)) | .[0]) as $created |

        # Get all updates, merge in order
        (map(select(.event == "LearningUpdated" and .learning_id == $id)) |
         sort_by(.ts) |
         reduce .[] as $u ({}; . + $u.updates)) as $updates |

        # Get evidence links
        (map(select(.event == "EvidenceLinked" and .learning_id == $id)) |
         map({box_id, strength, relationship})) as $evidence |

        # Get child learnings (this learning synthesizes)
        (map(select(.event == "LearningLinked" and .parent_learning_id == $id)) |
         map(.child_learning_id)) as $children |

        # Get parent learnings (this learning is part of)
        (map(select(.event == "LearningLinked" and .child_learning_id == $id)) |
         map(.parent_learning_id)) as $parents |

        # Combine
        $created + $updates + {
            evidence: $evidence,
            child_learnings: $children,
            parent_learnings: $parents
        }
    ' boxes.jsonl
}
```

### Calculate Effective Confidence

Learning confidence is adjusted based on evidence:

```
effective_confidence = base_confidence × evidence_factor × recency_factor

Where:
  evidence_factor = Σ(strength × relationship_weight) / max_evidence
    - relationship_weight: supports=1.0, tangential=0.3, contradicts=-0.5

  recency_factor = 0.95^(weeks_since_last_evidence)
```

---

## Component Details

### Session Processor (SessionEnd Hook)

**File:** `agents/claude-code/hooks/session-processor.sh`

**Trigger:** Session end (logout, clear, exit)

**Input:** JSON via stdin with `session_id`, `transcript_path`, `cwd`

**Output:** None (appends to boxes.jsonl)

**Process:**

1. Parse transcript for box patterns (emoji + dashes)
2. Extract fields from each box
3. Assign initial score based on box type
4. Emit `BoxCreated` event for each box

**Initial Scores by Type:**

| Type       | Score | Rationale                         |
| ---------- | ----- | --------------------------------- |
| Reflection | 90    | Applied learning (high value)     |
| Warning    | 90    | Serious risk identification       |
| Pushback   | 85    | Challenged user direction         |
| Assumption | 80    | Filled gap (learning opportunity) |
| Choice     | 70    | Active decision                   |
| Completion | 70    | Task assessment                   |
| Concern    | 65    | Risk flagged                      |
| Confidence | 60    | Uncertainty noted                 |
| Decision   | 55    | Judgment call                     |
| Suggestion | 45    | Optional improvement              |
| Quality    | 40    | Code assessment                   |
| FollowUps  | 35    | Next steps                        |

### Context Injector (SessionStart Hook)

**File:** `agents/claude-code/hooks/inject-context.sh`

**Trigger:** Session start (startup, resume, clear, compact)

**Input:** JSON via stdin with `session_id`, `cwd`

**Output:** JSON with `hookSpecificOutput.additionalContext`

**Process:**

1. Check whether any `BoxCreated` events exist since the last
   `AnalysisCompleted`
2. If so, inject a one-line reminder to run `/analyze-boxes`
3. Project all learnings from events
4. Calculate effective confidence for each
5. Apply recency decay and repo relevance boost
6. Select top learnings (level 1+ first, then level 0)
7. Project top boxes with recency decay
8. Format and inject combined context

**Injection Format:**

```
PRIOR SESSION LEARNINGS:

Unanalyzed response boxes detected (27). Run /analyze-boxes to update learnings.

## Patterns (from cross-session analysis)
• [HIGH] User prefers Zod for validation (92% confidence, 5 evidence)
• [MEDIUM] This repo uses functional patterns (78% confidence, repo-specific)

## Recent Notable Boxes
• Assumption: Assumed PostgreSQL [github.com/user/api] (2 days ago)
• Warning: No rate limiting on public endpoints [github.com/user/api]

Review and apply using 🔄 Reflection where relevant.
```

### Analysis Skill (/analyze-boxes)

**File:** `agents/claude-code/skills/analyze-boxes/`

**Trigger:** User runs `/analyze-boxes`

**Process:**

1. Load all events from boxes.jsonl
2. Find last `AnalysisCompleted` marker
3. Filter `BoxCreated` events since then
4. Project existing learnings
5. Present to Claude for analysis:
   - Identify new patterns
   - Link boxes to existing learnings
   - Suggest learning updates
   - Propose meta-learnings
6. User reviews and approves
7. Append approved events to boxes.jsonl
8. Append `AnalysisCompleted` marker

---

## Data Flow Examples

### Example 1: Box Collection

```
Session with 3 boxes → SessionEnd hook
                            │
                            ▼
                    ┌───────────────┐
                    │ boxes.jsonl   │
                    │               │
                    │ BoxCreated    │
                    │ BoxCreated    │
                    │ BoxCreated    │
                    └───────────────┘
```

### Example 2: Analysis Run

```
User: /analyze-boxes
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│                     AI ANALYSIS                              │
│                                                              │
│  "I found 3 boxes that suggest a pattern:                   │
│   - sess_001_2: Chose Zod over Yup                          │
│   - sess_002_1: Chose Zod over joi                          │
│   - sess_003_1: Chose Zod over superstruct                  │
│                                                              │
│   Proposed learning:                                         │
│   'User consistently prefers Zod for validation'            │
│   Confidence: 0.85                                          │
│   Scope: global                                             │
│                                                              │
│   Evidence links:                                            │
│   - sess_001_2 supports (strength: 0.9)                     │
│   - sess_002_1 supports (strength: 0.9)                     │
│   - sess_003_1 supports (strength: 0.8)"                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
        │
        ▼ (User approves)
┌───────────────┐
│ boxes.jsonl   │
│               │
│ + LearningCreated
│ + EvidenceLinked
│ + EvidenceLinked
│ + EvidenceLinked
│ + AnalysisCompleted
└───────────────┘
```

### Example 3: Context Injection

```
New session starts → SessionStart hook
                          │
                          ▼
                  ┌───────────────┐
                  │ Project state │
                  │ from events   │
                  └───────┬───────┘
                          │
                          ▼
            ┌─────────────────────────┐
            │ Learnings:              │
            │ • Zod preference (0.92) │
            │ • Functional style (0.78)│
            │                         │
            │ Top boxes:              │
            │ • Assumption: PostgreSQL│
            │ • Warning: No rate limit│
            └────────────┬────────────┘
                         │
                         ▼
              Inject as additionalContext
```

---

## Design Decisions

### Why Event Sourcing?

**Problem:** Traditional CRUD requires updating records in place, which:

- Loses history
- Makes it impossible to understand how learnings evolved
- Complicates concurrent updates

**Solution:** Event sourcing treats every change as an immutable event:

- Complete audit trail
- Can replay to any point in time
- Natural append-only model fits JSONL perfectly

### Why Explicit Link Events?

**Problem:** Embedding references (e.g., `evidence_box_ids: [...]`) creates
issues:

- Can't add evidence to existing learning without new event
- Queries in reverse direction require scanning all learnings
- Unclear when relationships changed

**Solution:** `EvidenceLinked` events:

- Bidirectional queries are symmetric
- Can add evidence incrementally
- Relationship metadata (strength, type) is explicit
- Full history of when links were created

### Why Learning Hierarchy?

**Problem:** Flat learnings don't capture meta-patterns:

- "Prefers Zod" + "Prefers functional style" + "Prefers small bundles" → "User
  prioritizes developer experience and TypeScript integration"

**Solution:** `LearningLinked` with `level` field:

- Level 0: Direct patterns from boxes (base learnings)
- Level 1+: Meta-learnings that synthesize multiple level-0 learnings
- Hierarchy enables richer context injection (meta-learnings first, then
  specifics)

### Why Strength and Relationship?

**Problem:** Not all evidence is equal:

- Some boxes strongly support a learning
- Some are tangentially related
- Some contradict the learning

**Solution:** Evidence metadata:

- `strength`: 0.0-1.0 for evidence quality
- `relationship`: supports/contradicts/tangential
- Enables nuanced confidence calculation

---

## File Structure

### Repository Structure

```
agent-response-boxes/
├── agents/
│   ├── claude-code/
│   │   ├── hooks/
│   │   │   ├── inject-context.sh     # SessionStart: project and inject
│   │   │   └── session-processor.sh  # SessionEnd: emit BoxCreated
│   │   ├── output-styles/
│   │   │   └── response-box.md       # Active output style
│   │   ├── rules/
│   │   │   └── response-boxes.md     # Complete specification
│   │   ├── skills/
│   │   │   └── analyze-boxes/SKILL.md
│   │   └── config/
│   │       └── claude-md-snippet.md
│   ├── opencode/
│   │   ├── plugins/
│   │   │   └── response-boxes.plugin.ts
│   │   ├── skills/
│   │   │   └── analyze-boxes/SKILL.md
│   │   └── instructions/
│   │       └── response-boxes.md
│   ├── windsurf/
│   │   ├── hooks/
│   │   │   ├── hooks.json
│   │   │   └── windsurf-collector.sh
│   │   ├── workflows/
│   │   │   └── response-boxes-start.md
│   │   └── rules/
│   │       └── response-boxes.md
│   └── cursor/
│       ├── hooks/
│       │   ├── hooks.json
│       │   └── cursor-collector.sh
│       ├── skills/
│       │   └── response-boxes-context/SKILL.md
│       └── rules/
│           └── response-boxes.mdc
├── tests/
│   ├── hooks/
│   │   ├── inject-context.bats
│   │   └── session-processor.bats
│   ├── installer/
│   │   └── install.bats
│   └── opencode/
│       ├── box-extraction.test.ts
│       └── context-injection.test.ts
├── docs/
│   ├── architecture.md
│   └── cross-agent-compatibility.md
└── install.sh
```

### Installed Files (User Level)

```
~/.claude/
├── hooks/
│   ├── session-processor.sh     # SessionEnd: emit BoxCreated events
│   └── inject-context.sh        # SessionStart: project and inject
├── output-styles/
│   └── response-box.md          # Active output style
├── rules/
│   └── response-boxes.md        # Complete specification
├── skills/
│   └── analyze-boxes/
│       └── SKILL.md             # AI-powered analysis skill

~/.config/opencode/plugins/
└── response-boxes.plugin.ts     # OpenCode plugin

~/.response-boxes/
├── analytics/
│   └── boxes.jsonl              # Event store (single source of truth)
└── hooks/
    ├── windsurf-collector.sh    # Windsurf collection hook
    └── cursor-collector.sh      # Cursor collection hook
```

---

## Dependencies

- **jq**: Required for JSON processing in hooks
- **bash**: Hooks are bash scripts
- **git**: Optional, for repository context

---

## Configuration

### Environment Variables

| Variable               | Default | Description                |
| ---------------------- | ------- | -------------------------- |
| `BOX_INJECT_LEARNINGS` | 3       | Max learnings to inject    |
| `BOX_INJECT_BOXES`     | 5       | Max boxes to inject        |
| `BOX_INJECT_DISABLED`  | false   | Disable injection entirely |
| `BOX_RECENCY_DECAY`    | 0.95    | Weekly decay factor        |

### Hook Registration

In `~/.claude/settings.json`:

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

## Limitations

1. **No real-time updates** — Learnings only created via explicit analysis runs
2. **Single-machine** — No sync across devices (future: cloud storage)
3. **jq dependency** — Hooks require jq for JSON processing
4. **Projection cost** — Large event stores may slow injection (mitigate:
   caching)

---

## Migration from v3.0.0

### Removed Components

- `box-index.json` — Replaced by projection from events
- `analyze-boxes.sh` script — Replaced by `/analyze-boxes` skill
- Static BASE_SCORES in processor — AI determines scores dynamically

### Data Migration

Existing `boxes.jsonl` entries (if any) are compatible:

- Old entries without `event` field are treated as legacy `BoxCreated` events
- Run `/analyze-boxes` to create learnings from historical boxes

---

## Changelog

- **v0.6.0** (2026-01-25): Anti-sycophancy separation
  - Removed 🪞 Sycophancy box from response box taxonomy
  - Created `rules/anti-sycophancy.md` with research-backed protocol
  - Historical Sycophancy boxes filtered from projection
  - Box count reduced from 13 to 12

- **v0.5.0** (2026-01-24): Multi-agent support
  - Added OpenCode plugin with full collection and injection
  - Added Windsurf hooks and workflow for enhanced mode
  - Added Cursor hooks and skill for basic mode
  - Added cross-agent compatibility documentation
  - Added CI/CD pipeline with bats and vitest tests
  - Added SECURITY.md for data handling policy
  - Consolidated repository structure under agents/

- **v4.0.0** (2026-01-22): Event-sourced architecture
  - Complete rewrite with event sourcing pattern
  - Added EvidenceLinked with strength and relationship
  - Added LearningLinked for hierarchy
  - Added AI-powered /analyze-boxes skill
  - Removed box-index.json (projection replaces it)
  - Simplified session-processor.sh to emit events only
