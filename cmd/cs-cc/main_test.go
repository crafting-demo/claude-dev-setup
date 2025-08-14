package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func captureOutput(t *testing.T, fn func() error) (string, error) {
	// capture stdout
	origStdout := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	os.Stdout = w
	defer func() { os.Stdout = origStdout }()

	// capture stderr as well to keep output unified
	origStderr := os.Stderr
	sr, sw, err := os.Pipe()
	if err != nil {
		w.Close()
		os.Stdout = origStdout
		t.Fatalf("pipe: %v", err)
	}
	os.Stderr = sw
	defer func() { os.Stderr = origStderr }()

	ch := make(chan string, 1)
	go func() {
		_ = w.Close()
		_ = sw.Close()
		buf1 := make([]byte, 64*1024)
		n1, _ := r.Read(buf1)
		buf2 := make([]byte, 64*1024)
		n2, _ := sr.Read(buf2)
		ch <- string(buf1[:n1]) + string(buf2[:n2])
	}()

	err = fn()
	out := <-ch
	return out, err
}

func TestRun_DryRun_BranchFlags(t *testing.T) {
	opts := &options{
		prompt:         "Do work",
		pool:           "mypool",
		repo:           "org/repo",
		action:         "branch",
		branch:         "main",
		ghToken:        "tok",
		mcpCfg:         "{}",
		tools:          "[]",
		template:       "claude-code-automation",
		deleteWhenDone: "no",
		name:           "",
		resume:         "resume-sbx", // skip gh validation
		taskID:         "task-123",
		debug:          "yes",
		customRepoPath: "workdir",
		dryRun:         true,
	}
	out, err := captureOutput(t, func() error { return run(opts) })
	if err != nil {
		t.Fatalf("run dry-run: %v", err)
	}
	// Check env propagation in printed create command
	if !strings.Contains(out, "claude/env[GITHUB_REPO]=org/repo") {
		t.Fatalf("missing GITHUB_REPO in create preview: %s", out)
	}
	if !strings.Contains(out, "claude/env[GITHUB_BRANCH]=main") {
		t.Fatalf("missing GITHUB_BRANCH in create preview: %s", out)
	}
	if !strings.Contains(out, "claude/env[DEBUG_MODE]=true") {
		t.Fatalf("missing DEBUG_MODE in create preview: %s", out)
	}
	if !strings.Contains(out, "repo-path: workdir") {
		t.Fatalf("missing repo-path line in dry run output: %s", out)
	}
	// Transfers list
	if !strings.Contains(out, "will transfer: prompt_new.txt") { // resume mode
		t.Fatalf("expected prompt_new.txt transfer in resume mode: %s", out)
	}
	if !strings.Contains(out, "will transfer: github_branch.txt") {
		t.Fatalf("expected github_branch.txt transfer: %s", out)
	}
	if !strings.Contains(out, "will transfer: tool_whitelist.txt") {
		t.Fatalf("expected tool_whitelist.txt transfer: %s", out)
	}
	if !strings.Contains(out, "will transfer: external_mcp.txt") {
		t.Fatalf("expected external_mcp.txt transfer: %s", out)
	}
}

func TestRun_DryRun_PRAndIssueFlags(t *testing.T) {
	// PR path
	optsPR := &options{prompt: "x", repo: "org/repo", prNum: "12", ghToken: "tok", dryRun: true, resume: "r"}
	outPR, err := captureOutput(t, func() error { return run(optsPR) })
	if err != nil {
		t.Fatalf("pr run: %v", err)
	}
	if !strings.Contains(outPR, "will transfer: pr_number.txt, action_type.txt=pr") {
		t.Fatalf("expected pr transfer lines: %s", outPR)
	}

	// Issue path
	optsIssue := &options{prompt: "x", repo: "org/repo", issueNum: "34", dryRun: true, resume: "r"}
	outIssue, err := captureOutput(t, func() error { return run(optsIssue) })
	if err != nil {
		t.Fatalf("issue run: %v", err)
	}
	if !strings.Contains(outIssue, "will transfer: issue_number.txt, action_type.txt=issue") {
		t.Fatalf("expected issue transfer lines: %s", outIssue)
	}
}

func TestRun_DryRun_AgentsDir(t *testing.T) {
	tmp := t.TempDir()
	agents := filepath.Join(tmp, "agents")
	if err := os.MkdirAll(agents, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(agents, "one.md"), []byte("hello"), 0o644); err != nil {
		t.Fatal(err)
	}
	opts := &options{prompt: "x", agentsDir: agents, dryRun: true, resume: "r"}
	out, err := captureOutput(t, func() error { return run(opts) })
	if err != nil {
		t.Fatalf("run: %v", err)
	}
	if !strings.Contains(out, "agents: 1 files -> ~/.claude/agents") {
		t.Fatalf("expected agents transfer note: %s", out)
	}
}

func TestRun_InvalidYesNo(t *testing.T) {
	opts := &options{prompt: "x", deleteWhenDone: "maybe", dryRun: true}
	if err := run(opts); err == nil {
		t.Fatalf("expected error for invalid delete-when-done")
	}
	opts2 := &options{prompt: "x", deleteWhenDone: "yes", debug: "maybe", dryRun: true}
	if err := run(opts2); err == nil {
		t.Fatalf("expected error for invalid debug")
	}
}
