"""Make and verify the portable Velin Windows x64 ZIP from a clean publish directory."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import struct
import xml.etree.ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("payload", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--tag")
    args = parser.parse_args()
    windows = Path(__file__).resolve().parents[1]
    version = ET.parse(windows / "KarimEldamatyWindows.csproj").findtext("./PropertyGroup/Version")
    version_pattern = r"(?:0|[1-9][0-9]{0,8})(?:\.(?:0|[1-9][0-9]{0,8})){2}(?:-test\.[1-9][0-9]{0,8})?"
    if version is None or re.fullmatch(version_pattern, version) is None:
        parser.error("Set a Velin version such as 1.0.0-test.2 in the project file.")
    if args.tag is not None and args.tag != f"velin-windows-v{version}":
        parser.error(f"The release tag must be velin-windows-v{version}.")

    payload, output = args.payload.resolve(), args.output.resolve()
    if output == payload or output.is_relative_to(payload):
        parser.error("Use a release folder outside the published app.")
    required = (
        "Velin.exe", "Velin.dll", "Velin.runtimeconfig.json", "Velin.deps.json",
        "coreclr.dll", "hostfxr.dll", "wpfgfx_cor3.dll", "onnxruntime.dll",
        "PdfSharp.dll", "UglyToad.PdfPig.dll", "x64/tesseract50.dll",
        "Resources/SymbolCatalog.json", "Resources/MathSymbols/deTeX.onnx", "Resources/OCR/eng.traineddata",
    )
    for name in required:
        path = payload / name
        if not path.is_file() or path.stat().st_size == 0:
            parser.error(f"Missing published file {name}.")
    for name in ("Velin.exe", "coreclr.dll", "wpfgfx_cor3.dll", "onnxruntime.dll", "x64/tesseract50.dll"):
        with (payload / name).open("rb") as binary:
            if binary.read(2) != b"MZ":
                parser.error(f"Invalid Windows binary {name}.")
            binary.seek(0x3C)
            binary.seek(struct.unpack("<I", binary.read(4))[0])
            if binary.read(6) != b"PE\x00\x00\x64\x86":
                parser.error(f"Expected an x64 binary for {name}.")

    name = f"Velin-{version}-Windows-x64"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{name}.zip"
    temporary = archive.with_suffix(".zip.tmp")
    inputs = {path.relative_to(payload).as_posix(): path for path in payload.rglob("*") if path.is_file()}
    for entry in ("README.md", "LICENSE", "THIRD-PARTY-NOTICES.md"):
        inputs[entry] = windows / entry
    for path in (windows / "Resources" / "Licenses").glob("*.txt"):
        inputs[f"Resources/Licenses/{path.name}"] = path
    try:
        with ZipFile(temporary, mode="w", compression=ZIP_DEFLATED) as zipped:
            for entry, source in sorted(inputs.items()):
                record = ZipInfo(f"{name}/{entry}", date_time=(2026, 1, 1, 0, 0, 0))
                record.compress_type = ZIP_DEFLATED
                with source.open("rb") as original, zipped.open(record, mode="w") as target:
                    shutil.copyfileobj(original, target)
        with ZipFile(temporary) as zipped:
            failure = zipped.testzip()
            if failure:
                raise IOError(f"ZIP integrity check failed at {failure}.")
            if len(zipped.namelist()) != len(inputs):
                raise IOError("ZIP entry count differs from the input manifest.")
        temporary.replace(archive)
    finally:
        temporary.unlink(missing_ok=True)

    with archive.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n", encoding="ascii")
    print(f"{archive} ({archive.stat().st_size:,} bytes)")
    print(f"SHA-256 {digest}")


if __name__ == "__main__":
    main()
