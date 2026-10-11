#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" PATH="$tmp/bin:$PATH" MOCK_RELOAD_MARK="$tmp/reload-once"
mkdir -p "$HOME/.config/hypr" "$tmp/bin"
target="$HOME/.config/hypr/bindings.lua"
printf '%s\n' '-- user custom binding stays untouched' > "$target"
cp "$target" "$tmp/original"
cat > "$tmp/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  binds) printf '%s\n' "${MOCK_BINDS_JSON:-[]}" ;;
  configerrors) printf '%s' "${MOCK_ERRORS:-}" ;;
  reload)
    if [[ ${MOCK_FAIL_FIRST_RELOAD:-0} == 1 && ! -e $MOCK_RELOAD_MARK ]]; then
      touch "$MOCK_RELOAD_MARK"
      exit 1
    fi ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$tmp/bin/hyprctl"
run() { bash "$root/scripts/install-hotkey.sh"; }
fail() { if "$@" >/dev/null 2>&1; then echo 'Unexpected shortcut write' >&2; exit 1; fi; }
# No user click means no script invocation and no side effect.
cmp "$target" "$tmp/original"
[[ ! -e $HOME/.config/keyritual/preferences.json ]]
# Existing or malformed active shortcut data refuses before file/backup changes.
fail env MOCK_BINDS_JSON='[{"modmask":65,"key":"K"}]' bash "$root/scripts/install-hotkey.sh"
fail env MOCK_BINDS_JSON='not-json' bash "$root/scripts/install-hotkey.sh"
cmp "$target" "$tmp/original"
# Symlinks and pre-existing Hyprland errors are rejected.
mv "$target" "$tmp/binding-real"
ln -s "$tmp/binding-real" "$target"
fail run
rm "$target"
mv "$tmp/binding-real" "$target"
fail env MOCK_ERRORS='parse error' bash "$root/scripts/install-hotkey.sh"
cmp "$target" "$tmp/original"
# Failed reload restores the original; backup remains recoverable.
fail env MOCK_FAIL_FIRST_RELOAD=1 bash "$root/scripts/install-hotkey.sh"
cmp "$target" "$tmp/original"
backups=("$HOME"/.config/hypr/.keyritual-bindings-backup.*)
[[ ${#backups[@]} -eq 1 && -f ${backups[0]} ]]
cmp "${backups[0]}" "$tmp/original"
# User acceptance installs exactly one marked binding without losing other lines.
run > /dev/null
grep -Fqx -- '-- keyritual: optional global launch binding' "$target"
grep -Fqx -- 'o.bind("SUPER + SHIFT + K", "Keyritual", "omarchy-shell shell toggle io.github.syfra3.keyritual '\''{}'\''")' "$target"
grep -Fqx -- '-- user custom binding stays untouched' "$target"
run > /dev/null
[[ $(grep -Fc -- '-- keyritual: optional global launch binding' "$target") -eq 1 ]]
backups=("$HOME"/.config/hypr/.keyritual-bindings-backup.*)
[[ ${#backups[@]} -eq 2 ]]
[[ ! -e $HOME/.config/keyritual/preferences.json ]]
printf '%s\n' 'isolated first-open hotkey script checks passed'
