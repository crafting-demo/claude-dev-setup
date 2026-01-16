import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
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
  .option('debug', {
    type: 'boolean',
    description: 'Wait for worker initialization and show all output',
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

    const state = loadState();

    const prsChanged = await scanPRs(argv, state);

    if (prsChanged) {
        saveState(state);
        console.log('State updated.');
    } else {
        console.log('No new PRs to process.');
    }

    console.log('GitHub watcher run completed.');
    process.exit(0);
  } catch (error) {
    console.error('An error occurred during watcher run:', error);
    process.exit(1);
  }
}

main(); 