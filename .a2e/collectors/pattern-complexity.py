#!/usr/bin/env python3
"""Measure maximum Rust function cyclomatic complexity without a threshold."""
import csv
import io
import json
import os
from pathlib import Path
import subprocess
import sys

output = Path(os.environ["A2E_OUTPUT_DIR"])
result = subprocess.run(
    ["/tmp/opencode/keyritual-quality/bin/lizard", "-l", "rust", "--csv", "-i", "-1", "src"],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
)
(output / "complexity.csv").write_bytes(result.stdout)
(output / "complexity.log").write_bytes(result.stderr)
if result.returncode:
    sys.exit(result.returncode)
try:
    rows = list(csv.reader(io.StringIO(result.stdout.decode("utf-8"))))
    if not rows:
        raise ValueError("no Rust functions analyzed")
    max_ccn = max(int(row[1]) for row in rows)
except (ValueError, IndexError, UnicodeError, csv.Error) as exc:
    print(f"Invalid complexity report: {exc}", file=sys.stderr)
    sys.exit(1)
(output / "result.json").write_text(json.dumps({"metric": max_ccn, "artifacts": ["complexity.csv", "complexity.log"]}) + "\n")
