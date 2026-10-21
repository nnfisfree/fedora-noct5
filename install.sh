#!/usr/bin/env bash
set -Eeuo pipefail
umask 022
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ ${1:-} == --help ]]; then
    echo "Usage: sudo bash install.sh [--resume] [existing-username]"
    echo "Fedora 44 x86_64; enables lionheartp/Hyprland COPR; reboot manually afterwards."
    exit 0
fi
[[ $EUID == 0 ]] || { echo "Run with sudo or as root." >&2; exit 1; }
RESUME=false
if [[ ${1:-} == --resume ]]; then RESUME=true; shift; fi
[[ $# -le 1 ]] || { echo "Expected at most one username." >&2; exit 1; }
TARGET_USER=${1:-${SUDO_USER:-}}
source "$ROOT/lib/common.sh"
source "$ROOT/modules/00-preflight.sh"
WORK=$(mktemp -d /var/tmp/hypr-noctalia.XXXXXXXX)
trap cleanup EXIT
prepare_workdir
LOG=/var/log/hypr-noctalia-$(date +%Y%m%d-%H%M%S)-$$.log
install -m 0600 /dev/null "$LOG"
exec > >(tee -a "$LOG") 2>&1
trap 'report_error "$?" "$LINENO" "$BASH_COMMAND" "${BASH_SOURCE[*]}"' ERR
printf 'Installer log: %s\n' "$LOG"
BACKUP=/var/backups/hypr-noctalia/$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$BACKUP"
systemctl get-default > "$BACKUP/previous-default-target"
sections=(10-packages 20-swash 30-user-config 40-session)
if $RESUME; then
    for binary in Hyprland noctalia uwsm swash; do
        command -v "$binary" >/dev/null || fail "Cannot resume: $binary is missing. Run the full installer."
    done
    sections=(30-user-config 40-session)
fi
for section in "${sections[@]}"; do
    echo "==> $section"
    source "$ROOT/modules/$section.sh"
done
printf '\nInstalled for %s. Backups: %s\n' "$TARGET_USER" "$BACKUP"
echo 'Reboot, then select “Hyprland + Noctalia” in SDDM.'
echo 'Super+Return: terminal; Super+Space: launcher; Print: screenshot → Swash.'
