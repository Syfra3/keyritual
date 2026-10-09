#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${CARGO_HOME:-$HOME/.cargo}/bin/keyritual-core"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
desktop="$data_home/applications/io.github.syfra3.keyritual.desktop"
icon="$data_home/icons/hicolor/512x512/apps/keyritual.png"

if [[ ! -x "$binary" ]]; then
  printf 'Missing %s. Run: cargo install --path "%s" --locked\n' "$binary" "$root" >&2
  exit 1
fi

install -d "$(dirname "$desktop")" "$(dirname "$icon")"
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == Exec=* ]]; then
    printf 'Exec="%s" launch\n' "$binary"
  else
    printf '%s\n' "$line"
  fi
done < "$root/extras/io.github.syfra3.keyritual.desktop" > "$desktop"
install -m644 "$root/assets/keyritual-icon.png" "$icon"
printf 'Installed launcher: %s\nInstalled icon: %s\n' "$desktop" "$icon"
