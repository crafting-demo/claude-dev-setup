package hostcli

import (
	"os"
	"testing"
)

func TestValidate_MinimalSuccess(t *testing.T) {
	tmp := t.TempDir()
	a := Args{
		CmdDir:     tmp,
		GitHubRepo: "org/repo",
		Branch:     "main",
	}
	if err := Validate(a); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestValidate_MissingCmdDir(t *testing.T) {
	a := Args{CmdDir: "", GitHubRepo: "org/repo", Branch: "x"}
	if err := Validate(a); err == nil {
		t.Fatalf("expected error for missing cmd dir")
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
	a := Args{CmdDir: path, GitHubRepo: "org/repo", Branch: "x"}
	if err := Validate(a); err == nil {
		t.Fatalf("expected error for non-existent cmd dir")
	}
}
