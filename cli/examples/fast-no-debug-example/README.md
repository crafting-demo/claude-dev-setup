# Fast No-Debug Example

A minimal example that runs without `--debug` and verifies results using `cs exec`.

## Files
- `run-example.sh` — launches a sandbox and transfers prompt/agents/tools
- `orchestration-prompt.txt` — asks to create `~/hello.txt` and print a confirmation line
- `agents/hello-writer.md` — simple agent with YAML frontmatter
- `tool-whitelist.json` — allows basic write/edit/run tools

## Run
```bash
export ANTHROPIC_API_KEY=your_key
cd fast-no-debug-example
./run-example.sh
```

## Verify
The script runs `cs exec` to:
- list `/home/owner/cmd`
- check `prompt.txt` exists
- list `~/.claude/agents`

You can also check for the file later:
```bash
cs exec -u 1000 -W "$SANDBOX_NAME/claude" -- sh -lc 'test -f "$HOME/hello.txt" && echo FOUND || echo MISSING'
```
