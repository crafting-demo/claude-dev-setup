function formatFiles(files) {
  if (!files || files.length === 0) {
    return 'No files reported by GitHub API.';
  }
  return files
    .map((file) => `- ${file.filename} (+${file.additions} -${file.deletions})`)
    .join('\n');
}

export function buildReviewPrompt({ owner, repo, pr, files }) {
  const prTitle = pr.title || '(untitled)';
  const prBody = pr.body || '(no description provided)';
  const prNumber = pr.number;
  const prUrl = pr.html_url;
  const headRef = pr.head?.ref || '';
  const baseRef = pr.base?.ref || '';

  return `You are an automated PR reviewer.

Repository: ${owner}/${repo}
PR: #${prNumber}
URL: ${prUrl}
Branch: ${headRef} -> ${baseRef}

Title:
${prTitle}

Description:
${prBody}

Changed files:
${formatFiles(files)}

Review instructions:
- Use \`gh pr view\` and \`gh pr diff\` to inspect the PR.
- Look for correctness issues, security risks, and missing tests.
- Keep feedback concise and actionable.
- Post a single summary comment on the PR.

When ready, post a comment using:
\`gh pr comment -R ${owner}/${repo} ${prNumber} --body "<your review>"\`
`;
}
