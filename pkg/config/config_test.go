package config

import (
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", name, err)
	}
	return path
}

func TestLoadFromDir_MinimalHappyPath(t *testing.T) {
	tmp := t.TempDir()
	writeFile(t, tmp, "prompt.txt", "Do the thing\n")
	writeFile(t, tmp, "tool_whitelist.txt", "[\"fs.read\"]\n")
	writeFile(t, tmp, "external_mcp.txt", "{\n  \"servers\": []\n}\n")
	writeFile(t, tmp, "github_repo.txt", "org/repo\n")
	writeFile(t, tmp, "github_token.txt", "ghp_secret_token\n")

	cfg, err := LoadFromDir(tmp)
	if err != nil {
		t.Fatalf("LoadFromDir error: %v", err)
	}

	if cfg.PromptFile == "" {
		t.Fatalf("expected PromptFile to be set")
	}
	if cfg.ToolWhitelistPath == "" {
		t.Fatalf("expected ToolWhitelistPath to be set")
	}
	if got := cfg.ExternalMCPConfigJSONValid; !got {
		t.Fatalf("expected ExternalMCPConfigJSONValid=true")
	}
	if cfg.GitHub.Repo != "org/repo" {
		t.Fatalf("github repo mismatch: %q", cfg.GitHub.Repo)
	}
	if !cfg.GitHub.TokenPresent {
		t.Fatalf("expected TokenPresent=true")
	}
}

func TestLoadFromDir_InvalidExternalMCPJSON(t *testing.T) {
	tmp := t.TempDir()
	writeFile(t, tmp, "prompt.txt", "x\n")
	writeFile(t, tmp, "external_mcp.txt", "not-json\n")

	cfg, err := LoadFromDir(tmp)
	if err != nil {
		t.Fatalf("LoadFromDir error: %v", err)
	}
	if cfg.ExternalMCPConfigPath == "" {
		t.Fatalf("expected ExternalMCPConfigPath present")
	}
	if cfg.ExternalMCPConfigJSONValid {
		t.Fatalf("expected ExternalMCPConfigJSONValid=false for invalid json")
	}
}
