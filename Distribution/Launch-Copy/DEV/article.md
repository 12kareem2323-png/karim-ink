---
title: "SketchGlide: my native whiteboard project for Mac and Windows"
published: false
tags: opensource, windows, swift, dotnet
---

I'm Karim Eldamaty, and I've released **SketchGlide 0.2 Test**, my personal whiteboard project for Mac and Windows. I wanted a place to draw, write notes and build diagrams without needing an account for ordinary drawing and saving.

The Mac app uses Swift, SwiftUI, AppKit and Metal. The Windows app uses C# and WPF. Both versions have floating translucent tools, light and dark appearance, adjustable brushes and an editable local board format. The code is public, so people can look at how it works and help improve it.

## What is in the Test

There are ten brushes and ten backgrounds, plus shapes, straightening, rulers and millimetre dimensions. Finished strokes stay unselected until you deliberately use selection or a lasso. The library has 380 searchable maths and engineering symbols. There is also a simple 3D workspace for concept sketches using planes and primitives.

You can save editable drawings, import images, copy and paste, and export images or PDF. The Mac PDF route supports vector output; Windows PDF contains a raster drawing. There are export/exchange options for sharing with other tools, but the native whiteboard does not run live inside a Notion page.

Text recognition, spelling suggestions and single-symbol maths recognition are available for review. They can make mistakes, especially with numbers and units. An optional OpenAI API assistant uses your own key and separate API billing. It is not included with a ChatGPT subscription. The Mac can use Apple's on-device model when available; Windows can connect to a separately installed local Ollama model.

## What I still need to test

This is an early public Test, not an App Store release. The Mac build is for Apple Silicon and is unnotarized. The Windows build is for Windows 11 Intel/AMD x64 and is unsigned. Read the first-launch help before opening either version and keep backups of your drawings.

The Windows app has been checked under x64 emulation in a Windows ARM virtual machine. I still need feedback from physical Intel/AMD PCs and different drawing tablets. Tablet pressure and tilt use information supplied by the driver; I can't promise every tablet feature or a locked 120 FPS.

## Try it or improve the source

[Website](https://karim-ink.stonyvale1.chatgpt.site/) · [Mac and Windows downloads](https://github.com/12kareem2323-png/karim-ink/releases/tag/v0.2.0-test) · [First-launch help](https://github.com/12kareem2323-png/karim-ink/blob/main/SUPPORT.md)

My own code and original assets are MIT licensed. Third-party libraries and models keep their separate notices. You can [fork the source](https://github.com/12kareem2323-png/karim-ink), make a focused change and open a pull request.

If you test it, please [report a bug](https://github.com/12kareem2323-png/karim-ink/issues) with your operating system, tablet/driver if relevant, and the steps that caused the problem. Feedback on drawing, performance and first launch would help me decide what to improve next.
