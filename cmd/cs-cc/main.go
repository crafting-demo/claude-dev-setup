package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/your-org/claude-dev-setup/pkg/hostcli"
	"github.com/your-org/claude-dev-setup/pkg/sandbox"
)

func main() {
	opts := &options{}

	rootCmd := &cobra.Command{
		Use:           "cs-cc",
		Short:         "Claude Sandbox Code CLI (Go)",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return run(opts)
		},
	}

	// Core flags (host contracts + GitHub context)
	rootCmd.Flags().StringVar(&opts.cmdDir, "cmd-dir", "/home/owner/cmd", "Path to worker command directory in sandbox")
	rootCmd.Flags().StringVar(&opts.repo, "github-repo", "", "GitHub repo (owner/name)")
	rootCmd.Flags().StringVar(&opts.action, "action-type", "branch", "Action type: branch|pr|issue")
	rootCmd.Flags().StringVar(&opts.branch, "github-branch", "", "Git branch (for action-type=branch)")
	rootCmd.Flags().StringVar(&opts.prNum, "pr-number", "", "PR number (for action-type=pr)")
	rootCmd.Flags().StringVar(&opts.issueNum, "issue-number", "", "Issue number (for action-type=issue)")

	// Orchestration inputs
	rootCmd.Flags().StringVarP(&opts.prompt, "prompt", "p", "", "Prompt string or file path (required)")
	rootCmd.Flags().StringVar(&opts.pool, "pool", "", "Sandbox pool name")
	rootCmd.Flags().StringVar(&opts.ghToken, "github-token", "", "GitHub access token (optional)")
    rootCmd.Flags().StringVar(&opts.mcpCfg, "mcp-config", "", "External MCP config JSON string or file path")
    rootCmd.Flags().StringVar(&opts.agentsDir, "agents-dir", "", "Directory containing agent .md files")
	rootCmd.Flags().StringVarP(&opts.tools, "tools", "t", "", "Tool whitelist JSON string or file path")
	rootCmd.Flags().StringVar(&opts.template, "template", "claude-code-automation", "Sandbox template name")
	rootCmd.Flags().StringVarP(&opts.deleteWhenDone, "delete-when-done", "d", "yes", "Delete sandbox when done: yes|no")
	rootCmd.Flags().StringVarP(&opts.name, "name", "n", "", "Sandbox name (auto-generated if empty)")
	rootCmd.Flags().StringVar(&opts.resume, "resume", "", "Resume existing sandbox (skip creation)")
    rootCmd.Flags().StringVar(&opts.taskID, "task-id", "", "Custom task ID")
	rootCmd.Flags().StringVar(&opts.debug, "debug", "no", "Debug mode: yes|no")
    rootCmd.Flags().StringVar(&opts.customRepoPath, "repo-path", "", "Custom repo path inside sandbox (optional)")
	rootCmd.Flags().BoolVar(&opts.dryRun, "dry-run", false, "Validate and print planned actions without executing")

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "[ERROR] %v\n", err)
		os.Exit(2)
	}
}

type options struct {
	// hostcli-compatible
	cmdDir   string
	repo     string
	action   string
	branch   string
	prNum    string
	issueNum string

	// orchestration inputs
	prompt         string
	pool           string
	ghToken        string
	mcpCfg         string
	agentsDir      string
	tools          string
	template       string
	deleteWhenDone string
	name           string
	resume         string
	taskID         string
	debug          string
	customRepoPath string
	dryRun         bool
}

func run(o *options) error {
	if strings.TrimSpace(o.prompt) == "" {
		return errors.New("prompt (-p) is required")
	}
	if !isYesNo(o.deleteWhenDone) {
		return fmt.Errorf("delete-when-done must be yes|no")
	}
	if !isYesNo(o.debug) {
		return fmt.Errorf("debug must be yes|no")
	}

	// Validate GitHub context only when provided
	if o.repo != "" || o.branch != "" || o.prNum != "" || o.issueNum != "" {
		parsed := hostcli.Args{
			CmdDir:      "/tmp/cscc-validate", // ephemeral
			GitHubRepo:  o.repo,
			ActionType:  hostcli.ActionType(o.action),
			Branch:      o.branch,
			PRNumber:    o.prNum,
			IssueNumber: o.issueNum,
		}
		if err := fakeDirExists(parsed.CmdDir, func() error { return hostcli.Validate(parsed) }); err != nil {
			return err
		}
	}

	// Resolve inputs
	promptContent, err := readFileOrString(o.prompt)
	if err != nil {
		return fmt.Errorf("prompt: %w", err)
	}
	mcpJSON, err := readOptionalJSON(o.mcpCfg)
	if err != nil {
		return fmt.Errorf("mcp-config: %w", err)
	}
	toolsJSON, err := readOptionalJSON(o.tools)
	if err != nil {
		return fmt.Errorf("tools: %w", err)
	}
	agents, err := listAgentFiles(o.agentsDir)
	if err != nil {
		return fmt.Errorf("agents-dir: %w", err)
	}

	// Determine sandbox
	isResume := strings.TrimSpace(o.resume) != ""
	sandboxName := o.resume
	if !isResume {
		if o.name != "" {
			sandboxName = o.name
		} else {
			sandboxName = generateSandboxName(o.repo, firstNonEmpty(o.prNum, o.issueNum, "dev"))
		}
	}

	// Environment variables to inject
	envVars := map[string]string{
		"SHOULD_DELETE":      yesNoToBool(o.deleteWhenDone),
		"DEBUG_MODE":         yesNoToBool(o.debug),
		"ANTHROPIC_API_KEY":  "${secret:shared/anthropic-apikey-eng}",
		"GH_PROMPT_DISABLED": "1",
	}
	if o.customRepoPath != "" {
		envVars["CUSTOM_REPO_PATH"] = o.customRepoPath
	}
	if o.repo != "" {
		envVars["GITHUB_REPO"] = o.repo
	}
	if o.ghToken != "" {
		envVars["GITHUB_TOKEN"] = o.ghToken
	}
	if o.prNum != "" {
		envVars["PR_NUMBER"] = o.prNum
		envVars["ACTION_TYPE"] = "pr"
	} else if o.issueNum != "" {
		envVars["ISSUE_NUMBER"] = o.issueNum
		envVars["ACTION_TYPE"] = "issue"
	} else if o.branch != "" {
		envVars["GITHUB_BRANCH"] = o.branch
		envVars["ACTION_TYPE"] = "branch"
	}

	// GitHub resource existence checks (parity with JS CLI). Only validate on create.
	if !isResume {
		if err := validateGitHubResources(o.repo, o.prNum, o.issueNum, o.branch, o.ghToken); err != nil {
			return err
		}
	}

	// Dry-run
	if o.dryRun {
		// Build and show exact create command
		r := sandbox.NewRunner()
		createCmd := r.BuildCreateCommand(firstNonEmpty(o.name, generateSandboxName(o.repo, firstNonEmpty(o.prNum, o.issueNum, "dev"))), o.template, o.pool, envVars)
		fmt.Println("cs sandbox create (preview):")
		fmt.Println(createCmd)
		printDryRun(sandboxName, isResume, o, agents)
		return nil
	}

	r := sandbox.NewRunner()
	if !isResume {
		fmt.Printf("[INFO] Creating sandbox %s using template %s\n", sandboxName, o.template)
		if err := r.CreateSandbox(sandboxName, o.template, o.pool, envVars); err != nil {
			return fmt.Errorf("sandbox create failed: %w", err)
		}
	} else {
		fmt.Printf("[INFO] Resuming sandbox %s\n", sandboxName)
	}

	// Transfers
	cmdDir := firstNonEmpty(o.cmdDir, "/home/owner/cmd")
	promptFile := "prompt.txt"
	if isResume {
		promptFile = "prompt_new.txt"
	}
	if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, promptFile), promptContent); err != nil {
		return fmt.Errorf("transfer prompt: %w", err)
	}
	if mcpJSON != "" {
		if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "external_mcp.txt"), mcpJSON); err != nil {
			return fmt.Errorf("transfer mcp: %w", err)
		}
	}
	if toolsJSON != "" {
		if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "tool_whitelist.txt"), toolsJSON); err != nil {
			return fmt.Errorf("transfer tools: %w", err)
		}
	}
	if o.repo != "" {
		if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "github_repo.txt"), o.repo); err != nil {
			return fmt.Errorf("transfer github repo: %w", err)
		}
	}
	if o.ghToken != "" {
		if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "github_token.txt"), o.ghToken); err != nil {
			return fmt.Errorf("transfer github token: %w", err)
		}
	}
	if o.branch != "" {
		if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "github_branch.txt"), o.branch); err != nil {
			return fmt.Errorf("transfer branch: %w", err)
		}
	}
	if o.prNum != "" {
		if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "pr_number.txt"), o.prNum); err != nil {
			return fmt.Errorf("transfer pr: %w", err)
		}
	}
	if o.issueNum != "" {
		if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "issue_number.txt"), o.issueNum); err != nil {
			return fmt.Errorf("transfer issue: %w", err)
		}
	}
	actionType := ""
	if o.prNum != "" {
		actionType = "pr"
	} else if o.issueNum != "" {
		actionType = "issue"
	} else if o.branch != "" {
		actionType = "branch"
	}
	if actionType != "" {
		if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "action_type.txt"), actionType); err != nil {
			return fmt.Errorf("transfer action type: %w", err)
		}
	}
	if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "task_mode.txt"), ternary(isResume, "resume", "create")); err != nil {
		return fmt.Errorf("transfer task mode: %w", err)
	}
	if o.taskID != "" {
		if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "task_id.txt"), o.taskID); err != nil {
			return fmt.Errorf("transfer task id: %w", err)
		}
	}
	if err := r.TransferContent(sandboxName, filepath.Join(cmdDir, "prompt_filename.txt"), promptFile); err != nil {
		return fmt.Errorf("transfer prompt filename: %w", err)
	}

	// Agents
	agentsDir := "/home/owner/.claude/agents"
	if len(agents) > 0 {
		if err := r.Mkdir(sandboxName, agentsDir); err != nil {
			return fmt.Errorf("mkdir agents: %w", err)
		}
		for _, a := range agents {
			target := filepath.Join(agentsDir, a.name+".md")
			if err := r.TransferContent(sandboxName, target, a.content); err != nil {
				return fmt.Errorf("transfer agent %s: %w", a.name, err)
			}
		}
	}

	fmt.Printf("[SUCCESS] Sandbox \"%s\" %s and configured.\n", sandboxName, ternary(isResume, "resumed", "created"))

	if strings.EqualFold(o.debug, "yes") {
		fmt.Printf("[INFO] Debug mode enabled – executing worker…\n")
		if err := r.Exec(sandboxName, "bash -i -c '~/claude/dev-worker/start-worker.sh'"); err != nil {
			return fmt.Errorf("worker exec failed: %w", err)
		}
		fmt.Println("[SUCCESS] Worker finished")
	}

	return nil
}

func isYesNo(v string) bool {
	s := strings.ToLower(strings.TrimSpace(v))
	return s == "yes" || s == "no"
}

func yesNoToBool(v string) string {
	if strings.EqualFold(strings.TrimSpace(v), "yes") {
		return "true"
	}
	return "false"
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

func generateSandboxName(repo string, item string) string {
	repoName := "sandbox"
	if repo != "" {
		parts := strings.Split(repo, "/")
		if len(parts) == 2 && parts[1] != "" {
			repoName = parts[1]
		}
	}
	repoName = sanitizeName(repoName)
	short := fmt.Sprintf("%d", time.Now().UnixMilli())
	if len(short) > 4 {
		short = short[len(short)-4:]
	}
	if item == "" {
		item = "dev"
	}
	name := fmt.Sprintf("cw-%s-%s-%s", repoName, item, short)
	if len(name) > 20 {
		name = name[:20]
	}
	return name
}

func sanitizeName(s string) string {
	s = strings.ToLower(s)
	s = regexp.MustCompile(`[^a-z0-9-]`).ReplaceAllString(s, "-")
	if s == "" {
		s = "sandbox"
	}
	// ensure starts with letter
	if s[0] < 'a' || s[0] > 'z' {
		s = "a" + s[1:]
	}
	// ensure ends with alnum
	last := s[len(s)-1]
	if !((last >= 'a' && last <= 'z') || (last >= '0' && last <= '9')) {
		s = s[:len(s)-1] + "9"
	}
	if len(s) > 8 {
		s = s[:8]
	}
	return s
}

func readFileOrString(value string) (string, error) {
	v := strings.TrimSpace(value)
	if v == "" {
		return "", nil
	}
	if strings.ContainsAny(v, "/\\") || strings.HasSuffix(v, ".txt") || strings.HasSuffix(v, ".json") || strings.HasSuffix(v, ".md") {
		b, err := os.ReadFile(absPath(v))
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(string(b)), nil
	}
	return v, nil
}

func readOptionalJSON(value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", nil
	}
	content, err := readFileOrString(value)
	if err != nil {
		return "", err
	}
	var js any
	if err := json.Unmarshal([]byte(content), &js); err != nil {
		return "", fmt.Errorf("invalid JSON: %w", err)
	}
	return content, nil
}

type agentFile struct {
	name    string
	content string
}

func listAgentFiles(dir string) ([]agentFile, error) {
	if strings.TrimSpace(dir) == "" {
		return nil, nil
	}
	root := absPath(dir)
	var files []agentFile
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if strings.HasSuffix(strings.ToLower(d.Name()), ".md") {
			b, rerr := os.ReadFile(path)
			if rerr != nil {
				return rerr
			}
			name := strings.TrimSuffix(d.Name(), filepath.Ext(d.Name()))
			files = append(files, agentFile{name: name, content: string(b)})
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(files, func(i, j int) bool { return files[i].name < files[j].name })
	return files, nil
}

func absPath(p string) string {
	if p == "" {
		return p
	}
	if filepath.IsAbs(p) {
		return p
	}
	wd, _ := os.Getwd()
	return filepath.Join(wd, p)
}

func ternary(cond bool, a, b string) string {
	if cond {
		return a
	}
	return b
}

// fakeDirExists ensures a directory exists around a callback (for hostcli.Validate)
func fakeDirExists(path string, fn func() error) error {
	if err := os.MkdirAll(path, 0o755); err != nil {
		return err
	}
	return fn()
}

func printDryRun(sandboxName string, isResume bool, o *options, agents []agentFile) {
	mode := "create"
	if isResume {
		mode = "resume"
	}
	fmt.Println("--- DRY RUN ---")
	fmt.Printf("sandbox: %s (%s)\n", sandboxName, mode)
	if o.repo != "" {
		fmt.Printf("repo: %s\n", o.repo)
	}
	if o.branch != "" {
		fmt.Printf("branch: %s\n", o.branch)
	}
	if o.prNum != "" {
		fmt.Printf("pr: %s\n", o.prNum)
	}
	if o.issueNum != "" {
		fmt.Printf("issue: %s\n", o.issueNum)
	}
	fmt.Printf("template: %s\n", o.template)
	if o.pool != "" {
		fmt.Printf("pool: %s\n", o.pool)
	}
	fmt.Printf("delete-when-done: %s\n", o.deleteWhenDone)
	fmt.Printf("debug: %s\n", o.debug)
	if o.customRepoPath != "" {
		fmt.Printf("repo-path: %s\n", o.customRepoPath)
	}
	fmt.Printf("will transfer: %s\n", ternary(isResume, "prompt_new.txt", "prompt.txt"))
	if strings.TrimSpace(o.mcpCfg) != "" {
		fmt.Println("will transfer: external_mcp.txt")
	}
	if strings.TrimSpace(o.tools) != "" {
		fmt.Println("will transfer: tool_whitelist.txt")
	}
	if o.repo != "" {
		fmt.Println("will transfer: github_repo.txt")
	}
	if o.ghToken != "" {
		fmt.Println("will transfer: github_token.txt")
	}
	if o.branch != "" {
		fmt.Println("will transfer: github_branch.txt")
	}
	if o.prNum != "" {
		fmt.Println("will transfer: pr_number.txt, action_type.txt=pr")
	}
	if o.issueNum != "" {
		fmt.Println("will transfer: issue_number.txt, action_type.txt=issue")
	}
	if o.taskID != "" {
		fmt.Println("will transfer: task_id.txt")
	}
	fmt.Println("will transfer: task_mode.txt, prompt_filename.txt")
	if len(agents) > 0 {
		fmt.Printf("agents: %d files -> ~/.claude/agents\n", len(agents))
	}
	fmt.Println("--------------")
}

// validateGitHubResources mirrors JS checks using gh CLI. Network failures are warnings; existence failures are errors.
func validateGitHubResources(repo, pr, issue, branch, token string) error {
	if repo == "" {
		return nil
	}
	// Environment with optional token
	env := os.Environ()
	if token != "" {
		env = append(env, "GITHUB_TOKEN="+token)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	run := func(name string, args ...string) error {
		cmd := exec.CommandContext(ctx, name, args...)
		cmd.Env = env
		cmd.Stdout = nil
		cmd.Stderr = nil
		return cmd.Run()
	}

	if pr != "" {
		if err := run("gh", "pr", "view", pr, "--repo", repo); err != nil {
			return fmt.Errorf("pull request #%s does not exist in %s", pr, repo)
		}
		return nil
	}
	if issue != "" {
		if err := run("gh", "issue", "view", issue, "--repo", repo, "--json", "number"); err != nil {
			return fmt.Errorf("issue #%s does not exist in %s", issue, repo)
		}
		return nil
	}
	if branch != "" {
		if err := run("gh", "api", "repos/"+repo+"/branches/"+branch, "--jq", ".name"); err != nil {
			return fmt.Errorf("branch '%s' does not exist in %s", branch, repo)
		}
		return nil
	}
	return nil
}
