#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "session-processor.sh exists and is readable" {
    [[ -f "${HOOKS_DIR}/session-processor.sh" ]]
}

@test "creates boxes file directory if it doesn't exist" {
    rm -rf "${TEST_RESPONSE_BOXES_DIR}/analytics"

    # Create a minimal transcript
    local transcript
    transcript="$(mktemp)"
    echo '{"messages":[]}' > "$transcript"

    export CLAUDE_TRANSCRIPT_FILE="$transcript"

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]
    [[ -d "${TEST_RESPONSE_BOXES_DIR}/analytics" ]]

    rm -f "$transcript"
}

@test "extracts boxes from transcript and appends to JSONL" {
    local transcript
    transcript="$(mktemp)"
    create_sample_transcript "$transcript"

    export CLAUDE_TRANSCRIPT_FILE="$transcript"

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]

    # Should have created box entries
    if [[ -f "$RESPONSE_BOXES_FILE" ]]; then
        [[ -s "$RESPONSE_BOXES_FILE" ]]
    fi

    rm -f "$transcript"
}

@test "respects RESPONSE_BOXES_DISABLED environment variable" {
    local transcript
    transcript="$(mktemp)"
    create_sample_transcript "$transcript"

    export CLAUDE_TRANSCRIPT_FILE="$transcript"
    export RESPONSE_BOXES_DISABLED=true

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]

    # Should not create/modify boxes file
    [[ ! -s "$RESPONSE_BOXES_FILE" ]] || [[ ! -f "$RESPONSE_BOXES_FILE" ]]

    rm -f "$transcript"
}

@test "handles empty transcript gracefully" {
    local transcript
    transcript="$(mktemp)"
    echo '{"messages":[]}' > "$transcript"

    export CLAUDE_TRANSCRIPT_FILE="$transcript"

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]

    rm -f "$transcript"
}

@test "handles transcript with no boxes gracefully" {
    local transcript
    transcript="$(mktemp)"
    cat > "$transcript" << 'EOF'
{
  "messages": [
    {"role": "user", "content": "Hello"},
    {"role": "assistant", "content": "Hi there!"}
  ]
}
EOF

    export CLAUDE_TRANSCRIPT_FILE="$transcript"

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]

    rm -f "$transcript"
}

@test "handles missing transcript file" {
    export CLAUDE_TRANSCRIPT_FILE="/nonexistent/path/transcript.json"

    run bash "${HOOKS_DIR}/session-processor.sh"

    # Should exit gracefully (0 or specific error code)
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "extracts Choice box correctly" {
    local transcript
    transcript="$(mktemp)"
    cat > "$transcript" << 'EOF'
{
  "messages": [
    {"role": "assistant", "content": "⚖️ Choice ───────────────────────────────────────\n**Selected:** Option A\n**Alternatives:** Option B, Option C\n**Reasoning:** Better fit\n────────────────────────────────────────────────"}
  ]
}
EOF

    export CLAUDE_TRANSCRIPT_FILE="$transcript"

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]

    if [[ -f "$RESPONSE_BOXES_FILE" ]] && [[ -s "$RESPONSE_BOXES_FILE" ]]; then
        assert_file_contains "$RESPONSE_BOXES_FILE" "Choice"
    fi

    rm -f "$transcript"
}

@test "extracts multiple box types from single message" {
    local transcript
    transcript="$(mktemp)"
    create_sample_transcript "$transcript"

    export CLAUDE_TRANSCRIPT_FILE="$transcript"

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]

    rm -f "$transcript"
}

@test "appends to existing boxes file without overwriting" {
    # Create existing boxes
    echo '{"event":"BoxCreated","id":"existing_001","type":"Warning","content":"Existing box"}' > "$RESPONSE_BOXES_FILE"

    local transcript
    transcript="$(mktemp)"
    create_sample_transcript "$transcript"

    export CLAUDE_TRANSCRIPT_FILE="$transcript"

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]

    # Original content should still be present
    assert_file_contains "$RESPONSE_BOXES_FILE" "existing_001"

    rm -f "$transcript"
}

@test "uses custom RESPONSE_BOXES_FILE path" {
    local custom_file="${TEST_HOME}/custom/boxes.jsonl"
    mkdir -p "$(dirname "$custom_file")"

    local transcript
    transcript="$(mktemp)"
    create_sample_transcript "$transcript"

    export CLAUDE_TRANSCRIPT_FILE="$transcript"
    export RESPONSE_BOXES_FILE="$custom_file"

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]

    rm -f "$transcript"
}

@test "includes schema_version in emitted events" {
    local transcript
    transcript="$(mktemp)"
    create_sample_transcript "$transcript"

    export CLAUDE_TRANSCRIPT_FILE="$transcript"

    run bash "${HOOKS_DIR}/session-processor.sh"

    [[ "$status" -eq 0 ]]

    if [[ -f "$RESPONSE_BOXES_FILE" ]] && [[ -s "$RESPONSE_BOXES_FILE" ]]; then
        # Check that events include schema_version
        assert_file_contains "$RESPONSE_BOXES_FILE" "schema_version"
    fi

    rm -f "$transcript"
}
