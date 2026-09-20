"""Run offline Raven contracts with the review runner's Python (3.11+).

AIDash's hook interpreter is Python 3.9; do not change the hook or add a TOML
dependency. The real launcher and these contracts use python3 from runner PATH.
"""
from pathlib import Path
import subprocess
import unittest


class RavenContractTests(unittest.TestCase):
    def test_offline_provider_and_actual_caller_contracts(self):
        contract = Path(__file__).resolve().parents[1] / "ci/tests/review_raven_contract.py"
        result = subprocess.run(
            ["python3", "-B", str(contract)], capture_output=True, text=True, timeout=90,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
