# SketchGlide · 0.2 Test

A personal whiteboard project **made by Kareem**. Draw, write, make diagrams and explore ideas in native Mac and Windows apps.

[Download the Test release](https://github.com/12kareem2323-png/karim-ink/releases/tag/v0.2.0-test) · [Website](https://karim-ink.stonyvale1.chatgpt.site/) · [Feedback](https://github.com/12kareem2323-png/karim-ink/issues) · [Support with PayPal](https://paypal.me/KEldamaty)

![The native Mac Test with a made-up drawing](assets/workspace-preview.png)

## Download

- **Mac:** Apple Silicon, macOS 14 or later. Download the DMG or app ZIP. Ad hoc signed and **unnotarized**; macOS may block first launch.
- **Windows Test:** Windows 11 **Intel/AMD x64**. Extract the entire ZIP, then open `SketchGlide.exe`. The .NET runtime is included. **Unsigned**; Windows may show an unknown-publisher warning.

These are early Test builds. Keep your editable drawings backed up and read [first-launch help](SUPPORT.md). The Windows app was checked in a Windows ARM virtual machine under x64 emulation; a physical Intel/AMD PC and your own drawing tablet still need testing. The Mac app was checked on Apple Silicon with macOS 27.2. No universal tablet support or locked 120 FPS is promised.

## What you can do

- Draw with **10 adjustable brushes** and **10 backgrounds**. Pan, zoom, use pressure when the driver supplies it, change colour and width, and undo edits.
- Keep new strokes unselected. Use deliberate selection/lasso, shapes, straightening, rulers, a protractor and millimetre dimensions.
- Place **380 searchable maths and engineering symbols**. Short diagram animations illustrate motion; they do not simulate real engineering behaviour.
- Review local text recognition, spelling suggestions and single-symbol maths recognition with **1,098 command classes**. Edit text/formulas, plot functions and use a calculator and unit conversions.
- Use an optional OpenAI API assistant with your own key and separate API billing. Mac also supports Apple's available on-device model; Windows can connect to a separately installed local Ollama model. Ordinary drawing and saving need no account.
- Make simple 3D concept sketches with planes and primitives, and retain editable `.karim3d` scenes.
- Save editable `.engboard` drawings; import images and export PNG/JPEG/PDF. Windows PDF embeds a raster drawing; Mac PDF supports vector output.
- Copy/paste, export an Excalidraw copy or a Notion-friendly HTML companion, and configure optional Craft exchange. Native apps are not embedded live inside Notion; these routes have different limits.
- Choose light, dark or system appearance, floating translucent tools and reduced-motion/transparency options.

The native apps use driver-provided tablet input and are not tied to one brand. Physical pressure, tilt, eraser and remote behaviour need checking with each device/driver. Whole handwritten-equation recognition, multiplayer, circuit simulation and full CAD constraints are not included. Review OCR/AI output, particularly numbers and units.

## Build it with me

**The editable app source is now included:** [macos/](macos/) contains Swift/SwiftUI/AppKit/Metal code; [windows/](windows/) contains C#/WPF code. [BUILDING.md](BUILDING.md) gives commands. Own code and original assets are **MIT licensed**; third-party models and dependencies retain their own [notices](THIRD_PARTY_NOTICES.md). You can fork the repository, make a focused change and open a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md).

[Privacy](PRIVACY.md) · [Verification](VERIFICATION.md) · [Release notes](RELEASE_NOTES.md) · [Security](SECURITY.md)

Also available on [itch.io](https://12kareem2323-png.itch.io/karim-ink). [GitHub Pages mirror](https://12kareem2323-png.github.io/karim-ink/). The existing `karim-ink` URLs and internal file/storage names are retained for compatibility; the project is now called **SketchGlide**.

Donations are optional and do not unlock features or buy a guaranteed support response. Payments go directly through [PayPal](https://paypal.me/KEldamaty); the app does not collect payment details.
