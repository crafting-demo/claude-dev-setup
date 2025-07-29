# Claude Code Dev Agent on Crafting

Launch developer agents in Crafting sandboxes using the `cs-cc` CLI. Create ephemeral development environments that can work on GitHub issues, pull requests, or branches with full Claude Code integration.

## Features

- **Direct CLI interface** - Launch agents without GitHub polling/watching
- **GitHub integration** - Work on issues, PRs, or specific branches
- **Multi-agent workflows** - Coordinate multiple specialized agents via MCP tools
- **Vertex AI support** - Use Claude models through GCP Vertex AI
- **Crafting native** - All work happens in ephemeral sandboxes

## Quick Start

1. **Create the template** in your Crafting dashboard named `claude-code-automation` using `claude-code-automation/template.yaml`
2. **Set environment variables** in your sandbox with `ANTHROPIC_API_KEY` secret access
3. **Use the CLI**:
   ```bash
   ./cli/cs-cc -p "Fix the login bug" -r "owner/repo" -ght "your_token" -pr 123
   ```

## CLI Usage

```
cs-cc - Claude Sandbox Code CLI

Usage: cs-cc [options]

Options:
  -p, --prompt <value>           Prompt string or file path (required)
  -pool <name>                   Sandbox pool name (optional)
  -r, --repo <owner/repo>        GitHub repository (required for GitHub integration)
  -ght, --github-token <token>   GitHub access token (required for GitHub integration)
  -pr, --pull-request <number>   Pull request number (mutually exclusive with -i, -b)
  -i, --issue <number>           Issue number (mutually exclusive with -pr, -b)
  -b, --branch <name>            Branch name (mutually exclusive with -pr, -i)
  -mc, --mcp-config <value>      External MCP config string or file path (optional)
  -lmc, --local-mcp-config <value> Local MCP tools config string or file path (optional)
  -t, --tools <value>            Tool whitelist string or file path (optional)
  -template, --template <value>  Custom template name (default: claude-code-automation)
  -d, --delete-when-done <yes|no> Delete sandbox when done (default: yes)
  -n, --name <name>              Sandbox name (default: auto-generated)
  --debug <yes|no>               Debug mode: wait for worker completion and show all output (default: no)
  --dry-run                      Validate parameters and show commands without execution
  --help                         Show this help message
```

## Examples

Comprehensive examples with multi-agent workflows, GitHub integration, and various configurations are available in the [cli directory](./cli/examples).

## Template Setup

1. **Create the Claude Code Worker Template** in your Crafting dashboard named `claude-code-automation` using the `template.yaml` file in the `claude-code-automation/` directory
2. **Set environment variables** - Ensure `ANTHROPIC_API_KEY` is configured as a Crafting secret path in your sandbox environment

## Using Claude models with GCP Vertex AI 

To use Claude models through GCP Vertex AI instead of direct Anthropic API:

1. **Enable Vertex AI** with Claude models in your GCP account
2. **Create a service account** with `AI Platform Developer` and `Vertex AI User` roles
3. **Add the service account JSON key** as a Crafting secret (e.g., `gcp-vertex-key.json`)
4. **Configure environment variables** in `claude-code-automation/template.yaml`:
   ```yaml
   - GOOGLE_APPLICATION_CREDENTIALS=/run/sandbox/fs/secrets/shared/gcp-vertex-key.json
   - ANTHROPIC_VERTEX_PROJECT_ID=YOUR-GCP-PROJECT-ID
   - CLAUDE_CODE_USE_VERTEX=1
   - CLOUD_ML_REGION=us-east5
   ```