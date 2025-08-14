package hostcli

import (
	"os"
	"testing"
)

func TestValidate_BranchSuccess(t *testing.T) {
	tmp := t.TempDir()
	a := Args{
		CmdDir:     tmp,
		GitHubRepo: "org/repo",
		ActionType: ActionBranch,
		Branch:     "main",
	}
	if err := Validate(a); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestValidate_MissingCmdDir(t *testing.T) {
	a := Args{CmdDir: "", GitHubRepo: "org/repo", ActionType: ActionBranch, Branch: "x"}
	if err := Validate(a); err == nil {
		t.Fatalf("expected error for missing cmd dir")
	}
}

func TestValidate_InvalidAction(t *testing.T) {
	tmp := t.TempDir()
	a := Args{CmdDir: tmp, GitHubRepo: "org/repo", ActionType: ActionType("bogus")}
	if err := Validate(a); err == nil {
		t.Fatalf("expected error for invalid action type")
	}
}

func TestValidate_PRRequiresNumber(t *testing.T) {
	tmp := t.TempDir()
	a := Args{CmdDir: tmp, GitHubRepo: "org/repo", ActionType: ActionPR}
	if err := Validate(a); err == nil {
		t.Fatalf("expected error for missing pr-number")
	}
}

func TestValidate_IssueRequiresNumber(t *testing.T) {
	tmp := t.TempDir()
	a := Args{CmdDir: tmp, GitHubRepo: "org/repo", ActionType: ActionIssue}
	if err := Validate(a); err == nil {
		t.Fatalf("expected error for missing issue-number")
	}
}

func TestValidate_CmdDirMustExist(t *testing.T) {
	// Create then remove to ensure it doesn't exist
	tmp := t.TempDir()
	path := tmp + "/gone"
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatalf("prep: %v", err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatalf("prep: %v", err)
	}
	a := Args{CmdDir: path, GitHubRepo: "org/repo", ActionType: ActionBranch, Branch: "x"}
	if err := Validate(a); err == nil {
		t.Fatalf("expected error for non-existent cmd dir")
	}
}
