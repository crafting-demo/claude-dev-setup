package claude

import (
	"bufio"
	"encoding/json"
	"io"
)

// Minimal stream-json event
type Event struct {
	Type string `json:"type"`
	Data any    `json:"data,omitempty"`
}

// ParseStream decodes line-delimited JSON events.
func ParseStream(r io.Reader) ([]Event, error) {
	var out []Event
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		var e Event
		if err := json.Unmarshal(scanner.Bytes(), &e); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return out, nil
}
