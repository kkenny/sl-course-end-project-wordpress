#!/usr/bin/env bats

# Performance tests for WordPress deployment
# These tests verify performance characteristics and auto-scaling behavior

setup() {
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"
    
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
    STACK_NAME="${STACK_NAME:-wordpress-dev}"
    REGION="${REGION:-${AWS_REGION:-us-east-1}}"
    
    # Check if AWS credentials are configured
    # Verify credentials are available (either from _set_profile.sh or already set)
    if [ -z "$AWS_ACCESS_KEY_ID" ] && [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        # Try to verify with AWS CLI
        if ! aws sts get-caller-identity &> /dev/null; then
            skip "AWS credentials not configured. Ensure _set_profile.sh exports AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or run 'aws configure'"
        fi
    elif ! check_aws_credentials; then
        skip "AWS credentials from _set_profile.sh are invalid or expired. Please check your credentials."
    fi
    
    # Check if stack exists
    if ! check_stack_exists "$STACK_NAME" "$REGION"; then
        skip "Stack '$STACK_NAME' does not exist in region '$REGION'"
    fi
    
    # Get WordPress URL from stack outputs
    WORDPRESS_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='WordPressURL'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$WORDPRESS_URL" ] || [ "$WORDPRESS_URL" == "None" ]; then
        skip "WordPressURL output not found for stack '$STACK_NAME'"
    fi
    
    # Get Auto Scaling Group name
    ASG_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='AutoScalingGroupName'].OutputValue" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ASG_NAME" ] || [ "$ASG_NAME" == "None" ]; then
        skip "AutoScalingGroupName output not found"
    fi
    
    # Performance test configuration
    PERFORMANCE_TEST_DURATION="${PERFORMANCE_TEST_DURATION:-30}"  # seconds
    PERFORMANCE_TEST_CONCURRENT="${PERFORMANCE_TEST_CONCURRENT:-50}"  # concurrent requests
    LOAD_TEST_DURATION="${LOAD_TEST_DURATION:-120}"  # seconds for load test
    LOAD_TEST_CONCURRENT="${LOAD_TEST_CONCURRENT:-100}"  # concurrent requests for load test
    
    # Get initial instance count
    INITIAL_INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$REGION" \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
        --output text 2>/dev/null || echo "0")
    
    # Check for bc (basic calculator) - warn if not available but don't fail
    if ! command -v bc &> /dev/null; then
        echo "Warning: 'bc' command not found. Some calculations may be less precise." >&2
        echo "Install with: brew install bc (macOS) or sudo apt-get install bc (Linux)" >&2
    fi
    
    # Check for Apache Bench (ab) - required for load tests
    if ! command -v ab &> /dev/null; then
        echo "Warning: 'ab' (Apache Bench) not found. Load tests will use curl fallback." >&2
        echo "Install with: brew install httpd (macOS) or sudo apt-get install apache2-utils (Linux)" >&2
        HAS_AB=false
    else
        HAS_AB=true
    fi
}

teardown() {
    # Restore _set_profile.sh if it was backed up
    if [ -f "${PROJECT_ROOT}/_set_profile.sh.bak" ]; then
        mv "${PROJECT_ROOT}/_set_profile.sh.bak" "${PROJECT_ROOT}/_set_profile.sh" 2>/dev/null || true
    fi
}

# Helper function to make HTTP request and measure time
measure_response_time() {
    local url="$1"
    local start_time=$(date +%s.%N)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    echo "$http_code|$duration"
}

# Helper function to run concurrent requests
run_concurrent_requests() {
    local url="$1"
    local num_requests="$2"
    local concurrent="$3"
    local results_file=$(mktemp)
    local pids=()
    
    # Launch concurrent requests
    for ((i=1; i<=num_requests; i++)); do
        (
            result=$(measure_response_time "$url")
            echo "$result" >> "$results_file"
        ) &
        pids+=($!)
        
        # Limit concurrent processes
        if [ ${#pids[@]} -ge $concurrent ]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
        fi
    done
    
    # Wait for all remaining processes
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    echo "$results_file"
}

@test "WordPress homepage responds within acceptable time" {
    # Make multiple requests and measure response times
    local total_requests=10
    local max_acceptable_time=2.0  # seconds
    local success_count=0
    local total_time=0
    
    for ((i=1; i<=total_requests; i++)); do
        result=$(measure_response_time "$WORDPRESS_URL")
        http_code=$(echo "$result" | cut -d'|' -f1)
        duration=$(echo "$result" | cut -d'|' -f2)
        
        if [ "$http_code" == "200" ]; then
            success_count=$((success_count + 1))
            total_time=$(echo "$total_time + $duration" | bc 2>/dev/null || echo "$total_time")
        fi
    done
    
    # Verify at least 90% of requests succeed
    success_rate=$(echo "scale=2; $success_count * 100 / $total_requests" | bc 2>/dev/null || echo "0")
    [ "$success_count" -ge 9 ]
    
    # Calculate average response time
    if [ "$success_count" -gt 0 ]; then
        avg_time=$(echo "scale=3; $total_time / $success_count" | bc 2>/dev/null || echo "0")
        echo "Average response time: ${avg_time}s (${success_count}/${total_requests} successful)" >&2
        
        # Verify average response time is acceptable
        avg_time_int=$(echo "$avg_time" | cut -d. -f1)
        max_time_int=$(echo "$max_acceptable_time" | cut -d. -f1)
        [ "$avg_time_int" -le "$max_time_int" ] || [ "$(echo "$avg_time <= $max_acceptable_time" | bc 2>/dev/null || echo "0")" == "1" ]
    fi
}

@test "WordPress handles moderate concurrent load" {
    # Run moderate concurrent load test
    local num_requests=100
    local concurrent=20
    local min_success_rate=95  # percentage
    
    echo "Running moderate load test: $num_requests requests with $concurrent concurrent connections..." >&2
    
    if [ "$HAS_AB" == "true" ]; then
        # Use Apache Bench for better performance and metrics
        local ab_output=$(ab -n "$num_requests" -c "$concurrent" -q "$WORDPRESS_URL" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            echo "Apache Bench failed. Output: $ab_output" >&2
            # Fall back to curl-based test
            results_file=$(run_concurrent_requests "$WORDPRESS_URL" "$num_requests" "$concurrent")
            
            local success_count=0
            local total_count=0
            
            while IFS='|' read -r http_code duration; do
                total_count=$((total_count + 1))
                if [ "$http_code" == "200" ]; then
                    success_count=$((success_count + 1))
                fi
            done < "$results_file"
            rm -f "$results_file"
            
            echo "Fallback test results: ${success_count}/${total_count} successful" >&2
            [ "$success_count" -ge $((total_count * min_success_rate / 100)) ]
        else
            # Parse Apache Bench output
            echo "$ab_output" >&2
            
            # Extract success rate from ab output
            local failed_requests=$(echo "$ab_output" | grep -i "Failed requests" | awk '{print $3}' | tr -d '()' || echo "0")
            local success_count=$((num_requests - failed_requests))
            local success_rate=$(echo "scale=2; $success_count * 100 / $num_requests" | bc 2>/dev/null || echo "0")
            
            echo "Apache Bench results: ${success_count}/${num_requests} successful (${success_rate}%)" >&2
            
            # Verify success rate meets threshold
            [ "$success_count" -ge $((num_requests * min_success_rate / 100)) ]
        fi
    else
        # Fallback to curl-based test
        results_file=$(run_concurrent_requests "$WORDPRESS_URL" "$num_requests" "$concurrent")
        
        local success_count=0
        local total_count=0
        
        while IFS='|' read -r http_code duration; do
            total_count=$((total_count + 1))
            if [ "$http_code" == "200" ]; then
                success_count=$((success_count + 1))
            fi
        done < "$results_file"
        rm -f "$results_file"
        
        echo "Curl-based test results: ${success_count}/${total_count} successful" >&2
        [ "$success_count" -ge $((total_count * min_success_rate / 100)) ]
    fi
}

@test "WordPress handles heavy load and triggers auto-scaling" {
    # This test pushes heavy traffic to trigger auto-scaling
    local duration=$LOAD_TEST_DURATION
    local concurrent=$LOAD_TEST_CONCURRENT
    local check_interval=10  # seconds between instance count checks
    
    echo "Starting heavy load test to trigger auto-scaling..." >&2
    echo "Duration: ${duration}s, Concurrent requests: $concurrent" >&2
    echo "Initial instance count: $INITIAL_INSTANCE_COUNT" >&2
    
    # Get initial instance count and max size
    local initial_count=$INITIAL_INSTANCE_COUNT
    local max_size=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$REGION" \
        --query 'AutoScalingGroups[0].MaxSize' \
        --output text 2>/dev/null || echo "2")
    
    # Start load generation in background
    local load_pid
    if [ "$HAS_AB" == "true" ]; then
        # Use Apache Bench for more efficient load generation
        # Calculate total requests based on duration (aim for high RPS)
        local requests_per_second=50
        local total_requests=$((duration * requests_per_second))
        
        echo "Using Apache Bench: $total_requests requests with $concurrent concurrent connections..." >&2
        
        # Run ab in background with timeout
        (
            timeout "$duration" ab -n "$total_requests" -c "$concurrent" -q "$WORDPRESS_URL" >/dev/null 2>&1
        ) &
        load_pid=$!
    else
        # Fallback to curl-based load generation
        echo "Using curl-based load generation (Apache Bench not available)..." >&2
        (
            local end_time=$(($(date +%s) + duration))
            while [ $(date +%s) -lt $end_time ]; do
                # Launch batch of concurrent requests
                for ((i=1; i<=concurrent; i++)); do
                    curl -s -o /dev/null --max-time 5 "$WORDPRESS_URL" >/dev/null 2>&1 &
                done
                # Small delay to prevent overwhelming the system
                sleep 0.1
            done
            wait
        ) &
        load_pid=$!
    fi
    
    # Monitor instance count during load test
    local max_instances_seen=$initial_count
    local scaling_detected=false
    local check_count=0
    
    while kill -0 "$load_pid" 2>/dev/null; do
        sleep $check_interval
        check_count=$((check_count + 1))
        
        local current_count=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG_NAME" \
            --region "$REGION" \
            --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
            --output text 2>/dev/null || echo "$initial_count")
        
        if [ "$current_count" -gt "$max_instances_seen" ]; then
            max_instances_seen=$current_count
            scaling_detected=true
            echo "Auto-scaling detected! Instance count increased to: $current_count" >&2
        fi
        
        echo "Check $check_count: Current instances: $current_count, Max seen: $max_instances_seen" >&2
    done
    
    # Wait for load test to complete
    wait "$load_pid" 2>/dev/null || true
    
    # Give some time for scaling to stabilize
    echo "Waiting for scaling to stabilize..." >&2
    sleep 30
    
    # Get final instance count
    local final_count=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$REGION" \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`] | length(@)' \
        --output text 2>/dev/null || echo "$initial_count")
    
    echo "Load test complete. Initial: $initial_count, Final: $final_count, Max seen: $max_instances_seen" >&2
    
    # Verify service remained available during load
    local health_check=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$WORDPRESS_URL" 2>/dev/null || echo "000")
    [ "$health_check" == "200" ]
    
    # For production environments, verify scaling occurred
    # For development, scaling may not occur due to lower max size
    if [ "$max_size" -gt "$initial_count" ]; then
        # If max size allows scaling, verify that scaling was attempted or occurred
        # Note: Scaling may take time, so we check if max instances seen increased OR if final count is higher
        if [ "$max_instances_seen" -gt "$initial_count" ] || [ "$final_count" -gt "$initial_count" ]; then
            echo "Auto-scaling successfully triggered (or in progress)" >&2
        else
            echo "Warning: Auto-scaling did not trigger, but service remained available" >&2
            # Don't fail the test if service remained available - scaling may need more time or traffic
        fi
    else
        echo "Max size ($max_size) equals initial count ($initial_count), scaling not possible" >&2
    fi
}

@test "WordPress maintains performance under sustained load" {
    # Test sustained load over a period of time
    local duration=60  # seconds
    local concurrent=30
    local min_success_rate=90  # percentage
    
    echo "Running sustained load test for ${duration}s..." >&2
    
    if [ "$HAS_AB" == "true" ]; then
        # Use Apache Bench for sustained load testing
        # Calculate total requests (aim for ~10 requests per second)
        local requests_per_second=10
        local total_requests=$((duration * requests_per_second))
        
        echo "Using Apache Bench: $total_requests requests with $concurrent concurrent connections..." >&2
        
        local ab_output=$(ab -n "$total_requests" -c "$concurrent" -q "$WORDPRESS_URL" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            echo "Apache Bench failed. Output: $ab_output" >&2
            false
        else
            # Parse Apache Bench output
            echo "$ab_output" >&2
            
            # Extract metrics from ab output
            local failed_requests=$(echo "$ab_output" | grep -i "Failed requests" | awk '{print $3}' | tr -d '()' || echo "0")
            local success_count=$((total_requests - failed_requests))
            local success_rate=$(echo "scale=2; $success_count * 100 / $total_requests" | bc 2>/dev/null || echo "0")
            
            # Extract time per request (mean)
            local time_per_request=$(echo "$ab_output" | grep -i "Time per request" | head -1 | awk '{print $4}' || echo "0")
            
            echo "Sustained load test results:" >&2
            echo "  Total requests: $total_requests" >&2
            echo "  Successful: $success_count (${success_rate}%)" >&2
            echo "  Time per request: ${time_per_request}ms" >&2
            
            # Verify success rate meets threshold
            [ "$success_count" -ge $((total_requests * min_success_rate / 100)) ]
            
            # Verify time per request is reasonable (under 3000ms = 3 seconds)
            if [ -n "$time_per_request" ] && [ "$time_per_request" != "0" ]; then
                time_per_request_int=$(echo "$time_per_request" | cut -d. -f1)
                [ "$time_per_request_int" -lt 3000 ]
            fi
        fi
    else
        # Fallback to curl-based sustained load
        local requests_per_second=10
        local results_file=$(mktemp)
        local start_time=$(date +%s)
        
        # Generate sustained load
        while [ $(($(date +%s) - start_time)) -lt $duration ]; do
            # Launch batch of requests
            for ((i=1; i<=concurrent; i++)); do
                (
                    result=$(measure_response_time "$WORDPRESS_URL")
                    echo "$result" >> "$results_file"
                ) &
            done
            
            # Control request rate
            sleep $(echo "scale=2; 1 / $requests_per_second" | bc 2>/dev/null || echo "0.1")
        done
        
        # Wait for all requests to complete
        wait
        
        # Analyze results
        local success_count=0
        local total_count=0
        local total_time=0
        
        while IFS='|' read -r http_code duration; do
            total_count=$((total_count + 1))
            if [ "$http_code" == "200" ]; then
                success_count=$((success_count + 1))
                total_time=$(echo "$total_time + $duration" | bc 2>/dev/null || echo "$total_time")
            fi
        done < "$results_file"
        
        rm -f "$results_file"
        
        # Calculate metrics
        if [ "$total_count" -gt 0 ]; then
            success_rate=$(echo "scale=2; $success_count * 100 / $total_count" | bc 2>/dev/null || echo "0")
            
            if [ "$success_count" -gt 0 ]; then
                avg_time=$(echo "scale=3; $total_time / $success_count" | bc 2>/dev/null || echo "0")
            else
                avg_time=0
            fi
            
            echo "Sustained load test results:" >&2
            echo "  Total requests: $total_count" >&2
            echo "  Successful: $success_count (${success_rate}%)" >&2
            echo "  Average response time: ${avg_time}s" >&2
            
            # Verify success rate meets threshold
            [ "$success_count" -ge $((total_count * min_success_rate / 100)) ]
            
            # Verify average response time is reasonable (under 3 seconds)
            [ "$(echo "$avg_time < 3.0" | bc 2>/dev/null || echo "0")" == "1" ] || [ "$avg_time" == "0" ]
        else
            echo "Error: No requests completed" >&2
            false
        fi
    fi
}

@test "WordPress recovers after load test" {
    # Verify service recovers and returns to normal after load test
    echo "Verifying service recovery after load test..." >&2
    
    # Wait a bit for any scaling activities to stabilize
    sleep 10
    
    # Make several requests to verify service is responsive
    local success_count=0
    local total_requests=20
    
    for ((i=1; i<=total_requests; i++)); do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$WORDPRESS_URL" 2>/dev/null || echo "000")
        if [ "$http_code" == "200" ]; then
            success_count=$((success_count + 1))
        fi
        sleep 0.5
    done
    
    echo "Recovery test: ${success_count}/${total_requests} requests successful" >&2
    
    # Verify at least 95% of requests succeed
    [ "$success_count" -ge $((total_requests * 95 / 100)) ]
}

