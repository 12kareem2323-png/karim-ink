# Local OCR assets

The portable Windows x64 app uses Tesseract.NET 5.2.0 and bundled English LSTM OCR data. It does not call a cloud OCR service. Windows.Media.Ocr is used only if this process has package identity; Microsoft documents that requirement at https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.

English data downloaded from https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/eng.traineddata on 8 October 2026.
SHA-256: 7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2
Size: 4,113,088 bytes.
Upstream repository: https://github.com/tesseract-ocr/tessdata_fast.
Apache License 2.0 retained in LICENSE-tessdata-fast.txt.

.NET wrapper source: https://github.com/charlesw/tesseract.
Apache License 2.0 retained in LICENSE-Tesseract.NET.txt.
The wrapper's native binaries require the Microsoft Visual C++ 2015–2022 x64 runtime (Visual Studio 2019-compatible). Native/runtime behavior still needs checking on Windows. The OCR transcription always requires review, particularly handwriting, numbers, decimal points and engineering units.
