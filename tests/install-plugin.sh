#!/usr/bin/env bash
set -euo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/project/scripts" "$tmp/project/assets" "$tmp/project/bin" "$tmp/bin"
cp "$source_root/scripts/install-plugin.sh" "$tmp/project/scripts/"
cp "$source_root/manifest.json" "$source_root/Keyritual.qml" "$tmp/project/"
cp "$source_root/assets/keyritual-seal.png" "$tmp/project/assets/"
cp "$source_root/bin/keyritual-core" "$tmp/project/bin/"
chmod +x "$tmp/project/bin/keyritual-core"
export XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH"
dest="$XDG_CONFIG_HOME/omarchy/plugins/io.github.syfra3.keyritual"
printf '#!/usr/bin/env bash\nif [[ ${FAIL_VALIDATE:-0} == 1 && $* == "plugin validate "* ]]; then exit 1; fi\nif [[ ${FAIL_ENABLE:-0} == 1 && $* == "plugin enable "* ]]; then exit 1; fi\n' > "$tmp/bin/omarchy"
printf '#!/usr/bin/env bash\n[[ ${FAIL_RESCAN:-0} != 1 ]]\n' > "$tmp/bin/omarchy-shell"
chmod +x "$tmp/bin/omarchy" "$tmp/bin/omarchy-shell"
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
# Existing exact installation is recognized, and replacement retains the old directory.
run --check
run
backup=("$XDG_CONFIG_HOME"/omarchy/plugins/.keyritual-backup.*/plugin)
[[ ${#backup[@]} -eq 1 && -d ${backup[0]} ]]
cmp "${backup[0]}/Keyritual.qml" "$dest/Keyritual.qml"
# Unknown source revisions cannot replace a managed three-file install without verified ownership.
printf '\n// newer release\n' >> "$tmp/project/Keyritual.qml"
fail run --check
cp "$source_root/Keyritual.qml" "$tmp/project/Keyritual.qml"
run --check
run
backup=("$XDG_CONFIG_HOME"/omarchy/plugins/.keyritual-backup.*/plugin)
[[ ${#backup[@]} -eq 2 ]]
# An unknown payload with the same manifest ID is not owned.
printf '\n// user modification\n' >> "$dest/Keyritual.qml"
fail run --check
fail run
cmp "$dest/manifest.json" "$tmp/project/manifest.json"
cp "$tmp/project/Keyritual.qml" "$dest/Keyritual.qml"
# Bundled binary changes/symlinks and unexpected files are never overwritten.
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
[[ ${#backup[@]} -eq 2 ]]
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
