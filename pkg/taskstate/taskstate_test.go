package taskstate

import (
	"os"
	"testing"
)

func TestLoadSaveAndQueue(t *testing.T) {
	tmpFile := t.TempDir() + "/state.json"
	m, err := Load(tmpFile)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if err := m.Save(); err != nil {
		t.Fatalf("save empty: %v", err)
	}
	if st, err := os.Stat(tmpFile); err != nil || st.Size() == 0 {
		t.Fatalf("expected non-empty state file")
	}

	m.Enqueue(Task{ID: "a"})
	if got := m.StartNext(); got == nil || got.ID != "a" || got.Status != "in_progress" {
		t.Fatalf("start next unexpected: %+v", got)
	}
	m.LinkSessionToCurrent("sess-123")
	done := m.CompleteCurrent("done")
	if done == nil || done.ID != "a" || done.Status != "done" || done.SessionID != "sess-123" {
		t.Fatalf("complete unexpected: %+v", done)
	}

	if err := m.Save(); err != nil {
		t.Fatalf("save final: %v", err)
	}
}
