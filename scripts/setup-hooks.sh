#!/bin/sh
# Configure git to use version-controlled hooks from scripts/hooks/

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: Not inside a git repository."
  exit 1
fi

git config core.hooksPath scripts/hooks
echo "Git hooks path set to scripts/hooks/"
echo "Hooks active: pre-commit, pre-push"
