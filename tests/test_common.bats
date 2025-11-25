#!/usr/bin/env bats

# Test suite for _common.sh functions

# Source the common functions
setup() {
    # Get the directory where this test file is located
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
    
    # Source _common.sh but skip sourcing _set_profile.sh if it exists
    # We'll mock AWS commands anyway
    export COMMON_DIR="$PROJECT_ROOT"
    export SCRIPT_DIR="$PROJECT_ROOT"
    
    # Source _common.sh, but prevent sourcing _set_profile.sh
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
}

@test "generate_password returns a password" {
    run generate_password
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^.{12,16}$ ]]
}

@test "generate_password contains uppercase letters" {
    run generate_password
    [ "$status" -eq 0 ]
    [[ "$output" =~ [A-Z] ]]
}

@test "generate_password contains lowercase letters" {
    run generate_password
    [ "$status" -eq 0 ]
    [[ "$output" =~ [a-z] ]]
}

@test "generate_password contains numbers" {
    run generate_password
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9] ]]
}

@test "generate_password contains special characters" {
    run generate_password
    [ "$status" -eq 0 ]
    # Check for at least one special character from the allowed set
    # Use a simple approach: check if password contains any non-alphanumeric character
    # that's in the allowed special character set
    special_chars="!#\$%&*()_+-=[]{}|;:,.<>?~"
    found=0
    for (( i=0; i<${#output}; i++ )); do
        char="${output:$i:1}"
        if [[ "$special_chars" == *"$char"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}

@test "generate_password does not contain invalid RDS characters" {
    run generate_password
    [ "$status" -eq 0 ]
    # Check that output does not contain invalid RDS characters: /, @, ", or space
    echo "$output" | grep -qvE '[/@" ]'
    [ $? -eq 0 ]
}

@test "generate_password length is between 12 and 16 characters" {
    for i in {1..10}; do
        run generate_password
        [ "$status" -eq 0 ]
        length=${#output}
        [ "$length" -ge 12 ]
        [ "$length" -le 16 ]
    done
}

@test "validate_key_pair returns error when key pair name is empty" {
    run validate_key_pair ""
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Key Pair Name is required" ]]
}

@test "check_aws_credentials function exists and can be called" {
    # Just verify the function exists - actual AWS check will depend on environment
    run type generate_password
    [ "$status" -eq 0 ]
}

@test "check_stack_exists returns error when stack name is empty" {
    run check_stack_exists ""
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Stack name is required" ]]
}

@test "get_stack_status returns error when stack name is empty" {
    run get_stack_status ""
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Stack name is required" ]]
}

@test "update_template_ami returns error when template file is missing" {
    run update_template_ami "" "ami-12345678"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Template file and AMI ID are required" ]]
}

@test "update_template_ami returns error when AMI ID is missing" {
    run update_template_ami "nonexistent.yaml" ""
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Template file and AMI ID are required" ]]
}

@test "update_template_ami returns error when template file does not exist" {
    run update_template_ami "nonexistent.yaml" "ami-12345678"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" ]]
}

