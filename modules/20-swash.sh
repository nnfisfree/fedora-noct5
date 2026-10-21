#!/usr/bin/env bash
# Build as the desktop user; only copy the staged installation as root.
source "$ROOT/packages/sources.sh"
fetch "$SWASH_URL" "$SWASH_SHA256" "$WORK/swash.tar.gz"
install -d -m 0755 -o "$TARGET_UID" -g "$TARGET_GID" "$WORK/build-user"
tar --extract --gzip --file "$WORK/swash.tar.gz" --directory "$WORK/build-user" --no-same-owner
chown -R "$TARGET_UID:$TARGET_GID" "$WORK/build-user"
src="$WORK/build-user/swash-$SWASH_VERSION"
build="$WORK/build-user/build"
stage="$WORK/build-user/stage"
as_user meson setup "$build" "$src" --prefix=/usr/local --buildtype=release
as_user meson compile -C "$build" -j 2
as_user meson test -C "$build" --print-errorlogs
as_user meson install -C "$build" --destdir "$stage"
# Preserve each existing destination before installing this pinned release.
while IFS= read -r -d '' file; do backup "${file#"$stage"}"; done < <(find "$stage" -type f -print0)
while IFS= read -r -d '' file; do
    mode=0644
    [[ -x $file ]] && mode=0755
    install -Dm "$mode" -- "$file" "${file#"$stage"}"
done < <(find "$stage" -type f -print0)
find "$stage" -type f -printf '/%P\n' > "$BACKUP/swash-installed-files.txt"
restorecon -RF /usr/local/bin/swash /usr/local/share/applications /usr/local/share/icons
/usr/local/bin/swash --version
