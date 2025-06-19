import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import { execSync } from 'node:child_process';
import { scanIssues } from './issue-scan.js';
import { scanPRs } from './pr-scan.js';
import { loadState, saveState } from './state.js';

const argv = yargs(hideBin(process.argv))
  .option('dry-run', {
    alias: 'd',
    type: 'boolean',
    description: 'Run without executing actions or posting comments',
    default: false,
  })
  .option('verbose', {
    alias: 'v',
    type: 'boolean',
    description: 'Run with verbose logging',
    default: false,
  })
  .help()
  .alias('help', 'h')
  .argv;

async function main() {
  if (argv.verbose) {
    console.log('Verbose mode enabled.');
    console.log('Options:', argv);
  }

  try {
    console.log('Starting GitHub watcher...');
    
    console.log('Authenticating with sandbox service...');
    execSync('cs login');
    console.log('Authentication successful.');

    const state = loadState();

    const issuesChanged = await scanIssues(argv, state);
    const prsChanged = await scanPRs(argv, state);

    if (issuesChanged || prsChanged) {
        saveState(state);
        console.log('State updated.');
    } else {
        console.log('No new comments to process.');
    }

    console.log('GitHub watcher run completed.');
  } catch (error) {
    console.error('An error occurred during watcher run:', error);
    process.exit(1);
  }
}

main(); 