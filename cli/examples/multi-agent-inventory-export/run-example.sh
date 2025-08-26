#!/bin/bash

# Multi-Agent Inventory Export Example
# Demonstrates a three-agent workflow: software_engineer → qa_analyst → documentation_writer
# Task: Add 'Export Current Inventory to CSV' feature with GitHub PR

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."
PROMPT_FILE="$SCRIPT_DIR/orchestration-prompt.txt"
AGENTS_DIR="$SCRIPT_DIR/agents"
TOOL_WHITELIST_FILE="$SCRIPT_DIR/tool-whitelist.json"

# Validate required files exist
if [ ! -f "$PROMPT_FILE" ]; then
    echo "❌ Error: Orchestration prompt not found at $PROMPT_FILE"
    exit 1
fi

if [ ! -d "$AGENTS_DIR" ]; then
    echo "❌ Error: Agents directory not found at $AGENTS_DIR"
    exit 1
fi

if [ ! -f "$TOOL_WHITELIST_FILE" ]; then
    echo "❌ Error: Tool whitelist file not found at $TOOL_WHITELIST_FILE"
    exit 1
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"

cd "$REPO_ROOT"
./bin/cs-cc \
  -p "$PROMPT_FILE" \
  --github-repo "crafting-test1/claude_test" \
  --github-token "$GITHUB_TOKEN" \
  --github-branch "main" \
  --agents-dir "$AGENTS_DIR" \
  -t "$TOOL_WHITELIST_FILE" \
  -n "cs-cc-inv-ex" \
  --debug yes