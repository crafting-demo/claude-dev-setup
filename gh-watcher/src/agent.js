import { exec } from 'node:child_process';
import { mkdtempSync, unlinkSync, writeFileSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join as joinPath } from 'node:path';
import {
  CMD_DIR,
  GITHUB_TOKEN,
  SANDBOX_DEF_PATH,
  SANDBOX_TEMPLATE_NAME,
  TOOL_WHITELIST_JSON,
  USE_SANDBOX_POOL,
  SANDBOX_POOL_NAME,
} from './config.js';
import { octokit } from './github.js';

function execCommand(command, timeoutMs) {
  return new Promise((resolve, reject) => {
    const child = exec(command, { timeout: timeoutMs });
    child.stdout.on('data', (data) => process.stdout.write(data));
    child.stderr.on('data', (data) => process.stderr.write(data));
    child.on('close', (code) => {
      if (code === 0) {
        resolve({ code });
      } else {
        reject(new Error(`Command failed with exit code: ${code}`));
      }
    });
    child.on('error', (error) => reject(error));
  });
}

async function transferContent(sandboxName, targetPath, content) {
  const tempDir = mkdtempSync(joinPath(tmpdir(), 'gh-watcher-'));
  const tempFile = joinPath(tempDir, 'payload.txt');
  writeFileSync(tempFile, content, 'utf8');
  const scpCmd = `cs scp ${tempFile} ${sandboxName}:${targetPath}`;
  try {
    await execCommand(scpCmd, 30000);
  } finally {
    try {
      unlinkSync(tempFile);
    } catch (err) {
      console.warn(`Failed to remove temp file: ${err.message}`);
    }
    try {
      rmdirSync(tempDir);
    } catch (err) {
      console.warn(`Failed to remove temp dir: ${err.message}`);
    }
  }
}

export async function runDevAgent(payload, options) {
  const { owner, repo, kind, prompt, issueNumber, prNumber, prUrl, prHeadRef } = payload;
  const { dryRun, verbose, debug } = options;

  // Create a unique sandbox name that is less than 20 chars
  const repoName = repo.split('/')[1] || 'repo';
  const timestamp = Date.now().toString().slice(-4);
  const itemNumber = issueNumber || prNumber;
  const sandboxName = `cw-${repoName.substring(0,8)}-${itemNumber}-${timestamp}`.substring(0, 20);

  // Determine if the worker should be destroyed after completion
  const shouldDelete = debug ? 'false' : 'true';

  // Build command template based on template source
  const templateArg = SANDBOX_TEMPLATE_NAME
    ? `-t ${SANDBOX_TEMPLATE_NAME}`
    : `--from def:${SANDBOX_DEF_PATH}`;
  const baseCreateCmd = `cs sandbox create \${sandboxName} ${templateArg}`;
  const poolOption = USE_SANDBOX_POOL === 1 ? ` --use-pool \${poolName}` : '';
  const envVars = ` \\
  -D 'claude/env[GITHUB_REPO]=\${owner}/\${repo}' \\
  -D 'claude/env[GITHUB_BRANCH]=\${prHeadRef}' \\
  -D 'claude/env[GITHUB_TOKEN]=\${GITHUB_TOKEN}' \\
  -D 'claude/env[ACTION_TYPE]=\${kind}' \\
  -D 'claude/env[PR_NUMBER]=\${prNumber}' \\
  -D 'claude/env[PR_URL]=\${prUrl}' \\
  -D 'claude/env[SHOULD_DELETE]=\${shouldDelete}' \\
  -D 'claude/env[ANTHROPIC_API_KEY]=\${secret:shared/anthropic-apikey-eng}'`;
  
  const commandTemplate = baseCreateCmd + poolOption + envVars;

  const cmd = commandTemplate
    .replace(/\${sandboxName}/g, sandboxName)
    .replace(/\${poolName}/g, SANDBOX_POOL_NAME)
    .replace(/\${owner}/g, owner)
    .replace(/\${repo}/g, repo)
    .replace(/\${kind}/g, kind)
    .replace(/\${prNumber}/g, prNumber || '')
    .replace(/\${prUrl}/g, prUrl || '')
    .replace(/\${prHeadRef}/g, prHeadRef || '')
    .replace(/\${shouldDelete}/g, shouldDelete)
    .replace(/\${GITHUB_TOKEN}/g, GITHUB_TOKEN);

  console.log(`[${dryRun ? 'DRY RUN' : 'ACTION'}] Dev agent command prepared.`);
  if (verbose) console.log(`[${dryRun ? 'DRY RUN' : 'ACTION'}] > ${cmd}`);

  if (dryRun) return;

  try {
    console.log(`Executing sandbox creation command for ${kind} #${itemNumber}...`);
    
    // Wait for sandbox creation to complete with real-time output streaming
    await execCommand(cmd, 120000);

    console.log(`Sandbox is ready for ${kind} #${itemNumber}, proceeding with file transfer and execution...`);

    // Extract sandbox name from the create command for subsequent operations
    const extractedSandboxName = sandboxName; // We already have it from the command template

    const cmdDir = CMD_DIR || '/home/owner/cmd';
    await transferContent(extractedSandboxName, `${cmdDir}/prompt.txt`, prompt);
    await transferContent(extractedSandboxName, `${cmdDir}/prompt_filename.txt`, 'prompt.txt');
    await transferContent(extractedSandboxName, `${cmdDir}/task_mode.txt`, 'create');
    await transferContent(extractedSandboxName, `${cmdDir}/task_id.txt`, `pr-${itemNumber}`);
    await transferContent(extractedSandboxName, `${cmdDir}/github_repo.txt`, `${owner}/${repo}`);
    await transferContent(extractedSandboxName, `${cmdDir}/github_token.txt`, GITHUB_TOKEN);
    await transferContent(extractedSandboxName, `${cmdDir}/github_branch.txt`, prHeadRef || '');
    await transferContent(extractedSandboxName, `${cmdDir}/tool_whitelist.txt`, TOOL_WHITELIST_JSON);

    // Execute start-worker.sh in the sandbox
    const execCmd = `cs exec -t -u 1000 -W ${extractedSandboxName}/claude -- bash -i -c '~/claude/dev-worker/start-worker.sh'`;
    console.log(`Firing off worker initialization: ${execCmd}`);
    
    if (debug) {
      // In debug mode, wait for completion and show all output
      console.log(`DEBUG MODE: Waiting for worker initialization to complete...`);
      await new Promise((resolve, reject) => {
        const child = exec(execCmd);
        child.stdout.on('data', (data) => { process.stdout.write(data); });
        child.stderr.on('data', (data) => { process.stderr.write(data); });
        child.on('close', (code) => {
          if (code === 0) {
            console.log(`\nWorker initialization completed successfully for ${kind} #${itemNumber}`);
            resolve({ code });
          } else {
            console.error(`\nWorker initialization failed for ${kind} #${itemNumber} with exit code: ${code}`);
            reject(new Error(`Worker initialization failed with exit code: ${code}`));
          }
        });
        child.on('error', (error) => {
          console.error(`\nWorker initialization failed for ${kind} #${itemNumber}: ${error.message}`);
          reject(error);
        });
      });
      const resultMessage = `🚀 PR review sandbox created and worker started for #${itemNumber}. Processing in background...`;
      await octokit.issues.createComment({
        owner,
        repo,
        issue_number: itemNumber,
        body: resultMessage,
      });
      console.log(`Posted success comment to #${itemNumber}. Worker initialization running in background.`);
    } else {
      // In non-debug mode, fire and forget (do not wait for logs)
      console.log(`Non-debug mode: launching worker in background with setsid nohup.`);
      const logFile = `./worker-${sandboxName}-${Date.now()}.log`;
      const backgroundCmd = `setsid nohup ${execCmd} >${logFile} 2>&1 &`;
      console.log(`Background command: ${backgroundCmd}`);
      console.log(`Logs will be written to: ${logFile}`);
      exec(backgroundCmd);
      const resultMessage = `🚀 PR review sandbox created and worker started for #${itemNumber}. Processing in background...`;
      await octokit.issues.createComment({
        owner,
        repo,
        issue_number: itemNumber,
        body: resultMessage,
      });
      console.log(`Posted success comment to #${itemNumber}. Worker initialization running in background.`);
    }

  } catch (error) {
    const resultMessage = `❌ Dev agent sandbox creation failed for ${kind} #${itemNumber}: ${error.message}`;
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
