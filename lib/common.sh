#!/usr/bin/env bash
fail() { echo "ERROR: $*" >&2; exit 1; }
as_user() { runuser -u "$TARGET_USER" -- env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME HOME="$TARGET_HOME" "$@"; }
backup() {
    local path=$1
    if [[ -e $path || -L $path ]]; then
        mkdir -p "$BACKUP$(dirname "$path")"
        cp -a -- "$path" "$BACKUP$path"
    fi
}
fetch() {
    local url=$1 checksum=$2 destination=$3
    curl --fail --location --retry 3 --connect-timeout 20 --proto '=https' \
        --tlsv1.2 "$url" -o "$destination"
    printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check --status || fail "Checksum mismatch: $url"
}

prepare_workdir() {
    # Both full and resumed installs execute staged files as the desktop user.
    # Keep the parent root-owned and unwritable, but allow directory traversal.
    chmod 0755 "$WORK"
}

report_error() {
    printf '\nERROR (%s), line %s: %s\nSource stack: %s\nLog: %s\n' "$1" "$2" "$3" "$4" "${LOG:-not yet created}" >&2
}
cleanup() {
    local status=$?
    if (( status == 0 )); then
        rm -rf -- "$WORK"
    else
        printf 'Installation incomplete. Diagnostic files retained in %s\n' "$WORK" >&2
    fi
}
