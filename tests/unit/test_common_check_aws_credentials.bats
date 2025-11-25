#!/usr/bin/env bats

# Test suite for check_aws_credentials function with AWS CLI mocking

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

@test "check_aws_credentials returns success when credentials are valid" {
    # Create a mock aws script that succeeds
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
    echo '{"Account":"123456789012"}'
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run check_aws_credentials
    [ "$status" -eq 0 ]
}

@test "check_aws_credentials returns error when credentials are invalid" {
    # Create a mock aws script that fails
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
    exit 1
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run check_aws_credentials
    [ "$status" -ne 0 ]
    [[ "$output" =~ "AWS credentials not configured" ]]
}

@test "check_aws_credentials returns error when AWS CLI fails" {
    # Create a mock aws script that always fails
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
    echo "Error: Unable to locate credentials" >&2
    exit 255
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run check_aws_credentials
    [ "$status" -ne 0 ]
    [[ "$output" =~ "AWS credentials not configured" ]]
}

