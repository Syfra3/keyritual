#!/usr/bin/env python3
"""Compare the bundled engine with the existing local release build."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

output = Path(os.environ["A2E_OUTPUT_DIR"])
start = time.monotonic()
result = subprocess.run(["cmp", "bin/keyritual-core", "target/release/keyritual-core"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
elapsed = time.monotonic() - start
(output / "bundle-match.log").write_bytes(result.stdout)
if result.returncode:
    sys.exit(result.returncode)
(output / "result.json").write_text(json.dumps({"metric": elapsed, "artifacts": ["bundle-match.log"]}) + "\n")
