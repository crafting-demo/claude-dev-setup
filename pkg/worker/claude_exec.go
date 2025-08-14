package worker

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/your-org/claude-dev-setup/pkg/taskstate"
)

// RunClaudeStream executes `claude` with stream-json in the provided repoDir,
// writes session.json when sessionId appears, and updates task state.
//
// permissionMode should typically be "default" (not bypass). When allowedTools is non-empty,
// it will be passed via --allowedTools. disallowedTools is also honored.
func RunClaudeStream(homeDir, repoDir, prompt string, state *taskstate.Manager, debug bool, allowedTools []string, disallowedTools []string, permissionMode string) error {
	if prompt == "" {
		return errors.New("missing prompt")
	}
	if repoDir == "" {
		return errors.New("missing repoDir")
	}
	if st, err := os.Stat(repoDir); err != nil || !st.IsDir() {
		return fmt.Errorf("repoDir not found or not a directory: %s", repoDir)
	}
	// Build command. Use central MCP config if present.
	mcpCfg := filepath.Join(homeDir, ".mcp.json")
	// Use --print for non-interactive mode; stream-json requires --verbose per CLI docs
	args := []string{"--print", "--output-format", "stream-json", "--verbose"}
	if permissionMode == "" {
		permissionMode = "default"
	}
	args = append(args, "--permission-mode", permissionMode)
	if len(allowedTools) > 0 {
		args = append(args, "--allowedTools", strings.Join(allowedTools, ","))
	}
	if len(disallowedTools) > 0 {
		args = append(args, "--disallowedTools", strings.Join(disallowedTools, ","))
	}
	// Positional prompt last, per CLI usage
	args = append(args, prompt)
	if st, err := os.Stat(mcpCfg); err == nil && !st.IsDir() {
		args = append([]string{"--mcp-config", mcpCfg}, args...)
	}
	cmd := exec.Command("claude", args...)
	cmd.Dir = repoDir
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
		var obj any
		if err := json.Unmarshal([]byte(line), &obj); err == nil {
			// Extract session id from system events
			if m, ok := obj.(map[string]any); ok {
				if typ, ok := m["type"].(string); ok && typ == "system" {
					if sid, ok := m["session_id"].(string); ok && sid != "" {
						sessionId = sid
					}
				}
			}
			if debug {
				// Truncate long strings and pretty print
				trimmed := truncateLongStrings(obj, 400)
				pretty := mustPrettyJSON(trimmed)
				fmt.Printf("%s\n", pretty)
			}
		} else {
			// Not JSON – print raw when in debug
			if debug {
				fmt.Printf("%s\n", line)
			}
		}
	}
	if sessionId != "" {
		// Persist session.json
		sessPath := filepath.Join(homeDir, "session.json")
		_ = os.WriteFile(sessPath, []byte("{\n  \"sessionId\": \""+sessionId+"\"\n}"), 0o644)
		// Link session to current only if one is not already set
		stNow := state.GetState()
		alreadySet := stNow.Current != nil && stNow.Current.SessionID != ""
		if !alreadySet {
			state.LinkSessionToCurrent(sessionId)
		}
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

// truncateLongStrings walks an arbitrary JSON-like structure and truncates long string values.
func truncateLongStrings(v any, max int) any {
	switch t := v.(type) {
	case string:
		if utf8.RuneCountInString(t) > max {
			// Ensure we do not cut in the middle of a rune
			rs := []rune(t)
			if len(rs) > max {
				return string(rs[:max]) + "… (truncated)"
			}
		}
		return t
	case []any:
		out := make([]any, len(t))
		for i := range t {
			out[i] = truncateLongStrings(t[i], max)
		}
		return out
	case map[string]any:
		out := make(map[string]any, len(t))
		for k, val := range t {
			out[k] = truncateLongStrings(val, max)
		}
		return out
	default:
		return v
	}
}

func mustPrettyJSON(v any) string {
	b, err := json.MarshalIndent(v, "", "  ")
	if err == nil {
		return string(b)
	}
	// Fallback best-effort: try to indent raw bytes if already JSON
	if bb, ok := v.([]byte); ok {
		var buf bytes.Buffer
		if json.Indent(&buf, bb, "", "  ") == nil {
			return buf.String()
		}
		return string(bb)
	}
	// Last resort: string format
	return fmt.Sprintf("%v", v)
}
