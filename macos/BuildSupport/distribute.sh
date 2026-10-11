#!/bin/bash
# Requires an existing Developer ID certificate and an authenticated notarytool profile.
# No passwords or signing keys are stored in this source or included in releases.
set -euo pipefail
if [ "$#" -ne 4 ]; then
  printf 'Usage: distribute.sh APP_PATH OUTPUT_DIRECTORY SIGNING_IDENTITY NOTARY_PROFILE\n' >&2
  exit 2
fi
karim_app="$1"
karim_output="$2"
karim_identity="$3"
karim_notary_profile="$4"
case "$karim_identity" in 'Developer ID Application:'*) ;; *) printf 'Use your Developer ID Application identity.\n' >&2; exit 2 ;; esac
[ -f "$karim_app/Contents/MacOS/EngineeringBoard" ] || { printf 'Missing app binary.\n' >&2; exit 2; }
mkdir -p "$karim_output"
# No nested executable libraries are bundled; sign this single app without --deep.
codesign --force --sign "$karim_identity" --options runtime --timestamp "$karim_app"
codesign --verify --strict --verbose=2 "$karim_app"
ditto -c -k --keepParent --sequesterRsrc "$karim_app" "$karim_output/SketchGlide-notary-submission.zip"
xcrun notarytool submit "$karim_output/SketchGlide-notary-submission.zip" --keychain-profile "$karim_notary_profile" --wait --output-format json > "$karim_output/notarization.json"
python3 - "$karim_output/notarization.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted': raise SystemExit('Apple has not accepted this build. Do not publish it.')
PY
xcrun stapler staple "$karim_app"
xcrun stapler validate "$karim_app"
spctl --assess --type execute --verbose=2 "$karim_app"
ditto -c -k --keepParent --sequesterRsrc "$karim_app" "$karim_output/SketchGlide-0.2.0-Test-macOS-arm64.zip"
karim_dmg_source="$(mktemp -d "$karim_output/dmg.XXXXXX")"
trap 'rm -rf "$karim_dmg_source"' EXIT
ditto "$karim_app" "$karim_dmg_source/SketchGlide.app"
ln -s /Applications "$karim_dmg_source/Applications"
hdiutil create -volname 'SketchGlide 0.2 Test' -srcfolder "$karim_dmg_source" -ov -format UDZO "$karim_output/SketchGlide-0.2.0-Test-macOS-arm64.dmg"
codesign --force --sign "$karim_identity" --timestamp "$karim_output/SketchGlide-0.2.0-Test-macOS-arm64.dmg"
xcrun notarytool submit "$karim_output/SketchGlide-0.2.0-Test-macOS-arm64.dmg" --keychain-profile "$karim_notary_profile" --wait --output-format json > "$karim_output/dmg-notarization.json"
python3 - "$karim_output/dmg-notarization.json" <<'PY'
import json,sys
if json.load(open(sys.argv[1])).get('status') != 'Accepted': raise SystemExit('Apple has not accepted this disk image. Do not publish it.')
PY
xcrun stapler staple "$karim_output/SketchGlide-0.2.0-Test-macOS-arm64.dmg"
xcrun stapler validate "$karim_output/SketchGlide-0.2.0-Test-macOS-arm64.dmg"
(cd "$karim_output" && shasum -a 256 SketchGlide-0.2.0-Test-macOS-arm64.zip SketchGlide-0.2.0-Test-macOS-arm64.dmg > SHA256SUMS.txt)
printf 'Verified signed and notarized release ready in %s\n' "$karim_output"
