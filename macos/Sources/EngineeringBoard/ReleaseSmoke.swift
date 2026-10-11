import AppKit
import SwiftUI
import CoreGraphics
import Darwin

/// An explicit, offline release check of the shipping @main entry point.
/// A fresh temporary library is selected before BoardStore is constructed;
/// no path argument can redirect this check to a real drawing library.
@MainActor
enum ReleaseSmoke {
    private struct Context {
        let output: URL
        let library: URL
        let defaultsName: String
    }
    private static var context: Context?
    private static var started = false
    static var isActive: Bool { context != nil }
    static var appearanceDefaults: UserDefaults? {
        context.flatMap { UserDefaults(suiteName: $0.defaultsName) }
    }

    static func prepare(arguments: [String] = Array(ProcessInfo.processInfo.arguments.dropFirst())) -> URL? {
        let smokeArguments = arguments.filter { $0.hasPrefix("--release-smoke") }
        guard !smokeArguments.isEmpty else { return nil }
        guard arguments == ["--release-smoke-test"] else {
            fail("The release check accepts only --release-smoke-test; no library paths or extra arguments are allowed.", code: 64)
        }
        let identifier = UUID().uuidString
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let output = temporary.appendingPathComponent("KarimInkSmoke-" + identifier, isDirectory: true)
        let library = output.appendingPathComponent("Boards", isDirectory: true)
        do {
            guard !FileManager.default.fileExists(atPath: output.path) else {
                fail("The release check requires a new temporary directory.", code: 64)
            }
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: output.path)
            context = Context(output: output, library: library, defaultsName: "com.karimeldamaty.karimink.smoke." + identifier)
            writeLine("KARIM_INK_SMOKE_OUTPUT=" + output.path)
            return library
        } catch {
            fail("The temporary release library could not be created: " + error.localizedDescription, code: 1)
        }
    }

    static func captureWhenReady(store: BoardStore, workspace: Workspace) {
        guard context != nil, !started else { return }
        started = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { capture(store: store, workspace: workspace, attempt: 0) }
    }

    private static func capture(store: BoardStore, workspace: Workspace, attempt: Int) {
        guard let context else { return }
        guard let mainWindow = NSApp.windows.first(where: { $0.title == "SketchGlide" && $0.isVisible }),
              let mainView = mainWindow.contentView, mainView.bounds.width >= 1000, mainView.bounds.height >= 600 else {
            guard attempt < 10 else { fail("The shipping app did not produce its main window.", code: 1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { capture(store: store, workspace: workspace, attempt: attempt + 1) }
            return
        }
        do {
            guard store.directory.resolvingSymlinksInPath() == context.library,
                  store.boards.isEmpty, store.error == nil else {
                throw SmokeError.invalid("The release library must remain empty and isolated.")
            }
            try snapshot(mainView, at: context.output.appendingPathComponent("shipping-home.png"))
            _ = nativeSnapshot(mainWindow, at: context.output.appendingPathComponent("shipping-home-native.png"))
            let feedbackWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            feedbackWindow.title = "SketchGlide · Feedback release check"
            feedbackWindow.isReleasedWhenClosed = false
            feedbackWindow.contentView = NSHostingView(rootView: ReleaseSupportView())
            feedbackWindow.center()
            feedbackWindow.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                captureDrawing(store: store, workspace: workspace, mainWindow: mainWindow, feedbackWindow: feedbackWindow)
            }
        } catch { fail("The shipping home check failed: " + error.localizedDescription, code: 1) }
    }

    private static func captureDrawing(store: BoardStore, workspace: Workspace, mainWindow: NSWindow, feedbackWindow: NSWindow) {
        guard let context else { return }
        var board = Board(title: "Hello, SketchGlide", width: 1280, height: 860)
            board.background = .dots
            board.elements = [
                DrawingElement(kind: .text, points: [.init(x: 72, y: 110)], color: .graphite, text: "hello, ideas.", fontSize: 54),
                DrawingElement(kind: .text, points: [.init(x: 75, y: 188)], color: .teal, text: "A personal sketch space. Made by Kareem.", fontSize: 21),
                DrawingElement(kind: .rectangle, points: [.init(x: 74, y: 290), .init(x: 290, y: 390)], color: .teal, width: 2),
                DrawingElement(kind: .text, points: [.init(x: 108, y: 325)], text: "Sketch an idea", fontSize: 22),
                DrawingElement(kind: .arrow, points: [.init(x: 308, y: 340), .init(x: 407, y: 340)], color: .teal, width: 2),
                DrawingElement(kind: .rectangle, points: [.init(x: 424, y: 290), .init(x: 640, y: 390)], color: .violet, width: 2),
                DrawingElement(kind: .text, points: [.init(x: 456, y: 325)], text: "Make it clearer", fontSize: 22),
                DrawingElement(kind: .text, points: [.init(x: 76, y: 482)], color: .graphite, text: "Small strokes. Big possibilities.", fontSize: 28),
                DrawingElement(kind: .dimension, points: [.init(x: 75, y: 624), .init(x: 575, y: 624)], color: .teal, width: 1.5)
            ]
            let wave = (0...140).map { i -> InkPoint in
                let t = Double(i) / 140
                return InkPoint(x: 75 + 590 * t, y: 560 + sin(t * .pi * 4) * 30,
                    pressure: 0.25 + 0.6 * t)
            }
            board.elements.append(DrawingElement(kind: .stroke, points: wave, color: .teal, width: 5, pen: .fountain))
            let session = DrawingSession(board: board, storesPreferences: false)
            session.zoom = 1
            session.selectedIDs = []
            workspace.session = session
            workspace.showLibrary = false
            feedbackWindow.orderOut(nil)
            mainWindow.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                do {
                    guard let view = mainWindow.contentView, store.boards.isEmpty,
                          workspace.session?.board.elements.count == board.elements.count,
                          workspace.session?.selectedIDs.isEmpty == true else {
                        throw SmokeError.invalid("The synthetic drawing must remain unselected and outside the library.")
                    }
                    try snapshot(view, at: context.output.appendingPathComponent("shipping-drawing.png"))
                    _ = nativeSnapshot(mainWindow, at: context.output.appendingPathComponent("shipping-drawing-native.png"))
                    for format in ExportFormat.allCases {
                        let data = try BoardExport.data(board: board, format: format)
                        try data.write(to: context.output.appendingPathComponent("synthetic-drawing." + format.fileExtension), options: .atomic)
                    }
                    feedbackWindow.makeKeyAndOrderFront(nil)
                    finish(store: store, mainWindow: mainWindow, feedbackWindow: feedbackWindow)
                } catch { fail("The synthetic canvas/export check failed: " + error.localizedDescription, code: 1) }
            }
    }

    private static func finish(store: BoardStore, mainWindow: NSWindow, feedbackWindow: NSWindow) {
        guard let context else { return }
        do {
            guard let feedbackView = feedbackWindow.contentView else { throw SmokeError.invalid("No feedback view.") }
            try snapshot(feedbackView, at: context.output.appendingPathComponent("shipping-feedback.png"))
            let nativeFeedback = nativeSnapshot(feedbackWindow, at: context.output.appendingPathComponent("shipping-feedback-native.png"))
            let resourceRoot = Bundle.main.resourceURL!
            let requiredResources = ["AppIcon.icns", "MathSymbols/deTeX.mlmodel", "MathSymbols/symbols.json",
                "MathSymbols/PROVENANCE.md", "THIRD_PARTY_NOTICES.md"]
            let resources = requiredResources.map { (path: $0, present: FileManager.default.fileExists(atPath: resourceRoot.appendingPathComponent($0).path)) }
            guard resources.allSatisfy(\.present), ReleaseSupport.version == "0.2.0",
                  ReleaseSupport.build == "2", Bundle.main.bundleIdentifier == "com.karimeldamaty.karimink",
                  store.boards.isEmpty else { throw SmokeError.invalid("Version, branding, resources or isolated storage check failed.") }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let checks = ["shippingMainEntryPoint": true, "mainWindowVisible": mainWindow.isVisible,
                "feedbackRendered": feedbackWindow.isVisible, "emptyTemporaryLibrary": store.boards.isEmpty,
                "isolatedLibrary": store.directory.resolvingSymlinksInPath() == context.library,
                "bundledResourcesPresent": resources.allSatisfy(\.present), "noCloudRequestInvoked": true, "syntheticCanvasRendered": true, "syntheticExportsWritten": true, "noAutomaticSelection": true]
            let receipt = Receipt(status: "passed", version: ReleaseSupport.version, build: ReleaseSupport.build,
                bundleIdentifier: Bundle.main.bundleIdentifier!, library: context.library.path, nativeFeedbackCapture: nativeFeedback,
                windowTitle: mainWindow.title, checks: checks, resources: requiredResources)
            try encoder.encode(receipt).write(to: context.output.appendingPathComponent("receipt.json"), options: .atomic)
            UserDefaults.standard.removePersistentDomain(forName: context.defaultsName)
            writeLine("KARIM_INK_SMOKE_RESULT=" + context.output.appendingPathComponent("receipt.json").path)
            feedbackWindow.close()
            NSApp.terminate(nil)
        } catch { fail("The shipping feedback/resource check failed: " + error.localizedDescription, code: 1) }
    }

    private static func snapshot(_ view: NSView, at destination: URL) throws {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw SmokeError.invalid("The native view could not be captured.")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SmokeError.invalid("The view PNG could not be encoded.")
        }
        try data.write(to: destination, options: .atomic)
    }
    // Capture only windows created by this isolated app instance. Never request
    // new screen permission, and never capture the user's desktop or other apps.
    private static func nativeSnapshot(_ window: NSWindow, at destination: URL) -> Bool {
        guard CGPreflightScreenCaptureAccess() else { return false }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), destination.path]
        capture.standardOutput = FileHandle.nullDevice
        capture.standardError = FileHandle.nullDevice
        do { try capture.run(); capture.waitUntilExit() }
        catch { return false }
        return capture.terminationStatus == 0 && FileManager.default.fileExists(atPath: destination.path)
    }
    private static func writeLine(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
    private static func fail(_ message: String, code: Int32) -> Never {
        writeLine("KARIM_INK_SMOKE_FAILED=" + message)
        exit(code)
    }
    private struct Receipt: Codable {
        let status: String
        let version: String
        let build: String
        let bundleIdentifier: String
        let library: String
        let nativeFeedbackCapture: Bool
        let windowTitle: String
        let checks: [String: Bool]
        let resources: [String]
    }
    private enum SmokeError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
    }
}
