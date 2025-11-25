#!/usr/bin/env bats

# Test suite for get_latest_ami function

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

@test "get_latest_ami returns default AMI when AWS CLI fails" {
    # Create a mock aws script in a temp directory and add it to PATH
    MOCK_AWS_DIR="${BATS_TMPDIR}/mock_aws"
    mkdir -p "$MOCK_AWS_DIR"
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-images" ] && [ "$3" = "--owners" ]; then
    exit 1
fi
exit 1
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    export PATH="${MOCK_AWS_DIR}:$PATH"
    
    run get_latest_ami "us-east-1"
    [ "$status" -eq 0 ]
    # The function outputs warning to stderr, AMI to stdout
    # The output should contain the default AMI (may have warning on stderr mixed in)
    [[ "$output" =~ "ami-0c55b159cbfafe1f0" ]]
}

@test "get_latest_ami returns default AMI when no AMIs found" {
    # Create a mock aws script that returns empty
    MOCK_AWS_DIR="${BATS_TMPDIR}/mock_aws"
    mkdir -p "$MOCK_AWS_DIR"
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-images" ] && [ "$3" = "--owners" ]; then
    # Return empty stdout (the function checks for empty)
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    export PATH="${MOCK_AWS_DIR}:$PATH"
    
    run get_latest_ami "us-east-1"
    [ "$status" -eq 0 ]
    # Function outputs warning to stderr, default AMI to stdout
    [[ "$output" =~ "ami-0c55b159cbfafe1f0" ]]
}

@test "get_latest_ami returns default AMI when response is None" {
    # Create a mock aws script that returns "None"
    MOCK_AWS_DIR="${BATS_TMPDIR}/mock_aws"
    mkdir -p "$MOCK_AWS_DIR"
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-images" ] && [ "$3" = "--owners" ]; then
    echo "None"
    exit 0
fi
exit 1
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    export PATH="${MOCK_AWS_DIR}:$PATH"
    
    run get_latest_ami "us-east-1"
    [ "$status" -eq 0 ]
    # Function outputs warning to stderr, default AMI to stdout
    [[ "$output" =~ "ami-0c55b159cbfafe1f0" ]]
}

@test "get_latest_ami returns AMI ID when AWS CLI succeeds" {
    # Create a mock aws script that returns valid AMI ID
    MOCK_AWS_DIR="${BATS_TMPDIR}/mock_aws"
    mkdir -p "$MOCK_AWS_DIR"
    # Use a simpler approach - check if us-west-2 appears in arguments
    cat > "${MOCK_AWS_DIR}/aws" <<'EOFMOCK'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-images" ] && [ "$3" = "--owners" ]; then
    # Check if us-west-2 appears in the arguments (simple string check)
    args="$@"
    if echo "$args" | grep -q "us-west-2"; then
        echo "ami-1234567890abcdef0"
        exit 0
    fi
fi
exit 1
EOFMOCK
    chmod +x "${MOCK_AWS_DIR}/aws"
    export PATH="${MOCK_AWS_DIR}:$PATH"
    
    run get_latest_ami "us-west-2"
    [ "$status" -eq 0 ]
    # Output should contain the AMI ID (may have warning on stderr)
    echo "$output" | grep -q "ami-1234567890abcdef0"
    [ $? -eq 0 ]
}

@test "get_latest_ami uses default region when not specified" {
    # Create a mock aws script
    MOCK_AWS_DIR="${BATS_TMPDIR}/mock_aws"
    mkdir -p "$MOCK_AWS_DIR"
    # Use a simpler approach - check if us-east-1 appears in arguments (default region)
    cat > "${MOCK_AWS_DIR}/aws" <<'EOFMOCK'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-images" ] && [ "$3" = "--owners" ]; then
    # Check if us-east-1 appears in the arguments (simple string check)
    args="$@"
    if echo "$args" | grep -q "us-east-1"; then
        echo "ami-9876543210fedcba0"
        exit 0
    fi
fi
exit 1
EOFMOCK
    chmod +x "${MOCK_AWS_DIR}/aws"
    export PATH="${MOCK_AWS_DIR}:$PATH"
    
    run get_latest_ami
    [ "$status" -eq 0 ]
    # Output should contain the AMI ID (may have warning on stderr)
    echo "$output" | grep -q "ami-9876543210fedcba0"
    [ $? -eq 0 ]
}

@test "get_latest_ami uses custom default AMI when provided" {
    # Create a mock aws script that fails
    MOCK_AWS_DIR="${BATS_TMPDIR}/mock_aws"
    mkdir -p "$MOCK_AWS_DIR"
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-images" ] && [ "$3" = "--owners" ]; then
    exit 1
fi
exit 1
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    export PATH="${MOCK_AWS_DIR}:$PATH"
    
    run get_latest_ami "us-east-1" "ami-custom-default"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ami-custom-default" ]]
}

