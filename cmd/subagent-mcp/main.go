package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/your-org/claude-dev-setup/pkg/mcp"
)

// Minimal JSON-RPC 2.0 over stdio with MCP methods: initialize, tools/list, tools/call

type request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
}

type response struct {
	JSONRPC string    `json:"jsonrpc"`
	ID      any       `json:"id"`
	Result  any       `json:"result,omitempty"`
	Error   *rpcError `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type initializeResult struct {
	ServerInfo   map[string]string `json:"serverInfo"`
	Capabilities map[string]any    `json:"capabilities"`
}

type toolsListResult struct {
	Tools []toolDescriptor `json:"tools"`
}

type toolDescriptor struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	InputSchema map[string]any `json:"inputSchema"`
}

type toolsCallParams struct {
	Name   string         `json:"name"`
	Params map[string]any `json:"params"`
}

type toolsCallResult struct {
	Content string `json:"content"`
}

func main() {
	// Discover agent roots
	cmdDir := os.Getenv("CMD_DIR")
	if cmdDir == "" {
		cmdDir = "/home/owner/cmd"
	}
	repoDir := os.Getenv("REPO_DIR")
	if repoDir == "" {
		repoDir = filepath.Join(os.Getenv("HOME"), "claude", "target-repo")
	}

	var roots []string
	// transfer from orchestrator: /home/owner/cmd/agents
	if st, err := os.Stat(filepath.Join(cmdDir, "agents")); err == nil && st.IsDir() {
		roots = append(roots, filepath.Join(cmdDir, "agents"))
	}
	// repo-level agents
	if st, err := os.Stat(filepath.Join(repoDir, "agents")); err == nil && st.IsDir() {
		roots = append(roots, filepath.Join(repoDir, "agents"))
	}
	agents, _ := mcp.LoadAgentsFrom(roots)
	agentIndex := map[string]mcp.LoadedAgent{}
	for _, a := range agents {
		agentIndex[a.ToolName] = a
	}

	in := bufio.NewScanner(os.Stdin)
	enc := json.NewEncoder(os.Stdout)
	for in.Scan() {
		var req request
		if err := json.Unmarshal(in.Bytes(), &req); err != nil {
			continue
		}
		switch req.Method {
		case "initialize":
			_ = enc.Encode(response{JSONRPC: "2.0", ID: req.ID, Result: initializeResult{
				ServerInfo:   map[string]string{"name": "subagent-mcp", "version": "0.1.0"},
				Capabilities: map[string]any{"tools": map[string]any{"list": true, "call": true}},
			}})
		case "tools/list":
			var list toolsListResult
			for _, a := range agents {
				list.Tools = append(list.Tools, toolDescriptor{
					Name:        a.ToolName,
					Description: a.Description,
					InputSchema: map[string]any{
						"type":       "object",
						"required":   a.InputSchema.Required,
						"properties": a.InputSchema.Properties,
					},
				})
			}
			_ = enc.Encode(response{JSONRPC: "2.0", ID: req.ID, Result: list})
		case "tools/call":
			var p toolsCallParams
			if err := json.Unmarshal(req.Params, &p); err != nil {
				_ = enc.Encode(response{JSONRPC: "2.0", ID: req.ID, Error: &rpcError{Code: -32602, Message: "invalid params"}})
				continue
			}
			ag, ok := agentIndex[p.Name]
			if !ok {
				_ = enc.Encode(response{JSONRPC: "2.0", ID: req.ID, Error: &rpcError{Code: -32601, Message: "unknown tool"}})
				continue
			}
			// Render prompt (default passthrough; Jinja2 when built with mcp_subagents tag)
			prompt, err := mcp.Render(ag.Operation.Prompt, p.Params)
			if err != nil {
				_ = enc.Encode(response{JSONRPC: "2.0", ID: req.ID, Error: &rpcError{Code: -32002, Message: err.Error()}})
				continue
			}
			// Execute child Claude with verified flags later (placeholder cmd build; flags verified in docs step)
			// We pass allowed tools and permission mode.
			out, err := runChildClaude(prompt, ag.AllowedTools, ag.PermissionMode)
			if err != nil {
				_ = enc.Encode(response{JSONRPC: "2.0", ID: req.ID, Error: &rpcError{Code: -32010, Message: err.Error()}})
				continue
			}
			_ = enc.Encode(response{JSONRPC: "2.0", ID: req.ID, Result: toolsCallResult{Content: out}})
		default:
			_ = enc.Encode(response{JSONRPC: "2.0", ID: req.ID, Error: &rpcError{Code: -32601, Message: "method not found"}})
		}
	}
}

func runChildClaude(prompt string, allowed []string, permissionMode string) (string, error) {
	if strings.TrimSpace(prompt) == "" {
		return "", fmt.Errorf("empty prompt")
	}
	if permissionMode == "" {
		permissionMode = "default"
	}
	// Verified flags will be wired after docs check. For now, build args consistent with parent runner to keep code compiling.
	args := []string{"--print", "--output-format", "stream-json", "--verbose", "--permission-mode", permissionMode, "-p", prompt}
	if len(allowed) > 0 {
		// Tentative; will verify and adjust
		args = append(args, "--allowedTools", strings.Join(allowed, ","))
	}
	// Reuse central MCP config if present
	mcpCfg := filepath.Join(os.Getenv("HOME"), ".mcp.json")
	if st, err := os.Stat(mcpCfg); err == nil && !st.IsDir() {
		args = append([]string{"--mcp-config", mcpCfg}, args...)
	}
	// Run in repo dir if available
	repoDir := os.Getenv("REPO_DIR")
	if repoDir == "" {
		repoDir = filepath.Join(os.Getenv("HOME"), "claude", "target-repo")
	}
	// Execute synchronously and collect concise output lines for return value
	out, err := runCmdCollect("claude", repoDir, args...)
	if err != nil {
		return "", err
	}
	// Return last non-empty line within a reasonable window to keep response small
	lines := strings.Split(strings.TrimSpace(out), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		t := strings.TrimSpace(lines[i])
		if t != "" {
			return t, nil
		}
	}
	return fmt.Sprintf("completed at %s", time.Now().Format(time.RFC3339)), nil
}

func runCmdCollect(cmdName string, dir string, args ...string) (string, error) {
	cmd := exec.Command(cmdName, args...)
	cmd.Dir = dir
	var out bytes.Buffer
	var errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			msg = err.Error()
		}
		return "", fmt.Errorf(msg)
	}
	return out.String(), nil
}
