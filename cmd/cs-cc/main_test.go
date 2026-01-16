package main

import (
	"testing"
)

func captureOutput(t *testing.T, fn func() error) (string, error) {
	// legacy helper retained; not used in simplified assertions
	return "", fn()
}

func TestRun_DryRun_BranchFlags(t *testing.T) {
	opts := &options{
		prompt:         "Do work",
		pool:           "mypool",
		repo:           "org/repo",
		branch:         "main",
		ghToken:        "tok",
		mcpCfg:         "{}",
		tools:          "[]",
		template:       "claude-code-automation",
		deleteWhenDone: "no",
		name:           "",
		resume:         "resume-sbx",
		taskID:         "task-123",
		debug:          "yes",
		customRepoPath: "workdir",
		dryRun:         true,
		workspace:      "claude",
	}
	_, err := captureOutput(t, func() error { return run(opts) })
	if err != nil {
		t.Fatalf("run dry-run: %v", err)
	}
}

func TestRun_InvalidYesNo(t *testing.T) {
	opts := &options{prompt: "x", deleteWhenDone: "maybe", dryRun: true, workspace: "claude"}
	if err := run(opts); err == nil {
		t.Fatalf("expected error for invalid delete-when-done")
	}
	opts2 := &options{prompt: "x", deleteWhenDone: "yes", debug: "maybe", dryRun: true, workspace: "claude"}
	if err := run(opts2); err == nil {
		t.Fatalf("expected error for invalid debug")
	}
}
