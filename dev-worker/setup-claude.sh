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
        echo "  1. Navigate to your workspace: cd ~/claude/claude-workspace"
        echo "  2. Test Claude Code: claude --version"
        echo "  3. Start using Claude Code: claude"
        echo
        print_warning "Note: You'll need to authenticate with your Anthropic API key when you first run Claude Code"
        return 0
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

# Step 8: Configure MCP servers and tools from $HOME/cmd/ files
print_status "Configuring MCP servers and tools..."

# Set working directory to project root
cd "$HOME/claude" || {
    print_error "Could not change to $HOME/claude directory"
    exit 1
}

# Function to configure local MCP server if local tools are defined
configure_local_mcp_server() {
    local local_mcp_file="$HOME/cmd/local_mcp_tools.txt"
    
    print_status "Current directory before MCP config: $(pwd)"
    print_status "Current user: $(whoami)"
    
    cd "$HOME/claude" || {
        print_error "Could not change to claude workspace directory"
        return 1
    }
    
    print_status "Changed to directory: $(pwd)"
    
    if [ -f "$local_mcp_file" ]; then
        print_status "Found local MCP tools configuration, setting up local MCP server..."
        
        # Check if the local MCP server exists
        local mcp_server_path="$HOME/claude/dev-worker/local_mcp_server/local-mcp-server.js"
        if [ ! -f "$mcp_server_path" ]; then
            print_error "Local MCP server not found at $mcp_server_path"
            return 1
        fi
        
        # Ensure the MCP server path is owned by the current user
        sudo chown -R "$USER:$USER" "$HOME/claude/dev-worker/local_mcp_server" 2>/dev/null || true
        
        # Change to the claude workspace directory where .mcp.json should be created
        cd "$HOME/claude" || {
            print_error "Could not change to claude workspace directory"
            return 1
        }
        
        print_status "Configuring MCP server in directory: $(pwd)"
        
        # Add local MCP server to Claude Code configuration
        if claude mcp add local_server node "$mcp_server_path" --scope project 2>/dev/null; then
            print_success "Local MCP server configured successfully"
        else
            print_warning "Failed to configure local MCP server, trying alternative approach..."
            # Create .mcp.json manually if claude mcp add fails
            cat > .mcp.json << EOF
{
  "mcpServers": {
    "local_server": {
      "type": "stdio",
      "command": "node",
      "args": ["$mcp_server_path"],
      "env": {}
    }
  }
}
EOF
            # Ensure the config file is owned by the current user
            chown "$USER:$USER" .mcp.json 2>/dev/null || true
            print_success "Local MCP server configured via .mcp.json"
        fi
        
        # Verify the configuration was created
        if [ -f ".mcp.json" ]; then
            print_status "MCP configuration file created successfully:"
            cat .mcp.json
        else
            print_warning "No .mcp.json file found after configuration attempt"
        fi
        # After creating .mcp.json manually
        chown owner:owner .mcp.json 2>/dev/null || true
        print_status "Set .mcp.json ownership to owner:owner"
    else
        print_status "No local MCP tools configuration found, skipping local server setup"
    fi
}

# Function to configure external MCP servers
configure_external_mcp_servers() {
    local external_mcp_file="$HOME/cmd/external_mcp.txt"
    
    if [ -f "$external_mcp_file" ]; then
        print_status "Found external MCP configuration, setting up external servers..."
        
        # Read and parse external MCP configuration
        if [ -s "$external_mcp_file" ]; then
            # Check if it's valid JSON
            if python3 -m json.tool "$external_mcp_file" > /dev/null 2>&1; then
                # Parse JSON and configure servers
                python3 << EOF
import json
import subprocess
import sys

try:
    with open('$external_mcp_file', 'r') as f:
        config = json.load(f)
    
    if 'servers' in config:
        for server_name, server_config in config['servers'].items():
            print(f"Configuring external MCP server: {server_name}")
            
            # Build claude mcp add command
            cmd = ['claude', 'mcp', 'add', server_name, '--scope', 'project']
            
            if 'command' in server_config:
                cmd.extend(['--command', server_config['command']])
            
            if 'args' in server_config:
                for arg in server_config['args']:
                    cmd.extend(['--args', arg])
            
            # Add environment variables if present
            if 'env' in server_config:
                for env_var, env_val in server_config['env'].items():
                    cmd.extend(['--env', f'{env_var}={env_val}'])
            
            # Execute command
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                print(f"✓ Configured {server_name} successfully")
            else:
                print(f"✗ Failed to configure {server_name}: {result.stderr}")
    
except Exception as e:
    print(f"Error parsing external MCP config: {e}")
    sys.exit(1)
EOF
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
    fi
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
                # Extract tools from JSON array
                python3 -c "
import json
with open('$whitelist_file', 'r') as f:
    tools = json.load(f)
    if isinstance(tools, list):
        for tool in tools:
            print(tool)
" > /tmp/tool_whitelist.tmp
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

# Execute MCP configuration steps
print_status "Current directory before executing MCP config: $(pwd)"
print_status "Current user: $(whoami)"
configure_local_mcp_server
configure_external_mcp_servers
configure_tool_whitelist
setup_prompt

# Verify MCP configuration
print_status "Verifying MCP configuration..."
if claude mcp list > /dev/null 2>&1; then
    print_success "MCP configuration verification passed"
    # Show configured servers
    print_status "Configured MCP servers:"
    claude mcp list 2>/dev/null || echo "  (No servers configured)"
else
    print_warning "MCP configuration verification failed, but installation may still work"
fi

# Final success message
echo
print_success "🎉 Claude Code setup with MCP configuration completed successfully!"
echo
print_status "Configuration Summary:"
echo "  • Claude Code: Installed and verified"
echo "  • MCP Servers: Configured from /cmd/ directory"
echo "  • Tool Whitelist: Applied if provided"
echo "  • Prompt: Ready from $HOME/cmd/prompt.txt"
echo
print_status "Next steps:"
echo "  1. Navigate to your workspace: cd ~/claude"
echo "  2. Test Claude Code: claude --version"
echo "  3. List MCP servers: claude mcp list"
echo "  4. Start using Claude Code with MCP tools"
echo
print_warning "Note: You'll need to authenticate with your Anthropic API key when you first run Claude Code" 