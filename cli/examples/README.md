# Claude Dev Setup Examples

This directory contains practical examples demonstrating how to use the `cs-cc` CLI for various developer agent workflows.

## Available Examples

### 🚀 Multi-Agent Inventory Export (`multi-agent-inventory-export/`)

A comprehensive example showcasing a three-agent collaborative workflow to implement a CSV export feature:

- **front_end_engineer** - UI components and user experience
- **back_end_engineer** - API endpoints and data processing  
- **documentation_writer** - Feature documentation and user guides

### 🔐 Secure Authentication Pipeline (`secure-auth-pipeline/`)

A sophisticated example demonstrating **sequential subagent orchestration** where agents build upon each other's work:

- **software_engineer** - Implements JWT authentication system with APIs and client integration
- **security_analyst** - Reviews implementation, applies security hardening and OWASP compliance
- **documentation_writer** - Creates comprehensive security documentation and developer guides

This example showcases how agents can work in sequence with clear dependencies, context inheritance, and iterative refinement cycles to produce production-ready, secure code.

### 📝 Emoji README Enhancement (`emoji-readme-example/`)

A simple single-agent example demonstrating README enhancement with emojis and visual improvements:

- **emoji_enhancer** - Specializes in adding emojis and visual improvements to documentation

### ⚡ Fast No-Debug (`fast-no-debug-example/`)

A minimal example that runs without `--debug` and verifies results via `cs exec`. Useful for quick smoke checks.

## Common Features

All examples demonstrate:
- Complete Git workflow with branch creation, commits, and automated PR creation
- GitHub integration using the `gh` CLI tool with ✅ emoji-prefixed PR titles
- Real-time workflow streaming
- Persistent sandbox management
- Individual agent files for better organization and maintainability

**Quick Start:**
```bash
# Multi-agent collaborative workflow
cd multi-agent-inventory-export
export GITHUB_TOKEN="your_token"
export ANTHROPIC_API_KEY="your_anthropic_api_key"
./run-example.sh

# Sequential subagent orchestration
cd secure-auth-pipeline
export GITHUB_TOKEN="your_token"
export ANTHROPIC_API_KEY="your_anthropic_api_key"
./run-example.sh
```

## Prerequisites

All examples require:
- Built `cs-cc` CLI (available at `../cs-cc`)
- `GITHUB_TOKEN` environment variable set with repo access permissions
- `ANTHROPIC_API_KEY` environment variable set with your Anthropic API key
- Access to target GitHub repositories

## Example Structure

Each example typically includes:
- `run-example.sh` - Main execution script
- `README.md` - Detailed documentation
- Configuration files (prompts, tool definitions, etc.)

## Agent File Structure

Each example now uses individual agent files in an `agents/` directory instead of a single `mcp-tools.json` file:

```
example-directory/
├── agents/
│   ├── agent1.json          # Individual agent definition
│   ├── agent2.json          # Another agent definition
│   └── agent3.json          # Third agent definition
├── orchestration-prompt.txt  # Main workflow prompt
├── tool-whitelist.json      # Available tools configuration
└── run-example.sh           # Execution script
```

**Agent File Format:**
```json
{
  "name": "agent_name",
  "description": "What this agent does and when to invoke it",
  "prompt": "System prompt defining the agent's role and instructions",
  "inputSchema": {
    "type": "object",
    "properties": {
      "parameter_name": {
        "type": "string",
        "description": "Parameter description"
      }
    },
    "required": ["parameter_name"]
  }
}
```

## Adding New Examples

When creating new examples:
1. Create a descriptive directory name
2. Create an `agents/` directory with individual agent JSON files
3. Include a comprehensive README
4. Provide all necessary configuration files
5. Make scripts executable (`chmod +x`)
6. Update this top-level README

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
   # For multi-agent collaborative workflow:
   cd multi-agent-inventory-export
   ./run-example.sh
   
   # For sequential subagent orchestration:
   cd secure-auth-pipeline
   ./run-example.sh
   ```

## Troubleshooting

- **Permission errors**: Ensure scripts are executable (`chmod +x script.sh`)
- **CLI not found**: Verify the CLI is built and path is correct
- **GitHub access**: Check token permissions and repository access
- **Anthropic API key issues**: Ensure your API key is valid and has sufficient credits
- **Sandbox issues**: Verify Crafting account and credentials

For example-specific issues, refer to the individual README files. 