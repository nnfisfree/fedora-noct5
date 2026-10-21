#!/usr/bin/env bash
# This is the Fedora repository currently documented by the Hyprland project.
dnf -y install dnf5-plugins ca-certificates curl python3 tar gzip
printf '%s\n' 'Enabling community repository lionheartp/Hyprland (RPM signatures remain enabled).'
dnf -y copr enable lionheartp/Hyprland
dnf -y --refresh upgrade
mapfile -t packages < <(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$ROOT"/packages/*.txt)
# DNF must resolve every dependency; do not silently skip broken/missing packages.
dnf -y install "${packages[@]}"
python3 - <<'CHECK'
import subprocess
for name, minimum in [('hyprland', (0,56,2)), ('noctalia', (5,3,0))]:
    version = subprocess.check_output(['rpm','-q','--qf','%{VERSION}',name], text=True)
    parts = tuple(int(x) for x in version.split('.')[:3])
    if parts < minimum:
        raise SystemExit(f'{name} {version} is too old; need {minimum}')
CHECK
