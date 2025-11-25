#!/bin/bash

# Test runner script for bats-core tests

# Don't exit on error - we want to update badge and commit even if tests fail
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_BIN="${SCRIPT_DIR}/test_helper/bats-core/bin/bats"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Running tests with bats-core${NC}"
echo "================================"
echo ""

# Check if bats-core is installed
if [ ! -f "$BATS_BIN" ]; then
    echo -e "${YELLOW}bats-core not found. Installing...${NC}"
    echo ""
    "${SCRIPT_DIR}/setup-bats.sh"
    echo ""
fi

# Check if bats-core is still not available
if [ ! -f "$BATS_BIN" ]; then
    echo -e "${RED}Error: bats-core installation failed${NC}"
    echo "Please run: ./setup-bats.sh"
    exit 1
fi

# Check for help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [OPTIONS] [TEST_FILES...]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -i, --integration  Run integration tests (requires deployed stacks)"
    echo "  -p, --performance  Run performance tests (requires deployed stacks)"
    echo "  -a, --all           Run all tests (unit, integration, and performance)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Run all unit tests"
    echo "  $0 --integration                      # Run all integration tests"
    echo "  $0 --performance                      # Run all performance tests"
    echo "  $0 --integration STACK_NAME=wordpress-prod  # Run integration tests for specific stack"
    echo "  $0 --performance STACK_NAME=wordpress-prod  # Run performance tests for specific stack"
    echo "  $0 --all                              # Run all tests"
    echo "  $0 tests/unit/test_common.bats         # Run specific test file"
    echo ""
    echo "Integration/Performance Test Environment Variables:"
    echo "  STACK_NAME          Stack name to test (default: wordpress-dev)"
    echo "  REGION              AWS region (default: us-east-1 or AWS_REGION)"
    echo "  LOAD_TEST_DURATION  Duration for load tests in seconds (default: 120)"
    echo "  LOAD_TEST_CONCURRENT Concurrent requests for load tests (default: 100)"
    echo ""
    exit 0
fi

# Determine which tests to run
if [ $# -eq 0 ]; then
    # Run all unit tests by default
    TEST_FILES="${SCRIPT_DIR}/tests/unit/*.bats"
elif [ "$1" = "--integration" ] || [ "$1" = "-i" ]; then
    # Run integration tests
    shift
    if [ $# -eq 0 ]; then
        TEST_FILES="${SCRIPT_DIR}/tests/integration/*.bats"
    else
        TEST_FILES="$@"
    fi
elif [ "$1" = "--performance" ] || [ "$1" = "-p" ]; then
    # Run performance tests
    shift
    if [ $# -eq 0 ]; then
        TEST_FILES="${SCRIPT_DIR}/tests/performance/*.bats"
    else
        TEST_FILES="$@"
    fi
elif [ "$1" = "--all" ] || [ "$1" = "-a" ]; then
    # Run all tests (unit, integration, and performance)
    TEST_FILES="${SCRIPT_DIR}/tests/unit/*.bats ${SCRIPT_DIR}/tests/integration/*.bats ${SCRIPT_DIR}/tests/performance/*.bats"
    shift
    if [ $# -gt 0 ]; then
        TEST_FILES="$TEST_FILES $@"
    fi
else
    # Run specific test files
    TEST_FILES="$@"
fi

# Run the tests
echo -e "${YELLOW}Running tests...${NC}"
echo ""

# Track overall exit code
OVERALL_EXIT=0
FIRST_FILE=true

# Process each test file separately to track filenames
for test_file in $TEST_FILES; do
    # Skip if file doesn't exist (e.g., from glob expansion)
    [ ! -f "$test_file" ] && continue
    
    # Extract just the filename
    filename=$(basename "$test_file")
    
    # Print file header (with blank line before if not first file)
    if [ "$FIRST_FILE" = false ]; then
        echo ""
    fi
    echo "$filename"
    echo ""
    FIRST_FILE=false
    
    # Run tests for this file and format output
    "$BATS_BIN" "$test_file" | awk -v green="${GREEN}" -v red="${RED}" -v nc="${NC}" '
    BEGIN {
        test_num = 0
    }
    /^1\.\./ {
        # Skip the TAP plan line
        next
    }
    /^ok [0-9]+/ {
        test_num++
        # Extract test name (everything after "ok N ")
        test_name = $0
        sub(/^ok [0-9]+ /, "", test_name)
        # Print test with number and green checkmark
        printf " %s✓ %d. %s%s\n", green, test_num, test_name, nc
        next
    }
    /^not ok [0-9]+/ {
        test_num++
        # Extract test name
        test_name = $0
        sub(/^not ok [0-9]+ /, "", test_name)
        # Print test with number and red X
        printf " %s✗ %d. %s%s\n", red, test_num, test_name, nc
        next
    }
    {
        # Print other lines as-is (like error messages)
        print
    }
    '
    
    # Capture exit code from this test file
    FILE_EXIT=${PIPESTATUS[0]}
    if [ $FILE_EXIT -ne 0 ]; then
        OVERALL_EXIT=$FILE_EXIT
    fi
done

EXIT_CODE=$OVERALL_EXIT

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    TEST_STATUS="passing"
    BADGE_COLOR="brightgreen"
else
    echo -e "${RED}✗ Some tests failed${NC}"
    TEST_STATUS="failing"
    BADGE_COLOR="red"
fi

# Function to update test badge in README.md
update_test_badge() {
    local readme_file="${SCRIPT_DIR}/README.md"
    local badge_text="[![Tests](https://img.shields.io/badge/tests-${TEST_STATUS}-${BADGE_COLOR})](tests)"
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    if [ ! -f "$readme_file" ]; then
        echo "Warning: README.md not found, skipping badge update" >&2
        return 1
    fi
    
    # Create a temporary file for the updated README
    local temp_file=$(mktemp)
    
    # Check if badge already exists in README
    if grep -q "^\[!\[Tests\]" "$readme_file"; then
        # Update existing badge line
        awk -v badge="$badge_text" -v timestamp="$timestamp" '
        /^\[!\[Tests\]/ {
            print badge
            next
        }
        /^<!-- Tests last run:/ {
            print "<!-- Tests last run: " timestamp " -->"
            next
        }
        {
            print
        }
        ' "$readme_file" > "$temp_file"
    else
        # Add badge at the very top of README
        {
            echo "$badge_text"
            echo "<!-- Tests last run: ${timestamp} -->"
            echo ""
            cat "$readme_file"
        } > "$temp_file"
    fi
    
    # Replace original file with updated version
    mv "$temp_file" "$readme_file"
    
    echo "Updated test badge in README.md: ${TEST_STATUS}" >&2
    return 0
}

# Function to commit README.md changes
commit_readme_changes() {
    local readme_file="${SCRIPT_DIR}/README.md"
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Not in a git repository, skipping commit" >&2
        return 1
    fi
    
    # Check if README.md has changes
    if ! git diff --quiet "$readme_file" 2>/dev/null; then
        # Stage the README.md file
        git add "$readme_file" > /dev/null 2>&1
        
        # Commit with a descriptive message
        local commit_message="Update test status badge: ${TEST_STATUS} [skip ci]"
        if git commit -m "$commit_message" > /dev/null 2>&1; then
            echo "Committed test badge update to README.md" >&2
            return 0
        else
            echo "Warning: Failed to commit README.md changes" >&2
            return 1
        fi
    else
        echo "No changes to README.md to commit" >&2
        return 0
    fi
}

# Update badge and commit if tests were run
if [ -n "$TEST_FILES" ]; then
    echo ""
    echo -e "${BLUE}Updating test status badge...${NC}"
    update_test_badge
    
    echo -e "${BLUE}Committing README.md changes...${NC}"
    commit_readme_changes
    echo ""
fi

exit $EXIT_CODE

