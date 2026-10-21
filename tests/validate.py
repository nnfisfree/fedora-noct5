#!/usr/bin/env python3
"""Validate the bundle without installing anything or requiring root."""
import pathlib
import shutil
import subprocess
import tempfile
import tomllib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class BundleTests(unittest.TestCase):
    def test_shell_syntax(self):
        for path in ROOT.rglob('*.sh'):
            subprocess.run(['bash', '-n', str(path)], check=True)
        subprocess.run(['bash', str(ROOT/'install.sh'), '--help'], check=True,
                       stdout=subprocess.DEVNULL)

    def test_lua_syntax(self):
        if not shutil.which('luac'):
            self.skipTest('luac unavailable; install-time Hyprland validation is still mandatory')
        for path in (ROOT/'config/hypr').rglob('*.lua'):
            subprocess.run(['luac', '-p', str(path)], check=True)

    def test_screenshot_pipe(self):
        config = tomllib.loads((ROOT/'config/noctalia/config.toml').read_text())
        self.assertEqual(set(config), {'shell'})  # No appearance overrides.
        shot = config['shell']['screenshot']
        self.assertTrue(shot['pipe_to_command'])
        self.assertFalse(shot['save_to_file'])
        with tempfile.TemporaryDirectory() as temp:
            exe = pathlib.Path(temp)/'swash'
            exe.write_text('#!/bin/bash\n[[ $1 == --stdin && $2 == --name && $3 == *.png ]] || exit 9\ncat\n')
            exe.chmod(0o755)
            import os
            env = dict(os.environ, PATH=f'{temp}:'+os.environ['PATH'])
            for command in (shot['pipe_command'], config['shell']['clipboard_image_action_command']):
                result = subprocess.run(['bash', '-c', command], input=b'PNG-payload',
                                        stdout=subprocess.PIPE, env=env, check=True)
                self.assertEqual(result.stdout, b'PNG-payload')

    def test_resume_config_stage(self):
        # Exercise the actual staging/copy/audio code from an mktemp-style 0700
        # parent. No package/build module runs first. Host privilege switching
        # and SELinux relabeling are outside this unprivileged test.
        with tempfile.TemporaryDirectory() as temp:
            fixture = pathlib.Path(temp)
            for name in ('work', 'home', 'backup'):
                (fixture/name).mkdir(mode=0o700)
            script = r"""
set -Eeuo pipefail
ROOT=$1
WORK=$2/work
TARGET_HOME=$2/home
BACKUP=$2/backup
source "$ROOT/lib/common.sh"
prepare_workdir
as_user() {
    # Assert the access required by a different UID, then execute real file I/O.
    [[ $(stat -c %a "$WORK") == 755 ]]
    if [[ $1 == xdg-user-dirs-update ]]; then return 0; fi
    env -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR HOME="$TARGET_HOME" "$@"
}
restorecon() { :; }
source "$ROOT/modules/30-user-config.sh"
"""
            subprocess.run(['bash', '-c', script, 'test', str(ROOT), temp], check=True)
            config = fixture/'home/.config'
            self.assertEqual((config/'hypr/hyprland.lua').read_bytes(),
                             (ROOT/'config/hypr/hyprland.lua').read_bytes())
            self.assertTrue((config/'systemd/user/pipewire-session-manager.service').is_symlink())
            self.assertEqual((fixture/'work').stat().st_mode & 0o777, 0o755)
            # Preserve edits on another resumed run.
            (config/'hypr/local-note').write_text('keep this')
            subprocess.run(['bash', '-c', script, 'test', str(ROOT), temp], check=True)
            self.assertEqual((config/'hypr.before-hypr-noctalia-backup/local-note').read_text(),
                             'keep this')

    def test_audio_without_user_bus(self):
        import os
        units = ['pipewire.socket', 'pipewire-pulse.socket', 'wireplumber.service']
        if not all((pathlib.Path('/usr/lib/systemd/user')/u).exists() for u in units):
            self.skipTest('Host lacks the PipeWire/WirePlumber unit files')
        with tempfile.TemporaryDirectory() as temp:
            env = dict(os.environ)
            env.pop('DBUS_SESSION_BUS_ADDRESS', None)
            env.pop('XDG_RUNTIME_DIR', None)
            config = pathlib.Path(temp)/'systemd/user'
            for _ in range(2):  # The repair must also be idempotent.
                subprocess.run(['bash', str(ROOT/'lib/enable-audio.sh'), str(config)],
                               env=env, check=True)
            expected = {
                'sockets.target.wants/pipewire.socket': 'pipewire.socket',
                'sockets.target.wants/pipewire-pulse.socket': 'pipewire-pulse.socket',
                'pipewire.service.wants/wireplumber.service': 'wireplumber.service',
                'pipewire-session-manager.service': 'wireplumber.service',
            }
            for link, unit in expected.items():
                self.assertEqual(os.readlink(config/link), '/usr/lib/systemd/user/'+unit)
            (config/'pipewire.socket').symlink_to('/dev/null')
            result = subprocess.run(['bash', str(ROOT/'lib/enable-audio.sh'), str(config)],
                                    env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_manifest_and_startup(self):
        names = [line.strip() for p in (ROOT/'packages').glob('*.txt')
                 for line in p.read_text().splitlines() if line.strip() and not line.startswith('#')]
        self.assertEqual(len(names), len(set(names)))
        self.assertNotIn('fastfetch', names)
        self.assertTrue({'hyprland','noctalia','uwsm','sddm-wayland-generic',
                         'gtk4-devel','libadwaita-devel','pipewire-pulseaudio'} <= set(names))
        startup = (ROOT/'config/hypr/config/autostart.lua').read_text()
        self.assertIn('uwsm finalize &&', startup)
        self.assertIn('&& noctalia', startup)
        session = (ROOT/'modules/40-session.sh').read_text()
        self.assertLess(session.index('--verify-config'), session.index('enable sddm'))
        self.assertLess(session.index('enable sddm'), session.index('set-default graphical.target'))

if __name__ == '__main__':
    unittest.main(verbosity=2)
