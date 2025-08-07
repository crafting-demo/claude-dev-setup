#!/bin/bash

# Emoji README Resume Example - Complete Multi-Task Workflow
# Demonstrates the full task resumption and queue system

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN environment variable is required"
    echo "Usage: GITHUB_TOKEN=your_token_here ANTHROPIC_API_KEY=your_key_here ./run-complete-workflow.sh"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ Error: ANTHROPIC_API_KEY environment variable is required"
    echo "Usage: GITHUB_TOKEN=your_token_here ANTHROPIC_API_KEY=your_key_here ./run-complete-workflow.sh"
    exit 1
fi

echo "🚀 Emoji README Resume Example - Complete Multi-Task Workflow"
echo "============================================================"
echo ""
echo "This example demonstrates:"
echo "  1. Creating initial sandbox with task management"
echo "  2. Resuming existing sandbox with follow-up task"
echo "  3. Different tool sets for different tasks"
echo "  4. Task queue processing and state management"
echo ""

# Generate unique sandbox name for this run (max 20 chars)
SANDBOX_NAME="emoji-$(date +%m%d%H%M)"
echo "📦 Generated sandbox name: $SANDBOX_NAME"
echo ""

# Task 1: Initial emoji enhancement
echo "📋 TASK 1: Initial Emoji Enhancement"
echo "======================================"
echo "- Enhances README with emojis and visual improvements"
echo "- Uses emoji_enhancer agent"
echo "- Creates initial sandbox and task queue"
echo ""

"$SCRIPT_DIR/run-task1-initial.sh"

if [ $? -ne 0 ]; then
    echo "❌ Task 1 failed, aborting workflow"
    exit 1
fi

echo ""
echo "✅ Task 1 completed!"
echo ""

# Task 2: Follow-up badges and structure
echo "📋 TASK 2: Follow-up Badges and Structure"
echo "=========================================="
echo "- Adds professional badges to README"
echo "- Improves document structure and organization"
echo "- Uses badge_generator and structure_organizer agents"
echo "- Resumes existing sandbox with different tools"
echo ""

"$SCRIPT_DIR/run-task2-followup.sh" "$SANDBOX_NAME"

if [ $? -ne 0 ]; then
    echo "❌ Task 2 failed"
    exit 1
fi

echo ""
echo "🎉 WORKFLOW COMPLETE!"
echo "===================="
echo "✅ Both tasks completed successfully"
echo "📦 Sandbox: $SANDBOX_NAME"
echo ""
echo "Summary of what was demonstrated:"
echo "  ✓ Multi-task workflow with task resumption"
echo "  ✓ Different agent sets for different tasks"
echo "  ✓ Task queue management and state persistence"
echo "  ✓ Session continuity across task transitions"
echo "  ✓ Dynamic tool permission updates"
echo ""
echo "💡 Check the sandbox to see the results:"
echo "   cs exec -u 1000 -W $SANDBOX_NAME/claude -- ls -la"
echo ""
echo "🔧 Debug with task state manager:"
echo "   dev-worker/task-state-manager.sh status"
echo "   dev-worker/task-state-manager.sh read"