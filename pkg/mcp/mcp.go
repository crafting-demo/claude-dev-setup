package mcp

import "errors"

// Subagent defines the minimal interface for invoking a subagent.
type Subagent interface {
	Name() string
	Call(input string) (string, error)
}

// EchoSubagent is a trivial subagent implementation useful for wiring tests.
type EchoSubagent struct{ name string }

func NewEchoSubagent(name string) *EchoSubagent { return &EchoSubagent{name: name} }
func (e *EchoSubagent) Name() string            { return e.name }
func (e *EchoSubagent) Call(input string) (string, error) {
	if input == "" {
		return "", errors.New("empty input")
	}
	return e.name + ": " + input, nil
}
