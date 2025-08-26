package worker

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGenerateRepoPermissions_JSONWhitelist(t *testing.T) {
	tmp := t.TempDir()
	cmdDir := filepath.Join(tmp, "cmd")
	repoDir := filepath.Join(tmp, "repo")
	if err := os.MkdirAll(cmdDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(repoDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cmdDir, "tool_whitelist.txt"), []byte("[\n \"Read\", \"Write\"\n]"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := GenerateRepoPermissions(cmdDir, repoDir); err != nil {
		t.Fatalf("gen perms: %v", err)
	}
	if _, err := os.Stat(filepath.Join(repoDir, ".claude", "settings.local.json")); err != nil {
		t.Fatalf("settings not written: %v", err)
	}
}
