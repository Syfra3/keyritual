#!/usr/bin/env bash
# Only invoked after the user accepts the first-open Keyritual dialog.
set -euo pipefail

[[ $# -eq 0 ]] || { printf '%s\n' 'Usage: install-hotkey.sh' >&2; exit 2; }
[[ -n ${HOME:-} && -d $HOME && -O $HOME ]] || { printf '%s\n' 'User home is unavailable or not owned by this user.' >&2; exit 1; }
parent="$HOME/.config/hypr"
target="$parent/bindings.lua"
for part in "$HOME/.config" "$parent" "$target"; do
  [[ ! -L $part ]] || { printf 'Refusing symlink: %s\n' "$part" >&2; exit 1; }
done
[[ -d $parent && -O $parent && -f $target && -O $target ]] || {
  printf 'Existing user-owned Hyprland bindings file required at %s\n' "$target" >&2; exit 1;
}
command -v hyprctl >/dev/null && command -v jq >/dev/null || {
  printf '%s\n' 'hyprctl and jq are required; no changes made.' >&2; exit 1;
}
marker='-- keyritual: optional global launch binding'
binding='o.bind("SUPER + SHIFT + K", "Keyritual", "omarchy-shell shell toggle io.github.syfra3.keyritual '\''{}'\''")'
if grep -Fqx -- "$marker" "$target" && grep -Fqx -- "$binding" "$target"; then
  printf '%s\n' 'Keyritual Super+Shift+K binding is already installed.'
  exit 0
fi
if grep -Fq -- "$marker" "$target" || grep -Fq -- 'SUPER + SHIFT + K' "$target"; then
  printf '%s\n' 'Existing or modified shortcut found; refusing to overwrite or duplicate it.' >&2
  exit 1
fi
binds="$(hyprctl binds -j)" || { printf '%s\n' 'Cannot inspect active shortcuts.' >&2; exit 1; }
if ! jq -e 'type == "array" and all(.[]; (.modmask | type) == "number" and (.key | type) == "string")' >/dev/null <<<"$binds"; then
  printf '%s\n' 'Active shortcuts response is invalid; no changes made.' >&2
  exit 1
fi
if jq -e 'any(.[]; .modmask == 65 and (.key | ascii_upcase) == "K")' >/dev/null <<<"$binds"; then
  printf '%s\n' 'Super+Shift+K is already occupied; no changes made.' >&2
  exit 1
fi
pre_errors="$(hyprctl configerrors)" || { printf '%s\n' 'Cannot inspect Hyprland config errors.' >&2; exit 1; }
[[ -z $pre_errors ]] || { printf '%s\n' 'Hyprland has pre-existing config errors; no changes made.' >&2; exit 1; }
original_hash="$(sha256sum "$target")"
original_stat="$(stat -c '%d:%i:%Y:%s' "$target")"
backup="$(mktemp "$parent/.keyritual-bindings-backup.XXXXXX")"
stage="$(mktemp "$parent/.keyritual-bindings-stage.XXXXXX")"
trap 'rm -f -- "$stage"' EXIT
cp -p -- "$target" "$backup"
cp -p -- "$target" "$stage"
printf '\n%s\n%s\n' "$marker" "$binding" >> "$stage"
if [[ $(sha256sum "$target") != "$original_hash" || $(stat -c '%d:%i:%Y:%s' "$target") != "$original_stat" ]]; then
  printf '%s\n' 'Bindings changed during preparation; no changes made.' >&2
  exit 1
fi
mv -- "$stage" "$target"
post_ok=1
hyprctl reload >/dev/null || post_ok=0
post_errors="$(hyprctl configerrors)" || post_ok=0
if [[ $post_ok -eq 0 || -n $post_errors ]]; then
  restore="$(mktemp "$parent/.keyritual-bindings-restore.XXXXXX")"
  cp -p -- "$backup" "$restore"
  if mv -- "$restore" "$target" && hyprctl reload >/dev/null; then
    printf 'Hyprland rejected shortcut; restored original. Backup: %s\n' "$backup" >&2
  else
    printf 'ROLLBACK FAILED: original backup remains at %s\n' "$backup" >&2
  fi
  exit 1
fi
printf 'Installed Super+Shift+K for Keyritual. Original backup: %s\n' "$backup"
