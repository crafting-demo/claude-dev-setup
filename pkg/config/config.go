package config

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

type GitHubContext struct {
	Repo         string
	TokenPresent bool
	Branch       string
}

type Config struct {
	BaseDir                    string
	PromptFile                 string
	PromptFilenameRef          string
	TaskMode                   string
	TaskID                     string
	ToolWhitelistPath          string
	ProcessedToolWhitelistPath string
	ExternalMCPConfigPath      string
	ExternalMCPConfigJSONValid bool
	GitHub                     GitHubContext
	Env                        map[string]string
}

func LoadFromDir(baseDir string) (*Config, error) {
	cfg := &Config{BaseDir: baseDir, Env: map[string]string{}}

	// Required directory
	info, err := os.Stat(baseDir)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, errors.New("baseDir is not a directory")
	}

	// Files under /home/owner/cmd
	cfg.PromptFile = firstExisting(baseDir, []string{"prompt.txt", "prompt_new.txt"})
	cfg.PromptFilenameRef = optionalFile(baseDir, "prompt_filename.txt")
	cfg.TaskMode = readTrim(optionalFile(baseDir, "task_mode.txt"))
	cfg.TaskID = readTrim(optionalFile(baseDir, "task_id.txt"))
	cfg.ToolWhitelistPath = optionalFile(baseDir, "tool_whitelist.txt")
	cfg.ProcessedToolWhitelistPath = optionalFile(baseDir, "processed_tool_whitelist.txt")
	cfg.ExternalMCPConfigPath = optionalFile(baseDir, "external_mcp.txt")
	cfg.ExternalMCPConfigJSONValid = validateJSONIfPresent(cfg.ExternalMCPConfigPath)

	// GitHub context (files preferred over env)
	cfg.GitHub = GitHubContext{
		Repo:         readTrim(optionalFile(baseDir, "github_repo.txt")),
		TokenPresent: fileHasContent(optionalFile(baseDir, "github_token.txt")),
		Branch:       readTrim(optionalFile(baseDir, "github_branch.txt")),
	}

	// Selected env variables
	for _, key := range []string{
		"GITHUB_REPO", "GITHUB_BRANCH", "SANDBOX_NAME", "CUSTOM_REPO_PATH", "SHOULD_DELETE", "DEBUG_MODE",
	} {
		if val := strings.TrimSpace(os.Getenv(key)); val != "" {
			// Do not store tokens or secrets here
			cfg.Env[key] = val
		}
	}

	return cfg, nil
}

func firstExisting(baseDir string, names []string) string {
	for _, n := range names {
		p := filepath.Join(baseDir, n)
		if fileExists(p) {
			return p
		}
	}
	return ""
}

func optionalFile(baseDir, name string) string {
	p := filepath.Join(baseDir, name)
	if fileExists(p) {
		return p
	}
	return ""
}

func fileExists(path string) bool {
	if path == "" {
		return false
	}
	st, err := os.Stat(path)
	return err == nil && !st.IsDir()
}

func readTrim(path string) string {
	if path == "" {
		return ""
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func fileHasContent(path string) bool {
	if path == "" {
		return false
	}
	st, err := os.Stat(path)
	if err != nil {
		return false
	}
	return st.Size() > 0
}

func validateJSONIfPresent(path string) bool {
	if path == "" {
		return false
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	var tmp any
	return json.Unmarshal(b, &tmp) == nil
}

// ReadPromptFrom returns the contents of the first present prompt file.
func ReadPromptFrom(baseDir string) string {
	if baseDir == "" {
		return ""
	}
	for _, name := range []string{"prompt.txt", "prompt_new.txt"} {
		p := filepath.Join(baseDir, name)
		if fileExists(p) {
			b, err := os.ReadFile(p)
			if err == nil {
				return string(b)
			}
		}
	}
	return ""
}
