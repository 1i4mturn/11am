#!/usr/bin/env bash
# Fix Vercel "commit author email is not valid" (Mac .local addresses).
# Run in your terminal — uses your GitHub noreply email if GITHUB_EMAIL is unset.
set -euo pipefail

cd "$(dirname "$0")/.."

EMAIL="${GITHUB_EMAIL:-}"
if [ -z "$EMAIL" ]; then
  echo "Set your GitHub email, then re-run:"
  echo ""
  echo "  GITHUB_EMAIL='you@example.com' bash scripts/fix-git-author.sh"
  echo ""
  echo "Or use GitHub's private noreply (Settings → Emails):"
  echo "  GITHUB_EMAIL='12345678+1i4mturn@users.noreply.github.com' bash scripts/fix-git-author.sh"
  exit 1
fi

echo "This will set git author for THIS REPO ONLY and amend the last commit."
echo "  email: $EMAIL"
echo ""
read -r -p "Continue? [y/N] " ok
if [[ ! "$ok" =~ ^[yY]$ ]]; then exit 0; fi

git config user.email "$EMAIL"
git config user.name "${GIT_USER_NAME:-Liam Turner}"
git commit --amend --reset-author --no-edit

echo ""
echo "Done. Push the amended commit:"
echo "  git push --force-with-lease origin main"
echo ""
echo "Then re-run: npm run deploy:all"
