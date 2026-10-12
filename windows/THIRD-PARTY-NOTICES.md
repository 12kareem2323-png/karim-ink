# Bundled components

SketchGlide is made by Karim Eldamaty. Original source code, artwork and symbol catalogue are available under this project’s MIT licence. The Windows package also contains these dependencies and retains their licence notices:

- Microsoft .NET / WPF 10.0.12: MIT licence and third-party notices in `Resources/Licenses`. [Microsoft source](https://github.com/dotnet/wpf).
- ONNX Runtime 1.23.2: MIT licence in `Resources/Licenses/LICENSE-ONNXRuntime.txt`. [Microsoft source](https://github.com/microsoft/onnxruntime).
- DeTeXt published model and supplementary metadata: MIT notices and pinned provenance in `Resources/MathSymbols`. The original trained weights were converted to ONNX; the training database is not bundled. Detexify training data has its own ODbL terms. [Model source](https://github.com/venkatasg/DeTeXt).
- Tesseract .NET wrapper 5.2.0, native Tesseract OCR 5 and English LSTM language data: Apache 2.0. Notices and data provenance are in `Resources/OCR`. [Wrapper source](https://github.com/charlesw/tesseract), [Tesseract source](https://github.com/tesseract-ocr/tesseract), [language data source](https://github.com/tesseract-ocr/tessdata_fast).
- Leptonica native image library: BSD-style notice in `Resources/Licenses/LICENSE-Leptonica.txt`. [Leptonica source](https://github.com/DanBloomberg/leptonica).
- Microsoft Visual C++ x64 runtime is an optional external prerequisite for native OCR/inference. Its installer is not bundled. Download directly from [Microsoft](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist) if Windows reports a missing native dependency.

The OpenAI assistant uses the [Responses API](https://developers.openai.com/api/docs/guides/migrate-to-responses) and an editable [GPT-4.1](https://developers.openai.com/api/docs/models/gpt-4.1) default. It is an API client and requires the user's API access; a ChatGPT subscription is separate. No OpenAI key or user drawing is bundled. Optional local Ollama is installed separately by the user.

The package has not been signed with a commercial publisher certificate. Native Windows runtime, interface and physical tablet tests are separate from the Mac-side build and logic checks.
