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



print_status "=== Claude Code Automation Workflow ==="

# Step 1: Setup Claude Code and MCP configuration
print_status "Setting up Claude Code environment..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/setup-claude.sh" ]; then
    print_status "Sourcing setup-claude.sh to configure Claude Code and MCP..."
    source "$SCRIPT_DIR/setup-claude.sh"
    print_success "Claude Code and MCP setup completed"
    
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
echo "ANTHROPIC_API_KEY: $([ -n "$ANTHROPIC_API_KEY" ] && echo "[set]" || echo "[not set]")" >&2

# Validate required environment variables
print_status "Validating environment variables..."

if [ -z "$GITHUB_REPO" ] || [ -z "$GITHUB_TOKEN" ]; then
    print_error "Missing required environment variables"
    echo "Required: GITHUB_REPO, GITHUB_TOKEN" >&2
    echo "Current values:" >&2
    echo "GITHUB_REPO: '$GITHUB_REPO'" >&2
    echo "GITHUB_TOKEN: '$([ -n "$GITHUB_TOKEN" ] && echo "[set]" || echo "[empty]")'" >&2
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

# Start local MCP server if configured
print_status "Starting MCP server lifecycle management..."

# Function to start local MCP server
start_local_mcp_server() {
    # Prevent the entire worker from aborting if MCP server startup fails
    # This function is best-effort: Claude Code can still work without a long-running
    # background server because it will spawn the server on demand via `claude mcp`.
    set +e  # Temporarily disable exit-on-error within this function
    local local_mcp_config="$HOME/cmd/local_mcp_tools.txt"
    local mcp_server_script="$HOME/claude/dev-worker/local_mcp_server/local-mcp-server.js"
    
    print_status "MCP Server startup - User: $(whoami), HOME: $HOME"
    
    if [ -f "$local_mcp_config" ] && [ -s "$local_mcp_config" ]; then
        print_status "Local MCP tools configuration found, starting local MCP server..."
        print_status "Config file: $local_mcp_config"
        print_status "Server script: $mcp_server_script"
        
        if [ ! -f "$mcp_server_script" ]; then
            print_warning "Local MCP server script not found at $mcp_server_script (continuing)"
            set -e
            return 0
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
                print_warning "Failed to install MCP server dependencies (continuing without local server)"
                set -e
                return 0
            }
        fi
        
        # Start the MCP server in background
        print_status "Starting local MCP server at $mcp_server_script"
        cd "$mcp_server_dir"
        
        # In debug mode, show MCP logs in real-time; otherwise redirect to file
        if [ "$DEBUG_MODE" = "true" ]; then
            print_status "Debug mode: Starting MCP server with real-time logging"
            
            # OPTION 1: Direct stdout integration (immediate, no file needed)
            # This sends MCP logs directly to stdout with [MCP-DIRECT] prefix
            print_status "🔧 Using direct stdout integration for immediate MCP visibility"
            if [ "$(whoami)" = "owner" ]; then
                node local-mcp-server.js 2>&1 | sed 's/^/[MCP-DIRECT] /' &
            else
                sudo -u owner node local-mcp-server.js 2>&1 | sed 's/^/[MCP-DIRECT] /' &
            fi
            MCP_SERVER_PID=$!
            echo $MCP_SERVER_PID > "$HOME/cmd/mcp_server.pid"
            print_status "✅ MCP server started with direct stdout integration"
            sleep 2  # Give server time to start
            
            # OPTION 2: Also maintain file-based tailing as backup
            # (Commented out to avoid duplicate logs, but can be enabled if needed)
            # 
            # # In debug mode, start server normally but also tail its log file in background
            # if [ "$(whoami)" = "owner" ]; then
            #     nohup node local-mcp-server.js > mcp-server.log 2>&1 &
            # else
            #     nohup sudo -u owner node local-mcp-server.js > mcp-server.log 2>&1 &
            # fi
            # MCP_SERVER_PID=$!
            # 
            # # Start log tailing process to show MCP logs in real-time
            # sleep 2  # Give server more time to start and create log file
            # 
            # # Create log file if it doesn't exist
            # if [ ! -f mcp-server.log ]; then
            #     touch mcp-server.log
            #     print_status "Created MCP server log file"
            # fi
            # 
            # # Start robust log tailing with error handling
            # print_status "🔧 Starting MCP log integration..."
            # (
            #     # Wait for log file to have content or timeout after 10 seconds
            #     timeout=10
            #     while [ ! -s mcp-server.log ] && [ $timeout -gt 0 ]; do
            #         sleep 1
            #         timeout=$((timeout - 1))
            #     done
            #     
            #     if [ -s mcp-server.log ]; then
            #         print_status "✅ MCP log file ready, starting real-time streaming"
            #         tail -f mcp-server.log | while IFS= read -r line; do 
            #             echo "[MCP-SERVER] $line"
            #         done
            #     else
            #         print_warning "⚠️  MCP log file empty after timeout, starting tail anyway"
            #         tail -f mcp-server.log | while IFS= read -r line; do 
            #             echo "[MCP-SERVER] $line"
            #         done
            #     fi
            # ) &
            # MCP_LOG_PID=$!
            # echo $MCP_LOG_PID > "$HOME/cmd/mcp_log.pid"
            # print_status "🔧 MCP server logs will be prefixed with [MCP-SERVER] in real-time"
        else
            # Normal mode: redirect to log file
            if [ "$(whoami)" = "owner" ]; then
                nohup node local-mcp-server.js > mcp-server.log 2>&1 &
            else
                nohup sudo -u owner node local-mcp-server.js > mcp-server.log 2>&1 &
            fi
            MCP_SERVER_PID=$!
        fi
        
        # Give the server a moment to start
        sleep 3
        
        # Verify the server started successfully
        if kill -0 $MCP_SERVER_PID 2>/dev/null; then
            print_success "Local MCP server started successfully (PID: $MCP_SERVER_PID)"
            echo $MCP_SERVER_PID > "$HOME/cmd/mcp_server.pid"
            if [ "$DEBUG_MODE" = "true" ]; then
                print_status "🔧 MCP server running - tool calls will appear with [MCP-SERVER] prefix"
                print_status "   Look for: [LOCAL-MCP] 🔧 TOOL CALL INITIATED messages"
            else
                print_status "MCP server running - logs saved to mcp-server.log"
            fi
        else
            print_warning "Local MCP server did not remain running (non-fatal)."
            if [ "$DEBUG_MODE" != "true" ]; then
                print_status "Recent server logs:"
                tail -10 mcp-server.log 2>/dev/null || echo "No logs available"
            fi
        fi
    else
        print_status "No local MCP tools configuration found, skipping local MCP server startup"
        print_status "Checked for: $local_mcp_config"
        if [ -f "$local_mcp_config" ]; then
            print_status "File exists but is empty ($(wc -c < "$local_mcp_config") bytes)"
        fi
    fi

    # Re-enable exit-on-error for the rest of the script and always succeed
    set -e
    return 0
}

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
                        mcp_count=$(echo "$line" | jq -r '.mcp_servers | length // 0')
                    else
                        session_id="unknown"
                        model="unknown"
                        mcp_count="unknown"
                    fi
                    print_status "🔧 Claude session initialized (ID: ${session_id:0:8}..., Model: $model, MCP servers: $mcp_count)"
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
                            if echo "$tool_name" | grep -q "mcp__"; then
                                tool_prefix="[MCP-TOOL]"
                            else
                                tool_prefix="[TOOL]"
                            fi
                            
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
                        if echo "$line" | grep -q "mcp__"; then
                            print_status "[MCP-TOOL] 🔧 Tool call initiated"
                        else
                            print_status "[TOOL] 🔧 Tool call initiated"
                        fi
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
                                if [ "$DEBUG_MODE" = "true" ]; then
                                    # Debug mode: show more detailed output
                                    if [ ${#result_content} -gt 500 ]; then
                                        print_status "[TOOL-OUTPUT] ${result_content:0:500}... (${#result_content} chars total)"
                                    else
                                        print_status "[TOOL-OUTPUT] $result_content"
                                    fi
                                else
                                    # Normal mode: show brief output or just indicate content
                                    if [ ${#result_content} -gt 200 ]; then
                                        print_status "[TOOL-OUTPUT] ${result_content:0:200}... (${#result_content} chars)"
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

# Stream-JSON logging setup
if [ "$DEBUG_MODE" = "true" ]; then
    print_status "🐛 DEBUG MODE ENABLED - Real-time Claude event streaming with enhanced MCP visibility"
    print_status "   Tool calls, MCP interactions, and performance metrics will be shown in real-time"
else
    print_status "📋 Normal mode - Claude events will be processed with stream-json for better reliability"
fi

# MCP server will be started on-demand by Claude Code
print_status "🔧 MCP server will be started on-demand by Claude Code"
print_status "   All tool calls and interactions will be captured via stream-json events"

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



# Clone the target repository
print_status "Cloning repository: $GITHUB_REPO"
gh repo clone "$GITHUB_REPO" target-repo
cd target-repo

print_success "Repository cloned successfully"

# Copy MCP configuration to target-repo directory where Claude Code will run
print_status "Copying MCP configuration to target repository..."
if [ -f "$WORKSPACE_DIR/.mcp.json" ]; then
    cp "$WORKSPACE_DIR/.mcp.json" .mcp.json
    print_success "MCP configuration copied to target repository"
    print_status "MCP config location: $(pwd)/.mcp.json"

    # -----------------------------------------------------------------------------
    # Ensure the global Claude configuration (~/.claude.json) enables the local MCP
    # server for the *target-repo* directory we just set up. Without this entry the
    # `claude mcp list` command will report no servers even when .mcp.json exists.
    # -----------------------------------------------------------------------------

    # print_status "Patching global Claude config (~/.claude.json) for project scope..."

    # if "$SCRIPT_DIR/patch_claude_config.py" "$(pwd)"; then
    #     print_success "Global Claude config patched successfully"
    # else
    #     print_warning "Failed to patch global Claude config (continuing anyway)"
    # fi
else
    print_warning "No MCP configuration found at $WORKSPACE_DIR/.mcp.json"
fi

# Create .claude directory and settings.local.json for permissions
mkdir -p .claude

# Generate permissions based on tool whitelist or use defaults
print_status "Configuring Claude permissions based on tool whitelist..."

# Default available tools (used as fallback if no whitelist provided)
# Reference list of all available Claude tools:
# Built-in: Read, Write, Edit, MultiEdit, LS, Glob, Grep, Bash, Task, TodoRead, TodoWrite, NotebookRead, NotebookEdit, WebFetch, WebSearch
# MCP tools: Will be added dynamically based on configured MCP servers

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

# Test Claude MCP configuration
print_status "Testing Claude MCP configuration..."
if claude mcp list 2>&1; then
    print_success "Claude MCP list command succeeded"
else
    print_warning "Claude MCP list command failed - MCP may not be properly configured"
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

# Use stream-json format for structured output and real-time event processing
if claude --mcp-config .mcp.json -p "$FINAL_PROMPT" --output-format stream-json --verbose | parse_claude_stream_json; then
    print_success "Claude Code execution pipeline completed successfully"
else
    exit_code=$?
    print_error "Claude Code execution failed with exit code: $exit_code"
    echo "Available commands in PATH:"
    which claude 2>/dev/null || echo "claude command not found"
    exit 1
fi

# Ensure Claude-specific files are in .gitignore to prevent accidental commits
print_status "Ensuring Claude configuration files are excluded from git tracking..."

# Create or append to .gitignore with Claude-specific entries
if [ -f .gitignore ]; then
    # Check if our entries already exist to avoid duplicates
    if ! grep -q "^\.mcp\.json$" .gitignore; then
        echo ".mcp.json" >> .gitignore
        print_status "Added .mcp.json to .gitignore"
    fi
    if ! grep -q "^\.claude/$" .gitignore; then
        echo ".claude/" >> .gitignore
        print_status "Added .claude/ to .gitignore"
    fi
else
    # Create new .gitignore with Claude entries
    cat > .gitignore << EOF
# Claude Code automation configuration files
.mcp.json
.claude/
EOF
    print_status "Created .gitignore with Claude configuration exclusions"
fi

print_success "=== Claude Code Automation Completed Successfully ==="

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
echo "  MCP Configuration: Applied from cs-cc parameters" >&2
echo >&2
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