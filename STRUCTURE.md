# Claude Dev Setup - File Structure

This document outlines the organized file structure for the Claude Dev Setup project components.

## 📁 Directory Structure

```
claude-dev-setup/
├── bin/                          # Built binaries (via make build)
│   └── cs-cc                     # Go host CLI binary
├── claude-code-automation/       # Sandbox template
│   └── template.yaml
├── cli/                          # Examples (shell workflows, agents, tool lists)
│   └── examples                  # Example scenarios
├── cmd/                          # Go binaries (new)
│   ├── cs-cc                     # Host orchestrator CLI (validation, planning)
│   ├── taskstate                 # Taskstate helper CLI
│   └── worker                    # Worker orchestration binary
├── dev-worker/                   # Worker scripts (shell integration retained)
│   ├── configure_external_mcp.py # Configure external MCP servers from JSON
│   ├── generate_permissions_json.py # Generate permissions JSON for Claude
│   ├── process_tool_whitelist.py # Normalize tool whitelist inputs
│   ├── setup-claude.sh           # Claude Code installation script
│   ├── setup-go.sh               # Go toolchain bootstrap for worker
│   ├── start-worker.sh           # Worker startup script (calls Go worker)
│   └── task-state-manager.sh     # Legacy helper (being replaced by Go)
├── pkg/                          # Shared Go packages (new)
│   ├── claude                    # Stream-JSON parsing helpers
│   ├── config                    # Contracts loader (/home/owner/cmd/*)
│   ├── github                    # GitHub helpers
│   ├── hostcli                   # Host CLI validation and planning
│   ├── mcp                       # Subagents interfaces + external MCP client hooks
│   ├── permissions               # settings.local.json generation
│   ├── sandbox                   # Sandbox orchestration helpers
│   ├── taskstate                 # JSON queue current/queue/history
│   └── worker                    # Minimal worker runner orchestration
├── go.mod, go.sum, Makefile      # Build and deps
└── *.md, *.json                  # Documentation and config files
```

## 🚀 Component Overview

### CLI (`/cmd/cs-cc` and `/bin`)
- New Go CLI (`/cmd/cs-cc`): validates args and orchestrator contracts; built to `bin/cs-cc`.
- Examples are provided under `/cli/examples` (no separate legacy CLI entrypoint).

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
make build

# Run host CLI (Go)
./bin/cs-cc --prompt "Fix the login bug" \
  --github-repo owner/repo \
  --action-type branch \
  --github-branch main \
  --dry-run

# Or via go run
go run ./cmd/cs-cc -p "Fix the login bug" \
  --github-repo owner/repo \
  --action-type branch \
  --github-branch main \
  --dry-run
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