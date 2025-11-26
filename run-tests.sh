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

# Determine which tests to run and track categories
RUN_UNIT=false
RUN_INTEGRATION=false
RUN_PERFORMANCE=false
TEST_FILES=""
CUSTOM_FILES=""

if [ $# -eq 0 ]; then
    # Run all unit tests by default
    RUN_UNIT=true
    TEST_FILES="${SCRIPT_DIR}/tests/unit/*.bats"
elif [ "$1" = "--integration" ] || [ "$1" = "-i" ]; then
    # Run integration tests
    RUN_INTEGRATION=true
    shift
    if [ $# -eq 0 ]; then
        TEST_FILES="${SCRIPT_DIR}/tests/integration/*.bats"
    else
        TEST_FILES="$@"
        CUSTOM_FILES="$@"
    fi
elif [ "$1" = "--performance" ] || [ "$1" = "-p" ]; then
    # Run performance tests
    RUN_PERFORMANCE=true
    shift
    if [ $# -eq 0 ]; then
        TEST_FILES="${SCRIPT_DIR}/tests/performance/*.bats"
    else
        TEST_FILES="$@"
        CUSTOM_FILES="$@"
    fi
elif [ "$1" = "--all" ] || [ "$1" = "-a" ]; then
    # Run all tests (unit, integration, and performance)
    RUN_UNIT=true
    RUN_INTEGRATION=true
    RUN_PERFORMANCE=true
    TEST_FILES="${SCRIPT_DIR}/tests/unit/*.bats ${SCRIPT_DIR}/tests/integration/*.bats ${SCRIPT_DIR}/tests/performance/*.bats"
    shift
    if [ $# -gt 0 ]; then
        TEST_FILES="$TEST_FILES $@"
        CUSTOM_FILES="$@"
    fi
else
    # Run specific test files - determine categories from file paths
    TEST_FILES="$@"
    CUSTOM_FILES="$@"
    for test_file in "$@"; do
        if [[ "$test_file" == *"tests/unit"* ]]; then
            RUN_UNIT=true
        elif [[ "$test_file" == *"tests/integration"* ]]; then
            RUN_INTEGRATION=true
        elif [[ "$test_file" == *"tests/performance"* ]]; then
            RUN_PERFORMANCE=true
        fi
    done
fi

# Run the tests
echo -e "${YELLOW}Running tests...${NC}"
echo ""

# Track overall exit code and per-category results
OVERALL_EXIT=0
UNIT_EXIT=0
INTEGRATION_EXIT=0
PERFORMANCE_EXIT=0
FIRST_FILE=true

# Function to run tests for a specific category
run_test_category() {
    local category="$1"
    local category_files="$2"
    local category_exit=0
    
    if [ -z "$category_files" ]; then
        return 0
    fi
    
    local has_tests=false
    for test_file in $category_files; do
        if [ -f "$test_file" ]; then
            has_tests=true
            break
        fi
    done
    
    if [ "$has_tests" = false ]; then
        return 0
    fi
    
    echo -e "${BLUE}Running ${category} tests...${NC}"
    echo ""
    
    for test_file in $category_files; do
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
            category_exit=$FILE_EXIT
            OVERALL_EXIT=$FILE_EXIT
        fi
    done
    
    return $category_exit
}

# Run tests by category and track results
if [ "$RUN_UNIT" = true ]; then
    UNIT_FILES="${SCRIPT_DIR}/tests/unit/*.bats"
    if [ -n "$CUSTOM_FILES" ]; then
        # Filter custom files to only unit tests
        UNIT_FILES=""
        for file in $CUSTOM_FILES; do
            if [[ "$file" == *"tests/unit"* ]] && [ -f "$file" ]; then
                UNIT_FILES="$UNIT_FILES $file"
            fi
        done
        [ -z "$UNIT_FILES" ] && UNIT_FILES="${SCRIPT_DIR}/tests/unit/*.bats"
    fi
    run_test_category "unit" "$UNIT_FILES"
    UNIT_EXIT=$?
    echo ""
fi

if [ "$RUN_INTEGRATION" = true ]; then
    INTEGRATION_FILES="${SCRIPT_DIR}/tests/integration/*.bats"
    if [ -n "$CUSTOM_FILES" ]; then
        # Filter custom files to only integration tests
        INTEGRATION_FILES=""
        for file in $CUSTOM_FILES; do
            if [[ "$file" == *"tests/integration"* ]] && [ -f "$file" ]; then
                INTEGRATION_FILES="$INTEGRATION_FILES $file"
            fi
        done
        [ -z "$INTEGRATION_FILES" ] && INTEGRATION_FILES="${SCRIPT_DIR}/tests/integration/*.bats"
    fi
    run_test_category "integration" "$INTEGRATION_FILES"
    INTEGRATION_EXIT=$?
    echo ""
fi

if [ "$RUN_PERFORMANCE" = true ]; then
    PERFORMANCE_FILES="${SCRIPT_DIR}/tests/performance/*.bats"
    if [ -n "$CUSTOM_FILES" ]; then
        # Filter custom files to only performance tests
        PERFORMANCE_FILES=""
        for file in $CUSTOM_FILES; do
            if [[ "$file" == *"tests/performance"* ]] && [ -f "$file" ]; then
                PERFORMANCE_FILES="$PERFORMANCE_FILES $file"
            fi
        done
        [ -z "$PERFORMANCE_FILES" ] && PERFORMANCE_FILES="${SCRIPT_DIR}/tests/performance/*.bats"
    fi
    run_test_category "performance" "$PERFORMANCE_FILES"
    PERFORMANCE_EXIT=$?
    echo ""
fi

# Determine overall exit code
EXIT_CODE=$OVERALL_EXIT

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
else
    echo -e "${RED}✗ Some tests failed${NC}"
fi

# Function to update test badges in README.md
update_test_badges() {
    local readme_file="${SCRIPT_DIR}/README.md"
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    if [ ! -f "$readme_file" ]; then
        echo "Warning: README.md not found, skipping badge update" >&2
        return 1
    fi
    
    # Determine badge status for each category
    local unit_badge=""
    local integration_badge=""
    local performance_badge=""
    
    if [ "$RUN_UNIT" = true ]; then
        if [ "$UNIT_EXIT" -eq 0 ]; then
            unit_badge="[![Unit Tests](https://img.shields.io/badge/unit%20tests-passing-brightgreen)](tests/unit)"
        else
            unit_badge="[![Unit Tests](https://img.shields.io/badge/unit%20tests-failing-red)](tests/unit)"
        fi
    fi
    
    if [ "$RUN_INTEGRATION" = true ]; then
        if [ "$INTEGRATION_EXIT" -eq 0 ]; then
            integration_badge="[![Integration Tests](https://img.shields.io/badge/integration%20tests-passing-brightgreen)](tests/integration)"
        else
            integration_badge="[![Integration Tests](https://img.shields.io/badge/integration%20tests-failing-red)](tests/integration)"
        fi
    fi
    
    if [ "$RUN_PERFORMANCE" = true ]; then
        if [ "$PERFORMANCE_EXIT" -eq 0 ]; then
            performance_badge="[![Performance Tests](https://img.shields.io/badge/performance%20tests-passing-brightgreen)](tests/performance)"
        else
            performance_badge="[![Performance Tests](https://img.shields.io/badge/performance%20tests-failing-red)](tests/performance)"
        fi
    fi
    
    # Create a temporary file for the updated README
    local temp_file=$(mktemp)
    local in_badge_section=false
    local badges_written=false
    local found_unit=false
    local found_integration=false
    local found_performance=false
    
    # Process README line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Check if we're in the badge section (starts with badge, ends before first heading)
        if [[ "$line" =~ ^\[!\[.*\]\(https://img.shields.io.*badge.*tests ]]; then
            in_badge_section=true
            # Check which badge this is and update if we ran that category
            if [[ "$line" =~ Unit[[:space:]]*Tests ]] || [[ "$line" =~ unit.*tests ]] || [[ "$line" =~ badge/unit ]]; then
                found_unit=true
                if [ -n "$unit_badge" ]; then
                    echo "$unit_badge"
                else
                    echo "$line"  # Keep existing badge if we didn't run unit tests
                fi
            elif [[ "$line" =~ Integration[[:space:]]*Tests ]] || [[ "$line" =~ integration.*tests ]] || [[ "$line" =~ badge/integration ]]; then
                found_integration=true
                if [ -n "$integration_badge" ]; then
                    echo "$integration_badge"
                else
                    echo "$line"  # Keep existing badge if we didn't run integration tests
                fi
            elif [[ "$line" =~ Performance[[:space:]]*Tests ]] || [[ "$line" =~ performance.*tests ]] || [[ "$line" =~ badge/performance ]]; then
                found_performance=true
                if [ -n "$performance_badge" ]; then
                    echo "$performance_badge"
                else
                    echo "$line"  # Keep existing badge if we didn't run performance tests
                fi
            else
                # Old generic badge or unknown badge - skip it (we'll replace with category badges)
                continue
            fi
            continue
        fi
        
        # Check if we hit a heading (starts with #) - end of badge section
        if [[ "$line" =~ ^#+[[:space:]] ]] && [ "$in_badge_section" = true ]; then
            in_badge_section=false
            # Write any new badges before the heading if we haven't already
            if [ "$badges_written" = false ]; then
                # Write badges in order: unit, integration, performance
                if [ -n "$unit_badge" ] && [ "$found_unit" = false ]; then
                    echo "$unit_badge"
                fi
                if [ -n "$integration_badge" ] && [ "$found_integration" = false ]; then
                    echo "$integration_badge"
                fi
                if [ -n "$performance_badge" ] && [ "$found_performance" = false ]; then
                    echo "$performance_badge"
                fi
                # Update timestamp
                echo "<!-- Tests last run: ${timestamp} -->"
                echo ""
                badges_written=true
            fi
            echo "$line"
            continue
        fi
        
        # Skip old timestamp comments (we'll add a new one)
        if echo "$line" | grep -q "^<!--[[:space:]]*Tests[[:space:]]*last[[:space:]]*run:"; then
            continue
        fi
        
        # If we're still in badge section, skip empty lines
        if [ "$in_badge_section" = true ]; then
            if [[ -z "$line" ]]; then
                continue
            fi
            # If it's not a badge and not empty, we've left the badge section
            in_badge_section=false
        fi
        
        # Write the line normally
        echo "$line"
    done < "$readme_file" > "$temp_file"
    
    # If badges weren't written (no heading found or file starts with badges), prepend them
    if [ "$badges_written" = false ]; then
        {
            [ -n "$unit_badge" ] && echo "$unit_badge"
            [ -n "$integration_badge" ] && echo "$integration_badge"
            [ -n "$performance_badge" ] && echo "$performance_badge"
            echo "<!-- Tests last run: ${timestamp} -->"
            echo ""
            cat "$temp_file"
        } > "${temp_file}.new"
        mv "${temp_file}.new" "$temp_file"
    fi
    
    # Replace original file with updated version
    mv "$temp_file" "$readme_file"
    
    local updated_categories=""
    [ -n "$unit_badge" ] && updated_categories="${updated_categories}unit "
    [ -n "$integration_badge" ] && updated_categories="${updated_categories}integration "
    [ -n "$performance_badge" ] && updated_categories="${updated_categories}performance "
    
    echo "Updated test badges in README.md: ${updated_categories}" >&2
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
        
        # Build commit message with category information
        local categories=""
        [ "$RUN_UNIT" = true ] && categories="${categories}unit "
        [ "$RUN_INTEGRATION" = true ] && categories="${categories}integration "
        [ "$RUN_PERFORMANCE" = true ] && categories="${categories}performance "
        
        local commit_message="Update test status badges: ${categories}[skip ci]"
        if git commit -m "$commit_message" > /dev/null 2>&1; then
            echo "Committed test badge updates to README.md" >&2
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

# Update badges and commit if tests were run
if [ "$RUN_UNIT" = true ] || [ "$RUN_INTEGRATION" = true ] || [ "$RUN_PERFORMANCE" = true ]; then
    echo ""
    echo -e "${BLUE}Updating test status badges...${NC}"
    update_test_badges
    
    echo -e "${BLUE}Committing README.md changes...${NC}"
    commit_readme_changes
    echo ""
fi

exit $EXIT_CODE

