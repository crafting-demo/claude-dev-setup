package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/your-org/claude-dev-setup/pkg/worker"
)

func main() {
	cmdDir := os.Getenv("CMD_DIR")
	if cmdDir == "" {
		cmdDir = "/home/owner/cmd"
	}
	statePath := os.Getenv("STATE_PATH")
	if statePath == "" {
		statePath = filepath.Join(os.Getenv("HOME"), "state.json")
	}
	sessionPath := os.Getenv("SESSION_PATH")
	if sessionPath == "" {
		sessionPath = filepath.Join(os.Getenv("HOME"), "session.json")
	}

	r := worker.NewRunner()
	if err := r.Run(cmdDir, statePath, sessionPath); err != nil {
		fmt.Fprintf(os.Stderr, "[ERROR] worker run failed: %v\n", err)
		os.Exit(23)
	}
}
