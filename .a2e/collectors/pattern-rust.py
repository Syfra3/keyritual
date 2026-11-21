#!/usr/bin/env python3
"""Run the owner-selected Rust suite, recording output for private review."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

output = Path(os.environ["A2E_OUTPUT_DIR"])
start = time.monotonic()
result = subprocess.run(["cargo", "test"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
elapsed = time.monotonic() - start
(output / "cargo-test.log").write_bytes(result.stdout)
if result.returncode:
    sys.exit(result.returncode)
(output / "result.json").write_text(json.dumps({"metric": elapsed, "artifacts": ["cargo-test.log"]}) + "\n")
