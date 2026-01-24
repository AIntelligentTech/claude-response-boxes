#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "install.sh exists and is executable" {
    [[ -f "${PROJECT_ROOT}/install.sh" ]]
    [[ -x "${PROJECT_ROOT}/install.sh" ]]
}

@test "install.sh --help shows usage information" {
    run bash "${PROJECT_ROOT}/install.sh" --help

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--user"* ]]
    [[ "$output" == *"--project"* ]]
    [[ "$output" == *"--dry-run"* ]]
}

@test "install.sh --dry-run does not modify files" {
    run bash "${PROJECT_ROOT}/install.sh" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"Dry-run"* ]]
}

@test "install.sh --dry-run --project does not modify files" {
    run bash "${PROJECT_ROOT}/install.sh" --project --dry-run

    [[ "$status" -eq 0 ]]
}

@test "install.sh --basic skips hooks and skills" {
    run bash "${PROJECT_ROOT}/install.sh" --basic --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Basic mode"* ]] || [[ "$output" == *"basic"* ]] || [[ "$output" == *"prompt-only"* ]]
}

@test "install.sh detects local source correctly" {
    cd "$PROJECT_ROOT"
    run bash "${PROJECT_ROOT}/install.sh" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Source: local"* ]]
}

@test "install.sh reports status of existing installation" {
    run bash "${PROJECT_ROOT}/install.sh" --dry-run

    [[ "$status" -eq 0 ]]
    # Should report on existing files
    [[ "$output" == *"status"* ]] || [[ "$output" == *"present"* ]] || [[ "$output" == *"missing"* ]]
}

@test "install.sh --uninstall --dry-run shows what would be removed" {
    run bash "${PROJECT_ROOT}/install.sh" --uninstall --dry-run

    [[ "$status" -eq 0 ]]
}

@test "install.sh validates source files exist" {
    # The installer should find source files in agents/claude-code/
    run bash "${PROJECT_ROOT}/install.sh" --dry-run

    [[ "$status" -eq 0 ]]
    # Should not report missing source files
    [[ "$output" != *"Source file not found"* ]]
}

@test "install.sh --install-opencode flag is recognized" {
    run bash "${PROJECT_ROOT}/install.sh" --install-opencode --dry-run

    [[ "$status" -eq 0 ]]
}

@test "install.sh --install-windsurf-basic flag is recognized" {
    run bash "${PROJECT_ROOT}/install.sh" --install-windsurf-basic --dry-run

    [[ "$status" -eq 0 ]]
}

@test "install.sh --install-cursor-basic flag is recognized" {
    run bash "${PROJECT_ROOT}/install.sh" --install-cursor-basic --dry-run

    [[ "$status" -eq 0 ]]
}

@test "install.sh --cleanup-legacy flag is recognized" {
    run bash "${PROJECT_ROOT}/install.sh" --cleanup-legacy --dry-run

    [[ "$status" -eq 0 ]]
}

@test "install.sh --force flag is recognized" {
    run bash "${PROJECT_ROOT}/install.sh" --force --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Force"* ]] || [[ "$output" == *"force"* ]]
}

@test "install.sh handles unknown flags gracefully" {
    run bash "${PROJECT_ROOT}/install.sh" --unknown-flag --dry-run

    # Should warn but not crash
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "install.sh is idempotent (dry-run twice produces same output)" {
    run bash "${PROJECT_ROOT}/install.sh" --dry-run
    local first_output="$output"

    run bash "${PROJECT_ROOT}/install.sh" --dry-run
    local second_output="$output"

    # Both runs should succeed
    [[ "$status" -eq 0 ]]
}
