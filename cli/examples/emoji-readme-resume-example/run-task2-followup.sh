#!/bin/bash

# Emoji README Resume Example - Task 2: Follow-up Badges and Structure
# Demonstrates resuming existing sandbox with different tools and follow-up task

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_PATH="$SCRIPT_DIR/../../cs-cc"

# Get sandbox name from command line argument
SANDBOX_NAME="$1"
if [ -z "$SANDBOX_NAME" ]; then
    echo "❌ Error: Sandbox name required"
    echo "Usage: $0 <sandbox_name>"
    echo "Example: $0 emoji-08071410"
    exit 1
fi

# Check for required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable is required"
    echo "Usage: GITHUB_TOKEN=your_token_here $0 <sandbox_name>"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable is required"
    echo "Usage: ANTHROPIC_API_KEY=your_key_here GITHUB_TOKEN=your_token_here $0 <sandbox_name>"
    exit 1
fi

# Task 2 configuration
TASK2_PROMPT="$SCRIPT_DIR/task2-badges-and-structure.txt"
AGENTS_DIR="$SCRIPT_DIR/agents"
TASK2_TOOLS="$SCRIPT_DIR/task2-tools.json"

# Validate required files exist
if [ ! -f "$CLI_PATH" ]; then
    echo "❌ Error: cs-cc CLI not found at $CLI_PATH"
    exit 1
fi

if [ ! -f "$TASK2_PROMPT" ]; then
    echo "❌ Error: Task 2 prompt not found at $TASK2_PROMPT"
    exit 1
fi

if [ ! -d "$AGENTS_DIR" ]; then
    echo "❌ Error: Agents directory not found at $AGENTS_DIR"
    exit 1
fi

if [ ! -f "$TASK2_TOOLS" ]; then
    echo "❌ Error: Task 2 tools not found at $TASK2_TOOLS"
    exit 1
fi

echo "🔄 Starting Emoji README Resume Example - Task 2 (Follow-up)"
echo "📦 Resuming sandbox: $SANDBOX_NAME"
echo "📝 Task 2 prompt: $TASK2_PROMPT"
echo "🤖 Agents directory: $AGENTS_DIR"
echo "🔧 Task 2 tools: $TASK2_TOOLS"
echo ""

# Check current task state
echo "📊 Current task state:"
"$SCRIPT_DIR/../../../dev-worker/task-state-manager.sh" status || echo "Could not read task state"
echo ""

# Execute cs-cc in resume mode with different tools
echo "Executing follow-up task with cs-cc in resume mode..."
"$CLI_PATH" \
    --resume "$SANDBOX_NAME" \
    -p "$TASK2_PROMPT" \
    -t "$TASK2_TOOLS" \
    -tid "badges-structure-task" \
    --debug yes

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Task 2 completed successfully!"
    echo "📊 Final task state:"
    "$SCRIPT_DIR/../../../dev-worker/task-state-manager.sh" status || echo "Could not read task state"
    echo ""
    echo "🎉 Multi-task workflow demonstration complete!"
    echo "📦 Sandbox: $SANDBOX_NAME"
else
    echo ""
    echo "❌ Task 2 failed"
    exit 1
fi