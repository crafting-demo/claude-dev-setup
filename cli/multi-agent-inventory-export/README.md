# Multi-Agent Inventory Export Example

This example demonstrates a three-agent workflow using the `cs-cc` CLI to add a CSV export feature to a GitHub repository. It showcases how multiple AI agents can collaborate to implement, test, and document a feature.

## Overview

The workflow involves three specialized agents:

1. **Software Engineer** - Implements the core CSV export functionality
   - Creates `/api/export` endpoint returning sample CSV data
   - Adds "Export CSV" button to the main page

2. **QA Analyst** - Writes tests for the new feature
   - Tests that the export button exists
   - Validates the API endpoint returns CSV data

3. **Documentation Writer** - Updates project documentation
   - Adds a section to README about the CSV export feature
   - Documents usage instructions

## Files

- `run-example.sh` - Main script that executes the multi-agent workflow
- `orchestration-prompt.txt` - Coordination instructions for the agents
- `mcp-tools.json` - Configuration defining the three agent tools
- `tool-whitelist.json` - Allowed tools for the agents
- `README.md` - This documentation file

## Prerequisites

1. **Environment Setup**
   - `GITHUB_TOKEN` environment variable with repo access permissions
   - `ANTHROPIC_API_KEY` environment variable with your Anthropic API key
   - Built `cs-cc` CLI available at `../cs-cc`

2. **GitHub Repository**
   - Target repo: `crafting-test1/claude_test`
   - Ensure your GitHub token has access to this repository

## Usage

1. **Set your authentication:**
   ```bash
   export GITHUB_TOKEN="your_github_personal_access_token"
   export ANTHROPIC_API_KEY="your_anthropic_api_key"
   ```

2. **Run the example:**
   ```bash
   cd claude-dev-setup/cli/multi-agent-inventory-export
   ./run-example.sh
   ```

3. **Monitor the workflow:**
   - The script runs in debug mode with real-time streaming
   - You'll see each agent's work as it happens
   - A persistent sandbox is created for inspection

4. **Check the results:**
   - Visit the GitHub repository to see the created pull request
   - The PR will contain the implemented feature, tests, and documentation

## What Happens

1. **Validation** - Script checks for required files and environment variables
2. **Agent Orchestration** - Launches three specialized AI agents in sequence
3. **Implementation** - Software engineer creates the CSV export feature
4. **Testing** - QA analyst writes automated tests
5. **Documentation** - Technical writer updates the README
6. **GitHub Integration** - Changes are committed and a PR is created

## Configuration

### Customizing the Workflow

- **Target Repository**: Edit `REPO` variable in `run-example.sh`
- **Agent Behavior**: Modify the prompts in `mcp-tools.json`
- **Orchestration**: Update instructions in `orchestration-prompt.txt`
- **Available Tools**: Adjust the whitelist in `tool-whitelist.json`

### Tool Whitelist

The agents have access to these tools:
- **MCP Agents**: `local_server___software_engineer`, `local_server___qa_analyst`, `local_server___documentation_writer`
- **File Operations**: `Read`, `Write`, `Edit`, `LS`, `Grep`
- **System Tools**: `Bash`, `Task`

## Cleanup

After running the example:

1. **Inspect the sandbox** (optional):
   ```bash
   cs ssh <sandbox-name>
   ```

2. **Delete the sandbox**:
   ```bash
   cs sandbox delete <sandbox-name> --force
   ```

The sandbox name is displayed in the script output.

## Troubleshooting

- **CLI not found**: Ensure `cs-cc` is built and available at the expected path
- **GitHub token issues**: Verify token has repo permissions and is correctly set
- **Anthropic API key issues**: Ensure your API key is valid and has sufficient credits
- **Agent failures**: Check the sandbox logs for detailed error information

## Expected Output

On success, you should see:
- Real-time streaming of agent activities
- A new pull request in the target repository
- Implemented CSV export feature with tests and documentation
- Success message with sandbox and cleanup instructions 