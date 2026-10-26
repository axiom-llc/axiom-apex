"""Exercise the documented demo as a separate, credential-free process."""
import os
from pathlib import Path
import subprocess
import sys
import unittest


class RecoveryDemoTest(unittest.TestCase):
    def test_demo_proves_recovery_without_touching_configured_history(self):
        import tempfile

        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            sentinel = Path(directory) / "runs.db"
            sentinel.write_bytes(b"existing history must stay untouched")
            env = {**os.environ, "APEX_HISTORY_DB_PATH": str(sentinel),
                   "GEMINI_API_KEY": "", "LLM_PROVIDER": "invalid-demo-must-ignore"}
            result = subprocess.run(
                [sys.executable, "examples/recovery.py"], cwd=root, env=env,
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Recovery: HALTED | effects: first, second", result.stdout)
            self.assertIn("Recovery: BLOCKED | effects: first", result.stdout)
            self.assertIn("PASS: no duplicate effects; ambiguous recovery refused.", result.stdout)
            self.assertEqual(result.stdout, (root / "docs/assets/recovery.txt").read_text())
            self.assertEqual(sentinel.read_bytes(), b"existing history must stay untouched")


if __name__ == "__main__":
    unittest.main()
