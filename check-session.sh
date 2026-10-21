#!/usr/bin/env bash
# Run inside the installed Hyprland session as the desktop user.
set -u
failed=0
check() {
    local label=$1; shift
    if "$@"; then printf 'PASS: %s\n' "$label"; else printf 'FAIL: %s\n' "$label"; failed=1; fi
}
check 'Hyprland IPC' hyprctl version
check 'Noctalia process' pgrep -u "$(id -u)" -x noctalia
check 'Swash executable' swash --version
for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
    check "$unit" systemctl --user is-active "$unit"
done
check 'NetworkManager' systemctl is-active NetworkManager.service
check 'Desktop portal' busctl --user --timeout=15 introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.FileChooser
errors=$(hyprctl configerrors 2>&1) || failed=1
if [[ -n $errors && $errors != 'ok' ]]; then printf 'Hyprland config check: %s\n' "$errors"; failed=1; fi
echo 'Also test Print → Swash, sound playback, Super+L unlock, and a browser screen-share dialog.'
exit "$failed"
