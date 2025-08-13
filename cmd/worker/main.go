package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/your-org/claude-dev-setup/pkg/config"
	"github.com/your-org/claude-dev-setup/pkg/worker"
)

func main() {
	cmdDir := os.Getenv("CMD_DIR")
	if cmdDir == "" {
		cmdDir = "/home/owner/cmd"
	}
	statePath := os.Getenv("STATE_PATH")
	if statePath == "" {
		statePath = filepath.Join(os.Getenv("HOME"), "state.json")
	}
	sessionPath := os.Getenv("SESSION_PATH")
	if sessionPath == "" {
		sessionPath = filepath.Join(os.Getenv("HOME"), "session.json")
	}

	// Prepare external MCP central config (~/.mcp.json)
	if err := worker.WriteCentralMCPConfig(cmdDir, os.Getenv("HOME")); err != nil {
		fmt.Fprintf(os.Stderr, "[WARNING] failed writing central MCP config: %v\n", err)
	}

	// Load config to get GitHub context
	cfg, cfgErr := config.LoadFromDir(cmdDir)
	if cfgErr == nil {
		// Authenticate with GitHub if possible (token presence only logged elsewhere)
		_ = worker.EnsureGitHubAuth()
		// Prepare repository: clone if missing, checkout branch if provided
		_ = worker.PrepareRepo(os.Getenv("HOME"), "", cfg.GitHub.Repo, cfg.GitHub.Branch)
	}

	// Generate permissions for the repo if present
	repoDir := os.Getenv("CUSTOM_REPO_PATH")
	if repoDir != "" {
		if !filepath.IsAbs(repoDir) {
			repoDir = filepath.Join(os.Getenv("HOME"), repoDir)
		}
	} else {
		repoDir = filepath.Join(os.Getenv("HOME"), "claude", "target-repo")
	}
	if st, err := os.Stat(repoDir); err == nil && st.IsDir() {
		if err := worker.GenerateRepoPermissions(cmdDir, repoDir); err != nil {
			fmt.Fprintf(os.Stderr, "[WARNING] failed generating repo permissions: %v\n", err)
		}
	}

	r := worker.NewRunner()
	if err := r.Run(cmdDir, statePath, sessionPath); err != nil {
		fmt.Fprintf(os.Stderr, "[ERROR] worker run failed: %v\n", err)
		os.Exit(23)
	}
}
