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

@test "create-ami.sh shows help with -h flag" {
    run "${PROJECT_ROOT}/create-ami.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "--stack-name" ]]
}

@test "create-ami.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/create-ami.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "create-ami.sh rejects unknown option" {
    run "${PROJECT_ROOT}/create-ami.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown option" ]]
}

@test "create-ami.sh accepts stack-name argument" {
    run "${PROJECT_ROOT}/create-ami.sh" -s test-stack 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "create-ami.sh accepts region argument" {
    run "${PROJECT_ROOT}/create-ami.sh" -s test-stack -r us-west-2 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "create-ami.sh accepts name-prefix argument" {
    run "${PROJECT_ROOT}/create-ami.sh" -s test-stack -n my-prefix 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "create-ami.sh accepts description argument" {
    run "${PROJECT_ROOT}/create-ami.sh" -s test-stack -d "Test description" 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "update-launch-template-with-ami.sh shows help with -h flag" {
    run "${PROJECT_ROOT}/update-launch-template-with-ami.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "--stack-name" ]]
}

@test "update-launch-template-with-ami.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/update-launch-template-with-ami.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "update-launch-template-with-ami.sh rejects unknown option" {
    run "${PROJECT_ROOT}/update-launch-template-with-ami.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown option" ]]
}

@test "update-launch-template-with-ami.sh accepts stack-name argument" {
    run "${PROJECT_ROOT}/update-launch-template-with-ami.sh" -s test-stack 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "update-launch-template-with-ami.sh accepts region argument" {
    run "${PROJECT_ROOT}/update-launch-template-with-ami.sh" -s test-stack -r us-west-2 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "update-launch-template-with-ami.sh accepts ami-id argument" {
    run "${PROJECT_ROOT}/update-launch-template-with-ami.sh" -s test-stack -a ami-12345678 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "update-launch-template-with-ami.sh accepts ami-file argument" {
    run "${PROJECT_ROOT}/update-launch-template-with-ami.sh" -s test-stack -f ami-file.txt 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/create-key-pair.sh shows help with -h flag" {
    run "${PROJECT_ROOT}/utils/create-key-pair.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "--key-pair" ]]
}

@test "utils/create-key-pair.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/utils/create-key-pair.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "utils/create-key-pair.sh accepts key-pair argument" {
    run "${PROJECT_ROOT}/utils/create-key-pair.sh" -k test-key 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/create-key-pair.sh accepts region argument" {
    run "${PROJECT_ROOT}/utils/create-key-pair.sh" -k test-key -r us-west-2 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/create-key-pair.sh accepts legacy positional argument" {
    run "${PROJECT_ROOT}/utils/create-key-pair.sh" test-key 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/get-stack-info.sh shows help with -h flag" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "--stack-name" ]]
}

@test "utils/get-stack-info.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "utils/get-stack-info.sh rejects unknown option" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" --unknown-option
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown option" ]]
}

@test "utils/get-stack-info.sh accepts stack-name argument" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -s test-stack 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/get-stack-info.sh accepts region argument" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -s test-stack -r us-west-2 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/get-stack-info.sh accepts events flag" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -s test-stack -e 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/get-stack-info.sh accepts resources flag" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -s test-stack -R 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/get-stack-info.sh accepts outputs flag" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -s test-stack -o 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/get-stack-info.sh accepts parameters flag" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -s test-stack -p 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/get-stack-info.sh accepts instances flag" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -s test-stack -i 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/get-stack-info.sh accepts database flag" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -s test-stack -d 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

@test "utils/get-stack-info.sh accepts all flag" {
    run "${PROJECT_ROOT}/utils/get-stack-info.sh" -s test-stack -a 2>&1 || true
    [[ ! "$output" =~ "Unknown option" ]] || [ "$status" -eq 0 ]
}

