#!/usr/bin/env bats

# Test suite for update_template_ami function with actual file operations

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
    
    # Create a temporary test template file
    TEST_TEMPLATE="${BATS_TMPDIR}/test-template.yaml"
    cat > "$TEST_TEMPLATE" <<EOF
Resources:
  TestInstance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: ami-09887f71d98a72a5c
EOF
    
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
}

@test "update_template_ami updates AMI ID in template" {
    local new_ami="ami-1234567890abcdef0"
    
    run update_template_ami "$TEST_TEMPLATE" "$new_ami"
    assert_success
    
    # Check that the AMI was updated
    run grep -q "$new_ami" "$TEST_TEMPLATE"
    assert_success
    refute_output --partial "ami-09887f71d98a72a5c"
}

@test "update_template_ami handles multiple AMI references" {
    # Create template with multiple AMI references
    cat > "$TEST_TEMPLATE" <<EOF
Resources:
  Instance1:
    Properties:
      ImageId: ami-09887f71d98a72a5c
  Instance2:
    Properties:
      ImageId: ami-09887f71d98a72a5c
EOF
    
    local new_ami="ami-1234567890abcdef0"
    
    run update_template_ami "$TEST_TEMPLATE" "$new_ami"
    assert_success
    
    # Count occurrences of new AMI (should be 2)
    count=$(grep -o "$new_ami" "$TEST_TEMPLATE" | wc -l | tr -d ' ')
    assert [ "$count" -eq 2 ]
}

