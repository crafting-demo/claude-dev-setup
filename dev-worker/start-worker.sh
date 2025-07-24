#!/bin/bash

# Claude Code Worker Script
# This script executes Claude Code automation workflows
# Supports both issue creation and PR comment workflows

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

print_status "=== Claude Code Automation Workflow ==="

# Read prompt from cmd directory (cs-cc parameter system)
PROMPT_FILE="$HOME/cmd/prompt.txt"
print_status "Reading prompt from cs-cc parameter file: $PROMPT_FILE"

if [ ! -f "$PROMPT_FILE" ]; then
    print_error "Prompt file not found: $PROMPT_FILE"
    print_error "This should have been created by cs-cc CLI"
    exit 1
fi

CLAUDE_PROMPT=$(cat "$PROMPT_FILE")
if [ -z "$CLAUDE_PROMPT" ]; then
    print_error "Prompt file is empty: $PROMPT_FILE"
    exit 1
fi

print_status "Prompt loaded successfully (${#CLAUDE_PROMPT} characters)"
print_status "Prompt preview: $(echo "$CLAUDE_PROMPT" | head -c 100)..."

# Debug: Print environment variables (safely)
print_status "Environment variables from cs-cc CLI:"
echo "GITHUB_REPO: $GITHUB_REPO"
echo "GITHUB_TOKEN: $([ -n "$GITHUB_TOKEN" ] && echo "[set]" || echo "[empty]")"
echo "ACTION_TYPE: $ACTION_TYPE"
echo "PR_NUMBER: $PR_NUMBER"
echo "ISSUE_NUMBER: $ISSUE_NUMBER"
echo "GITHUB_BRANCH: $GITHUB_BRANCH"
echo "FILE_PATH: $FILE_PATH"
echo "LINE_NUMBER: $LINE_NUMBER"
echo "SHOULD_DELETE: $SHOULD_DELETE"
echo "SANDBOX_NAME: $SANDBOX_NAME"
echo "ANTHROPIC_API_KEY: $([ -n "$ANTHROPIC_API_KEY" ] && echo "[set]" || echo "[not set]")"

# Validate required environment variables
print_status "Validating environment variables..."

if [ -z "$GITHUB_REPO" ] || [ -z "$GITHUB_TOKEN" ] || [ -z "$ACTION_TYPE" ]; then
    print_error "Missing required environment variables"
    echo "Required: GITHUB_REPO, GITHUB_TOKEN, ACTION_TYPE"
    echo "Current values:"
    echo "GITHUB_REPO: '$GITHUB_REPO'"
    echo "GITHUB_TOKEN: '$([ -n "$GITHUB_TOKEN" ] && echo "[set]" || echo "[empty]")'"
    echo "ACTION_TYPE: '$ACTION_TYPE'"
    exit 1
fi

# Validate ANTHROPIC_API_KEY
if [ -z "$ANTHROPIC_API_KEY" ]; then
    print_error "ANTHROPIC_API_KEY not available"
    echo "Make sure to set your Anthropic API key before running this script"
    exit 1
fi

# Validate ACTION_TYPE and parameter relationships (cs-cc action types)
if [ "$ACTION_TYPE" = "pr" ] && [ -z "$PR_NUMBER" ]; then
    print_error "PR_NUMBER is required when ACTION_TYPE=pr"
    exit 1
fi

if [ "$ACTION_TYPE" = "issue" ] && [ -z "$ISSUE_NUMBER" ]; then
    print_error "ISSUE_NUMBER is required when ACTION_TYPE=issue"
    exit 1
fi

if [ "$ACTION_TYPE" = "branch" ] && [ -z "$GITHUB_BRANCH" ]; then
    print_error "GITHUB_BRANCH is required when ACTION_TYPE=branch"
    exit 1
fi

if [ "$ACTION_TYPE" = "pr" ] && [ -n "$FILE_PATH" ]; then
    print_status "PR context: $FILE_PATH:$LINE_NUMBER"
fi

if [ "$ACTION_TYPE" != "issue" ] && [ "$ACTION_TYPE" != "pr" ] && [ "$ACTION_TYPE" != "branch" ]; then
    print_error "ACTION_TYPE must be 'issue', 'pr', or 'branch'"
    exit 1
fi

print_success "Environment variables validated"

# Ensure PATH includes npm global binaries (Claude Code installation directory)
export PATH="$HOME/.npm-global/bin:$PATH"
print_status "Updated PATH to include Claude Code installation directory"

# Force logout to clear any previous authentication and re-authenticate with GITHUB_TOKEN
print_status "Resetting GitHub CLI authentication..."
set +e  # Temporarily disable exit on error
echo "y" | gh auth logout --hostname github.com >/dev/null 2>&1
logout_result=$?
set -e  # Re-enable exit on error
if [ $logout_result -eq 0 ]; then
    print_status "Previous GitHub CLI session logged out"
else
    print_status "No previous GitHub CLI session found (this is normal)"
fi

if [ -n "$GITHUB_TOKEN" ]; then
    print_status "Attempting to authenticate with GitHub CLI using token..."
    set +e  # Temporarily disable exit on error
    echo "$GITHUB_TOKEN" | gh auth login --with-token
    login_result=$?
    set -e  # Re-enable exit on error
    
    if [ $login_result -eq 0 ]; then
        print_success "GitHub CLI authenticated via provided GITHUB_TOKEN"
    else
        print_error "GitHub CLI authentication failed with exit code: $login_result"
        print_status "Checking if GITHUB_TOKEN environment variable authentication works..."
        
        # Test a simple gh command to see if env var auth works
        set +e
        gh auth status
        status_result=$?
        set -e
        
        if [ $status_result -eq 0 ]; then
            print_success "GitHub CLI authenticated via GITHUB_TOKEN environment variable"
        else
            print_error "GitHub CLI authentication completely failed"
            print_status "Token length: ${#GITHUB_TOKEN}"
            print_status "Token starts with: ${GITHUB_TOKEN:0:10}..."
            exit 1
        fi
    fi
else
    print_error "GITHUB_TOKEN is not set"
    exit 1
fi

# Check for required tools
print_status "Checking required tools..."

if ! command_exists gh; then
    print_error "GitHub CLI (gh) is not installed"
    echo "Please install GitHub CLI: https://cli.github.com/"
    exit 1
fi

if ! command_exists git; then
    print_error "Git is not installed"
    exit 1
fi

if ! command_exists claude; then
    print_error "Claude Code is not installed or not in PATH"
    echo "Please run setup-claude.sh first to install Claude Code"
    exit 1
fi

print_success "Required tools check passed"

# Start local MCP server if configured
print_status "Starting MCP server lifecycle management..."

# Function to start local MCP server
start_local_mcp_server() {
    local local_mcp_config="$HOME/cmd/local_mcp_tools.txt"
    local mcp_server_script="$HOME/claude/dev-worker/local_mcp_server/local-mcp-server.js"
    
    print_status "MCP Server startup - User: $(whoami), HOME: $HOME"
    
    if [ -f "$local_mcp_config" ] && [ -s "$local_mcp_config" ]; then
        print_status "Local MCP tools configuration found, starting local MCP server..."
        print_status "Config file: $local_mcp_config"
        print_status "Server script: $mcp_server_script"
        
        if [ ! -f "$mcp_server_script" ]; then
            print_error "Local MCP server script not found at $mcp_server_script"
            return 1
        fi
        
        # Ensure we're running as the owner user
        if [ "$(whoami)" != "owner" ]; then
            print_warning "Script not running as owner user, current user: $(whoami)"
            # Try to switch to owner user for MCP operations
            export HOME="/home/owner"
            local_mcp_config="/home/owner/cmd/local_mcp_tools.txt"
            mcp_server_script="/home/owner/claude/dev-worker/local_mcp_server/local-mcp-server.js"
            print_status "Adjusted paths - Config: $local_mcp_config, Script: $mcp_server_script"
        fi
        
        # Check if server is already running
        if pgrep -f "local-mcp-server.js" > /dev/null; then
            print_warning "Local MCP server already running, stopping previous instance"
            pkill -f "local-mcp-server.js" || true
            sleep 2
        fi
        
        # Ensure MCP server directory and dependencies are ready
        local mcp_server_dir="$(dirname "$mcp_server_script")"
        if [ ! -d "$mcp_server_dir/node_modules" ]; then
            print_status "Installing MCP server dependencies..."
            cd "$mcp_server_dir"
            npm install --silent || {
                print_error "Failed to install MCP server dependencies"
                return 1
            }
        fi
        
        # Start the MCP server in background
        print_status "Starting local MCP server at $mcp_server_script"
        cd "$mcp_server_dir"
        
        # Run as owner user if we're not already
        if [ "$(whoami)" = "owner" ]; then
            nohup node local-mcp-server.js > mcp-server.log 2>&1 &
        else
            nohup sudo -u owner node local-mcp-server.js > mcp-server.log 2>&1 &
        fi
        MCP_SERVER_PID=$!
        
        # Give the server a moment to start
        sleep 3
        
        # Verify the server started successfully
        if kill -0 $MCP_SERVER_PID 2>/dev/null; then
            print_success "Local MCP server started successfully (PID: $MCP_SERVER_PID)"
            echo $MCP_SERVER_PID > "$HOME/cmd/mcp_server.pid"
        else
            print_error "Failed to start local MCP server"
            print_status "Server logs:"
            tail -10 mcp-server.log 2>/dev/null || echo "No logs available"
            return 1
        fi
    else
        print_status "No local MCP tools configuration found, skipping local MCP server startup"
        print_status "Checked for: $local_mcp_config"
        if [ -f "$local_mcp_config" ]; then
            print_status "File exists but is empty ($(wc -c < "$local_mcp_config") bytes)"
        fi
    fi
}

# Function to setup cleanup trap for MCP server
setup_mcp_cleanup() {
    # Function to cleanup MCP server on exit
    cleanup_mcp_server() {
        if [ -f "$HOME/cmd/mcp_server.pid" ]; then
            local pid=$(cat "$HOME/cmd/mcp_server.pid")
            print_status "Cleaning up MCP server (PID: $pid)..."
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                sleep 2
                # Force kill if still running
                kill -9 "$pid" 2>/dev/null || true
            fi
            rm -f "$HOME/cmd/mcp_server.pid"
            print_success "MCP server cleanup completed"
        fi
    }
    
    # Set trap to cleanup on script exit
    trap cleanup_mcp_server EXIT
}

# Execute MCP server management
setup_mcp_cleanup
start_local_mcp_server

# Verify MCP configuration is ready
print_status "Verifying MCP configuration readiness..."
if [ -f "$HOME/cmd/external_mcp.txt" ]; then
    print_status "External MCP configuration available"
fi
if [ -f "$HOME/cmd/processed_tool_whitelist.txt" ]; then
    print_status "Tool whitelist configuration available"
    TOOL_COUNT=$(wc -l < "$HOME/cmd/processed_tool_whitelist.txt" 2>/dev/null || echo "0")
    print_status "Tools available: $TOOL_COUNT"
fi

print_success "MCP server lifecycle management completed"

# Configure GitHub CLI
print_status "Configuring GitHub CLI..."
if gh auth status >/dev/null 2>&1; then
    print_success "GitHub CLI already authenticated"
else
    # Try to authenticate, but don't fail if GITHUB_TOKEN env var is already in use
    if echo "$GITHUB_TOKEN" | gh auth login --with-token >/dev/null 2>&1; then
        print_success "GitHub CLI authenticated via token"
    elif [ -n "$GITHUB_TOKEN" ]; then
        # GITHUB_TOKEN is set, so authentication should work via env var
        print_success "GitHub CLI authenticated via GITHUB_TOKEN environment variable"
    else
        print_error "GitHub CLI authentication failed"
        exit 1
    fi
fi

# Setup workspace (using MCP-configured directory)
WORKSPACE_DIR="/home/owner/claude"
TARGET_REPO_DIR="$WORKSPACE_DIR/target-repo"

print_status "Setting up workspace in MCP-configured directory..."
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Remove existing target-repo if it exists
if [ -d "$TARGET_REPO_DIR" ]; then
    print_warning "Removing existing target-repo directory"
    rm -rf "$TARGET_REPO_DIR"
fi

# Configure Git to use the GitHub token for authentication in automated environments
print_status "Configuring Git authentication for automated environment..."
git config --global credential.helper store
git config --global user.name "Claude Code Automation"
git config --global user.email "automation@claudecode.dev"

# Set up Git credential store for this session
echo "https://github-token:${GITHUB_TOKEN}@github.com" > ~/.git-credentials

print_success "Git authentication configured"

# Clone the target repository
print_status "Cloning repository: $GITHUB_REPO"
gh repo clone "$GITHUB_REPO" target-repo
cd target-repo

print_success "Repository cloned successfully"

# Create .claude directory and settings.local.json for permissions
mkdir -p .claude
cat > .claude/settings.local.json << EOF
{
  "permissions": {
    "allow": [
      "Read",
      "Write",
      "Edit",
      "MultiEdit",
      "LS",
      "Glob",
      "Grep",
      "Bash",
      "Task",
      "TodoRead",
      "TodoWrite",
      "NotebookRead",
      "NotebookEdit",
      "WebFetch",
      "WebSearch"
    ],
    "deny": []
  }
}
EOF

# Branch management based on action type
if [ "$ACTION_TYPE" = "issue" ]; then
    print_status "Creating new branch for issue #$ISSUE_NUMBER workflow..."
    BRANCH_NAME="claude-issue-$ISSUE_NUMBER-$(date +%s)"
    git checkout -b "$BRANCH_NAME"
    print_success "Created new branch: $BRANCH_NAME"
    
elif [ "$ACTION_TYPE" = "pr" ]; then
    print_status "Checking out existing PR #$PR_NUMBER branch..."
    gh pr checkout "$PR_NUMBER"
    BRANCH_NAME=$(git branch --show-current)
    print_success "Checked out PR branch: $BRANCH_NAME"
    
elif [ "$ACTION_TYPE" = "branch" ]; then
    print_status "Checking out specified branch: $GITHUB_BRANCH"
    if git checkout "$GITHUB_BRANCH" 2>/dev/null; then
        print_success "Checked out existing branch: $GITHUB_BRANCH"
    elif git checkout -b "$GITHUB_BRANCH" 2>/dev/null; then
        print_success "Created and checked out new branch: $GITHUB_BRANCH"
    else
        print_error "Failed to checkout or create branch: $GITHUB_BRANCH"
        exit 1
    fi
    BRANCH_NAME="$GITHUB_BRANCH"
fi

# Prepend context to the prompt if available
FINAL_PROMPT="$CLAUDE_PROMPT"
if [ "$ACTION_TYPE" = "pr" ] && [ -n "$FILE_PATH" ]; then
    CONTEXT_HEADER="Working on PR #$PR_NUMBER, specifically \`$FILE_PATH\` at line \`$LINE_NUMBER\`."
    FINAL_PROMPT="$CONTEXT_HEADER\n\n$CLAUDE_PROMPT"
elif [ "$ACTION_TYPE" = "issue" ] && [ -n "$ISSUE_NUMBER" ]; then
    CONTEXT_HEADER="Working on issue #$ISSUE_NUMBER."
    FINAL_PROMPT="$CONTEXT_HEADER\n\n$CLAUDE_PROMPT"
elif [ "$ACTION_TYPE" = "branch" ] && [ -n "$GITHUB_BRANCH" ]; then
    CONTEXT_HEADER="Working on branch \`$GITHUB_BRANCH\`."
    FINAL_PROMPT="$CONTEXT_HEADER\n\n$CLAUDE_PROMPT"
fi

# Execute Claude Code with the provided prompt
print_status "Executing Claude Code..."
echo "Prompt: $FINAL_PROMPT"

# Debug: Check if CLAUDE_PROMPT is effectively empty
if [ -z "${FINAL_PROMPT// }" ]; then
    print_error "CLAUDE_PROMPT is empty or contains only whitespace"
    echo "Raw CLAUDE_PROMPT value: '$CLAUDE_PROMPT'"
    echo "Length: ${#CLAUDE_PROMPT}"
    exit 1
fi

print_status "CLAUDE_PROMPT validation passed (length: ${#FINAL_PROMPT})"

# PATH already exported earlier in script

# Test Claude Code with version first (non-interactive)
print_status "Testing Claude Code version command..."
if timeout 10 claude --version 2>&1; then
    print_success "Claude version command succeeded"
else
    print_error "Claude version command failed - this is bad"
    exit 1
fi

# Test Claude Code with a simple hello command  
print_status "Testing Claude Code with a simple command..."
if claude -p "Say hello" --verbose 2>&1; then
    print_success "Claude test command succeeded"
else
    EXIT_CODE=$?
    print_error "Claude test command failed with exit code: $EXIT_CODE"
    if [ $EXIT_CODE -eq 124 ]; then
        print_error "Command timed out - likely hanging on auth or input"
        print_error "Maybe Claude needs manual authentication first?"
    fi
    print_error "Trying claude config status to check auth..."
    timeout 10 claude config 2>&1 || print_error "Claude config also failed"
    exit 1
fi

# Run Claude Code
if claude -p "$FINAL_PROMPT" --verbose; then
    print_success "Claude Code execution completed"
else
    print_error "Claude Code execution failed"
    echo "Available commands in PATH:"
    which claude 2>/dev/null || echo "claude command not found"
    exit 1
fi

# Check if there are any changes (including untracked files, excluding .claude directory)
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard | grep -v '^\.claude/')" ]; then
    print_warning "No changes detected. Exiting."
    exit 0
fi

print_status "Changes detected, proceeding with commit and push..."

# Stage and commit changes (excluding .claude directory)
git add . ':!.claude'
COMMIT_MSG="Claude Code automation: $(echo "$FINAL_PROMPT" | head -c 50)..."
git commit -m "$COMMIT_MSG"
print_success "Changes committed"

# Push changes
print_status "Pushing changes to origin/$BRANCH_NAME..."

# Set up remote URL with token for this specific push if needed
REPO_URL_WITH_TOKEN="https://github-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"
git remote set-url origin "$REPO_URL_WITH_TOKEN"

if git push origin "$BRANCH_NAME"; then
    print_success "Changes pushed to remote"
else
    print_error "Failed to push changes"
    print_status "Attempting alternative push method..."
    
    # Try with explicit credentials
    if git push "https://github-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" "$BRANCH_NAME"; then
        print_success "Changes pushed to remote (alternative method)"
    else
        print_error "All push attempts failed"
        exit 1
    fi
fi

# Handle PR creation/update based on action type
if [ "$ACTION_TYPE" = "issue" ]; then
    print_status "Creating new pull request for issue #$ISSUE_NUMBER..."
    PR_TITLE="Fix issue #$ISSUE_NUMBER: $(echo "$FINAL_PROMPT" | head -c 40)..."
    
    # Create PR body
    cat > /tmp/pr_body.txt << EOF
This PR was automatically generated by Claude Code to address issue #$ISSUE_NUMBER.

## Issue addressed:
Fixes #$ISSUE_NUMBER

## Prompt executed:
\`\`\`
$FINAL_PROMPT
\`\`\`

## Changes made:
- Automated code changes based on the provided instructions
- Generated by Claude Code cs-cc automation system

## Review notes:
Please review the changes carefully before merging.
EOF
    
    gh pr create --title "$PR_TITLE" --body-file /tmp/pr_body.txt --base main --head "$BRANCH_NAME"
    print_success "Pull request created successfully!"
    
    # Clean up temp file
    rm -f /tmp/pr_body.txt
    
elif [ "$ACTION_TYPE" = "pr" ]; then
    print_status "Updating existing PR #$PR_NUMBER with new changes..."
    
    # Create comment body
    cat > /tmp/comment_body.txt << EOF
🤖 Claude Code automation has updated this PR with new changes.

## Prompt executed:
\`\`\`
$FINAL_PROMPT
\`\`\`

## Latest changes:
The code has been automatically updated based on the provided instructions using cs-cc automation.
EOF
    
    gh pr comment "$PR_NUMBER" --body-file /tmp/comment_body.txt
    print_success "PR comment added successfully!"
    
    # Clean up temp file
    rm -f /tmp/comment_body.txt
    
elif [ "$ACTION_TYPE" = "branch" ]; then
    print_status "Changes pushed to branch $GITHUB_BRANCH"
    print_status "You can create a PR manually or the changes are ready on the branch"
fi

print_success "=== Claude Code Automation Completed Successfully ==="

# Print summary
echo
print_status "Summary:"
echo "  Repository: $GITHUB_REPO"
echo "  Branch: $BRANCH_NAME"
echo "  Action Type: $ACTION_TYPE"
if [ "$ACTION_TYPE" = "pr" ]; then
    echo "  PR Number: $PR_NUMBER"
elif [ "$ACTION_TYPE" = "issue" ]; then
    echo "  Issue Number: $ISSUE_NUMBER"
elif [ "$ACTION_TYPE" = "branch" ]; then
    echo "  Target Branch: $GITHUB_BRANCH"
fi
echo "  Changes: Committed and pushed"
echo "  MCP Configuration: Applied from cs-cc parameters"
echo
print_success "🎉 Workflow completed successfully!"

# Cleanup logic based on SHOULD_DELETE environment variable
if [ "$SHOULD_DELETE" = "true" ]; then
    print_status "Non-debug mode: Initiating sandbox cleanup..."
    if [ -n "$SANDBOX_NAME" ]; then
        print_status "Deleting sandbox: $SANDBOX_NAME"
        if cs sandbox remove "$SANDBOX_NAME" --force; then
            print_success "Sandbox deleted successfully"
        else
            print_error "Failed to delete sandbox: $SANDBOX_NAME"
            # Don't exit with error - the main work is done
        fi
    else
        print_warning "SANDBOX_NAME not set, cannot delete sandbox"
    fi
else
    print_status "Debug mode: Keeping sandbox alive for debugging..."
    print_status "Sandbox name: $SANDBOX_NAME"
fi 