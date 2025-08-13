# Claude Dev Setup - File Structure

This document outlines the organized file structure for the Claude Dev Setup project components.

## 📁 Directory Structure

```
claude-dev-setup/
├── cli/                          # Legacy shell-based CS-CC CLI and examples
│   └── cs-cc                     # Legacy CLI entrypoint
├── cmd/                          # Go binaries (new)
│   ├── cs-cc                     # Host orchestrator CLI (validation, planning)
│   └── worker                    # Worker orchestration binary
├── pkg/                          # Shared Go packages (new)
│   ├── config                    # Contracts loader (/home/owner/cmd/*)
│   ├── taskstate                 # JSON queue current/queue/history
│   ├── worker                    # Minimal worker runner orchestration
│   ├── permissions               # settings.local.json generation
│   ├── mcp                       # Subagents interfaces + external MCP client hooks
│   └── claude                    # Stream-JSON parsing helpers
├── dev-worker/                   # Worker scripts (shell integration retained)
│   ├── setup-claude.sh           # Claude Code installation script
│   ├── start-worker.sh           # Worker startup script (calls Go worker)
│   └── task-state-manager.sh     # Legacy helper (being replaced by Go)
├── claude-code-automation/       # Sandbox template
└── *.md, *.json                  # Documentation and config files
```

## 🚀 Component Overview

### CLI (`/cmd/cs-cc` and `/cli`)
- New Go CLI (`/cmd/cs-cc`): validates args and orchestrator contracts.
- Legacy shell CLI (`/cli/cs-cc`): retained for compatibility and examples.

### Subagents and MCP
- Subagents: native Claude Code subagents are the default for internal tools.
- External MCP: supported via `/home/owner/cmd/external_mcp.txt`; worker connects as a client. No local MCP server runs.

### Dev Worker (`/cmd/worker` and `/dev-worker`)
- Go worker (`/cmd/worker`): loads contracts, updates `state.json`, links `session.json`.
- Scripts (`/dev-worker`): install/setup wrappers that invoke the Go worker and Claude Code.

## 🔧 Usage

### CLI Usage
```bash
# From claude-dev-setup root
./cli/cs-cc -p "prompt" -r "owner/repo" -ght "token" -pr 123

# Add to PATH for global access
export PATH="$PATH:/path/to/claude-dev-setup/cli"
cs-cc --help
```

### Subagents and External MCP
Subagents require agent definitions under `.claude/agents/*.md` in the target repo. External MCP servers are declared in `/home/owner/cmd/external_mcp.txt` (JSON); the worker connects as a client.

## 📋 Integration Flow

1. **cs-cc** creates/resumes sandbox and transfers configs to `$HOME/cmd/`.
2. **setup-claude.sh** configures Claude Code and prepares permissions.
3. **start-worker.sh** runs the Go worker and launches Claude Code; subagents are used by default.
4. External MCP servers (if any) are connected as clients per `external_mcp.txt`.

## 🔗 File Relationships

- CLI reads configurations and transfers to sandbox
- Subagents are defined in the target repo under `.claude/agents/`.
- External MCP servers are listed in `$HOME/cmd/external_mcp.txt`.
- Worker scripts orchestrate startup sequence using the Go worker.