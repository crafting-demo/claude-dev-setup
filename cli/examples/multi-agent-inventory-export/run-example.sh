#!/bin/bash

# Multi-Agent Inventory Export Example
# Demonstrates a three-agent workflow: software_engineer → qa_analyst → documentation_writer
# Task: Add 'Export Current Inventory to CSV' feature with GitHub PR

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR/../../..}"
REPO="crafting-test1/claude_test"
BRANCH="main"
SANDBOX_NAME="cs-cc-inv-ex"

# Configuration files
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

# Check for required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable is required"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable is required"
    exit 1
fi

# Execute the cs-cc command (Go CLI). Prefer built binary; no Node fallback.
(cd "$REPO_ROOT" && \
  if [ -x ./bin/cs-cc ]; then \
    ./bin/cs-cc \
      -p "$PROMPT_FILE" \
      --github-repo "$REPO" \
      --github-token "$GITHUB_TOKEN" \
      --github-branch "$BRANCH" \
      --agents-dir "$AGENTS_DIR" \
      -t "$TOOL_WHITELIST_FILE" \
      -n "$SANDBOX_NAME" \
      -d no \
      --debug yes; \
  else \
    go run ./cmd/cs-cc \
      -p "$PROMPT_FILE" \
      --github-repo "$REPO" \
      --github-token "$GITHUB_TOKEN" \
      --github-branch "$BRANCH" \
      --agents-dir "$AGENTS_DIR" \
      -t "$TOOL_WHITELIST_FILE" \
      -n "$SANDBOX_NAME" \
      -d no \
      --debug yes; \
  fi)