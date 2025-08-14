package permissions

import (
	"encoding/json"
	"os"
)

type Settings struct {
	Tools []string `json:"tools"`
}

// Generate writes a minimal .claude/settings.local.json-equivalent structure based on tool whitelist.
func Generate(outputPath string, tools []string) error {
	s := Settings{Tools: tools}
	b, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(outputPath, b, 0o644)
}
