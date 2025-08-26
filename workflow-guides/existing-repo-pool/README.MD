# Using cs-cc with an existing repo in a sandbox pool

This guide explains how to use cs-cc to delegate tasks to Claude Code dev agents that run within a sandbox claimed from a sandbox pool.

## Prerequisites

1. Add the `claude-dev-setup` checkout to your sandbox pool template to ensure that the worker scripts cs-cc relies on will be properly configured within your target workspace. We'll refer to this as `sb-pool-template` and the pool that uses it as `sb-pool`.
```
workspaces:
  - name: ai-ws
    # 1. Add checkout below to setup claude code worker
    checkouts:
      - path: claude
        repo:
          git: git@github.com:crafting-demo/claude-dev-setup.git
        version_spec: multi-agent
        manifest:
          overlays:
            - file: dev-worker/.sandbox/manifest.yaml
      - path: existing-repo # An existing repo checkout
        repo:
          git: git@github.com:...
    # 2. Ensure you have your ANTHROPIC_API_KEY set
    env:
      - ANTHROPIC_API_KEY=${secret:shared/anthropic-apikey-eng}
    # 3. (OPTIONAL) Define a completion script for the dev worker to call once it's finished.
    system:
      files:
        - path: /home/owner/completion.sh
          mode: "0755"
          overwrite: true
          content: |
            #!/bin/bash

            # Check if TASK_ID parameter is provided
            if [ $# -eq 0 ]; then
                echo "Error: TASK_ID parameter is required"
                echo "Usage: $0 TASK_ID"
                exit 1
            fi

            TASK_ID="$1"

            echo "Marking task as completed"
            echo "Task ID: $TASK_ID"
```

2. Set up the **host sandbox**. This is the sandbox that will use `cs-cc` to delegate work to 

## Step 1: Install cs-cc on the host sandbox
```bash
install -Dm755 <(curl -L "https://github.com/crafting-demo/claude-dev-setup/releases/download/v0.3.2/cs-cc-linux-amd64") "$HOME/.local/bin/cs-cc"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Step 2: Define the initial task

Create a `prompt.txt` file with your task description in it. Include instructions for what Claude should do, how it shoudl use subagents and, if applicable, how it should use Git to commit or push work. 

<details>
  <summary>Task example</summary>

<pre>
You need to enhance the README.md file in this repository by adding emojis and improving its visual appeal.

**TASK DEFINITION:**
Make the README.md more engaging and visually appealing by adding appropriate emojis and improving formatting. The goal is to make the documentation more friendly and easier to scan while maintaining professionalism.

**REQUIREMENTS:**
- Add relevant emojis to section headers
- Include emojis for key features, benefits, or action items  
- Improve formatting for better readability
- Make the content more engaging without being excessive
- Keep it professional and appropriate for a technical audience

**AVAILABLE SUBAGENT:**
- **emoji-enhancer** - Native subagent that specializes in adding emojis and visual improvements to documentation

**DELIVERABLES:**
- Enhanced README.md with appropriate emojis
- Improved formatting and visual appeal
- Maintained technical accuracy and professionalism

**APPROACH:**
Use the emoji-enhancer subagent to transform the existing README into a more visually appealing and engaging document. Focus on making it easier to scan and more inviting to read.

**COMMIT POLICY (MANDATORY):**
- After ANY change is applied by you or any subagent, immediately commit the change before proceeding.
- Use:
  <code>bash
  git add -A
  git commit -m "docs: incremental README enhancement (describe specific change)"
  </code>
- Do not leave the working tree dirty between steps.

**COMPLETION REQUIREMENTS:**
Once you have successfully enhanced the README with emojis and visual improvements:

1. **Create a new branch** - Use git commands to create a new feature branch for your work:
   <code>bash
   git checkout -b emoji-enhancement-$(date +%s)
   </code>

2. **Commit your changes** - Stage and commit all your work:
   <code>bash
   git add .
   git commit -m "docs: enhance README with emojis and improved formatting"
   </code>

3. **Create Pull Request with Automatic Push** - Use `gh` to handle both pushing and PR creation:
   <code>bash
   gh pr create --title "✅ docs: enhance README with emojis and improved formatting" --body "Enhanced README.md with appropriate emojis and improved formatting for better readability and visual appeal." --base main
   </code>
   
   **Important**: GitHub CLI will automatically push the branch and create the PR without any user interaction.

**IMPORTANT**: The PR title MUST start with the ✅ emoji as the first character.

The pull request should clearly document the visual improvements made to help reviewers understand the enhancements.

Begin enhancing the README with emojis and visual improvements. 
</pre>

</details>

## Step 3: Define agents

Agents can be provided to `cs-cc` by specifying a directory containing markdown definitions of agents, or by defining them within your repository. All agent definitions must follow [Claude Code's subagent file format](https://docs.anthropic.com/en/docs/claude-code/sub-agents#file-format).

### Passing agent definitions 

If you have a directory that contains markdown agent definitions, you can pass those into `cs-cc` to be used by Claude code as **user-level subagents** using the `--agents-dir` flag

### Using agent definitions from your repo

Dev workers spawned from `cs-cc` support the use of Claude Code's native **project-level subagents** defined in the a top-level `.claude/agents` directory inside of your repo.

## Step 4: Define allowed tools
Allowed tools are defined as a JSON array in a file. Example:
```json
[
  "Read",
  "Write",
  "Edit",
  "LS",
  "Grep",
  "Bash"
]
```

## Step 5: Run cs-cc

Note on GitHub auth: A GitHub personal access token (PAT) can optionally be included as a flag. If not included, the dev worker will attempt to use the GitHub app installation token from the target sandbox's credential store.

```bash
cs-cc \
  -p prompt.txt \
  --github-repo "your-org/existing-repo" \
  --github-token "$GITHUB_TOKEN" \
  --repo-path "existing-repo" \
  --template "template-name" \
  --pool "claude-dev-pool" \
  -t "allowed-tools.json" \
  -n "sb-name" \
  --debug yes \
  --workspace "ai-ws" # This must match the workspace name from your template
  ```

## Step 6 (optional): Create a follow up task on the same sandbox
```bash
cs-cc \
  --resume "sb-name" \
  -p prompt2.txt \
  -t "allowed-tools.json" \
  --task-id "badges-structure-task" \
  --debug yes
  --workspace "ai-ws"
  ```
