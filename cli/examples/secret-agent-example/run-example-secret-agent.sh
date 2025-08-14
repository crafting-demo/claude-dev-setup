#!/bin/bash

# Secret Agent Invocation Example
# Mirrors emoji example parameters; validates actual subagent invocation

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR/../../..}"
REPO="crafting-test1/claude_test"
BRANCH="main"

SANDBOX_NAME="cs-cc-secret-agent"

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
    echo "Usage: GITHUB_TOKEN=your_token_here ./run-example-secret-agent.sh"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable is required"
    echo "Usage: ANTHROPIC_API_KEY=your_key_here GITHUB_TOKEN=your_token_here ./run-example-secret-agent.sh"
    exit 1
fi

echo "🎯 Running secret agent example"
echo "📁 This example will:"
echo "   1. Clone the repository: $REPO"
echo "   2. Transfer a single agent: secret-agent"
echo "   3. Instruct Claude to use the secret-agent subagent"
echo "   4. Return favorites as JSON (or NO_AGENT_INVOCATION if not actually invoked)"
echo ""

# Execute the cs-cc command (Go CLI). Prefer built binary; no Node fallback.
(cd "$REPO_ROOT" && \
  if [ -x ./bin/cs-cc ]; then \
    ./bin/cs-cc \
      -p "$PROMPT_FILE" \
      --github-repo "$REPO" \
      --github-token "$GITHUB_TOKEN" \
      --github-branch "$BRANCH" \
      --pool "claude-dev-pool" \
      --template "cc-pool-test-temp" \
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
      --pool "claude-dev-pool" \
      --template "cc-pool-test-temp" \
      --agents-dir "$AGENTS_DIR" \
      -t "$TOOL_WHITELIST_FILE" \
      -n "$SANDBOX_NAME" \
      -d no \
      --debug yes; \
  fi)

echo ""
echo "✅ Secret agent example completed!"
echo "📋 Check the sandbox logs to verify:"
echo "   • Agent file present under ~/.claude/agents/secret-agent.md"
echo "   • Stream shows explicit subagent usage, not inline emulation"
echo "   • Output is JSON with expected values: {color: 'cyan', number: 26, bird: 'blue jay'}"


