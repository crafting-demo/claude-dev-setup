# Claude Dev Setup - File Structure

This document outlines the organized file structure for the Claude Dev Setup project components.

## 📁 Directory Structure

```
claude-dev-setup/
├── cli/                          # CS-CC Command Line Interface
│   └── cs-cc                     # Main CLI executable
├── dev-worker/                   # Dev Worker Components
│   ├── local_mcp_server/         # Local MCP Server Implementation
│   │   ├── package.json          # Node.js dependencies for MCP server
│   │   ├── local-mcp-server.js   # MCP server implementation
│   │   └── test-local-mcp-tools.txt  # Example tool configuration
│   ├── setup-claude.sh           # Claude Code installation script
│   ├── start-worker.sh           # Worker startup script
│   └── initialize_worker.sh      # Worker initialization
├── gh-watcher/                   # GitHub Watcher (legacy)
├── claude-code-automation/       # Sandbox template
└── *.md, *.json                  # Documentation and config files
```

## 🚀 Component Overview

### CLI (`/cli`)
- **cs-cc**: Command-line interface for creating dev-worker sandboxes
- Handles parameter parsing, GitHub integration, MCP configuration
- Transfers configurations to sandbox via SCP

### Local MCP Server (`/dev-worker/local_mcp_server`)
- **local-mcp-server.js**: MCP protocol implementation for LLM-backed tools
- **package.json**: Node.js dependencies (@modelcontextprotocol/sdk)
- **test-local-mcp-tools.txt**: Example configuration showing tool definition format

### Dev Worker Scripts (`/dev-worker`)
- **setup-claude.sh**: Installs and configures Claude Code
- **start-worker.sh**: Starts worker with MCP server integration
- **initialize_worker.sh**: Initial worker setup

## 🔧 Usage

### CLI Usage
```bash
# From claude-dev-setup root
./cli/cs-cc -p "prompt" -r "owner/repo" -ght "token" -pr 123

# Add to PATH for global access
export PATH="$PATH:/path/to/claude-dev-setup/cli"
cs-cc --help
```

### MCP Server Usage
```bash
# From dev-worker/local_mcp_server
npm install
node local-mcp-server.js
```

## 📋 Integration Flow

1. **cs-cc CLI** creates sandbox and transfers configs to `$HOME/cmd/`
2. **setup-claude.sh** configures Claude Code with MCP integration
3. **start-worker.sh** starts local MCP server and Claude Code
4. **local-mcp-server.js** serves LLM-backed tools to Claude Code via MCP protocol

## 🔗 File Relationships

- CLI reads configurations and transfers to sandbox
- MCP server reads `$HOME/cmd/local_mcp_tools.txt` for tool definitions
- Worker scripts orchestrate startup sequence and integration
- All components work together to provide seamless LLM-backed tool experience 