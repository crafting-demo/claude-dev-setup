# Claude Dev Setup Examples

This directory contains practical examples demonstrating how to use the `cs-cc` CLI for various developer agent workflows.

## Available Examples

### Multi-Agent Inventory Export (`multi-agent-inventory-export/`)

A comprehensive example showcasing a three-agent collaborative workflow to implement a CSV export feature:

- **Software Engineer** - Implements the feature
- **QA Analyst** - Writes tests 
- **Documentation Writer** - Updates documentation

This example demonstrates:
- Multi-agent coordination using MCP tools
- GitHub integration with automatic PR creation
- Real-time workflow streaming
- Persistent sandbox management

**Quick Start:**
```bash
cd multi-agent-inventory-export
export GITHUB_TOKEN="your_token"
./run-example.sh
```

## Prerequisites

All examples require:
- Built `cs-cc` CLI (available at `./cs-cc`)
- `GITHUB_TOKEN` environment variable set with repo access permissions
- `ANTHROPIC_API_KEY` environment variable set with your Anthropic API key
- Access to target GitHub repositories

## Example Structure

Each example typically includes:
- `run-example.sh` - Main execution script
- `README.md` - Detailed documentation
- Configuration files (prompts, tool definitions, etc.)

## Adding New Examples

When creating new examples:
1. Create a descriptive directory name
2. Include a comprehensive README
3. Provide all necessary configuration files
4. Make scripts executable (`chmod +x`)
5. Update this top-level README

## Getting Started

1. **Build the CLI** (if not already done):
   ```bash
   # Follow build instructions for cs-cc
   ```

2. **Set up authentication**:
   ```bash
   export GITHUB_TOKEN="your_github_personal_access_token"
   export ANTHROPIC_API_KEY="your_anthropic_api_key"
   ```

3. **Choose an example and run it**:
   ```bash
   cd multi-agent-inventory-export
   ./run-example.sh
   ```

## Troubleshooting

- **Permission errors**: Ensure scripts are executable (`chmod +x script.sh`)
- **CLI not found**: Verify the CLI is built and path is correct
- **GitHub access**: Check token permissions and repository access
- **Sandbox issues**: Verify Crafting account and credentials

For example-specific issues, refer to the individual README files. 