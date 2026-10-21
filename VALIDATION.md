# Validation

Local checks passed:

- Bash and Lua syntax checks.
- Six regression tests covering configuration staging, backups, repeat runs, offline audio enablement, package lists and screenshot piping.
- ShellCheck at warning level, excluding cross-module source/variable warnings (SC1090, SC1091, SC2034).
- Swash 1.5.1 source checksum, local compilation, upstream test and staged installation.

The two reported installation failures are corrected:

1. Audio enablement writes per-user systemd links without requiring an active user bus.
2. Both full and resumed installations prepare a traversable, root-owned temporary directory before running any section as the desktop user. Staged-file readability is checked before replacing configuration.

The bundle also includes persistent installation logs, retained diagnostic files on failure, two-job compilation for smaller VMs, and a post-login check script.

A disposable Fedora 44 VM test resolved the package transaction successfully, but was stopped at the user's request before installation finished. A complete installation and graphical login are **not verified**. During installation, the target machine runs Swash's tests and Hyprland's configuration validator before graphical boot is enabled.
