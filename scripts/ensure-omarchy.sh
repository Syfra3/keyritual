#!/usr/bin/env bash
set -euo pipefail

if command -v omarchy-shell >/dev/null 2>&1; then
  if omarchy-shell shell rescanPlugins >/dev/null 2>&1; then
    exit 0
  fi
  printf '%s\n' 'omarchy-shell is installed but the Quattro desktop shell is not responding. Finish the Omarchy upgrade/reboot and log in before rerunning make install.' >&2
  exit 1
fi

if ! command -v omarchy >/dev/null 2>&1 || ! omarchy upgrade to quattro --help >/dev/null 2>&1; then
  printf '%s\n' 'Omarchy Quattro is required. Install or upgrade Omarchy with its official instructions before installing Keyritual.' >&2
  exit 1
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  printf '%s\n' 'Omarchy Quattro upgrade needs an interactive terminal. Run make install there (or run omarchy upgrade to quattro directly).' >&2
  exit 1
fi

printf '%s\n' 'Keyritual needs Omarchy Quattro. Starting the official interactive Omarchy 3 -> 4 upgrade.'
printf '%s\n' 'The upgrader will ask you to confirm the system migration and give reboot instructions.'
omarchy upgrade to quattro

# The running desktop can remain on Omarchy 3 until reboot. Never proceed to
# install or enable a Quattro plugin in that transitional session.
printf '%s\n' 'Omarchy upgrade command returned. If you completed it, follow its reboot instructions; then rerun make install to install Keyritual.' >&2
exit 1
