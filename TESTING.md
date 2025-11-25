# Testing Guide

This repository uses [bats-core](https://github.com/bats-core/bats-core) for unit testing bash scripts.

## Quick Start

### 1. Install Testing Dependencies

Run the setup script to install bats-core and helper libraries:

```bash
./setup-bats.sh
```

This will install:
- `bats-core` - The testing framework
- `bats-support` - Helper functions for loading and running tests
- `bats-assert` - Assertion library for bats

All dependencies are installed locally in `test_helper/` directory.

### 2. Run Tests

Run all tests:

```bash
./run-tests.sh
```

Run specific test files:

```bash
./run-tests.sh tests/unit/test_common.bats
./run-tests.sh tests/unit/test_common.bats tests/unit/test_common_update_template.bats
```

Or use bats directly:

```bash
./test_helper/bats-core/bin/bats tests/unit/
```

## Test Structure

Tests are located in the `tests/unit/` directory:

```
tests/
└── unit/
    ├── test_common.bats                          # Tests for _common.sh functions
    ├── test_common_update_template.bats           # Tests for template update functions
    ├── test_common_get_latest_ami.bats           # Tests for get_latest_ami() with AWS mocking
    ├── test_common_get_aws_account.bats           # Tests for get_aws_account() success/failure
    ├── test_common_validate_key_pair.bats        # Enhanced tests for validate_key_pair()
    ├── test_common_auto_select_key_pair.bats     # Tests for auto_select_key_pair() function
    ├── test_common_check_stack_exists.bats        # Tests for check_stack_exists() with AWS mocking
    ├── test_common_get_stack_status.bats          # Tests for get_stack_status() with AWS mocking
    ├── test_common_check_aws_credentials.bats    # Tests for check_aws_credentials() with AWS mocking
    └── test_script_args.bats                     # Tests for script argument parsing
```

## Writing Tests

### Basic Test Structure

```bash
#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    # Setup code runs before each test
    TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
    source "${PROJECT_ROOT}/_common.sh"
}

teardown() {
    # Cleanup code runs after each test
    # Clean up temporary files, restore backups, etc.
}

@test "description of what this test does" {
    run function_to_test "arg1" "arg2"
    assert_success
    assert_output "expected output"
}
```

### Common Assertions

- `assert_success` - Assert command exited with status 0
- `assert_failure` - Assert command exited with non-zero status
- `assert_output "text"` - Assert output matches exactly
- `assert_output --partial "text"` - Assert output contains text
- `assert_output --regexp 'pattern'` - Assert output matches regex
- `refute_output "text"` - Assert output does not match
- `assert [ condition ]` - Assert a condition is true

### Example Test

```bash
@test "generate_password returns a password of correct length" {
    run generate_password
    assert_success
    assert_output --regexp '^.{12,16}$'
}

@test "validate_key_pair returns error when key pair name is empty" {
    run validate_key_pair ""
    assert_failure
    assert_output --partial "Key Pair Name is required"
}
```

## Mocking External Commands

To mock AWS CLI commands or other external dependencies, you can override functions:

```bash
@test "check_aws_credentials with mocked AWS CLI" {
    aws() {
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
            echo '{"Account":"123456789012"}'
            return 0
        fi
        return 1
    }
    export -f aws
    
    run check_aws_credentials
    assert_success
}
```

## Test Coverage Summary

**Total Test Files:** 10  
**Total Tests:** 97  
**Test Framework:** bats-core

### Quick Statistics

- **Core Functions:** 9 functions fully tested (47 tests across 9 test files)
- **Script Argument Parsing:** 9 scripts fully tested (50 tests in 1 test file)
- **AWS CLI Mocking:** All AWS-dependent functions use isolated mocking
- **Error Handling:** Comprehensive edge case and failure scenario coverage

### Test Breakdown by Category

| Category | Test Files | Tests | Status |
|----------|-----------|-------|--------|
| Core Functions (`_common.sh`) | 9 | 47 | ✅ Complete |
| Script Argument Parsing | 1 | 50 | ✅ Complete |
| **Total** | **10** | **97** | **✅ All Passing** |

### Test Files Breakdown

| Test File | Tests | Description |
|-----------|-------|-------------|
| `test_common.bats` | 14 | Core function tests (password, validation, error handling) |
| `test_common_auto_select_key_pair.bats` | 4 | Key pair auto-selection logic |
| `test_common_check_aws_credentials.bats` | 3 | AWS credentials validation |
| `test_common_check_stack_exists.bats` | 5 | Stack existence checking |
| `test_common_get_aws_account.bats` | 3 | AWS account retrieval |
| `test_common_get_latest_ami.bats` | 6 | AMI lookup functionality |
| `test_common_get_stack_status.bats` | 6 | Stack status retrieval |
| `test_common_update_template.bats` | 2 | Template AMI updates |
| `test_common_validate_key_pair.bats` | 4 | Key pair validation |
| `test_script_args.bats` | 50 | All script argument parsing |

## Test Coverage Details

Current test coverage includes:

### Core Functions (`_common.sh`)
- ✅ `generate_password()` - Password generation and validation (length, character requirements)
- ✅ `validate_key_pair()` - Input validation and AWS CLI mocking (success/failure cases)
- ✅ `check_aws_credentials()` - AWS CLI mocking (success, failure, error handling)
- ✅ `check_stack_exists()` - AWS CLI mocking (success, failure, default/custom regions)
- ✅ `get_stack_status()` - AWS CLI mocking (various statuses, error handling, regions)
- ✅ `get_latest_ami()` - AWS CLI mocking (success, failure, default AMI)
- ✅ `get_aws_account()` - Success and failure cases with AWS CLI mocking
- ✅ `update_template_ami()` - File operations and AMI replacement
- ✅ `auto_select_key_pair()` - Single key pair selection, error handling, default region

### Script Argument Parsing
- ✅ `deploy-prod.sh` - All argument options and help message
- ✅ `deploy-dev.sh` - Help message
- ✅ `destroy-stack.sh` - Argument parsing
- ✅ `create-ami.sh` - All argument options (-s, -r, -n, -d) and help message
- ✅ `update-launch-template-with-ami.sh` - All argument options (-s, -r, -a, -f) and help message
- ✅ `utils/check-stack-status.sh` - Argument parsing
- ✅ `utils/troubleshoot-wordpress.sh` - Argument parsing
- ✅ `utils/create-key-pair.sh` - All argument options (-k, -r), help message, and legacy positional argument
- ✅ `utils/get-stack-info.sh` - All argument options (-s, -r, -e, -R, -o, -p, -i, -d, -a) and help message

## Running Specific Test Suites

You can run specific categories of tests:

```bash
# Run only core function tests
./run-tests.sh tests/unit/test_common*.bats

# Run only argument parsing tests
./run-tests.sh tests/unit/test_script_args.bats

# Run tests for a specific function
./run-tests.sh tests/unit/test_common_get_latest_ami.bats

# Run tests for AWS credential functions
./run-tests.sh tests/unit/test_common_check_aws_credentials.bats tests/unit/test_common_get_aws_account.bats
```

## Continuous Integration

To run tests in CI/CD pipelines:

```bash
# Install dependencies
./setup-bats.sh

# Run tests
./run-tests.sh
```

## Best Practices

1. **Test one thing per test** - Each `@test` should verify a single behavior
2. **Use descriptive test names** - Test names should clearly describe what is being tested
3. **Mock external dependencies** - Don't make real AWS API calls in unit tests
4. **Clean up in teardown** - Restore files, remove temporary data
5. **Test edge cases** - Empty inputs, missing files, invalid data
6. **Test error conditions** - Verify functions fail appropriately

## Troubleshooting

### Tests fail with "command not found: bats"

Run `./setup-bats.sh` to install bats-core.

### Tests fail with "load: command not found"

Make sure bats-support and bats-assert are installed:
```bash
./setup-bats.sh
```

### Tests can't find _common.sh

Ensure test setup correctly sets `PROJECT_ROOT` and sources the file:
```bash
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
source "${PROJECT_ROOT}/_common.sh"
```

## Resources

- [bats-core Documentation](https://bats-core.readthedocs.io/)
- [bats-assert Documentation](https://github.com/bats-core/bats-assert)
- [bats-support Documentation](https://github.com/bats-core/bats-support)

