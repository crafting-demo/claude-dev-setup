import { octokit } from './github.js';
import { WATCHLIST, PR_LABELS, PROCESS_EXISTING_PRS } from './config.js';
import { runDevAgent } from './agent.js';
import { buildReviewPrompt } from './pr-review-prompt.js';

function prHasRequiredLabels(pr) {
  if (!PR_LABELS || PR_LABELS.length === 0) {
    return true;
  }
  const labels = (pr.labels || []).map((label) => label.name);
  return PR_LABELS.some((required) => labels.includes(required));
}

async function listPrFiles(owner, repo, prNumber) {
  return await octokit.paginate(octokit.pulls.listFiles, {
    owner,
    repo,
    pull_number: prNumber,
  });
}

export async function scanPRs(options, state) {
  const { dryRun, verbose } = options;
  let hasChanges = false;

  for (const repoFullName of WATCHLIST) {
    const [owner, repo] = repoFullName.split('/');
    if (!state[repoFullName]) state[repoFullName] = {};

    if (verbose) console.log(`Scanning PRs for ${owner}/${repo}...`);

    const prs = await octokit.paginate(octokit.pulls.list, {
      owner,
      repo,
      state: 'open',
    });

    let lastPrUpdatedAt = state[repoFullName].lastPrUpdatedAt || '';
    if (!lastPrUpdatedAt && !PROCESS_EXISTING_PRS) {
      state[repoFullName].lastPrUpdatedAt = new Date().toISOString();
      hasChanges = true;
      if (verbose) console.log(`Initialized lastPrUpdatedAt for ${repoFullName}`);
      continue;
    }

    for (const pr of prs) {
      if (!prHasRequiredLabels(pr)) {
        continue;
      }

      if (lastPrUpdatedAt && pr.updated_at <= lastPrUpdatedAt) {
        continue;
      }

      const files = await listPrFiles(owner, repo, pr.number);
      const prompt = buildReviewPrompt({ owner, repo, pr, files });

      const payload = {
        owner,
        repo,
        kind: 'pr_review',
        prompt,
        issueNumber: pr.number,
        prNumber: pr.number,
        prUrl: pr.html_url,
        prHeadRef: pr.head?.ref || '',
      };

      await runDevAgent(payload, options);
    }

    const newest = prs.reduce((latest, pr) => {
      if (!latest || pr.updated_at > latest) {
        return pr.updated_at;
      }
      return latest;
    }, lastPrUpdatedAt);

    if (newest && newest !== lastPrUpdatedAt) {
      state[repoFullName].lastPrUpdatedAt = newest;
      hasChanges = true;
    }
  }
  return hasChanges;
} 