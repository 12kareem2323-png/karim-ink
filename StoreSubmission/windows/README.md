# SketchGlide Windows Store preparation

Made by Karim Eldamaty. Prepared 12 October 2026. **Draft preparation only:** no MSIX has been built, signed, installed, WACK-tested, submitted or approved. The original app remains the unsigned 0.2 Test. The Windows SDK MakeAppx tool was absent in the inspected test VM. The new preparation script has been reviewed but not executed.

## What is included

- An MSIX manifest template with mandatory Store identity placeholders.
- Prepare-StorePackage.ps1, which verifies the pinned application ZIP before creating a new draft folder. It never signs, installs, submits, downloads files or changes execution policy.
- Original SketchGlide logo sizes and complete dependency notices.
- An identity input file, listing draft, privacy snapshot and remaining QA checklist.

## Obtain the exact input

Download https://github.com/12kareem2323-png/karim-ink/releases/download/v0.2.0-test/SketchGlide-0.2.0-Windows-x64-Test.zip into this kit's Inputs folder. The application ZIP is deliberately excluded from the kit to avoid another 104 MB copy. Compare SHA-256 with Inputs/SHA256SUMS.txt. The expected hash is ed275d81fd370d5d3dcd873350e736f0438880d04bddf9c1fdf4fb50e9eda018.

## After creating the free Microsoft account

1. Start at https://storedeveloper.microsoft.com/ and complete the owner identity check directly with Microsoft. Reserve the app name.
2. Copy IDENTITY-INPUTS.json to a private working file and fill the exact PackageIdentityName, PublisherDistinguishedName, PublisherDisplayName and ReservedDisplayName shown in Partner Center. Keep the published blank template unchanged.
3. Choose a four-part StorePackageVersion that follows Microsoft's current rules. Its first component must be nonzero and its fourth component 0. Store packaging version is separate from the current native 0.2 Test display version; no Store version has been chosen or reserved by this kit.
4. On Windows, run the helper using your reviewed exact identity file:

```powershell
powershell -NoProfile -File .\Prepare-StorePackage.ps1 -IdentityFile .\my-identity.json -OutputName SketchGlide-Store-Draft-01
```

If local script policy prevents execution, use your own approved development environment. Do not weaken system policy for this kit.

The helper creates a new Prepared child folder; an existing output is never overwritten. To additionally create an **unsigned draft MSIX**, pass -Pack and -MakeAppxPath with the path to your Microsoft-signed Windows SDK MakeAppx.exe. The SDK's default semantic checks are enabled, but those checks do not establish installability or certification. No SDK is installed automatically.

## Remaining packaging and review gates

- Confirm the exact Store identity and reserved app name, then prepare a consistent final release version.
- Review runFullTrust and unvirtualizedResources restricted capabilities and justify them to Microsoft. The draft excludes only the existing drawing/settings folders from write virtualization; acceptance and actual packaged behaviour are unverified. Adapt the source/container approach if those capabilities are refused.
- Prefer Visual Studio's Store packaging workflow to produce its recommended .msixupload after association with the real Store identity. MakeAppx alone produces an MSIX, not that upload wrapper.
- Test launch, native DLL/model/OCR loading, drawing, saving, clipboard, export, tablet/eraser, links and DPAPI credentials on a physical Intel/AMD Windows 11 PC using the actual package. Test updates and uninstall/data retention with made-up files.
- Run Windows App Certification Kit. Test the interactive setup dialogue separately if retaining an outside-Store installer; the Store package should not depend on Install.cmd.
- Confirm final privacy, age rating, restricted-capability justification, accessibility, contact details and encryption/export-compliance form answers. They remain unanswered.
- Upload accurate real screenshots, submit for review and verify an approved fresh Store install.

Store-approved MSIX submissions receive Microsoft signing. An outside-Store MSIX still needs a signature trusted by recipients. The existing ZIP/Install.cmd is not a signed MSI/EXE Store submission. No certificate has been bought or imported.

Official references:
- https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/open-a-developer-account?tabs=individual
- https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-package-requirements
- https://learn.microsoft.com/en-us/windows/msix/package/create-app-package-with-makeappx-tool
- https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/dotnet/package-app
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path
