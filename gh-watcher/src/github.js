import { Octokit } from '@octokit/rest';
import { GITHUB_TOKEN } from './config.js';

if (!GITHUB_TOKEN) {
  console.error('Missing GITHUB_TOKEN or GH_TOKEN. Please set it in your environment.');
  process.exit(1);
}

export const octokit = new Octokit({
  auth: GITHUB_TOKEN,
  userAgent: 'gh-watcher/0.1',
  request: { timeout: 10_000 },
});

octokit.hook.after("request", async (response) => {
  if (response.headers['x-ratelimit-remaining'] === '0') {
    const retryAfter = response.headers['retry-after'];
    console.error(`GitHub API rate limit exceeded. Retry after ${retryAfter} seconds. Exiting.`);
    process.exit(75); // EX_TEMPFAIL from sysexits.h
  }
}); 