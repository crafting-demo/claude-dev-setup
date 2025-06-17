#!/bin/bash

# Claude Code Setup Script
# This script automates the installation and setup of Claude Code
# Based on the official setup guide

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists npm; then
    print_error "npm is not installed. Please install Node.js and npm first."
    exit 1
fi

if ! command_exists node; then
    print_error "Node.js is not installed. Please install Node.js first."
    exit 1
fi

print_success "Prerequisites check passed"

# Step 1: Create claude-workspace directory
print_status "Creating claude-workspace directory..."
mkdir -p "$HOME/claude-workspace"
print_success "Created claude-workspace directory"

# Step 2: Setup npm global directory
print_status "Setting up npm global directory..."
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
print_success "Configured npm to use user-owned global directory"

# Step 3: Setup PATH in shell configuration files
print_status "Configuring PATH in shell files..."

PATH_EXPORT='export PATH="$HOME/.npm-global/bin:$PATH"'

# Add to .bashrc if it exists and doesn't already contain the export
if [ -f "$HOME/.bashrc" ]; then
    if ! grep -Fxq "$PATH_EXPORT" "$HOME/.bashrc" 2>/dev/null; then
        echo "$PATH_EXPORT" >> "$HOME/.bashrc"
        print_success "Added PATH export to .bashrc"
    else
        print_warning "PATH export already exists in .bashrc"
    fi
fi

# Add to .profile if it exists and doesn't already contain the export
if [ -f "$HOME/.profile" ]; then
    if ! grep -Fxq "$PATH_EXPORT" "$HOME/.profile" 2>/dev/null; then
        echo "$PATH_EXPORT" >> "$HOME/.profile"
        print_success "Added PATH export to .profile"
    else
        print_warning "PATH export already exists in .profile"
    fi
fi

# Export PATH for current session
export PATH="$HOME/.npm-global/bin:$PATH"
print_success "PATH configured for current session"

# Step 4: Install Claude Code
print_status "Installing Claude Code globally..."
if npm install -g @anthropic-ai/claude-code; then
    print_success "Claude Code installed successfully"
else
    print_error "Failed to install Claude Code"
    exit 1
fi

# Step 5: Verify installation
print_status "Verifying installation..."
if command_exists claude; then
    VERSION=$(claude --version 2>/dev/null || echo "unknown")
    print_success "Claude Code is installed and accessible"
    print_status "Version: $VERSION"
else
    print_error "Claude Code installation verification failed"
    print_warning "You may need to restart your terminal or run: source ~/.bashrc"
    exit 1
fi

# Final success message
echo
print_success "🎉 Claude Code setup completed successfully!"
echo
print_status "Next steps:"
echo "  1. Restart your terminal or run: source ~/.bashrc"
echo "  2. Navigate to your workspace: cd ~/claude-workspace"
echo "  3. Test Claude Code: claude --version"
echo "  4. Start using Claude Code: claude"
echo
print_warning "Note: You'll need to authenticate with your Anthropic API key when you first run Claude Code" 