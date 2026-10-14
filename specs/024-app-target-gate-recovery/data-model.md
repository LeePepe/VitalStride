# State Model: App-target required gate

No persisted product data or schema changes are involved. The relevant state is an ephemeral workflow execution contract.

## States

- **Prepared**: checkout, Xcode selection, XcodeGen installation, and project generation completed.
- **Running non-quarantined suite**: exactly one App-target command is active with the accepted explicit exclusion.
- **Terminal success**: that command returned zero; the required job succeeds.
- **Terminal failure**: that command returned nonzero; the required job fails immediately after publishing the available evidence.

## Forbidden transition

- **Terminal failure → Running non-quarantined suite** is forbidden within the same workflow run. That transition is the whole-suite retry defect.

## External dependency state

- RepoInfra recovery merged: execution policy corrected.
- MY-1490 merged: catalog-distribution expectation corrected by its owning layer.
- Fresh PR #418 required App-target success: shipping blocker cleared only after both upstream states are true.

