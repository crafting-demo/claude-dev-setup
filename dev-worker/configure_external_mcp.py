#!/usr/bin/env python3
"""
Configure external MCP servers from JSON configuration file.
"""

import json
import subprocess
import sys
import argparse


def configure_external_mcp_servers(config_file_path):
    """Configure external MCP servers from JSON config."""
    try:
        with open(config_file_path, 'r') as f:
            config = json.load(f)
        
        if 'servers' in config:
            for server_name, server_config in config['servers'].items():
                print(f"Configuring external MCP server: {server_name}")
                
                # Build claude mcp add command
                cmd = ['claude', 'mcp', 'add', server_name, '--scope', 'project']
                
                if 'command' in server_config:
                    cmd.extend(['--command', server_config['command']])
                
                if 'args' in server_config:
                    for arg in server_config['args']:
                        cmd.extend(['--args', arg])
                
                # Add environment variables if present
                if 'env' in server_config:
                    for env_var, env_val in server_config['env'].items():
                        cmd.extend(['--env', f'{env_var}={env_val}'])
                
                # Execute command
                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.returncode == 0:
                    print(f"✓ Configured {server_name} successfully")
                else:
                    print(f"✗ Failed to configure {server_name}: {result.stderr}")
        else:
            print("No 'servers' section found in configuration")
    
    except Exception as e:
        print(f"Error parsing external MCP config: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description='Configure external MCP servers from JSON config')
    parser.add_argument('config_file', help='Path to the external MCP configuration JSON file')
    
    args = parser.parse_args()
    configure_external_mcp_servers(args.config_file)


if __name__ == '__main__':
    main() 