#!/bin/bash

# Secure Authentication Pipeline Example
# Demonstrates sequential subagent orchestration: software_engineer → security_analyst → documentation_writer
# Task: Implement secure JWT authentication with security hardening and comprehensive documentation

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_PATH="$SCRIPT_DIR/../../cs-cc"
REPO="crafting-test1/claude_test"
BRANCH="main"
SANDBOX_NAME="cs-cc-secure-auth"

# Configuration files
PROMPT_FILE="$SCRIPT_DIR/orchestration-prompt.txt"
MCP_TOOLS_FILE="$SCRIPT_DIR/mcp-tools.json"
TOOL_WHITELIST_FILE="$SCRIPT_DIR/tool-whitelist.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔐 Secure Authentication Pipeline Example${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""
echo -e "This example demonstrates ${YELLOW}sequential subagent orchestration${NC} with:"
echo -e "  ${GREEN}1. Software Engineer${NC} → Implements JWT authentication system"
echo -e "  ${GREEN}2. Security Analyst${NC} → Reviews and hardens security"  
echo -e "  ${GREEN}3. Documentation Writer${NC} → Creates comprehensive security docs"
echo ""

# Validate required files exist
if [ ! -f "$CLI_PATH" ]; then
    echo -e "❌ ${RED}Error: cs-cc CLI not found at $CLI_PATH${NC}"
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "❌ ${RED}Error: Orchestration prompt not found at $PROMPT_FILE${NC}"
    exit 1
fi

if [ ! -f "$MCP_TOOLS_FILE" ]; then
    echo -e "❌ ${RED}Error: MCP tools file not found at $MCP_TOOLS_FILE${NC}"
    exit 1
fi

if [ ! -f "$TOOL_WHITELIST_FILE" ]; then
    echo -e "❌ ${RED}Error: Tool whitelist file not found at $TOOL_WHITELIST_FILE${NC}"
    exit 1
fi

# Check for required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "❌ ${RED}Error: GITHUB_TOKEN environment variable is required${NC}"
    echo -e "   ${YELLOW}Set it with: export GITHUB_TOKEN=\"your_github_token\"${NC}"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo -e "❌ ${RED}Error: ANTHROPIC_API_KEY environment variable is required${NC}"
    echo -e "   ${YELLOW}Set it with: export ANTHROPIC_API_KEY=\"your_anthropic_api_key\"${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites validated${NC}"
echo -e "${BLUE}🚀 Launching sequential subagent workflow...${NC}"
echo ""

# Execute the cs-cc command
$CLI_PATH \
  -p "$PROMPT_FILE" \
  -r "$REPO" \
  -ght "$GITHUB_TOKEN" \
  -b "$BRANCH" \
  -lmc "$MCP_TOOLS_FILE" \
  -t "$TOOL_WHITELIST_FILE" \
  -n "$SANDBOX_NAME" \
  -d no \
  --debug yes