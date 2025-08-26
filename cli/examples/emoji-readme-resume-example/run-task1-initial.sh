#!/bin/bash

# Emoji README Resume Example - Task 1: Initial Emoji Enhancement
# Demonstrates creating initial sandbox with task management system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

# Task 1 configuration
TASK1_PROMPT="$SCRIPT_DIR/task1-emoji-enhancement.txt"
AGENTS_DIR="$SCRIPT_DIR/agents"
TOOL_WHITELIST="$SCRIPT_DIR/tool-whitelist.json"

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

# Validate required files exist

if [ ! -f "$TASK1_PROMPT" ]; then
    echo "❌ Error: Task 1 prompt not found at $TASK1_PROMPT"
    exit 1
fi

if [ ! -d "$AGENTS_DIR" ]; then
    echo "❌ Error: Agents directory not found at $AGENTS_DIR"
    exit 1
fi

if [ ! -f "$TOOL_WHITELIST" ]; then
    echo "❌ Error: Tool whitelist not found at $TOOL_WHITELIST"
    exit 1
fi

echo "🚀 Starting Emoji README Resume Example - Task 1"
echo "📁 Using repository: $REPO"
echo "🌿 Using branch: $BRANCH"
echo "📝 Task 1 prompt: $TASK1_PROMPT"
echo "🤖 Agents directory: $AGENTS_DIR"
echo "🔧 Tool whitelist: $TOOL_WHITELIST"
echo ""

SANDBOX_NAME="emoji-$(date +%m%d%H%M)"

# Execute cs-cc with task management for initial task (Go CLI)
cd "$REPO_ROOT"
./bin/cs-cc \
  -p "$TASK1_PROMPT" \
  --github-repo "crafting-test1/claude_test" \
  --github-token "$GITHUB_TOKEN" \
  --github-branch "main" \
  --agents-dir "$AGENTS_DIR" \
  -t "$TOOL_WHITELIST" \
  --task-id "emoji-enhancement-task" \
  --template "cc-pool-test-temp" \
  -n "$SANDBOX_NAME" \
  --debug yes

echo "✅ Task 1 done: $SANDBOX_NAME"