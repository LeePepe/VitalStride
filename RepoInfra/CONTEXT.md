---
layer: RepoInfra
role: Repository automation, policy enforcement, release tooling, and non-product repository configuration
paths: [.github, scripts, fastlane, .gitignore, .gitleaks.toml, .swiftlint.yml, .swiftlint-baseline.json, .specify/extensions.yml, .specify/extensions, .specify/init-options.json, .specify/integration.json, .specify/integrations, .specify/scripts, .specify/templates, .specify/workflows]
depends_on: []
depended_by: []
red_lines:
  - Gate speed and change ownership are independent; local RepoInfra validation stays fast while heavy app tests remain required CI
  - AI Reviewer performs content review only; PR Manager owns CI, build, test, lint, hook, merge-readiness, and shipping state
  - project.yml remains AppUI's XcodeGen source of truth; RepoInfra automation may invoke it but does not own it
  - Generated outputs, caches, logs, local credentials, and signing secrets are exclusions rather than layer content
support_excludes: [AGENTS.md, CLAUDE.md, CONTEXT.md, RepoInfra/CONTEXT.md, README.md, '**/CONTEXT.md', design, docs, specs, .specify/memory]
generated_excludes: [VitalStride.xcodeproj, build, .build, '**/.build', DerivedData, derived-data, .agent_context, '*.log', '*.xcresult', '*.xcuserdata', '*.xcworkspace/xcuserdata', xcuserdata, Package.resolved, '*.ipa', '*.dSYM', '*.dSYM.zip', '**/.swiftpm', 'Prototype/*.xcodeproj', scripts/i18n_check_lproj_parity.report.md, scripts/i18n_extract_hardcoded.report.md, local, fastlane/report.xml, fastlane/Preview.html, fastlane/test_output, .env, '.env.*', '*.p8', 'AuthKey_*.p8', '*.mobileprovision', 'AppStore_*.mobileprovision', .DS_Store, .Trashes, Thumbs.db, '*.swp', '*~', .idea, .vscode, __pycache__, '**/__pycache__', '*.pyc', '*.pyo', .claude, .claude-flow, .swarm, ruvector.db]
test: bash scripts/test-repoinfra.sh
owns: [GitHub Actions workflows, git hooks, CI/review/release scripts, fastlane release automation, repository lint and secret-scan configuration, spec-kit automation]
---

# RepoInfra Context

## Responsibility

`RepoInfra` owns executable repository automation and its configuration: CI/workflow definitions,
hooks and scripts (including their tests), fastlane release tooling, lint/security policy files, and
the executable/configurable parts of `.specify`. It has no product-layer dependency and product
layers do not depend on it; automation invoking a layer's validation command does not create a code
dependency.

`project.yml` stays in `AppUI` because it defines app targets. The derived tracked Xcode project is
classified as generated output, not schedulable implementation. Governance, specifications,
architecture/design evidence, and agent-facing documentation are visible support exclusions rather
than a catch-all infrastructure layer.

## Validation

Run the frontmatter `test` command for the fast local gate. It checks exhaustive/non-overlapping
tracked-path coverage, shell and Python syntax, and RepoInfra Python tests without running
`xcodebuild`. Required CI remains responsible for full app and package gates.
