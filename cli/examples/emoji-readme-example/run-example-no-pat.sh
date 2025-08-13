#!/bin/bash

# Emoji README Enhancement Example - No GitHub Token (Crafting Credentials)
# Demonstrates agent detection from repository AND Crafting credential usage
# Task: Enhance README.md with emojis and better formatting using agents from repo/agents/
# Authentication: Uses Crafting credential defaults instead of explicit GitHub token

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."
REPO="crafting-test1/claude_test"
BRANCH="main"

SANDBOX_NAME="cs-cc-no-pat"

# Configuration files
PROMPT_FILE="$SCRIPT_DIR/orchestration-prompt.txt"
TOOL_WHITELIST_FILE="$SCRIPT_DIR/tool-whitelist.json"

# Note: NO AGENTS_DIR - we will rely on repository agents detection
# Note: NO GITHUB_TOKEN - we will rely on Crafting credential defaults

# Validate required files exist

if [ ! -f "$PROMPT_FILE" ]; then
    echo "❌ Error: Orchestration prompt not found at $PROMPT_FILE"
    exit 1
fi

if [ ! -f "$TOOL_WHITELIST_FILE" ]; then
    echo "❌ Error: Tool whitelist file not found at $TOOL_WHITELIST_FILE"
    exit 1
fi

# Check for required environment variables (only ANTHROPIC_API_KEY now)
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable is required"
    echo "Usage: ANTHROPIC_API_KEY=your_key_here ./run-example-no-pat.sh"
    exit 1
fi

# Verify we're NOT setting GITHUB_TOKEN (to test Crafting fallback)
if [ -n "$GITHUB_TOKEN" ]; then
    echo "⚠️  Warning: GITHUB_TOKEN is set in environment"
    echo "   This example is designed to test Crafting credential fallback"
    echo "   Consider unsetting GITHUB_TOKEN: unset GITHUB_TOKEN"
    echo ""
fi

echo "🎯 Running emoji enhancement example with Crafting credential authentication"
echo "📁 This example will:"
echo "   1. Clone the repository: $REPO"
echo "   2. Look for agents in the repository's /agents/ directory"
echo "   3. Use those agents (not CLI-provided agents) for the task"
echo "   4. Use Crafting credentials (NOT explicit GitHub token)"
echo "   5. Enhance README.md with emojis and formatting"
echo ""
echo "💡 Expected: The target repository should contain an /agents/ directory with emoji_enhancer.json"
echo "🔐 Expected: Crafting environment should provide GitHub credentials via wsenv"
echo ""

# Execute the cs-cc command WITHOUT -ght flag (Go CLI; testing Crafting credential fallback)
(cd "$REPO_ROOT" && go run ./cmd/cs-cc \
  -p "$PROMPT_FILE" \
  -r "$REPO" \
  -b "$BRANCH" \
  -rp "working-repo" \
  -pool "claude-dev-pool" \
  -template "cc-pool-test-temp" \
  -t "$TOOL_WHITELIST_FILE" \
  -n "$SANDBOX_NAME" \
  -d no \
  --debug yes)

echo ""
echo "✅ Emoji enhancement example completed with Crafting credentials!"
echo "📋 Check the sandbox logs to verify:"
echo "   • Repository agents directory detection"
echo "   • Agent loading from repository /agents/ directory"
echo "   • Crafting credential authentication (wsenv git-credentials)"
echo "   • Successful emoji enhancement execution"
echo ""
echo "🔍 Look for these log messages in the output:"
echo "   • 'No GitHub token provided, attempting to use Crafting credentials...'"
echo "   • 'Attempting to retrieve GitHub token from Crafting credentials...'"
echo "   • 'Successfully retrieved token from Crafting credentials'"
echo "   • 'GitHub CLI authenticated successfully via crafting token'"