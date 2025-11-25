#!/usr/bin/env bats

# Test suite for get_stack_status function with AWS CLI mocking

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
    
    # Create a temporary directory for mock aws executable
    MOCK_AWS_DIR="${BATS_TMPDIR}/mock_aws"
    mkdir -p "$MOCK_AWS_DIR"
    export PATH="${MOCK_AWS_DIR}:$PATH" # Prepend mock dir to PATH
}

teardown() {
    # Restore _set_profile.sh if it was backed up
    if [ -f "${PROJECT_ROOT}/_set_profile.sh.bak" ]; then
        mv "${PROJECT_ROOT}/_set_profile.sh.bak" "${PROJECT_ROOT}/_set_profile.sh" 2>/dev/null || true
    fi
    
    # Clean up mock aws executable and restore PATH
    rm -rf "${MOCK_AWS_DIR}"
    export PATH="${PATH#${MOCK_AWS_DIR}:}"
}

@test "get_stack_status returns CREATE_COMPLETE status" {
    # Create a mock aws script that returns CREATE_COMPLETE
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ] && [ "$3" = "--stack-name" ] && [ "$4" = "test-stack" ]; then
    echo "CREATE_COMPLETE"
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run get_stack_status "test-stack" "us-east-1"
    [ "$status" -eq 0 ]
    [ "$output" = "CREATE_COMPLETE" ]
}

@test "get_stack_status returns UPDATE_IN_PROGRESS status" {
    # Create a mock aws script that returns UPDATE_IN_PROGRESS
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ] && [ "$3" = "--stack-name" ] && [ "$4" = "test-stack" ]; then
    echo "UPDATE_IN_PROGRESS"
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run get_stack_status "test-stack" "us-east-1"
    [ "$status" -eq 0 ]
    [ "$output" = "UPDATE_IN_PROGRESS" ]
}

@test "get_stack_status returns empty when stack does not exist" {
    # Create a mock aws script that fails (stack not found)
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ] && [ "$3" = "--stack-name" ] && [ "$4" = "nonexistent-stack" ]; then
    exit 1
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run get_stack_status "nonexistent-stack" "us-east-1"
    [ "$status" -eq 0 ]  # Function returns 0 but outputs empty string
    [ -z "$output" ]
}

@test "get_stack_status uses default region when not specified" {
    # Create a mock aws script that checks for default region
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ] && [ "$3" = "--stack-name" ] && [ "$4" = "test-stack" ] && [ "$5" = "--region" ] && [ "$6" = "us-east-1" ]; then
    echo "CREATE_COMPLETE"
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run get_stack_status "test-stack"
    [ "$status" -eq 0 ]
    [ "$output" = "CREATE_COMPLETE" ]
}

@test "get_stack_status handles custom region" {
    # Create a mock aws script that checks for custom region
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ] && [ "$3" = "--stack-name" ] && [ "$4" = "test-stack" ] && [ "$5" = "--region" ] && [ "$6" = "us-west-2" ]; then
    echo "UPDATE_COMPLETE"
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run get_stack_status "test-stack" "us-west-2"
    [ "$status" -eq 0 ]
    [ "$output" = "UPDATE_COMPLETE" ]
}

@test "get_stack_status handles AWS CLI failure gracefully" {
    # Create a mock aws script that always fails
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ]; then
    exit 1
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run get_stack_status "test-stack" "us-east-1"
    [ "$status" -eq 0 ]  # Function returns 0 but outputs empty string
    [ -z "$output" ]
}

