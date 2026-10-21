#!/usr/bin/env bash
# Run as the target user. Write enablement links without contacting systemd/D-Bus.
set -euo pipefail
unit_dir=$1
for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
    [[ -f /usr/lib/systemd/user/$unit ]] || { echo "Missing user unit: $unit" >&2; exit 1; }
    [[ $(readlink "$unit_dir/$unit" || true) != /dev/null ]] || {
        echo "User unit is masked: $unit. Unmask it before retrying." >&2; exit 1;
    }
done
mkdir -p "$unit_dir/sockets.target.wants" "$unit_dir/pipewire.service.wants"
ln -sfn /usr/lib/systemd/user/pipewire.socket "$unit_dir/sockets.target.wants/pipewire.socket"
ln -sfn /usr/lib/systemd/user/pipewire-pulse.socket "$unit_dir/sockets.target.wants/pipewire-pulse.socket"
ln -sfn /usr/lib/systemd/user/wireplumber.service "$unit_dir/pipewire.service.wants/wireplumber.service"
ln -sfn /usr/lib/systemd/user/wireplumber.service "$unit_dir/pipewire-session-manager.service"
