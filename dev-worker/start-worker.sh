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

# Read prompt from dev_prompt.txt file
PROMPT_FILE="/home/owner/claude-workspace/dev_prompt.txt"
print_status "Reading prompt from file: $PROMPT_FILE"

if [ ! -f "$PROMPT_FILE" ]; then
    print_error "Prompt file not found: $PROMPT_FILE"
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
print_status "Environment variables:"
echo "GITHUB_REPO: $GITHUB_REPO"
echo "GITHUB_TOKEN: $([ -n "$GITHUB_TOKEN" ] && echo "[set]" || echo "[empty]")"
echo "ACTION_TYPE: $ACTION_TYPE"
echo "PR_NUMBER: $PR_NUMBER"
echo "FILE_PATH: $FILE_PATH"
echo "LINE_NUMBER: $LINE_NUMBER"
echo "ANTHROPIC_API_KEY: $([ -n "$ANTHROPIC_API_KEY" ] && echo "[set]" || echo "[empty]")"

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

# Validate ACTION_TYPE and PR_NUMBER relationship
if [ "$ACTION_TYPE" = "pr_comment" ] && [ -z "$PR_NUMBER" ]; then
    print_error "PR_NUMBER is required when ACTION_TYPE=pr_comment"
    exit 1
fi

if [ "$ACTION_TYPE" = "pr_comment" ] && [ -n "$FILE_PATH" ]; then
    print_status "PR Comment context: $FILE_PATH:$LINE_NUMBER"
fi

if [ "$ACTION_TYPE" != "issue" ] && [ "$ACTION_TYPE" != "pr_comment" ]; then
    print_error "ACTION_TYPE must be 'issue' or 'pr_comment'"
    exit 1
fi

print_success "Environment variables validated"

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

# Setup workspace
WORKSPACE_DIR="/home/owner/claude/claude-workspace"
TARGET_REPO_DIR="$WORKSPACE_DIR/target-repo"

print_status "Setting up workspace..."
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
    print_status "Creating new branch for issue workflow..."
    BRANCH_NAME="claude-automation-$(date +%s)"
    git checkout -b "$BRANCH_NAME"
    print_success "Created new branch: $BRANCH_NAME"
    
elif [ "$ACTION_TYPE" = "pr_comment" ]; then
    print_status "Checking out existing PR branch..."
    gh pr checkout "$PR_NUMBER"
    BRANCH_NAME=$(git branch --show-current)
    print_success "Checked out PR branch: $BRANCH_NAME"
fi

# Prepend context to the prompt if available
FINAL_PROMPT="$CLAUDE_PROMPT"
if [ "$ACTION_TYPE" = "pr_comment" ] && [ -n "$FILE_PATH" ]; then
    CONTEXT_HEADER="The user has commented on \`$FILE_PATH\` at line \`$LINE_NUMBER\`."
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

# Ensure PATH includes npm global binaries (in case user didn't restart shell)
export PATH="$HOME/.npm-global/bin:$PATH"

# Test Claude Code with a simple hello command
print_status "Testing Claude Code with a simple command..."
claude -p "Say hello"

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
    print_status "Creating new pull request..."
    PR_TITLE="Claude Code: $(echo "$FINAL_PROMPT" | head -c 50)..."
    
    # Create PR body
    cat > /tmp/pr_body.txt << EOF
This PR was automatically generated by Claude Code.

## Prompt executed:
\`\`\`
$FINAL_PROMPT
\`\`\`

## Changes made:
- Automated code changes based on the provided instructions
- Generated by Claude Code automation system

## Review notes:
Please review the changes carefully before merging.
EOF
    
    gh pr create --title "$PR_TITLE" --body-file /tmp/pr_body.txt --base main --head "$BRANCH_NAME"
    print_success "Pull request created successfully!"
    
    # Clean up temp file
    rm -f /tmp/pr_body.txt
    
elif [ "$ACTION_TYPE" = "pr_comment" ]; then
    print_status "Updating existing PR #$PR_NUMBER..."
    
    # Sanitize the prompt for the comment to prevent feedback loops
    PROMPT_FOR_COMMENT=$(echo "$FINAL_PROMPT" | sed "s/$TRIGGER_PHRASE//g")

    # Create comment body
    cat > /tmp/comment_body.txt << EOF
🤖 Claude Code automation has updated this PR with new changes.

## Prompt executed:
\`\`\`
$PROMPT_FOR_COMMENT
\`\`\`

## Latest changes:
The code has been automatically updated based on the provided instructions.
EOF
    
    gh pr comment "$PR_NUMBER" --body-file /tmp/comment_body.txt
    print_success "PR comment added successfully!"
    
    # Clean up temp file
    rm -f /tmp/comment_body.txt
fi

print_success "=== Claude Code Automation Completed Successfully ==="

# Print summary
echo
print_status "Summary:"
echo "  Repository: $GITHUB_REPO"
echo "  Branch: $BRANCH_NAME"
echo "  Action Type: $ACTION_TYPE"
if [ "$ACTION_TYPE" = "pr_comment" ]; then
    echo "  PR Number: $PR_NUMBER"
fi
echo "  Changes: Committed and pushed"
echo
print_success "🎉 Workflow completed successfully!" 