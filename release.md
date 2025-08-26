# Release guide (cs-cc)

This repository publishes a GitHub Release automatically whenever you push a semantic tag of the form `vX.Y.Z`.

What happens when you push a tag:
- The GitHub Actions workflow builds `cs-cc` with `-ldflags "-X main.version=<tag>"`.
- It creates a release named after the tag and uploads the artifact:
  - `dist/cs-cc-linux-amd64`
- `releases/latest` is updated to point to the newest `v*.*.*` release.

## Create a new release
From the commit you want to release:
```bash
# lightweight tag
git tag vX.Y.Z
git push origin vX.Y.Z
```

Or with an annotated tag (includes a message on the tag):
```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

## Fix a tag pointing at the wrong commit
If you tagged the wrong commit, retarget the tag to the current `HEAD`:
```bash
# delete remote tag first
git push origin :refs/tags/vX.Y.Z
# (optional) delete local tag if it exists
git tag -d vX.Y.Z
# recreate at current commit, then push
git tag vX.Y.Z
git push origin vX.Y.Z
```

## Notes
- The workflow is triggered by pushing tags matching `v*.*.*` (branch is irrelevant once the tag exists).
- If your HTTPS push fails due to permissions, switch the remote to SSH and push:
```bash
git remote set-url origin git@github.com:<org>/<repo>.git
```
- Example release URLs (replace org/repo):
  - Specific: `https://github.com/<org>/<repo>/releases/tag/vX.Y.Z`
  - Latest: `https://github.com/<org>/<repo>/releases/latest`
