package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

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
		// Hydrate env vars from cmd files if not already set (no logging of values)
		// Also reuse previously set GITHUB_TOKEN from environment (sandbox persists env between runs)
		if os.Getenv("GITHUB_TOKEN") == "" {
			if b, err := os.ReadFile(filepath.Join(cmdDir, "github_token.txt")); err == nil {
				os.Setenv("GITHUB_TOKEN", strings.TrimSpace(string(b)))
			}
		}
		if os.Getenv("GITHUB_REPO") == "" && cfg.GitHub.Repo == "" {
			if b, err := os.ReadFile(filepath.Join(cmdDir, "github_repo.txt")); err == nil {
				os.Setenv("GITHUB_REPO", strings.TrimSpace(string(b)))
			}
		}
		if os.Getenv("GITHUB_BRANCH") == "" && cfg.GitHub.Branch == "" {
			if b, err := os.ReadFile(filepath.Join(cmdDir, "github_branch.txt")); err == nil {
				os.Setenv("GITHUB_BRANCH", strings.TrimSpace(string(b)))
			}
		}

		// Authenticate with GitHub if possible (token presence only logged elsewhere)
		_ = worker.EnsureGitHubAuth()
		// Prepare repository only when we have repo/branch context
		repo := cfg.GitHub.Repo
		if repo == "" {
			repo = os.Getenv("GITHUB_REPO")
		}
		branch := cfg.GitHub.Branch
		if branch == "" {
			branch = os.Getenv("GITHUB_BRANCH")
		}
		if repo != "" || branch != "" {
			_ = worker.PrepareRepo(os.Getenv("HOME"), "", repo, branch)
		}
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
