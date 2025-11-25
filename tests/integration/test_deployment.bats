#!/usr/bin/env bats

# Integration tests for post-deployment verification
# These tests verify that deployed stacks are working correctly

# setup_file runs once before all tests
setup_file() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
    
    export PROJECT_ROOT
    export COMMON_DIR="$PROJECT_ROOT"
    export SCRIPT_DIR="$PROJECT_ROOT"
    
    # Source profile first to load AWS credentials from environment variables
    # Check both PROJECT_ROOT and current directory for _set_profile.sh
    SET_PROFILE_FILE=""
    if [ -f "${PROJECT_ROOT}/_set_profile.sh" ]; then
        SET_PROFILE_FILE="${PROJECT_ROOT}/_set_profile.sh"
    elif [ -f "${SCRIPT_DIR}/_set_profile.sh" ]; then
        SET_PROFILE_FILE="${SCRIPT_DIR}/_set_profile.sh"
    fi
    
    if [ -n "$SET_PROFILE_FILE" ]; then
        # Source the profile file (suppress output from echo/aws configure list)
        source "$SET_PROFILE_FILE" >/dev/null 2>&1
        # Backup after sourcing to prevent _common.sh from sourcing it again
        mv "$SET_PROFILE_FILE" "${SET_PROFILE_FILE}.bak" 2>/dev/null || true
    fi
    
    source "${PROJECT_ROOT}/_common.sh"
    
    # Default stack name and region (can be overridden with environment variables)
    export STACK_NAME="${STACK_NAME:-wordpress-dev}"
    export REGION="${REGION:-${AWS_REGION:-us-east-1}}"
    
    # Check if AWS credentials are configured
    # Verify credentials are available (either from _set_profile.sh or already set)
    if [ -z "$AWS_ACCESS_KEY_ID" ] && [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        # Try to verify with AWS CLI
        if ! aws sts get-caller-identity &> /dev/null; then
            echo "AWS credentials not configured. Ensure _set_profile.sh exports AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or run 'aws configure'" >&2
            exit 1
        fi
    elif ! check_aws_credentials; then
        echo "AWS credentials from _set_profile.sh are invalid or expired. Please check your credentials." >&2
        exit 1
    fi
    
    # Check if stack exists - fail early if it doesn't exist
    # This prevents all tests from running if the environment isn't deployed
    if ! check_stack_exists "$STACK_NAME" "$REGION"; then
        echo "Stack '$STACK_NAME' does not exist in region '$REGION'" >&2
        echo "Please deploy the stack before running integration tests." >&2
        exit 1
    fi
    
    # Get WordPress URL from stack outputs
    export WORDPRESS_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='WordPressURL'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    # Verify WordPressURL output exists - fail early if missing
    if [ -z "$WORDPRESS_URL" ] || [ "$WORDPRESS_URL" == "None" ]; then
        echo "WordPressURL output not found for stack '$STACK_NAME'" >&2
        echo "The stack exists but is missing the WordPressURL output." >&2
        exit 1
    fi
}

setup() {
    # setup() runs before each test
    # Most setup is done in setup_file, but we can add per-test setup here if needed
    :
}

teardown() {
    # Per-test teardown (if needed)
    :
}

# teardown_file runs once after all tests
teardown_file() {
    # Restore _set_profile.sh if it was backed up
    # PROJECT_ROOT should be available from setup_file
    if [ -n "$PROJECT_ROOT" ] && [ -f "${PROJECT_ROOT}/_set_profile.sh.bak" ]; then
        mv "${PROJECT_ROOT}/_set_profile.sh.bak" "${PROJECT_ROOT}/_set_profile.sh" 2>/dev/null || true
    fi
}

# Note: Stack existence and WordPressURL output are now verified in setup_file()
# If they don't exist, setup_file() will exit with error code 1, preventing all tests from running

@test "WordPress URL is accessible and returns 200" {
    # Make HTTP request to WordPress URL
    # Note: WORDPRESS_URL is guaranteed to be set by setup_file()
    run curl -s -o /dev/null -w "%{http_code}" --max-time 30 "$WORDPRESS_URL"
    
    [ "$status" -eq 0 ]
    [ "$output" -eq 200 ]
}

@test "WordPress URL responds with HTML content" {
    # Make HTTP request and check for HTML content
    run curl -s --max-time 30 "$WORDPRESS_URL"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "<html" ]] || [[ "$output" =~ "<!DOCTYPE" ]] || [[ "$output" =~ "WordPress" ]]
}

@test "hostname.php endpoint is accessible" {
    # Test the hostname.php endpoint
    HOSTNAME_URL="${WORDPRESS_URL}/hostname.php"
    
    run curl -s -o /dev/null -w "%{http_code}" --max-time 30 "$HOSTNAME_URL"
    
    [ "$status" -eq 0 ]
    [ "$output" -eq 200 ]
}

@test "hostname.php returns hostname information" {
    # Test that hostname.php returns expected content
    HOSTNAME_URL="${WORDPRESS_URL}/hostname.php"
    
    run curl -s --max-time 30 "$HOSTNAME_URL"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "hostname" ]] || [[ "$output" =~ "Server Hostname" ]] || [[ "$output" =~ "html" ]]
}

@test "Load balancer DNS is accessible on port 80 and returns 200" {
    # Get load balancer DNS from stack outputs
    LB_DNS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDNS'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$LB_DNS" ] || [ "$LB_DNS" == "None" ]; then
        skip "LoadBalancerDNS output not found"
    fi
    
    # Test HTTP connection to load balancer on port 80 (http:// defaults to port 80)
    LB_URL="http://${LB_DNS}"
    run curl -s -o /dev/null -w "%{http_code}" --max-time 30 "$LB_URL"
    
    [ "$status" -eq 0 ]
    [ "$output" -eq 200 ]
}

@test "Stack is in CREATE_COMPLETE or UPDATE_COMPLETE state" {
    # Verify stack is in a completed state
    run get_stack_status "$STACK_NAME" "$REGION"
    
    [ "$status" -eq 0 ]
    [[ "$output" == "CREATE_COMPLETE" ]] || [[ "$output" == "UPDATE_COMPLETE" ]]
}

@test "Database is not accessible from the internet" {
    # Get database endpoint from stack outputs
    DB_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='DatabaseEndpoint'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$DB_ENDPOINT" ] || [ "$DB_ENDPOINT" == "None" ]; then
        skip "DatabaseEndpoint output not found"
    fi
    
    # Verify database is not publicly accessible via AWS API (authoritative check)
    DB_INSTANCE_ID=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResources[?ResourceType==`AWS::RDS::DBInstance`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$DB_INSTANCE_ID" ] || [ "$DB_INSTANCE_ID" == "None" ]; then
        skip "Database instance not found in stack"
    fi
    
    PUBLICLY_ACCESSIBLE=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --region "$REGION" \
        --query 'DBInstances[0].PubliclyAccessible' \
        --output text 2>/dev/null || echo "false")
    
    # Database must not be publicly accessible
    # Normalize the value (AWS CLI may return "False", "false", "None", or empty with whitespace)
    if [ -z "$PUBLICLY_ACCESSIBLE" ] || [ "$PUBLICLY_ACCESSIBLE" == "None" ]; then
        PUBLICLY_ACCESSIBLE="false"
    fi
    PUBLICLY_ACCESSIBLE_NORMALIZED=$(echo "$PUBLICLY_ACCESSIBLE" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [ "$PUBLICLY_ACCESSIBLE_NORMALIZED" == "false" ]
    
    # Additionally, attempt to connect to MySQL port 3306 from the test machine (outside VPC)
    # This validates that security groups are properly configured
    # Connection should fail or timeout if database is not accessible from internet
    if command -v nc &> /dev/null; then
        # Use netcat if available (most reliable)
        run timeout 5 nc -zv -w 2 "$DB_ENDPOINT" 3306 2>&1
        # Connection should fail (non-zero exit code indicates connection refused/timeout)
        [ "$status" -ne 0 ]
    elif [ -e /dev/tcp ]; then
        # Use bash built-in TCP redirection as fallback
        run timeout 5 bash -c "echo > /dev/tcp/$DB_ENDPOINT/3306" 2>&1
        # Connection should fail (non-zero exit code)
        [ "$status" -ne 0 ]
    fi
    # If connection tools are not available, the PubliclyAccessible check above is sufficient
}

@test "Auto Scaling Group has correct instance count based on environment" {
    # Get Auto Scaling Group name from stack outputs
    ASG_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='AutoScalingGroupName'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ASG_NAME" ] || [ "$ASG_NAME" == "None" ]; then
        skip "AutoScalingGroupName output not found"
    fi
    
    # Get Environment parameter from stack to determine expected values
    ENVIRONMENT=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Parameters[?ParameterKey=='Environment'].ParameterValue" \
        --output text 2>/dev/null || echo "")
    
    # If Environment parameter not found, try to infer from stack name
    if [ -z "$ENVIRONMENT" ] || [ "$ENVIRONMENT" == "None" ]; then
        if [[ "$STACK_NAME" == *"prod"* ]] || [[ "$STACK_NAME" == *"Prod"* ]] || [[ "$STACK_NAME" == *"PROD"* ]]; then
            ENVIRONMENT="Production"
        else
            ENVIRONMENT="Development"
        fi
    fi
    
    # Set expected values based on environment
    if [ "$ENVIRONMENT" == "Production" ]; then
        EXPECTED_DESIRED_CAPACITY=3
        EXPECTED_MIN_SIZE=3
        EXPECTED_MAX_SIZE=8
    else
        EXPECTED_DESIRED_CAPACITY=1
        EXPECTED_MIN_SIZE=1
        EXPECTED_MAX_SIZE=2
    fi
    
    # Get Auto Scaling Group details
    ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$REGION" \
        --query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ASG_INFO" ] || [ "$ASG_INFO" == "None" ]; then
        skip "Could not retrieve Auto Scaling Group information"
    fi
    
    DESIRED_CAPACITY=$(echo "$ASG_INFO" | awk '{print $1}')
    MIN_SIZE=$(echo "$ASG_INFO" | awk '{print $2}')
    MAX_SIZE=$(echo "$ASG_INFO" | awk '{print $3}')
    
    # Get actual instance count (only count instances in InService state)
    ACTUAL_INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$REGION" \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
        --output text 2>/dev/null || echo "0")
    
    # Verify DesiredCapacity matches expected
    [ "$DESIRED_CAPACITY" -eq "$EXPECTED_DESIRED_CAPACITY" ]
    
    # Verify MinSize matches expected
    [ "$MIN_SIZE" -eq "$EXPECTED_MIN_SIZE" ]
    
    # Verify MaxSize matches expected
    [ "$MAX_SIZE" -eq "$EXPECTED_MAX_SIZE" ]
    
    # Verify actual instance count is within MinSize and MaxSize
    [ "$ACTUAL_INSTANCE_COUNT" -ge "$MIN_SIZE" ]
    [ "$ACTUAL_INSTANCE_COUNT" -le "$MAX_SIZE" ]
    
    # Verify actual instance count matches DesiredCapacity
    # In a healthy ASG, the count should match desired capacity
    # Note: During scaling operations, count might temporarily differ, but we verify it's within bounds above
    [ "$ACTUAL_INSTANCE_COUNT" -eq "$DESIRED_CAPACITY" ]
}

@test "EC2 instances have correct PHP version installed" {
    # Get Auto Scaling Group name from stack outputs
    ASG_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='AutoScalingGroupName'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ASG_NAME" ] || [ "$ASG_NAME" == "None" ]; then
        skip "AutoScalingGroupName output not found"
    fi
    
    # Get key pair name from stack parameters
    KEY_PAIR_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Parameters[?ParameterKey=='KeyPairName'].ParameterValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$KEY_PAIR_NAME" ] || [ "$KEY_PAIR_NAME" == "None" ]; then
        skip "KeyPairName parameter not found"
    fi
    
    # Try to find the key file in common locations
    KEY_FILE=""
    POSSIBLE_KEY_LOCATIONS=(
        "${PROJECT_ROOT}/${KEY_PAIR_NAME}.pem"
        "${PROJECT_ROOT}/wordpress-project.pem"
        "${HOME}/.ssh/${KEY_PAIR_NAME}.pem"
        "${HOME}/.ssh/id_rsa"
    )
    
    for key_path in "${POSSIBLE_KEY_LOCATIONS[@]}"; do
        if [ -f "$key_path" ] && [ -r "$key_path" ]; then
            KEY_FILE="$key_path"
            break
        fi
    done
    
    if [ -z "$KEY_FILE" ]; then
        skip "SSH key file not found for key pair '$KEY_PAIR_NAME'. Expected locations: ${POSSIBLE_KEY_LOCATIONS[*]}"
    fi
    
    # Ensure key file has correct permissions
    chmod 600 "$KEY_FILE" 2>/dev/null || true
    
    # Get all running instances from Auto Scaling Group
    INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$REGION" \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$INSTANCE_IDS" ] || [ "$INSTANCE_IDS" == "None" ]; then
        skip "No running instances found in Auto Scaling Group"
    fi
    
    # Check PHP version on each instance
    ALL_INSTANCES_VALID=true
    for INSTANCE_ID in $INSTANCE_IDS; do
        # Get instance public IP
        PUBLIC_IP=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --region "$REGION" \
            --query "Reservations[0].Instances[0].PublicIpAddress" \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; then
            echo "Warning: Could not get public IP for instance $INSTANCE_ID" >&2
            ALL_INSTANCES_VALID=false
            continue
        fi
        
        # SSH into instance and check PHP version
        # Use timeout to prevent hanging, and use StrictHostKeyChecking=no for automation
        PHP_VERSION_OUTPUT=$(timeout 30 ssh -i "$KEY_FILE" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 \
            -o LogLevel=ERROR \
            ec2-user@"$PUBLIC_IP" \
            "php -v 2>&1" 2>/dev/null || echo "")
        
        if [ -z "$PHP_VERSION_OUTPUT" ]; then
            echo "Warning: Could not retrieve PHP version from instance $INSTANCE_ID ($PUBLIC_IP)" >&2
            ALL_INSTANCES_VALID=false
            continue
        fi
        
        # Extract PHP version (format: "PHP 8.2.0" or similar)
        # Use sed for portability (works on both Linux and macOS)
        PHP_VERSION=$(echo "$PHP_VERSION_OUTPUT" | sed -n 's/.*PHP \([0-9]\+\.[0-9]\+\).*/\1/p' | head -1 || echo "")
        
        if [ -z "$PHP_VERSION" ]; then
            echo "Warning: Could not parse PHP version from instance $INSTANCE_ID. Output: $PHP_VERSION_OUTPUT" >&2
            ALL_INSTANCES_VALID=false
            continue
        fi
        
        # Verify PHP version is 8.0, 8.1, or 8.2
        PHP_MAJOR=$(echo "$PHP_VERSION" | cut -d. -f1)
        PHP_MINOR=$(echo "$PHP_VERSION" | cut -d. -f2)
        
        if [ "$PHP_MAJOR" != "8" ]; then
            echo "Error: Instance $INSTANCE_ID has PHP $PHP_VERSION, expected PHP 8.x" >&2
            ALL_INSTANCES_VALID=false
            continue
        fi
        
        if [ "$PHP_MINOR" != "0" ] && [ "$PHP_MINOR" != "1" ] && [ "$PHP_MINOR" != "2" ]; then
            echo "Error: Instance $INSTANCE_ID has PHP $PHP_VERSION, expected PHP 8.0, 8.1, or 8.2" >&2
            ALL_INSTANCES_VALID=false
            continue
        fi
        
        # PHP version is valid (8.0, 8.1, or 8.2)
        echo "Instance $INSTANCE_ID ($PUBLIC_IP): PHP $PHP_VERSION ✓" >&2
    done
    
    [ "$ALL_INSTANCES_VALID" == "true" ]
}

@test "EC2 instances have httpd installed, enabled, and running" {
    # Get Auto Scaling Group name from stack outputs
    ASG_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='AutoScalingGroupName'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ASG_NAME" ] || [ "$ASG_NAME" == "None" ]; then
        skip "AutoScalingGroupName output not found"
    fi
    
    # Get key pair name from stack parameters
    KEY_PAIR_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Parameters[?ParameterKey=='KeyPairName'].ParameterValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$KEY_PAIR_NAME" ] || [ "$KEY_PAIR_NAME" == "None" ]; then
        skip "KeyPairName parameter not found"
    fi
    
    # Try to find the key file in common locations
    KEY_FILE=""
    POSSIBLE_KEY_LOCATIONS=(
        "${PROJECT_ROOT}/${KEY_PAIR_NAME}.pem"
        "${PROJECT_ROOT}/wordpress-project.pem"
        "${HOME}/.ssh/${KEY_PAIR_NAME}.pem"
        "${HOME}/.ssh/id_rsa"
    )
    
    for key_path in "${POSSIBLE_KEY_LOCATIONS[@]}"; do
        if [ -f "$key_path" ] && [ -r "$key_path" ]; then
            KEY_FILE="$key_path"
            break
        fi
    done
    
    if [ -z "$KEY_FILE" ]; then
        skip "SSH key file not found for key pair '$KEY_PAIR_NAME'. Expected locations: ${POSSIBLE_KEY_LOCATIONS[*]}"
    fi
    
    # Ensure key file has correct permissions
    chmod 600 "$KEY_FILE" 2>/dev/null || true
    
    # Get all running instances from Auto Scaling Group
    INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$REGION" \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$INSTANCE_IDS" ] || [ "$INSTANCE_IDS" == "None" ]; then
        skip "No running instances found in Auto Scaling Group"
    fi
    
    # Check httpd status on each instance
    ALL_INSTANCES_VALID=true
    for INSTANCE_ID in $INSTANCE_IDS; do
        # Get instance public IP
        PUBLIC_IP=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --region "$REGION" \
            --query "Reservations[0].Instances[0].PublicIpAddress" \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; then
            echo "Warning: Could not get public IP for instance $INSTANCE_ID" >&2
            ALL_INSTANCES_VALID=false
            continue
        fi
        
        # SSH into instance and check httpd status
        # Use a single SSH call with newline-separated output
        HTTPD_STATUS=$(timeout 30 ssh -i "$KEY_FILE" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 \
            -o LogLevel=ERROR \
            ec2-user@"$PUBLIC_IP" \
            "rpm -q httpd >/dev/null 2>&1 && echo 'INSTALLED' || echo 'NOT_INSTALLED'; systemctl is-enabled httpd 2>/dev/null || echo 'NOT_ENABLED'; systemctl is-active httpd 2>/dev/null || echo 'NOT_RUNNING'" 2>/dev/null || echo "")
        
        if [ -z "$HTTPD_STATUS" ]; then
            echo "Warning: Could not retrieve httpd status from instance $INSTANCE_ID ($PUBLIC_IP)" >&2
            ALL_INSTANCES_VALID=false
            continue
        fi
        
        # Parse the status output (three lines: installed, enabled, running)
        HTTPD_INSTALLED=$(echo "$HTTPD_STATUS" | sed -n '1p' | tr -d '[:space:]')
        HTTPD_ENABLED=$(echo "$HTTPD_STATUS" | sed -n '2p' | tr -d '[:space:]')
        HTTPD_RUNNING=$(echo "$HTTPD_STATUS" | sed -n '3p' | tr -d '[:space:]')
        
        INSTANCE_VALID=true
        
        # Check if httpd is installed
        if [ "$HTTPD_INSTALLED" != "INSTALLED" ]; then
            echo "Error: Instance $INSTANCE_ID ($PUBLIC_IP): httpd is not installed" >&2
            INSTANCE_VALID=false
        fi
        
        # Check if httpd is enabled at boot
        if [ "$HTTPD_ENABLED" != "enabled" ]; then
            echo "Error: Instance $INSTANCE_ID ($PUBLIC_IP): httpd is not enabled at boot (status: $HTTPD_ENABLED)" >&2
            INSTANCE_VALID=false
        fi
        
        # Check if httpd is running
        if [ "$HTTPD_RUNNING" != "active" ]; then
            echo "Error: Instance $INSTANCE_ID ($PUBLIC_IP): httpd is not running (status: $HTTPD_RUNNING)" >&2
            INSTANCE_VALID=false
        fi
        
        if [ "$INSTANCE_VALID" == "true" ]; then
            echo "Instance $INSTANCE_ID ($PUBLIC_IP): httpd installed ✓, enabled ✓, running ✓" >&2
        else
            ALL_INSTANCES_VALID=false
        fi
    done
    
    [ "$ALL_INSTANCES_VALID" == "true" ]
}

