#!/bin/bash

# Script to set up bats-core for testing
# This installs bats-core locally in the repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_HELPER_DIR="${SCRIPT_DIR}/test_helper"
BATS_DIR="${TEST_HELPER_DIR}/bats-core"
BATS_SUPPORT_DIR="${TEST_HELPER_DIR}/bats-support"
BATS_ASSERT_DIR="${TEST_HELPER_DIR}/bats-assert"

echo "Setting up bats-core and helper libraries for testing..."

# Create test_helper directory
mkdir -p "$TEST_HELPER_DIR"

# Install bats-core
if [ -d "$BATS_DIR" ] && [ -f "${BATS_DIR}/bin/bats" ]; then
    echo "✓ bats-core already installed"
else
    echo "Installing bats-core..."
    cd "$TEST_HELPER_DIR"
    if [ -d "bats-core" ]; then
        rm -rf bats-core
    fi
    git clone --depth 1 https://github.com/bats-core/bats-core.git bats-core
    cd bats-core
    ./install.sh "$BATS_DIR"
    echo "✓ bats-core installed"
fi

# Install bats-support
if [ -d "$BATS_SUPPORT_DIR" ]; then
    echo "✓ bats-support already installed"
else
    echo "Installing bats-support..."
    cd "$TEST_HELPER_DIR"
    git clone --depth 1 https://github.com/bats-core/bats-support.git
    echo "✓ bats-support installed"
fi

# Install bats-assert
if [ -d "$BATS_ASSERT_DIR" ]; then
    echo "✓ bats-assert already installed"
else
    echo "Installing bats-assert..."
    cd "$TEST_HELPER_DIR"
    git clone --depth 1 https://github.com/bats-core/bats-assert.git
    echo "✓ bats-assert installed"
fi

echo ""
echo "✓ All testing dependencies installed successfully!"
echo ""
echo "You can now run tests with:"
echo "  ./run-tests.sh"
echo "  or"
echo "  ./test_helper/bats-core/bin/bats tests/"
