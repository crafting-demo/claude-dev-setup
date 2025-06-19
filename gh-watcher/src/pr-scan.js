import { octokit } from './github.js';
import { WATCHLIST, TRIGGER_PHRASE } from './config.js';
import { runDevAgent } from './agent.js';

async function getPrComments(owner, repo, prNumber, verbose) {
  if (verbose) console.log(`   Fetching comments for PR #${prNumber}`);
  const issueComments = await octokit.paginate(octokit.issues.listComments, {
    owner,
    repo,
    issue_number: prNumber,
  });
  const reviewComments = await octokit.paginate(octokit.pulls.listReviewComments, {
    owner,
    repo,
    pull_number: prNumber,
  });
  return [...issueComments, ...reviewComments].sort((a, b) => a.id - b.id);
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

    let maxCommentId = state[repoFullName].lastPrComment || 0;

    for (const pr of prs) {
      const comments = await getPrComments(owner, repo, pr.number, verbose);

      for (const comment of comments) {
        if (comment.id <= (state[repoFullName].lastPrComment || 0)) {
          continue;
        }

        maxCommentId = Math.max(maxCommentId, comment.id);

        if (comment.body.includes(TRIGGER_PHRASE)) {
          console.log(`Trigger phrase found in PR #${pr.number} (commentId: ${comment.id})`);

          const payload = {
            owner,
            repo,
            kind: 'pr_comment',
            prompt: comment.body,
            issueNumber: pr.number,
            prNumber: pr.number,
            filePath: comment.path,
            lineNumber: comment.line,
          };

          await runDevAgent(payload, options);
        }
      }
    }

    if (maxCommentId > (state[repoFullName].lastPrComment || 0)) {
      state[repoFullName].lastPrComment = maxCommentId;
      hasChanges = true;
    }
  }
  return hasChanges;
} 