import { exec } from 'node:child_process';
import { GITHUB_TOKEN, TRIGGER_PHRASE } from './config.js';
import { octokit } from './github.js';

export async function runDevAgent(payload, options) {
  const { owner, repo, kind, prompt, issueNumber, prNumber, filePath, lineNumber } = payload;
  const { dryRun, verbose } = options;

  // Create a unique sandbox name that is less than 20 chars
  const repoName = repo.split('/')[1] || 'repo';
  const timestamp = Date.now().toString().slice(-4);
  const itemNumber = issueNumber || prNumber;
  const sandboxName = `cw-${repoName.substring(0,8)}-${itemNumber}-${timestamp}`.substring(0, 20);

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
  const escapedPrompt = prompt
    .replace(/\\/g, '\\\\')  // Escape backslashes first
    .replace(/'/g, "'\\''")  // Escape single quotes
    .replace(/\n/g, '\\n')   // Escape newlines
    .replace(/\r/g, '\\r')   // Escape carriage returns
    .replace(/\t/g, '\\t')   // Escape tabs
    .replace(/\$/g, '\\$');  // Escape dollar signs

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
    // Fire off the command and return immediately - don't wait for completion
    const child = exec(cmd, (error, stdout, stderr) => {
      // This callback will run eventually, but we don't wait for it
      if (error) {
        console.error(`Sandbox creation failed for ${kind} #${itemNumber}: ${error.message}`);
      } else if (verbose) {
        console.log(`Sandbox stdout: ${stdout}`);
        if (stderr) console.error(`Sandbox stderr: ${stderr}`);
      }
    });

    // Detach the process so it continues running after we return
    child.unref();

    const resultMessage = `🚀 Dev agent sandbox creation initiated for ${kind} #${itemNumber}. Check the sandbox list for status.`;
    await octokit.issues.createComment({
      owner,
      repo,
      issue_number: itemNumber,
      body: resultMessage,
    });
    console.log(`Posted initiation comment to #${itemNumber}. Sandbox creation running in background.`);

  } catch (error) {
    const resultMessage = `❌ Dev agent failed to start for ${kind} #${itemNumber}.`;
    await octokit.issues.createComment({
        owner,
        repo,
        issue_number: itemNumber,
        body: resultMessage,
    });
    console.log(`Posted failure comment to #${itemNumber}.`);
    throw error;
  }
}
