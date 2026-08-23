#!/usr/bin/env bash
# Fast local validation for the RepoInfra change-owner layer. No app build.
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"

bash scripts/check-frontmatter.sh

while IFS= read -r script; do
  bash -n "$script"
done < <(git ls-files '*.sh' 'scripts/hooks/*' 'scripts/rulesets/apply')

while IFS= read -r script; do
  python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), filename=sys.argv[1])' "$script"
done < <(find scripts .specify/extensions .specify/scripts -type f -name '*.py' -print | sort)

python3 -B -m unittest discover -s scripts/tests -p 'test_*.py'

echo "✅ RepoInfra fast validation passed."
