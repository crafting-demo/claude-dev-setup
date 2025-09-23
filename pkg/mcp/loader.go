package mcp

import (
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// AgentSpec captures the subset of YAML needed to expose an MCP tool and render a prompt.
type AgentSpec struct {
	Name        string           `yaml:"name"`
	Description string           `yaml:"description"`
	AgentName   string           `yaml:"agent_name"`
	Defaults    AgentDefaults    `yaml:"defaults"`
	InputSchema AgentInputSchema `yaml:"input_schema"`
	Operations  []AgentOperation `yaml:"operations"`
}

type AgentDefaults struct {
	Model          string   `yaml:"model"`
	AllowedTools   []string `yaml:"allowed_tools"`
	PermissionMode string   `yaml:"permission_mode"`
}

type AgentInputSchema struct {
	Properties map[string]map[string]any `yaml:"properties"`
	Required   []string                  `yaml:"required"`
}

type AgentOperation struct {
	Description string `yaml:"description"`
	Prompt      string `yaml:"prompt"`
}

// LoadedAgent is a normalized structure used by the MCP server.
type LoadedAgent struct {
	ToolName       string
	Description    string
	AllowedTools   []string
	PermissionMode string
	InputSchema    AgentInputSchema
	Operation      AgentOperation
}

// LoadAgentsFrom recursively discovers YAML files under the provided roots and returns normalized agents.
func LoadAgentsFrom(roots []string) ([]LoadedAgent, error) {
	var files []string
	for _, r := range roots {
		if strings.TrimSpace(r) == "" {
			continue
		}
		_ = filepath.WalkDir(r, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if d.IsDir() {
				return nil
			}
			low := strings.ToLower(d.Name())
			if strings.HasSuffix(low, ".yaml") || strings.HasSuffix(low, ".yml") {
				files = append(files, path)
			}
			return nil
		})
	}
	sort.Strings(files)
	var out []LoadedAgent
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil || len(b) == 0 {
			continue
		}
		content := string(b)
		base := filepath.Base(f)
		toolName := strings.TrimSpace(extractScalar(content, "agent_name"))
		if toolName == "" {
			toolName = strings.TrimSuffix(base, filepath.Ext(base))
		}
		desc := extractScalar(content, "description")
		allowed := extractList(content, "allowed_tools")
		perm := extractScalar(content, "permission_mode")
		if perm == "" {
			perm = "default"
		}
		prompt := extractPromptBlock(content)
		if strings.TrimSpace(prompt) == "" {
			// If no prompt block, skip
			continue
		}
		la := LoadedAgent{
			ToolName:       toolName,
			Description:    firstNonEmpty(desc, "subagent tool"),
			AllowedTools:   allowed,
			PermissionMode: perm,
			InputSchema:    AgentInputSchema{Properties: map[string]map[string]any{}, Required: nil},
			Operation:      AgentOperation{Description: "operation", Prompt: prompt},
		}
		out = append(out, la)
	}
	if len(out) == 0 {
		return nil, errors.New("no agents discovered")
	}
	return out, nil
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

// extractScalar finds a simple YAML scalar at the top/mid-level: key: value
func extractScalar(s string, key string) string {
	lines := strings.Split(s, "\n")
	prefix := key + ":"
	for _, line := range lines {
		t := strings.TrimSpace(line)
		if strings.HasPrefix(t, prefix) {
			v := strings.TrimSpace(strings.TrimPrefix(t, prefix))
			v = strings.Trim(v, "\"'")
			return v
		}
	}
	return ""
}

// extractList supports either bracket lists (key: [a, b]) or dash lists beneath key:
func extractList(s string, key string) []string {
	lines := strings.Split(s, "\n")
	var out []string
	keyIdx := -1
	keyIndent := 0
	for i, line := range lines {
		if keyIdx == -1 {
			// search for key
			if idx := strings.Index(line, key+":"); idx >= 0 {
				keyIdx = i
				keyIndent = leadingSpaces(line)
				// check bracket list on same line
				rest := strings.TrimSpace(line[idx+len(key)+1:])
				if strings.HasPrefix(rest, "[") && strings.Contains(rest, "]") {
					inner := rest[1:strings.Index(rest, "]")]
					parts := strings.Split(inner, ",")
					for _, p := range parts {
						v := strings.TrimSpace(strings.Trim(p, "\"'"))
						if v != "" {
							out = append(out, v)
						}
					}
					return out
				}
			}
		} else {
			// collect dash list items with greater indent
			if leadingSpaces(line) <= keyIndent {
				break
			}
			t := strings.TrimSpace(line)
			if strings.HasPrefix(t, "- ") {
				v := strings.TrimSpace(strings.TrimPrefix(t, "- "))
				v = strings.Trim(v, "\"'")
				if v != "" {
					out = append(out, v)
				}
			} else if t == "" {
				continue
			} else if strings.Contains(t, ":") {
				// next section
				break
			}
		}
	}
	return out
}

// extractPromptBlock finds operations: ... prompt: | <block>
func extractPromptBlock(s string) string {
	lines := strings.Split(s, "\n")
	promptIdx := -1
	promptIndent := 0
	for i, line := range lines {
		if strings.Contains(line, "prompt:") {
			promptIdx = i
			promptIndent = leadingSpaces(line)
			// if inline scalar
			if idx := strings.Index(line, "prompt:"); idx >= 0 {
				rest := strings.TrimSpace(line[idx+len("prompt:"):])
				if rest != "" && rest != "|" && rest != ">" && rest != "|-" && rest != ">-" {
					return rest
				}
			}
			break
		}
	}
	if promptIdx == -1 {
		return ""
	}
	var b strings.Builder
	for j := promptIdx + 1; j < len(lines); j++ {
		line := lines[j]
		if leadingSpaces(line) <= promptIndent && strings.TrimSpace(line) != "" {
			break
		}
		// strip at most promptIndent+2 spaces to normalize block
		trim := min(leadingSpaces(line), promptIndent+2)
		b.WriteString(line[trim:])
		if j < len(lines)-1 {
			b.WriteString("\n")
		}
	}
	return strings.TrimRight(b.String(), "\n")
}

func leadingSpaces(s string) int {
	n := 0
	for _, r := range s {
		if r == ' ' {
			n++
		} else {
			break
		}
	}
	return n
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
