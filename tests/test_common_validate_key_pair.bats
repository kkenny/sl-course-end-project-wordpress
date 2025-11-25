#!/usr/bin/env bats

# Test suite for validate_key_pair function with enhanced testing

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
    
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

@test "validate_key_pair returns success when key pair exists" {
    # Mock aws command to return success
    aws() {
        if [ "$1" = "ec2" ] && [ "$2" = "describe-key-pairs" ] && [ "$3" = "--key-names" ] && [ "$4" = "test-key" ]; then
            echo "test-key"
            return 0
        fi
        return 1
    }
    export -f aws
    
    run validate_key_pair "test-key" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "validate_key_pair returns error when key pair does not exist" {
    # Mock aws command to return error (key pair not found)
    aws() {
        if [ "$1" = "ec2" ] && [ "$2" = "describe-key-pairs" ] && [ "$3" = "--key-names" ]; then
            return 1
        fi
        if [ "$1" = "ec2" ] && [ "$2" = "describe-key-pairs" ] && [ "$3" = "--region" ]; then
            echo "key1"
            echo "key2"
            return 0
        fi
        return 1
    }
    export -f aws
    
    run validate_key_pair "nonexistent-key" "us-east-1"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "does not exist" ]]
}

@test "validate_key_pair uses default region when not specified" {
    # Mock aws command
    aws() {
        if [ "$1" = "ec2" ] && [ "$2" = "describe-key-pairs" ] && [ "$3" = "--key-names" ] && [ "$4" = "test-key" ] && [ "$5" = "--region" ] && [ "$6" = "us-east-1" ]; then
            echo "test-key"
            return 0
        fi
        return 1
    }
    export -f aws
    
    run validate_key_pair "test-key"
    [ "$status" -eq 0 ]
}

@test "validate_key_pair handles custom region" {
    # Mock aws command
    aws() {
        if [ "$1" = "ec2" ] && [ "$2" = "describe-key-pairs" ] && [ "$3" = "--key-names" ] && [ "$4" = "test-key" ] && [ "$5" = "--region" ] && [ "$6" = "us-west-2" ]; then
            echo "test-key"
            return 0
        fi
        return 1
    }
    export -f aws
    
    run validate_key_pair "test-key" "us-west-2"
    [ "$status" -eq 0 ]
}

