package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/your-org/claude-dev-setup/pkg/hostcli"
)

func main() {
	var cmdDir, repo, action, branch, prNum, issueNum string
	flag.StringVar(&cmdDir, "cmd-dir", "/home/owner/cmd", "Path to worker command directory")
	flag.StringVar(&repo, "github-repo", "", "GitHub repo (owner/name)")
	flag.StringVar(&action, "action-type", "branch", "Action type: branch|pr|issue")
	flag.StringVar(&branch, "github-branch", "", "Git branch (for action-type=branch)")
	flag.StringVar(&prNum, "pr-number", "", "PR number (for action-type=pr)")
	flag.StringVar(&issueNum, "issue-number", "", "Issue number (for action-type=issue)")
	flag.Parse()

	args := hostcli.Args{
		CmdDir:      cmdDir,
		GitHubRepo:  repo,
		ActionType:  hostcli.ActionType(action),
		Branch:      branch,
		PRNumber:    prNum,
		IssueNumber: issueNum,
	}
	if err := hostcli.Validate(args); err != nil {
		fmt.Fprintf(os.Stderr, "[ERROR] validation failed: %v\n", err)
		os.Exit(2)
	}

	fmt.Printf("[INFO] cs-cc validated args: cmdDir=%s repo=%s action=%s\n", cmdDir, repo, action)
}
