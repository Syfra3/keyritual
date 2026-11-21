#!/usr/bin/env python3
"""Collect Rust line coverage using the selected isolated, offline tool."""
import json
import os
from pathlib import Path
import subprocess
import sys

output = Path(os.environ["A2E_OUTPUT_DIR"])
env = dict(
    os.environ,
    CARGO_TARGET_DIR="/tmp/opencode/keyritual-coverage",
    LLVM_COV="/usr/bin/llvm-cov",
    LLVM_PROFDATA="/usr/bin/llvm-profdata",
)
result = subprocess.run(
    ["/tmp/opencode/keyritual-tools/bin/cargo-llvm-cov", "llvm-cov", "--json", "--summary-only", "--offline"],
    env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
)
(output / "coverage.json").write_bytes(result.stdout)
(output / "coverage.log").write_bytes(result.stderr)
if result.returncode:
    sys.exit(result.returncode)
try:
    report = json.loads(result.stdout)
    totals = report["data"][0]["totals"]["lines"]
    if totals["count"] <= 0:
        raise ValueError("no instrumented lines")
    percentage = 100.0 * totals["covered"] / totals["count"]
except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as exc:
    print(f"Invalid coverage report: {exc}", file=sys.stderr)
    sys.exit(1)
(output / "result.json").write_text(json.dumps({"metric": percentage, "artifacts": ["coverage.json", "coverage.log"]}) + "\n")
