#!/usr/bin/env python3
"""
Patch ~/.claude.json to enable local MCP server for a specific project path.

This script ensures that the global Claude configuration includes the necessary
mcpServers definition and enabledMcpjsonServers entry for the specified project
directory, so that `claude mcp list` will show the local_server.
"""

import json
import os
import sys
from pathlib import Path


def patch_claude_config(project_path, server_name="local_server", claude_config_path=None):
    """
    Patch the global Claude configuration to enable MCP server for project.
    
    Args:
        project_path: Absolute path to the project directory
        server_name: Name of the MCP server (default: "local_server")
        claude_config_path: Path to Claude config file (default: ~/.claude.json)
    """
    if claude_config_path is None:
        claude_config_path = Path.home() / ".claude.json"
    else:
        claude_config_path = Path(claude_config_path)
    
    # Check if config file exists
    if not claude_config_path.exists():
        print(f"[WARNING] Claude config not found at {claude_config_path}")
        return False
    
    try:
        # Load existing configuration
        with open(claude_config_path, 'r', encoding='utf-8') as fh:
            data = json.load(fh)
    except Exception as e:
        print(f"[ERROR] Could not load {claude_config_path}: {e}", file=sys.stderr)
        return False
    
    # Ensure projects section exists
    projects = data.setdefault('projects', {})
    proj_entry = projects.setdefault(project_path, {})
    
    # Default allowed tools for Claude Code
    default_tools = [
        "Read", "Write", "Edit", "MultiEdit", "LS", "Glob", "Grep",
        "Bash", "Task", "TodoRead", "TodoWrite", "NotebookRead", 
        "NotebookEdit", "WebFetch", "WebSearch"
    ]
    
    # Ensure allowedTools array contains the default tools
    allowed_tools = proj_entry.setdefault('allowedTools', [])
    tools_added = []
    for tool in default_tools:
        if tool not in allowed_tools:
            allowed_tools.append(tool)
            tools_added.append(tool)
    
    if tools_added:
        print(f"[INFO] Added tools to allowedTools: {', '.join(tools_added)}")
    
    # Enable all project MCP servers
    proj_entry['enableAllProjectMcpServers'] = True
    print(f"[INFO] Set enableAllProjectMcpServers to true for {project_path}")
    
    # Ensure enabledMcpjsonServers array contains the server
    enabled = proj_entry.setdefault('enabledMcpjsonServers', [])
    if server_name not in enabled:
        enabled.append(server_name)
        print(f"[INFO] Added {server_name} to enabledMcpjsonServers for {project_path}")
    
    # Ensure mcpServers definition exists for this project
    mcp_servers = proj_entry.setdefault('mcpServers', {})
    if server_name not in mcp_servers:
        mcp_servers[server_name] = {
            "type": "stdio",
            "command": ".mcp.json",
            "args": [],
            "env": {}
        }
        print(f"[INFO] Added {server_name} definition to mcpServers for {project_path}")
    
    try:
        # Write the patched config back
        with open(claude_config_path, 'w', encoding='utf-8') as fh:
            json.dump(data, fh, indent=2)
        print(f"[SUCCESS] Patched {claude_config_path} for project {project_path}")
        return True
    except Exception as e:
        print(f"[ERROR] Could not write {claude_config_path}: {e}", file=sys.stderr)
        return False


def main():
    """Command line interface for the patch script."""
    if len(sys.argv) < 2:
        print("Usage: patch_claude_config.py <project_path> [server_name]")
        print("Example: patch_claude_config.py /home/owner/claude/target-repo")
        sys.exit(1)
    
    project_path = sys.argv[1]
    server_name = sys.argv[2] if len(sys.argv) > 2 else "local_server"
    
    # Convert to absolute path
    project_path = os.path.abspath(project_path)
    
    success = patch_claude_config(project_path, server_name)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main() 