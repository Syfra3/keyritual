#!/usr/bin/env bash
set -euo pipefail

id='io.github.syfra3.keyritual'
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugins="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
destination="$plugins/$id"

if [[ $# -gt 1 || ( $# -eq 1 && $1 != '--check' ) ]]; then
  printf '%s\n' 'Usage: install-plugin.sh [--check]' >&2
  exit 2
fi

if ! command -v omarchy-shell >/dev/null 2>&1 || ! command -v omarchy >/dev/null 2>&1; then
  printf '%s\n' 'Keyritual requires Omarchy Quattro / 4.x (omarchy-shell and omarchy plugin).' >&2
  exit 1
fi

# Recognize only exact known payloads, never an arbitrary matching plugin ID.
known_old_qml='6e9d575c9b8af106fe9431fa337d3386a3c3165e91b251ddfe49cf67145dc59a'
known_previous_qml='b735f4a1cb3c612f26d160424a5ec69a960730ebaee8b400e33ab1e37c8dfb8c'
known_practice_qml='f2fdcc9c5ce9f9730f2f538f62770f234e57216fe9bdb37c96b7b5d8c8dd87d4'
known_focus_qml='3cb059d4243dbb400629604aa89159dfecd0fe60bb04a8effe4ada056f4e4db6'
known_escape_qml='09a43d098f6c0761d89f504376a1d99fb71f0a1ad6747a1dc3da6dadf3716690'
known_ctrl_m_qml='a5e03fc51a9ebe11fdea32d8057835ce127123430d2df6f0fb76a06114790d89'
known_reflect_qml='51c8078ada2696a5939c827c48c550d3b21ba2b08f4a0e5e31fb090e4adb55c7'
known_three_line_qml='0e379924c3880e50919525497d732906ac1738dcbf1a8c6beef2a5c7cb36eba4'
known_fixed_prompt_qml='a4de5a3a62d4d4eb3eb91031a814024f8a165f48de4141011a64dab2dece9d16'
known_popup_history_qml='98bef552273bcedb439172b94124f0c23d50bebedfad1fe1853f23a3b5c27960'
known_corner_qml='9b2eb33ad9984e8e01ce766817a47057aaec23258a31e11c59762a9f5467e43c'
known_history_share_qml='939bc92edd83b405e7c23c66c064dddfaf50ffec9d3ba537b3cf7f88939c2191'
known_hotkey_qml='0fc03aa895a448470962ab7a2c864d317821042c04be9a601608b6b5f7d16e34'
known_boxed_controls_qml='69b9f6eb0fbc2adc66edde6ec102f15172ae45d2af8661cc69b0cf05595e17f0'
known_boxed_controls_binary='32149e519206f00cfbc12051df7dd2f4faa9fc07d3571c7d3bd9e194fd244939'
known_compact_controls_qml='c95620dbfe2bb73ccd79276b1def05672b243748ae1d702fbaa277f7b32d1687'
known_compact_controls_manifest='b747bf75789af6f24d037f55343238531c35353f46a2edcd426defb2a27070c5'
known_legacy_manifest='662c855b60dde440f79b87bdddd185a0d3529366254f627b50b5d710972c5fd3'
known_view_manifest='2ad68bf78125102ad8ec81dc624d387d7685b7034fa1fa0ff44555d4c7b55627'
known_screen_manifest='f37c819e53e9ddc3e648ff9dd259004fad29291744f633f85c63d6bec584e714'
owned_payload() {
  [[ ! -L $destination && -d $destination &&
     -f $destination/manifest.json && ! -L $destination/manifest.json ]] || return 1
  shopt -s nullglob dotglob
  local contents=("$destination"/*)
  shopt -u nullglob dotglob
  [[ ${#contents[@]} -eq 2 || ${#contents[@]} -eq 3 || ${#contents[@]} -eq 4 || ${#contents[@]} -eq 5 ]] || return 1
  local old_manifest_hash qml_hash
  old_manifest_hash="$(sha256sum "$destination/manifest.json")" || return 1
  old_manifest_hash=${old_manifest_hash%% *}
  if [[ $old_manifest_hash == "$known_legacy_manifest" ]]; then
    qml_file=Keyritual.qml
  elif [[ $old_manifest_hash == "$known_view_manifest" ]]; then
    qml_file=KeyritualView.qml
  elif [[ $old_manifest_hash == "$known_screen_manifest" ]]; then
    qml_file=keyritual-screen.qml
  elif cmp -s "$destination/manifest.json" "$root/manifest.json"; then
    qml_file=Keyritual.qml
  elif [[ $old_manifest_hash == "$known_compact_controls_manifest" && ${#contents[@]} -eq 5 ]]; then
    qml_file=Keyritual.qml
  else
    return 1
  fi
  [[ -f $destination/$qml_file && ! -L $destination/$qml_file ]] || return 1
  qml_hash="$(sha256sum "$destination/$qml_file")" || return 1
  qml_hash=${qml_hash%% *}
  if [[ $old_manifest_hash == "$known_compact_controls_manifest" &&
        $qml_hash != "$known_compact_controls_qml" && $qml_hash != "$known_boxed_controls_qml" ]]; then
    return 1
  fi
  if [[ ${#contents[@]} -eq 5 ]]; then
    [[ -d $destination/scripts && ! -L $destination/scripts &&
       -f $destination/scripts/install-hotkey.sh && ! -L $destination/scripts/install-hotkey.sh &&
       -x $destination/scripts/install-hotkey.sh ]] || return 1
    shopt -s nullglob dotglob
    local scripts=("$destination"/scripts/*)
    shopt -u nullglob dotglob
    [[ ${#scripts[@]} -eq 1 ]] || return 1
    cmp -s "$destination/scripts/install-hotkey.sh" "$root/scripts/install-hotkey.sh" || return 1
    # The remaining payload uses the same guarded binary and seal checks as four-file installs.
  fi
  if [[ ${#contents[@]} -eq 4 || ${#contents[@]} -eq 5 ]]; then
    [[ $qml_file == Keyritual.qml && -d $destination/bin && ! -L $destination/bin &&
       -f $destination/bin/keyritual-core && ! -L $destination/bin/keyritual-core &&
       -x $destination/bin/keyritual-core && -f $destination/keyritual-seal.png &&
       ! -L $destination/keyritual-seal.png ]] || return 1
    shopt -s nullglob dotglob
    local bundled=("$destination"/bin/*)
    shopt -u nullglob dotglob
    [[ ${#bundled[@]} -eq 1 ]] || return 1
    cmp -s "$destination/keyritual-seal.png" "$root/assets/keyritual-seal.png" &&
      { cmp -s "$destination/bin/keyritual-core" "$root/bin/keyritual-core" ||
        { [[ ${#contents[@]} -eq 5 && ( $qml_hash == "$known_boxed_controls_qml" ||
             $qml_hash == "$known_compact_controls_qml" ) ]] &&
          { [[ $qml_hash != "$known_compact_controls_qml" ]] ||
            { [[ $old_manifest_hash == "$known_compact_controls_manifest" ||
                 $old_manifest_hash == "$(sha256sum "$root/manifest.json" | cut -d' ' -f1)" ]] &&
              cmp -s "$destination/$qml_file" "$root/Keyritual.qml"; }; } &&
          binary_hash="$(sha256sum "$destination/bin/keyritual-core")" &&
          [[ ${binary_hash%% *} == "$known_boxed_controls_binary" ]]; }; } &&
      { cmp -s "$destination/$qml_file" "$root/Keyritual.qml" ||
        [[ ${#contents[@]} -eq 5 && ( $qml_hash == "$known_hotkey_qml" || $qml_hash == "$known_boxed_controls_qml" ) ]]; }
  elif [[ ${#contents[@]} -eq 3 ]]; then
    [[ $qml_file == Keyritual.qml && -f $destination/keyritual-seal.png && ! -L $destination/keyritual-seal.png ]] || return 1
    cmp -s "$destination/keyritual-seal.png" "$root/assets/keyritual-seal.png" || return 1
    cmp -s "$destination/$qml_file" "$root/Keyritual.qml" || [[ $qml_hash == "$known_three_line_qml" || $qml_hash == "$known_fixed_prompt_qml" || $qml_hash == "$known_popup_history_qml" || $qml_hash == "$known_corner_qml" || $qml_hash == "$known_history_share_qml" ]]
  elif [[ $qml_file == Keyritual.qml ]]; then
    [[ $qml_hash == "$known_old_qml" || $qml_hash == "$known_previous_qml" || $qml_hash == "$known_practice_qml" || $qml_hash == "$known_focus_qml" || $qml_hash == "$known_escape_qml" || $qml_hash == "$known_ctrl_m_qml" || $qml_hash == "$known_reflect_qml" ]]
  elif [[ $qml_file == KeyritualView.qml || $qml_file == keyritual-screen.qml ]]; then
    [[ $qml_hash == "$known_reflect_qml" ]]
  else
    cmp -s "$destination/$qml_file" "$root/Keyritual.qml"
  fi
}

# Replace only a recognized local Keyritual installation; unknown content is never overwritten.
if [[ -e "$destination" || -L "$destination" ]]; then
  if [[ ! -f $root/manifest.json || ! -f $root/Keyritual.qml ||
        ! -x $root/bin/keyritual-core || ! -f $root/assets/keyritual-seal.png ]] || ! owned_payload; then
    printf 'Unrecognized plugin at %s; refusing replacement.\n' "$destination" >&2
    exit 1
  fi
  original_manifest_hash="$(sha256sum "$destination/manifest.json")"
  original_qml_hash="$(sha256sum "$destination/$qml_file")"
  original_qml_file="$qml_file"
  replacing=1
else
  replacing=0
fi

if [[ ! -x $root/bin/keyritual-core || ! -x $root/scripts/install-hotkey.sh ]]; then
  printf '%s\n' 'Bundled engine or optional hotkey script missing; run make bundle and check plugin files.' >&2
  exit 1
fi
if [[ "${1:-}" == '--check' ]]; then
  exit 0
fi

install -d "$plugins"
staging="$(mktemp -d "$plugins/.keyritual.XXXXXX")"
backup=''
activated=0
cleanup() {
  result=$?
  trap - EXIT
  if [[ $result -ne 0 && -n $backup && -d $backup/plugin ]]; then
    if [[ -e $destination || -L $destination ]]; then
      mv "$destination" "$backup/failed-replacement" || printf 'Failed to preserve failed replacement at %s\n' "$destination" >&2
    fi
    if [[ ! -e $destination && ! -L $destination ]]; then
      mv "$backup/plugin" "$destination" || printf 'ROLLBACK FAILED: original remains at %s/plugin\n' "$backup" >&2
    fi
  elif [[ $result -ne 0 && $activated -eq 1 && $replacing -eq 0 ]]; then
    mv "$destination" "$staging/failed-replacement" || true
  fi
  if [[ -d $staging ]]; then rm -rf -- "$staging"; fi
  if [[ -n $backup && -d $backup ]]; then
    printf 'Original plugin backup: %s/plugin\n' "$backup" >&2
  fi
  exit "$result"
}
trap cleanup EXIT
install -m644 "$root/manifest.json" "$staging/manifest.json"
install -m644 "$root/Keyritual.qml" "$staging/Keyritual.qml"
install -m644 "$root/assets/keyritual-seal.png" "$staging/keyritual-seal.png"
install -Dm755 "$root/bin/keyritual-core" "$staging/bin/keyritual-core"
install -Dm755 "$root/scripts/install-hotkey.sh" "$staging/scripts/install-hotkey.sh"
omarchy plugin validate "$staging"

# Recheck after validation to avoid replacing a changed installation.
if [[ $replacing -eq 1 ]]; then
  if ! owned_payload ||
     [[ $(sha256sum "$destination/manifest.json") != "$original_manifest_hash" ||
        $qml_file != "$original_qml_file" ||
        $(sha256sum "$destination/$original_qml_file") != "$original_qml_hash" ]]; then
    printf '%s\n' 'Plugin changed during validation; refusing replacement.' >&2
    exit 1
  fi
  backup="$(mktemp -d "$plugins/.keyritual-backup.XXXXXX")"
  mv "$destination" "$backup/plugin"
fi
mv "$staging" "$destination"
activated=1
omarchy-shell shell rescanPlugins
omarchy plugin enable "$id"
printf 'Installed local plugin: %s\n' "$destination"
