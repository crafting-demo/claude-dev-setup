package worker

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// EnsureGitHubAuth attempts a minimal auth check. If GITHUB_TOKEN is set, gh can use it via env.
// We do not print the token; only the presence is logged by the caller.
func EnsureGitHubAuth() error {
	cmd := exec.Command("gh", "auth", "status")
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}

// PrepareRepo ensures the repository exists at repoDir. If missing, uses gh to clone githubRepo.
// If branch is provided, it checks out the branch.
func PrepareRepo(homeDir, repoDir, githubRepo, branch string) error {
	if repoDir == "" {
		repoDir = filepath.Join(homeDir, "claude", "target-repo")
	}
	if st, err := os.Stat(repoDir); err == nil && st.IsDir() {
		// Repo exists; optionally switch branch
		if branch != "" {
			if err := runInDir(repoDir, "git", "fetch", "--all", "--quiet"); err != nil {
				return err
			}
			if err := runInDir(repoDir, "git", "checkout", branch); err != nil {
				return err
			}
		}
		return nil
	}
	// Clone fresh
	if err := os.MkdirAll(filepath.Dir(repoDir), 0o755); err != nil {
		return err
	}
	if githubRepo == "" {
		return fmt.Errorf("github repo is required to clone")
	}
	if err := runInDir(filepath.Dir(repoDir), "gh", "repo", "clone", githubRepo, filepath.Base(repoDir)); err != nil {
		return err
	}
	if branch != "" {
		if err := runInDir(repoDir, "git", "checkout", branch); err != nil {
			return err
		}
	}
	return nil
}

func runInDir(dir string, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}
