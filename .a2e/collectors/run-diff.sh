#!/bin/sh
# Explicit invocation only. Pass --root, --base, --phase and optionally --execute.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec python3 "$here/.a2e/scripts/a2e_collect.py" "$@"
