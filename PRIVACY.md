# Karim Ink privacy

This describes the Mac 0.1 preview. Karim Ink is a local drawing app with optional cloud integrations.

## Local work

Drawings, imported content, 3D drafts and application preferences are kept on your Mac. Editable drawings and export copies are ordinary local files; the app does not add its own file encryption. They can contain notes, images and metadata such as drawing names. Anyone you give a file to may be able to read that content.

Ink smoothing, Apple Vision text recognition, local spelling suggestions and DeTeXt single-symbol recognition run on the Mac. Automatic handwriting review reads a bounded amount of recent ink after a drawing pause and offers suggestions. You can turn it off in Assistant settings. It does not automatically send handwriting to OpenAI or replace the original ink.

The app does not include an analytics SDK or advertising SDK. Boards are not uploaded unless you use the optional services described below. Feedback is submitted deliberately. macOS and any separately used service have their own privacy settings and policies.

## AI choices

**On this Mac** uses Apple's on-device model when it is available. It needs compatible hardware, macOS 26 or later and a ready Apple Intelligence model. The app checks availability before using it.

**OpenAI** sends your current prompt and recent conversation text to the OpenAI API when you click Send. A rendered board image is included only if you choose **Attach current board**. Cloud wording correction sends the preview text when you explicitly choose that action.

**Auto** chooses a route based on the request and shows it before Send. Complex engineering questions, calculations and board images can select the cloud route; Auto does not mean every question stays local.

Your OpenAI API key is stored in macOS Keychain, not in drawing files or exports. You can remove it in Assistant settings. API chat requests ask OpenAI not to store the response (`store: false`); this is not a promise of zero provider retention. OpenAI's own terms and data controls apply. Chat history remains in memory for the current drawing session and is not saved inside `.engboard` files.

## Craft, Notion and external links

Craft updating is optional. A configured connection sends supported drawing objects to the selected Craft whiteboard when you send/update, or while you explicitly enable Live updates. Craft credentials stay in Keychain. This is one-way updating, not shared editing.

Notion HTML, Excalidraw and image/PDF exports create files for you to share. An exported companion can contain a rendered copy of the board and editable new ink. Uploading it to a service shares that content with the destination under that service's rules. Native board links reopen a saved drawing in the Mac app; they do not upload it.

Optional embedded Notion/Microsoft Whiteboard panels use a persistent WebKit website-data store. If you sign in there, the service can keep cookies, local storage and a signed-in session on this Mac across app launches. That data is separate from drawing files and can remain after a drawing is deleted. Use the service's own sign-out controls; signing out may leave cached website data behind. You can use your normal browser instead of the embedded panel.

Help, feedback and donation links open an external site. That site can receive the normal information associated with a visit, and information you choose to submit. Donation processing is handled by the chosen payment service; Karim Ink does not collect card details.

## Permissions and control

Ordinary drawing does not require Full Disk Access, camera, microphone or screen-recording access. File import/export uses the system file chooser. Tablet operation may need permissions for the tablet's own driver. Optional direct Quick Keys control may need Input Monitoring and is disconnected by default.

You can export your editable drawings, delete drawings from the library, remove saved integration credentials and disable optional cloud features. Recovery/archive copies and exported files may remain after a library item is deleted; remove copies you no longer need separately.

For questions, use [project support](https://github.com/12kareem2323-png/karim-ink/issues). Do not include private drawings, API keys, connection tokens or personal information in a public issue.
