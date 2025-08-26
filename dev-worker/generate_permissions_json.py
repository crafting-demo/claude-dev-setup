#!/usr/bin/env python3
"""
Generate Claude permissions JSON from processed tool whitelist.
"""

import json
import sys
import argparse


def generate_permissions_json(whitelist_file_path, fallback_tools=None):
    """Generate permissions JSON from tool whitelist file."""
    if fallback_tools is None:
        fallback_tools = [
            "Read", "Write", "Edit", "MultiEdit", "LS", "Glob", "Grep",
            "Bash", "Task", "TodoRead", "TodoWrite", "NotebookRead", 
            "NotebookEdit", "WebFetch", "WebSearch"
        ]
    
    try:
        with open(whitelist_file_path, 'r') as f:
            tools = [line.strip() for line in f if line.strip()]
        
        if not tools:
            tools = fallback_tools
            status = "fallback"
        else:
            status = "whitelist"
            
    except FileNotFoundError:
        tools = fallback_tools
        status = "fallback"
    except Exception as e:
        print(f"Error reading whitelist: {e}", file=sys.stderr)
        tools = fallback_tools
        status = "fallback"
    
    # Generate the permissions JSON structure
    permissions = {
        "permissions": {
            "allow": tools,
            "deny": []
        },
        # For compatibility with newer versions of Claude Code that expect allowedTools
        "allowedTools": tools,
        "ignorePatterns": [],
        "enableAllProjectMcpServers": True
    }
    
    return permissions, len(tools), status


def main():
    parser = argparse.ArgumentParser(description='Generate Claude permissions JSON from tool whitelist')
    parser.add_argument('whitelist_file', help='Path to the processed tool whitelist file')
    parser.add_argument('--format', choices=['json', 'info', 'both'], default='both',
                       help='Output format: json only, info only, or both')
    parser.add_argument('--indent', type=int, default=2, help='JSON indentation level')
    
    args = parser.parse_args()
    
    permissions, tool_count, status = generate_permissions_json(args.whitelist_file)
    
    if args.format in ['info', 'both']:
        print(f"TOOL_COUNT={tool_count}")
        print(f"STATUS={status}")
        if args.format == 'both':
            print("---")
    
    if args.format in ['json', 'both']:
        print(json.dumps(permissions, indent=args.indent))
    
    if args.format == 'info':
        # Also print the tool list for verification
        tools = permissions['permissions']['allow']
        print(f"TOOLS={','.join(tools)}")


if __name__ == '__main__':
    main() 