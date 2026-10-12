# Mac listing draft

**Preparation only.** This copy describes implemented Mac features from the shipped source README. Revalidate each feature in the final sandboxed build before submitting; remove anything that cannot be reviewed. The current **0.2 Test** belongs on TestFlight while unfinished, rather than a production App Store page. [Apple review guideline 2.2](https://developer.apple.com/app-store/review/guidelines/#beta-testing)

## Copy-ready fields

- Name: **SketchGlide**
- Subtitle: **Engineering drawing & maths**
- Promotional text: A native Mac whiteboard for engineering diagrams, maths and ideas, with custom brushes, local symbol recognition and editable drawing files.
- Keywords: `whiteboard,drawing,maths,engineering,diagram,sketch,handwriting,symbols,graph,canvas`
- Category candidates: Graphics & Design; Productivity.
- Price candidate: Free. Availability and release timing remain the owner's choices.

## Description

SketchGlide brings drawing, maths and engineering diagrams into a native Mac workspace.

DRAW YOUR WAY
Choose from ten brush profiles and ten paper backgrounds. Adjust colour, line width, opacity and pressure response. Pan and zoom, undo and redo, and switch deliberately between drawing and selection. Use stroke or pixel erasing, geometric guides and millimetre dimensions.

BUILD DIAGRAMS AND WORK THROUGH MATHS
Browse 380 engineering and mathematics symbols. Recognise individual handwritten symbols locally and review the suggested match. Add editable text and formulas, use the calculator, and plot graphs. Local handwriting smoothing and OCR review help you refine notes while keeping control of the result.

KEEP AND SHARE YOUR WORK
Save drawings in a local library and export PDF, PNG, JPEG or editable .engboard files. Explore sketch planes and basic 3D primitives, with editable .karim3d files. Craft exchange and Notion-friendly HTML export provide ways to move work into other tools.

A MAC WORKSPACE
Choose light, dark or system appearance with native glass-style controls. The app targets Apple Silicon Macs running macOS 14 or later.

OPTIONAL CLOUD ASSISTANCE
Configure your own OpenAI API access for cloud assistance. Cloud features require an internet connection and may incur provider charges. A ChatGPT subscription does not include API access. Core drawing and local symbol recognition work without a cloud AI key.

Recognition suggestions need review. This is an engineering sketching tool and does not claim CAD certification, full handwritten-equation recognition or universal drawing-tablet compatibility.

## Fields still requiring confirmation

Use the structured values in `listing-draft.json`. The proposed marketing/support/privacy URLs already have public pages, but their final Store wording and support contact details still need review. Do not infer a verified seller name, Team ID, age rating, privacy-label answers, encryption declaration or legal trading status. The current bundle identifier is `com.karimeldamaty.karimink`; its availability under a future Apple team is unconfirmed.

The current shipped build is version `0.2.0`, build `2`. Choose the production version and a fresh Store build number, then match the actual archive. The current ZIP's copyright text says “Kareem”; the source licence names Karim Eldamaty. The editable source Info.plist was corrected to Karim Eldamaty on 12 October; pick up that correction in the next properly built Store archive. Existing Test archive bytes are retained.

The first App Store version does not need a “What's New” update field. Draft field lengths are checked locally: name/subtitle ≤30 characters; promotional text ≤170; keywords ≤100 bytes; description ≤4000 characters. [Apple name/subtitle fields](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/), [version metadata fields](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)

Feature evidence: the current Mac source `README.md`, source files and release QA. No 120 FPS guarantee, live multiplayer, complete handwriting-to-LaTeX, automatic Notion embedding, every-tablet support, CAD accuracy certification or App Store approval is claimed.
