package worker

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestWriteCentralMCPConfig_WritesEmptyWhenMissing(t *testing.T) {
	tmp := t.TempDir()
	cmdDir := filepath.Join(tmp, "cmd")
	homeDir := filepath.Join(tmp, "home")
	if err := os.MkdirAll(cmdDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(homeDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := WriteCentralMCPConfig(cmdDir, homeDir); err != nil {
		t.Fatalf("write mcp: %v", err)
	}
	b, err := os.ReadFile(filepath.Join(homeDir, ".mcp.json"))
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}
	if _, ok := m["mcpServers"]; !ok {
		t.Fatalf("expected mcpServers key")
	}
}
