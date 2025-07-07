# Setup

1. In your Crafting dashboard, create a new template named `claude-code-automation` using the `template.yaml` file in `claude-code-automation` directory. 
2. Create the dev agent orchestrator sandbox from scratch. Make sure to properly configure your own `ANTHROPIC_API_KEY` secret path for the the ENV. Alternatively, if you wish to use Claude models running within GCP, follow the instructions below for Vertex AI.
3. Clone this repo.
4. Go to GitHub and generate a Personal Access Token (PAT) for the repos you would like your dev agent to have access to. Make sure it has access to Actions, Contents, Issues, Pull Requests. Set the PAT as the `GITHUB_TOKEN` env var
5. In `claude-dev-setup/gh-watcher/watchlist.txt`, add all the repos you want your dev agent to monitor. One per line. Ex. `crafting-test1/claude_test`.
6. In `claude-dev-setup/gh-watcher`, run `npm install`
7. Set the trigger phrase you would like to monitor for in the comments of your GitHub issues and Pull Requests. Edit `claude-dev-setup/gh-watcher/src/config.js` or using env var `TRIGGER_PHRASE`. Ex. `@crafting-code`
8. In `claude-dev-setup/gh-watcher`, run `npm run watch` to perform a single a poll of the repos specified in your watchlist.

Once a comment is found in a PR or issues containing the trigger phase, your orchestrator sandbox will spin up a worker sandbox using the `claude-code-automation` template, which will take the following steps.
1. Install Claude Code, configured with your API Key (passed in from the Orchestrator as an env var), and give permissions for tool use.
2. Clone the target repo
3. If the comment was on an issue, it will cut a new branch related to that issue. If the comment was on a PR, it will switch to that branch.
4. Fire up Claude Code, and create a prompt from the full GitHub context. For a PR comment it will use the context of the comment + file name + line number (if specified). For an issue, it will use the context of the issue name, body and triggering comment.
5. After Claude Code completes the work, it will commit changes and then: If Issue: Create a PR with a description of changes, or, if PR comment, push changes to the branch and leave a comment about updates.
6. After changes are made, the action is logged is in `gh-watcher/state.json` so that work is not re-triggered in subsequent runs.
7. If the orchestrator is not in debug mode, the dev worker will be destroyed upon completing it's task.

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



To do:
- Debug mode in watcher should: 1. Make sure should destroy flag passed into workers is false. 2. Make sure the watcher stays connected to the workers so progress is visible (which is how it's currently configured). When debug mode is disabled, it should not stay connected to the worker after the command is executed successfully so it doens't get blocked on the log running `initialize_worker.sh` script.

- Include instructions on how to get this to run as a repeating timed job in a pinned sandbox.