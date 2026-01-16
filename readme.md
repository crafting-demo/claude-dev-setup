# GitHub PR Watcher for Claude Reviews

This repo provides a simple GitHub PR watcher that runs on a cron schedule, creates a review sandbox for new PRs, runs Claude Code to review the PR, and posts a comment back on the PR.

## How it works

1. **Watcher** (`gh-watcher/`) polls GitHub every 5 minutes (via `.sandbox/manifest.yaml`).
2. When it sees a new or updated PR, it creates a sandbox (`cs sandbox create`).
3. The watcher transfers a review prompt and GitHub context into `/home/owner/cmd`.
4. The sandbox runs `~/claude/dev-worker/start-worker.sh`, which launches the Go worker and Claude Code.
5. Claude posts a single review comment on the PR using `gh pr comment`.

## Quick setup

1. **Ensure the worker definition file is present**: `claude-code-automation/template.yaml`.
2. **Ensure secrets are available** in the template environment:
   - `ANTHROPIC_API_KEY`
3. **Configure the watcher**:
   - `gh-watcher/watchlist.txt` with `owner/repo` lines
   - Optional env vars:
     - `PROCESS_EXISTING_PRS=true` to review existing PRs on first run
     - `PR_LABELS=review-me,ready` to only process labeled PRs
4. **Run the watcher**:
   - In a sandbox: `.sandbox/manifest.yaml` runs it every 5 minutes
   - Locally for smoke test:
     ```bash
     cd gh-watcher
     npm install
     npm run watch
     ```

## Environment variables (watcher)

- `GITHUB_TOKEN` (required)
- `PROCESS_EXISTING_PRS` (optional)
- `PR_LABELS` (optional; comma-separated)
- `CMD_DIR` (optional; default `/home/owner/cmd`)
- `SANDBOX_DEF_PATH` (optional; default `../claude-code-automation/template.yaml`)
- `SANDBOX_TEMPLATE_NAME` (optional; if set, uses a named template instead of the local definition file)

## Optional: cs-cc CLI

`cs-cc` still exists for ad-hoc orchestration of a single sandbox + prompt, but it is not required for the watcher flow.

## Tests

```bash
make test
```
