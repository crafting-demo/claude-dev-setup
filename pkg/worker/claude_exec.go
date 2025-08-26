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

// lastConciseSubagent tracks the most recent subagent name seen in a tool_use
// event so that the subsequent tool_result can be annotated consistently.
var lastConciseSubagent string

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
	// Provide prompt via -p to ensure non-interactive input is accepted even for multi-line prompts
	args = append(args, "-p", prompt)
	if st, err := os.Stat(mcpCfg); err == nil && !st.IsDir() {
		args = append([]string{"--mcp-config", mcpCfg}, args...)
	}
	cmd := exec.Command("claude", args...)
	cmd.Dir = repoDir
	if debug {
		// Print the repository directory where Claude will be executed
		fmt.Printf("[INFO] Running Claude in repo directory: %s\n", repoDir)
	}
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
	streamFormat := strings.ToLower(strings.TrimSpace(os.Getenv("CSCC_STREAM_FORMAT")))
	if streamFormat == "" && debug {
		streamFormat = "concise"
	}
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
				if streamFormat == "concise" {
					printConciseEvent(obj)
				} else {
					// Truncate long strings and pretty print
					trimmed := truncateLongStrings(obj, 400)
					pretty := mustPrettyJSON(trimmed)
					fmt.Printf("%s\n", pretty)
				}
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

// printConciseEvent prints a compact summary of stream-json events:
// - assistant preambles (message text)
// - tool_use: name and key input summary (file_path, command, subagent_type, etc.)
// - tool_result: success/error with brief content
func printConciseEvent(v any) {
	m, ok := v.(map[string]any)
	if !ok {
		return
	}
	// Messages carry most interesting events
	msg, ok := m["message"].(map[string]any)
	if !ok {
		return
	}
	content, ok := msg["content"].([]any)
	if !ok {
		return
	}
	for _, it := range content {
		part, ok := it.(map[string]any)
		if !ok {
			continue
		}
		typ, _ := part["type"].(string)
		switch typ {
		case "text":
			if t, _ := part["text"].(string); strings.TrimSpace(t) != "" {
				fmt.Printf("🤖 Claude: %q\n", t)
			}
		case "tool_use":
			name, _ := part["name"].(string)
			input, _ := part["input"].(map[string]any)
			// Detect subagent context
			prefix := ""
			if sa, ok := input["subagent_type"].(string); ok && strings.TrimSpace(sa) != "" {
				lastConciseSubagent = sa
				prefix = "[" + sa + "] "
			} else {
				lastConciseSubagent = ""
			}
			summary := summarizeToolInput(input)
			if summary != "" {
				fmt.Printf("🔧 %stool_use: %s - %s\n", prefix, name, summary)
			} else {
				fmt.Printf("🔧 %stool_use: %s\n", prefix, name)
			}
		case "tool_result":
			isErr, _ := part["is_error"].(bool)
			// Try common result shapes
			if txt, _ := part["content"].(string); txt != "" {
				emoji := "🟢"
				if isErr {
					emoji = "🔴"
				}
				prefix := ""
				if lastConciseSubagent != "" {
					prefix = "[" + lastConciseSubagent + "] "
					lastConciseSubagent = ""
				}
				fmt.Printf("%s %stool_result: %q\n", emoji, prefix, txt)
			}
		}
	}
}

func summarizeToolInput(in map[string]any) string {
	if in == nil {
		return ""
	}
	// Common fields
	if fp, ok := in["file_path"].(string); ok && fp != "" {
		return fmt.Sprintf("file=%s", fp)
	}
	if cmd, ok := in["command"].(string); ok && cmd != "" {
		return fmt.Sprintf("cmd=%s", truncateString(cmd, 120))
	}
	if p, ok := in["path"].(string); ok && p != "" {
		return fmt.Sprintf("path=%s", p)
	}
	if prompt, ok := in["prompt"].(string); ok && prompt != "" {
		return fmt.Sprintf("prompt=%s", truncateString(prompt, 120))
	}
	return ""
}

func truncateString(s string, max int) string {
	if utf8.RuneCountInString(s) <= max {
		return s
	}
	rs := []rune(s)
	if len(rs) > max {
		return string(rs[:max]) + "…"
	}
	return s
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
