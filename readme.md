# Claude Code Dev Agent on Crafting (CLI)

Launch developer agents in Crafting sandboxes using the `cs-cc` CLI. Create ephemeral development environments that can work on GitHub issues, pull requests, or branches with full Claude Code integration.

## Features

- **cs-cc** — Fast, robust CLI for launching agent sandboxes
- **Direct CLI interface** — Launch agents without GitHub polling/watching
- **GitHub integration** — Work on issues, PRs, or specific branches
- **Multi-agent workflows** — Coordinate specialized subagents; external MCP servers are supported as clients
- **Vertex AI support** — Use Claude models through GCP Vertex AI
- **Crafting native** — All work happens in ephemeral sandboxes

## What you can do

- Create a fresh sandbox with an initial task (using a template and optional pool)
- Queue additional tasks into a single sandbox to run sequentially
- Run in debug mode (foreground, stream output) or non-debug mode (background)
- Use a completion handler pattern to trigger scripts when work finishes
- Specify a sandbox pool and template during creation

## Install on Linux

Quick installs from the latest GitHub Release:

- User-local:
```bash
install -Dm755 <(curl -L "https://github.com/crafting-demo/claude-dev-setup/releases/download/v0.1.0/cs-cc") "$HOME/.local/bin/cs-cc"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Quick Start

1. Create the template in your Crafting dashboard named `claude-code-automation` using `claude-code-automation/template.yaml`
2. Ensure sandbox env has `ANTHROPIC_API_KEY` access
3. Run the CLI (binary):
   ```bash
   cs-cc -p "Fix the login bug" --github-repo owner/repo --action-type branch --github-branch main --dry-run
   ```

## Core workflows

### Create a fresh sandbox with an initial task

```bash
# Create and run with a named sandbox, template, and optional pool
cs-cc \
  -p ./cli/examples/emoji-readme-example/orchestration-prompt.txt \
  --github-repo owner/repo \
  --action-type branch \
  --github-branch main \
  --template "claude-code-automation" \
  --pool "standard" \
  -n "cw-docs-demo" \
  --debug yes
```

- --template: sandbox template name (default `claude-code-automation`)
- --pool: optional pool name to create in a specific resource pool
- --debug yes: run worker in foreground and stream output until completion

To run in background (non-debug):

```bash
cs-cc \
  -p ./cli/examples/fast-no-debug-example/orchestration-prompt.txt \
  --github-repo owner/repo \
  --github-branch main \
  --template "claude-code-automation" \
  -n "cw-fast-demo" \
  --debug no \
  -d no
```

This returns immediately and starts the worker in the sandbox. Logs stream to `~/worker.log` inside the sandbox.

### Queue additional tasks into an existing sandbox (resume)

After a sandbox exists (e.g., `cw-docs-demo`), queue another task into the same sandbox:

```bash
./bin/cs-cc \
  -p "Add badges and improve README structure" \
  --resume cw-docs-demo \
  --task-id task-badges-001 \
  --debug yes
```

Notes:
- `--resume <sandbox>` reuses the same sandbox; `cs-cc` transfers `prompt_new.txt` and sets `task_mode.txt=resume`.
- The worker will enqueue a new task (with the provided `--task-id` if set) and run it next.

You can repeat `--resume` calls to add a queue of tasks. See `cli/examples/emoji-readme-resume-example`.

## Completion handler

After the worker finishes successfully, the dev worker calls a completion script if present:

- Path: `/home/owner/completion.sh`
- Arguments: the last task ID when available (from `~/state.json`)

Invocation pattern (from the sandbox):

```bash
bash /home/owner/completion.sh "$TASK_ID"
```

Define the completion script in the sandbox template (not via CLI). For example, extend the template overlay to install the script during post-checkout:

```yaml
workspaces:
    - name: claude
      system:
        files:
          - path: /home/owner/completion.sh
            owner: "1000:1000"
            mode: "0755"
            content: |
              #!/usr/bin/env bash
              TASK_ID="$1"
              echo "Completed task: ${TASK_ID}" >> "$HOME/completed.log"
```

With this in place, the worker will invoke `/home/owner/completion.sh "$TASK_ID"` automatically on success.

## CLI Usage (Go)

```
cs-cc (Go) - Claude Sandbox Code CLI

Flags:
  -p, --prompt string              Prompt string or file path (required)
      --github-repo string         GitHub repository (owner/repo)
      --action-type string         Action type: branch|pr|issue (default "branch")
      --github-branch string       Branch name (for action-type=branch)
      --pr-number string           Pull request number (for action-type=pr)
      --issue-number string        Issue number (for action-type=issue)
      --mcp-config string          External MCP config JSON string or file path
      --agents-dir string          Directory containing agent .md files
  -t, --tools string               Tool whitelist JSON string or file path
      --template string            Sandbox template name (default "claude-code-automation")
  -d, --delete-when-done string    Delete sandbox when done: yes|no (default "yes")
  -n, --name string                Sandbox name (auto-generated if empty)
      --resume string              Resume existing sandbox (skips creation)
      --task-id string             Custom task ID (optional)
      --repo-path string           Custom repo path inside sandbox
      --pool string                Sandbox pool name (optional)
      --github-token string        GitHub access token (optional; Crafting creds fallback)
      --cmd-dir string             Path to /home/owner/cmd (default "/home/owner/cmd")
      --debug string               Debug mode: yes|no (default "no")
      --dry-run                    Validate and print planned actions without executing
      --version                    Print version and exit
```

## Examples

Comprehensive examples with multi-agent workflows, GitHub integration, and various configurations are available in the [examples directory](./cli/examples/README.md):
- `emoji-readme-example/`: simple single-task run
- `emoji-readme-resume-example/`: two queued tasks in the same sandbox
- `fast-no-debug-example/`: background mode and simple verification
- `multi-agent-inventory-export/`: multi-agent, multi-step workflow

## Template Setup (Subagents by default)

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

## Testing

- Run all tests: `make test`
- Unit tests cover:
  - `pkg/config` loader for `/home/owner/cmd` contracts
  - `pkg/hostcli` validation of GitHub action context
  - `pkg/taskstate` queue and transitions
  - `pkg/worker` runner session linkage and completion
  - `pkg/permissions` and `pkg/mcp` basic behaviors
  - `cmd/cs-cc` dry-run flag handling and transfer previews

Planned: add integration tests to simulate end-to-end worker execution producing `~/session.json`, `~/state.json`, and `<repo>/.claude/settings.local.json`.

## Binaries

Built artifacts are placed in `bin/` by `make build` targets:

- `bin/cs-cc` — Go host CLI
- `bin/worker` — Go worker entrypoint

Use `make cs-cc` and `make worker` for explicit builds.

## Exit codes

The CLI uses explicit exit codes to make failure modes obvious:

- 0: success
- 2: validation error (args/contracts)
- 10: sandbox create/resume failure
- 11: file transfer failure (including agents copy)
- 20: worker bootstrap/background start failure (non-debug)
- 23: worker execution failure (debug mode)
- 30: unexpected error
