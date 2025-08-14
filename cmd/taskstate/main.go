package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/your-org/claude-dev-setup/pkg/taskstate"
)

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: taskstate -state <path> <command> [args...]\n")
	fmt.Fprintf(os.Stderr, "Commands: init | read | status | current | next | create <promptFile> [toolWhitelist] [customId] | update <taskId> <status> [sessionId]\n")
}

func main() {
	statePath := flag.String("state", filepath.Join(os.Getenv("HOME"), "state.json"), "path to state.json")
	flag.Parse()
	args := flag.Args()
	if len(args) == 0 {
		usage()
		os.Exit(2)
	}

	cmd := args[0]
	switch cmd {
	case "init":
		mgr := taskstate.NewManager(*statePath)
		// no-op save of empty state if file missing
		_ = mgr.Save()
		fmt.Println("ok")
	case "read":
		mgr, _ := taskstate.Load(*statePath)
		b, _ := json.MarshalIndent(mgr.GetState(), "", "  ")
		os.Stdout.Write(b)
	case "status":
		mgr, _ := taskstate.Load(*statePath)
		st := mgr.GetState()
		fmt.Printf("current:%v queue:%d history:%d\n", st.Current != nil, len(st.Queue), len(st.History))
	case "current":
		mgr, _ := taskstate.Load(*statePath)
		st := mgr.GetState()
		b, _ := json.MarshalIndent(st.Current, "", "  ")
		os.Stdout.Write(b)
	case "next":
		mgr, _ := taskstate.Load(*statePath)
		t := mgr.StartNext()
		_ = mgr.Save()
		b, _ := json.MarshalIndent(t, "", "  ")
		os.Stdout.Write(b)
	case "create":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "create requires <promptFile>")
			os.Exit(2)
		}
		promptFile := args[1]
		_ = promptFile // reserved for future: embed prompt path in Data
		customId := ""
		if len(args) >= 4 {
			customId = args[3]
		}
		mgr, _ := taskstate.Load(*statePath)
		id := customId
		if id == "" {
			id = fmt.Sprintf("task-%d", os.Getpid())
		}
		mgr.Enqueue(taskstate.Task{ID: id, Status: "pending", Data: map[string]any{"promptFile": promptFile}})
		_ = mgr.Save()
		fmt.Println(id)
	case "update":
		if len(args) < 3 {
			fmt.Fprintln(os.Stderr, "update requires <taskId> <status> [sessionId]")
			os.Exit(2)
		}
		taskId, status := args[1], args[2]
		session := ""
		if len(args) >= 4 {
			session = args[3]
		}
		mgr, _ := taskstate.Load(*statePath)
		st := mgr.GetState()
		// naive: if current matches, update; otherwise if pending in queue, promote and update
		if st.Current != nil && st.Current.ID == taskId {
			if session != "" {
				mgr.LinkSessionToCurrent(session)
			}
			mgr.CompleteCurrent(status)
			_ = mgr.Save()
			fmt.Println("ok")
			return
		}
		// try start-next until matching id (simplistic)
		for {
			t := mgr.StartNext()
			if t == nil {
				break
			}
			if t.ID == taskId {
				if session != "" {
					mgr.LinkSessionToCurrent(session)
				}
				mgr.CompleteCurrent(status)
				break
			}
		}
		_ = mgr.Save()
		fmt.Println("ok")
	default:
		usage()
		os.Exit(2)
	}
}
