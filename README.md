# Fedora 44 · Hyprland + Noctalia
One entry point for a **regular Fedora 44 minimal x86_64 installation**, with no existing desktop or display manager. Uses Noctalia's default appearance. No CachyOS themes, bar layout, cursors, wallpaper, Fastfetch configuration, or login-shell modifications are installed.

## Run

You need a working Internet connection and an existing ordinary user with a login password. Extract the entire bundle, then run from a TTY:
```text
git clone https://github.com/nnfisfree/fedora-noct5.git
cd fedora-noct5
chmod +x install.sh
sudo bash install.sh "$USER"
sudo reboot
```

If logged in as root, use `bash install.sh alice`, replacing `alice` with the actual desktop user. The script does not create accounts or passwords. It prints completion only when all sections succeed. It never reboots or starts SDDM during installation.

After reboot, choose **Hyprland + Noctalia** in SDDM's session selector. This entry starts Hyprland through UWSM. Select this entry rather than the package's plain Hyprland entry.

## What it installs

- Hyprland and its screen-sharing portal from the community **lionheartp/Hyprland COPR**, currently linked by Hyprland's Fedora installation documentation. RPM signature checking remains enabled.
- Fedora's Noctalia v5 package, SDDM with its generic Weston Wayland greeter, and UWSM. Weston is used only for the login screen; no full desktop environment is installed.
- Mesa, firmware, XWayland, PipeWire/WirePlumber, NetworkManager/Wi-Fi, Bluetooth, UPower, power profiles, Polkit, a keyring, GTK file-picker portal, fonts and desktop utilities.
- Kitty, Dolphin, Firefox, a text editor, calculator, and btop, matching the supplied application shortcuts.
- **Swash 1.5.1**, built from a pinned, SHA-256-checked source archive as the ordinary user. Files are staged first and installed into `/usr/local` as root. Tesseract and English OCR data are included. Build dependencies stay installed. Compilation uses two jobs to limit memory use in a VM.

The installer refreshes and upgrades installed Fedora packages before installing the desktop. Missing packages or dependency failures stop the installation instead of being silently skipped. It requires Hyprland >= 0.56.2 and Noctalia >= 5.3.0, matching the configuration APIs researched for this bundle. RPM updates remain managed by DNF; Swash updates require changing the pinned release/checksum and rerunning its build through the installer.

## Swash integration

`config/noctalia/config.toml` contains only functional overrides:

- Enable Noctalia's Polkit agent and systemd application launching.
- Route region/fullscreen screenshots to `swash --stdin --name ...`.
- Route the clipboard image action to Swash as well.
- Let Swash handle saving or copying the edited result, instead of Noctalia saving an unedited duplicate.

**Print** selects a region; **Super+Print** captures the full screen. Both open Swash. Swash keeps its own default preferences; no CachyOS Swash appearance settings are copied. Use Swash's Save or Copy action to keep the edited image.

## Layout

```text
install.sh                  small entry point
lib/common.sh               staging, logs, backups, user execution
lib/enable-audio.sh         offline user-service enablement
check-session.sh           checks to run after graphical login
modules/00-preflight.sh     Fedora/user/session checks
modules/10-packages.sh      repositories and packages
modules/20-swash.sh         pinned source build
modules/30-user-config.sh   configuration and user audio units
modules/40-session.sh       config validation and next-boot login
packages/*.txt             package lists by section
packages/sources.sh        pinned Swash URL and checksum
config/hypr/               monitor, input, bindings, startup, rules
config/noctalia/           Swash and authentication integration
config/uwsm/               session environment
config/xdg-desktop-portal/ portal backend selection
system/                    SDDM and session entry
tests/                    local validation (no installation)
```

## Shortcuts and personal settings

| Shortcut | Action |
| --- | --- |
| Super+Return | Kitty |
| Super+Space | Noctalia launcher |
| Super+E / W / T / C | Files / browser / editor / calculator |
| Super+Z / X | Noctalia settings / control center |
| Super+V | Clipboard |
| Super+L | Lock |
| Super+Alt+C | Session menu |
| Super+Shift+W | Wallpaper selector |
| Print / Super+Print | Region / fullscreen screenshot → Swash |
| Super+Q / F | Close / fullscreen |
| Super+Alt+Space | Toggle floating |
| Super+arrows | Focus a window |
| Super+1…0 | Workspaces 1…10 |
| Super+Shift+1…0 | Move window to workspace |
| Super+left/right drag | Move/resize window |

Edit `~/.config/hypr/config/input.lua` for the keyboard layout (initially US), and `monitors.lua` for display layout/scaling. Noctalia settings control its appearance. Unspecified compositor appearance settings keep Hyprland defaults.

The graphics setup uses Fedora's kernel/Mesa drivers. Proprietary NVIDIA driver installation, Secure Boot key enrollment, and hardware-specific driver workarounds are **not automated**; machines requiring those need that hardware setup separately. This bundle does not guarantee every GPU/VM supports Hyprland. Intel and AMD systems normally use the installed open drivers.

## Backups, reruns and recovery

The installer replaces only `~/.config/{hypr,noctalia,uwsm,xdg-desktop-portal}`. Before replacing them, it backs them up under `/var/backups/hypr-noctalia/TIMESTAMP-PID/`, preserving absolute paths inside that directory. It also moves each previous user directory beside the new one with a `.before-hypr-noctalia-...` suffix. Existing system files that this installer changes are backed up too. Audio setup also backs up `~/.config/systemd/user` and adds PipeWire/WirePlumber enablement links there. It does not populate `/etc/skel` or change other users.

Rerunning reinstalls the supplied configuration: back up any edits you want to keep. Fedora packages are not downgraded, and no complete system rollback is attempted on failure. Packages, the COPR, and already completed sections may remain installed after an error. A persistent log is saved at `/var/log/hypr-noctalia-*.log`, and temporary build files are retained on failure. Fix the reported issue and rerun. `sudo bash install.sh --resume "$USER"` is available only when packages and Swash already installed successfully; it reruns configuration and login setup.

The previous boot target is recorded in `previous-default-target` inside the backup. To return to console boot from another TTY (Ctrl+Alt+F3):

```bash
sudo systemctl disable sddm
sudo systemctl set-default multi-user.target
sudo reboot
```

After graphical login, run `bash check-session.sh` from the extracted bundle. Also test sound, Print → Swash, locking/unlocking and screen sharing manually.

For troubleshooting:

```bash
journalctl -b -u sddm
journalctl --user -b
hyprctl configerrors
cat ~/.cache/noctalia/noctalia.log
```

To remove the manually built Swash later, inspect `swash-installed-files.txt` in the relevant backup and remove only those listed files, restoring backed-up predecessors where appropriate. Do not recursively delete `/usr/local`.

## Validation and sources

Run `python3 tests/validate.py` from this directory for Bash syntax, TOML/integration, dependency-list and Lua syntax checks (Lua checks run when `luac` is available). During installation, **Hyprland's own `--verify-config` runs before enabling graphical boot**. These checks do not replace testing login, GPU rendering, audio, locking, screenshots and portals on a Fedora 44 machine.

References inspected while preparing the bundle:

- [Requested CachyOS package](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/cachyos-hypr-noctalia), pointing to [configuration release 1.2.6](https://github.com/CachyOS/cachyos-hypr-noctalia/tree/1.2.6). Used as a functional reference only; appearance files are not copied.
- [Hyprland installation](https://wiki.hypr.land/Getting-Started/Installation/) and [0.56.2 configuration example](https://github.com/hyprwm/Hyprland/blob/v0.56.2/example/hyprland.lua).
- [Fedora Noctalia package](https://packages.fedoraproject.org/pkgs/noctalia/noctalia/) and [Noctalia installation](https://docs.noctalia.dev/noctalia/getting-started/installation/).
- [UWSM display-manager integration](https://github.com/Vladimir-csp/uwsm#readme).
- [Fedora's SDDM Wayland greeter](https://packages.fedoraproject.org/pkgs/sddm/sddm-wayland-generic/).
- [Swash source and build instructions](https://github.com/ItsLemmy/swash/tree/v1.5.1). Swash is GPL-3.0-or-later; its source license remains with the downloaded source.
