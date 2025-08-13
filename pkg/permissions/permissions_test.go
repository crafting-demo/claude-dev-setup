package permissions

import (
	"encoding/json"
	"os"
	"testing"
)

func TestGenerate(t *testing.T) {
	tmp := t.TempDir() + "/settings.local.json"
	tools := []string{"fs.read", "git.clone"}
	if err := Generate(tmp, tools); err != nil {
		t.Fatalf("generate: %v", err)
	}
	b, err := os.ReadFile(tmp)
	if err != nil {
		t.Fatal(err)
	}
	var s Settings
	if err := json.Unmarshal(b, &s); err != nil {
		t.Fatal(err)
	}
	if len(s.Tools) != 2 || s.Tools[0] != "fs.read" {
		t.Fatalf("unexpected tools: %+v", s.Tools)
	}
}
