#!/bin/bash
# Build a local Mac app. This is not distribution signing or notarization.
set -euo pipefail
karim_source="$(cd "$(dirname "$0")" && pwd)"
# KARIM_SDK may select an installed SDK explicitly. A compatible installed 26.5
# SDK is used when the host's default SDK and Swift compiler are out of step.
karim_sdk="${KARIM_SDK:-$(xcrun --show-sdk-path)}"
if [ -z "${KARIM_SDK:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
  karim_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
karim_build="${KARIM_BUILD_DIR:-$karim_source/.build}"
karim_app="${KARIM_APP_PATH:-$karim_source/dist/SketchGlide.app}"
karim_arch="${KARIM_ARCH:-arm64}"
case "$karim_arch" in arm64|x86_64) ;; *) printf 'Unsupported architecture.\n' >&2; exit 1 ;; esac
cd "$karim_source"
karim_overlay="$(python3 "$karim_source/BuildSupport/prepare_sdk.py" "$karim_sdk" "$karim_build/sdk-overlay")"
swift build --jobs 2 --configuration release --build-system native --arch "$karim_arch" --sdk "$karim_sdk" --scratch-path "$karim_build" -Xswiftc -vfsoverlay -Xswiftc "$karim_overlay" -Xcc -ivfsoverlay -Xcc "$karim_overlay"
karim_binary="$(swift build --jobs 2 --configuration release --build-system native --arch "$karim_arch" --sdk "$karim_sdk" --scratch-path "$karim_build" --show-bin-path)/EngineeringBoard"
python3 - "$karim_app" <<'PYGUARD'
import subprocess, sys
from pathlib import Path
app = Path(sys.argv[1]).resolve()
exe = str(app / 'Contents/MacOS/EngineeringBoard')
commands = subprocess.run(['/bin/ps', '-axo', 'command'], capture_output=True, text=True, check=True).stdout.splitlines()
if any(command == exe or command.startswith(exe + ' ') for command in commands):
    raise SystemExit('The destination app is running. Choose a new KARIM_APP_PATH.')
PYGUARD
mkdir -p "$karim_app/Contents/MacOS" "$karim_app/Contents/Resources"
cp "$karim_binary" "$karim_app/Contents/MacOS/EngineeringBoard"
cp "$karim_source/LICENSE" "$karim_app/Contents/Resources/LICENSE.txt"
cp "$karim_source/Info.plist" "$karim_app/Contents/Info.plist"
cp "$karim_source/AppIcon.icns" "$karim_app/Contents/Resources/AppIcon.icns"
for karim_resource in MathSymbols QuickKeys; do
  rm -rf "$karim_app/Contents/Resources/$karim_resource"
  cp -R "$karim_source/Resources/$karim_resource" "$karim_app/Contents/Resources/"
done
if [ -d "$karim_source/third-party-licenses" ]; then cp -R "$karim_source/third-party-licenses" "$karim_app/Contents/Resources/"; fi
if [ -f "$karim_source/THIRD_PARTY_NOTICES.md" ]; then cp "$karim_source/THIRD_PARTY_NOTICES.md" "$karim_app/Contents/Resources/"; fi
codesign --force --sign - "$karim_app"
codesign --verify --strict "$karim_app"
printf 'Local build ready: %s\nNot notarized. BuildSupport/package-preview.sh packages a clearly labelled free preview; distribute.sh handles a future notarized release.\n' "$karim_app"
