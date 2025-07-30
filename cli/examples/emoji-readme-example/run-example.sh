#!/bin/bash

# Emoji README Enhancement Example
# Demonstrates a simple single-agent workflow using Claude Code automation
# Task: Enhance README.md with emojis and better formatting

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_PATH="$SCRIPT_DIR/../../cs-cc"
REPO="crafting-test1/claude_test"
BRANCH="main"
SANDBOX_NAME="cs-cc-emoji-ex"

# Configuration files
PROMPT_FILE="$SCRIPT_DIR/orchestration-prompt.txt"
MCP_TOOLS_FILE="$SCRIPT_DIR/mcp-tools.json"
TOOL_WHITELIST_FILE="$SCRIPT_DIR/tool-whitelist.json"

# Validate required files exist
if [ ! -f "$CLI_PATH" ]; then
    echo "❌ Error: cs-cc CLI not found at $CLI_PATH"
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    echo "❌ Error: Orchestration prompt not found at $PROMPT_FILE"
    exit 1
fi

if [ ! -f "$MCP_TOOLS_FILE" ]; then
    echo "❌ Error: MCP tools file not found at $MCP_TOOLS_FILE"
    exit 1
fi

if [ ! -f "$TOOL_WHITELIST_FILE" ]; then
    echo "❌ Error: Tool whitelist file not found at $TOOL_WHITELIST_FILE"
    exit 1
fi

# Check for required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable is required"
    echo "Usage: GITHUB_TOKEN=your_token_here ./run-example.sh"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable is required"
    echo "Usage: ANTHROPIC_API_KEY=your_key_here GITHUB_TOKEN=your_token_here ./run-example.sh"
    exit 1
fi

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