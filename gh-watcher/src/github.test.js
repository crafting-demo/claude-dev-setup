import { test } from 'node:test';
import assert from 'node:assert';
import { octokit } from './github.js';
import { WATCHLIST } from './config.js';

test('GitHub Connection and Authentication Test', async () => {
  if (WATCHLIST.length === 0) {
    throw new Error('Watchlist is empty. Add at least one repository to watchlist.txt to run tests.');
  }

  const repoFullName = WATCHLIST[0];
  const [owner, repo] = repoFullName.split('/');

  await assert.doesNotReject(
    async () => {
      const response = await octokit.rest.repos.get({ owner, repo });
      assert.strictEqual(response.status, 200, 'Should receive a 200 OK status');
      assert.strictEqual(response.data.full_name, repoFullName, 'Fetched repository full name should match');
    },
    'Should be able to connect to GitHub and authenticate successfully.'
  );
}); 