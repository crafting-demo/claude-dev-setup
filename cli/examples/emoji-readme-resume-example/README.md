# Emoji README Resume Example

This example demonstrates the task resumption and queue system for Claude Code automation workflows. It shows how to:

1. **Create an initial sandbox** with task management
2. **Resume an existing sandbox** with follow-up tasks  
3. **Use different tool sets** for different tasks
4. **Manage task queues** and state persistence
5. **Maintain session continuity** across task transitions

## Workflow Overview

The example consists of two tasks that work together:

### Task 1: Emoji Enhancement
- **Goal**: Enhance README.md with emojis and visual improvements
- **Agent**: `emoji_enhancer`
- **Tools**: Standard tools + emoji_enhancer MCP tool
- **Action**: Creates initial sandbox and first task in queue

### Task 2: Badges and Structure  
- **Goal**: Add professional badges and improve document structure
- **Agents**: `badge_generator`, `structure_organizer`
- **Tools**: Standard tools + badge_generator + structure_organizer MCP tools
- **Action**: Resumes existing sandbox with different tool set

## Files Structure

```
emoji-readme-resume-example/
├── README.md                           # This documentation
├── task1-emoji-enhancement.txt         # Initial task prompt
├── task2-badges-and-structure.txt      # Follow-up task prompt  
├── agents/                             # Agent definitions
│   ├── emoji_enhancer.json            # Task 1 agent
│   ├── badge_generator.json           # Task 2 agent
│   └── structure_organizer.json       # Task 2 agent
├── tool-whitelist.json                 # Task 1 tools
├── task2-tools.json                    # Task 2 tools
├── run-task1-initial.sh               # Execute initial task
├── run-task2-followup.sh              # Execute follow-up task
└── run-complete-workflow.sh           # Complete workflow demo
```

## Prerequisites

Before running any scripts, you need to set the required environment variables:

```bash
export GITHUB_TOKEN="your_github_token_here"
export ANTHROPIC_API_KEY="your_anthropic_api_key_here"
```

**Note**: Sandbox names are limited to 20 characters, so the generated names follow the format `emoji-MMDDHHMM`.

## Usage

### Option 1: Complete Workflow (Recommended)

Run the complete workflow demonstration:

```bash
GITHUB_TOKEN="your_token" ANTHROPIC_API_KEY="your_key" ./run-complete-workflow.sh
```

This will:
1. Execute Task 1 (emoji enhancement) automatically
2. Execute Task 2 (badges and structure) automatically
3. Show final results and task state

### Option 2: Step-by-Step Execution

#### Step 1: Execute Initial Task
```bash
GITHUB_TOKEN="your_token" ANTHROPIC_API_KEY="your_key" ./run-task1-initial.sh
```

This creates a sandbox with a name like `emoji-08071410` and executes the first task.

#### Step 2: Execute Follow-up Task
```bash
GITHUB_TOKEN="your_token" ANTHROPIC_API_KEY="your_key" ./run-task2-followup.sh <sandbox_name>
```

Replace `<sandbox_name>` with the name from Step 1. This resumes the existing sandbox with a new task.

### Option 3: Manual cs-cc Commands

#### Initial Task:
```bash
../../cs-cc \
    -p task1-emoji-enhancement.txt \
    -r "crafting-test1/claude_test" \
    -ght "your_github_token" \
    -b main \
    -ad agents \
    -t tool-whitelist.json \
    -tid "emoji-enhancement-task" \
    -n "my-emoji-sandbox" \
    -d no \
    --debug yes
```

#### Follow-up Task:
```bash
../../cs-cc \
    --resume "my-emoji-sandbox" \
    -p task2-badges-and-structure.txt \
    -ght "your_github_token" \
    -ad agents \
    -t task2-tools.json \
    -tid "badges-structure-task" \
    --debug yes
```

## Key Features Demonstrated

### 🔄 Task Resumption
- `--resume <sandbox_name>` flag skips sandbox creation
- Existing Claude session is maintained
- Repository state is preserved

### 📋 Task Queue Management
- Tasks are tracked in `~/state.json`
- Queue status can be checked with `task-state-manager.sh status`
- Automatic progression through pending tasks

### 🔧 Dynamic Tool Updates
- Different tool whitelists for different tasks
- Tool permissions updated automatically when resuming
- MCP agents can be different between tasks

### 📊 State Persistence
- Task state tracked with timestamps and status
- Session IDs correlated with tasks
- Complete task history maintained

## Debugging and Monitoring

### Check Task State
```bash
# View current task queue status
../../../dev-worker/task-state-manager.sh status

# View complete state file
../../../dev-worker/task-state-manager.sh read

# View current task details
../../../dev-worker/task-state-manager.sh current
```

### Check Sandbox State
```bash
# List sandbox files
cs exec -u 1000 -W <sandbox_name>/claude -- ls -la

# Check task files
cs exec -u 1000 -W <sandbox_name>/claude -- ls -la /home/owner/cmd/

# View task state in sandbox
cs exec -u 1000 -W <sandbox_name>/claude -- cat /home/owner/state.json
```

## Expected Results

After running the complete workflow:

1. **Task 1** enhances the README with emojis and creates a PR
2. **Task 2** adds badges and improves structure on the same branch
3. **Final result**: A comprehensive README improvement with both emoji enhancements and professional badges
4. **Task queue**: Shows completed tasks and maintains history

This demonstrates a realistic multi-step documentation improvement workflow that would be common in real development scenarios.