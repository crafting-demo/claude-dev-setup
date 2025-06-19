import { exec } from 'node:child_process';
import { GITHUB_TOKEN, TRIGGER_PHRASE } from './config.js';
import { octokit } from './github.js';

export async function runDevAgent(payload, options) {
  const { owner, repo, kind, prompt, issueNumber, prNumber, filePath, lineNumber } = payload;
  const { dryRun, verbose } = options;

  // Create a unique sandbox name that is less than 20 chars
  const repoName = repo.split('/')[1] || 'repo';
  const timestamp = Date.now().toString().slice(-4);
  const sandboxName = `cw-${repoName.substring(0,8)}-${issueNumber}-${timestamp}`.substring(0, 20);

  // Hardcoded command template
  const commandTemplate = `cs sandbox create \${sandboxName} \\
  -t claude-code-automation \\
  -D 'claude/env[GITHUB_REPO]=\${owner}/\${repo}' \\
  -D 'claude/env[CLAUDE_PROMPT]=\${prompt}' \\
  -D 'claude/env[GITHUB_TOKEN]=\${GITHUB_TOKEN}' \\
  -D 'claude/env[ACTION_TYPE]=\${kind}' \\
  -D 'claude/env[TRIGGER_PHRASE]=\${triggerPhrase}' \\
  -D 'claude/env[PR_NUMBER]=\${prNumber}' \\
  -D 'claude/env[FILE_PATH]=\${filePath}' \\
  -D 'claude/env[LINE_NUMBER]=\${lineNumber}' \\
  -D 'claude/env[SHOULD_DELETE]=\${shouldDelete}' \\
  -D 'claude/env[ANTHROPIC_API_KEY]=\${secret:shared/anthropic-apikey-eng}'`;

  // Escape the prompt to handle special characters in the shell
  const escapedPrompt = prompt.replace(/'/g, "'\\''");

  const cmd = commandTemplate
    .replace(/\${sandboxName}/g, sandboxName)
    .replace(/\${owner}/g, owner)
    .replace(/\${repo}/g, repo)
    .replace(/\${prompt}/g, escapedPrompt)
    .replace(/\${kind}/g, kind)
    .replace(/\${triggerPhrase}/g, TRIGGER_PHRASE)
    .replace(/\${prNumber}/g, prNumber || '')
    .replace(/\${filePath}/g, filePath || '')
    .replace(/\${lineNumber}/g, lineNumber || '')
    .replace(/\${shouldDelete}/g, 'false')
    .replace(/\${GITHUB_TOKEN}/g, GITHUB_TOKEN);

  console.log(`[${dryRun ? 'DRY RUN' : 'ACTION'}] Dev agent command prepared.`);
  if (verbose) console.log(`[${dryRun ? 'DRY RUN' : 'ACTION'}] > ${cmd}`);

  if (dryRun) return;

  try {
    await new Promise((resolve, reject) => {
      exec(cmd, (error, stdout, stderr) => {
        if (error) {
          console.error(`Dev agent execution failed: ${error.message}`);
          reject(error);
          return;
        }
        if (verbose) {
          console.log(`Dev agent stdout: ${stdout}`);
          console.error(`Dev agent stderr: ${stderr}`);
        }
        resolve();
      });
    });

    const resultMessage = `✅ Dev agent successfully triggered for ${kind} #${issueNumber}.`;
    await octokit.issues.createComment({
      owner,
      repo,
      issue_number: issueNumber,
      body: resultMessage,
    });
    console.log(`Posted success comment to #${issueNumber}.`);

  } catch (error) {
    const resultMessage = `❌ Dev agent failed for ${kind} #${issueNumber}.`;
    await octokit.issues.createComment({
        owner,
        repo,
        issue_number: issueNumber,
        body: resultMessage,
    });
    console.log(`Posted failure comment to #${issueNumber}.`);
  }
}
