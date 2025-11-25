# Performance Tests

This directory contains performance and load tests for the WordPress deployment.

## Overview

The performance tests verify:
- Response time performance under normal load
- Ability to handle concurrent requests
- Auto-scaling behavior under heavy load
- Service recovery after load tests

## Prerequisites

1. **AWS Credentials**: Must be configured and have access to the deployed stack
2. **Apache Bench (ab)**: **Recommended** for load testing - provides better performance and metrics
   - Install on macOS: `brew install httpd` (ab comes with httpd)
   - Install on Linux: `sudo apt-get install apache2-utils` or `sudo yum install httpd-tools`
   - Note: Tests will fall back to curl-based load generation if ab is not available
3. **bc (Basic Calculator)**: Required for floating-point arithmetic
   - Install on macOS: `brew install bc`
   - Install on Linux: `sudo apt-get install bc` or `sudo yum install bc`
4. **curl**: Required for HTTP requests (usually pre-installed)
5. **bats-core**: Required for running the tests (see main TESTING.md)

## Running Performance Tests

### Run all performance tests:
```bash
bats tests/performance/test_performance.bats
```

### Run with specific stack:
```bash
STACK_NAME=wordpress-prod bats tests/performance/test_performance.bats
```

### Run with custom configuration:
```bash
# Adjust test duration and concurrency
PERFORMANCE_TEST_DURATION=60 \
LOAD_TEST_DURATION=180 \
LOAD_TEST_CONCURRENT=150 \
bats tests/performance/test_performance.bats
```

## Test Descriptions

### 1. WordPress homepage responds within acceptable time
- **Purpose**: Verify baseline response time performance
- **Method**: Makes 10 sequential requests and measures response times
- **Pass Criteria**: 
  - At least 90% of requests succeed
  - Average response time is under 2 seconds

### 2. WordPress handles moderate concurrent load
- **Purpose**: Test service under moderate concurrent load
- **Method**: Sends 100 requests with 20 concurrent connections using Apache Bench (or curl fallback)
- **Pass Criteria**: 
  - At least 95% of requests succeed
  - Service remains responsive
- **Note**: Uses Apache Bench if available for better performance metrics

### 3. WordPress handles heavy load and triggers auto-scaling
- **Purpose**: Push heavy traffic to trigger auto-scaling
- **Method**: 
  - Generates sustained high load using Apache Bench (or curl fallback)
  - Monitors Auto Scaling Group instance count during load
  - Verifies scaling occurs (if max size allows)
- **Pass Criteria**:
  - Service remains available during load
  - Auto-scaling triggers (if environment allows)
  - Instance count increases under load
- **Note**: Uses Apache Bench if available for more efficient load generation

### 4. WordPress maintains performance under sustained load
- **Purpose**: Verify service maintains performance over time
- **Method**: Generates sustained load for 60 seconds using Apache Bench (or curl fallback)
- **Pass Criteria**:
  - At least 90% of requests succeed
  - Average response time remains under 3 seconds
- **Note**: Uses Apache Bench if available for better performance metrics

### 5. WordPress recovers after load test
- **Purpose**: Verify service recovers to normal operation
- **Method**: Makes 20 requests after load test completes
- **Pass Criteria**: At least 95% of requests succeed

## Configuration

Environment variables can be used to customize test behavior:

- `STACK_NAME`: CloudFormation stack name (default: `wordpress-dev`)
- `REGION`: AWS region (default: `us-east-1` or `$AWS_REGION`)
- `PERFORMANCE_TEST_DURATION`: Duration for performance tests in seconds (default: 30)
- `PERFORMANCE_TEST_CONCURRENT`: Concurrent requests for performance tests (default: 50)
- `LOAD_TEST_DURATION`: Duration for heavy load test in seconds (default: 120)
- `LOAD_TEST_CONCURRENT`: Concurrent requests for load test (default: 100)

## Auto-Scaling Test Notes

The auto-scaling test (`WordPress handles heavy load and triggers auto-scaling`) is designed to:
1. Generate sustained high traffic
2. Monitor the Auto Scaling Group instance count
3. Detect when scaling occurs

**Important considerations:**
- Scaling may take several minutes to trigger and complete
- Development environments may have lower max size limits
- The test verifies service availability even if scaling doesn't occur immediately
- CloudWatch metrics and Auto Scaling policies determine when scaling triggers

## Troubleshooting

### Tests fail with "bc: command not found"
Install bc calculator:
- macOS: `brew install bc`
- Linux: `sudo apt-get install bc` or `sudo yum install bc`

### Apache Bench not available
The tests will automatically fall back to curl-based load generation if Apache Bench is not installed. However, for best performance and metrics, install Apache Bench:
- macOS: `brew install httpd` (ab comes with httpd)
- Linux: `sudo apt-get install apache2-utils` or `sudo yum install httpd-tools`

### Auto-scaling doesn't trigger
- Check Auto Scaling Group configuration (min/max/desired capacity)
- Verify CloudWatch alarms are configured
- Check if sufficient time has passed (scaling can take 5-10 minutes)
- Review Auto Scaling Group activity history in AWS Console

### Tests timeout or hang
- Reduce `LOAD_TEST_DURATION` and `LOAD_TEST_CONCURRENT` values
- Check network connectivity to the WordPress URL
- Verify the stack is in a healthy state

### High error rates during load test
- This may indicate the service is under stress
- Check CloudWatch metrics for CPU, memory, and network
- Review Auto Scaling Group health checks
- Consider increasing instance capacity

## Best Practices

1. **Run during off-peak hours**: Performance tests generate significant load
2. **Monitor AWS Console**: Watch Auto Scaling Group and CloudWatch during tests
3. **Start with lower values**: Gradually increase load test parameters
4. **Review results**: Check both test output and AWS metrics
5. **Clean up**: Ensure tests complete and don't leave processes running

## Integration with CI/CD

These tests can be integrated into CI/CD pipelines but should be:
- Run against dedicated test environments
- Configured with appropriate timeouts
- Monitored for resource usage
- Run conditionally (e.g., on schedule or manual trigger)

