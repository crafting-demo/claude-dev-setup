#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$SCRIPT_DIR/../../..}"
SB_NAME="fastsb-test"
REPO="${REPO:-crafting-test1/claude_test}"
BRANCH="${BRANCH:-main}"
PROMPT_FILE="$SCRIPT_DIR/orchestration-prompt.txt"
AGENTS_DIR="$SCRIPT_DIR/agents"
TOOL_WHITELIST_FILE="$SCRIPT_DIR/tool-whitelist.json"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: prompt missing at $PROMPT_FILE" >&2
  exit 1
fi
if [ ! -d "$AGENTS_DIR" ]; then
  echo "Error: agents dir missing at $AGENTS_DIR" >&2
  exit 1
fi
if [ ! -f "$TOOL_WHITELIST_FILE" ]; then
  echo "Error: tools file missing at $TOOL_WHITELIST_FILE" >&2
  exit 1
fi

(
  cd "$REPO_ROOT"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    TOKEN_ARGS=(--github-token "$GITHUB_TOKEN")
  else
    TOKEN_ARGS=()
  fi
  if [ -x ./bin/cs-cc ]; then
    ./bin/cs-cc \
      -p "$PROMPT_FILE" \
      --github-repo "$REPO" \
      --github-branch "$BRANCH" \
      ${TOKEN_ARGS:+"${TOKEN_ARGS[@]}"} \
      --agents-dir "$AGENTS_DIR" \
      --template "cc-pool-test-temp" \
      -t "$TOOL_WHITELIST_FILE" \
      -n "$SB_NAME" \
      -d no
  else
    go run ./cmd/cs-cc \
      -p "$PROMPT_FILE" \
      --github-repo "$REPO" \
      --github-branch "$BRANCH" \
      ${TOKEN_ARGS:+"${TOKEN_ARGS[@]}"} \
      --agents-dir "$AGENTS_DIR" \
      --template "cc-pool-test-temp" \
      -t "$TOOL_WHITELIST_FILE" \
      -n "$SB_NAME" \
      -d no
  fi
)

echo "Verifying sandbox inputs via cs exec..."
cs exec -u 1000 -W "$SB_NAME/claude" -- sh -lc 'ls -la /home/owner/cmd | cat'
cs exec -u 1000 -W "$SB_NAME/claude" -- sh -lc 'test -f /home/owner/cmd/prompt.txt && echo "OK: prompt.txt present"'
cs exec -u 1000 -W "$SB_NAME/claude" -- sh -lc 'ls -la /home/owner/.claude/agents | cat'

echo "Waiting up to 3 minutes for hello.txt to be created by the worker..."
sleep 180
cs exec -u 1000 -W "$SB_NAME/claude" -- sh -lc 'test -f "$HOME/hello.txt" && echo "OK: hello.txt found" || (echo "MISSING: hello.txt"; exit 1)'

echo "Done. Sandbox: $SB_NAME"


