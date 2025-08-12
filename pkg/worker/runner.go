package worker

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/your-org/claude-dev-setup/pkg/config"
	"github.com/your-org/claude-dev-setup/pkg/taskstate"
)

type Runner struct{}

func NewRunner() *Runner { return &Runner{} }

type SessionFile struct {
	SessionID string `json:"sessionId"`
}

// Run performs minimal worker orchestration: load config, load state, start next task if none, link session if present, save state.
func (r *Runner) Run(cmdDir, statePath, sessionPath string) error {
	if cmdDir == "" || statePath == "" {
		return errors.New("missing cmdDir or statePath")
	}

	// Load config (safe summary printed by caller if needed)
	_, err := config.LoadFromDir(cmdDir)
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

	// Start next if none
	st := mgr.GetState()
	if st.Current == nil && len(st.Queue) > 0 {
		mgr.StartNext()
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

	// For this minimal runner, immediately complete the current task to produce deterministic state transitions
	// In future, this will wrap the actual execution lifecycle.
	st = mgr.GetState()
	if st.Current != nil {
		mgr.CompleteCurrent("done")
	}

	// Persist
	if err := mgr.Save(); err != nil {
		return fmt.Errorf("save state: %w", err)
	}

	return nil
}
