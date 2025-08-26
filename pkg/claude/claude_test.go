package claude

import (
	"strings"
	"testing"
)

func TestParseStream(t *testing.T) {
	input := "{\"type\":\"log\",\"data\":\"a\"}\n{\"type\":\"result\",\"data\":{\"ok\":true}}\n"
	evs, err := ParseStream(strings.NewReader(input))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(evs) != 2 || evs[0].Type != "log" || evs[1].Type != "result" {
		t.Fatalf("unexpected events: %+v", evs)
	}
}
