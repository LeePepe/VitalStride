# Quickstart: Verify App-target gate recovery

Run from the repository root.

## Focused deterministic workflow regression

```bash
python3 -B -m unittest discover -s scripts/tests -p 'test_app_target_gate.py'
```

Expected result: the controlled failure and success scenarios pass, proving one invocation and correct exit propagation without launching a simulator.

## Complete RepoInfra gate

```bash
bash scripts/test-repoinfra.sh
```

Expected result: frontmatter/path coverage, shell and Python syntax, all RepoInfra unittests, and existing contract tests pass.

## Additional boundary checks

```bash
bash -n scripts/ci/run-app-target-tests.sh
git diff --check
```

Confirm the implementation diff contains only:

- `.github/workflows/ci.yml`
- `scripts/ci/run-app-target-tests.sh`
- `scripts/tests/test_app_target_gate.py`

Do not run local App-target `xcodebuild` as proof of the RepoInfra task. The unchanged required GitHub `App target` job is the integration gate after implementation.

