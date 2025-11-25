#!/bin/bash

# Test runner script for bats-core tests

set -e

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

# Determine which tests to run
if [ $# -eq 0 ]; then
    # Run all tests
    TEST_FILES="${SCRIPT_DIR}/tests/unit/*.bats"
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
else
    echo -e "${RED}✗ Some tests failed${NC}"
fi

exit $EXIT_CODE

