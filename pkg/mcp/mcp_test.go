package mcp

import "testing"

func TestEchoSubagent(t *testing.T) {
	s := NewEchoSubagent("sa")
	out, err := s.Call("hi")
	if err != nil || out != "sa: hi" {
		t.Fatalf("unexpected: out=%q err=%v", out, err)
	}
}
