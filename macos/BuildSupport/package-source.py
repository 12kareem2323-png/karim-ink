"""Archive only checked-in source/resources; never include builds or private drawings."""
from pathlib import Path
import argparse
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
allowed_files = {"Package.swift", "Info.plist", "build.sh", "AppIcon.icns", "README.md", "CONTRIBUTING.md", "VERIFICATION.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "ICON_PROVENANCE.md", ".gitignore"}
allowed_dirs = {"Sources", "Tests", "Resources", "third-party-licenses", "BuildSupport", "EngineeringBoard.xcodeproj"}
excluded = {"__pycache__", "xcuserdata", ".DS_Store"}
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if not path.is_file() or path.is_symlink() or any(part in excluded for part in relative.parts):
            continue
        if relative.parts[0] not in allowed_dirs and relative.as_posix() not in allowed_files:
            continue
        if path.suffix in {".pyc", ".xcuserstate", ".engboard", ".karim3d"}:
            continue
        archive.write(path, "SketchGlide-0.2.0-macOS-source/" + relative.as_posix())
print(args.output)
