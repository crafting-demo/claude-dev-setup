package worker

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// WriteCentralMCPConfig reads external_mcp.txt (JSON) and writes ~/.mcp.json. If missing/empty, writes an empty structure.
func WriteCentralMCPConfig(cmdDir string, homeDir string) error {
	src := filepath.Join(cmdDir, "external_mcp.txt")
	var obj map[string]any
	if st, err := os.Stat(src); err == nil && !st.IsDir() {
		b, err := os.ReadFile(src)
		if err == nil && len(b) > 0 {
			if err := json.Unmarshal(b, &obj); err != nil {
				// Invalid JSON; fall back to empty
				obj = map[string]any{"mcpServers": map[string]any{}}
			}
		}
	}
	if obj == nil {
		obj = map[string]any{"mcpServers": map[string]any{}}
	}
	// Merge in local Subagent MCP server as a separate entry.
	servers, _ := obj["mcpServers"].(map[string]any)
	if servers == nil {
		servers = map[string]any{}
	}
	// Command will run the Go subagent server via `go run` for now; setup-go ensures Go is present.
	servers["subagents"] = map[string]any{
		"command": "go",
		"args":    []string{"run", "/home/owner/claude/cmd/subagent-mcp"},
		"env": map[string]string{
			"CMD_DIR":  cmdDir,
			"REPO_DIR": filepath.Join(homeDir, "claude", "target-repo"),
		},
	}
	obj["mcpServers"] = servers
	dest := filepath.Join(homeDir, ".mcp.json")
	b, err := json.MarshalIndent(obj, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(dest, b, 0o644)
}
