#!/bin/bash

# Emoji README Resume Example - Task 2: Follow-up Badges and Structure
# Demonstrates resuming existing sandbox with different tools and follow-up task

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

# Get sandbox name from command line argument
SANDBOX_NAME="$1"
if [ -z "$SANDBOX_NAME" ]; then
    echo "❌ Error: Sandbox name required"
    echo "Usage: $0 <sandbox_name>"
    echo "Example: $0 emoji-08071410"
    exit 1
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

# Task 2 configuration
TASK2_PROMPT="$SCRIPT_DIR/task2-badges-and-structure.txt"
AGENTS_DIR="$SCRIPT_DIR/agents"
TASK2_TOOLS="$SCRIPT_DIR/task2-tools.json"

# Validate required files exist

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

echo "Resuming: $SANDBOX_NAME"

# Check current task state
echo "State:"
(cd "$SCRIPT_DIR/../../.." && ./bin/taskstate -state ~/state.json status) || true

# Execute cs-cc in resume mode with different tools (prefer built binary)
cd "$REPO_ROOT"
./bin/cs-cc \
  --resume "$SANDBOX_NAME" \
  -p "$TASK2_PROMPT" \
  -t "$TASK2_TOOLS" \
  --task-id "badges-structure-task" \
  --debug yes

echo "✅ Task 2 done"