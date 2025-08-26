package sandbox

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Runner provides thin wrappers over Crafting CLI commands (cs exec/scp/sandbox).
// All operations are non-interactive and suitable for automation.
type Runner struct{ workspace string }

func NewRunner(workspace string) *Runner { return &Runner{workspace: workspace} }

// CreateSandbox creates a new sandbox using the provided template and optional pool.
// envVars map will be translated to `-D '<workspace>/env[KEY]=VALUE'` entries.
func (r *Runner) CreateSandbox(sandboxName, template, pool string, envVars map[string]string) error {
	if sandboxName == "" || template == "" {
		return fmt.Errorf("sandbox name and template are required")
	}

	args := r.buildCreateArgs(sandboxName, template, pool, envVars)
	run := func() error {
		cmd := exec.Command("cs", args...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}
	return runWithRetries(run, 5, 2*time.Second)
}

// Exec runs a command inside the sandbox as user 1000 within the configured workspace.
func (r *Runner) Exec(sandboxName string, command string) error {
	if sandboxName == "" || strings.TrimSpace(command) == "" {
		return fmt.Errorf("sandbox and command are required")
	}
	args := []string{"exec", "-t", "-u", "1000", "-W", sandboxName + "/" + r.workspace, "--", "bash", "-lc", command}
	run := func() error {
		cmd := exec.Command("cs", args...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}
	return runWithRetries(run, 5, 2*time.Second)
}

// Mkdir ensures a directory exists inside the sandbox.
func (r *Runner) Mkdir(sandboxName string, remoteDir string) error {
	if sandboxName == "" || remoteDir == "" {
		return fmt.Errorf("sandbox and remoteDir are required")
	}
	return r.Exec(sandboxName, fmt.Sprintf("mkdir -p %s", shellQuote(remoteDir)))
}

// TransferContent writes content to a temporary file and copies it to the sandbox path using cs scp.
func (r *Runner) TransferContent(sandboxName, targetPath, content string) error {
	if sandboxName == "" || targetPath == "" {
		return fmt.Errorf("sandbox and targetPath are required")
	}
	// Ensure remote directory exists first
	remoteDir := filepath.Dir(targetPath)
	if err := r.Mkdir(sandboxName, remoteDir); err != nil {
		return err
	}

	// Create temp file
	tmpFile := filepath.Join(os.TempDir(), fmt.Sprintf("cscc_%d.txt", time.Now().UnixNano()))
	if err := os.WriteFile(tmpFile, []byte(content), 0o600); err != nil {
		return err
	}
	defer os.Remove(tmpFile)

	args := []string{"scp", tmpFile, fmt.Sprintf("%s/%s:%s", sandboxName, r.workspace, targetPath)}
	run := func() error {
		cmd := exec.Command("cs", args...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}
	return runWithRetries(run, 5, 2*time.Second)
}

func shellQuote(s string) string {
	// Minimal quoting for paths
	if strings.ContainsAny(s, " \t\n\"") {
		return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
	}
	return s
}

// BuildCreateCommand builds the exact shell command used for sandbox creation (for dry-run output).
func (r *Runner) BuildCreateCommand(sandboxName, template, pool string, envVars map[string]string) string {
	args := r.buildCreateArgs(sandboxName, template, pool, envVars)
	parts := make([]string, 0, len(args)+1)
	parts = append(parts, "cs")
	for _, a := range args {
		if strings.ContainsAny(a, " \t\n\"") {
			parts = append(parts, shellQuote(a))
		} else {
			parts = append(parts, a)
		}
	}
	return strings.Join(parts, " ")
}

func (r *Runner) buildCreateArgs(sandboxName, template, pool string, envVars map[string]string) []string {
	args := []string{"sandbox", "create", sandboxName, "-t", template}
	if pool != "" {
		args = append(args, "--use-pool", pool)
	}
	// to ensure deterministic order in printed command
	keys := make([]string, 0, len(envVars))
	for k := range envVars {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		v := envVars[k]
		entry := fmt.Sprintf("%s/env[%s]=%s", r.workspace, k, v)
		args = append(args, "-D", entry)
	}
	return args
}

func runWithRetries(fn func() error, attempts int, baseDelay time.Duration) error {
	if attempts < 1 {
		attempts = 1
	}
	var err error
	for i := 0; i < attempts; i++ {
		err = fn()
		if err == nil {
			return nil
		}
		if i < attempts-1 {
			d := baseDelay * time.Duration(1<<i)
			if d > 10*time.Second {
				d = 10 * time.Second
			}
			time.Sleep(d)
		}
	}
	return err
}
