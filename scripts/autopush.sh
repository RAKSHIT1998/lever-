#!/bin/zsh
# Auto-commit and push LEVER changes to origin/main. Run by the Claude Code Stop hook.
# Safe to run any time: exits quietly when there is nothing to commit or no remote yet.
set -u
cd "$(dirname "$0")/.." || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git -c commit.gpgsign=false commit -q -m "Update LEVER — $(date '+%Y-%m-%d %H:%M')

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" || exit 0
fi

git remote get-url origin >/dev/null 2>&1 || exit 0
if [ -n "$(git log origin/main..HEAD --oneline 2>/dev/null)" ] || ! git rev-parse origin/main >/dev/null 2>&1; then
  git push -q -u origin main 2>/dev/null && echo '{"systemMessage": "Pushed to GitHub (origin/main)."}'
fi
exit 0
