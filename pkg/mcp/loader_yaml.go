//go:build mcp_subagents
// +build mcp_subagents

package mcp

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	yaml "gopkg.in/yaml.v3"
)

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
		var spec AgentSpec
		if yaml.Unmarshal(b, &spec) != nil {
			continue
		}
		if len(spec.Operations) == 0 || strings.TrimSpace(spec.Operations[0].Prompt) == "" {
			continue
		}
		toolName := strings.TrimSpace(spec.AgentName)
		if toolName == "" {
			base := filepath.Base(f)
			toolName = strings.TrimSuffix(base, filepath.Ext(base))
		}
		la := LoadedAgent{
			ToolName:       toolName,
			Description:    firstNonEmpty(spec.Description, spec.Name, "subagent tool"),
			AllowedTools:   append([]string{}, spec.Defaults.AllowedTools...),
			PermissionMode: firstNonEmpty(spec.Defaults.PermissionMode, "default"),
			InputSchema:    spec.InputSchema,
			Operation:      spec.Operations[0],
		}
		out = append(out, la)
	}
	return out, nil
}
