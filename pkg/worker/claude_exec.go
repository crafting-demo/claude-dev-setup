package worker

import (
	"bufio"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/your-org/claude-dev-setup/pkg/claude"
	"github.com/your-org/claude-dev-setup/pkg/taskstate"
)

// RunClaudeStream executes `claude` with stream-json, writes session.json when sessionId appears, and updates task state.
func RunClaudeStream(homeDir, prompt string, state *taskstate.Manager) error {
	if prompt == "" {
		return errors.New("missing prompt")
	}
	// Build command. Use central MCP config if present.
	mcpCfg := filepath.Join(homeDir, ".mcp.json")
	args := []string{"--output-format", "stream-json", "-p", prompt}
	if st, err := os.Stat(mcpCfg); err == nil && !st.IsDir() {
		args = append([]string{"--mcp-config", mcpCfg}, args...)
	}
	cmd := exec.Command("claude", args...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return err
	}

	reader := bufio.NewReader(stdout)
	events, err := claude.ParseStream(reader)
	if err != nil {
		return err
	}

	var sessionId string
	for _, e := range events {
		if e.Type == "system" {
			// Try to extract session id if present
			b, _ := json.Marshal(e.Data)
			var m map[string]any
			if json.Unmarshal(b, &m) == nil {
				if v, ok := m["session_id"].(string); ok && v != "" {
					sessionId = v
				}
			}
		}
	}
	if sessionId != "" {
		// Persist session.json
		sessPath := filepath.Join(homeDir, "session.json")
		_ = os.WriteFile(sessPath, []byte("{\n  \"sessionId\": \""+sessionId+"\"\n}"), 0o644)
		// Link session to current
		state.LinkSessionToCurrent(sessionId)
	}

	// Mark current complete
	state.CompleteCurrent("done")
	if err := state.Save(); err != nil {
		return err
	}

	return cmd.Wait()
}
