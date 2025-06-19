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

# Function to clean up corrupted Claude Code installations
cleanup_claude_installation() {
    local claude_dir="$HOME/.npm-global/lib/node_modules/@anthropic-ai"
    
    if [ -d "$claude_dir" ]; then
        print_status "Checking for corrupted Claude Code installation..."
        
        # Remove any temporary directories from failed npm operations
        find "$claude_dir" -name ".claude-code-*" -type d 2>/dev/null | while read -r temp_dir; do
            if [ -d "$temp_dir" ]; then
                print_warning "Removing corrupted temporary directory: $(basename "$temp_dir")"
                rm -rf "$temp_dir"
            fi
        done
        
        # If claude-code directory exists but claude command doesn't work, clean it up
        if [ -d "$claude_dir/claude-code" ] && ! command_exists claude; then
            print_warning "Found broken Claude Code installation, removing it..."
            rm -rf "$claude_dir/claude-code"
        fi
    fi
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

# Step 1: claude-workspace directory is now created by manifest.yaml

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

# Step 4: Clean up any corrupted installations
cleanup_claude_installation

# Step 5: Check if Claude Code is already properly installed
print_status "Checking for existing Claude Code installation..."
if command_exists claude; then
    CURRENT_VERSION=$(claude --version 2>/dev/null || echo "unknown")
    print_warning "Claude Code is already installed (version: $CURRENT_VERSION)"
    
    # Ask if user wants to reinstall (or provide --force flag)
    if [[ "${1:-}" == "--force" ]] || [[ "${1:-}" == "-f" ]]; then
        print_status "Force flag detected, reinstalling Claude Code..."
        npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
        cleanup_claude_installation
    else
        print_status "Use --force or -f flag to reinstall, or skip to verification step"
        print_success "Claude Code is already installed and working"
        # Skip to verification
        echo
        print_success "🎉 Claude Code setup completed successfully!"
        echo
        print_status "Next steps:"
        echo "  1. Navigate to your workspace: cd ~/claude-workspace"
        echo "  2. Test Claude Code: claude --version"
        echo "  3. Start using Claude Code: claude"
        echo
        print_warning "Note: You'll need to authenticate with your Anthropic API key when you first run Claude Code"
        exit 0
    fi
fi

# Step 6: Install Claude Code
print_status "Installing Claude Code globally..."
if npm install -g @anthropic-ai/claude-code; then
    print_success "Claude Code installed successfully"
else
    print_error "Failed to install Claude Code"
    print_warning "This might be due to a corrupted npm cache. Try running: npm cache clean --force"
    exit 1
fi

# Step 7: Verify installation
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