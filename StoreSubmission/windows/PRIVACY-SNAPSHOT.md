# SketchGlide privacy · 0.2 Test

SketchGlide is a local drawing app with optional online services. It contains no advertising or analytics SDK. The ordinary app does not upload drawings automatically. Files are ordinary local editable documents, not encrypted vaults: a person you share them with can read their content.

## Local work

Drawing, saving, ink smoothing and single-symbol recognition run locally. Mac text recognition uses Apple Vision and spelling services. Windows uses local Tesseract English OCR and Windows spelling suggestions. Review suggestions before inserting/replacing; changes can be undone. The local 3D sketchbook stores editable scene files.

Historic storage/internal identifiers are preserved to keep earlier drawings compatible. Recovery/archive/export copies may remain after deleting a library item; delete unwanted copies separately.

## Optional AI

On Mac, a ready Apple Intelligence model can answer locally on compatible hardware with macOS 26 or later. On Windows, optional Ollama connects to a separately installed model at `127.0.0.1:11434` for text-only local requests. No local model is silently replaced by a paid cloud request after failure.

The OpenAI option sends the prompt when you click Send. Mac also includes recent in-memory conversation text. A board image is sent only when you choose Attach. Explicit cloud wording correction sends the reviewed text. The route is displayed before sending; Auto on Mac can select the cloud for complex questions or image attachments. Your API key and separate API billing are required; a ChatGPT subscription does not supply API access.

API requests use `store: false`. This requests that OpenAI not store the response; it does not promise zero provider retention. OpenAI's own terms and controls apply.

Mac keys and Craft credentials are stored in macOS Keychain. Windows credentials are encrypted for the current Windows user with DPAPI under `%LOCALAPPDATA%\KarimEldamaty\Credentials`. They are separate from drawings/exports. Mac session chat history stays in memory, not `.engboard`; Windows panel prompt/answer text is not automatically persisted. Explicitly inserting an answer stores it as ordinary drawing text.

## Other services and shared files

Craft exchange is optional and sends supported objects to a configured scoped connection after your action, or while Mac Live updates are explicitly enabled. It is not multiplayer/two-way native editing. Notion HTML and Excalidraw/image/PDF exports create copies you can share. The HTML companion uses a rendered board background plus separate new browser ink; it does not embed or synchronise the native app automatically.

Optional embedded service panels on Mac use persistent WebKit website storage. Signed-in cookies/cache can remain across launches and after a board is deleted. Use the service's sign-out controls, or your external browser. The service has its own privacy terms.

Help, feedback and donation buttons open external services after your action. A visit shares normal browser request information with that service. Payments are handled by PayPal; SketchGlide does not collect card details. Public GitHub feedback must not include keys, tokens or private drawings.

Ordinary drawing needs no Full Disk Access, microphone or camera permission. File import/export uses a file chooser. Tablet drivers can require their own permissions. Mac's optional direct Quick Keys bridge can require Input Monitoring and is disconnected by default.

The public website is remotely hosted, not served by the developer's Mac. Sites, GitHub Pages, itch.io and any services you choose have their own policies. The website adds no donation tracking or advertising SDK.

[Project feedback](https://github.com/12kareem2323-png/karim-ink/issues)
