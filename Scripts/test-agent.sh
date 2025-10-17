#!/bin/bash
# ArkavoAgent Test Runner
# Quick test script for testing the ArkavoAgent Swift package

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 ArkavoAgent Test Suite${NC}"
echo "═══════════════════════════════════════════════════"
echo ""

# Check if arkavo-edge is running
if pgrep -x "arkavo" > /dev/null; then
    echo -e "${GREEN}✓${NC} arkavo-edge agent detected"
else
    echo -e "${YELLOW}⚠️  arkavo-edge agent not detected${NC}"
    echo "   Start it with: arkavo"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""

# Navigate to test directory
cd "$(dirname "$0")/../ArkavoAgentTest"

# Parse arguments
if [ "$1" = "--interactive" ]; then
    echo -e "${BLUE}🚀 Starting Interactive CLI...${NC}"
    echo ""
    swift run ArkavoAgentTest --interactive

elif [ "$1" = "--test" ] && [ -n "$2" ]; then
    echo -e "${BLUE}🔨 Building test tool...${NC}"
    swift build
    echo ""
    echo -e "${BLUE}🧪 Running test: $2${NC}"
    echo ""
    swift run ArkavoAgentTest --test "$2"

else
    echo -e "${BLUE}🔨 Building test tool...${NC}"
    swift build
    echo ""
    echo -e "${BLUE}🚀 Running all tests...${NC}"
    echo ""
    swift run ArkavoAgentTest --test-all
fi

echo ""
echo -e "${GREEN}✅ Test suite complete${NC}"
