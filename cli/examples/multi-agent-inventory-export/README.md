# Multi-Agent Inventory Export Example

This example demonstrates a three-agent workflow using the `cs-cc` CLI to add a CSV export feature to a GitHub repository. It showcases how multiple AI agents can collaborate to implement, test, and document a feature.

## Overview

The workflow involves three specialized agents that use **dynamic inputs** to build upon each other's work:

1. **Software Engineer** - Implements features based on task descriptions
   - Receives detailed task requirements as input
   - Creates API endpoints and UI components accordingly
   - Outputs implementation details for next agent

2. **QA Analyst** - Writes tests based on implementation details
   - Receives implementation notes from the software engineer
   - Creates comprehensive tests that match the actual implementation
   - Validates both UI and API functionality

3. **Documentation Writer** - Updates documentation based on feature details
   - Receives comprehensive feature summary from previous agents
   - Documents actual functionality and usage patterns
   - Creates user-friendly documentation

## Files

- `run-example.sh` - Main script that executes the multi-agent workflow
- `orchestration-prompt.txt` - Coordination instructions for the agents
- `agents/` - Directory containing individual agent definitions:
  - `front_end_engineer.json` - UI implementation agent
  - `back_end_engineer.json` - API and server-side logic agent
  - `documentation_writer.json` - Documentation creation agent
- `tool-whitelist.json` - Allowed tools for the agents
- `README.md` - This documentation file

## Prerequisites

1. **Environment Setup**
   - `GITHUB_TOKEN` environment variable with repo access permissions
   - `ANTHROPIC_API_KEY` environment variable with your Anthropic API key
   - Built `cs-cc` CLI available at `../../cs-cc`

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
   cd claude-dev-setup/cli/examples/multi-agent-inventory-export
   ./run-example.sh
   ```

3. **Monitor the workflow:**
   - The script runs in debug mode with real-time streaming
   - You'll see each agent's work as it happens
   - A persistent sandbox is created for inspection

4. **Check the results:**
   - Visit the GitHub repository to see the created pull request (title will start with ✅ emoji)
   - The PR will contain the implemented feature, tests, and documentation on a new feature branch

## What Happens

1. **Validation** - Script checks for required files and environment variables
2. **Agent Orchestration** - Launches three specialized AI agents with dynamic inputs
3. **Implementation** - Software engineer receives detailed task description and implements feature
4. **Testing** - QA analyst receives implementation details and writes matching tests
5. **Documentation** - Technical writer receives feature summary and creates comprehensive docs
6. **Git Workflow** - Creates new branch, commits all changes, pushes to remote
7. **GitHub Integration** - Uses `gh` CLI tool to create PR with ✅ emoji-prefixed title

### Dynamic Input Flow

- **Step 1**: Software Engineer gets specific task requirements
- **Step 2**: QA Analyst gets implementation details from Step 1's output  
- **Step 3**: Documentation Writer gets comprehensive feature details from both previous steps

This demonstrates true multi-agent collaboration where each agent's work informs the next.

## Configuration

### Customizing the Workflow

- **Target Repository**: Edit `REPO` variable in `run-example.sh`
- **Agent Behavior**: Modify the individual agent files in `agents/` directory
- **Orchestration**: Update instructions in `orchestration-prompt.txt`
- **Available Tools**: Adjust the whitelist in `tool-whitelist.json`

### Tool Whitelist

The agents have access to these tools:
- **MCP Agents**: `local_server___front_end_engineer`, `local_server___back_end_engineer`, `local_server___documentation_writer`
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
- Complete Git workflow execution (branch creation, commits, push)
- A new pull request in the target repository with ✅ emoji-prefixed title
- Implemented CSV export feature with tests and documentation
- Success message with sandbox and cleanup instructions 