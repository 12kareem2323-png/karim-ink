# Karim Ink support and feedback

[Download the Mac preview](https://github.com/12kareem2323-png/karim-ink/releases/tag/v0.1.0) · [Open an issue](https://github.com/12kareem2323-png/karim-ink/issues)

Windows is coming soon. This release targets Apple Silicon Macs running macOS 14 or later and has been tested on Apple Silicon with macOS 27.2. It is an ad hoc signed, unnotarized preview distributed outside the Mac App Store. Local language-model chat additionally needs macOS 26 or later and a ready Apple Intelligence model.

## First launch on a Mac

Download the ZIP or DMG from the official release page and move **Karim Ink.app** into **Applications**. The published SHA-256 checksums identify the release files; they do not replace Apple signing or notarization.

If macOS blocks the first launch because the developer cannot be verified, first check that you trust the source and that the file matches the release. After attempting to open Karim Ink, open **System Settings → Privacy & Security**. Where available, choose **Open Anyway** for Karim Ink and confirm **Open**. This creates an exception for that app. Apple's [Safely open apps on your Mac](https://support.apple.com/en-us/102445) describes the conditions and warnings.

Do not disable Gatekeeper, remove quarantine flags or follow a workaround for an alert that says the app contains malware or is damaged. Stop and report the exact message instead. A managed school/work Mac may not allow an exception.

## Report a problem

Include:

- Karim Ink version, macOS version and Mac model.
- What you expected, what happened and the shortest steps that reproduce it.
- For pen problems: tablet brand/model, pen model, driver version and whether mouse drawing works.
- A screenshot or small synthetic example when it helps. Remove private information first.

Never post API keys, Craft connection links/tokens, private coursework or sensitive files. Security reports should follow [SECURITY.md](SECURITY.md).

## Common questions

**The download will not open.** This preview is unnotarized. Follow the first-launch section above for an unidentified-developer warning; for other warnings, report the exact macOS message. Keep Gatekeeper and other macOS security protections enabled.

**Pressure or tilt is missing.** Check the tablet's current macOS driver, its application profile and macOS permissions. Open the app's tablet/pressure test. Karim Ink uses standard AppKit pen events; a driver must provide pressure, tilt or eraser data for the app to use it. Vendor-specific buttons and remotes are not interchangeable across brands.

**AI does not answer.** Local chat needs a ready Apple model. Cloud chat needs internet, your own working OpenAI API key and API credit; a ChatGPT subscription alone is not enough. Check the displayed route and error in Assistant settings.

**Craft or Notion does not behave like the Mac app.** Craft updating handles supported basic objects in one direction. Notion uses an exported HTML companion. Neither embeds the native drawing engine or supplies multiplayer/two-way editing.

**Recognition is wrong.** DeTeXt recognizes one symbol at a time. OCR and spelling can misread technical notes. Review suggestions, numbers and units before changing the drawing.

## Support development

Verified payment links will be added after setup. Donations will be voluntary and will not buy extra features or a guaranteed support response.

Feedback, small reproducible examples and documentation improvements also help.
