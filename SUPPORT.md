# SketchGlide help

[Download 0.2 Test](https://github.com/12kareem2323-png/karim-ink/releases/tag/v0.2.0-test) · [Report a problem](https://github.com/12kareem2323-png/karim-ink/issues/new/choose)

## Mac first launch

Use the official DMG/ZIP, compare SHA-256 with the release checksum file, and copy SketchGlide.app into Applications. This early Test is ad hoc signed and unnotarized. macOS can block first launch. If you trust that verified download, follow Apple's per-app **System Settings → Privacy & Security → Open Anyway** instructions. Keep system security protections enabled. The download is Apple Silicon only; older target macOS versions have not been runtime-tested.

Apple help: https://support.apple.com/en-gb/102445

## Windows first launch

Download the x64 Test ZIP and choose **Extract All** before opening SketchGlide.exe. Keep the DLLs and Resources beside it. The .NET runtime is included. Windows can show an unknown-publisher/SmartScreen warning because this Test is unsigned. Verify the official download and keep Windows security enabled. If native OCR reports a missing runtime, use Microsoft's official x64 Visual C++ runtime: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist

The release targets Windows 11 Intel/AMD x64. QA used x64 emulation in a Windows ARM virtual machine; real Intel/AMD and physical-tablet checks are still needed. Optional Install.cmd installs for your Windows user; no automatic driver/runtime installation occurs.

## Drawings, AI and feedback

Back up editable `.engboard` and `.karim3d` files. Review OCR/AI, especially decimal points, units and symbols. Ordinary drawing/saving is offline. Optional cloud AI needs your own API key and separate API billing. Full handwriting-to-LaTeX, full CAD simulation, live native Notion embedding and universal tablet support are not promised.

For bugs, provide version, OS/processor, tablet/driver if relevant, steps and a made-up sample. Do not post private notes, credentials or account screenshots. [Privacy](PRIVACY.md) describes local files and optional routes.

[Optional PayPal support](https://paypal.me/KEldamaty) goes directly to Karim Eldamaty's public PayPal page. Donations do not unlock features or buy guaranteed support. You can also download the Test through [itch.io](https://12kareem2323-png.itch.io/karim-ink).
