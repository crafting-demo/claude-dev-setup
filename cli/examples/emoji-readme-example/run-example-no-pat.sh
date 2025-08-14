#!/bin/bash

# Emoji README Enhancement Example - No GitHub Token (Crafting Credentials)
# Demonstrates agent detection from repository AND Crafting credential usage
# Task: Enhance README.md with emojis and better formatting using agents from repo/agents/
# Authentication: Uses Crafting credential defaults instead of explicit GitHub token

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."
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
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

# Verify we're NOT setting GITHUB_TOKEN (to test Crafting fallback)
if [ -n "$GITHUB_TOKEN" ]; then
    echo "⚠️  Warning: GITHUB_TOKEN is set in environment"
    echo "   This example is designed to test Crafting credential fallback"
    echo "   Consider unsetting GITHUB_TOKEN: unset GITHUB_TOKEN"
    echo ""
fi

cd "$REPO_ROOT"
./bin/cs-cc \
  -p "$PROMPT_FILE" \
  --github-repo "crafting-test1/claude_test" \
  --github-branch "main" \
  --repo-path "working-repo" \
  --template "cc-pool-test-temp" \
  -t "$TOOL_WHITELIST_FILE" \
  -n "cs-cc-no-pat" \
  --debug yes