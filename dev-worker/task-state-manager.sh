#!/bin/bash

# Task State Management System
# Manages task queue, state persistence, and task transitions for Claude Code automation

# Task state schema for ~/state.json:
# {
#   "currentTask": "task-id-123" | null,
#   "queue": [
#     {
#       "id": "task-id-123",
#       "status": "pending|in_progress|completed|failed",
#       "created": "2024-01-01T12:00:00Z",
#       "updated": "2024-01-01T12:05:00Z",
#       "promptFile": "prompt.txt",
#       "promptPreview": "First 100 chars of prompt...",
#       "toolWhitelist": "tool-whitelist.json",
#       "sessionId": "session-abc123" | null,
#       "retryCount": 0,
#       "metadata": {
#         "source": "cli|api",
#         "priority": 1
#       }
#     }
#   ],
#   "history": [],
#   "version": "1.0"
# }

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to print output without colors
print_status() {
    echo "[TASK-STATE] $1" >&2
}

print_success() {
    echo "[TASK-STATE] ✅ $1" >&2
}

print_warning() {
    echo "[TASK-STATE] ⚠️ $1" >&2
}

print_error() {
    echo "[TASK-STATE] ❌ $1" >&2
}

# Function to generate unique task ID
generate_task_id() {
    local custom_id="$1"
    
    if [ -n "$custom_id" ]; then
        # Validate custom ID format (alphanumeric, hyphens, underscores only)
        if [[ "$custom_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "$custom_id"
        else
            print_error "Invalid task ID format: $custom_id. Must contain only letters, numbers, hyphens, and underscores."
            return 1
        fi
    else
        # Generate timestamp-based ID
        local timestamp=$(date +%Y%m%d-%H%M%S)
        local random=$(openssl rand -hex 3 2>/dev/null || echo $(( RANDOM % 1000 )))
        echo "task-${timestamp}-${random}"
    fi
}

# Function to get current timestamp in ISO format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Function to initialize state file if it doesn't exist
init_state_file() {
    local state_file="$HOME/state.json"
    
    if [ ! -f "$state_file" ]; then
        print_status "Initializing task state file: $state_file"
        cat > "$state_file" << 'EOF'
{
  "currentTask": null,
  "queue": [],
  "history": [],
  "version": "1.0"
}
EOF
        print_success "Task state file initialized"
    fi
}

# Function to validate state file format
validate_state_file() {
    local state_file="$HOME/state.json"
    
    if [ ! -f "$state_file" ]; then
        print_error "State file does not exist: $state_file"
        return 1
    fi
    
    # Check if it's valid JSON
    if ! python3 -m json.tool "$state_file" >/dev/null 2>&1; then
        print_error "State file contains invalid JSON: $state_file"
        return 1
    fi
    
    # Check for required fields
    local current_task=$(python3 -c "import json, sys; data=json.load(open('$state_file')); print(data.get('currentTask', 'null'))" 2>/dev/null)
    local queue=$(python3 -c "import json, sys; data=json.load(open('$state_file')); print(type(data.get('queue', [])))" 2>/dev/null)
    
    if [ "$queue" != "<class 'list'>" ]; then
        print_error "State file missing or invalid 'queue' field"
        return 1
    fi
    
    print_status "State file validation passed"
    return 0
}

# Function to read task state
read_state() {
    local state_file="$HOME/state.json"
    init_state_file
    
    if validate_state_file; then
        cat "$state_file"
    else
        print_error "Failed to read task state"
        return 1
    fi
}

# Function to get current task
get_current_task() {
    local state_file="$HOME/state.json"
    init_state_file
    
    python3 -c "
import json, sys
try:
    with open('$state_file') as f:
        data = json.load(f)
    current_task_id = data.get('currentTask')
    if current_task_id:
        for task in data.get('queue', []):
            if task.get('id') == current_task_id:
                print(json.dumps(task, indent=2))
                sys.exit(0)
    print('null')
except Exception as e:
    print('null')
    sys.exit(1)
"
}

# Function to get next pending task
get_next_pending_task() {
    local state_file="$HOME/state.json"
    init_state_file
    
    python3 -c "
import json, sys
try:
    with open('$state_file') as f:
        data = json.load(f)
    for task in data.get('queue', []):
        if task.get('status') == 'pending':
            print(json.dumps(task, indent=2))
            sys.exit(0)
    print('null')
except Exception as e:
    print('null')
    sys.exit(1)
"
}

# Function to create new task
create_task() {
    local prompt_file="$1"
    local tool_whitelist="$2"
    local custom_id="$3"
    
    # Generate task ID
    local generated_id
    generated_id=$(generate_task_id "$custom_id")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Get prompt preview (first 100 characters)
    local prompt_preview=""
    if [ -f "$prompt_file" ]; then
        prompt_preview=$(head -c 100 "$prompt_file" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
        if [ ${#prompt_preview} -eq 100 ]; then
            prompt_preview="${prompt_preview}..."
        fi
    fi
    
    local state_file="$HOME/state.json"
    init_state_file
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Create task object
    local task_json
    task_json=$(cat << EOF
{
  "id": "$generated_id",
  "status": "pending",
  "created": "$timestamp",
  "updated": "$timestamp",
  "promptFile": "$prompt_file",
  "promptPreview": "$prompt_preview",
  "toolWhitelist": "$tool_whitelist",
  "sessionId": null,
  "retryCount": 0,
  "metadata": {
    "source": "cli",
    "priority": 1
  }
}
EOF
)
    
    # Add task to queue using Python
    python3 << EOF
import json
import sys

try:
    with open('$state_file', 'r') as f:
        data = json.load(f)
    
    # Parse task JSON
    task_data = json.loads('''$task_json''')
    
    # Add new task to queue
    data['queue'].append(task_data)
    
    with open('$state_file', 'w') as f:
        json.dump(data, f, indent=2)
    
    print('$generated_id')
except Exception as e:
    print(f"Error creating task: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    if [ $? -eq 0 ]; then
        print_success "Created task: $generated_id"
        echo "$generated_id"
    else
        print_error "Failed to create task"
        return 1
    fi
}

# Function to update task status
update_task_status() {
    local task_id="$1"
    local new_status="$2"
    local session_id="$3"  # Optional
    
    if [ -z "$task_id" ] || [ -z "$new_status" ]; then
        print_error "Task ID and status are required"
        return 1
    fi
    
    # Validate status
    case "$new_status" in
        pending|in_progress|completed|failed)
            ;;
        *)
            print_error "Invalid status: $new_status. Must be: pending, in_progress, completed, or failed"
            return 1
            ;;
    esac
    
    local state_file="$HOME/state.json"
    init_state_file
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Update task using Python
    python3 << EOF
import json
import sys

try:
    with open('$state_file', 'r') as f:
        data = json.load(f)
    
    task_found = False
    # First check queue
    for task in data['queue']:
        if task['id'] == '$task_id':
            task['status'] = '$new_status'
            task['updated'] = '$timestamp'
            if '$session_id':
                task['sessionId'] = '$session_id'
            task_found = True
            break
    
    # If not found in queue, check history (for completed tasks being re-updated)
    if not task_found:
        for task in data.get('history', []):
            if task['id'] == '$task_id':
                task['status'] = '$new_status'
                task['updated'] = '$timestamp'
                if '$session_id':
                    task['sessionId'] = '$session_id'
                task_found = True
                break
    
    if not task_found:
        print(f"Task not found in queue or history: $task_id", file=sys.stderr)
        sys.exit(1)
    
    # Update current task pointer
    if '$new_status' == 'in_progress':
        data['currentTask'] = '$task_id'
    elif '$new_status' in ['completed', 'failed']:
        if data.get('currentTask') == '$task_id':
            data['currentTask'] = None
        # Move to history
        for i, task in enumerate(data['queue']):
            if task['id'] == '$task_id':
                data['history'].append(data['queue'].pop(i))
                break
    
    with open('$state_file', 'w') as f:
        json.dump(data, f, indent=2)
    
    print('success')
except Exception as e:
    print(f"Error updating task: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    if [ $? -eq 0 ]; then
        print_success "Updated task $task_id status to: $new_status"
    else
        print_error "Failed to update task status"
        return 1
    fi
}

# Function to get queue status
get_queue_status() {
    local state_file="$HOME/state.json"
    init_state_file
    
    python3 -c "
import json
try:
    with open('$state_file') as f:
        data = json.load(f)
    
    queue = data.get('queue', [])
    current_task = data.get('currentTask')
    
    pending_count = len([t for t in queue if t.get('status') == 'pending'])
    in_progress_count = len([t for t in queue if t.get('status') == 'in_progress'])
    
    print(f'Current task: {current_task or \"None\"}')
    print(f'Pending tasks: {pending_count}')
    print(f'In progress tasks: {in_progress_count}')
    print(f'Total queued tasks: {len(queue)}')
    print(f'History count: {len(data.get(\"history\", []))}')
except Exception as e:
    print(f'Error reading queue status: {e}')
"
}

# Function to cleanup old completed tasks from history
cleanup_history() {
    local max_history="${1:-50}"  # Default to keeping last 50 completed tasks
    
    local state_file="$HOME/state.json"
    init_state_file
    
    python3 << EOF
import json
import sys

try:
    with open('$state_file', 'r') as f:
        data = json.load(f)
    
    history = data.get('history', [])
    if len(history) > $max_history:
        # Keep only the most recent entries
        data['history'] = history[-$max_history:]
        
        with open('$state_file', 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f'Cleaned up history, kept {len(data["history"])} most recent tasks')
    else:
        print(f'History size ({len(history)}) within limit ({$max_history})')
        
except Exception as e:
    print(f"Error cleaning up history: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        init)
            init_state_file
            ;;
        validate)
            validate_state_file
            ;;
        status)
            get_queue_status
            ;;
        current)
            get_current_task
            ;;
        next)
            get_next_pending_task
            ;;
        create)
            create_task "$2" "$3" "$4" "$5"
            ;;
        update)
            update_task_status "$2" "$3" "$4"
            ;;
        cleanup)
            cleanup_history "$2"
            ;;
        read)
            read_state
            ;;
        help|*)
            echo "Usage: $0 {init|validate|status|current|next|create|update|cleanup|read|help}"
            echo ""
            echo "Commands:"
            echo "  init                              Initialize state file"
            echo "  validate                          Validate state file format"
            echo "  status                            Show queue status summary"
            echo "  current                           Get current task details"
            echo "  next                              Get next pending task"
            echo "  create <prompt_file> <tools> [id] Create new task"
            echo "  update <task_id> <status> [session] Update task status"
            echo "  cleanup [max_history]             Clean up old history entries"
            echo "  read                              Read entire state file"
            echo "  help                              Show this help"
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi