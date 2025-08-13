#!/bin/bash

# Claude Code Worker Script
# This script executes Claude Code automation workflows
# Supports both issue creation and PR comment workflows

set -e  # Exit on any error

# Function to print output without colors
print_status() {
    echo "[INFO] $1" >&2
}

print_success() {
    echo "[SUCCESS] $1" >&2
}

print_warning() {
    echo "[WARNING] $1" >&2
}

print_error() {
    echo "[ERROR] $1" >&2
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}





# Function to detect and report project-level subagents in .claude/agents/ directory
detect_project_subagents() {
    local project_agents_dir=".claude/agents"
    
    print_status "Checking for project-level subagents..."
    
    # Check if .claude/agents directory exists in current repo
    if [ ! -d "$project_agents_dir" ]; then
        print_status "No .claude/agents directory found in repository"
        return 0
    fi
    
    # Find .md agent files in the .claude/agents directory
    local agent_files=$(find "$project_agents_dir" -name "*.md" -type f 2>/dev/null)
    
    if [ -z "$agent_files" ]; then
        print_status "No .md agent files found in .claude/agents directory"
        return 0
    fi
    
    local agent_count=$(echo "$agent_files" | wc -l)
    print_success "Found $agent_count project agent files in .claude/agents/"
    print_status "Project agents:"
    while IFS= read -r agent_file; do
        local agent_name=$(basename "$agent_file" .md)
        print_status "  - $agent_name"
    done <<< "$agent_files"
    print_status "Project agents will override user agents with same names"
    
    return 0
}



print_status "=== Claude Code Automation Workflow ==="

# Prefer Go worker path when enabled; fallback to shell workflow on failure
if [ "${USE_GO_WORKER:-true}" = "true" ]; then
    # Ensure Go toolchain
    if [ -f "$SCRIPT_DIR/setup-go.sh" ]; then
        print_status "Ensuring Go toolchain is available..."
        bash "$SCRIPT_DIR/setup-go.sh"
    fi
    if command -v go >/dev/null 2>&1; then
        if [ -d "$HOME/claude" ]; then
            print_status "Attempting Go worker path..."
            if (cd "$HOME/claude" && go run ./cmd/worker); then
                print_success "Go worker completed"
                exit 0
            else
                print_warning "Go worker failed; falling back to shell path"
            fi
        fi
    fi
fi

# Step 1: Determine task mode as early as possible so we can pivot setup behavior
# Load TASK_MODE from /home/owner/cmd/task_mode.txt if not already set
if [ -z "${TASK_MODE:-}" ]; then
    if [ -f "$HOME/cmd/task_mode.txt" ]; then
        TASK_MODE=$(tr -d '\r' < "$HOME/cmd/task_mode.txt" | tr -d ' \t')
    fi
fi
if [ -z "${TASK_MODE:-}" ]; then
    TASK_MODE="create"
fi

# Step 2: Setup Claude Code (skip initial MCP config until after agent aggregation)
print_status "Setting up Claude Code environment..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip Claude Code setup in resume mode (already installed)
if [ "$TASK_MODE" = "resume" ]; then
    print_status "Resume mode: Skipping Claude Code setup (already installed)"
    # Ensure PATH includes Claude Code
    export PATH="$HOME/.npm-global/bin:$PATH"
    print_status "PATH confirmed: $PATH"
elif [ -f "$SCRIPT_DIR/setup-claude.sh" ]; then
    print_status "Sourcing setup-claude.sh to configure Claude Code (MCP config deferred)..."
    export SKIP_INITIAL_MCP_CONFIG="true"
    source "$SCRIPT_DIR/setup-claude.sh"
    print_success "Claude Code setup completed (MCP config will happen after agent aggregation)"
    
    # Ensure PATH includes Claude Code after installation
    export PATH="$HOME/.npm-global/bin:$PATH"
    print_status "PATH confirmed: $PATH"
else
    print_error "setup-claude.sh not found in $SCRIPT_DIR"
    exit 1
fi

# -----------------------------------------------------------------------------------
# Ensure the dev-worker code is up-to-date with the latest commit from the repository
# -----------------------------------------------------------------------------------
print_status "Checking for newer commits in dev-worker repository..."
set +e  # Don't abort workflow if update fails
cd /home/owner/claude || true
# Mark repo as safe for Git >=2.35+ ownership checks
git config --global --add safe.directory /home/owner/claude 2>/dev/null || true
CURRENT_COMMIT=$(git rev-parse --verify HEAD 2>/dev/null)
git fetch --quiet origin || true
git pull --quiet --rebase --autostash origin "$(git rev-parse --abbrev-ref HEAD)" || true
UPDATED_COMMIT=$(git rev-parse --verify HEAD 2>/dev/null)
if [ "$CURRENT_COMMIT" != "$UPDATED_COMMIT" ]; then
    print_success "Dev-worker repository updated: $CURRENT_COMMIT → $UPDATED_COMMIT"
else
    print_status "Dev-worker repository already up-to-date ($CURRENT_COMMIT)"
fi
cd "$SCRIPT_DIR" || true
set -e

# Initialize task management system
print_status "=== Task Management System Initialization ==="

# Load task management state from cs-cc parameters
TASK_MODE="create"  # Default mode
CUSTOM_TASK_ID=""
PROMPT_FILENAME="prompt.txt"  # Default filename

if [ -f "$HOME/cmd/task_mode.txt" ]; then
    TASK_MODE=$(cat "$HOME/cmd/task_mode.txt" 2>/dev/null || echo "create")
    print_status "Task mode: $TASK_MODE"
    if [ "$DEBUG_MODE" = "true" ]; then
        print_status "[DEBUG] Task mode loaded from file: $HOME/cmd/task_mode.txt"
    fi
fi

if [ -f "$HOME/cmd/task_id.txt" ]; then
    CUSTOM_TASK_ID=$(cat "$HOME/cmd/task_id.txt" 2>/dev/null || echo "")
    print_status "Custom task ID: $CUSTOM_TASK_ID"
    if [ "$DEBUG_MODE" = "true" ]; then
        print_status "[DEBUG] Custom task ID loaded from file: $HOME/cmd/task_id.txt"
    fi
fi

if [ -f "$HOME/cmd/prompt_filename.txt" ]; then
    PROMPT_FILENAME=$(cat "$HOME/cmd/prompt_filename.txt" 2>/dev/null || echo "prompt.txt")
    print_status "Prompt filename: $PROMPT_FILENAME"
    if [ "$DEBUG_MODE" = "true" ]; then
        print_status "[DEBUG] Prompt filename loaded from file: $HOME/cmd/prompt_filename.txt"
    fi
fi

if [ "$DEBUG_MODE" = "true" ]; then
    print_status "[DEBUG] Task Management State:"
    print_status "[DEBUG]   TASK_MODE: $TASK_MODE"
    print_status "[DEBUG]   CUSTOM_TASK_ID: $CUSTOM_TASK_ID"
    print_status "[DEBUG]   PROMPT_FILENAME: $PROMPT_FILENAME"
    print_status "[DEBUG]   Available cmd files: $(ls -la $HOME/cmd/ 2>/dev/null | wc -l) files"
fi

# Initialize task state manager
"$SCRIPT_DIR/task-state-manager.sh" init >/dev/null 2>&1 || print_warning "Failed to initialize task state manager"

# Handle task creation or queuing based on mode
if [ "$TASK_MODE" = "create" ]; then
    print_status "Creating initial task..."
    
    # Read prompt from original file for task creation
    INITIAL_PROMPT_FILE="$HOME/cmd/prompt.txt"
    if [ -f "$INITIAL_PROMPT_FILE" ]; then
        TOOL_WHITELIST_FILE=""
        if [ -f "$HOME/cmd/tool_whitelist.txt" ]; then
            TOOL_WHITELIST_FILE="tool_whitelist.txt"
        fi
        
        TASK_ID=$("$SCRIPT_DIR/task-state-manager.sh" create "$INITIAL_PROMPT_FILE" "$TOOL_WHITELIST_FILE" "$CUSTOM_TASK_ID" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$TASK_ID" ]; then
            print_success "Created task: $TASK_ID"
            export CURRENT_TASK_ID="$TASK_ID"
        else
            print_warning "Failed to create task in state manager, continuing with legacy mode"
        fi
    fi
    
elif [ "$TASK_MODE" = "resume" ]; then
    print_status "Resume mode: Adding new task to queue..."
    
    # Handle new task file (prompt_new.txt becomes prompt_N.txt)
    NEW_PROMPT_FILE="$HOME/cmd/prompt_new.txt"
    if [ -f "$NEW_PROMPT_FILE" ]; then
        # Generate next task number
        NEXT_TASK_NUM=1
        while [ -f "$HOME/cmd/prompt_${NEXT_TASK_NUM}.txt" ]; do
            NEXT_TASK_NUM=$((NEXT_TASK_NUM + 1))
        done
        
        # Move new prompt to numbered file
        mv "$NEW_PROMPT_FILE" "$HOME/cmd/prompt_${NEXT_TASK_NUM}.txt"
        print_status "Moved new prompt to: prompt_${NEXT_TASK_NUM}.txt"
        
        # Create task in queue
        TOOL_WHITELIST_FILE=""
        if [ -f "$HOME/cmd/tool_whitelist.txt" ]; then
            TOOL_WHITELIST_FILE="tool_whitelist.txt"
        fi
        
        TASK_ID=$("$SCRIPT_DIR/task-state-manager.sh" create "$HOME/cmd/prompt_${NEXT_TASK_NUM}.txt" "$TOOL_WHITELIST_FILE" "$CUSTOM_TASK_ID" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$TASK_ID" ]; then
            print_success "Queued new task: $TASK_ID"
        else
            print_warning "Failed to queue new task"
        fi
    fi
    
    # Check if there's a task currently in progress or get next pending task
    CURRENT_TASK=$("$SCRIPT_DIR/task-state-manager.sh" current 2>/dev/null)
    if [ "$CURRENT_TASK" = "null" ] || [ -z "$CURRENT_TASK" ]; then
        print_status "No task in progress, checking for pending tasks..."
        NEXT_TASK=$("$SCRIPT_DIR/task-state-manager.sh" next 2>/dev/null)
        if [ "$NEXT_TASK" != "null" ] && [ -n "$NEXT_TASK" ]; then
            # Start the next pending task
            TASK_ID=$(echo "$NEXT_TASK" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null)
            if [ -n "$TASK_ID" ]; then
                print_status "Starting next pending task: $TASK_ID"
                "$SCRIPT_DIR/task-state-manager.sh" update "$TASK_ID" "in_progress" >/dev/null 2>&1 || true
                export CURRENT_TASK_ID="$TASK_ID"
                
                # Update prompt file based on task
                TASK_PROMPT_FILE=$(echo "$NEXT_TASK" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('promptFile', 'prompt.txt'))" 2>/dev/null)
                if [ -f "$TASK_PROMPT_FILE" ]; then
                    PROMPT_FILENAME=$(basename "$TASK_PROMPT_FILE")
                    print_status "Using task prompt file: $PROMPT_FILENAME"
                fi
            fi
        else
            print_status "No pending tasks found"
        fi
    else
        print_status "Resuming existing task in progress..."
        TASK_ID=$(echo "$CURRENT_TASK" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null)
        export CURRENT_TASK_ID="$TASK_ID"
        
        # Get the prompt file for the current task
        TASK_PROMPT_FILE=$(echo "$CURRENT_TASK" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('promptFile', 'prompt.txt'))" 2>/dev/null)
        if [ -f "$TASK_PROMPT_FILE" ]; then
            PROMPT_FILENAME=$(basename "$TASK_PROMPT_FILE")
            print_status "Resuming with prompt file: $PROMPT_FILENAME"
        fi
    fi
fi

# Print task queue status
"$SCRIPT_DIR/task-state-manager.sh" status 2>/dev/null || print_warning "Could not read task queue status"

print_status "=== Task Management Initialization Complete ==="

# Read prompt from determined file (cs-cc parameter system)
PROMPT_FILE="$HOME/cmd/$PROMPT_FILENAME"
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

# BEGIN REINTRODUCED SECTION — Load env vars from cs-cc parameter files when not present
if [ -z "$GITHUB_REPO" ] && [ -f "$HOME/cmd/github_repo.txt" ]; then
    export GITHUB_REPO=$(cat "$HOME/cmd/github_repo.txt" 2>/dev/null || echo "")
fi

if [ -z "$GITHUB_TOKEN" ] && [ -f "$HOME/cmd/github_token.txt" ]; then
    export GITHUB_TOKEN=$(cat "$HOME/cmd/github_token.txt" 2>/dev/null || echo "")
fi

if [ -z "$GITHUB_BRANCH" ] && [ -f "$HOME/cmd/github_branch.txt" ]; then
    export GITHUB_BRANCH=$(cat "$HOME/cmd/github_branch.txt" 2>/dev/null || echo "main")
fi

# Note: User agents are now processed by cs-cc and transferred to ~/.claude/agents/
# Project agents are detected in the repository's .claude/agents/ directory

# END REINTRODUCED SECTION

# Debug: Print environment variables (safely)
print_status "Environment variables from cs-cc CLI:"
echo "GITHUB_REPO: $GITHUB_REPO" >&2
echo "GITHUB_TOKEN: $([ -n "$GITHUB_TOKEN" ] && echo "[set]" || echo "[empty]")" >&2
echo "ACTION_TYPE: $ACTION_TYPE" >&2
echo "PR_NUMBER: $PR_NUMBER" >&2
echo "ISSUE_NUMBER: $ISSUE_NUMBER" >&2
echo "GITHUB_BRANCH: $GITHUB_BRANCH" >&2
echo "FILE_PATH: $FILE_PATH" >&2
echo "LINE_NUMBER: $LINE_NUMBER" >&2
echo "SHOULD_DELETE: $SHOULD_DELETE" >&2
echo "SANDBOX_NAME: $SANDBOX_NAME" >&2
echo "CUSTOM_REPO_PATH: $CUSTOM_REPO_PATH" >&2
echo "AGENTS: $([ -d "$HOME/.claude/agents" ] && echo "[user agents in ~/.claude/agents]" || echo "[none]")" >&2
echo "ANTHROPIC_API_KEY: $([ -n "$ANTHROPIC_API_KEY" ] && echo "[set]" || echo "[not set]")" >&2

# Validate required environment variables
print_status "Validating environment variables..."

if [ -z "$GITHUB_REPO" ]; then
    print_error "Missing required environment variables"
    echo "Required: GITHUB_REPO" >&2
    echo "Current values:" >&2
    echo "GITHUB_REPO: '$GITHUB_REPO'" >&2
    echo "GITHUB_TOKEN: '$([ -n "$GITHUB_TOKEN" ] && echo "[set]" || echo "[empty]")' (optional, will use Crafting credentials if not provided)" >&2
    echo "ACTION_TYPE: '$ACTION_TYPE' (optional)" >&2
    exit 1
fi

# Validate ANTHROPIC_API_KEY
if [ -z "$ANTHROPIC_API_KEY" ]; then
    print_error "ANTHROPIC_API_KEY not available"
    echo "Make sure to set your Anthropic API key before running this script"
    exit 1
fi

# Validate ACTION_TYPE (optional context about task source)
if [ -n "$ACTION_TYPE" ]; then
    if [ "$ACTION_TYPE" != "issue" ] && [ "$ACTION_TYPE" != "pr" ] && [ "$ACTION_TYPE" != "branch" ]; then
        print_error "ACTION_TYPE must be 'issue', 'pr', or 'branch' (or omitted)"
        exit 1
    fi
    
    # Log context information when available
    if [ "$ACTION_TYPE" = "pr" ] && [ -n "$PR_NUMBER" ]; then
        print_status "PR context: #$PR_NUMBER"
        if [ -n "$FILE_PATH" ]; then
            print_status "File context: $FILE_PATH:$LINE_NUMBER"
        fi
    elif [ "$ACTION_TYPE" = "issue" ] && [ -n "$ISSUE_NUMBER" ]; then
        print_status "Issue context: #$ISSUE_NUMBER"
    elif [ "$ACTION_TYPE" = "branch" ] && [ -n "$GITHUB_BRANCH" ]; then
        print_status "Branch context: $GITHUB_BRANCH"
    fi
fi

print_success "Environment variables validated"

# Ensure PATH includes npm global binaries (Claude Code installation directory)
export PATH="$HOME/.npm-global/bin:$PATH"
print_status "Updated PATH to include Claude Code installation directory"

# Function to get GitHub token from Crafting credentials
get_crafting_github_token() {
    local repo_path="$1"
    
    print_status "Attempting to retrieve GitHub token from Crafting credentials..."
    print_status "Repository path: $repo_path"
    
    # Use wsenv git-credentials to get token
    local token
    token=$(echo -e "protocol=https\nhost=github.com\npath=${repo_path}" \
            | /opt/sandboxd/sbin/wsenv git-credentials \
            | awk -F= '/^password=/{print $2}')
    
    if [ -n "$token" ]; then
        print_success "Retrieved GitHub token from Crafting credentials"
        echo "$token"
        return 0
    else
        print_error "Failed to retrieve GitHub token from Crafting credentials"
        return 1
    fi
}

# Force logout to clear any previous authentication and re-authenticate
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

# Determine GitHub token source and authenticate
if [ -n "$GITHUB_TOKEN" ]; then
    print_status "Using explicitly provided GitHub token..."
    auth_token="$GITHUB_TOKEN"
    token_source="explicit"
else
    print_status "No GitHub token provided, attempting to use Crafting credentials..."
    
    # Extract repository path from GITHUB_REPO for Crafting credentials
    if [ -n "$GITHUB_REPO" ]; then
        repo_path="$GITHUB_REPO"
        print_status "Extracting repository path from GITHUB_REPO: $repo_path"
        
        # Get token from Crafting credentials
        set +e  # Don't exit on error during credential retrieval
        auth_token=$(get_crafting_github_token "$repo_path")
        credential_result=$?
        set -e
        
        if [ $credential_result -eq 0 ] && [ -n "$auth_token" ]; then
            print_success "Successfully retrieved token from Crafting credentials"
            token_source="crafting"
        else
            print_error "Failed to retrieve token from Crafting credentials"
            print_error "Both explicit token and Crafting credentials failed"
            exit 1
        fi
    else
        print_error "GITHUB_REPO not set - cannot determine repository for Crafting credentials"
        exit 1
    fi
fi

# Authenticate with GitHub CLI using the obtained token
print_status "Authenticating with GitHub CLI using $token_source token..."
set +e  # Temporarily disable exit on error
echo "$auth_token" | gh auth login --with-token
login_result=$?
set -e  # Re-enable exit on error

if [ $login_result -eq 0 ]; then
    print_success "GitHub CLI authenticated successfully via $token_source token"
else
    print_error "GitHub CLI authentication failed with exit code: $login_result"
    print_status "Checking if token works via environment variable authentication..."
    
    # Test a simple gh command to see if env var auth works
    set +e
    GITHUB_TOKEN="$auth_token" gh auth status
    status_result=$?
    set -e
    
    if [ $status_result -eq 0 ]; then
        print_success "GitHub CLI authenticated via $token_source token environment variable"
        # Export the token for subsequent commands
        export GITHUB_TOKEN="$auth_token"
    else
        print_error "GitHub CLI authentication completely failed"
        print_status "Token source: $token_source"
        print_status "Token length: ${#auth_token}"
        print_status "Token starts with: ${auth_token:0:10}..."
        exit 1
    fi
fi

# Configure git to use GitHub CLI credentials for push operations
print_status "Configuring git to use GitHub CLI credentials..."
set +e  # Temporarily disable exit on error
gh auth setup-git
setup_git_result=$?
set -e  # Re-enable exit on error

if [ $setup_git_result -eq 0 ]; then
    print_success "Git configured to use GitHub CLI credentials for push operations"
else
    print_warning "Failed to configure git credentials (exit code: $setup_git_result), git push operations may fail"
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
    print_error "Claude Code is not installed or not in PATH after setup"
    print_error "Setup may have failed - check setup-claude.sh output above"
    exit 1
fi

print_success "Required tools check passed"

# Native subagent system - no additional setup needed
print_status "Native subagent system active - ready for user and project agents"

# Function to parse stream-json output from Claude
parse_claude_stream_json() {
    # Associative array to store tool call details for correlation (bash 4.0+)
    declare -A tool_calls
    
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue
        
        # Extract event type using jq if available, fallback to basic parsing
        if command -v jq >/dev/null 2>&1; then
            event_type=$(echo "$line" | jq -r '.type // "unknown"' 2>/dev/null)
            subtype=$(echo "$line" | jq -r '.subtype // ""' 2>/dev/null)
        else
            # Fallback parsing without jq
            event_type=$(echo "$line" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')
            subtype=$(echo "$line" | sed -n 's/.*"subtype":"\([^"]*\)".*/\1/p')
        fi
        
        # Route events based on type
        case "$event_type" in
            "system")
                if [ "$subtype" = "init" ]; then
                    if command -v jq >/dev/null 2>&1; then
                        session_id=$(echo "$line" | jq -r '.session_id // "unknown"')
                        model=$(echo "$line" | jq -r '.model // "unknown"')
                        subagent_count=$(echo "$line" | jq -r '.subagents | length // 0')
                    else
                        session_id="unknown"
                        model="unknown"
                        subagent_count="unknown"
                    fi
                    print_status "🔧 Claude session initialized (ID: ${session_id:0:8}..., Model: $model, Subagents: $subagent_count)"
                    
                    # Persist session information for task resumption
                    if [ "$session_id" != "unknown" ] && [ "$session_id" != "null" ]; then
                        local session_file="$HOME/session.json"
                        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                        
                        print_status "Persisting session information to $session_file"
                        cat > "$session_file" << EOF
{
  "sessionId": "$session_id",
  "model": "$model",
                    "subagentCount": $subagent_count,
  "created": "$timestamp",
  "lastActive": "$timestamp",
  "status": "active"
}
EOF
                        
                        # Update current task with session ID if we have one
                        if [ -f "$HOME/cmd/task_mode.txt" ]; then
                            local task_mode=$(cat "$HOME/cmd/task_mode.txt" 2>/dev/null || echo "")
                            if [ "$task_mode" = "create" ] || [ "$task_mode" = "resume" ]; then
                                # Get current task ID from task state manager
                                local current_task=$("$SCRIPT_DIR/task-state-manager.sh" current 2>/dev/null)
                                if [ "$current_task" != "null" ] && [ -n "$current_task" ]; then
                                    local task_id=$(echo "$current_task" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null)
                                    if [ -n "$task_id" ]; then
                                        print_status "Updating task $task_id with session ID: $session_id"
                                        "$SCRIPT_DIR/task-state-manager.sh" update "$task_id" "in_progress" "$session_id" >/dev/null 2>&1 || true
                                    fi
                                fi
                            fi
                        fi
                    fi
                fi
                ;;
            "assistant")
                # Check if this contains a tool use
                if echo "$line" | grep -q '"tool_use"'; then
                    if command -v jq >/dev/null 2>&1; then
                        tool_name=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_use") | .name // "unknown"' 2>/dev/null)
                        tool_id=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_use") | .id // "unknown"' 2>/dev/null)
                        tool_input=$(echo "$line" | jq -c '.message.content[]? | select(.type == "tool_use") | .input // {}' 2>/dev/null)
                        
                        if [ -n "$tool_name" ] && [ "$tool_name" != "null" ] && [ "$tool_name" != "unknown" ]; then
                            # Store tool call details for correlation with results
                            tool_calls["$tool_id"]="$tool_name"
                            
                            # Format tool call message with input details
                            # All tools are now native - subagents are handled transparently
                            tool_prefix="[TOOL]"
                            
                            # Special handling for common tools to show relevant parameters
                            case "$tool_name" in
                                "Bash")
                                    # Extract command from Bash tool input
                                    bash_command=$(echo "$tool_input" | jq -r '.command // ""' 2>/dev/null)
                                    if [ -n "$bash_command" ] && [ "$bash_command" != "null" ] && [ "$bash_command" != "" ]; then
                                        print_status "$tool_prefix 🔧 Calling Bash: $bash_command"
                                    else
                                        print_status "$tool_prefix 🔧 Calling: $tool_name"
                                    fi
                                    ;;
                                "Read"|"Write"|"Edit"|"MultiEdit")
                                    # Extract file_path for file operations
                                    file_path=$(echo "$tool_input" | jq -r '.file_path // ""' 2>/dev/null)
                                    if [ -n "$file_path" ] && [ "$file_path" != "null" ] && [ "$file_path" != "" ]; then
                                        print_status "$tool_prefix 🔧 Calling $tool_name: $file_path"
                                    else
                                        print_status "$tool_prefix 🔧 Calling: $tool_name"
                                    fi
                                    ;;
                                *)
                                    # For other tools, show tool name and condensed input if available
                                    if [ "$tool_input" != "{}" ] && [ -n "$tool_input" ]; then
                                        # Show first key-value pair or truncated input in debug mode
                                        if [ "$DEBUG_MODE" = "true" ]; then
                                            print_status "$tool_prefix 🔧 Calling $tool_name with: $tool_input"
                                        else
                                            print_status "$tool_prefix 🔧 Calling: $tool_name"
                                        fi
                                    else
                                        print_status "$tool_prefix 🔧 Calling: $tool_name"
                                    fi
                                    ;;
                            esac
                        fi
                    else
                        print_status "[TOOL] 🔧 Tool call initiated"
                    fi
                elif echo "$line" | grep -q '"text"'; then
                    # This is a regular text response - show meaningful content
                    if command -v jq >/dev/null 2>&1; then
                        text_content=$(echo "$line" | jq -r '.message.content[]? | select(.type == "text") | .text // ""' 2>/dev/null)
                        if [ -n "$text_content" ] && [ "$text_content" != "null" ]; then
                            # In debug mode, show more content; in normal mode, show reasonable preview
                            if [ "$DEBUG_MODE" = "true" ]; then
                                # Debug mode: show more content with length indicator
                                if [ ${#text_content} -gt 500 ]; then
                                    print_status "[CLAUDE] ${text_content:0:500}... (${#text_content} chars total)"
                                else
                                    print_status "[CLAUDE] $text_content"
                                fi
                            else
                                # Normal mode: show reasonable preview to avoid log spam
                                if [ ${#text_content} -gt 150 ]; then
                                    print_status "[CLAUDE] ${text_content:0:150}..."
                                else
                                    print_status "[CLAUDE] $text_content"
                                fi
                            fi
                        fi
                    fi
                fi
                ;;
            "user")
                # Tool results - show actual content returned by tools
                if echo "$line" | grep -q '"tool_result"'; then
                    if command -v jq >/dev/null 2>&1; then
                        tool_id=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_result") | .tool_use_id // "unknown"' 2>/dev/null)
                        is_error=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_result") | .is_error // false' 2>/dev/null)
                        
                        # Get the tool name from our stored correlation
                        tool_name="${tool_calls[$tool_id]:-unknown}"
                        
                        # Extract result content properly - it's an array of content objects
                        result_content=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_result") | .content[]? | .text // ""' 2>/dev/null)
                        
                        if [ "$is_error" = "true" ]; then
                            # Extract detailed error information
                            error_msg=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_result") | .error // ""' 2>/dev/null)
                            
                            # If no error field, try to extract from content
                            if [ -z "$error_msg" ] || [ "$error_msg" = "null" ] || [ "$error_msg" = "" ]; then
                                error_msg=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_result") | .content[]? | .text // "Unknown error"' 2>/dev/null)
                            fi
                            
                            # Show correlated tool failure with actual error
                            if [ "$tool_name" != "unknown" ]; then
                                print_warning "[TOOL-RESULT] ❌ $tool_name failed: $error_msg"
                            else
                                print_warning "[TOOL-RESULT] ❌ Tool execution failed: $error_msg"
                            fi
                        else
                            # Tool succeeded
                            if [ "$tool_name" != "unknown" ]; then
                                print_status "[TOOL-RESULT] ✅ $tool_name completed"
                            else
                                print_status "[TOOL-RESULT] ✅ Tool execution completed"
                            fi
                            
                            # Show tool result content if not empty
                            if [ -n "$result_content" ] && [ "$result_content" != "null" ] && [ "$result_content" != "" ]; then
                                # Show tool result content with appropriate limits
                                if [ "$DEBUG_MODE" = "true" ]; then
                                    if [ ${#result_content} -gt 1000 ]; then
                                        print_status "[TOOL-OUTPUT] ${result_content:0:1000}... (${#result_content} chars total)"
                                    else
                                        print_status "[TOOL-OUTPUT] $result_content"
                                    fi
                                else
                                    if [ ${#result_content} -gt 300 ]; then
                                        print_status "[TOOL-OUTPUT] ${result_content:0:300}... (${#result_content} chars)"
                                    else
                                        print_status "[TOOL-OUTPUT] $result_content"
                                    fi
                                fi
                            fi
                        fi
                    else
                        print_status "[TOOL-RESULT] Tool execution completed"
                    fi
                fi
                ;;
            "result")
                if command -v jq >/dev/null 2>&1; then
                    is_error=$(echo "$line" | jq -r '.is_error // false')
                    duration_ms=$(echo "$line" | jq -r '.duration_ms // 0')
                    num_turns=$(echo "$line" | jq -r '.num_turns // 0')
                    total_cost=$(echo "$line" | jq -r '.total_cost_usd // 0')
                    
                    if [ "$is_error" = "true" ]; then
                        print_error "Claude execution failed"
                    else
                        print_success "Claude execution completed (${duration_ms}ms, $num_turns turns, \$${total_cost})"
                    fi
                else
                    if echo "$line" | grep -q '"is_error":false'; then
                        print_success "Claude execution completed"
                    else
                        print_error "Claude execution failed"
                    fi
                fi
                ;;
            *)
                # Unknown event type - log in debug mode only
                if [ "$DEBUG_MODE" = "true" ]; then
                    print_status "[DEBUG] Unknown event type: $event_type"
                fi
                ;;
        esac
    done
}



# Debug mode status
if [ "$DEBUG_MODE" = "true" ]; then
    print_status "🐛 DEBUG MODE ENABLED - Real-time Claude event streaming"
    print_status "   Tool calls and performance metrics will be shown in real-time"
else
    print_status "📋 Normal mode - Claude events will be processed with stream-json for better reliability"
fi

# Native subagent system - no additional server management needed
print_status "🔧 Native subagent system active"
print_status "   All subagent interactions will be captured via stream-json events"

# Verify subagent configuration is ready
print_status "Verifying subagent configuration readiness..."
if [ -f "$HOME/cmd/external_mcp.txt" ]; then
    print_status "External MCP configuration available"
fi
if [ -f "$HOME/cmd/processed_tool_whitelist.txt" ]; then
    print_status "Tool whitelist configuration available"
    TOOL_COUNT=$(wc -l < "$HOME/cmd/processed_tool_whitelist.txt" 2>/dev/null || echo "0")
    print_status "Tools available: $TOOL_COUNT"
fi

print_success "Native subagent system and external MCP support ready"

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

print_status "Setting up workspace in MCP-configured directory..."
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Skip redundant setup in resume mode
if [ "$TASK_MODE" = "resume" ]; then
    print_status "Resume mode: Skipping repository setup, using existing workspace"
    
    # In resume mode, just navigate to existing directory
    if [ -n "$CUSTOM_REPO_PATH" ]; then
        TARGET_REPO_DIR="/home/owner/$CUSTOM_REPO_PATH"
        if [ ! -d "$TARGET_REPO_DIR" ]; then
            print_error "Resume mode: Custom repo path does not exist: $TARGET_REPO_DIR"
            exit 1
        fi
        cd "$TARGET_REPO_DIR"
        print_status "Resume mode: Using existing custom repo at $TARGET_REPO_DIR"
    else
        TARGET_REPO_DIR="$WORKSPACE_DIR/target-repo"
        if [ ! -d "$TARGET_REPO_DIR" ]; then
            print_error "Resume mode: Target repository does not exist: $TARGET_REPO_DIR"
            print_error "Cannot resume - sandbox may not be properly initialized"
            exit 1
        fi
        cd target-repo
        print_status "Resume mode: Using existing repository at $TARGET_REPO_DIR"
    fi
    
    # Skip project subagent detection in resume mode - should already be detected
    print_status "Resume mode: Skipping project subagent detection (using existing configuration)"
    
else
    # Normal mode: full setup
    print_status "Initial mode: Setting up repository and MCP configuration"
    
    # Determine target repo directory based on whether custom repo path is provided
    if [ -n "$CUSTOM_REPO_PATH" ]; then
        TARGET_REPO_DIR="/home/owner/$CUSTOM_REPO_PATH"
        print_status "Using custom repo path: $TARGET_REPO_DIR"
        
        # Verify the custom repo directory exists
        if [ ! -d "$TARGET_REPO_DIR" ]; then
            print_error "Custom repo path does not exist: $TARGET_REPO_DIR"
            exit 1
        fi
        
        cd "$TARGET_REPO_DIR"
        print_success "Using existing repository at $TARGET_REPO_DIR"
    else
        TARGET_REPO_DIR="$WORKSPACE_DIR/target-repo"
        
        # Remove existing target-repo if it exists
        if [ -d "$TARGET_REPO_DIR" ]; then
            print_warning "Removing existing target-repo directory"
            rm -rf "$TARGET_REPO_DIR"
        fi
        
        # Clone the target repository
        print_status "Cloning repository: $GITHUB_REPO"
        gh repo clone "$GITHUB_REPO" target-repo
        cd target-repo
        
        print_success "Repository cloned successfully"
    fi

    # Detect project-level subagents in .claude/agents/ directory
    detect_project_subagents
fi

# Verify subagent system and external MCP configuration
print_status "Verifying native subagent system and external MCP configuration..."
user_agents_count=0
project_agents_count=0

# Count user agents
if [ -d "$HOME/.claude/agents" ]; then
    user_agents_count=$(find "$HOME/.claude/agents" -name "*.md" -type f 2>/dev/null | wc -l)
fi

# Count project agents
if [ -d ".claude/agents" ]; then
    project_agents_count=$(find ".claude/agents" -name "*.md" -type f 2>/dev/null | wc -l)
fi

# Check external MCP configuration
external_mcp_servers=0
if [ -f "/home/owner/.mcp.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        external_mcp_servers=$(jq '.mcpServers | length' /home/owner/.mcp.json 2>/dev/null || echo "0")
    fi
fi

print_status "User agents available: $user_agents_count"
print_status "Project agents available: $project_agents_count"  
print_status "External MCP servers configured: $external_mcp_servers"
print_success "Native subagent system and external MCP verification completed"

# Create .claude directory and settings.local.json for permissions
mkdir -p .claude

# Generate permissions based on tool whitelist or use defaults
print_status "Configuring Claude permissions based on tool whitelist..."

# Default available tools (used as fallback if no whitelist provided)
# Reference list of all available Claude tools:
# Built-in: Read, Write, Edit, MultiEdit, LS, Glob, Grep, Bash, Task, TodoRead, TodoWrite, NotebookRead, NotebookEdit, WebFetch, WebSearch
# Subagent tools: Available through native Claude Code subagent system

# Generate permissions using external script  
PERMISSIONS_OUTPUT=$("$SCRIPT_DIR/generate_permissions_json.py" "$HOME/cmd/processed_tool_whitelist.txt" --format both 2>/dev/null)

if [ $? -eq 0 ]; then
    # Parse the output from the script
    TOOL_COUNT=$(echo "$PERMISSIONS_OUTPUT" | grep "^TOOL_COUNT=" | cut -d'=' -f2)
    STATUS=$(echo "$PERMISSIONS_OUTPUT" | grep "^STATUS=" | cut -d'=' -f2)
    PERMISSIONS_JSON=$(echo "$PERMISSIONS_OUTPUT" | sed -n '/^---$/,$p' | tail -n +2)
    
    case "$STATUS" in
        "whitelist")
            print_status "Using tool whitelist from cs-cc configuration"
            print_status "Configured $TOOL_COUNT tools from whitelist"
            ;;
        "fallback")
            print_warning "No valid tool whitelist found, using default permissions"
            print_status "Using $TOOL_COUNT default Claude tools"
            ;;
    esac
    
    # Show configured tools for verification
    "$SCRIPT_DIR/generate_permissions_json.py" "$HOME/cmd/processed_tool_whitelist.txt" --format info | grep "^TOOLS=" | cut -d'=' -f2 | sed 's/^/  Tools: /' | tr ',' ' '
else
    print_error "Failed to generate permissions, using emergency fallback"
    PERMISSIONS_JSON='{
  "permissions": {
    "allow": [
      "Read", "Write", "Edit", "MultiEdit", "LS", "Glob", "Grep",
      "Bash", "Task", "TodoRead", "TodoWrite", "NotebookRead", 
      "NotebookEdit", "WebFetch", "WebSearch"
    ],
    "deny": []
  }
}'
fi

# Create the settings.local.json with dynamic permissions
echo "$PERMISSIONS_JSON" > .claude/settings.local.json



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
echo "Prompt: $FINAL_PROMPT" >&2

# Debug: Check if CLAUDE_PROMPT is effectively empty
if [ -z "${FINAL_PROMPT// }" ]; then
    print_error "CLAUDE_PROMPT is empty or contains only whitespace"
    echo "Raw CLAUDE_PROMPT value: '$CLAUDE_PROMPT'" >&2
    echo "Length: ${#CLAUDE_PROMPT}" >&2
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

# Test Claude subagent system and external MCP configuration
print_status "Testing Claude subagent system and external MCP configuration..."
if claude --version 2>&1; then
    print_success "Claude version command succeeded - subagent system ready"
else
    print_warning "Claude command failed - subagent system may not be available"
fi

# Test external MCP configuration
print_status "Testing external MCP configuration..."
if [ -f "/home/owner/.mcp.json" ]; then
    if claude --mcp-config /home/owner/.mcp.json mcp list 2>&1; then
        print_success "External MCP configuration verified"
    else
        print_warning "External MCP configuration failed - may not have external servers"
    fi
else
    print_status "No MCP configuration file - no external servers configured"
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

# Run Claude Code with stream-json output
print_status "Executing Claude Code with stream-json for real-time event monitoring..."

# Check for session reuse in resume mode
CLAUDE_RESUME_FLAG=""
if [ "$TASK_MODE" = "resume" ]; then
    # Try to find existing session ID from session.json
    SESSION_FILE="$HOME/session.json"
    if [ -f "$SESSION_FILE" ]; then
        if command -v jq >/dev/null 2>&1; then
            EXISTING_SESSION_ID=$(jq -r '.sessionId // empty' "$SESSION_FILE" 2>/dev/null)
            if [ -n "$EXISTING_SESSION_ID" ] && [ "$EXISTING_SESSION_ID" != "null" ]; then
                print_status "Resume mode: Found existing session ID: ${EXISTING_SESSION_ID:0:8}..."
                CLAUDE_RESUME_FLAG="--resume $EXISTING_SESSION_ID"
                print_status "Resume mode: Will attempt to reuse existing Claude session"
            else
                print_status "Resume mode: No valid session ID found, starting new session"
            fi
        else
            print_status "Resume mode: jq not available, cannot parse session file"
        fi
    else
        print_status "Resume mode: No session file found, starting new session"
    fi
fi

# Use stream-json format for structured output and real-time event processing
if claude --mcp-config /home/owner/.mcp.json -p "$FINAL_PROMPT" $CLAUDE_RESUME_FLAG --output-format stream-json --verbose | parse_claude_stream_json; then
    print_success "Claude Code execution pipeline completed successfully"
else
    exit_code=$?
    print_error "Claude Code execution failed with exit code: $exit_code"
    echo "Available commands in PATH:"
    which claude 2>/dev/null || echo "claude command not found"
    exit 1
fi

# Ensure Claude-specific files are in .gitignore to prevent accidental commits (only in git repositories)
if [ -d .git ]; then
    print_status "Ensuring Claude configuration files are excluded from git tracking..."
    
    # Create or append to .gitignore with Claude-specific entries
    if [ -f .gitignore ]; then
        # Check if our entries already exist to avoid duplicates (only .claude/ now since MCP config is centralized)
        if ! grep -q "^\.claude/$" .gitignore; then
            echo ".claude/" >> .gitignore
            print_status "Added .claude/ to .gitignore"
        fi
    else
        # Create new .gitignore with Claude entries
        cat > .gitignore << EOF
# Claude Code automation configuration files
.claude/
EOF
        print_status "Created .gitignore with Claude configuration exclusions"
    fi
else
    print_status "Not a git repository - skipping .gitignore setup"
fi

print_success "=== Claude Code Automation Completed Successfully ==="

# Handle task completion and queue processing
print_status "=== Task Management Completion Processing ==="

if [ -n "$CURRENT_TASK_ID" ]; then
    # Always mark current task as completed (the task manager handles duplicates)
    print_status "Marking current task as completed: $CURRENT_TASK_ID"
    if [ "$DEBUG_MODE" = "true" ]; then
        print_status "[DEBUG] Updating task status: $CURRENT_TASK_ID -> completed"
    fi
    if ! "$SCRIPT_DIR/task-state-manager.sh" update "$CURRENT_TASK_ID" "completed" >/dev/null 2>&1; then
        # Suppress noisy warning when task is already completed/moved to history
        CURRENT_STATE_JSON=$("$SCRIPT_DIR/task-state-manager.sh" read 2>/dev/null || echo '{}')
        already_completed=$(printf '%s' "$CURRENT_STATE_JSON" | python3 - "$CURRENT_TASK_ID" << 'PY'
import json,sys
try:
    data=json.load(sys.stdin)
    task_id = sys.argv[1] if len(sys.argv) > 1 else ""
    for t in data.get('history', []):
        if t.get('status')=='completed' and t.get('id')==task_id:
            print('yes'); sys.exit(0)
    print('no')
except Exception:
    print('no')
PY
)
        if [ "$already_completed" = "yes" ]; then
            print_status "Task $CURRENT_TASK_ID already completed, skipping status update"
        else
            print_warning "Failed to update task status"
        fi
    fi
    
    # Check for next pending task in queue
    if [ "$DEBUG_MODE" = "true" ]; then
        print_status "[DEBUG] Checking for next pending task in queue..."
    fi
    NEXT_TASK=$("$SCRIPT_DIR/task-state-manager.sh" next 2>/dev/null)
    if [ "$NEXT_TASK" != "null" ] && [ -n "$NEXT_TASK" ]; then
        NEXT_TASK_ID=$(echo "$NEXT_TASK" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null)
        if [ -n "$NEXT_TASK_ID" ]; then
            print_status "Found next pending task: $NEXT_TASK_ID"
            if [ "$DEBUG_MODE" = "true" ]; then
                print_status "[DEBUG] Next task details:"
                echo "$NEXT_TASK" | python3 -m json.tool 2>/dev/null | sed 's/^/[DEBUG]   /' || print_status "[DEBUG] Could not parse task JSON"
            fi
            
            # Check if we should continue with next task (only if not in delete mode)
            if [ "$SHOULD_DELETE" != "true" ]; then
                print_status "Starting next task automatically..."
                if [ "$DEBUG_MODE" = "true" ]; then
                    print_status "[DEBUG] SHOULD_DELETE=false, proceeding with next task"
                fi
                
                # Update task to in_progress
                "$SCRIPT_DIR/task-state-manager.sh" update "$NEXT_TASK_ID" "in_progress" >/dev/null 2>&1 || true
                
                # Update current task ID for proper completion tracking
                export CURRENT_TASK_ID="$NEXT_TASK_ID"
                
                # Get the prompt file for the next task
                NEXT_PROMPT_FILE=$(echo "$NEXT_TASK" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('promptFile', ''))" 2>/dev/null)
                
                if [ -f "$NEXT_PROMPT_FILE" ]; then
                    print_status "Executing next task with prompt: $NEXT_PROMPT_FILE"
                    
                    # Read the next task prompt
                    NEXT_CLAUDE_PROMPT=$(cat "$NEXT_PROMPT_FILE")
                    
                    # Update tool permissions if new task has different tools
                    NEXT_TOOL_WHITELIST=$(echo "$NEXT_TASK" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('toolWhitelist', ''))" 2>/dev/null)
                    if [ -n "$NEXT_TOOL_WHITELIST" ] && [ -f "$HOME/cmd/$NEXT_TOOL_WHITELIST" ]; then
                        print_status "Updating tool permissions for next task..."
                        if [ "$DEBUG_MODE" = "true" ]; then
                            print_status "[DEBUG] Tool whitelist file: $HOME/cmd/$NEXT_TOOL_WHITELIST"
                            print_status "[DEBUG] Current tools: $(cat "$HOME/cmd/$NEXT_TOOL_WHITELIST" 2>/dev/null | tr '\n' ' ')"
                        fi
                        
                        # Regenerate permissions for new task
                        NEXT_PERMISSIONS_OUTPUT=$("$SCRIPT_DIR/generate_permissions_json.py" "$HOME/cmd/$NEXT_TOOL_WHITELIST" --format both 2>/dev/null)
                        if [ $? -eq 0 ]; then
                            NEXT_PERMISSIONS_JSON=$(echo "$NEXT_PERMISSIONS_OUTPUT" | sed -n '/^---$/,$p' | tail -n +2)
                            echo "$NEXT_PERMISSIONS_JSON" > .claude/settings.local.json
                            print_status "Updated tool permissions for next task"
                            if [ "$DEBUG_MODE" = "true" ]; then
                                TOOL_COUNT=$(echo "$NEXT_PERMISSIONS_OUTPUT" | grep "^TOOL_COUNT=" | cut -d'=' -f2)
                                print_status "[DEBUG] Updated .claude/settings.local.json with $TOOL_COUNT tools"
                            fi
                        else
                            if [ "$DEBUG_MODE" = "true" ]; then
                                print_status "[DEBUG] Failed to generate permissions for tool whitelist"
                            fi
                        fi
                    elif [ "$DEBUG_MODE" = "true" ]; then
                        print_status "[DEBUG] No tool whitelist update needed (file: $NEXT_TOOL_WHITELIST, exists: $([ -f "$HOME/cmd/$NEXT_TOOL_WHITELIST" ] && echo 'yes' || echo 'no'))"
                    fi
                    
                    # Add task context to prompt
                    TASK_CONTEXT="This is a follow-up task (ID: $NEXT_TASK_ID) in a multi-task workflow. Previous task completed successfully."
                    NEXT_FINAL_PROMPT="$TASK_CONTEXT\n\n$NEXT_CLAUDE_PROMPT"
                    
                    print_status "Executing next task with Claude Code..."
                    
                    # Check for session reuse for next task
                    NEXT_CLAUDE_RESUME_FLAG=""
                    if [ -f "$HOME/session.json" ] && command -v jq >/dev/null 2>&1; then
                        NEXT_SESSION_ID=$(jq -r '.sessionId // empty' "$HOME/session.json" 2>/dev/null)
                        if [ -n "$NEXT_SESSION_ID" ] && [ "$NEXT_SESSION_ID" != "null" ]; then
                            print_status "Next task: Reusing session ID: ${NEXT_SESSION_ID:0:8}..."
                            NEXT_CLAUDE_RESUME_FLAG="--resume $NEXT_SESSION_ID"
                        fi
                    fi
                    
                    # Execute next task
                    if claude --mcp-config /home/owner/.mcp.json -p "$NEXT_FINAL_PROMPT" $NEXT_CLAUDE_RESUME_FLAG --output-format stream-json --verbose | parse_claude_stream_json; then
                        print_success "Next task completed successfully"
                        "$SCRIPT_DIR/task-state-manager.sh" update "$NEXT_TASK_ID" "completed" >/dev/null 2>&1 || true
                    else
                        print_error "Next task failed"
                        "$SCRIPT_DIR/task-state-manager.sh" update "$NEXT_TASK_ID" "failed" >/dev/null 2>&1 || true
                    fi
                else
                    print_warning "Next task prompt file not found: $NEXT_PROMPT_FILE"
                fi
            else
                print_status "Sandbox will be deleted - skipping next task execution"
                print_status "Next task $NEXT_TASK_ID remains in queue for future execution"
            fi
        fi
    else
        print_status "No more pending tasks in queue"
    fi
else
    print_status "No current task ID found - legacy mode execution"
fi

# Print final task queue status
"$SCRIPT_DIR/task-state-manager.sh" status 2>/dev/null || print_warning "Could not read final task queue status"

print_status "=== Task Management Completion Processing Complete ==="

# Print summary
echo >&2
print_status "Summary:"
echo "  Repository: $GITHUB_REPO" >&2
echo "  Action Type: $ACTION_TYPE" >&2
if [ "$ACTION_TYPE" = "pr" ]; then
    echo "  PR Number: $PR_NUMBER" >&2
elif [ "$ACTION_TYPE" = "issue" ]; then
    echo "  Issue Number: $ISSUE_NUMBER" >&2
elif [ "$ACTION_TYPE" = "branch" ]; then
    echo "  Target Branch: $GITHUB_BRANCH" >&2
fi
echo "  Subagent System: Native Claude Code subagents + external MCP support active" >&2
echo >&2
print_success "🎉 Workflow completed successfully!"

# Call completion script with task ID if available
if [ -n "$CURRENT_TASK_ID" ]; then
    COMPLETION_SCRIPT="/home/owner/completion.sh"
    if [ -f "$COMPLETION_SCRIPT" ]; then
        print_status "Calling completion script with task ID: $CURRENT_TASK_ID"
        if bash "$COMPLETION_SCRIPT" "$CURRENT_TASK_ID"; then
            print_success "Completion script executed successfully"
        else
            print_warning "Completion script failed (exit code: $?)"
        fi
    else
        print_warning "Completion script not found at: $COMPLETION_SCRIPT"
    fi
else
    print_status "No current task ID available - skipping completion script"
fi

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