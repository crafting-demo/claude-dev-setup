#!/bin/bash

# Emoji README Resume Example - Task 1: Initial Emoji Enhancement
# Demonstrates creating initial sandbox with task management system

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_PATH="$SCRIPT_DIR/../../cs-cc"
REPO="crafting-test1/claude_test"
BRANCH="main"

# Task 1 configuration
TASK1_PROMPT="$SCRIPT_DIR/task1-emoji-enhancement.txt"
AGENTS_DIR="$SCRIPT_DIR/agents"
TOOL_WHITELIST="$SCRIPT_DIR/tool-whitelist.json"

# Validate required files exist
if [ ! -f "$CLI_PATH" ]; then
    echo "❌ Error: cs-cc CLI not found at $CLI_PATH"
    exit 1
fi

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

# Generate sandbox name
SANDBOX_NAME="emoji-resume-$(date +%m%d-%H%M)"
echo "📦 Sandbox name: $SANDBOX_NAME"

# Execute cs-cc with task management for initial task
echo "Executing initial task with cs-cc..."
"$CLI_PATH" \
    -p "$TASK1_PROMPT" \
    -r "$REPO" \
    -b "$BRANCH" \
    -ad "$AGENTS_DIR" \
    -t "$TOOL_WHITELIST" \
    -tid "emoji-enhancement-task" \
    -n "$SANDBOX_NAME" \
    -d no \
    --debug yes

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Task 1 completed successfully!"
    echo "📦 Sandbox name: $SANDBOX_NAME"
    echo "📊 Check task state with: dev-worker/task-state-manager.sh status"
    echo "🔄 Next step: Run run-task2-followup.sh $SANDBOX_NAME to add the second task"
else
    echo ""
    echo "❌ Task 1 failed"
    exit 1
fi