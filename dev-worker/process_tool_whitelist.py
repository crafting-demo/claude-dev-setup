#!/usr/bin/env python3
"""
Process tool whitelist from JSON format and output as newline-separated list.
"""

import json
import sys
import argparse


def process_tool_whitelist(whitelist_file_path):
    """Process tool whitelist from JSON format."""
    try:
        with open(whitelist_file_path, 'r') as f:
            tools = json.load(f)
            
        if isinstance(tools, list):
            for tool in tools:
                print(tool)
        else:
            print(f"Error: Expected a JSON array, got {type(tools).__name__}", file=sys.stderr)
            sys.exit(1)
            
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error processing tool whitelist: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description='Process tool whitelist from JSON format')
    parser.add_argument('whitelist_file', help='Path to the tool whitelist JSON file')
    
    args = parser.parse_args()
    process_tool_whitelist(args.whitelist_file)


if __name__ == '__main__':
    main() 