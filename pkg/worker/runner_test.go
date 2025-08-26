package worker

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/your-org/claude-dev-setup/pkg/taskstate"
)

func TestRunner_Run_StartsNextAndLinksSession(t *testing.T) {
	tmp := t.TempDir()
	cmdDir := filepath.Join(tmp, "cmd")
	if err := os.MkdirAll(cmdDir, 0o755); err != nil {
		t.Fatal(err)
	}
	// minimal required file
	if err := os.WriteFile(filepath.Join(cmdDir, "prompt.txt"), []byte("x\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	statePath := filepath.Join(tmp, "state.json")
	// seed queue
	m := taskstate.NewManager(statePath)
	m.Enqueue(taskstate.Task{ID: "t1"})
	if err := m.Save(); err != nil {
		t.Fatal(err)
	}

	// session
	sessPath := filepath.Join(tmp, "session.json")
	b, _ := json.Marshal(map[string]string{"sessionId": "sess-1"})
	if err := os.WriteFile(sessPath, b, 0o644); err != nil {
		t.Fatal(err)
	}

	r := NewRunner()
	t.Setenv("DEBUG_MODE", "false")
	if err := r.Run(cmdDir, statePath, sessPath); err != nil {
		t.Fatalf("run: %v", err)
	}

	// verify state
	m2, err := taskstate.Load(statePath)
	if err != nil {
		t.Fatal(err)
	}
	st := m2.GetState()
	if st.Current != nil {
		t.Fatalf("expected current to be cleared after run; got: %+v", st.Current)
	}
	if len(st.History) != 1 || st.History[0].ID != "t1" || st.History[0].SessionID != "sess-1" || st.History[0].Status == "" {
		t.Fatalf("unexpected history: %+v", st.History)
	}
}
