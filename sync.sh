#!/bin/bash
set -euo pipefail

# Sync from the original 0xMassi/darwinkit repo into our fork.
# Fetches latest from original/main, rebases our commits on top,
# pushes a sync branch, and creates a PR.
#
# Remotes:
#   origin   → genesiscz/darwinkit-swift (our fork)
#   original → 0xMassi/darwinkit (upstream source)
#
# Usage:
#   ./sync.sh       # fetch, rebase, push sync branch, create PR
#   ./sync.sh --dry # fetch only, show what would change

ORIGINAL_REPO="https://github.com/0xMassi/darwinkit"
DRY=false

for arg in "$@"; do
  case "$arg" in
    --dry) DRY=true ;;
    *)     echo "Unknown flag: $arg"; echo "Usage: ./sync.sh [--dry]"; exit 1 ;;
  esac
done

# Require clean working tree before sync operations
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree has uncommitted changes. Commit or stash first."
  exit 1
fi

# Ensure we're on main
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  echo "Switching to main..."
  git checkout main || exit 1
fi

echo "Fetching from original (0xMassi/darwinkit)..."
git fetch original

# Show what's new
BEHIND=$(git rev-list --count HEAD..original/main 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count original/main..HEAD 2>/dev/null || echo 0)
echo ""
echo "Status: $BEHIND commits behind original/main, $AHEAD commits ahead"

if [ "$BEHIND" = "0" ]; then
  echo "Already up to date with original/main."
  exit 0
fi

# Collect new commit info before rebasing
NEW_COMMITS=$(git log --oneline HEAD..original/main)
NEW_COMMIT_COUNT=$BEHIND
LATEST_SHA=$(git rev-parse --short original/main)

echo ""
echo "New commits from original/main:"
echo "$NEW_COMMITS"
echo ""

if [ "$DRY" = true ]; then
  echo "(dry run — no changes made)"
  exit 0
fi

# Build the commit list for PR body (with links to original repo)
COMMIT_LIST=$(git log --format="- [\`%h\`](${ORIGINAL_REPO}/commit/%H) %s" HEAD..original/main)

# Create a sync branch from current main
SYNC_BRANCH="sync/upstream-$(date +%Y%m%d-%H%M%S)"
echo "Creating sync branch: $SYNC_BRANCH"
git checkout -b "$SYNC_BRANCH" --no-track

# Rebase our commits onto original/main
echo "Rebasing onto original/main..."
git rebase original/main

# Push the sync branch
echo "Pushing $SYNC_BRANCH to origin..."
git push -u origin "$SYNC_BRANCH"

# Create PR
echo "Creating pull request..."
PR_URL=$(gh pr create \
  --base main \
  --head "$SYNC_BRANCH" \
  --title "sync: upstream 0xMassi/darwinkit (${LATEST_SHA})" \
  --body "$(cat <<EOF
## Upstream Sync

Rebased our fork onto the latest [\`original/main\`](${ORIGINAL_REPO}) (${NEW_COMMIT_COUNT} new commits).

### New commits from upstream

${COMMIT_LIST}

### Source

- Upstream repo: ${ORIGINAL_REPO}
- Synced up to: [\`${LATEST_SHA}\`](${ORIGINAL_REPO}/commit/$(git rev-parse original/main))
EOF
)")

echo ""
echo "PR created: $PR_URL"
echo ""
echo "To merge: gh pr merge $PR_URL --rebase --delete-branch"
