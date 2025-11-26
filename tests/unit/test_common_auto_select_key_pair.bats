#!/usr/bin/env bats

# Test suite for auto_select_key_pair function

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
    
    # Track test keys created during tests (for cleanup)
    export TEST_KEY_PAIRS_CREATED="${BATS_TMPDIR}/test_key_pairs_created.txt"
    touch "$TEST_KEY_PAIRS_CREATED"
}

teardown() {
    # Restore _set_profile.sh if it was backed up
    if [ -f "${PROJECT_ROOT}/_set_profile.sh.bak" ]; then
        mv "${PROJECT_ROOT}/_set_profile.sh.bak" "${PROJECT_ROOT}/_set_profile.sh" 2>/dev/null || true
    fi
    
    # Clean up test key pairs if they were created
    if [ -f "$TEST_KEY_PAIRS_CREATED" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                # Format: KEY_NAME:REGION:PEM_FILE
                KEY_NAME=$(echo "$line" | cut -d':' -f1)
                REGION=$(echo "$line" | cut -d':' -f2)
                PEM_FILE=$(echo "$line" | cut -d':' -f3)
                
                # Remove PEM file from filesystem
                if [ -n "$PEM_FILE" ] && [ -f "$PEM_FILE" ]; then
                    rm -f "$PEM_FILE" 2>/dev/null || true
                fi
                
                # Delete key pair from AWS (only if AWS credentials are available)
                if [ -n "$KEY_NAME" ] && [ -n "$REGION" ]; then
                    # Check if we have real AWS credentials (not mocked)
                    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
                        # Temporarily remove mock from PATH to use real AWS CLI
                        ORIGINAL_PATH="$PATH"
                        # Remove mock directory from PATH (handle both beginning and middle positions)
                        export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^${MOCK_AWS_DIR}$" | tr '\n' ':' | sed 's/:$//')
                        
                        # Delete the key pair from AWS
                        /usr/bin/aws ec2 delete-key-pair \
                            --key-name "$KEY_NAME" \
                            --region "$REGION" \
                            >/dev/null 2>&1 || true
                        
                        # Restore PATH
                        export PATH="$ORIGINAL_PATH"
                    fi
                fi
            fi
        done < "$TEST_KEY_PAIRS_CREATED"
        rm -f "$TEST_KEY_PAIRS_CREATED" 2>/dev/null || true
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

@test "auto_select_key_pair works with real AWS credentials when available" {
    # Skip if AWS credentials are not available
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        skip "AWS credentials not configured (AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY required)"
    fi
    
    # Temporarily remove mock from PATH to use real AWS CLI
    ORIGINAL_PATH="$PATH"
    # Remove mock directory from PATH (handle both beginning and middle positions)
    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^${MOCK_AWS_DIR}$" | tr '\n' ':' | sed 's/:$//')
    
    # Check if we can actually use AWS CLI
    if ! /usr/bin/aws sts get-caller-identity >/dev/null 2>&1; then
        export PATH="$ORIGINAL_PATH"
        skip "AWS credentials are invalid or expired"
    fi
    
    # Create a test key pair
    TEST_KEY_NAME="test-auto-select-$(date +%s)"
    TEST_REGION="${AWS_REGION:-us-east-1}"
    TEST_PEM_FILE="${PROJECT_ROOT}/${TEST_KEY_NAME}.pem"
    
    # Create the key pair
    if /usr/bin/aws ec2 create-key-pair \
        --key-name "$TEST_KEY_NAME" \
        --region "$TEST_REGION" \
        --query 'KeyMaterial' \
        --output text > "$TEST_PEM_FILE" 2>/dev/null; then
        
        chmod 400 "$TEST_PEM_FILE" 2>/dev/null || true
        
        # Track this key pair for cleanup
        echo "${TEST_KEY_NAME}:${TEST_REGION}:${TEST_PEM_FILE}" >> "$TEST_KEY_PAIRS_CREATED"
        
        # Test that auto_select_key_pair can find it
        # Note: auto_select_key_pair will use the real AWS CLI since we removed the mock from PATH
        run auto_select_key_pair "$TEST_REGION"
        [ "$status" -eq 0 ]
        
        # Verify the key pair name is in the output
        echo "$output" | grep -q "$TEST_KEY_NAME"
        [ $? -eq 0 ]
    else
        export PATH="$ORIGINAL_PATH"
        skip "Failed to create test key pair (may not have permissions)"
    fi
    
    # Restore PATH
    export PATH="$ORIGINAL_PATH"
}

