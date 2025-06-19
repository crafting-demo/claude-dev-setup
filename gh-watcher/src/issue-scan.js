import { octokit } from './github.js';
import { WATCHLIST, TRIGGER_PHRASE } from './config.js';
import { runDevAgent } from './agent.js';

export async function scanIssues(options, state) {
  const { dryRun, verbose } = options;
  let hasChanges = false;

  for (const repoFullName of WATCHLIST) {
    const [owner, repo] = repoFullName.split('/');
    if (!state[repoFullName]) state[repoFullName] = {};

    if (verbose) console.log(`Scanning issues for ${owner}/${repo}...`);

    const issues = await octokit.paginate(octokit.issues.listForRepo, {
      owner,
      repo,
      state: 'open',
    });

    let maxCommentId = state[repoFullName].lastIssueComment || 0;

    for (const issue of issues) {
      if (issue.pull_request) continue; // Skip PRs

      const comments = await octokit.paginate(octokit.issues.listComments, {
        owner,
        repo,
        issue_number: issue.number,
      });

      for (const comment of comments) {
        if (comment.id <= (state[repoFullName].lastIssueComment || 0)) {
          continue;
        }

        maxCommentId = Math.max(maxCommentId, comment.id);

        if (comment.body.includes(TRIGGER_PHRASE)) {
          console.log(`Trigger phrase found in issue #${issue.number} (commentId: ${comment.id})`);

          const payload = {
            owner,
            repo,
            kind: 'issue',
            prompt: `Issue #${issue.number}: ${issue.title}\\n\\n${issue.body}\\n\\n${comment.body}`,
            issueNumber: issue.number,
          };

          await runDevAgent(payload, options);
        }
      }
    }

    if (maxCommentId > (state[repoFullName].lastIssueComment || 0)) {
        state[repoFullName].lastIssueComment = maxCommentId;
        hasChanges = true;
    }
  }
  return hasChanges;
} 