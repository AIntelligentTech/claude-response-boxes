---
name: analyze-boxes
description: AI-powered analysis of response boxes to create learnings and link evidence
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash
---

# /analyze-boxes Skill

AI-powered analysis of response boxes to identify patterns, create learnings,
and link evidence.

## Trigger

User runs `/analyze-boxes`

---

## Instructions

You are analyzing response boxes from Claude Code sessions to identify patterns
and create learnings. The boxes are stored in `~/.claude/analytics/boxes.jsonl`
as an event-sourced log.

### Step 1: Load and Understand the Data

First, load the event store and find unprocessed boxes:

```bash
# Get last AnalysisCompleted timestamp (epoch)
LAST_ANALYSIS_EPOCH=$(jq -s -r '
  def ts_epoch($v): ($v // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+"; "") | fromdateiso8601;
  ([.[] | select(.event == "AnalysisCompleted")] | sort_by(.ts)) as $runs |
  if ($runs | length) > 0 then ts_epoch($runs[-1].through_ts // $runs[-1].ts)
  else ts_epoch("1970-01-01T00:00:00Z") end
' ~/.claude/analytics/boxes.jsonl 2>/dev/null || echo '0')

# Count boxes since last analysis (legacy lines without .event are treated as BoxCreated)
jq -s --argjson since "$LAST_ANALYSIS_EPOCH" '
  def ts_epoch($v): ($v // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+"; "") | fromdateiso8601;
  [.[] | select(((.event // "BoxCreated") == "BoxCreated") and (ts_epoch(.ts) > $since))] | length
' ~/.claude/analytics/boxes.jsonl
```

Read the full event store to understand:

- Recent BoxCreated events (unprocessed)
- Existing LearningCreated events (what patterns are already known)
- EvidenceLinked events (what boxes support which learnings)

### Step 2: Analyze for Patterns

Look for these pattern types in the unprocessed boxes:

1. **Repeated Choices** — Same library/tool/approach chosen multiple times
2. **Consistent Assumptions** — Similar assumptions made across sessions
3. **Recurring Warnings** — Same risks flagged repeatedly
4. **Pushback Themes** — Patterns in what user directions you disagree with
5. **Completion Gaps** — Frequently noted gaps in task completions
6. **Cross-Session Learning** — Reflection boxes showing applied learnings

### Step 3: Present Findings

For each pattern found, present:

```text
## Pattern: [Brief Description]

**Insight:** [One-sentence learning statement]

**Evidence:**
- Box sess_xxx_1: [summary] (strength: 0.9, supports)
- Box sess_yyy_2: [summary] (strength: 0.7, supports)
- Box sess_zzz_3: [summary] (strength: 0.4, tangential)

**Confidence:** [0.0-1.0 based on evidence strength and quantity]

**Scope:** [global | repo]

**Tags:** [category tags]

**Level:** [0 for direct patterns, 1+ for meta-learnings]
```

### Step 4: Check for Meta-Learnings

Look for opportunities to synthesize existing learnings:

- Multiple level-0 learnings that share a theme
- Patterns across different repositories suggesting global preferences
- Evolution of learnings over time

### Step 5: User Approval

After presenting findings, ask the user to approve which learnings to create.
Format the request clearly:

```text
## Proposed Events

I found the following patterns. Approve to add them to the event store:

1. [x] Learning: "User prefers Zod for validation"
   - Link 3 boxes as evidence
   - Confidence: 0.85, Scope: global

2. [x] Learning: "This repo uses functional patterns"
   - Link 2 boxes as evidence
   - Confidence: 0.78, Scope: repo

3. [ ] Update existing learning_001 confidence to 0.92
   - 2 new supporting boxes found

Which should I add? (all / numbers / none)
```

### Step 6: Emit Events

For approved items, generate and append events:

```bash
# Example: Emit LearningCreated
cat >> ~/.claude/analytics/boxes.jsonl << 'EOF'
{"event":"LearningCreated","id":"learning_XXX","ts":"2026-01-22T15:00:00Z","insight":"User prefers Zod for validation","confidence":0.85,"scope":"global","tags":["validation","typescript"],"level":0}
EOF

# Example: Emit EvidenceLinked
cat >> ~/.claude/analytics/boxes.jsonl << 'EOF'
{"event":"EvidenceLinked","id":"link_XXX","ts":"2026-01-22T15:00:00Z","learning_id":"learning_001","box_id":"sess_abc123_5","strength":0.9,"relationship":"supports"}
EOF

# Example: Emit LearningUpdated
cat >> ~/.claude/analytics/boxes.jsonl << 'EOF'
{"event":"LearningUpdated","id":"lupdate_XXX","ts":"2026-01-22T15:00:00Z","learning_id":"learning_001","updates":{"confidence":0.92}}
EOF

# Example: Emit AnalysisCompleted
cat >> ~/.claude/analytics/boxes.jsonl << 'EOF'
{"event":"AnalysisCompleted","id":"analysis_XXX","ts":"2026-01-22T15:00:00Z","through_ts":"2026-01-22T14:30:00Z","stats":{"boxes_analyzed":47,"learnings_created":3,"learnings_updated":2,"links_created":12}}
EOF
```

### ID Generation

Use these patterns for IDs:

- `learning_NNN` — Sequential learning number
- `link_NNN` — Sequential link number
- `llink_NNN` — Sequential learning link number
- `lupdate_NNN` — Sequential learning update number
- `analysis_NNN` — Sequential analysis number

Find the next number:

```bash
jq -s '[.[] | select(.id | startswith("learning_"))] | length + 1' ~/.claude/analytics/boxes.jsonl
```

---

## Event Schemas

### LearningCreated

```json
{
  "event": "LearningCreated",
  "id": "learning_001",
  "ts": "2026-01-22T15:00:00Z",
  "insight": "User prefers Zod for validation",
  "confidence": 0.85,
  "scope": "global",
  "tags": ["validation", "typescript"],
  "level": 0
}
```

### EvidenceLinked

```json
{
  "event": "EvidenceLinked",
  "id": "link_001",
  "ts": "2026-01-22T15:00:00Z",
  "learning_id": "learning_001",
  "box_id": "sess_abc123_5",
  "strength": 0.9,
  "relationship": "supports"
}
```

Relationship types:

- `supports` — Positive evidence
- `contradicts` — Counter-evidence
- `tangential` — Related but not direct

### LearningLinked

For meta-learnings that synthesize others:

```json
{
  "event": "LearningLinked",
  "id": "llink_001",
  "ts": "2026-01-22T16:00:00Z",
  "parent_learning_id": "learning_010",
  "child_learning_id": "learning_001",
  "relationship": "synthesizes"
}
```

Relationship types:

- `synthesizes` — Parent combines children
- `refines` — Parent is more specific
- `supersedes` — Parent replaces child

### LearningUpdated

```json
{
  "event": "LearningUpdated",
  "id": "lupdate_001",
  "ts": "2026-01-22T16:00:00Z",
  "learning_id": "learning_001",
  "updates": {
    "confidence": 0.92
  }
}
```

### AnalysisCompleted

```json
{
  "event": "AnalysisCompleted",
  "id": "analysis_001",
  "ts": "2026-01-22T15:00:00Z",
  "through_ts": "2026-01-22T14:30:00Z",
  "stats": {
    "boxes_analyzed": 47,
    "learnings_created": 3,
    "learnings_updated": 2,
    "links_created": 12
  }
}
```

---

## Guidelines

### Confidence Scoring

| Evidence                   | Confidence |
| -------------------------- | ---------- |
| 5+ strong supporting boxes | 0.9+       |
| 3-4 supporting boxes       | 0.75-0.85  |
| 2 supporting boxes         | 0.6-0.7    |
| 1 box (needs confirmation) | 0.4-0.5    |
| Contradicting evidence     | Reduce 0.2 |

### Scope Assignment

- `global` — Pattern applies across all repos
- `repo` — Pattern specific to one repo

Use repo scope when:

- Pattern only appears in one repository
- It reflects project-specific conventions
- Different repos show different patterns

### Evidence Strength

| Strength | Meaning                           |
| -------- | --------------------------------- |
| 0.9-1.0  | Direct, clear support             |
| 0.7-0.8  | Good support with minor ambiguity |
| 0.5-0.6  | Moderate support                  |
| 0.3-0.4  | Tangential relation               |
| 0.1-0.2  | Weak connection                   |

### Meta-Learning Criteria

Create level 1+ learnings when:

- 3+ level-0 learnings share a common theme
- A higher-level pattern explains multiple specific patterns
- User behavior suggests a general principle

---

## Example Analysis Output

```text
# Box Analysis Results

Analyzed 47 boxes since last analysis (2026-01-20).

## Pattern 1: Zod Preference for Validation

**Insight:** User consistently prefers Zod for schema validation over alternatives

**Evidence:**
- sess_abc_2: Choice - Chose Zod over Yup (strength: 0.9, supports)
- sess_def_1: Choice - Chose Zod over joi (strength: 0.9, supports)
- sess_ghi_3: Assumption - Assumed Zod for validation (strength: 0.7, supports)

**Confidence:** 0.85
**Scope:** global
**Tags:** validation, typescript, libraries
**Level:** 0

---

## Pattern 2: Functional Style in API Repo

**Insight:** This repository follows functional programming patterns

**Evidence:**
- sess_jkl_5: Decision - Used pure functions (strength: 0.8, supports)
- sess_mno_2: Choice - Chose fp-ts over class-based (strength: 0.9, supports)

**Confidence:** 0.78
**Scope:** repo
**Tags:** architecture, functional
**Level:** 0

---

## Proposed Events

Approve to add (respond with numbers or 'all'):

1. [x] Create learning: "User prefers Zod for validation"
2. [x] Create learning: "API repo uses functional patterns"
3. [ ] Update learning_003 confidence to 0.88 (2 new evidence)
```
