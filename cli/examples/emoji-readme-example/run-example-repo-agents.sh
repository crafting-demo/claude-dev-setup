#!/bin/bash

# Emoji README Enhancement Example - Repository Agents
# Demonstrates agent detection from repository itself instead of CLI agents flag
# Task: Enhance README.md with emojis and better formatting using agents from repo/agents/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."
PROMPT_FILE="$SCRIPT_DIR/orchestration-prompt.txt"
TOOL_WHITELIST_FILE="$SCRIPT_DIR/tool-whitelist.json"

# Note: NO AGENTS_DIR - we will rely on repository agents detection

# Validate required files exist

if [ ! -f "$PROMPT_FILE" ]; then
    echo "❌ Error: Orchestration prompt not found at $PROMPT_FILE"
    exit 1
fi

if [ ! -f "$TOOL_WHITELIST_FILE" ]; then
    echo "❌ Error: Tool whitelist file not found at $TOOL_WHITELIST_FILE"
    exit 1
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

echo "🎯 Running emoji enhancement example with repository agent detection"
echo "📁 This example will:"
echo "   1. Clone the repository: $REPO"
echo "   2. Look for agents in the repository's /agents/ directory"
echo "   3. Use those agents (not CLI-provided agents) for the task"
echo "   4. Enhance README.md with emojis and formatting"
echo ""
echo "💡 Expected: The target repository should contain an /agents/ directory with emoji_enhancer.json"
echo ""

cd "$REPO_ROOT"
./bin/cs-cc \
  -p "$PROMPT_FILE" \
  --github-repo "crafting-test1/claude_test" \
  --github-token "$GITHUB_TOKEN" \
  --github-branch "main" \
  --repo-path "working-repo" \
  --template "cc-pool-test-temp" \
  -t "$TOOL_WHITELIST_FILE" \
  -n "cs-cc-repo-agents" \
  --debug yes

echo "✅ Done"