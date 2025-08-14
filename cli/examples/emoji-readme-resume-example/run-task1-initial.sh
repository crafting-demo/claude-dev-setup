#!/bin/bash

# Emoji README Resume Example - Task 1: Initial Emoji Enhancement
# Demonstrates creating initial sandbox with task management system

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR/../../..}"
REPO="crafting-test1/claude_test"
BRANCH="main"

# Task 1 configuration
TASK1_PROMPT="$SCRIPT_DIR/task1-emoji-enhancement.txt"
AGENTS_DIR="$SCRIPT_DIR/agents"
TOOL_WHITELIST="$SCRIPT_DIR/tool-whitelist.json"

# Check for required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable is required"
    echo "Usage: GITHUB_TOKEN=your_token_here ./run-task1-initial.sh"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable is required"
    echo "Usage: ANTHROPIC_API_KEY=your_key_here GITHUB_TOKEN=your_token_here ./run-task1-initial.sh"
    exit 1
fi

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

# Generate sandbox name (max 20 chars)
SANDBOX_NAME="emoji-$(date +%m%d%H%M)"
echo "📦 Sandbox name: $SANDBOX_NAME"

# Execute cs-cc with task management for initial task (Go CLI)
echo "Executing initial task with cs-cc (Go)..."
(cd "$REPO_ROOT" && \
  if [ -x ./bin/cs-cc ]; then \
    ./bin/cs-cc \
      -p "$TASK1_PROMPT" \
      --github-repo "$REPO" \
      --github-token "$GITHUB_TOKEN" \
      --github-branch "$BRANCH" \
      --agents-dir "$AGENTS_DIR" \
      -t "$TOOL_WHITELIST" \
      --task-id "emoji-enhancement-task" \
      --pool "claude-dev-pool" \
      --template "cc-pool-test-temp" \
      -n "$SANDBOX_NAME" \
      -d no \
      --debug yes; \
  elif command -v go >/dev/null 2>&1; then \
    go run ./cmd/cs-cc \
      -p "$TASK1_PROMPT" \
      --github-repo "$REPO" \
      --github-token "$GITHUB_TOKEN" \
      --github-branch "$BRANCH" \
      --agents-dir "$AGENTS_DIR" \
      -t "$TOOL_WHITELIST" \
      --task-id "emoji-enhancement-task" \
      --pool "claude-dev-pool" \
      --template "cc-pool-test-temp" \
      -n "$SANDBOX_NAME" \
      -d no \
      --debug yes; \
  else \
    node ./cli/cs-cc \
      -p "$TASK1_PROMPT" \
      -r "$REPO" \
      -ght "$GITHUB_TOKEN" \
      -b "$BRANCH" \
      -ad "$AGENTS_DIR" \
      -t "$TOOL_WHITELIST" \
      -tid "emoji-enhancement-task" \
      -pool "claude-dev-pool" \
      -template "cc-pool-test-temp" \
      -n "$SANDBOX_NAME" \
      -d no \
      --debug yes; \
  fi)

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Task 1 completed successfully!"
    echo "📦 Sandbox name: $SANDBOX_NAME"
    echo "📊 Check task state with: go run ./cmd/taskstate -state ~/state.json status"
    echo "🔄 Next step: Run run-task2-followup.sh $SANDBOX_NAME to add the second task"
else
    echo ""
    echo "❌ Task 1 failed"
    exit 1
fi