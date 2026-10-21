#!/usr/bin/env bash
cp -R "$ROOT/config" "$WORK/config"
chmod -R a+rX "$WORK/config"
# Check staged files BEFORE moving any existing configuration out of the way.
as_user test -r "$WORK/config/hypr/hyprland.lua"
install -m 0644 "$ROOT/lib/enable-audio.sh" "$WORK/enable-audio.sh"
as_user test -r "$WORK/enable-audio.sh"
# Replace only the managed directories, with a full backup of each first.
# Do this as the desktop user so symlinked home-directory paths cannot cause root writes.
for name in hypr noctalia uwsm xdg-desktop-portal; do
    dest="$TARGET_HOME/.config/$name"
    backup "$dest"
    as_user mkdir -p "$TARGET_HOME/.config"
    if [[ -e $dest || -L $dest ]]; then
        as_user mv -- "$dest" "$dest.before-hypr-noctalia-$(basename "$BACKUP")"
    fi
    as_user cp -R --no-preserve=ownership "$WORK/config/$name" "$dest"
done
as_user xdg-user-dirs-update
# Configure the next login without requiring a user bus during installation.
backup "$TARGET_HOME/.config/systemd/user"
as_user bash "$WORK/enable-audio.sh" "$TARGET_HOME/.config/systemd/user"
restorecon -RF "$TARGET_HOME/.config/hypr" "$TARGET_HOME/.config/noctalia" \
    "$TARGET_HOME/.config/uwsm" "$TARGET_HOME/.config/xdg-desktop-portal" \
    "$TARGET_HOME/.config/systemd/user"
