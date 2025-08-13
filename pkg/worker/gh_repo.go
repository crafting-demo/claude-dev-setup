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
	// If already authenticated, nothing to do
	if err := exec.Command("gh", "auth", "status").Run(); err == nil {
		return nil
	}
	// Attempt non-interactive login using GITHUB_TOKEN if present
	token := os.Getenv("GITHUB_TOKEN")
	if token != "" {
		login := exec.Command("gh", "auth", "login", "--with-token")
		login.Stdin = bytesFromString(token)
		if err := login.Run(); err == nil {
			// Configure git to use gh credentials
			_ = exec.Command("gh", "auth", "setup-git").Run()
			return nil
		}
	}
	// Fallback: return status error; caller may rely on workspace creds
	return exec.Command("gh", "auth", "status").Run()
}

// bytesFromString returns a reader for the given string
func bytesFromString(s string) *os.File {
	// Create a temporary pipe to feed the token to gh
	r, w, _ := os.Pipe()
	go func() {
		_, _ = w.Write([]byte(s))
		_ = w.Close()
	}()
	return r
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
