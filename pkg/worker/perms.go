package worker

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/your-org/claude-dev-setup/pkg/permissions"
)

// ParseToolsFromWhitelist reads tools from processed_tool_whitelist.txt if present, otherwise from tool_whitelist.txt.
// Supports JSON array or newline-separated lists.
func ParseToolsFromWhitelist(cmdDir string) ([]string, error) {
	candidates := []string{
		filepath.Join(cmdDir, "processed_tool_whitelist.txt"),
		filepath.Join(cmdDir, "tool_whitelist.txt"),
	}
	var data []byte
	var err error
	found := ""
	for _, p := range candidates {
		if st, e := os.Stat(p); e == nil && !st.IsDir() {
			data, err = os.ReadFile(p)
			if err != nil {
				return nil, err
			}
			found = p
			break
		}
	}
	if found == "" {
		return []string{}, nil
	}

	// Try JSON array first
	var asJSON []string
	if json.Unmarshal(data, &asJSON) == nil {
		return asJSON, nil
	}
	// Fallback to newline-separated
	lines := strings.Split(string(data), "\n")
	tools := make([]string, 0, len(lines))
	for _, ln := range lines {
		t := strings.TrimSpace(ln)
		if t != "" {
			tools = append(tools, t)
		}
	}
	return tools, nil
}

// GenerateRepoPermissions writes settings.local.json under <repoDir>/.claude/ from tool whitelist in cmdDir.
func GenerateRepoPermissions(cmdDir, repoDir string) error {
	if repoDir == "" {
		return errors.New("repoDir is required")
	}
	tools, err := ParseToolsFromWhitelist(cmdDir)
	if err != nil {
		return err
	}
	// Ensure .claude dir
	targetDir := filepath.Join(repoDir, ".claude")
	if err := os.MkdirAll(targetDir, 0o755); err != nil {
		return err
	}
	out := filepath.Join(targetDir, "settings.local.json")
	return permissions.Generate(out, tools)
}
