#!/usr/bin/env bats

# Test suite for auto_select_key_pair function

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

@test "auto_select_key_pair returns single key pair automatically" {
    # Create a mock aws script that returns one key pair
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-key-pairs" ] && [ "$3" = "--region" ] && [ "$4" = "us-east-1" ] && [ "$5" = "--query" ] && [ "$6" = "KeyPairs[*].KeyName" ] && [ "$7" = "--output" ] && [ "$8" = "text" ]; then
    echo "my-key-pair"
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run auto_select_key_pair "us-east-1"
    [ "$status" -eq 0 ]
    # Function outputs messages to stderr, key pair name to stdout
    # The output should contain the key pair name (may have stderr messages mixed in)
    echo "$output" | grep -q "my-key-pair"
    [ $? -eq 0 ]
    # Also verify it's the actual return value (last non-empty line)
    last_line=$(echo "$output" | grep -v '^$' | tail -1)
    [ "$last_line" = "my-key-pair" ]
}

@test "auto_select_key_pair returns error when no key pairs found" {
    # Create a mock aws script that returns empty
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-key-pairs" ] && [ "$3" = "--region" ] && [ "$4" = "us-east-1" ] && [ "$5" = "--query" ] && [ "$6" = "KeyPairs[*].KeyName" ] && [ "$7" = "--output" ] && [ "$8" = "text" ]; then
    echo ""
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run auto_select_key_pair "us-east-1"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "No Key Pairs found" ]]
}

@test "auto_select_key_pair uses default region when not specified" {
    # Create a mock aws script that checks for default region
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-key-pairs" ] && [ "$3" = "--region" ] && [ "$4" = "us-east-1" ] && [ "$5" = "--query" ] && [ "$6" = "KeyPairs[*].KeyName" ] && [ "$7" = "--output" ] && [ "$8" = "text" ]; then
    echo "default-key"
    exit 0
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run auto_select_key_pair
    [ "$status" -eq 0 ]
    # Function outputs messages to stderr, key pair name to stdout
    # The output should contain the key pair name (may have stderr messages mixed in)
    echo "$output" | grep -q "default-key"
    [ $? -eq 0 ]
    # Also verify it's the actual return value (last non-empty line)
    last_line=$(echo "$output" | grep -v '^$' | tail -1)
    [ "$last_line" = "default-key" ]
}

@test "auto_select_key_pair handles AWS CLI failure" {
    # Create a mock aws script that fails
    cat > "${MOCK_AWS_DIR}/aws" <<'EOF'
#!/bin/bash
if [ "$1" = "ec2" ] && [ "$2" = "describe-key-pairs" ] && [ "$3" = "--region" ] && [ "$4" = "us-east-1" ] && [ "$5" = "--query" ] && [ "$6" = "KeyPairs[*].KeyName" ] && [ "$7" = "--output" ] && [ "$8" = "text" ]; then
    exit 1
fi
exec /usr/bin/aws "$@"
EOF
    chmod +x "${MOCK_AWS_DIR}/aws"
    
    run auto_select_key_pair "us-east-1"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "No Key Pairs found" ]]
}

