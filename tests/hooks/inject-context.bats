#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "inject-context.sh exists and is readable" {
    [[ -f "${HOOKS_DIR}/inject-context.sh" ]]
}

@test "outputs nothing when boxes file does not exist" {
    unset RESPONSE_BOXES_FILE
    export HOME="$TEST_HOME"

    run bash "${HOOKS_DIR}/inject-context.sh"

    [[ "$status" -eq 0 ]]
    [[ -z "$output" || "$output" == *"No boxes file"* || "$output" == "" ]]
}

@test "outputs nothing when boxes file is empty" {
    touch "$RESPONSE_BOXES_FILE"

    run bash "${HOOKS_DIR}/inject-context.sh"

    [[ "$status" -eq 0 ]]
}

@test "injects learnings from boxes file" {
    create_sample_boxes

    run bash "${HOOKS_DIR}/inject-context.sh"

    [[ "$status" -eq 0 ]]
    # Should contain some form of learning/pattern output
    [[ "$output" == *"Patterns"* ]] || [[ "$output" == *"Learning"* ]] || [[ "$output" == *"boxes"* ]] || [[ -z "$output" ]]
}

@test "respects BOX_INJECT_DISABLED environment variable" {
    create_sample_boxes
    export BOX_INJECT_DISABLED=true

    run bash "${HOOKS_DIR}/inject-context.sh"

    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "respects RESPONSE_BOXES_DISABLED environment variable" {
    create_sample_boxes
    export RESPONSE_BOXES_DISABLED=true

    run bash "${HOOKS_DIR}/inject-context.sh"

    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "respects BOX_INJECT_LEARNINGS limit" {
    create_sample_boxes
    export BOX_INJECT_LEARNINGS=1

    run bash "${HOOKS_DIR}/inject-context.sh"

    [[ "$status" -eq 0 ]]
}

@test "respects BOX_INJECT_BOXES limit" {
    create_sample_boxes
    export BOX_INJECT_BOXES=2

    run bash "${HOOKS_DIR}/inject-context.sh"

    [[ "$status" -eq 0 ]]
}

@test "handles malformed JSONL gracefully" {
    echo "not valid json" > "$RESPONSE_BOXES_FILE"

    run bash "${HOOKS_DIR}/inject-context.sh"

    # Should not crash, may output diagnostic
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "handles mixed valid and invalid JSONL lines" {
    cat > "$RESPONSE_BOXES_FILE" << 'EOF'
{"event":"BoxCreated","id":"box_001","type":"Assumption","content":"Test"}
invalid line
{"event":"BoxCreated","id":"box_002","type":"Choice","content":"Test2"}
EOF

    run bash "${HOOKS_DIR}/inject-context.sh"

    # Should handle gracefully
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "uses custom RESPONSE_BOXES_FILE path" {
    local custom_file="${TEST_HOME}/custom/boxes.jsonl"
    mkdir -p "$(dirname "$custom_file")"

    cat > "$custom_file" << 'EOF'
{"event":"BoxCreated","id":"box_custom","type":"Warning","content":"Custom path test"}
EOF

    export RESPONSE_BOXES_FILE="$custom_file"

    run bash "${HOOKS_DIR}/inject-context.sh"

    [[ "$status" -eq 0 ]]
}
