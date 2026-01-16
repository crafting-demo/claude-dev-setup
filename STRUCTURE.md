# Repo Structure

```
claude-dev-setup/
├── .sandbox/                   # Cron job for watcher
│   └── manifest.yaml
├── gh-watcher/                 # GitHub PR watcher (Node)
│   ├── src/
│   ├── watchlist.txt
│   └── package.json
├── claude-code-automation/     # Worker sandbox template
│   └── template.yaml
├── cmd/                        # Go binaries
│   ├── cs-cc                   # Optional orchestration CLI
│   ├── taskstate               # Taskstate helper
│   └── worker                  # Claude worker runner
├── dev-worker/                 # Worker scripts (Claude Code setup + run)
│   └── start-worker.sh
├── pkg/                        # Shared Go packages
├── bin/                        # Built binaries
├── Makefile
└── readme.md
```

## Key flow

- `gh-watcher` polls GitHub, builds a review prompt, and creates a sandbox.
- The watcher transfers inputs into `/home/owner/cmd` inside the sandbox.
- `dev-worker/start-worker.sh` runs the Go worker which executes Claude Code.
- Claude posts a review comment via `gh pr comment`.
