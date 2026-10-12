#!/bin/bash
# Packages a free preview. This is deliberately NOT Developer ID signing/notarization.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  printf 'Usage: package-preview.sh APP_PATH OUTPUT_DIRECTORY\n' >&2; exit 2
fi
karim_app="$1"
karim_output="$2"
[ -f "$karim_app/Contents/MacOS/EngineeringBoard" ] || { printf 'Missing app binary.\n' >&2; exit 2; }
mkdir -p "$karim_output"
karim_output="$(cd "$karim_output" && pwd)"
codesign --verify --strict "$karim_app"
karim_stage="$(mktemp -d "$karim_output/preview.XXXXXX")"
trap 'rm -rf "$karim_stage"' EXIT
ditto "$karim_app" "$karim_stage/SketchGlide.app"
cat > "$karim_stage/READ ME FIRST.txt" <<'README'
SketchGlide 0.2 Test — made by Karim Eldamaty
Apple Silicon Macs; macOS 14 or later target. Windows Test builds are separate; check the release for current availability.

This free preview has an ad hoc signature, not an Apple Developer ID signature.
It is NOT Apple-notarized. macOS can warn or block the first launch.

Only download from the official project and check its listed SHA-256 checksum:
https://github.com/12kareem2323-png/karim-ink/releases/tag/v0.2.0-test

Move SketchGlide.app to Applications. Try opening it once. If macOS blocks it
and you trust this preview, use System Settings > Privacy & Security >
Open Anyway, then confirm Open. If macOS reports harmful software, stop
and report the exact message. Keep macOS security protections enabled.
Apple instructions: https://support.apple.com/en-us/102445

Drawing, local saving and single-symbol recognition work offline.
Optional cloud AI requires your own OpenAI API key and separate API billing.
Back up important editable drawings; this is an early preview.

Feedback: Settings > Feedback & support, or
https://github.com/12kareem2323-png/karim-ink/issues
Optional support: https://paypal.me/KEldamaty
Editable source and contribution instructions: https://github.com/12kareem2323-png/karim-ink/tree/main/macos
Privacy and limits: https://github.com/12kareem2323-png/karim-ink
README
# A ZIP containing only the app and installation notes, not the staging folder.
(cd "$karim_stage" && COPYFILE_DISABLE=1 zip -q -r "$karim_output/SketchGlide-0.2.0-macOS-arm64-Test-unnotarized.next.zip" 'SketchGlide.app' 'READ ME FIRST.txt')
mv "$karim_output/SketchGlide-0.2.0-macOS-arm64-Test-unnotarized.next.zip" "$karim_output/SketchGlide-0.2.0-macOS-arm64-Test-unnotarized.zip"
ln -s /Applications "$karim_stage/Applications"
hdiutil create -volname 'SketchGlide 0.2 Test' -srcfolder "$karim_stage" -format UDZO -ov "$karim_output/SketchGlide-0.2.0-macOS-arm64-Test-unnotarized.dmg"
cp "$karim_stage/READ ME FIRST.txt" "$karim_output/READ-ME-FIRST.txt"
(cd "$karim_output" && shasum -a 256 SketchGlide-0.2.0-macOS-arm64-Test-unnotarized.zip SketchGlide-0.2.0-macOS-arm64-Test-unnotarized.dmg > SHA256SUMS.txt)
printf 'Unnotarized preview packaged. Verify extracted and mounted apps before upload.\n'
