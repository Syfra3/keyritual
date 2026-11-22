#!/usr/bin/env python3
"""Run the selected focused QML UI regression checks."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

output = Path(os.environ["A2E_OUTPUT_DIR"])
start = time.monotonic()
result = subprocess.run(["node", "tests/pattern-ui-regressions.cjs"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
elapsed = time.monotonic() - start
(output / "qml-ui-regressions.log").write_bytes(result.stdout)
if result.returncode:
    sys.exit(result.returncode)
(output / "result.json").write_text(json.dumps({"metric": elapsed, "artifacts": ["qml-ui-regressions.log"]}) + "\n")
