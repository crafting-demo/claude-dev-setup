package taskstate

import (
	"encoding/json"
	"errors"
	"os"
	"sync"
	"time"
)

type Task struct {
	ID        string         `json:"id"`
	Status    string         `json:"status"`
	SessionID string         `json:"sessionId,omitempty"`
	CreatedAt time.Time      `json:"createdAt"`
	UpdatedAt time.Time      `json:"updatedAt"`
	Data      map[string]any `json:"data,omitempty"`
}

type State struct {
	Current *Task  `json:"current,omitempty"`
	Queue   []Task `json:"queue,omitempty"`
	History []Task `json:"history,omitempty"`
}

type Manager struct {
	path  string
	mu    sync.Mutex
	state State
}

func NewManager(path string) *Manager {
	return &Manager{path: path, state: State{}}
}

func Load(path string) (*Manager, error) {
	m := NewManager(path)
	if path == "" {
		return nil, errors.New("empty state path")
	}
	b, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return m, nil
		}
		return nil, err
	}
	if len(b) == 0 {
		return m, nil
	}
	if err := json.Unmarshal(b, &m.state); err != nil {
		return nil, err
	}
	return m, nil
}

func (m *Manager) Save() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	b, err := json.MarshalIndent(m.state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(m.path, b, 0o644)
}

func (m *Manager) GetState() State {
	m.mu.Lock()
	defer m.mu.Unlock()
	// Return a shallow copy
	s := m.state
	return s
}

func (m *Manager) Enqueue(task Task) {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now().UTC()
	if task.CreatedAt.IsZero() {
		task.CreatedAt = now
	}
	task.UpdatedAt = now
	m.state.Queue = append(m.state.Queue, task)
}

func (m *Manager) StartNext() *Task {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.state.Current != nil {
		return m.state.Current
	}
	if len(m.state.Queue) == 0 {
		return nil
	}
	next := m.state.Queue[0]
	m.state.Queue = m.state.Queue[1:]
	next.Status = "in_progress"
	next.UpdatedAt = time.Now().UTC()
	m.state.Current = &next
	return m.state.Current
}

func (m *Manager) CompleteCurrent(finalStatus string) *Task {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.state.Current == nil {
		return nil
	}
	cur := m.state.Current
	if finalStatus == "" {
		finalStatus = "done"
	}
	cur.Status = finalStatus
	cur.UpdatedAt = time.Now().UTC()
	m.state.History = append(m.state.History, *cur)
	m.state.Current = nil
	return &m.state.History[len(m.state.History)-1]
}

func (m *Manager) LinkSessionToCurrent(sessionID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.state.Current == nil {
		return false
	}
	m.state.Current.SessionID = sessionID
	m.state.Current.UpdatedAt = time.Now().UTC()
	return true
}
