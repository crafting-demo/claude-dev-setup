import { exec } from 'node:child_process';
import { GITHUB_TOKEN } from './config.js';
import { octokit } from './github.js';

export async function runDevAgent(payload, options) {
  const { owner, repo, kind, prompt, issueNumber, prNumber, filePath, lineNumber } = payload;
  const { dryRun, verbose } = options;

  // Create a unique sandbox name
  const repoName = repo.split('/')[1];
  const timestamp = Date.now().toString().slice(-6);
  const sandboxName = `cw-${repoName}-${issueNumber}-${timestamp}`;

  // Hardcoded command template
  const commandTemplate = `cs sandbox create \${sandboxName} \\
  -t claude-code-automation \\
  -D 'claude/env[GITHUB_REPO]=\${owner}/\${repo}' \\
  -D 'claude/env[CLAUDE_PROMPT]=\${prompt}' \\
  -D 'claude/env[GITHUB_TOKEN]=\${GITHUB_TOKEN}' \\
  -D 'claude/env[ACTION_TYPE]=\${kind}' \\
  -D 'claude/env[PR_NUMBER]=\${prNumber}' \\
  -D 'claude/env[FILE_PATH]=\${filePath}' \\
  -D 'claude/env[LINE_NUMBER]=\${lineNumber}' \\
  -D 'claude/env[ANTHROPIC_API_KEY]=\${secret:shared/anthropic-apikey-eng}'`;

  // Escape the prompt to handle special characters in the shell
  const escapedPrompt = prompt.replace(/'/g, "'\\''");

  const cmd = commandTemplate
    .replace(/\${sandboxName}/g, sandboxName)
    .replace(/\${owner}/g, owner)
    .replace(/\${repo}/g, repo)
    .replace(/\${prompt}/g, escapedPrompt)
    .replace(/\${kind}/g, kind)
    .replace(/\${prNumber}/g, prNumber || '')
    .replace(/\${filePath}/g, filePath || '')
    .replace(/\${lineNumber}/g, lineNumber || '')
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