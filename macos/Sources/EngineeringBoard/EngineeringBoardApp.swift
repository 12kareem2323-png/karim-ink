import SwiftUI
import AppKit
import CoreText
import ImageIO

@MainActor
final class Workspace: ObservableObject {
    @Published var session: DrawingSession?
    @Published var conversation = AssistantConversation()
    @Published var showLibrary = true
    @Published var search = ""
    @Published var folder = "All drawings"
    @Published var showInspector = true
    @Published var inspectorTab = "Tools"
    @Published var showServices = false
    @Published var showDeTeXt = false
    @Published var showSketch3D = false
    private weak var savingStore: BoardStore?
    func finishEditing() -> Bool {
        guard let session, let store = savingStore else { return true }
        session.finishActiveInput?()
        return store.save(session.board)
    }
    func open(_ board: Board, store: BoardStore) {
        guard finishEditing() else { return }
        guard store.reload(), let saved = store.boards.first(where: { $0.id == board.id }) else {
            store.error = store.error ?? "This drawing is no longer in the local library."
            return
        }
        savingStore = store
        let next = DrawingSession(board: saved)
        next.onSave = { [weak store] board in store?.scheduleSave(board) }
        if conversation.busy { conversation.cancel() }
        conversation = AssistantConversation()
        session = next
        showLibrary = false
    }
    func home() { guard finishEditing() else { return }; if conversation.busy { conversation.cancel() }; session = nil; showLibrary = true }
    func recoverAsNewDrawing(store: BoardStore) {
        guard let current = session else { return }
        current.finishActiveInput?()
        var copy = current.board
        copy.id = UUID(); copy.created = Date(); copy.modified = Date(); copy.title += " · recovered copy"
        guard store.save(copy) else { return }
        if !store.boards.contains(where: { $0.id == copy.id }) { store.boards.insert(copy, at: 0) }
        _ = store.reload()
        store.conflictingBoardID = nil
        replaceSession(copy, store: store)
    }
    func reloadSavedDrawing(store: BoardStore) {
        guard let id = session?.board.id, store.reload() else { return }
        guard let saved = store.boards.first(where: { $0.id == id }) else {
            if conversation.busy { conversation.cancel() }
            session = nil; showLibrary = true
            store.error = "This drawing was removed from the library. Your unsaved version is preserved in Archive/Conflicts."
            return
        }
        replaceSession(saved, store: store)
    }
    private func replaceSession(_ board: Board, store: BoardStore) {
        if conversation.busy { conversation.cancel() }; conversation = AssistantConversation()
        let next = DrawingSession(board: board)
        next.onSave = { [weak store] board in store?.scheduleSave(board) }
        savingStore = store; session = next; showLibrary = false
    }
    func create(store: BoardStore, title: String = "Untitled drawing", background: BackgroundKind = .grid, folder: String = "General") {
        guard finishEditing() else { return }
        let board = store.create(title: title, background: background, folder: folder)
        guard store.boards.contains(where: { $0.id == board.id }) else { return }
        open(board, store: store)
    }
    func duplicate(_ board: Board, store: BoardStore) {
        guard finishEditing() else { return }
        let copy = store.duplicate(board)
        guard store.boards.contains(where: { $0.id == copy.id }) else { return }
        open(copy, store: store)
    }
    func importDrawing(store: BoardStore) {
        guard finishEditing() else { return }
        if let board = store.importBoard() { open(board, store: store) }
    }
    func openURL(_ url: URL, store: BoardStore) {
        if url.scheme?.lowercased() == BoardLinks.scheme {
            guard let id = BoardLinks.boardID(from: url) else {
                store.error = "This board link is invalid."
                return
            }
            guard finishEditing(), store.reload() else { return }
            guard let board = store.boards.first(where: { $0.id == id }) else {
                store.error = "This board link isn't in the drawing library on this Mac. Import its editable .engboard file first."
                return
            }
            open(board, store: store)
        } else {
            guard url.isFileURL else {
                store.error = "Open a local .engboard file or a valid karimboard drawing link."
                return
            }
            do {
                guard finishEditing() else { return }
                open(try store.importBoard(from: url), store: store)
            } catch { store.error = error.localizedDescription }
        }
    }
    func launchDeTeXt(store: BoardStore) {
        if session == nil { create(store: store, title: "Maths notes", background: .graph) }
        guard session != nil, finishEditing() else { return }
        showDeTeXt = true
    }
    func launchSketch3D(store: BoardStore) {
        if session == nil { create(store: store, title: "3D sketches", background: .isometric) }
        guard session != nil, finishEditing() else { return }
        showSketch3D = true
    }
}

@main
struct EngineeringBoardApp: App {
    @NSApplicationDelegateAdaptor(BoardAppDelegate.self) private var appDelegate
    @StateObject private var store: BoardStore
    @StateObject private var workspace = Workspace()
    @StateObject private var appearance: AppAppearance
    init() {
        // The explicit release check never opens the user's drawing library.
        let temporaryLibrary = ReleaseSmoke.prepare()
        _store = StateObject(wrappedValue: BoardStore(directory: temporaryLibrary))
        _appearance = StateObject(wrappedValue: AppAppearance(defaults: ReleaseSmoke.appearanceDefaults ?? .standard))
    }
    var body: some Scene {
        Window("SketchGlide", id: "main") {
            WorkspaceWindowContent(store: store, workspace: workspace, appearance: appearance, appDelegate: appDelegate)
        }
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 1320, height: 820)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SketchGlide") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "SketchGlide", .credits: NSAttributedString(string: "Made by Kareem.\nA personal project for drawing, maths and ideas."), .applicationVersion: "0.2 Test · 0.2.0", .version: "2"
                    ])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Drawing") { workspace.create(store: store) }.keyboardShortcut("n")
                Button("Open Drawing File…") { workspace.importDrawing(store: store) }.keyboardShortcut("o")
                Button("Save Drawing") { if let s = workspace.session { s.finishActiveInput?(); store.save(s.board) } }.keyboardShortcut("s")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { workspace.session?.undo() }.keyboardShortcut("z").disabled(workspace.session?.canUndo != true)
                Button("Redo") { workspace.session?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(workspace.session?.canRedo != true)
            }
            CommandMenu("Drawing") {
                Button("DeTeXt Maths…") { workspace.launchDeTeXt(store: store) }
                Button("3D Sketch…") { workspace.launchSketch3D(store: store) }
                Divider()
                Button("Duplicate Selection") { workspace.session?.duplicateSelection() }.keyboardShortcut("d")
                Button("Bring to Front") { workspace.session?.moveLayer(forward: true) }.keyboardShortcut("]")
                Button("Send to Back") { workspace.session?.moveLayer(forward: false) }.keyboardShortcut("[")
                Button("Copy Board Link") { if let board = workspace.session?.board { _ = BoardLinks.copy(for: board) } }
                    .disabled(workspace.session == nil)
                Button("Library") { workspace.home() }.keyboardShortcut("h", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                SettingsLink { Text("Feedback & support…") }
                if let repository = ReleaseSupport.repository {
                    Link("Project and downloads", destination: repository)
                }
                if let website = ReleaseSupport.website {
                    Link("SketchGlide website", destination: website)
                }
            }
            CommandMenu("Tablet") {
                ForEach(TabletShortcutAction.allCases, id: \.rawValue) { action in
                    Button(action.label) { workspace.session?.performTabletAction(action) }
                        .keyboardShortcut(KeyEquivalent(Character(action.key)), modifiers: [.command, .option])
                        .disabled(workspace.session == nil)
                }
            }
        }
        Settings { AppSettingsView(appearance: appearance, libraryDirectory: store.directory)
            .preferredColorScheme(appearance.preferredColorScheme) }
    }
}

@MainActor
private final class DrawingWindowReference: ObservableObject {
    weak var window: NSWindow?
}

/// Each WindowGroup instance owns its receiving window reference, while all
/// instances continue to share the drawing workspace and its save guards.
@MainActor
private struct WorkspaceWindowContent: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var workspace: Workspace
    @ObservedObject var appearance: AppAppearance
    let appDelegate: BoardAppDelegate
    @StateObject private var windowReference = DrawingWindowReference()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        WorkspaceView(store: store, workspace: workspace, appearance: appearance)
            .frame(minWidth: 1000, minHeight: 650)
            .preferredColorScheme(appearance.preferredColorScheme)
            .background(DrawingWindowRegistration { window in
                windowReference.window = window
                appDelegate.registerDrawingWindow(window)
            })
            .onAppear {
                appDelegate.workspace = workspace
                appDelegate.reopenDrawingWindow = { openWindow(id: "main") }
                if let window = windowReference.window { appDelegate.registerDrawingWindow(window) }
                NSApp.setActivationPolicy(.regular)
                ReleaseSmoke.captureWhenReady(store: store, workspace: workspace)
            }
            // A unique native scene handles both cold and warm links in one
            // workspace, without creating another drawing window.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .onOpenURL { url in
                guard !ReleaseSmoke.isActive else { return }
                workspace.openURL(url, store: store)
                windowReference.window?.makeKeyAndOrderFront(nil)
            }
    }
}

@MainActor
final class BoardAppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: Workspace?
    var reopenDrawingWindow: (() -> Void)?
    private let drawingWindows = NSHashTable<NSWindow>.weakObjects()
    private var recoveringClosedDrawing = false
    func registerDrawingWindow(_ window: NSWindow) {
        guard !drawingWindows.contains(window) else { return }
        drawingWindows.add(window)
        // SwiftUI owns its window delegate and external-event lifecycle.
        // Observe only the exact drawing window; Settings is not registered.
        NotificationCenter.default.addObserver(self, selector: #selector(drawingWindowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: window)
        window.isOpaque = false; window.backgroundColor = .windowBackgroundColor
        window.title = "SketchGlide"
        window.titlebarAppearsTransparent = true
    }
    @objc private func drawingWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, drawingWindows.contains(window) else { return }
        if workspace?.finishEditing() == false {
            // The App-level workspace retains the unsaved document. Suppress
            // automatic last-window termination, then show its recovery UI.
            recoveringClosedDrawing = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reopenDrawingWindow?()
                self.recoveringClosedDrawing = false
            }
        } else {
            drawingWindows.remove(window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            if workspace?.conversation.busy == true { workspace?.conversation.cancel() }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !recoveringClosedDrawing }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        canClose() ? .terminateNow : .terminateCancel
    }
    private func canClose() -> Bool {
        guard workspace?.finishEditing() == false else {
            if workspace?.conversation.busy == true { workspace?.conversation.cancel() }
            return true
        }
        let alert = NSAlert(); alert.messageText = "Keep this drawing open"
        alert.informativeText = "The latest edit couldn't be saved. Keep the window open and export an editable copy, or fix the local save error before closing."
        alert.addButton(withTitle: "Keep open"); alert.runModal(); return false
    }
}

private struct DrawingWindowRegistration: NSViewRepresentable {
    let register: (NSWindow) -> Void
    func makeNSView(context: Context) -> RegistrationView { RegistrationView(register: register) }
    func updateNSView(_ view: RegistrationView, context: Context) {
        view.register = register
        if let window = view.window { register(window) }
    }
    final class RegistrationView: NSView {
        var register: (NSWindow) -> Void
        init(register: @escaping (NSWindow) -> Void) { self.register = register; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { register(window) } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct WorkspaceView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var workspace: Workspace
    @ObservedObject var appearance = AppAppearance()
    var body: some View {
        GeometryReader { geometry in
            let libraryOverlay = workspace.session != nil && geometry.size.width < 1220
            HStack(spacing: 0) {
                if workspace.showLibrary && !libraryOverlay {
                    LibrarySidebar(store: store, workspace: workspace).frame(width: 218)
                    Divider().opacity(0.25)
                }
                if let session = workspace.session {
                    DrawingWorkspace(session: session, store: store, workspace: workspace, appearance: appearance).id(session.board.id)
                } else {
                    LibraryHome(store: store, workspace: workspace)
                }
            }
            .overlay(alignment: .leading) {
                if workspace.showLibrary && libraryOverlay {
                    LibrarySidebar(store: store, workspace: workspace).frame(width: 218)
                        .shadow(color: .black.opacity(0.18), radius: 16, x: 8)
                }
            }
        }
        .background(GlassSurface(material: .sidebar))
        .tint(.teal)
        .navigationTitle(workspace.session?.board.title ?? "SketchGlide")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { workspace.showLibrary.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help("Show or hide drawing library").accessibilityLabel("Toggle drawing library")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { workspace.create(store: store) } label: { Label("New drawing", systemImage: "square.and.pencil") }
                    .help("New drawing · ⌘N")
            }
            ToolbarItem(placement: .automatic) {
                if workspace.session == nil { ThemeToggle(appearance: appearance) }
            }
            ToolbarItem(placement: .automatic) {
                SettingsLink { Image(systemName: "gearshape") }.help("Appearance, assistant and app access")
            }
        }
        .alert("Drawing library", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            if store.conflictingBoardID == workspace.session?.board.id && store.conflictingBoardID != nil {
                Button("Save edits as new drawing") { workspace.recoverAsNewDrawing(store: store) }
                Button("Reload saved version") { workspace.reloadSavedDrawing(store: store) }
                Button("Keep open", role: .cancel) { store.error = nil }
            } else { Button("OK") { store.error = nil } }
        } message: { Text(store.error ?? "") }
    }
}

struct LibrarySidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var store: BoardStore
    @ObservedObject var workspace: Workspace
    private var folders: [String] { Array(Set(store.boards.map(\.folder))).sorted() }
    private var recent: [Board] { Array(store.boards.sorted { $0.modified > $1.modified }.prefix(5)) }
    var body: some View {
        let counts = Dictionary(grouping: store.boards, by: \.folder).mapValues(\.count)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "pencil.and.ruler.fill").font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.teal).frame(width: 38, height: 38)
                    .background(LinearGradient(colors: [.teal.opacity(0.17), .cyan.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 3) {
                    Text("SketchGlide").font(.system(size: 14, weight: .semibold))
                    Text("0.2 · TEST RELEASE").font(.system(size: 8.5, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                }
            }.padding(.top, 24).padding(.bottom, 24)
            Button { workspace.create(store: store) } label: {
                HStack { Image(systemName: "plus"); Text("New drawing"); Spacer(); Text("⌘N").font(.caption).opacity(0.6) }
                    .padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).controlSize(.large).padding(.bottom, 20)
            navigationRow("All drawings", symbol: "square.grid.2x2", count: store.boards.count, selected: workspace.session == nil && workspace.folder == "All drawings") {
                workspace.home(); workspace.folder = "All drawings"
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    sidebarCaption("FOLDERS").padding(.top, 23).padding(.bottom, 6)
                    ForEach(folders, id: \.self) { name in
                        navigationRow(name, symbol: "folder", count: counts[name, default: 0], selected: workspace.session == nil && workspace.folder == name) {
                            workspace.home(); workspace.folder = name
                        }
                    }
                    if !recent.isEmpty {
                        sidebarCaption("RECENT").padding(.top, 22).padding(.bottom, 6)
                        ForEach(recent) { board in
                            Button { workspace.open(board, store: store) } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    Image(systemName: board.background == .isometric ? "cube.transparent" : "doc.richtext")
                                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(board.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(board.modified, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(.vertical, 8).padding(.horizontal, 9).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("Open \(board.title)")
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
            VStack(alignment: .leading, spacing: 13) {
                Divider().opacity(0.35)
                HStack(spacing: 7) {
                    Image(systemName: "internaldrive").foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your local drawing desk").font(.system(size: 11, weight: .medium))
                        Text("Draw and save offline").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                SettingsLink { Label("Settings", systemImage: "gearshape").font(.system(size: 12)) }.buttonStyle(.plain)
            }.padding(.top, 16).padding(.bottom, 20)
        }.padding(.horizontal, 16).background(GlassSurface(material: .sidebar))
    }
    private func sidebarCaption(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary).padding(.horizontal, 9)
    }
    private func navigationRow(_ title: String, symbol: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
            }.padding(.horizontal, 9).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .foregroundStyle(selected ? Color.teal : Color.primary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [.teal.opacity(reduceTransparency ? 0.24 : 0.18), .cyan.opacity(reduceTransparency ? 0.13 : 0.065)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.24 : 0.70), .teal.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5))
                        .shadow(color: .teal.opacity(colorScheme == .dark ? 0.08 : 0.045), radius: 7, y: 3)
                }
            }
            .accessibilityValue(selected ? "Selected, \(count) drawings" : "\(count) drawings")
    }
}

struct LibraryHome: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var workspace: Workspace
    @State private var sort = "Recent"
    @FocusState private var searchFocused: Bool
    var boards: [Board] {
        let query = workspace.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = store.boards.filter {
            (workspace.folder == "All drawings" || $0.folder == workspace.folder) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) || $0.folder.localizedCaseInsensitiveContains(query))
        }
        return sort == "Name" ? list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } : list.sorted { $0.modified > $1.modified }
    }
    private var recent: Board? { store.boards.max { $0.modified < $1.modified } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SketchGlide").font(.system(size: 32, weight: .semibold, design: .rounded)).tracking(-0.8)
                        HStack(spacing: 9) {
                            Text("0.2 TEST").font(.system(size: 9, weight: .bold)).tracking(1)
                                .foregroundStyle(.teal).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.teal.opacity(0.12), in: Capsule())
                            Text("Made by Kareem").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        }
                        Text("Draw freely. Make your next idea clearer.").font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 2)
                    }
                    Spacer(minLength: 10)
                    Button { workspace.importDrawing(store: store) } label: { Label("Import drawing", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered).controlSize(.large).help("Open an editable .engboard file · ⌘O")
                }
                if workspace.search.isEmpty && workspace.folder == "All drawings" {
                    starterShelf
                    HStack(spacing: 13) {
                        quickTool("DeTeXt Maths", detail: "Draw a symbol. Build a formula.", symbol: "function", tint: .teal) { workspace.launchDeTeXt(store: store) }
                        quickTool("3D Sketchbook", detail: "Pick a side. Sketch. Look around.", symbol: "cube.transparent", tint: .indigo) { workspace.launchSketch3D(store: store) }
                    }
                }
                VStack(spacing: 17) {
                    HStack(spacing: 12) {
                        Text(workspace.search.isEmpty ? workspace.folder : "Search results").font(.system(size: 19, weight: .semibold))
                        Text("\(boards.count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(.secondary)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                        Spacer()
                        Picker("Sort drawings", selection: $sort) { Text("Recent first").tag("Recent"); Text("Name").tag("Name") }
                            .labelsHidden().frame(width: 128)
                    }
                    HStack(spacing: 10) {
                        Button { searchFocused = true } label: { Image(systemName: "magnifyingglass").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).keyboardShortcut("f", modifiers: .command).accessibilityLabel("Search drawings")
                        TextField("Search titles, folders or notes", text: $workspace.search).textFieldStyle(.plain).focused($searchFocused)
                        if !workspace.search.isEmpty {
                            Button { workspace.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search")
                        } else { Text("⌘F").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }.padding(.horizontal, 14).padding(.vertical, 12)
                        .glassPanel(radius: 14)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.teal.opacity(searchFocused ? 0.48 : 0), lineWidth: 1))
                }
                if boards.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName: workspace.search.isEmpty ? "pencil.and.outline" : "magnifyingglass").font(.system(size: 33, weight: .light)).foregroundStyle(.teal)
                        Text(workspace.search.isEmpty ? "Your next drawing starts here" : "No matching drawings").font(.title3.weight(.semibold))
                        Text(workspace.search.isEmpty ? "Choose a paper above or create a new drawing." : "Try a title, folder or word from your notes.").foregroundStyle(.secondary)
                        if workspace.search.isEmpty { Button("Create a drawing") { workspace.create(store: store) }.buttonStyle(.borderedProminent) }
                        else { Button("Clear search") { workspace.search = "" }.buttonStyle(.bordered) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 55)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 360), spacing: 18)], alignment: .leading, spacing: 20) {
                        ForEach(boards) { board in
                            Button { workspace.open(board, store: store) } label: { DrawingCard(board: board) }
                                .buttonStyle(.plain).help("Open \(board.title)")
                                .contextMenu {
                                    Button("Open") { workspace.open(board, store: store) }
                                    Button("Duplicate") { workspace.duplicate(board, store: store) }
                                    Button("Copy board link") { _ = BoardLinks.copy(for: board) }
                                    Button("Export editable file…") { store.exportProject(board) }
                                    Divider()
                                    Button("Archive drawing") { store.delete(board) }
                                }
                        }
                    }
                }
                HStack(spacing: 7) {
                    Image(systemName: "internaldrive").foregroundStyle(.teal)
                    Text("Made by Kareem · Stored on this Mac · Your drawings stay editable").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.top, 2)
            }.padding(.horizontal, 30).padding(.top, 29).padding(.bottom, 30)
        }.background(LibraryBackdrop())
    }
    private var starterShelf: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("START SOMETHING").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                if let recent {
                    Button { workspace.open(recent, store: store) } label: {
                        HStack(spacing: 5) { Text("Continue"); Text(recent.title).lineLimit(1); Image(systemName: "arrow.right") }.font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(.teal).frame(maxWidth: 330, alignment: .trailing).help("Continue \(recent.title)")
                }
            }
            HStack(spacing: 12) {
                template("Blank sheet", "A clean start", "doc", .plain)
                template("Graph paper", "Maths & functions", "square.grid.3x3", .graph)
                template("Engineering", "Scale & dimensions", "ruler", .engineering)
                template("Blueprint", "Plans & schematics", "square.dashed", .blueprint)
            }
        }
    }
    private func template(_ title: String, _ detail: String, _ icon: String, _ background: BackgroundKind) -> some View {
        Button { workspace.create(store: store, title: title, background: background, folder: workspace.folder == "All drawings" ? "General" : workspace.folder) } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    LibraryPaperIcon(symbol: icon, background: background)
                    Spacer()
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading).librarySurface(radius: 13)
        }.buttonStyle(LibraryCardButtonStyle()).help("New drawing with \(background.rawValue.lowercased())")
    }
    private func quickTool(_ title: String, detail: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(tint)
                    .frame(width: 38, height: 38).background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 13, weight: .semibold)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 2); Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(14).librarySurface(radius: 13)
        }.buttonStyle(LibraryCardButtonStyle())
    }
}

/// A few static colour pools give the glass something to catch. These are plain
/// vector gradients: no blur filters, timeline or continuously running animation.
private struct LibraryBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if !reduceTransparency {
                    LinearGradient(colors: [Color.teal.opacity(colorScheme == .dark ? 0.055 : 0.04), .clear, Color.indigo.opacity(colorScheme == .dark ? 0.05 : 0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [.cyan.opacity(colorScheme == .dark ? 0.13 : 0.14), .clear], center: UnitPoint(x: 0.12, y: 0.05), startRadius: 10, endRadius: max(220, geometry.size.width * 0.44))
                    RadialGradient(colors: [.indigo.opacity(colorScheme == .dark ? 0.12 : 0.07), .clear], center: UnitPoint(x: 0.94, y: 0.27), startRadius: 0, endRadius: max(180, geometry.size.width * 0.38))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct LibraryPaperIcon: View {
    let symbol: String
    let background: BackgroundKind
    var body: some View {
        Image(systemName: symbol).font(.system(size: 19, weight: .light))
            .foregroundStyle(background == .blueprint ? Color.white.opacity(0.9) : Color.teal)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(background == .blueprint ? Color(red: 0.10, green: 0.24, blue: 0.36) : Color.teal.opacity(background == .plain ? 0.045 : 0.075))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(background == .blueprint ? 0.24 : 0.40), lineWidth: 0.5))
            }
    }
}

/// Library cards deliberately share cheap tint and rim rendering. Only the search
/// field uses live native glass, keeping large galleries light while scrolling.
struct LibrarySurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(reduceTransparency ? 1 : (colorScheme == .dark ? 0.64 : 0.72)))
                .overlay {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.065 : 0.30), .white.opacity(colorScheme == .dark ? 0.008 : 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
        }
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.27 : 0.86), .white.opacity(colorScheme == .dark ? 0.055 : 0.24), Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.055)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.13 : 0.045), radius: 9, y: 4)
    }
}

private struct LibraryCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LibraryCardButtonBody(configuration: configuration)
    }
}
private struct LibraryCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    var body: some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.teal.opacity(configuration.isPressed ? 0.54 : (hovering ? 0.30 : 0)), lineWidth: 1))
            .background(.teal.opacity(configuration.isPressed ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 13))
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .onHover { hovering = $0 }
    }
}
extension View { func librarySurface(radius: CGFloat) -> some View { modifier(LibrarySurface(radius: radius)) } }

struct DrawingCard: View {
    let board: Board
    @State private var preview: NSImage?
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let preview { Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit) }
                    else { Rectangle().fill(board.background == .blueprint || board.background == .dark ? Color(red: 0.08, green: 0.16, blue: 0.24) : Color(red: 0.985, green: 0.98, blue: 0.965)).overlay(Image(systemName: "pencil.tip").foregroundStyle(.secondary)) }
                }.frame(height: 148).frame(maxWidth: .infinity)
                    .background(board.background == .blueprint || board.background == .dark ? Color(red: 0.08, green: 0.16, blue: 0.24) : Color(red: 0.998, green: 0.994, blue: 0.98)).clipped()
                Text(board.background.rawValue).font(.system(size: 9, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.94), in: Capsule()).padding(10)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(board.title).font(.system(size: 13, weight: .semibold)).lineLimit(1); Spacer(minLength: 2); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.secondary).opacity(hovering ? 1 : 0) }
                HStack {
                    Label(board.folder, systemImage: "folder").lineLimit(1)
                    Spacer(minLength: 3)
                    Text(board.modified, format: .dateTime.day().month(.abbreviated)).lineLimit(1)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(14)
        }.clipShape(RoundedRectangle(cornerRadius: 15)).librarySurface(radius: 15)
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.teal.opacity(hovering ? 0.38 : 0), lineWidth: 1))
            .onHover { hovering = $0 }
            .onDisappear { preview = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(board.title), \(board.folder), \(board.background.rawValue)")
            .task(id: LibraryThumbnailCache.key(for: board)) {
                let raster = await LibraryThumbnailCache.shared.thumbnail(LibraryThumbnailInput(board: board))
                guard !Task.isCancelled, let raster else { return }
                preview = NSImage(cgImage: raster.image, size: NSSize(width: raster.image.width, height: raster.image.height))
            }
    }
}

/// Immutable board snapshots are safe to read on the thumbnail actor. This wrapper
/// never mutates the copy-on-write board, its points, data or embedded 3D document.
private struct LibraryThumbnailInput: @unchecked Sendable { let board: Board }
private struct LibraryThumbnailRaster: @unchecked Sendable { let image: CGImage }

/// Disposable, representative library previews, not the export renderer. Work is
/// serialized off the main actor and bounded regardless of original drawing size.
private actor LibraryThumbnailCache {
    static let shared = LibraryThumbnailCache()
    private struct Entry { let image: CGImage; let bytes: Int; var accessed: UInt64 }
    private var entries: [String: Entry] = [:]
    private var bytes = 0
    private var accessClock: UInt64 = 0
    private let maximumBytes = 16 * 1024 * 1024
    private let maximumCount = 48
    var statistics: (bytes: Int, count: Int) { (bytes, entries.count) }
    nonisolated static func key(for board: Board) -> String {
        "\(board.id.uuidString)-\(board.modified.timeIntervalSince1970)-\(board.elements.count)-\(board.background.rawValue)-\(board.width)-\(board.height)"
    }
    func thumbnail(_ input: LibraryThumbnailInput) -> LibraryThumbnailRaster? {
        let key = Self.key(for: input.board)
        accessClock &+= 1
        if var entry = entries[key] {
            entry.accessed = accessClock; entries[key] = entry
            return LibraryThumbnailRaster(image: entry.image)
        }
        guard !Task.isCancelled, let image = Self.render(input.board) else { return nil }
        let cost = image.bytesPerRow * image.height
        while bytes + cost > maximumBytes || entries.count >= maximumCount {
            guard let oldest = entries.min(by: { $0.value.accessed < $1.value.accessed }), let removed = entries.removeValue(forKey: oldest.key) else { break }
            bytes -= removed.bytes
        }
        if cost <= maximumBytes {
            entries[key] = Entry(image: image, bytes: cost, accessed: accessClock); bytes += cost
        }
        return LibraryThumbnailRaster(image: image)
    }
    private static func render(_ board: Board) -> CGImage? {
        let width = 512, height = 300
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let dark = board.background == .blueprint || board.background == .dark
        let paper: [CGFloat] = dark ? (board.background == .blueprint ? [0.075, 0.20, 0.36, 1] : [0.10, 0.12, 0.15, 1]) : [0.998, 0.994, 0.98, 1]
        context.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: paper)!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        // AppKit text/diagram drawing uses only this worker's thread-local context.
        // No window, view or cached main-thread NSImage is touched.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Uniform sampling includes the oldest and newest objects. Sampling affects
        // only this preview; the drawing and exported artwork remain exact.
        let count = min(240, board.elements.count)
        let elements: [DrawingElement] = (0..<count).map { index in
            let sourceIndex = count <= 1 ? 0 : index * (board.elements.count - 1) / (count - 1)
            var element = board.elements[sourceIndex]
            element.text = String(element.text.prefix(300))
            if element.points.count > 48 {
                let original = element.points
                element.points = (0..<48).map { original[$0 * (original.count - 1) / 47] }
            }
            return element
        }
        // Fit the original sheet and every object's extents, even when the
        // representative preview omits an object. Scan scalar coordinates off
        // the main actor; avoid the full export normalisation/point translation.
        var bounds = CGRect(x: 0, y: 0, width: board.width, height: board.height)
        for element in board.elements {
            guard let first = element.points.first else { continue }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for point in element.points.dropFirst() {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
            if element.kind == .text {
                let lines = element.text.split(separator: "\n", omittingEmptySubsequences: false)
                maxX = minX + max(80, Double(lines.map(\.count).max() ?? 0) * element.fontSize * 0.57)
                maxY = minY + max(element.fontSize * 1.5, Double(lines.count) * element.fontSize * 1.4)
            }
            let padding = element.kind == .stroke ? max(element.effectiveBrushSettings.maxWidth * 2, 2) : max(element.width / 2, 2)
            let rect = CGRect(x: minX - padding, y: minY - padding, width: maxX - minX + padding * 2, height: maxY - minY + padding * 2)
            let angle = element.rotation * .pi / 180
            let rotatedWidth = abs(cos(angle)) * rect.width + abs(sin(angle)) * rect.height
            let rotatedHeight = abs(sin(angle)) * rect.width + abs(cos(angle)) * rect.height
            bounds = bounds.union(CGRect(x: rect.midX - rotatedWidth / 2, y: rect.midY - rotatedHeight / 2, width: rotatedWidth, height: rotatedHeight))
        }
        bounds = bounds.insetBy(dx: -max(30, bounds.width * 0.04), dy: -max(30, bounds.height * 0.04))
        let scale = min(CGFloat(width - 36) / bounds.width, CGFloat(height - 32) / bounds.height)
        context.translateBy(x: (CGFloat(width) - bounds.width * scale) / 2, y: (CGFloat(height) - bounds.height * scale) / 2)
        context.scaleBy(x: scale, y: scale); context.translateBy(x: -bounds.minX, y: -bounds.minY)
        // Grid lines are capped in display space, so large sheets cannot trigger
        // millions of background primitives in a small thumbnail.
        if board.background != .plain {
            let spacing = max(board.gridSpacing, 10 / scale)
            context.setStrokeColor(CGColor(gray: dark ? 1 : 0.45, alpha: dark ? 0.12 : 0.10))
            context.setLineWidth(0.6 / scale)
            let visible = bounds.insetBy(dx: -bounds.width, dy: -bounds.height)
            if board.background != .lined {
                for x in stride(from: floor(visible.minX / spacing) * spacing, through: visible.maxX, by: spacing) { context.move(to: CGPoint(x: x, y: visible.minY)); context.addLine(to: CGPoint(x: x, y: visible.maxY)) }
            }
            for y in stride(from: floor(visible.minY / spacing) * spacing, through: visible.maxY, by: spacing) { context.move(to: CGPoint(x: visible.minX, y: y)); context.addLine(to: CGPoint(x: visible.maxX, y: y)) }
            context.strokePath()
        }
        var imageCount = 0
        for element in elements {
            guard !Task.isCancelled, let first = element.points.first else { continue }
            let last = element.points.last ?? first
            let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(first.x - last.x), height: abs(first.y - last.y))
            context.saveGState()
            if element.rotation != 0 { let center = CGPoint(x: element.bounds.midX, y: element.bounds.midY); context.translateBy(x: center.x, y: center.y); context.rotate(by: element.rotation * .pi / 180); context.translateBy(x: -center.x, y: -center.y) }
            let c = element.color
            let components: [CGFloat] = dark && c == .graphite ? [0.91, 0.96, 1, CGFloat(c.a)] : [CGFloat(c.r), CGFloat(c.g), CGFloat(c.b), CGFloat(c.a)]
            let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: components)!
            context.setStrokeColor(color); context.setFillColor(color)
            context.setLineCap(.round); context.setLineJoin(.round)
            context.setLineWidth(max(0.8 / scale, element.kind == .stroke ? element.effectiveBrushSettings.maxWidth * 0.7 : element.width))
            switch element.kind {
            case .stroke, .line, .arrow, .dimension:
                if element.pen == .highlighter { context.setAlpha(0.36); context.setLineWidth(element.effectiveBrushSettings.maxWidth) }
                context.move(to: first.cg)
                for point in element.points.dropFirst() { context.addLine(to: point.cg) }
                context.strokePath()
            case .ellipse: context.addEllipse(in: rect); context.drawPath(using: element.fill ? .fillStroke : .stroke)
            case .rectangle: context.addRect(rect); context.drawPath(using: element.fill ? .fillStroke : .stroke)
            case .triangle:
                context.move(to: CGPoint(x: rect.midX, y: rect.minY)); context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); context.closePath(); context.drawPath(using: element.fill ? .fillStroke : .stroke)
            case .arc: context.addEllipse(in: rect); context.strokePath()
            case .text:
                // CoreText is safe off the main actor and supports Arabic shaping.
                let font = CTFontCreateWithName("Helvetica" as CFString, element.fontSize, nil)
                let text = String(element.text.prefix(300))
                let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
                let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
                let textRect = element.bounds.insetBy(dx: max(element.width / 2, 2), dy: max(element.width / 2, 2))
                let path = CGPath(rect: CGRect(origin: .zero, size: textRect.size), transform: nil)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
                context.translateBy(x: first.x, y: first.y + textRect.height); context.scaleBy(x: 1, y: -1); context.textMatrix = .identity; CTFrameDraw(frame, context)
            case .image:
                if imageCount < 6, let data = element.imageData, data.count <= 16 * 1024 * 1024,
                   let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                   let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                    imageCount += 1; context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1); context.draw(image, in: CGRect(origin: .zero, size: rect.size))
                } else { context.setFillColor(CGColor(gray: dark ? 0.5 : 0.7, alpha: 0.14)); context.fill(rect); context.stroke(rect) }
            case .symbol:
                if element.text.hasPrefix("catalog:"), let definition = SymbolCatalog.definition(id: String(element.text.dropFirst(8))) {
                    DiagramRenderer.draw(definition: definition, in: rect, context: context,
                                         color: NSColor(srgbRed: Double(components[0]), green: Double(components[1]), blue: Double(components[2]), alpha: Double(components[3])))
                } else {
                    // Complex LaTeX remains editable and fully typeset on the board.
                    // This small overview shows bounded source text, not an invented symbol.
                    let source = element.text.hasPrefix("mathlatex:") ? String(element.text.dropFirst(10)) : element.text
                    let font = CTFontCreateWithName("Helvetica" as CFString, min(rect.height * 0.5, 28), nil)
                    let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: source, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]))
                    let path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
                    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
                    context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1); context.textMatrix = .identity; CTFrameDraw(frame, context)
                }
            }
            context.restoreGState()
        }
        return context.makeImage()
    }
}
