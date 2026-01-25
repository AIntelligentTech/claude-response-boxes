#!/usr/bin/env bash
# Test helper for Response Boxes bats tests

# Get the directory of the test file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# Source directories
HOOKS_DIR="${PROJECT_ROOT}/agents/claude-code/hooks"
FIXTURES_DIR="${TEST_DIR}/fixtures"

# Temporary test directories
export TEST_HOME=""
export TEST_RESPONSE_BOXES_DIR=""
export TEST_CLAUDE_DIR=""

# Setup a clean test environment
setup_test_env() {
    TEST_HOME="$(mktemp -d)"
    TEST_RESPONSE_BOXES_DIR="${TEST_HOME}/.response-boxes"
    TEST_CLAUDE_DIR="${TEST_HOME}/.claude"

    mkdir -p "${TEST_RESPONSE_BOXES_DIR}/analytics"
    mkdir -p "${TEST_CLAUDE_DIR}/hooks"
    mkdir -p "${TEST_CLAUDE_DIR}/settings"

    # Override HOME for scripts
    export HOME="$TEST_HOME"
    export RESPONSE_BOXES_FILE="${TEST_RESPONSE_BOXES_DIR}/analytics/boxes.jsonl"
}

# Cleanup test environment
teardown_test_env() {
    if [[ -n "$TEST_HOME" ]] && [[ -d "$TEST_HOME" ]]; then
        rm -rf "$TEST_HOME"
    fi
}

# Create a sample boxes.jsonl with test data
create_sample_boxes() {
    local boxes_file="${1:-$RESPONSE_BOXES_FILE}"
    cat > "$boxes_file" << 'EOF'
{"event":"BoxCreated","id":"box_001","type":"Assumption","content":"Assumed TypeScript","metadata":{"repo":"test/repo"},"timestamp":"2026-01-20T10:00:00Z","schema_version":1}
{"event":"BoxCreated","id":"box_002","type":"Choice","content":"Chose Zod over Yup","metadata":{"repo":"test/repo"},"timestamp":"2026-01-21T10:00:00Z","schema_version":1}
{"event":"BoxCreated","id":"box_003","type":"Warning","content":"No rate limiting","metadata":{"repo":"test/api"},"timestamp":"2026-01-22T10:00:00Z","schema_version":1}
{"event":"LearningCreated","id":"learn_001","title":"User prefers Zod","confidence":0.85,"evidence":["box_002"],"timestamp":"2026-01-22T12:00:00Z","schema_version":1}
EOF
}

# Create a sample transcript for testing session processor
create_sample_transcript() {
    local transcript_file="$1"
    cat > "$transcript_file" << 'EOF'
{
  "messages": [
    {
      "role": "user",
      "content": "Add validation to the form"
    },
    {
      "role": "assistant",
      "content": "I'll add validation using Zod.\n\n⚖️ Choice ───────────────────────────────────────\n**Selected:** Zod for schema validation\n**Alternatives:** Yup, io-ts\n**Reasoning:** Better TypeScript inference\n────────────────────────────────────────────────\n\nHere's the implementation:\n\n```typescript\nconst schema = z.object({ email: z.string().email() });\n```\n\n🏁 Completion ───────────────────────────────────\n**Request:** Add validation to the form\n**Completed:** Added Zod schema validation\n**Confidence:** 9/10\n**Gaps:** None\n**Improve:** Could add more specific error messages\n────────────────────────────────────────────────"
    }
  ]
}
EOF
}

# Assert that a file contains expected content
assert_file_contains() {
    local file="$1"
    local pattern="$2"

    if ! grep -q "$pattern" "$file"; then
        echo "Expected file '$file' to contain pattern: $pattern"
        echo "File contents:"
        cat "$file"
        return 1
    fi
}

# Assert that a file does not contain content
assert_file_not_contains() {
    local file="$1"
    local pattern="$2"

    if grep -q "$pattern" "$file"; then
        echo "Expected file '$file' NOT to contain pattern: $pattern"
        echo "File contents:"
        cat "$file"
        return 1
    fi
}

# Assert JSONL file has expected number of lines
assert_jsonl_line_count() {
    local file="$1"
    local expected="$2"
    local actual

    actual="$(wc -l < "$file" | tr -d ' ')"

    if [[ "$actual" -ne "$expected" ]]; then
        echo "Expected $expected lines in '$file', got $actual"
        echo "File contents:"
        cat "$file"
        return 1
    fi
}

# Assert JSON value equals expected
assert_json_value() {
    local json="$1"
    local path="$2"
    local expected="$3"
    local actual

    actual="$(echo "$json" | jq -r "$path")"

    if [[ "$actual" != "$expected" ]]; then
        echo "Expected $path to equal '$expected', got '$actual'"
        return 1
    fi
}
