# Claude Code Dev Agent on Crafting

This repo contains everything you need to setup a dev agent that uses Claude Code to interact with issues and PR comments in a GitHub repo.

## Features
- Issues -> PRs. Assign open issues to the dev agent and it will pull down the repo, cut a branch, do the work and open a PR against that issue.
- PR comments -> Branch updates. Tag the dev agent in a PR comment with feedback and it will do the work and push an update to that PR.
- Full support for Claude models on GCP through Vertex AI
- Crafting native. All work happens within ephemeral sandboxes on your Crafting account.

## Demo
<a href="https://www.loom.com/share/9832c4c481794c1d9a707c3c435f1b81">
  <img width="500" alt="Screenshot 2025-07-08 at 1 30 06 PM" src="https://github.com/user-attachments/assets/f15e263c-84e7-4919-b2c9-13ebf8fb93d6" />
</a>


## Sandbox Setup

1. **Create the Claude Code Worker Template** In your Crafting dashboard, create a new template named `claude-code-automation` using the `template.yaml` file in `claude-code-automation` directory. 
2. **Ensure the following Env vars are set** in the sandbox you want the dev agent orchestrator to work within.
- **ANTHROPIC_API_KEY**: A path to your Anthropic API Key stored in a Crafting secret. Alternatively, if you wish to use Claude models running within GCP, follow the instructions below for Vertex AI.
- **GITHUB_TOKEN**: A PAT that will provide the dev agent access to the repo you wan it to work on. To generate one, to GitHub and generate a Personal Access Token (PAT) for the repos you would like your dev agent to have access to. Make sure it has access to Actions, Contents, Issues, Pull Requests.
3. **Update your sandbox YAML** to create a workspace configured for the orchestrator. Add the following under `workspaces`:
```
- name: cc-launcher
    checkouts:
      - path: claude-dev-setup
        repo:
          git: https://github.com/crafting-demo/claude-dev-setup.git
    packages:
      - name: nodejs
        version: 22.14.0 # or some version over 20
    env:
      - SHELL=/bin/bash
      - PATH=/usr/local/go/bin:/usr/local/node/bin:$PATH
```

5. **Add target repos** Inside the cc-launcher workspace, go to `claude-dev-setup/gh-watcher/watchlist.txt` and add all the repos you want your dev agent to monitor. One per line. Ex. `crafting-test1/claude_test`.
7. (optional) **Set the trigger phrase*** you would like to monitor for in the comments of your GitHub issues and Pull Requests. Edit `claude-dev-setup/gh-watcher/src/config.js` or using env var `TRIGGER_PHRASE`. Ex. `@crafting-code`
8. **Pin your sandbox** so the orchestrator timed job can continue to regularly poll GitHub. The default poll time is every 5 minutes, but you can change that in `./sandbox/manifest.yaml`.

## How it works

Once a comment is found in a PR or issues containing the trigger phase (default is **@crafting-code**), the orchestrator will spin up a worker sandbox using the `claude-code-automation` template, which will take the following steps.

1. Install Claude Code, configured with your API Key (passed in from the Orchestrator as an env var), and give permissions for tool use.
2. Clone the target repo
3. If the comment was on an issue, it will cut a new branch related to that issue. If the comment was on a PR, it will switch to that branch.
4. Fire up Claude Code, and create a prompt from the full GitHub context. For a PR comment it will use the context of the comment + file name + line number (if specified). For an issue, it will use the context of the issue name, body and triggering comment.
5. After Claude Code completes the work, it will commit changes and then: If Issue: Create a PR with a description of changes, or, if PR comment, push changes to the branch and leave a comment about updates.
6. After changes are made, the action is logged is in `gh-watcher/state.json` so that work is not re-triggered in subsequent runs.
7. If the orchestrator is not in debug mode, the dev worker will be destroyed upon completing it's task.

## Debug mode
You can run a dev worker synchronously by opening a terminal on the cc-launcher workspace, cd'ing to `claude-dev-setup/gh-watcher` and running `npm run watch -- --debug` to perform a single poll of the repos specified in your watchlist. Note: You will have to manually delete the worker sandbox yourself this way.

## Using Claude models inside of GCP with Vertex AI 

Follow the instructions below to use Verex AI

1. Make sure Vertex AI and Claude models are enabled in your GCP account. Requirements are:
- A Google Cloud Platform (GCP) account with billing enabled
- A GCP project with Vertex AI API enabled
- Access to desired Claude models (e.g., Claude Sonnet 4)
- Quota allocated in desired GCP region

2. Create a GCP service account with roles: `AI Platform Developer` and `Vertex AI User`. 
3. Create a JSON key and add it as a secret in Crafting, ex `gcp-vertex-key.json`
4. Add the following env vars to `claude-code-automation/template.yaml`:
- GOOGLE_APPLICATION_CREDENTIALS=/run/sandbox/fs/secrets/shared/gcp-vertex-key.json
- ANTHROPIC_VERTEX_PROJECT_ID=YOUR-GCP-PROJECT-ID
- CLAUDE_CODE_USE_VERTEX=1
- CLOUD_ML_REGION=us-east5
