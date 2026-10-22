#!/usr/bin/env bash
# Check and update the 22 plugins via the companion source installer.
# Normal user run. Only DNF and final file deployment use sudo.

set -Eeuo pipefail
command -v python3 >/dev/null || { echo 'Python 3 is required.' >&2; exit 2; }
exec python3 - "$0" "$@" <<'PYTHON'
import argparse
import csv
import json
import os
from pathlib import Path
import re
import sys
import subprocess
import urllib.error
import urllib.parse
import urllib.request

SCRIPT_PATH = Path(sys.argv.pop(1)).resolve()

REPOS = ['exeldro/obs-source-clone', 'FiniteSingularity/obs-stroke-glow-shadow', 'exeldro/obs-shaderfilter', 'FiniteSingularity/obs-noise', 'FiniteSingularity/obs-composite-blur', 'FiniteSingularity/obs-advanced-masks', 'nowrep/obs-vkcapture', 'exeldro/obs-transition-table', 'exeldro/obs-source-record', 'exeldro/obs-source-dock', 'exeldro/obs-source-copy', 'exeldro/obs-3d-effect', 'xurei/shadertastic', 'FiniteSingularity/obs-retro-effects', 'exeldro/obs-recursion-effect', 'dspstanky/pixel-art', 'exeldro/obs-move-transition', 'exeldro/obs-gradient-source', 'exeldro/obs-freeze-filter', 'exeldro/obs-draw', 'exeldro/obs-downstream-keyer', 'Aitum/obs-aitum-multistream']


def clean(value):
    # Keep untrusted release names/errors from injecting terminal control codes.
    return ''.join(c if c.isprintable() else '?' for c in str(value))


def api(path):
    request = urllib.request.Request(
        'https://api.github.com/repos/' + path,
        headers={'Accept': 'application/vnd.github+json',
                 'User-Agent': 'obs-plugin-update-checker',
                 'X-GitHub-Api-Version': '2022-11-28'})
    # Public repositories need no token. An optional token raises the rate limit.
    token = os.environ.get('GITHUB_TOKEN')
    if token:
        request.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code in (403, 429):
            raise RuntimeError('GitHub access/rate limit; retry later or set GITHUB_TOKEN') from None
        if exc.code == 404:
            raise RuntimeError('repository, release or comparison not found (HTTP 404)') from None
        raise RuntimeError('GitHub HTTP ' + str(exc.code)) from None
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        raise RuntimeError('network timeout, connection failure or invalid GitHub response') from None


def read_records(paths):
    records = {}
    for path in paths:
        with path.open(newline='') as stream:
            reader = csv.DictReader(stream, delimiter='\t')
            if reader.fieldnames != ['plugin', 'repository', 'tag', 'commit']:
                raise ValueError('Invalid sources.tsv header: ' + str(path))
            for row in reader:
                repo = row.get('repository')
                if repo not in REPOS:
                    continue
                if (row.get('plugin') != repo.split('/')[-1] or not row.get('tag')
                        or not re.fullmatch(r'[0-9a-fA-F]{40}', row.get('commit') or '')):
                    raise ValueError('Invalid source record: ' + str(path))
                records[repo] = row
    return records


def discover(parent):
    # sources.tsv is created BEFORE compilation. Only a successful final log
    # message qualifies a run for automatic discovery; build-only/failed runs
    # must never override a previous installed version.
    completed = []
    for manifest in parent.glob('run-*/sources.tsv'):
        log = manifest.parent / 'installer.log'
        if log.is_file() and re.search(
                r'^Installed all [0-9]+ selected plugins\. Restart native OBS',
                log.read_text(errors='replace'), re.MULTILINE):
            completed.append((log.stat().st_mtime_ns, str(manifest), manifest))
    return [item[2] for item in sorted(completed)]


def check(repo, record):
    latest = api(repo + '/releases/latest')
    tag = latest.get('tag_name')
    if not isinstance(tag, str) or not tag or latest.get('draft') or latest.get('prerelease'):
        raise RuntimeError('GitHub did not return a stable release')
    url = 'https://github.com/' + repo + '/releases/tag/' + urllib.parse.quote(tag, safe='')
    if record is None:
        return 'UNKNOWN LOCAL', tag, url
    if record['tag'] == tag:
        return 'UP TO DATE', tag, url
    # Compare the recorded commit, not the old tag's current target. Do not
    # assume any different tag is newer (release branches can diverge).
    compare = api(repo + '/compare/' + record['commit'] + '...' +
                  urllib.parse.quote(tag, safe='') + '?per_page=1')
    status = {'ahead': 'UPDATE AVAILABLE', 'behind': 'LOCAL AHEAD',
              'identical': 'SAME COMMIT', 'diverged': 'REVIEW RELEASE'}.get(compare.get('status'))
    if status is None:
        raise RuntimeError('Unexpected GitHub comparison status')
    return status, tag, url


def main():
    parser = argparse.ArgumentParser(prog='check-obs-plugin-updates.sh', description='Check stable releases and rebuild available plugin updates from source.')
    parser.add_argument('--work-dir', type=Path,
        default=Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'obs-fedora44-source',
        help='installer build directory (default: the installer cache directory)')
    parser.add_argument('--manifest', type=Path, action='append',
        help='explicit sources.tsv baseline; repeat to merge, later files take precedence')
    parser.add_argument('--only', choices=[r.split('/')[-1] for r in REPOS],
        help='check just one plugin')
    parser.add_argument('--list', action='store_true', help='list repositories and exit without network access')
    parser.add_argument('--check-only', action='store_true',
        help='report updates without installing anything')
    parser.add_argument('--installer', type=Path,
        default=SCRIPT_PATH.with_name('install-obs-fedora44.sh'),
        help='companion installer (default: next to this script)')
    parser.add_argument('--jobs', type=int, help='compiler jobs passed to the installer')
    args = parser.parse_args()
    if args.jobs is not None and args.jobs < 1:
        parser.error('--jobs must be a positive integer')
    if args.list:
        print('\n'.join(REPOS))
        return 0
    try:
        paths = args.manifest if args.manifest else discover(args.work_dir.expanduser())
        records = read_records([p.expanduser() for p in paths])
    except (OSError, ValueError) as exc:
        print('ERROR: ' + clean(exc), file=sys.stderr)
        return 2
    print('Comparing GitHub stable releases with recorded installer versions (not live binary detection).')
    if args.manifest:
        print('Explicit manifests are comparison baselines; they may describe uninstalled builds.')
    elif paths:
        print(f'Using {len(paths)} completed installer run(s); newest record wins for each plugin.')
    else:
        print('No completed installer records found. Latest versions will still be shown.')
    print('')
    print(f"{'PLUGIN':27} {'RECORDED':15} {'LATEST':15} STATUS")
    print('-' * 82)
    updates = errors = unknown = review = 0
    pending = []
    for repo in REPOS:
        name = repo.split('/')[-1]
        if args.only and name != args.only:
            continue
        record = records.get(repo)
        previous = record['tag'] if record else '—'
        try:
            status, tag, url = check(repo, record)
            print(f'{name:27} {clean(previous):15} {clean(tag):15} {status}', flush=True)
            if status == 'UPDATE AVAILABLE':
                updates += 1
                pending.append(name)
            elif status == 'UNKNOWN LOCAL':
                unknown += 1
            elif status == 'REVIEW RELEASE':
                review += 1
            if status != 'UP TO DATE':
                print('  ' + url, flush=True)
        except (RuntimeError, KeyError, TypeError, AttributeError) as exc:
            errors += 1
            print(f'{name:27} {clean(previous):15} {"?":15} ERROR: {clean(exc)}', flush=True)
    print(f'\n{updates} update(s), {unknown} unknown local version(s), {review} release(s) to review, {errors} error(s).')
    if args.check_only:
        print('Check-only mode: no packages or plugins were changed.')
        return 2 if errors or unknown or review else (1 if updates else 0)
    if not pending:
        print('No confirmed updates to install. No packages or plugins were changed.')
        return 2 if errors or unknown or review else 0
    installer = args.installer.expanduser().resolve()
    if not installer.is_file():
        print('ERROR: Companion installer not found: ' + str(installer), file=sys.stderr)
        print('Keep both scripts together or supply --installer PATH.', file=sys.stderr)
        return 2
    if os.geteuid() == 0:
        print('ERROR: Run as your normal user; the installer invokes sudo itself.', file=sys.stderr)
        return 2
    print('\nUpdating confirmed updates from source. Close OBS before proceeding.', flush=True)
    print('Unknown local versions and diverged releases are skipped.', flush=True)
    updated = []
    for name in pending:
        command = ['bash', str(installer), '--only', name,
                   '--work-dir', str(args.work_dir.expanduser().resolve())]
        if args.jobs is not None:
            command += ['--jobs', str(args.jobs)]
        print('\nUpdating ' + name + ' ...', flush=True)
        try:
            result = subprocess.run(command, check=False)
        except OSError as exc:
            print('ERROR: Cannot launch installer: ' + clean(exc), file=sys.stderr)
            return 2
        if result.returncode != 0:
            print(f'Update failed for {name} (installer exit {result.returncode}).', file=sys.stderr)
            print('Stopping further updates. Previously completed updates remain installed.', file=sys.stderr)
            print('Completed this run: ' + (', '.join(updated) or 'none'), file=sys.stderr)
            return 2
        updated.append(name)
    print('\nSuccessfully updated: ' + ', '.join(updated))
    print('Restart native OBS. Installer logs and backups are under ' + str(args.work_dir.expanduser()))
    return 2 if errors or unknown or review else 0



if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('\nCheck interrupted.', file=sys.stderr)
        sys.exit(130)
PYTHON
