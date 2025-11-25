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
    TEST_FILES="${SCRIPT_DIR}/tests/*.bats"
else
    # Run specific test files
    TEST_FILES="$@"
fi

# Run the tests
echo -e "${YELLOW}Running tests...${NC}"
echo ""

"$BATS_BIN" $TEST_FILES

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
else
    echo -e "${RED}✗ Some tests failed${NC}"
fi

exit $EXIT_CODE

