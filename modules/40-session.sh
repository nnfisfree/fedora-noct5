#!/usr/bin/env bash
[[ -f /usr/share/wayland-sessions/hyprland.desktop ]] || fail "Hyprland session entry is missing."
install -d -m 0700 -o "$TARGET_UID" -g "$TARGET_GID" "$WORK/verify-runtime"
as_user env XDG_RUNTIME_DIR="$WORK/verify-runtime" XDG_CONFIG_HOME="$TARGET_HOME/.config" \
    Hyprland --verify-config --config "$TARGET_HOME/.config/hypr/hyprland.lua"
backup /usr/share/wayland-sessions/hyprland-noctalia.desktop
install -m 0644 "$ROOT/system/hyprland-noctalia.desktop" /usr/share/wayland-sessions/
backup /etc/sddm.conf.d/90-hypr-noctalia.conf
install -Dm0644 "$ROOT/system/sddm.conf" /etc/sddm.conf.d/90-hypr-noctalia.conf
restorecon -RF /etc/sddm.conf.d /usr/share/wayland-sessions
systemctl enable NetworkManager.service bluetooth.service
systemctl enable sddm.service
# Last operation: next boot gets the greeter. Never interrupt the installing TTY.
systemctl set-default graphical.target
