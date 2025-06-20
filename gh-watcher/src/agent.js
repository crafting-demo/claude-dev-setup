import { exec } from 'node:child_process';
import { writeFileSync, unlinkSync } from 'node:fs';
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

  // Hardcoded command template (prompt now passed via file, not env var)
  const commandTemplate = `cs sandbox create \${sandboxName} \\
  -t claude-code-automation \\
  -D 'claude/env[GITHUB_REPO]=\${owner}/\${repo}' \\
  -D 'claude/env[GITHUB_TOKEN]=\${GITHUB_TOKEN}' \\
  -D 'claude/env[ACTION_TYPE]=\${kind}' \\
  -D 'claude/env[TRIGGER_PHRASE]=\${triggerPhrase}' \\
  -D 'claude/env[PR_NUMBER]=\${prNumber}' \\
  -D 'claude/env[FILE_PATH]=\${filePath}' \\
  -D 'claude/env[LINE_NUMBER]=\${lineNumber}' \\
  -D 'claude/env[SHOULD_DELETE]=\${shouldDelete}' \\
  -D 'claude/env[ANTHROPIC_API_KEY]=\${secret:shared/anthropic-apikey-eng}'`;

  const cmd = commandTemplate
    .replace(/\${sandboxName}/g, sandboxName)
    .replace(/\${owner}/g, owner)
    .replace(/\${repo}/g, repo)
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
    console.log(`Executing sandbox creation command for ${kind} #${itemNumber}...`);
    
    // Wait for sandbox creation to complete with real-time output streaming
    await new Promise((resolve, reject) => {
      const child = exec(cmd, { timeout: 120000 });
      
      // Stream stdout in real-time
      child.stdout.on('data', (data) => {
        process.stdout.write(data);
      });
      
      // Stream stderr in real-time
      child.stderr.on('data', (data) => {
        process.stderr.write(data);
      });
      
      // Handle completion
      child.on('close', (code) => {
        if (code === 0) {
          console.log(`\nSandbox creation completed successfully for ${kind} #${itemNumber}`);
          resolve({ code });
        } else {
          console.error(`\nSandbox creation failed for ${kind} #${itemNumber} with exit code: ${code}`);
          reject(new Error(`Sandbox creation failed with exit code: ${code}`));
        }
      });
      
      // Handle errors
      child.on('error', (error) => {
        console.error(`\nSandbox creation failed for ${kind} #${itemNumber}: ${error.message}`);
        reject(error);
      });
      
      // Safety timeout (2 minutes)
      setTimeout(() => {
        child.kill();
        reject(new Error('Sandbox creation timed out after 2 minutes'));
      }, 120000);
    });

    console.log(`Sandbox is ready for ${kind} #${itemNumber}, proceeding with file transfer and execution...`);

    // Extract sandbox name from the create command for subsequent operations
    const extractedSandboxName = sandboxName; // We already have it from the command template

    // Create dev_prompt.txt with the complete prompt
    const promptFilePath = './dev_prompt.txt';
    console.log(`Writing prompt to ${promptFilePath} (${prompt.length} characters)`);
    writeFileSync(promptFilePath, prompt, 'utf8');

    // Transfer dev_prompt.txt to the sandbox's claude/claude-workspace directory  
    const scpCmd = `cs scp ${promptFilePath} ${extractedSandboxName}:/home/owner/claude/claude-workspace/dev_prompt.txt`;
    console.log(`Transferring prompt file to sandbox: ${scpCmd}`);
    
    await new Promise((resolve, reject) => {
      const child = exec(scpCmd, { timeout: 30000 });
      
      // Stream output for file transfer (usually minimal but good for debugging)
      child.stdout.on('data', (data) => {
        process.stdout.write(`[SCP] ${data}`);
      });
      
      child.stderr.on('data', (data) => {
        process.stderr.write(`[SCP] ${data}`);
      });
      
      child.on('close', (code) => {
        if (code === 0) {
          console.log(`File transfer completed successfully for ${kind} #${itemNumber}`);
          resolve({ code });
        } else {
          console.error(`File transfer failed for ${kind} #${itemNumber} with exit code: ${code}`);
          reject(new Error(`File transfer failed with exit code: ${code}`));
        }
      });
      
      child.on('error', (error) => {
        console.error(`File transfer failed for ${kind} #${itemNumber}: ${error.message}`);
        reject(error);
      });
    });

    // Clean up local prompt file
    try {
      unlinkSync(promptFilePath);
      console.log(`Cleaned up local prompt file: ${promptFilePath}`);
    } catch (err) {
      console.warn(`Failed to clean up prompt file: ${err.message}`);
    }

        // Execute initialize_worker.sh in the sandbox
    const execCmd = `cs exec -t -u 1000 -W ${extractedSandboxName}/claude -- bash -i -c '~/claude/dev-worker/initialize_worker.sh'`;
    console.log(`Firing off worker initialization: ${execCmd}`);
    
    console.log(`Executing worker initialization with full output visibility...`);
    
    // Always wait for completion and show all output with real-time streaming
    await new Promise((resolve, reject) => {
      const child = exec(execCmd, { timeout: 600000 });
      
      // Stream stdout in real-time
      child.stdout.on('data', (data) => {
        process.stdout.write(data);
      });
      
      // Stream stderr in real-time
      child.stderr.on('data', (data) => {
        process.stderr.write(data);
      });
      
      // Handle completion
      child.on('close', (code) => {
        if (code === 0) {
          console.log(`\nWorker initialization completed successfully for ${kind} #${itemNumber}`);
          resolve({ code });
        } else {
          console.error(`\nWorker initialization failed for ${kind} #${itemNumber} with exit code: ${code}`);
          reject(new Error(`Worker initialization failed with exit code: ${code}`));
        }
      });
      
      // Handle errors
      child.on('error', (error) => {
        console.error(`\nWorker initialization failed for ${kind} #${itemNumber}: ${error.message}`);
        reject(error);
      });
      
      // 10 minute timeout
      setTimeout(() => {
        child.kill();
        reject(new Error('Worker initialization timed out after 10 minutes'));
      }, 600000);
    });

    const resultMessage = `🚀 Dev agent sandbox created, prompt transferred, and worker started for ${kind} #${itemNumber}. Processing in background...`;
    await octokit.issues.createComment({
      owner,
      repo,
      issue_number: itemNumber,
      body: resultMessage,
    });
    console.log(`Posted success comment to #${itemNumber}. Worker initialization running in background.`);

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
