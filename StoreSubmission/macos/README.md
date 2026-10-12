# SketchGlide Mac App Store preparation

Prepared 12 October 2026. **No App Store submission, paid enrolment, sandboxed Store archive, distribution signing or notarization has been completed by this kit.** The current public Mac package is an Apple Silicon, macOS 14+ target, ad hoc signed and unnotarized Test app.

Read `LISTING-DRAFT.md`, `SCREENSHOTS.md` and `REVIEW-NOTES-DRAFT.md`. The structured draft is in `listing-draft.json`. These are preparation documents; they are not an uploadable Store package.

## Account and cost

Apple lists **US$99 per membership year**, with regional pricing shown during enrolment. Apple's current UK Developer app listing shows **£78.99** for the program purchase; confirm the actual renewal/checkout amount before paying. A free Apple Account login does not provide a paid distribution team. No payment or enrolment is authorized by this kit. [Membership requirements](https://developer.apple.com/programs/enroll/), [current UK Apple listing](https://apps.apple.com/gb/app/apple-developer/id640199958)

The owner must complete identity verification directly with Apple, enable two-factor authentication, accept agreements and obtain a verified Team ID. Individual and organisation enrolment have different legal identity requirements; do not invent a company or seller name.

## Remaining workflow

1. Choose TestFlight for the present Test stage, or finish a production release before requesting Store review. A beta-labelled build is not a production Store release. [Apple guideline 2.2](https://developer.apple.com/app-store/review/guidelines/#beta-testing)
2. Once the owner elects to enrol, use the verified Apple team in full compatible Xcode. Register or confirm the existing bundle ID, enable App Sandbox, configure only required capabilities, and create a Store-specific build configuration. Preserve the independent downloadable Test app.
3. Adapt and test the file library, imports/exports, permissions, Keychain, outbound AI/Craft requests and optional HID bridge under the sandbox. Do not assume the current unsandboxed tests establish Store compatibility. Apple requires a self-contained sandboxed Mac Store app packaged through Xcode. [Mac Store requirements](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)
4. Produce and validate a fresh signed Xcode archive using the verified distribution identity/provisioning. Upload through Xcode's App Store Connect distribution workflow. Fix validation and processing errors; keep the upload receipt. A renamed ZIP/DMG is insufficient. [Apple upload workflow](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
5. Create the macOS app record, reconcile app/build versions, match the Xcode macOS app category to the chosen Store category, add the listing and screenshots, confirm real support details, finish privacy/age-rating/encryption/accessibility and regional compliance questions, and choose price/availability. These forms remain unanswered. [App record workflow](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
6. Supply review access for every enabled feature, run TestFlight and clean-install/upgrade checks, then submit the production build. Release manually only after approval and final owner review. No approval or release date can be promised.

## Technical gaps to resolve before upload

- `BuildSupport/create_xcode_project.py` explicitly sets `ENABLE_APP_SANDBOX=NO`, `ENABLE_HARDENED_RUNTIME=NO`, ad hoc `CODE_SIGN_IDENTITY=-` and manual signing. The inspected shipping bundle has no verified Team ID or sandbox entitlements. Store signing/configuration is unavailable and untested.
- Board storage currently uses Application Support `EngineeringBoard/Boards`. A sandbox changes the application container: test migration through a deliberate user-selected import without reading/deleting private drawings automatically. Verify save/recovery, exports, bookmarks and reopened files after restart.
- Outbound OpenAI/Craft networking needs appropriate sandbox access. Test Keychain access with the final team identity. Audit Quick Keys `IOHID` access, Input Monitoring, file pickers and any `Process` use; avoid blanket temporary exceptions. Apple asks for explanations of each requested temporary exception. [Sandbox submission information](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information/)
- No `.entitlements` or `PrivacyInfo.xcprivacy` file was found in the current source tree. Audit required-reason API use, including `UserDefaults`, and bundle accurate privacy-manifest declarations where required. Do not invent reasons. [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- Existing QA records clean native build, isolated packaged launches, local Core ML inference, export/storage/geometry/mock AI checks and native UI inspection. XCTest was **not executed** with the installed Command Line Tools. Sandbox, TestFlight/Store installation, macOS 14 runtime, physical tablets, live paid cloud AI, accessibility and sustained CPU/GPU/battery/120 FPS performance need relevant tests.

## Privacy, support and optional donations

Audit local drawings/OCR, Keychain credentials, selected AI text/images, Craft exports/sync and public GitHub feedback. Provider handling and retention must be checked; `store:false` in an API payload is not a privacy-form answer. Do not mark “Data Not Collected” without the complete audit. Confirm a public policy and accessible in-app policy link; the current public policy URL is a candidate, not an approved Store disclosure. [Apple privacy details](https://developer.apple.com/app-store/app-privacy-details/)

The existing support page offers GitHub feedback. Add or confirm a real contact route appropriate for the published app; never publish a private address, email or phone from a guess. [Support URL requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)

The current bundle includes an optional external PayPal support link and says it unlocks no features. Its acceptance in the Store build is **unreviewed**. Document the exact flow, storefronts and provider charges. Apple's tip/gift/payment rules require case-specific review; do not label Karim an approved nonprofit. If Apple requires changes, use an approved tip/IAP design or remove the link from the Store build. [Payment and donation rules](https://developer.apple.com/app-store/review/guidelines/#business)

## Separate direct-download signing

Developer ID signing, hardened-runtime validation, `notarytool` submission and stapling are the direct-download route. They remain unavailable/untested without the necessary paid team identity. This is separate from the Mac App Store upload/review workflow; notarizing the existing ZIP does not make it a Store package. [Apple Developer ID distribution](https://developer.apple.com/developer-id/)
