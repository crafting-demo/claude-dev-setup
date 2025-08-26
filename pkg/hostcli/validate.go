package hostcli

import (
	"errors"
	"fmt"
	"os"
)

type Args struct {
	CmdDir     string
	GitHubRepo string
	Branch     string
}

// Validate checks basic GitHub context when provided.
// Rules:
// - cmd-dir must exist
// - github-repo is required
// - branch is optional and not validated here
func Validate(a Args) error {
	if a.CmdDir == "" {
		return errors.New("cmd-dir is required")
	}
	if st, err := os.Stat(a.CmdDir); err != nil || !st.IsDir() {
		return fmt.Errorf("cmd-dir not found or not a directory: %s", a.CmdDir)
	}
	if a.GitHubRepo == "" {
		return errors.New("github-repo is required")
	}
	return nil
}
