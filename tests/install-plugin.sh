#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/project/scripts" "$tmp/project/assets" "$tmp/project/bin" "$tmp/bin"
cp "$source_root/scripts/install-plugin.sh" "$source_root/scripts/install-hotkey.sh" "$tmp/project/scripts/"
cp "$source_root/manifest.json" "$source_root/Keyritual.qml" "$tmp/project/"
cp "$source_root/assets/keyritual-seal.png" "$tmp/project/assets/"
cp "$source_root/bin/keyritual-core" "$tmp/project/bin/"
chmod +x "$tmp/project/bin/keyritual-core"
export REAL_SHA256SUM="$(command -v sha256sum)"
export XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH"
dest="$XDG_CONFIG_HOME/omarchy/plugins/io.github.syfra3.keyritual"
printf '#!/usr/bin/env bash\nif [[ ${FAIL_VALIDATE:-0} == 1 && $* == "plugin validate "* ]]; then exit 1; fi\nif [[ ${FAIL_ENABLE:-0} == 1 && $* == "plugin enable "* ]]; then exit 1; fi\n' > "$tmp/bin/omarchy"
printf '#!/usr/bin/env bash\n[[ ${FAIL_RESCAN:-0} != 1 ]]\n' > "$tmp/bin/omarchy-shell"
chmod +x "$tmp/bin/omarchy" "$tmp/bin/omarchy-shell"
# Simulate only the unavailable historical binary digest, never other file hashes.
printf 'historical boxed-controls engine fixture\n' > "$tmp/old-engine"
export OLD_ENGINE_FIXTURE="$tmp/old-engine" OLD_ENGINE_DEST="$dest/bin/keyritual-core"
cat > "$tmp/bin/sha256sum" <<'SH'
#!/usr/bin/env bash
if [[ $# -eq 1 && $1 == "$OLD_ENGINE_DEST" ]] && cmp -s "$1" "$OLD_ENGINE_FIXTURE"; then
  printf '32149e519206f00cfbc12051df7dd2f4faa9fc07d3571c7d3bd9e194fd244939  %s\n' "$1"
else
  exec "$REAL_SHA256SUM" "$@"
fi
SH
chmod +x "$tmp/bin/sha256sum"
run() { bash "$tmp/project/scripts/install-plugin.sh" "$@"; }
fail() { if "$@" >/dev/null 2>&1; then echo 'Unexpected success' >&2; exit 1; fi; }
# Check is read-only; fresh install activates the staged plugin.
run --check
[[ ! -e "$XDG_CONFIG_HOME" ]]
run
cmp "$dest/manifest.json" "$tmp/project/manifest.json"
cmp "$dest/keyritual-seal.png" "$tmp/project/assets/keyritual-seal.png"
cmp "$dest/bin/keyritual-core" "$tmp/project/bin/keyritual-core"
[[ -x "$dest/bin/keyritual-core" ]]
cmp "$dest/scripts/install-hotkey.sh" "$tmp/project/scripts/install-hotkey.sh"
[[ -x "$dest/scripts/install-hotkey.sh" ]]
# Existing exact installation is recognized, and replacement retains the old directory.
run --check
run
backup=("$XDG_CONFIG_HOME"/omarchy/plugins/.keyritual-backup.*/plugin)
[[ ${#backup[@]} -eq 1 && -d ${backup[0]} ]]
cmp "${backup[0]}/Keyritual.qml" "$dest/Keyritual.qml"
# Unknown source revisions cannot replace a managed bundle without verified ownership.
printf '\n// newer release\n' >> "$tmp/project/Keyritual.qml"
fail run --check
cp "$source_root/Keyritual.qml" "$tmp/project/Keyritual.qml"
run --check
run
backup=("$XDG_CONFIG_HOME"/omarchy/plugins/.keyritual-backup.*/plugin)
[[ ${#backup[@]} -eq 2 ]]
expected_backups=2
# Provenance: bytes copied from the previously installed boxed-controls Keyritual.qml
# (read-only source ~/.config/omarchy/plugins/io.github.syfra3.keyritual/Keyritual.qml).
# Pin the fixture so an accidental edit cannot silently remove this regression case.
boxed_qml="$source_root/tests/fixtures/boxed-controls.qml"
[[ $(sha256sum "$boxed_qml" | cut -d' ' -f1) == 69b9f6eb0fbc2adc66edde6ec102f15172ae45d2af8661cc69b0cf05595e17f0 ]]

  cp "$boxed_qml" "$dest/Keyritual.qml"
  cp "$tmp/old-engine" "$dest/bin/keyritual-core"
  chmod +x "$dest/bin/keyritual-core"
  run --check
  cp "$tmp/project/Keyritual.qml" "$dest/Keyritual.qml"
  [[ $("$REAL_SHA256SUM" "$tmp/project/Keyritual.qml" | cut -d' ' -f1) == c95620dbfe2bb73ccd79276b1def05672b243748ae1d702fbaa277f7b32d1687 ]]
  run --check # The exact compact source QML also pairs with the historical engine.
  printf '\n// newer source\n' >> "$tmp/project/Keyritual.qml"
  fail run --check # A later source revision cannot inherit the compact exception.
  cp "$source_root/Keyritual.qml" "$tmp/project/Keyritual.qml"
  python3 - "$dest/manifest.json" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_bytes(p.read_bytes().replace(b'"version": "0.1.0"', b'"version": "0.1.0-alpha.1"'))
PY
  [[ $("$REAL_SHA256SUM" "$dest/manifest.json" | cut -d' ' -f1) == b747bf75789af6f24d037f55343238531c35353f46a2edcd426defb2a27070c5 ]]
  run --check # Exact installed alpha manifest, compact QML and old engine.
  printf '\n// changed\n' >> "$dest/manifest.json"
  fail run --check
  cp "$tmp/project/manifest.json" "$dest/manifest.json"
  printf '\n// changed\n' >> "$dest/Keyritual.qml"
  fail run --check
  cp "$tmp/project/Keyritual.qml" "$dest/Keyritual.qml"
  printf '\n# changed\n' >> "$dest/scripts/install-hotkey.sh"
  fail run --check
  cp "$tmp/project/scripts/install-hotkey.sh" "$dest/scripts/install-hotkey.sh"
  printf '\nchanged\n' >> "$dest/bin/keyritual-core"
  fail run --check
  cp "$tmp/old-engine" "$dest/bin/keyritual-core"
  chmod +x "$dest/bin/keyritual-core"
  cp "$boxed_qml" "$dest/Keyritual.qml"
  printf '\n// changed\n' >> "$dest/Keyritual.qml"
  fail run --check
  cp "$boxed_qml" "$dest/Keyritual.qml"
  printf '\n# changed\n' >> "$dest/scripts/install-hotkey.sh"
  fail run --check
  cp "$tmp/project/scripts/install-hotkey.sh" "$dest/scripts/install-hotkey.sh"
  printf '\nchanged\n' >> "$dest/bin/keyritual-core"
  fail run --check
  cp "$tmp/old-engine" "$dest/bin/keyritual-core"
  chmod +x "$dest/bin/keyritual-core"
  printf 'unknown\n' > "$dest/unknown"
  fail run --check
  rm "$dest/unknown"
  run --check
  run
  backup=("$XDG_CONFIG_HOME"/omarchy/plugins/.keyritual-backup.*/plugin)
  [[ ${#backup[@]} -eq 3 ]]
  expected_backups=3
  boxed_backup=0
  for candidate in "${backup[@]}"; do
    if cmp -s "$candidate/Keyritual.qml" "$boxed_qml"; then boxed_backup=1; fi
  done
  [[ $boxed_backup -eq 1 ]]
  cmp "$dest/Keyritual.qml" "$tmp/project/Keyritual.qml"
# An unknown payload with the same manifest ID is not owned.
printf '\n// user modification\n' >> "$dest/Keyritual.qml"
fail run --check
fail run
cmp "$dest/manifest.json" "$tmp/project/manifest.json"
cp "$tmp/project/Keyritual.qml" "$dest/Keyritual.qml"
# Bundled binary/script changes and unexpected files are never overwritten.
printf '# customized\n' >> "$dest/scripts/install-hotkey.sh"
fail run --check
cp "$tmp/project/scripts/install-hotkey.sh" "$dest/scripts/install-hotkey.sh"
chmod +x "$dest/scripts/install-hotkey.sh"
printf 'tampered\n' >> "$dest/bin/keyritual-core"
fail run --check
cp "$tmp/project/bin/keyritual-core" "$dest/bin/keyritual-core"
chmod +x "$dest/bin/keyritual-core"
# Unexpected files, symlinks and incorrect manifest must all be rejected without writes.
printf 'custom\n' > "$dest/extra"
fail run --check
fail run
[[ -f "$dest/extra" ]]
rm "$dest/extra"
mv "$dest/Keyritual.qml" "$tmp/qml"
ln -s "$tmp/qml" "$dest/Keyritual.qml"
fail run
[[ -L "$dest/Keyritual.qml" ]]
rm "$dest/Keyritual.qml"
mv "$tmp/qml" "$dest/Keyritual.qml"
mv "$dest" "$tmp/original"
ln -s "$tmp/original" "$dest"
fail run --check
[[ -L "$dest" ]]
rm "$dest"
mv "$tmp/original" "$dest"
printf 'wrong\n' > "$dest/manifest.json"
fail run
[[ $(<"$dest/manifest.json") == wrong ]]
cp "$tmp/project/manifest.json" "$dest/manifest.json"
# Failed validation leaves the original alone and creates no new backup.
fail env FAIL_VALIDATE=1 bash "$tmp/project/scripts/install-plugin.sh"
cmp "$dest/manifest.json" "$tmp/project/manifest.json"
backup=("$XDG_CONFIG_HOME"/omarchy/plugins/.keyritual-backup.*/plugin)
[[ ${#backup[@]} -eq $expected_backups ]]
# Failed activation restores the original and retains the failed candidate separately.
fail env FAIL_RESCAN=1 bash "$tmp/project/scripts/install-plugin.sh"
cmp "$dest/Keyritual.qml" "$tmp/project/Keyritual.qml"
backup=("$XDG_CONFIG_HOME"/omarchy/plugins/.keyritual-backup.*/failed-replacement)
[[ ${#backup[@]} -eq 1 && -d ${backup[0]} ]]
fail env FAIL_ENABLE=1 bash "$tmp/project/scripts/install-plugin.sh"
cmp "$dest/manifest.json" "$tmp/project/manifest.json"
backup=("$XDG_CONFIG_HOME"/omarchy/plugins/.keyritual-backup.*/failed-replacement)
[[ ${#backup[@]} -eq 2 ]]
echo 'installer acceptance checks passed'
