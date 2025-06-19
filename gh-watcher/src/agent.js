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
    console.log(`Executing sandbox creation command synchronously for ${kind} #${itemNumber}...`);
    
    // Wait for sandbox creation to complete
    await new Promise((resolve, reject) => {
      const child = exec(cmd, { timeout: 120000 }, (error, stdout, stderr) => {
        if (error) {
          console.error(`Sandbox creation failed for ${kind} #${itemNumber}: ${error.message}`);
          if (stdout) console.log(`Sandbox stdout: ${stdout}`);
          if (stderr) console.error(`Sandbox stderr: ${stderr}`);
          reject(error);
          return;
        }
        
        // Always surface output for debugging
        console.log(`Sandbox creation completed successfully for ${kind} #${itemNumber}`);
        if (stdout) console.log(`Sandbox stdout: ${stdout}`);
        if (stderr) console.log(`Sandbox stderr: ${stderr}`);
        
        resolve({ stdout, stderr });
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
      exec(scpCmd, { timeout: 30000 }, (error, stdout, stderr) => {
        if (error) {
          console.error(`File transfer failed for ${kind} #${itemNumber}: ${error.message}`);
          if (stdout) console.log(`SCP stdout: ${stdout}`);
          if (stderr) console.error(`SCP stderr: ${stderr}`);
          reject(error);
          return;
        }
        
        console.log(`File transfer completed successfully for ${kind} #${itemNumber}`);
        if (stdout) console.log(`SCP stdout: ${stdout}`);
        if (stderr) console.log(`SCP stderr: ${stderr}`);
        
        resolve({ stdout, stderr });
      });
    });

    // Clean up local prompt file
    try {
      unlinkSync(promptFilePath);
      console.log(`Cleaned up local prompt file: ${promptFilePath}`);
    } catch (err) {
      console.warn(`Failed to clean up prompt file: ${err.message}`);
    }

    // Transfer dev-worker scripts to the sandbox
    const devWorkerCopyCmd = `cs scp -r ./dev-worker ${extractedSandboxName}:/home/owner/claude/`;
    console.log(`Transferring dev-worker scripts: ${devWorkerCopyCmd}`);
    
    await new Promise((resolve, reject) => {
      exec(devWorkerCopyCmd, { timeout: 30000 }, (error, stdout, stderr) => {
        if (error) {
          console.error(`Dev-worker transfer failed for ${kind} #${itemNumber}: ${error.message}`);
          if (stdout) console.log(`Dev-worker SCP stdout: ${stdout}`);
          if (stderr) console.error(`Dev-worker SCP stderr: ${stderr}`);
          reject(error);
          return;
        }
        
        console.log(`Dev-worker scripts transferred successfully for ${kind} #${itemNumber}`);
        if (stdout) console.log(`Dev-worker SCP stdout: ${stdout}`);
        if (stderr) console.log(`Dev-worker SCP stderr: ${stderr}`);
        
        resolve({ stdout, stderr });
      });
    });

    // Execute initialize_worker.sh in the sandbox
    const execCmd = `cs exec -W ${extractedSandboxName}/claude -- ~/claude/dev-worker/initialize_worker.sh`;
    console.log(`Firing off worker initialization: ${execCmd}`);
    
    if (options.debug) {
      console.log(`DEBUG MODE: Waiting for worker initialization to complete...`);
      
      // In debug mode, wait for completion and show all output
      await new Promise((resolve, reject) => {
        const child = exec(execCmd, { timeout: 600000 }, (error, stdout, stderr) => {
          if (error) {
            console.error(`Worker initialization failed for ${kind} #${itemNumber}: ${error.message}`);
            if (stdout) console.log(`Worker stdout:\n${stdout}`);
            if (stderr) console.error(`Worker stderr:\n${stderr}`);
            reject(error);
            return;
          }
          
          console.log(`Worker initialization completed for ${kind} #${itemNumber}`);
          if (stdout) console.log(`Worker stdout:\n${stdout}`);
          if (stderr) console.log(`Worker stderr:\n${stderr}`);
          resolve({ stdout, stderr });
        });
        
        // 10 minute timeout for debug mode
        setTimeout(() => {
          child.kill();
          reject(new Error('Worker initialization timed out after 10 minutes'));
        }, 600000);
      });
      
      console.log(`DEBUG: Worker initialization completed successfully`);
      
    } else {
      // Normal mode: fire and forget
      const child = exec(execCmd, { 
        detached: true,
        stdio: 'ignore'
      }, (error, stdout, stderr) => {
        // This callback will run eventually, but we don't wait for it
        if (error) {
          console.error(`Worker initialization failed for ${kind} #${itemNumber}: ${error.message}`);
        } else {
          console.log(`Worker initialization completed for ${kind} #${itemNumber}`);
        }
        if (stdout) console.log(`Worker stdout: ${stdout}`);
        if (stderr) console.log(`Worker stderr: ${stderr}`);
      });

      // Completely detach the process so it continues running independently
      child.unref();
      console.log(`Worker initialization started in background for ${kind} #${itemNumber}`);
    }

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
