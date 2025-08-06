#!/bin/bash

# Emoji README Enhancement Example - Repository Agents
# Demonstrates agent detection from repository itself instead of CLI agents flag
# Task: Enhance README.md with emojis and better formatting using agents from repo/agents/

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_PATH="$SCRIPT_DIR/../../cs-cc"
REPO="crafting-test1/claude_test"
BRANCH="main"

SANDBOX_NAME="cs-cc-repo-agents"

# Configuration files
PROMPT_FILE="$SCRIPT_DIR/orchestration-prompt.txt"
TOOL_WHITELIST_FILE="$SCRIPT_DIR/tool-whitelist.json"

# Note: NO AGENTS_DIR - we will rely on repository agents detection

# Validate required files exist
if [ ! -f "$CLI_PATH" ]; then
    echo "❌ Error: cs-cc CLI not found at $CLI_PATH"
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    echo "❌ Error: Orchestration prompt not found at $PROMPT_FILE"
    exit 1
fi

if [ ! -f "$TOOL_WHITELIST_FILE" ]; then
    echo "❌ Error: Tool whitelist file not found at $TOOL_WHITELIST_FILE"
    exit 1
fi

# Check for required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable is required"
    echo "Usage: GITHUB_TOKEN=your_token_here ./run-example-repo-agents.sh"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable is required"
    echo "Usage: ANTHROPIC_API_KEY=your_key_here GITHUB_TOKEN=your_token_here ./run-example-repo-agents.sh"
    exit 1
fi

echo "🎯 Running emoji enhancement example with repository agent detection"
echo "📁 This example will:"
echo "   1. Clone the repository: $REPO"
echo "   2. Look for agents in the repository's /agents/ directory"
echo "   3. Use those agents (not CLI-provided agents) for the task"
echo "   4. Enhance README.md with emojis and formatting"
echo ""
echo "💡 Expected: The target repository should contain an /agents/ directory with emoji_enhancer.json"
echo ""

# Execute the cs-cc command WITHOUT -ad flag
$CLI_PATH \
  -p "$PROMPT_FILE" \
  -r "$REPO" \
  -ght "$GITHUB_TOKEN" \
  -b "$BRANCH" \
  -rp "working-repo" \
  -pool "claude-dev-pool" \
  -template "cc-pool-test-temp" \
  -t "$TOOL_WHITELIST_FILE" \
  -n "$SANDBOX_NAME" \
  -d no \
  --debug yes

echo ""
echo "✅ Emoji enhancement example completed!"
echo "📋 Check the sandbox logs to verify:"
echo "   • Repository agents directory detection"
echo "   • Agent loading from repository /agents/ directory"
echo "   • Successful emoji enhancement execution"