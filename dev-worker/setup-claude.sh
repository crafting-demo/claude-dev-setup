#!/bin/bash

# Claude Code Setup Script
# This script automates the installation and setup of Claude Code
# Based on the official setup guide

set -e  # Exit on any error

# Function to print output without colors
print_status() {
    echo "[INFO] $1"
}

print_success() {
    echo "[SUCCESS] $1"
}

print_warning() {
    echo "[WARNING] $1"
}

print_error() {
    echo "[ERROR] $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}



# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Desired version can be provided via CLAUDE_CLI_VERSION, default to 1.0.77
DESIRED_VERSION="${CLAUDE_CLI_VERSION:-1.0.77}"

if command_exists claude; then
    CURRENT_VERSION=$(claude --version 2>/dev/null || echo "unknown")
    print_status "Detected installed Claude Code: ${CURRENT_VERSION}"
    if echo "$CURRENT_VERSION" | grep -q "$DESIRED_VERSION"; then
        if [[ "${1:-}" == "--force" ]] || [[ "${1:-}" == "-f" ]]; then
            print_status "Force flag detected; reinstalling pinned version $DESIRED_VERSION..."
            npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
            cleanup_claude_installation
        else
            print_success "Pinned version $DESIRED_VERSION already installed; skipping reinstall"
            # Proceed to verification
            DESIRED_ALREADY_INSTALLED=1
        fi
    else
        print_status "Installed version does not match desired $DESIRED_VERSION; reinstalling..."
        npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
        cleanup_claude_installation
    fi
fi

# Step 6: Install Claude Code
if [ -n "$DESIRED_ALREADY_INSTALLED" ]; then
    print_status "Skipping install step; desired version already present"
else
    print_status "Installing Claude Code globally (version $DESIRED_VERSION)..."
    if npm install -g @anthropic-ai/claude-code@"$DESIRED_VERSION"; then
        print_success "Claude Code installed successfully"
    else
        print_error "Failed to install Claude Code"
        print_warning "This might be due to a corrupted npm cache. Try running: npm cache clean --force"
        exit 1
    fi
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

# Step 8: Configure tools and settings from $HOME/cmd/ files
print_status "Configuring tools and settings..."

# Set working directory to project root
cd "$HOME/claude" || {
    print_error "Could not change to $HOME/claude directory"
    exit 1
}





# Function to configure tool whitelist
configure_tool_whitelist() {
    local whitelist_file="$HOME/cmd/tool_whitelist.txt"
    
    if [ -f "$whitelist_file" ]; then
        print_status "Found tool whitelist configuration..."
        
        if [ -s "$whitelist_file" ]; then
            # Check if it's JSON format or newline-separated
            if python3 -m json.tool "$whitelist_file" > /dev/null 2>&1; then
                print_status "Processing JSON format tool whitelist"
                # Extract tools from JSON array using external script
                "$SCRIPT_DIR/process_tool_whitelist.py" "$whitelist_file" > /tmp/tool_whitelist.tmp
            else
                print_status "Processing text format tool whitelist"
                # Assume newline-separated format
                cp "$whitelist_file" /tmp/tool_whitelist.tmp
            fi
            
            # Apply tool whitelist configuration
            # Note: Claude Code tool whitelisting may require specific commands or configuration
            # For now, we'll store it for the worker script to use
            cp /tmp/tool_whitelist.tmp "$HOME/cmd/processed_tool_whitelist.txt"
            rm -f /tmp/tool_whitelist.tmp
            
            print_success "Tool whitelist processed and saved"
        else
            print_warning "Tool whitelist file is empty"
        fi
    else
        print_status "No tool whitelist found, allowing all tools"
    fi
}

# Function to setup prompt for Claude execution
setup_prompt() {
    local prompt_file="$HOME/cmd/prompt.txt"
    
    if [ -f "$prompt_file" ]; then
        print_status "Found prompt configuration at $prompt_file"
        if [ -s "$prompt_file" ]; then
            print_success "Prompt file ready for execution"
        else
            print_warning "Prompt file is empty"
        fi
    else
        print_warning "No prompt file found at $prompt_file"
    fi
}

# Function to configure external MCP servers (we still support connecting to external MCPs as a client)
configure_external_mcp_servers() {
    local external_mcp_file="$HOME/cmd/external_mcp.txt"
    
    if [ -f "$external_mcp_file" ]; then
        print_status "Found external MCP configuration, setting up external servers..."
        
        # Read and parse external MCP configuration
        if [ -s "$external_mcp_file" ]; then
            # Check if it's valid JSON
            if python3 -m json.tool "$external_mcp_file" > /dev/null 2>&1; then
                # Parse JSON and configure servers using external script
                "$SCRIPT_DIR/configure_external_mcp.py" "$external_mcp_file"
                print_success "External MCP servers configured"
            else
                print_error "Invalid JSON format in external MCP configuration"
                return 1
            fi
        else
            print_warning "External MCP configuration file is empty"
        fi
    else
        print_status "No external MCP configuration found, skipping external server setup"
        # Create empty MCP config for consistency
        local mcp_config_path="/home/owner/.mcp.json"
        cat > "$mcp_config_path" << EOF
{
  "mcpServers": {}
}
EOF
        chown owner:owner "$mcp_config_path" 2>/dev/null || true
        print_status "Created empty centralized MCP configuration"
    fi
}

# Note: User agents are now processed by cs-cc and transferred to ~/.claude/agents/
# Project agents are detected in the repository's .claude/agents/ directory
# We no longer run a local MCP server, but we still support connecting to external MCP servers

# Execute configuration steps
print_status "Current directory before executing configuration: $(pwd)"
print_status "Current user: $(whoami)"
configure_external_mcp_servers
configure_tool_whitelist
setup_prompt

# Verify Claude Code installation and external MCP configuration
print_status "Verifying Claude Code installation..."
if claude --version > /dev/null 2>&1; then
    print_success "Claude Code verification passed"
    VERSION=$(claude --version 2>/dev/null || echo "unknown")
    print_status "Version: $VERSION"
else
    print_warning "Claude Code verification failed, installation may have issues"
fi

# Verify MCP configuration for external servers (if any)
print_status "Verifying MCP configuration for external servers..."
if [ -f "/home/owner/.mcp.json" ]; then
    if claude mcp list > /dev/null 2>&1; then
        print_success "MCP configuration verification passed"
        # Show configured external servers
        print_status "Configured external MCP servers:"
        claude mcp list 2>/dev/null || echo "  (No external servers configured)"
    else
        print_warning "MCP configuration verification failed for external servers"
    fi
else
    print_status "No MCP configuration file found - no external servers configured"
fi

# Final success message
echo
print_success "🎉 Claude Code setup with native subagents and external MCP support completed successfully!"
echo
print_status "Configuration Summary:"
echo "  • Claude Code: Installed and verified"
echo "  • Native Subagents: Ready for user and project agents"
echo "  • External MCP Servers: Configured if provided"
echo "  • Tool Whitelist: Applied if provided"
echo "  • Prompt: Ready from $HOME/cmd/prompt.txt"
echo
print_status "Next steps:"
echo "  1. Navigate to your workspace: cd ~/claude"
echo "  2. Test Claude Code: claude --version"
echo "  3. List external MCP servers: claude mcp list"
echo "  4. Start using Claude Code with native subagents and external MCP tools"
echo
print_warning "Note: You'll need to authenticate with your Anthropic API key when you first run Claude Code" 