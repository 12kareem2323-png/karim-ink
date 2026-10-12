# SketchGlide publishing checklist

Made by Karim Eldamaty. Checked 12 October 2026. The app remains **0.2 Test**.

## Public now

- [GitHub Releases](https://github.com/12kareem2323-png/karim-ink/releases/tag/v0.2.0-test): Mac and Windows downloads, checksums, source and creator kit.
- [itch.io](https://12kareem2323-png.itch.io/karim-ink): Mac and Windows software downloads.
- [Website](https://karim-ink.stonyvale1.chatgpt.site/), with a [GitHub Pages mirror](https://12kareem2323-png.github.io/karim-ink/): remote hosting works when Karim's Mac is off.
- [Custom Scoop bucket](https://github.com/12kareem2323-png/sketchglide-scoop): a pinned manifest for the complete Windows ZIP. Schema, checksum and archive contents are validated; actual Scoop installation/uninstallation remains untested. This is a developer-maintained bucket, not inclusion in Scoop's default buckets.

These channels have no listing charge for this release. Optional AI usage, payment processing and any paid services have their own costs. No paid membership, certificate or advertising has been purchased.

## Microsoft Store — free registration in the new flow

Microsoft currently offers **no registration fee** for Individual and Company accounts through its new onboarding entry point. Start at [storedeveloper.microsoft.com](https://storedeveloper.microsoft.com/); older Partner Center/Xbox/Visual Studio entry points may show the legacy fee flow. Follow Microsoft's current [account and verification instructions](https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/open-a-developer-account?tabs=individual).

1. Create the suitable account and complete identity verification directly with Microsoft. A personal project generally uses Individual with a personal Microsoft account; do not use school/work sign-in for that account type.
2. Reserve the app name. Obtain the exact package identity and publisher from Partner Center.
3. Build a Store MSIX for the WPF x64 app. Include all runtime, inference/OCR resources and licence notices. The current portable ZIP is not a Store package.
4. Test the packaged build on a physical Intel/AMD Windows 11 PC: launch, drawing, tablet pressure/eraser, copy/paste, local save/open, export, optional AI and updates/uninstall. Existing runtime QA used x64 emulation in a Windows ARM VM.
5. Run Windows App Certification Kit and fix failures.
6. Prepare accurate screenshots, features, privacy/support URLs, age rating and optional AI details.
7. Submit for certification, respond to review and verify a fresh Store install. Submission alone is not approval.

Microsoft signs approved MSIX/AppX Store packages. The separate MSI/EXE submission route requires a CA-trusted installer signature; our unsigned ZIP/Install.cmd is not that route. An outside-Store MSIX must be signed and trusted on users' devices. See [packaging a .NET desktop app](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/dotnet/package-app), [distribution paths](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path) and [MSIX signing](https://learn.microsoft.com/en-us/windows/msix/package/sign-msix-package-guide).

**Current state:** no Microsoft Store account or approved listing has been verified for this project. The source and checklist are ready; Store identity and packaged-build testing remain necessary.

## Mac App Store and trusted direct Mac downloads — US$99/year

Apple Developer Program membership is **US$99 annually**, with local pricing shown during enrolment. A free Apple sign-in does not provide Developer ID distribution signing/notarization. See [Apple's membership requirements and price](https://developer.apple.com/help/account/membership/program-enrollment/).

Apple review guideline 2.2 routes beta/Test apps through TestFlight. Keep the current 0.2 Test as a direct preview; prepare a production-quality version for the Mac App Store. The current generated Xcode configuration has sandboxing disabled and needs a Store-specific adaptation.

1. Enrol under the correct legal identity and create the App Store Connect record.
2. Prepare signing/provisioning and a separate appropriately sandboxed Store build.
3. Test file access, tablet behaviour, credentials and optional integrations within that package.
4. Prepare screenshots, privacy/support details, age rating and accurate features.
5. Check optional donation/payment links against [Apple's review rules](https://developer.apple.com/app-store/review/guidelines/), submit and verify an approved fresh install.

For trusted downloads outside the Store, use Developer ID signing and notarization. The current Mac Test is ad hoc signed and unnotarized. No paid enrolment or certificate is available for this release. See [Mac distribution](https://developer.apple.com/macos/distribution/).

## Other directories and promotion

Product Hunt, AlternativeTo, MacUpdate and Show HN have not been submitted. They need their own accounts or posting eligibility and accurate disclosures. WinGet needs a compatible validated manifest, unattended installation, the repository's contributor agreement and review; it is not currently listed there. Its repository does not accept our PowerShell setup scripts as an installer. See [WinGet submission](https://learn.microsoft.com/en-us/windows/package-manager/package/repository) and [repository policies](https://github.com/microsoft/winget-pkgs/blob/master/doc/Policies.md).

Use the [creator kit](https://github.com/12kareem2323-png/karim-ink/releases/download/v0.2.0-test/SketchGlide-Creator-Kit.zip?v=af848eda) for five editable one-minute scripts/prompts, captions and subtitles. Its two silent edited promos are not AI-generated footage. Upload finished videos using [YouTube Studio](https://studio.youtube.com/), [TikTok Studio](https://www.tiktok.com/tiktokstudio) or [Instagram](https://www.instagram.com/). Review generated visuals and avoid claims of Store approval, universal tablet support or guaranteed 120 FPS.

Use the [interactive website checklist](https://karim-ink.stonyvale1.chatgpt.site/publishing.html) to keep personal progress notes. It stores only checkbox marks in that browser and submits nothing to a store.

The [Store preparation kit](StoreSubmission/README.md) provides listing drafts, original icons, required identity inputs and an MSIX preparation helper. The helper has not been executed or SDK-validated; no MSIX is provided. [Free publishing/discovery list](Distribution/FREE-PUBLISHING-OPTIONS.md) lists additional routes with their current requirements.
