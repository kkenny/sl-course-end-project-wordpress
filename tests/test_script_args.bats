#!/usr/bin/env bats

# Test suite for script argument parsing

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
    
    export COMMON_DIR="$PROJECT_ROOT"
    export SCRIPT_DIR="$PROJECT_ROOT"
    
    # Prevent sourcing _set_profile.sh
    if [ -f "${PROJECT_ROOT}/_set_profile.sh" ]; then
        mv "${PROJECT_ROOT}/_set_profile.sh" "${PROJECT_ROOT}/_set_profile.sh.bak" 2>/dev/null || true
    fi
}

teardown() {
    # Restore _set_profile.sh if it was backed up
    if [ -f "${PROJECT_ROOT}/_set_profile.sh.bak" ]; then
        mv "${PROJECT_ROOT}/_set_profile.sh.bak" "${PROJECT_ROOT}/_set_profile.sh" 2>/dev/null || true
    fi
}

@test "deploy-prod.sh shows help with -h flag" {
    run "${PROJECT_ROOT}/deploy-prod.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "--help" ]]
}

@test "deploy-prod.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/deploy-prod.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "deploy-prod.sh rejects unknown option" {
    run "${PROJECT_ROOT}/deploy-prod.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown option" ]]
}

@test "deploy-prod.sh accepts stack-name argument" {
    # This will fail later but should parse the argument correctly
    run "${PROJECT_ROOT}/deploy-prod.sh" -s test-stack 2>&1 || true
    # The script will fail because it needs AWS credentials, but argument parsing should work
    # We just check it doesn't fail with "Unknown option"
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "deploy-prod.sh accepts username argument" {
    run "${PROJECT_ROOT}/deploy-prod.sh" -u testuser 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "deploy-prod.sh accepts email argument" {
    run "${PROJECT_ROOT}/deploy-prod.sh" -e test@example.com 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "deploy-prod.sh accepts key-pair argument" {
    run "${PROJECT_ROOT}/deploy-prod.sh" -k test-key 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "deploy-prod.sh accepts region argument" {
    run "${PROJECT_ROOT}/deploy-prod.sh" -r us-west-2 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "deploy-prod.sh accepts instance-type argument" {
    run "${PROJECT_ROOT}/deploy-prod.sh" -t t3.large 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "deploy-prod.sh accepts ami-id argument" {
    run "${PROJECT_ROOT}/deploy-prod.sh" -a ami-12345678 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "deploy-prod.sh accepts prompt-password flag" {
    run "${PROJECT_ROOT}/deploy-prod.sh" -p 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "deploy-dev.sh shows help with -h flag" {
    run "${PROJECT_ROOT}/deploy-dev.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "destroy-stack.sh shows help with -h flag" {
    run "${PROJECT_ROOT}/destroy-stack.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "destroy-stack.sh accepts stack-name argument" {
    run "${PROJECT_ROOT}/destroy-stack.sh" -s test-stack 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "destroy-stack.sh accepts region argument" {
    run "${PROJECT_ROOT}/destroy-stack.sh" -r us-west-2 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/check-stack-status.sh shows help with -h flag" {
    run "${PROJECT_ROOT}/utils/check-stack-status.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "utils/check-stack-status.sh accepts stack-name argument" {
    run "${PROJECT_ROOT}/utils/check-stack-status.sh" -s test-stack 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/troubleshoot-wordpress.sh shows help with -h flag" {
    run "${PROJECT_ROOT}/utils/troubleshoot-wordpress.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "utils/troubleshoot-wordpress.sh accepts stack-name argument" {
    run "${PROJECT_ROOT}/utils/troubleshoot-wordpress.sh" -s test-stack 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

