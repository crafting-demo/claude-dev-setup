#!/bin/bash

# Initialize Worker Script
# This script orchestrates the Claude Code automation workflow
# 1. First sets up Claude Code via setup-claude.sh
# 2. Then executes the worker via start-worker.sh

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INIT]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[INIT SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[INIT WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[INIT ERROR]${NC} $1"
}

print_status "=== Claude Code Worker Initialization ==="

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Step 1: Run setup-claude.sh
print_status "Step 1: Setting up Claude Code..."
if [ -f "$SCRIPT_DIR/setup-claude.sh" ]; then
    print_status "Executing setup-claude.sh..."
    bash "$SCRIPT_DIR/setup-claude.sh"
    print_success "Claude Code setup completed"
    
    # Ensure PATH includes Claude Code after installation
    export PATH="$HOME/.npm-global/bin:$PATH"
    print_status "Updated PATH to include Claude Code installation directory"
else
    print_error "setup-claude.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Step 2: Run start-worker.sh
print_status "Step 2: Starting Claude Code worker..."
if [ -f "$SCRIPT_DIR/start-worker.sh" ]; then
    print_status "Executing start-worker.sh..."
    bash "$SCRIPT_DIR/start-worker.sh"
    print_success "Claude Code worker execution completed"
else
    print_error "start-worker.sh not found in $SCRIPT_DIR"
    exit 1
fi

print_success "=== Worker Initialization Completed Successfully ===" 