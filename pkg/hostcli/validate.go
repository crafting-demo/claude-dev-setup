package hostcli

import (
	"errors"
	"fmt"
	"os"
)

type ActionType string

const (
	ActionBranch ActionType = "branch"
	ActionPR     ActionType = "pr"
	ActionIssue  ActionType = "issue"
)

type Args struct {
	CmdDir      string
	GitHubRepo  string
	ActionType  ActionType
	Branch      string
	PRNumber    string
	IssueNumber string
}

func Validate(a Args) error {
	if a.CmdDir == "" {
		return errors.New("cmd-dir is required")
	}
	if st, err := os.Stat(a.CmdDir); err != nil || !st.IsDir() {
		return fmt.Errorf("cmd-dir not found or not a directory: %s", a.CmdDir)
	}

	if a.GitHubRepo == "" {
		return errors.New("github-repo is required")
	}
	switch a.ActionType {
	case ActionBranch:
		if a.Branch == "" {
			return errors.New("branch action requires --github-branch")
		}
	case ActionPR:
		if a.PRNumber == "" {
			return errors.New("pr action requires --pr-number")
		}
	case ActionIssue:
		if a.IssueNumber == "" {
			return errors.New("issue action requires --issue-number")
		}
	default:
		return fmt.Errorf("invalid action-type: %q", string(a.ActionType))
	}
	return nil
}
