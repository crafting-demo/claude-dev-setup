#!/bin/bash

# Claude Code Worker Script (minimal wrapper)
# This script ensures PATH/toolchain and invokes the Go worker. Legacy logic removed.

set -e  # Exit on any error

# Function to print output without colors
print_status() {
	echo "[INFO] $1" >&2
}

print_success() {
	echo "[SUCCESS] $1" >&2
}

print_error() {
	echo "[ERROR] $1" >&2
}

# Go worker is mandatory; legacy path removed
if [ "${USE_GO_WORKER:-true}" != "true" ]; then
	print_error "Legacy path removed; set USE_GO_WORKER=true"
	exit 1
fi

print_status "=== Claude Code Automation Workflow ==="

# Ensure Go toolchain
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/setup-go.sh" ]; then
	print_status "Ensuring Go toolchain is available..."
	bash "$SCRIPT_DIR/setup-go.sh" || true
fi

# Ensure PATH includes npm global (Claude CLI), node/go common locations
export PATH="$HOME/.npm-global/bin:$HOME/.local/go/bin:/usr/local/go/bin:/usr/local/node/bin:$PATH"

# Invoke Go worker from repo root
if [ -d "$HOME/claude" ]; then
	print_status "Attempting Go worker path..."
	if (cd "$HOME/claude" && go run ./cmd/worker); then
		print_success "Go worker completed"
		exit 0
	else
		print_error "Go worker failed; aborting per migration plan"
		exit 1
	fi
else
	print_error "Repository directory not found: $HOME/claude"
	exit 1
fi