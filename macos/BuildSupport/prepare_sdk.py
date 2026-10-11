"""Prepare a local Clang VFS overlay for an observed Apple SDK packaging fault.

Usage: python3 BuildSupport/prepare_sdk.py SDK_PATH OVERLAY_DIRECTORY

No installed SDK is changed. The Command Line Tools SDK on this Mac omits
HIToolbox/TextInputSources.h, although its umbrella includes that header. This
app does not use that Carbon API. The overlay guards only this missing include
in a copy of the original umbrella; all other declarations remain intact.
A complete SDK produces an empty overlay and needs no workaround.
"""
from pathlib import Path
import json
import sys

sdk = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
header = sdk / "System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/Headers/HIToolbox.h"
output.mkdir(parents=True, exist_ok=True)
roots = []
if header.exists() and not (header.parent / "TextInputSources.h").exists():
    original = header.read_bytes()
    needle = b"#include <HIToolbox/TextInputSources.h>"
    if original.count(needle) != 1:
        raise SystemExit("Unexpected HIToolbox umbrella: no overlay created.")
    patched = output / "HIToolbox.h"
    patched.write_bytes(original.replace(needle, b"#if __has_include(<HIToolbox/TextInputSources.h>)\n" + needle + b"\n#endif"))
    for name in sorted({str(header), str(header.resolve())}):
        roots.append({"type": "file", "name": name, "external-contents": str(patched)})

overlay = output / "sdk-overlay.json"
overlay.write_text(json.dumps({"version": 0, "case-sensitive": True, "roots": roots}, indent=2) + "\n")
print(overlay)
