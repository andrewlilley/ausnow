#!/bin/sh
# One-shot GitHub deployment. Prerequisite: `gh auth login` once.
# Usage: sh scripts/deploy_github.sh [repo-name]   (default: ausnow)
set -e
REPO="${1:-ausnow}"
OWNER=$(gh api user -q .login)
echo "Deploying as $OWNER/$REPO"

if ! gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  gh repo create "$REPO" --public --description \
    "AusNow: an auto-updating release-by-release nowcast of Australian quarterly GDP growth" \
    --disable-wiki
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$OWNER/$REPO.git"
git push -u origin main

# Pages served from the Actions artifact (matches .github/workflows/nowcast.yml)
gh api -X POST "repos/$OWNER/$REPO/pages" -f build_type=workflow 2>/dev/null ||
  gh api -X PUT "repos/$OWNER/$REPO/pages" -f build_type=workflow 2>/dev/null || true

echo "Triggering first workflow run..."
gh workflow run nowcast.yml --repo "$OWNER/$REPO" || true
sleep 8
gh run list --repo "$OWNER/$REPO" --limit 1
echo
echo "Watch it:   gh run watch --repo $OWNER/$REPO"
echo "Site (once deployed): https://$OWNER.github.io/$REPO/"
