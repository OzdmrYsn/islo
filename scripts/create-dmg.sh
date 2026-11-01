#!/bin/zsh
set -euo pipefail

# Builds islo.'s disk image: the app and an Applications shortcut in a
# styled window (background, icon positions, volume icon). The layout is
# written straight into the image by dmgbuild, so Finder is never scripted.

if (( $# < 2 || $# > 3 )); then
    echo "Usage: $0 /path/to/islo.app /path/to/islo.dmg [version]" >&2
    exit 64
fi

app_path="${1:A}"
dmg_path="${2:A}"
version="${3:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")}"
script_dir="${0:A:h}"
project_root="${script_dir:h}"
assets="$script_dir/dmg"
venv="$project_root/.build/dmgbuild-venv"

if [[ ! -d "$app_path" ]]; then
    echo "Application not found: $app_path" >&2
    exit 66
fi

if [[ ! -x "$venv/bin/dmgbuild" ]]; then
    echo "Setting up dmgbuild in $venv"
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet "dmgbuild==1.6.5"
fi

/bin/mkdir -p "${dmg_path:h}"
if [[ -e "$dmg_path" ]]; then
    /bin/mv "$dmg_path" "$dmg_path.previous"
fi

"$venv/bin/dmgbuild" \
    -s "$assets/settings.py" \
    -D app="$app_path" \
    -D background="$assets/background.tiff" \
    -D volume_icon="$assets/VolumeIcon.icns" \
    "islo. $version" \
    "$dmg_path" 2>&1 | grep -v "is deprecated" || true

[[ -s "$dmg_path" ]] || { echo "DMG wasn't created" >&2; exit 1; }
/usr/bin/hdiutil verify "$dmg_path"
echo "DMG ready: $dmg_path"
