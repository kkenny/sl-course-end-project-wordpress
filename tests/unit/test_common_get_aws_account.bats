#!/usr/bin/env bats

# Test suite for get_aws_account function

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
    
    export COMMON_DIR="$PROJECT_ROOT"
    export SCRIPT_DIR="$PROJECT_ROOT"
    
    # Prevent sourcing _set_profile.sh
    if [ -f "${PROJECT_ROOT}/_set_profile.sh" ]; then
        mv "${PROJECT_ROOT}/_set_profile.sh" "${PROJECT_ROOT}/_set_profile.sh.bak" 2>/dev/null || true
    fi
    
    source "${PROJECT_ROOT}/_common.sh"
}

teardown() {
    # Restore _set_profile.sh if it was backed up
    if [ -f "${PROJECT_ROOT}/_set_profile.sh.bak" ]; then
        mv "${PROJECT_ROOT}/_set_profile.sh.bak" "${PROJECT_ROOT}/_set_profile.sh" 2>/dev/null || true
    fi
    
    # Restore original aws function if it was mocked
    unset -f aws 2>/dev/null || true
}

@test "get_aws_account returns account ID when AWS CLI succeeds" {
    # Mock aws command to return valid account ID
    aws() {
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ] && [ "$3" = "--query" ] && [ "$4" = "Account" ]; then
            echo "123456789012"
            return 0
        fi
        return 1
    }
    export -f aws
    
    run get_aws_account
    [ "$status" -eq 0 ]
    [[ "$output" =~ "123456789012" ]]
}

@test "get_aws_account returns error when AWS CLI fails" {
    # Mock aws command to fail
    aws() {
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
            return 1
        fi
        return 1
    }
    export -f aws
    
    run get_aws_account
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Could not retrieve AWS account" ]]
}

@test "get_aws_account returns error when response is empty" {
    # Mock aws command to return empty
    aws() {
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ] && [ "$3" = "--query" ] && [ "$4" = "Account" ]; then
            echo ""
            return 0
        fi
        return 1
    }
    export -f aws
    
    run get_aws_account
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Could not retrieve AWS account" ]]
}

