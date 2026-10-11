#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -m)" in
  x86_64) ;;
  *) printf '%s\n' 'This alpha bundles only an x86_64 Linux engine.' >&2; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
install -m644 "$root/manifest.json" "$root/Keyritual.qml" "$tmp/"
install -m644 "$root/assets/keyritual-seal.png" "$tmp/keyritual-seal.png"
install -Dm755 "$root/bin/keyritual-core" "$tmp/bin/keyritual-core"
install -Dm755 "$root/scripts/install-hotkey.sh" "$tmp/scripts/install-hotkey.sh"
[[ -x "$tmp/bin/keyritual-core" && -x "$tmp/scripts/install-hotkey.sh" ]]
expected="$(awk -F '"' '/^version = / { print $2; exit }' "$root/Cargo.toml")"
[[ "$("$tmp/bin/keyritual-core" --version)" == "keyritual-core $expected" ]]
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$tmp"
fi
response="$(printf '%s\n' '{"id":1,"type":"start","mode":"words","limit":10,"strict":false}' | XDG_STATE_HOME="$tmp/state" "$tmp/bin/keyritual-core" serve)"
python -c 'import json,sys; s=json.loads(sys.argv[1]); assert s["id"]==1 and s["type"]=="state" and s["phase"]=="ready" and s["prompt"]' "$response"
[[ ! -e "$tmp/state/keyritual/history.json" ]]
printf '%s\n' 'bundled plugin validation and isolated engine IPC passed'
