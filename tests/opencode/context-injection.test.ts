import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { promises as fs } from "fs";
import * as os from "os";
import * as path from "path";

// Re-implement projectContextFromEvents for testing
interface BoxCreatedEvent {
  readonly event: "BoxCreated";
  readonly id: string;
  readonly ts: string;
  readonly box_type: string;
  readonly fields: Record<string, string>;
  readonly context: Record<string, unknown>;
  readonly initial_score: number;
  readonly schema_version: number;
}

async function projectContextFromEvents(
  boxesFile: string,
): Promise<string | null> {
  let raw: string;
  try {
    raw = await fs.readFile(boxesFile, { encoding: "utf8" });
  } catch {
    return null;
  }

  const lines = raw.split(/\r?\n/);
  const boxes: BoxCreatedEvent[] = [];
  const learnings: { insight: string; confidence: number; ts: string }[] = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed === "") {
      continue;
    }

    let parsed: any;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      continue;
    }

    const eventType =
      typeof parsed.event === "string" ? parsed.event : "BoxCreated";

    if (eventType === "BoxCreated") {
      const ts =
        typeof parsed.ts === "string" ? parsed.ts : new Date(0).toISOString();
      const boxType =
        typeof parsed.box_type === "string"
          ? parsed.box_type
          : typeof parsed.type === "string"
            ? parsed.type
            : "Unknown";
      const fields =
        parsed.fields && typeof parsed.fields === "object"
          ? (parsed.fields as Record<string, string>)
          : {};

      boxes.push({
        event: "BoxCreated",
        id: typeof parsed.id === "string" ? parsed.id : `oc_legacy_${ts}`,
        ts,
        box_type: boxType,
        fields,
        context:
          parsed.context && typeof parsed.context === "object"
            ? (parsed.context as Record<string, unknown>)
            : {},
        initial_score:
          typeof parsed.initial_score === "number" ? parsed.initial_score : 50,
        schema_version:
          typeof parsed.schema_version === "number" ? parsed.schema_version : 0,
      });
    } else if (eventType === "LearningCreated") {
      const insight = typeof parsed.insight === "string" ? parsed.insight : "";
      if (insight === "") {
        continue;
      }
      const confidence =
        typeof parsed.confidence === "number" ? parsed.confidence : 0.0;
      const ts =
        typeof parsed.ts === "string" ? parsed.ts : new Date(0).toISOString();
      learnings.push({ insight, confidence, ts });
    }
  }

  if (boxes.length === 0 && learnings.length === 0) {
    return null;
  }

  const maxLearnings = 3;
  const maxBoxes = 5;

  learnings.sort((a, b) => {
    if (b.confidence !== a.confidence) {
      return b.confidence - a.confidence;
    }
    return (new Date(b.ts).getTime() || 0) - (new Date(a.ts).getTime() || 0);
  });

  boxes.sort((a, b) => {
    return (new Date(b.ts).getTime() || 0) - (new Date(a.ts).getTime() || 0);
  });

  const topLearnings = learnings.slice(0, maxLearnings);
  const topBoxes = boxes.slice(0, maxBoxes);

  const linesOut: string[] = [];
  linesOut.push("PRIOR SESSION LEARNINGS (from Response Boxes):");
  linesOut.push("");

  if (topLearnings.length > 0) {
    linesOut.push("Patterns (AI-synthesized learnings)");
    for (const l of topLearnings) {
      const conf = Number.isFinite(l.confidence)
        ? l.confidence.toFixed(2)
        : "--";
      linesOut.push(`• [${conf}] ${l.insight}`);
    }
    linesOut.push("");
  }

  if (topBoxes.length > 0) {
    linesOut.push("Recent notable boxes");
    for (const box of topBoxes) {
      const entries = Object.entries(box.fields);
      const summaryValues = entries
        .slice(0, 2)
        .map(([key, value]) => `${key}: ${value}`);
      const summary = summaryValues.join(" | ");
      linesOut.push(`• ${box.box_type}: ${summary}`);
    }
    linesOut.push("");
  }

  return linesOut.join("\n");
}

describe("projectContextFromEvents", () => {
  let testDir: string;
  let boxesFile: string;

  beforeEach(async () => {
    testDir = await fs.mkdtemp(path.join(os.tmpdir(), "response-boxes-test-"));
    boxesFile = path.join(testDir, "boxes.jsonl");
  });

  afterEach(async () => {
    try {
      await fs.rm(testDir, { recursive: true });
    } catch {
      // Ignore cleanup errors
    }
  });

  it("returns null when file does not exist", async () => {
    const result = await projectContextFromEvents(
      "/nonexistent/path/boxes.jsonl",
    );
    expect(result).toBeNull();
  });

  it("returns null for empty file", async () => {
    await fs.writeFile(boxesFile, "");
    const result = await projectContextFromEvents(boxesFile);
    expect(result).toBeNull();
  });

  it("projects boxes from JSONL file", async () => {
    const events = [
      {
        event: "BoxCreated",
        id: "box_001",
        ts: "2026-01-20T10:00:00Z",
        box_type: "Choice",
        fields: { selected: "Zod", alternatives: "Yup" },
        schema_version: 1,
      },
      {
        event: "BoxCreated",
        id: "box_002",
        ts: "2026-01-21T10:00:00Z",
        box_type: "Warning",
        fields: { risk: "No auth", likelihood: "High" },
        schema_version: 1,
      },
    ];

    const content = events.map((e) => JSON.stringify(e)).join("\n");
    await fs.writeFile(boxesFile, content);

    const result = await projectContextFromEvents(boxesFile);

    expect(result).not.toBeNull();
    expect(result).toContain("PRIOR SESSION LEARNINGS");
    expect(result).toContain("Recent notable boxes");
    expect(result).toContain("Choice");
    expect(result).toContain("Warning");
  });

  it("projects learnings from JSONL file", async () => {
    const events = [
      {
        event: "LearningCreated",
        id: "learn_001",
        insight: "User prefers Zod",
        confidence: 0.85,
        ts: "2026-01-21T12:00:00Z",
        schema_version: 1,
      },
    ];

    const content = events.map((e) => JSON.stringify(e)).join("\n");
    await fs.writeFile(boxesFile, content);

    const result = await projectContextFromEvents(boxesFile);

    expect(result).not.toBeNull();
    expect(result).toContain("Patterns");
    expect(result).toContain("User prefers Zod");
    expect(result).toContain("0.85");
  });

  it("sorts learnings by confidence (highest first)", async () => {
    const events = [
      {
        event: "LearningCreated",
        id: "learn_001",
        insight: "Low confidence",
        confidence: 0.5,
        ts: "2026-01-20T10:00:00Z",
        schema_version: 1,
      },
      {
        event: "LearningCreated",
        id: "learn_002",
        insight: "High confidence",
        confidence: 0.95,
        ts: "2026-01-20T09:00:00Z",
        schema_version: 1,
      },
      {
        event: "LearningCreated",
        id: "learn_003",
        insight: "Medium confidence",
        confidence: 0.75,
        ts: "2026-01-20T11:00:00Z",
        schema_version: 1,
      },
    ];

    const content = events.map((e) => JSON.stringify(e)).join("\n");
    await fs.writeFile(boxesFile, content);

    const result = await projectContextFromEvents(boxesFile);

    expect(result).not.toBeNull();
    // High confidence should appear before low confidence
    const highIndex = result!.indexOf("High confidence");
    const lowIndex = result!.indexOf("Low confidence");
    expect(highIndex).toBeLessThan(lowIndex);
  });

  it("sorts boxes by timestamp (most recent first)", async () => {
    const events = [
      {
        event: "BoxCreated",
        id: "box_001",
        ts: "2026-01-18T10:00:00Z",
        box_type: "Oldest",
        fields: { test: "old" },
        schema_version: 1,
      },
      {
        event: "BoxCreated",
        id: "box_002",
        ts: "2026-01-22T10:00:00Z",
        box_type: "Newest",
        fields: { test: "new" },
        schema_version: 1,
      },
      {
        event: "BoxCreated",
        id: "box_003",
        ts: "2026-01-20T10:00:00Z",
        box_type: "Middle",
        fields: { test: "mid" },
        schema_version: 1,
      },
    ];

    const content = events.map((e) => JSON.stringify(e)).join("\n");
    await fs.writeFile(boxesFile, content);

    const result = await projectContextFromEvents(boxesFile);

    expect(result).not.toBeNull();
    // Newest should appear before oldest
    const newestIndex = result!.indexOf("Newest");
    const oldestIndex = result!.indexOf("Oldest");
    expect(newestIndex).toBeLessThan(oldestIndex);
  });

  it("limits boxes to maxBoxes", async () => {
    const events = [];
    for (let i = 0; i < 10; i++) {
      events.push({
        event: "BoxCreated",
        id: `box_${i}`,
        ts: `2026-01-${20 + i}T10:00:00Z`,
        box_type: `Type${i}`,
        fields: { test: `value${i}` },
        schema_version: 1,
      });
    }

    const content = events.map((e) => JSON.stringify(e)).join("\n");
    await fs.writeFile(boxesFile, content);

    const result = await projectContextFromEvents(boxesFile);

    expect(result).not.toBeNull();
    // Should only show 5 boxes (maxBoxes default)
    const boxMatches = result!.match(/• Type\d+:/g);
    expect(boxMatches?.length).toBeLessThanOrEqual(5);
  });

  it("limits learnings to maxLearnings", async () => {
    const events = [];
    for (let i = 0; i < 10; i++) {
      events.push({
        event: "LearningCreated",
        id: `learn_${i}`,
        insight: `Learning ${i}`,
        confidence: 0.5 + i * 0.05,
        ts: `2026-01-${20 + i}T10:00:00Z`,
        schema_version: 1,
      });
    }

    const content = events.map((e) => JSON.stringify(e)).join("\n");
    await fs.writeFile(boxesFile, content);

    const result = await projectContextFromEvents(boxesFile);

    expect(result).not.toBeNull();
    // Should only show 3 learnings (maxLearnings default)
    const learningMatches = result!.match(/• \[\d+\.\d+\] Learning/g);
    expect(learningMatches?.length).toBeLessThanOrEqual(3);
  });

  it("handles malformed JSON lines gracefully", async () => {
    const content = `{"event":"BoxCreated","id":"box_001","ts":"2026-01-20T10:00:00Z","box_type":"Valid","fields":{"test":"value"},"schema_version":1}
invalid json line
{"event":"BoxCreated","id":"box_002","ts":"2026-01-21T10:00:00Z","box_type":"AlsoValid","fields":{"test":"value2"},"schema_version":1}`;

    await fs.writeFile(boxesFile, content);

    const result = await projectContextFromEvents(boxesFile);

    expect(result).not.toBeNull();
    expect(result).toContain("Valid");
    expect(result).toContain("AlsoValid");
  });

  it("handles legacy format (type instead of box_type)", async () => {
    const events = [
      {
        event: "BoxCreated",
        id: "box_001",
        ts: "2026-01-20T10:00:00Z",
        type: "LegacyType",
        fields: { test: "value" },
      },
    ];

    const content = events.map((e) => JSON.stringify(e)).join("\n");
    await fs.writeFile(boxesFile, content);

    const result = await projectContextFromEvents(boxesFile);

    expect(result).not.toBeNull();
    expect(result).toContain("LegacyType");
  });

  it("handles events without explicit event field (treats as BoxCreated)", async () => {
    const events = [
      {
        id: "box_001",
        ts: "2026-01-20T10:00:00Z",
        box_type: "Implicit",
        fields: { test: "value" },
      },
    ];

    const content = events.map((e) => JSON.stringify(e)).join("\n");
    await fs.writeFile(boxesFile, content);

    const result = await projectContextFromEvents(boxesFile);

    expect(result).not.toBeNull();
    expect(result).toContain("Implicit");
  });
});
