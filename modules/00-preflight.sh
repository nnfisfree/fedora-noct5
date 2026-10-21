#!/usr/bin/env bash
source /etc/os-release
[[ $ID == fedora && $VERSION_ID == 44 ]] || fail "This installer requires Fedora 44."
[[ $(uname -m) == x86_64 ]] || fail "This bundle was checked for x86_64 only."
[[ ! -e /run/ostree-booted ]] || fail "Use regular Fedora, not an Atomic/OSTree image."
[[ -n $TARGET_USER && $TARGET_USER != root && $TARGET_USER != -* ]] || fail "Supply an existing non-root username."
entry=$(getent passwd "$TARGET_USER") || fail "Unknown user: $TARGET_USER"
IFS=: read -r _ _ TARGET_UID TARGET_GID _ TARGET_HOME TARGET_SHELL <<< "$entry"
[[ $TARGET_UID -ge 1000 && -d $TARGET_HOME && $TARGET_HOME == /* && $TARGET_HOME != / ]] || fail "Expected a regular user with an existing home."
[[ $TARGET_SHELL != */nologin && $TARGET_SHELL != */false ]] || fail "User has no login shell."
[[ -d /run/systemd/system ]] || fail "Run on the booted system, not inside a chroot."
command -v dnf >/dev/null || fail "dnf is required."
if [[ -L /etc/systemd/system/display-manager.service ]]; then
    [[ $(readlink -f /etc/systemd/system/display-manager.service) == */sddm.service ]] || fail "Another display manager is configured; this installer targets a minimal installation."
fi
# Refuse concurrent installs before creating temporary state.
exec 9>/run/hypr-noctalia-install.lock
flock -n 9 || fail "Another installer is running."
