#!/usr/bin/env bash
# Fedora 4x native OBS installation with & cool plugins i use.
# Normal user run. Only DNF and final file deployment use sudo.

set -Eeuo pipefail
umask 022
REPOS=(
 exeldro/obs-source-clone
 FiniteSingularity/obs-stroke-glow-shadow
 exeldro/obs-shaderfilter
 FiniteSingularity/obs-noise
 FiniteSingularity/obs-composite-blur
 FiniteSingularity/obs-advanced-masks
 nowrep/obs-vkcapture
 exeldro/obs-transition-table
 exeldro/obs-source-record
 exeldro/obs-source-dock
 exeldro/obs-source-copy
 exeldro/obs-3d-effect
 xurei/shadertastic
 FiniteSingularity/obs-retro-effects
 exeldro/obs-recursion-effect
 dspstanky/pixel-art
 exeldro/obs-move-transition
 exeldro/obs-gradient-source
 exeldro/obs-freeze-filter
 exeldro/obs-draw
 exeldro/obs-downstream-keyer
 Aitum/obs-aitum-multistream
)
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
 cat <<'HELP'
Usage: bash install-obs-fedora44.sh [options]
  --list                 List the 22 source repositories; do nothing else
  --only NAME            Build just this repository basename (e.g. obs-move-transition)
  --jobs N               Compiler jobs (default: CPU count, capped at 4)
  --work-dir PATH        Parent for a new, retained build/log/backup directory
  --build-only           Install dependencies and build/stage; do not deploy plugins
  --help                 Show help

Requires Fedora 44 x86_64, a normal sudo-capable user, and internet access.
Close OBS first. DNF uses ONLY the official fedora and updates repositories.
OBS is synchronized to their newest available package; each plugin uses the
GitHub API's latest non-prerelease release tag at execution time.
No plugin release binaries are downloaded. Shadertastic's upstream build does
fetch binary ONNX Runtime/OpenCV dependencies. Sources/submodules are compiled
without sudo. All plugins must build and validate before any are deployed.
HELP
}
ONLY='' BUILD_ONLY=0 JOBS='' WORK_PARENT="${XDG_CACHE_HOME:-$HOME/.cache}/obs-fedora44-source"
while (($#)); do
 case $1 in
  --help|-h) usage; exit 0 ;;
  --list) printf '%s\n' "${REPOS[@]}"; exit 0 ;;
  --only|--jobs|--work-dir)
   (($# >= 2)) || die "Missing value for $1"
   case $1 in --only) ONLY=$2;; --jobs) JOBS=$2;; --work-dir) WORK_PARENT=$2;; esac
   shift 2 ;;
  --build-only) BUILD_ONLY=1; shift ;;
  *) die "Unknown option: $1" ;;
 esac
done
if [[ -n $ONLY ]]; then
 selected=()
 for repo in "${REPOS[@]}"; do [[ ${repo##*/} != "$ONLY" ]] || selected+=("$repo"); done
 ((${#selected[@]} == 1)) || die "Unknown plugin: $ONLY (see --list)"
 REPOS=("${selected[@]}")
fi
[[ -z $JOBS || $JOBS =~ ^[1-9][0-9]*$ ]] || die '--jobs must be a positive integer'
((EUID != 0)) || die 'Run as your normal user, without sudo; the script invokes sudo when needed.'
[[ -r /etc/os-release ]] || die 'Missing /etc/os-release'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == fedora && ${VERSION_ID:-} == 44 ]] || die 'This installer requires Fedora 44.'
[[ $(uname -m) == x86_64 ]] || die 'This recipe supports x86_64 (Shadertastic includes x86_64 dependency archives).'
for cmd in sudo dnf rpm pgrep flock; do command -v "$cmd" >/dev/null || die "Missing command: $cmd"; done
pgrep -x obs >/dev/null && die 'Close OBS before running this installer.'
if [[ -z $JOBS ]]; then JOBS=$(getconf _NPROCESSORS_ONLN); ((JOBS <= 4)) || JOBS=4; fi
mkdir -p -- "$WORK_PARENT"
WORK_PARENT=$(realpath -- "$WORK_PARENT")
exec 9>"$WORK_PARENT/installer.lock"
flock -n 9 || die "Another installer is using $WORK_PARENT"
RUN=$(mktemp -d "$WORK_PARENT/run-XXXXXXXX")
mkdir -p "$RUN"/{logs,sources,build,stage,backup}
exec > >(tee -a "$RUN/installer.log") 2>&1
trap 'printf "Installer failed at line %s. Logs: %s\n" "$LINENO" "$RUN" >&2' ERR
printf 'Build directory: %s\n' "$RUN"
sudo -v
DNF=(sudo dnf --disable-repo='*' --enable-repo=fedora --enable-repo=updates --refresh -y)

# Name-based install and distro-sync ensure OBS is selected from official repos,
# even when a newer third-party build is already installed (conflicts fail closed).

"${DNF[@]}" install obs-studio obs-studio-devel \
 gcc gcc-c++ cmake ninja-build make git curl jq python3 pkgconf-pkg-config \
 binutils patch tar gzip xz unzip findutils coreutils util-linux \
 qt6-qtbase-devel qt6-qtbase-private-devel qt6-qtsvg-devel \
 extra-cmake-modules jansson-devel libcurl-devel zlib-ng-compat-devel \
 vulkan-loader-devel vulkan-headers libglvnd-devel libX11-devel libxcb-devel \
 wayland-devel wayland-protocols-devel patchelf policycoreutils
"${DNF[@]}" distro-sync obs-studio obs-studio-libs obs-studio-devel
rpm -q obs-studio obs-studio-libs obs-studio-devel > "$RUN/obs-packages.txt"
cat "$RUN/obs-packages.txt"

# Fedora splits module binaries into obs-studio-libs; query both packages.

mapfile -t MODULE_DIRS < <(rpm -ql obs-studio obs-studio-libs |
 sed -n 's@^\(/usr/lib[^/]*/obs-plugins\)/[^/]*\.so$@\1@p' | sort -u)
((${#MODULE_DIRS[@]} == 1)) || die 'Could not determine a unique OBS plugin directory from installed RPMs.'
PLUGIN_DIR=${MODULE_DIRS[0]}
LIBDIR=${PLUGIN_DIR%/obs-plugins}
DATA_DIR=/usr/share/obs/obs-plugins
[[ $LIBDIR == /usr/lib64 ]] || die "Unexpected library directory: $LIBDIR"
[[ -d $DATA_DIR ]] || die "Missing OBS data directory: $DATA_DIR"
printf 'Module directory: %s\nData directory: %s\n' "$PLUGIN_DIR" "$DATA_DIR"
printf 'plugin\trepository\ttag\tcommit\n' > "$RUN/sources.tsv"

build_one() (
 set -Eeuo pipefail
 local repo=$1 name=${1##*/} tag sha src build stage response module
 local -a extra=() install_args=()
 trap 'printf "Build failed: %s (line %s)\n" "$name" "$LINENO" >&2' ERR
 src="$RUN/sources/$name"; build="$RUN/build/$name"; stage="$RUN/stage/$name"
 module=$name
 case $name in
  obs-vkcapture) module=linux-vkcapture ;;
  obs-draw) module=draw-dock ;;
  obs-source-clone|obs-transition-table|obs-source-record|obs-source-dock|obs-source-copy|obs-3d-effect|obs-recursion-effect|obs-move-transition|obs-gradient-source|obs-freeze-filter|obs-downstream-keyer|obs-aitum-multistream)
   module=${name#obs-} ;;
 esac
 response="$RUN/logs/$name-release.json"
 # Fail on API errors/rate limits; never silently substitute an unstable branch.
 curl --fail --silent --show-error --location --retry 3 \
  "https://api.github.com/repos/$repo/releases/latest" -o "$response"
 tag=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name | select(type == "string" and length > 0)' "$response")
 git check-ref-format "refs/tags/$tag"
 git init -q "$src"
 git -C "$src" remote add origin "https://github.com/$repo.git"
 git -C "$src" fetch --depth 1 origin "refs/tags/$tag"
 git -C "$src" checkout --detach FETCH_HEAD
 git -C "$src" submodule update --init --recursive --depth 1
 sha=$(git -C "$src" rev-parse HEAD)
 printf '%s\t%s\t%s\t%s\n' "$name" "$repo" "$tag" "$sha" >> "$RUN/sources.tsv"
 printf '\nBuilding %s at %s (%s)\n' "$name" "$tag" "$sha"

 # Small build-system compatibility adjustments, retained in the source diff.
 # Older helper files hard-code -Werror independently of CMake's switch.

 python3 - "$src" <<'PY'
import pathlib,re,sys
src=pathlib.Path(sys.argv[1])
p=src/'cmake/ObsPluginHelpers.cmake'
if p.exists():
    p.write_text(re.sub(r'(?m)^(\s*)-Werror\s*$',r'\1-Wno-error',p.read_text()))
p=src/'CMakeLists.txt'
s=p.read_text().replace('Qt_VERSION VERSION_LESS','Qt6_VERSION VERSION_LESS')
p.write_text(s)
PY
 if [[ $name == obs-recursion-effect ]] && [[ ! -f /usr/include/obs/util/circlebuf.h ]]; then

 # OBS 32 removed this header. It implements an inline container, not a
 # libobs ABI. Vendor the final OBS 31 header privately, with its license.

 mkdir -p "$src/compat/util"
  curl --fail --silent --show-error --location --retry 3 \
   https://raw.githubusercontent.com/obsproject/obs-studio/31.1.2/libobs/util/circlebuf.h \
   -o "$src/compat/util/circlebuf.h"
  printf '%s  %s\n' b1fe1d83a8d8ecb4afbfba53cce69d24ca3b5f4abdb2955369a27139e10af1e0 \
   "$src/compat/util/circlebuf.h" | sha256sum -c -
  sed -i 's/"c99defs.h"/<util\/c99defs.h>/; s/"bmem.h"/<util\/bmem.h>/' "$src/compat/util/circlebuf.h"
  # shellcheck disable=SC2016 # This variable is expanded by CMake, not Bash.
  printf '\ntarget_include_directories(recursion-effect PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/compat")\n' >> "$src/CMakeLists.txt"
 fi
 git -C "$src" diff > "$RUN/logs/$name-build-adjustments.patch"
 if [[ $name == obs-advanced-masks || $name == shadertastic ]]; then
  extra+=(-DENABLE_QT=ON -DENABLE_FRONTEND_API=ON)
 fi

 # Both modern GNUInstallDirs and older OBS helper variables are supplied.
 # Do not use Ubuntu CI presets: they can fetch a different OBS/Qt SDK.

 cmake -S "$src" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR="${LIBDIR#/usr/}" -DCMAKE_INSTALL_DATAROOTDIR=share \
  -DLIB_OUT_DIR="${PLUGIN_DIR#/usr/}" -DDATA_OUT_DIR="${DATA_DIR#/usr/}/$module" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_OUT_OF_TREE=ON \
  -DCMAKE_C_STANDARD=17 -DLINUX_PORTABLE=OFF \
  -Dlibobs_DIR="$LIBDIR/cmake/libobs" \
  -Dobs-frontend-api_DIR="$LIBDIR/cmake/obs-frontend-api" \
  -DQT_VERSION=6 "${extra[@]}"
 cmake --build "$build" --parallel "$JOBS"
 mkdir -p "$stage"

 # Newer FiniteSingularity releases provide both OBS 32 Legacy and OBS 33
 # Modern layouts. Use only the component matching Fedora's verified directory.

 if [[ -f $src/cmake/linux/helpers.cmake ]] &&
    grep -q 'COMPONENT Legacy' "$src/cmake/linux/helpers.cmake"; then
  install_args+=(--component Legacy)
 fi
 DESTDIR="$stage" cmake --install "$build" "${install_args[@]}"
 # Validate the full staging tree, not merely CMake's exit status.
 python3 - "$stage" "$name" "$PLUGIN_DIR" "$DATA_DIR" "$LIBDIR" "$module" <<'PY'
import pathlib,sys,os,subprocess
stage=pathlib.Path(sys.argv[1]); name,plug,data,lib,module=sys.argv[2:]
allowed=[plug+'/'+module+'.so',data+'/'+module+'/']
if name=='shadertastic': allowed += [plug+'/shadertastic/']
if name=='obs-vkcapture':
    allowed += [lib+'/libVkLayer_obs_vkcapture.so',lib+'/obs_glcapture/',
                '/usr/share/vulkan/implicit_layer.d/obs_vkcapture_64.json',
                '/usr/bin/obs-gamecapture','/usr/bin/obs-vkcapture','/usr/bin/obs-glcapture']
files=[]
for p in stage.rglob('*'):
    if p.is_dir() and not p.is_symlink(): continue
    dest='/'+str(p.relative_to(stage))
    if not any(dest.startswith(a) if a.endswith('/') else dest==a for a in allowed):
        raise SystemExit('Unexpected install destination: '+dest)
    if p.is_symlink():
        try:p.resolve().relative_to(stage.resolve())
        except ValueError:raise SystemExit('Symlink escapes staging tree: '+str(p))
    elif not p.is_file():raise SystemExit('Unexpected special file: '+str(p))
    files.append(dest)
so=stage/(plug+'/'+module+'.so').lstrip('/')
if not so.is_file():raise SystemExit('Missing OBS module: '+str(so))
symbols=subprocess.check_output(['readelf','--dyn-syms','--wide',str(so)],text=True)
for symbol in ['obs_module_load','obs_module_ver']:
    if not any(symbol==l.split()[-1] and ' UND ' not in l for l in symbols.splitlines() if l.split()):
        raise SystemExit('Missing exported OBS entry point: '+symbol)
if not (stage/(data+'/'+module).lstrip('/')).is_dir():
    raise SystemExit('Missing plugin data directory')
(stage.parent/(name+'.files')).write_text(''.join(f.lstrip('/')+'\n' for f in sorted(files)))
print('Validated',len(files),'staged files for',name)
PY
)
failed=()
for repo in "${REPOS[@]}"; do
 name=${repo##*/}

 # Do not invoke the build function in an if/! condition: that disables errexit
 # inside Bash functions. This subshell explicitly enables errexit instead.

 set +e
 build_one "$repo" 2>&1 | tee "$RUN/logs/$name.log"
 result=${PIPESTATUS[0]}
 set -e
 if ((result != 0)); then failed+=("$name"); fi
done
if ((${#failed[@]})); then
 printf '\nFailed plugins: %s\n' "${failed[*]}"
 die "No plugins deployed. Inspect $RUN/logs. OBS/dependency RPMs were installed."
fi
if ((BUILD_ONLY)); then
 printf '\nAll selected plugins built and staged. No plugins deployed. Files: %s\n' "$RUN"
 exit 0
fi
pgrep -x obs >/dev/null && die 'OBS was started during the build. Close it and rerun.'

# Validate existing destination paths, reject package-owned collisions, and back
# up every file this run replaces. Manifests also identify newly installed files.

: > "$RUN/replaced-files.txt"
: > "$RUN/new-files.txt"
for repo in "${REPOS[@]}"; do
 name=${repo##*/}
 while IFS= read -r rel; do
  dest="/$rel"
  parent=$(dirname "$dest")
  while [[ $parent != / ]]; do
   [[ ! -L $parent ]] || die "Destination parent is a symlink: $parent"
   [[ ! -e $parent || -d $parent ]] || die "Destination parent is not a directory: $parent"
   parent=$(dirname "$parent")
  done
  [[ ! -L $dest && ! -d $dest ]] || die "Destination is a symlink/directory: $dest"
  if rpm -qf "$dest" >/dev/null 2>&1; then
   die "An RPM owns $dest; remove the conflicting plugin RPM before retrying."
  fi
  if [[ -e $dest ]]; then
   printf '%s\n' "$rel" >> "$RUN/replaced-files.txt"
  else
   printf '%s\n' "$rel" >> "$RUN/new-files.txt"
  fi
 done < "$RUN/stage/$name.files"
done
sudo tar -C / --verbatim-files-from -cpf "$RUN/backup/replaced-files.tar" -T "$RUN/replaced-files.txt"
for repo in "${REPOS[@]}"; do
 name=${repo##*/}

 # Archive files only; do not reset ownership/modes of existing /usr directories.

 tar -C "$RUN/stage/$name" --verbatim-files-from --no-recursion \
  -cpf "$RUN/$name.tar" -T "$RUN/stage/$name.files"
 sudo tar -C / --no-same-owner --no-same-permissions -xf "$RUN/$name.tar"
done
sudo ldconfig
sudo restorecon -RF "$PLUGIN_DIR" "$DATA_DIR"
if [[ -f /usr/share/vulkan/implicit_layer.d/obs_vkcapture_64.json ]]; then
 sudo restorecon -RF /usr/share/vulkan/implicit_layer.d "$LIBDIR/obs_glcapture"
 sudo restorecon "$LIBDIR/libVkLayer_obs_vkcapture.so" /usr/bin/obs-gamecapture /usr/bin/obs-vkcapture /usr/bin/obs-glcapture
fi
printf '\nInstalled all %s selected plugins. Restart native OBS (/usr/bin/obs).\n' "${#REPOS[@]}"
printf 'Sources, logs, file manifests and backup: %s\n' "$RUN"
printf 'Use obs-gamecapture %%command%% in Steam launch options for 64-bit game capture.\n'
printf 'Builds passed; confirm runtime loading in OBS: Help > Log Files > View Current Log.\n'
