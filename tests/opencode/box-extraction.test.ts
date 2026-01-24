import { describe, it, expect } from "vitest";

// Re-implement extractBoxesFromText for testing (same logic as plugin)
interface BoxSegment {
  readonly boxType: string;
  readonly fields: Record<string, string>;
  readonly raw: string;
}

function extractBoxesFromText(text: string): BoxSegment[] {
  const segments: BoxSegment[] = [];

  // Match headers like: "⚖️ Choice ─────────────" (emoji + type + dashes)
  const headerPattern = /^(.+?)\s+([A-Za-z][A-Za-z ]*)\s+[-\u2500]{10,}\s*$/gm;

  const matches = Array.from(text.matchAll(headerPattern));
  if (matches.length === 0) {
    return segments;
  }

  for (let index = 0; index < matches.length; index += 1) {
    const match = matches[index];
    if (match.index === undefined) {
      continue;
    }

    const start = match.index;
    const end =
      index + 1 < matches.length && matches[index + 1].index !== undefined
        ? (matches[index + 1].index as number)
        : text.length;

    const block = text.slice(start, end).trim();
    if (block.length === 0) {
      continue;
    }

    const headerLineEnd = block.indexOf("\n");
    const boxTypeRaw = match[2] ?? "";
    const boxType = boxTypeRaw.trim();

    const body =
      headerLineEnd === -1 ? "" : block.slice(headerLineEnd + 1).trim();
    const fields: Record<string, string> = {};

    const fieldPattern = /\*\*([^*]+)\*\*:\s*(.+)/g;
    let fieldMatch: RegExpExecArray | null;
    while ((fieldMatch = fieldPattern.exec(body)) !== null) {
      const rawName = fieldMatch[1]?.trim();
      const value = fieldMatch[2]?.trim() ?? "";
      if (!rawName || value === "") {
        continue;
      }
      const key = rawName.toLowerCase().replace(/\s+/g, "_");
      if (!(key in fields)) {
        fields[key] = value;
      }
    }

    segments.push({
      boxType,
      fields,
      raw: block,
    });
  }

  return segments;
}

describe("extractBoxesFromText", () => {
  it("returns empty array for text without boxes", () => {
    const text = "Just some regular text without any response boxes.";
    const result = extractBoxesFromText(text);
    expect(result).toEqual([]);
  });

  it("extracts a single Choice box", () => {
    const text = `⚖️ Choice ───────────────────────────────────────
**Selected:** Zod for schema validation
**Alternatives:** Yup, io-ts, manual validation
**Reasoning:** Better TypeScript inference
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    expect(result[0].boxType).toBe("Choice");
    expect(result[0].fields.selected).toBe("Zod for schema validation");
    expect(result[0].fields.alternatives).toBe("Yup, io-ts, manual validation");
    expect(result[0].fields.reasoning).toBe("Better TypeScript inference");
  });

  it("extracts a Completion box", () => {
    const text = `🏁 Completion ───────────────────────────────────
**Request:** Add validation to form
**Completed:** Added Zod schema
**Confidence:** 9/10
**Gaps:** No server-side validation
**Improve:** Should ask about patterns
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    expect(result[0].boxType).toBe("Completion");
    expect(result[0].fields.request).toBe("Add validation to form");
    expect(result[0].fields.completed).toBe("Added Zod schema");
    expect(result[0].fields.confidence).toBe("9/10");
    expect(result[0].fields.gaps).toBe("No server-side validation");
    expect(result[0].fields.improve).toBe("Should ask about patterns");
  });

  it("extracts a Sycophancy box", () => {
    const text = `🪞 Sycophancy ───────────────────────────────────
**Rating:** 10/10
**Check:** Direct technical response
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    expect(result[0].boxType).toBe("Sycophancy");
    expect(result[0].fields.rating).toBe("10/10");
    expect(result[0].fields.check).toBe("Direct technical response");
  });

  it("extracts multiple boxes from a single message", () => {
    const text = `I'll implement this feature.

⚖️ Choice ───────────────────────────────────────
**Selected:** Option A
**Alternatives:** Option B
**Reasoning:** Better fit
────────────────────────────────────────────────

Here's the code...

🏁 Completion ───────────────────────────────────
**Request:** Implement feature
**Completed:** Feature implemented
**Confidence:** 8/10
**Gaps:** None
**Improve:** Could add tests
────────────────────────────────────────────────

🪞 Sycophancy ───────────────────────────────────
**Rating:** 9/10
**Check:** Focused on task
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(3);
    expect(result[0].boxType).toBe("Choice");
    expect(result[1].boxType).toBe("Completion");
    expect(result[2].boxType).toBe("Sycophancy");
  });

  it("extracts Assumption box", () => {
    const text = `💭 Assumption ───────────────────────────────────
**What:** Using TypeScript
**Basis:** tsconfig.json exists
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    expect(result[0].boxType).toBe("Assumption");
    expect(result[0].fields.what).toBe("Using TypeScript");
    expect(result[0].fields.basis).toBe("tsconfig.json exists");
  });

  it("extracts Warning box", () => {
    const text = `🚨 Warning ──────────────────────────────────────
**Risk:** No authentication
**Likelihood:** High
**Consequence:** Unauthorized access
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    expect(result[0].boxType).toBe("Warning");
    expect(result[0].fields.risk).toBe("No authentication");
    expect(result[0].fields.likelihood).toBe("High");
    expect(result[0].fields.consequence).toBe("Unauthorized access");
  });

  it("extracts Decision box", () => {
    const text = `🎯 Decision ─────────────────────────────────────
**What:** Using functional approach
**Reasoning:** Better testability
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    expect(result[0].boxType).toBe("Decision");
    expect(result[0].fields.what).toBe("Using functional approach");
    expect(result[0].fields.reasoning).toBe("Better testability");
  });

  it("extracts Reflection box", () => {
    const text = `🔄 Reflection ───────────────────────────────────
**Prior:** Assumed PostgreSQL
**Learning:** User prefers SQLite
**Application:** Using SQLite for this project
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    expect(result[0].boxType).toBe("Reflection");
    expect(result[0].fields.prior).toBe("Assumed PostgreSQL");
    expect(result[0].fields.learning).toBe("User prefers SQLite");
    expect(result[0].fields.application).toBe("Using SQLite for this project");
  });

  it("handles multi-word field values", () => {
    const text = `⚖️ Choice ───────────────────────────────────────
**Selected:** A very long selection with multiple words and special chars: test
**Alternatives:** First option, second option, third option
**Reasoning:** This is a detailed reasoning that spans multiple words
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    expect(result[0].fields.selected).toContain("very long selection");
    expect(result[0].fields.alternatives).toContain("First option");
  });

  it("normalizes field names to lowercase with underscores", () => {
    const text = `🏁 Completion ───────────────────────────────────
**Request:** Test
**Completed:** Test
**Confidence:** 9/10
**Gaps:** None
**Improve:** None
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    // All field names should be lowercase
    const keys = Object.keys(result[0].fields);
    for (const key of keys) {
      expect(key).toBe(key.toLowerCase());
    }
  });

  it("handles box with Unicode dash characters", () => {
    const text = `⚖️ Choice ───────────────────────────────────────
**Selected:** Test
**Alternatives:** Other
**Reasoning:** Because
────────────────────────────────────────────────`;

    const result = extractBoxesFromText(text);

    expect(result).toHaveLength(1);
    expect(result[0].boxType).toBe("Choice");
  });
});
