#!/usr/bin/env bats

# Test suite for check_stack_exists function with AWS CLI mocking

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

@test "check_stack_exists returns success when stack exists" {
    # Create a mock aws script that returns valid stack data
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ] && [ "$3" = "--stack-name" ] && [ "$4" = "test-stack" ]; then
    echo '{"Stacks":[{"StackName":"test-stack"}]}'
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run check_stack_exists "test-stack" "us-east-1"
    [ "$status" -eq 0 ]
}

@test "check_stack_exists returns error when stack does not exist" {
    # Create a mock aws script that returns error (stack not found)
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ] && [ "$3" = "--stack-name" ] && [ "$4" = "nonexistent-stack" ]; then
    exit 1
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run check_stack_exists "nonexistent-stack" "us-east-1"
    [ "$status" -ne 0 ]
}

@test "check_stack_exists uses default region when not specified" {
    # Create a mock aws script that checks for default region
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ] && [ "$3" = "--stack-name" ] && [ "$4" = "test-stack" ] && [ "$5" = "--region" ] && [ "$6" = "us-east-1" ]; then
    echo '{"Stacks":[{"StackName":"test-stack"}]}'
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run check_stack_exists "test-stack"
    [ "$status" -eq 0 ]
}

@test "check_stack_exists handles custom region" {
    # Create a mock aws script that checks for custom region
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ] && [ "$3" = "--stack-name" ] && [ "$4" = "test-stack" ] && [ "$5" = "--region" ] && [ "$6" = "us-west-2" ]; then
    echo '{"Stacks":[{"StackName":"test-stack"}]}'
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run check_stack_exists "test-stack" "us-west-2"
    [ "$status" -eq 0 ]
}

@test "check_stack_exists handles AWS CLI failure" {
    # Create a mock aws script that always fails
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "cloudformation" ] && [ "$2" = "describe-stacks" ]; then
    exit 1
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run check_stack_exists "test-stack" "us-east-1"
    [ "$status" -ne 0 ]
}

