package worker

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/your-org/claude-dev-setup/pkg/taskstate"
)

// RunClaudeStream executes `claude` with stream-json, writes session.json when sessionId appears, and updates task state.
func RunClaudeStream(homeDir, prompt string, state *taskstate.Manager, debug bool) error {
	if prompt == "" {
		return errors.New("missing prompt")
	}
	// Build command. Use central MCP config if present.
	mcpCfg := filepath.Join(homeDir, ".mcp.json")
	args := []string{"--output-format", "stream-json", "--verbose", "-p", prompt}
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

	scanner := bufio.NewScanner(stdout)
	var sessionId string
	for scanner.Scan() {
		line := scanner.Text()
		if debug {
			fmt.Printf("%s\n", line)
		}
		var m map[string]any
		if json.Unmarshal([]byte(line), &m) == nil {
			if typ, ok := m["type"].(string); ok && typ == "system" {
				if sid, ok := m["session_id"].(string); ok && sid != "" {
					sessionId = sid
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

	if err := scanner.Err(); err != nil {
		return err
	}
	return cmd.Wait()
}
