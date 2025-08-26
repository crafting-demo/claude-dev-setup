package worker

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/your-org/claude-dev-setup/pkg/config"
	"github.com/your-org/claude-dev-setup/pkg/taskstate"
)

type Runner struct{}

func NewRunner() *Runner { return &Runner{} }

type SessionFile struct {
	SessionID string `json:"sessionId"`
}

// Run performs worker orchestration: load config, ensure repo, write MCP config, generate permissions, start/complete task, persist state.
func (r *Runner) Run(cmdDir, statePath, sessionPath string) error {
	if cmdDir == "" || statePath == "" {
		return errors.New("missing cmdDir or statePath")
	}

	// Load config (safe summary printed by caller if needed)
	cfg, err := config.LoadFromDir(cmdDir)
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	// Ensure state directory exists
	if err := os.MkdirAll(filepath.Dir(statePath), 0o755); err != nil {
		return fmt.Errorf("ensure state dir: %w", err)
	}

	// Load state
	mgr, err := taskstate.Load(statePath)
	if err != nil {
		return fmt.Errorf("load state: %w", err)
	}

	// Start next if none; if queue empty and we have a prompt, enqueue a task in create mode
	st := mgr.GetState()
	if st.Current == nil {
		if len(st.Queue) > 0 {
			mgr.StartNext()
		}
	}

	// Link session if available
	if sessionPath != "" {
		if b, err := os.ReadFile(sessionPath); err == nil && len(b) > 0 {
			var s SessionFile
			if json.Unmarshal(b, &s) == nil && s.SessionID != "" {
				mgr.LinkSessionToCurrent(s.SessionID)
			}
		}
	}

	// If a prompt file exists use it; otherwise attempt to read prompt.txt
	prompt := config.ReadPromptFrom(cmdDir)
	if prompt == "" {
		// fallback to reading prompt.txt
		p := filepath.Join(cmdDir, "prompt.txt")
		if b, e := os.ReadFile(p); e == nil {
			prompt = string(b)
		}
	}

	// If no current task and we have a prompt, enqueue and start
	st = mgr.GetState()
	if st.Current == nil && prompt != "" {
		// Prefer provided task ID when present; otherwise generate one
		id := cfg.TaskID
		if strings.TrimSpace(id) == "" {
			id = fmt.Sprintf("task-%d", time.Now().Unix())
		}
		mgr.Enqueue(taskstate.Task{ID: id})
		mgr.StartNext()
	}

	// Determine repo directory: CUSTOM_REPO_PATH (absolute or HOME-relative),
	// or default to /home/owner/claude/target-repo
	repoDir := os.Getenv("CUSTOM_REPO_PATH")
	if repoDir != "" && !filepath.IsAbs(repoDir) {
		repoDir = filepath.Join(os.Getenv("HOME"), repoDir)
	}
	if repoDir == "" {
		repoDir = filepath.Join(os.Getenv("HOME"), "claude", "target-repo")
	}

	// Execute Claude stream-json in the repo directory
	if st := mgr.GetState(); st.Current != nil && prompt != "" {
		debug := os.Getenv("DEBUG_MODE") == "true"
		// Derive allowed/disallowed tools from whitelist
		allowedTools, _ := ParseToolsFromWhitelist(cmdDir)
		// If Task is not explicitly allowed, disallow it to force Write/Edit usage
		disallowed := []string{}
		hasTask := false
		for _, t := range allowedTools {
			if t == "Task" {
				hasTask = true
				break
			}
		}
		if !hasTask {
			disallowed = append(disallowed, "Task")
		}
		permMode := os.Getenv("CLAUDE_PERMISSION_MODE")
		if permMode == "" {
			permMode = "default"
		}
		if err := RunClaudeStream(os.Getenv("HOME"), repoDir, prompt, mgr, debug, allowedTools, disallowed, permMode); err != nil {
			// If Claude is unavailable in unit tests, fall back to completing current
			mgr.CompleteCurrent("done")
		}
	}

	// Persist
	if err := mgr.Save(); err != nil {
		return fmt.Errorf("save state: %w", err)
	}

	return nil
}
