import SwiftUI
import AppKit

struct DrawingWorkspace: View {
    @ObservedObject var session: DrawingSession
    @ObservedObject var store: BoardStore
    @ObservedObject var workspace: Workspace
    @ObservedObject var appearance: AppAppearance
    @State private var showWritingReview = false
    @State private var showRecognition = false
    @State private var showCalculator = false
    @State private var showHelp = false
    @State private var showTablet = false
    @StateObject private var quickKeys = QuickKeysBridge()
    @StateObject private var handwriting = AutoHandwritingCoordinator()
    @AppStorage("engineeringboard.handwriting.autoReview") private var automaticHandwriting = true
    private let shapes: [DrawTool] = [.line, .arrow, .rectangle, .ellipse, .triangle, .arc, .dimension]

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        BoardCanvas(session: session)
                        drawingToolbar.padding(.top, 12).padding(.horizontal, 16)
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(alignment: .bottomLeading) {
                        if handwriting.hasPreview {
                            Button { showWritingReview = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "text.badge.checkmark").foregroundStyle(.teal)
                                    Text(handwriting.suggestions.isEmpty ? "Review handwriting" : "Review handwriting · \(handwriting.suggestions.count) spelling suggestions")
                                        .font(.system(size: 11, weight: .medium))
                                }.padding(.horizontal, 13).padding(.vertical, 10).glassPanel(radius: 12)
                            }.buttonStyle(.plain).padding(16)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if session.pendingDimensionID != nil {
                            DimensionPopover(session: session).padding(.top, 116).padding(.trailing, 20).id(session.pendingDimensionID)
                        }
                    }
                    statusBar
                }
                if workspace.showServices || workspace.showInspector {
                    Divider().opacity(0.35)
                    sidePanel
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showWritingReview) { AIHandwritingReview(session: session, initialText: handwriting.hasPreview ? handwriting.previewText : nil) }
        .sheet(isPresented: $showRecognition) { HandwritingPreview(session: session).frame(minWidth: 520, minHeight: 370) }
        .sheet(isPresented: $showCalculator) { EngineeringCalculator(session: session).frame(width: 520, height: 470) }
        .sheet(isPresented: $workspace.showDeTeXt) { DeTeXtWorkbench(session: session) }
        .sheet(isPresented: $workspace.showSketch3D) { Sketch3DPanel(session: session) }
        .sheet(isPresented: $showHelp) { HelpView().frame(width: 580, height: 550) }
        .sheet(isPresented: $showTablet) { TabletSettingsPanel(session: session, quickKeys: quickKeys) }
        .onAppear {
            if session.cameraOffset == .zero { session.cameraOffset = CGPoint(x: -24 / session.zoom, y: -76 / session.zoom) }
            let drawing = session
            quickKeys.onAction = { [weak drawing] action in drawing?.performTabletAction(action) }
            quickKeys.setMode(session.tabletWorkspaceMode)
            handwriting.schedule(session: session, isInputActive: { session.isInputActive })
        }
        .onChange(of: session.tabletWorkspaceMode) { _, mode in quickKeys.setMode(mode) }
        .onChange(of: session.revision) { _, _ in
            handwriting.schedule(session: session, isInputActive: { session.isInputActive })
        }
        .onChange(of: automaticHandwriting) { _, enabled in
            if enabled { handwriting.schedule(session: session, isInputActive: { session.isInputActive }) }
            else { handwriting.stop() }
        }
        .onDisappear { quickKeys.stop(); handwriting.stop() }
        .alert("Drawing", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK") { session.error = nil }
        } message: { Text(session.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { workspace.home() } label: { Image(systemName: "square.grid.2x2") }
                .buttonStyle(GlassToolbarButtonStyle(size: 32)).help("Drawing library · ⇧⌘H").accessibilityLabel("Drawing library")
            VStack(alignment: .leading, spacing: 3) {
                TextField("Untitled drawing", text: $session.board.title)
                    .textFieldStyle(.plain).font(.system(size: 14, weight: .semibold))
                    .onSubmit { session.changed() }
                    .onChange(of: session.board.title) { _, _ in session.changed() }
                    .accessibilityLabel("Drawing name")
                Text("SketchGlide")
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(minWidth: 120, maxWidth: 240, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                panelButton("Symbols", icon: "square.grid.2x2", tab: "Symbols")
                panelButton("AI", icon: "sparkles", tab: "AI")
                Button { workspace.launchDeTeXt(store: store) } label: { Image(systemName: "function") }
                    .buttonStyle(GlassToolbarButtonStyle(size: 30)).help("DeTeXt · handwritten maths and editable formulas").accessibilityLabel("DeTeXt maths workspace")
                Button { workspace.launchSketch3D(store: store) } label: { Image(systemName: "cube.transparent") }
                    .buttonStyle(GlassToolbarButtonStyle(size: 30)).help("3D sketchbook").accessibilityLabel("3D sketchbook")
                Button {
                    workspace.showServices.toggle()
                    if workspace.showServices { workspace.showInspector = false }
                } label: { Image(systemName: "note.text") }
                    .buttonStyle(GlassToolbarButtonStyle(isSelected: workspace.showServices, size: 30))
                    .help("Notes and web pages").accessibilityLabel("Notes and web pages")
            }
            Divider().frame(height: 21).padding(.horizontal, 2)
            ThemeToggle(appearance: appearance)
            utilityMenu
            exportMenu
            Button {
                if workspace.showServices { workspace.showServices = false }
                else { workspace.showInspector.toggle() }
            } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(GlassToolbarButtonStyle(isSelected: workspace.showInspector || workspace.showServices, size: 30))
                .help("Show or hide the side panel").accessibilityLabel("Toggle side panel")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassChrome(material: .headerView)
        .overlay(alignment: .bottom) { Rectangle().fill(ChromePalette.border).frame(height: 0.5) }
    }

    private var utilityMenu: some View {
        Menu {
            Button("Focus canvas", systemImage: "arrow.up.left.and.arrow.down.right") {
                workspace.showLibrary = false; workspace.showInspector = false; workspace.showServices = false
            }
            Button("Tablet and pressure settings…", systemImage: "pencil.tip.crop.circle") { showTablet = true }
            Divider()
            Button("Improve handwriting and spelling…", systemImage: "text.badge.checkmark") { showWritingReview = true }
            Toggle("Read handwriting after a pause", isOn: $automaticHandwriting)
            Button("DeTeXt Maths…", systemImage: "function") { workspace.launchDeTeXt(store: store) }
            Button("3D Sketchbook…", systemImage: "cube.transparent") { workspace.launchSketch3D(store: store) }
            Button("Calculator…", systemImage: "plus.forwardslash.minus") { showCalculator = true }
            Divider()
            Button("Help and keyboard shortcuts…", systemImage: "questionmark.circle") { showHelp = true }
        } label: { Image(systemName: "ellipsis").frame(width: 26, height: 30) }
            .menuStyle(.borderlessButton).fixedSize().help("Study tools, tablet settings and help").accessibilityLabel("More drawing commands")
    }

    private var exportMenu: some View {
        Menu {
            ForEach(ExportFormat.allCases, id: \.self) { format in
                Button(format.rawValue.uppercased()) {
                    session.finishActiveInput?()
                    do { try BoardExport.export(board: session.board, format: format) }
                    catch { session.error = error.localizedDescription }
                }
            }
            Divider()
            Button("Editable drawing…") { session.finishActiveInput?(); store.exportProject(session.board) }
            Button("Craft / Excalidraw drawing…") {
                session.finishActiveInput?()
                do { try CraftExchange.export(board: session.board) }
                catch { session.error = error.localizedDescription }
            }
            Button("Notion interactive HTML copy…") {
                session.finishActiveInput?()
                do { try NotionHTMLExport.export(board: session.board) }
                catch { session.error = error.localizedDescription }
            }
            Button("Copy link to this board") {
                session.finishActiveInput?()
                if BoardLinks.copy(for: session.board) { session.status = "Board link copied · opens the latest local drawing" }
            }
        } label: { Label("Export", systemImage: "square.and.arrow.up").font(.system(size: 11, weight: .medium)) }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 10).frame(height: 30)
            .background(Color.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .help("Export an image, PDF or editable drawing")
    }

    private func panelButton(_ name: String, icon: String, tab: String) -> some View {
        Button {
            if workspace.showInspector && workspace.inspectorTab == tab { workspace.showInspector = false }
            else { workspace.inspectorTab = tab; workspace.showInspector = true; workspace.showServices = false }
        } label: { Label(name, systemImage: icon) }
            .buttonStyle(GlassCommandButtonStyle(isSelected: workspace.showInspector && workspace.inspectorTab == tab))
            .fixedSize()
    }

    private var drawingToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                primaryTools
                toolbarDivider
                penMenu
                widthMenu
                settingsButton
                toolbarDivider
                historyTools
            }.padding(6).glassPanel(radius: 17, interactive: true).fixedSize(horizontal: true, vertical: true)
            VStack(spacing: 3) {
                HStack(spacing: 3) { primaryTools }
                HStack(spacing: 3) { penMenu; widthMenu; settingsButton; toolbarDivider; historyTools }
            }.padding(6).glassPanel(radius: 17, interactive: true).fixedSize(horizontal: true, vertical: true)
        }
    }

    private var primaryTools: some View {
        Group {
            ForEach([DrawTool.ink, .eraser, .select, .lasso]) { tool in toolButton(tool) }
            toolbarDivider
            Menu {
                ForEach(shapes) { tool in
                    Button { session.tool = tool } label: { Label(tool.rawValue, systemImage: tool.symbol) }
                }
            } label: {
                Image(systemName: shapes.contains(session.tool) ? session.tool.symbol : "line.diagonal")
                    .font(.system(size: 16)).frame(width: 30, height: 34)
                    .foregroundStyle(shapes.contains(session.tool) ? .teal : .primary)
                    .background(shapes.contains(session.tool) ? Color.teal.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }.menuStyle(.borderlessButton).frame(width: 36)
                .help("Lines, shapes and dimensions").accessibilityLabel("Lines, shapes and dimensions")
            toolButton(.text)
        }
    }

    private var penMenu: some View {
        Menu {
            ForEach(PenKind.allCases) { pen in
                Button { session.pen = pen; session.tool = .ink } label: {
                    Label(pen.name + (session.pen == pen ? " ✓" : ""), systemImage: pen.symbol)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(session.color.swift).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                Text(session.pen == .technical ? "Fineliner" : session.pen.rawValue)
                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
        }.menuStyle(.borderlessButton).frame(width: 103).help("Choose one of ten pens").accessibilityLabel("Current pen: " + session.pen.name)
    }

    private var widthMenu: some View {
        Menu {
            ForEach([1.0, 2, 3, 5, 8, 12, 24, 40], id: \.self) { width in
                Button("\(BoardRenderer.formatted(width)) pt") {
                    var settings = session.brushSettings
                    settings.maxWidth = width; settings.minWidth = min(settings.minWidth, width)
                    if session.pen == .technical { settings.minWidth = width }
                    session.brushSettings = settings
                }
            }
        } label: { Text("\(BoardRenderer.formatted(session.brushSettings.maxWidth)) pt").font(.system(size: 10)).monospacedDigit() }
            .menuStyle(.borderlessButton).frame(width: 64).help("Quick brush width").accessibilityLabel("Brush width")
    }

    private var settingsButton: some View {
        Button {
            workspace.showServices = false; workspace.showInspector = true; workspace.inspectorTab = "Tools"
        } label: { Image(systemName: "slider.horizontal.3") }
            .buttonStyle(GlassToolbarButtonStyle(isSelected: workspace.showInspector && workspace.inspectorTab == "Tools"))
            .help("Colour, pressure and drawing tools").accessibilityLabel("Pen and drawing settings")
    }

    private var historyTools: some View {
        Group {
            Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(GlassToolbarButtonStyle()).disabled(!session.canUndo).help("Undo · ⌘Z").accessibilityLabel("Undo")
            Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(GlassToolbarButtonStyle()).disabled(!session.canRedo).help("Redo · ⇧⌘Z").accessibilityLabel("Redo")
        }
    }

    private func toolButton(_ tool: DrawTool) -> some View {
        Button { session.tool = tool } label: { Image(systemName: tool.symbol).font(.system(size: 16)) }
            .buttonStyle(GlassToolbarButtonStyle(isSelected: session.tool == tool))
            .help(tool.rawValue).accessibilityLabel(tool.rawValue)
    }
    private var toolbarDivider: some View { Divider().frame(height: 23).padding(.horizontal, 4) }

    private var sidePanel: some View {
        VStack(spacing: 0) {
            if workspace.showServices {
                HStack { Label("Notes & web", systemImage: "note.text").font(.system(size: 12, weight: .semibold)); Spacer(); closePanel }
                    .padding(.horizontal, 16).padding(.top, 14)
                ServicesPanel(session: session)
            } else {
                HStack {
                    Picker("Panel", selection: $workspace.inspectorTab) {
                        Text("Tools").tag("Tools"); Text("Symbols").tag("Symbols"); Text("AI").tag("AI")
                    }.labelsHidden().pickerStyle(.segmented)
                    closePanel
                }.padding(.horizontal, 13).padding(.vertical, 12)
                if workspace.inspectorTab == "AI" { AssistantPanel(session: session, conversation: workspace.conversation) }
                else if workspace.inspectorTab == "Symbols" { SymbolLibrary(session: session) }
                else { ToolInspector(session: session, showRecognition: $showRecognition, showCalculator: $showCalculator) }
            }
        }.frame(width: workspace.showServices ? 340 : (workspace.inspectorTab == "Tools" ? 300 : (workspace.inspectorTab == "AI" ? 360 : 330)))
            .glassChrome(material: .sidebar)
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.12)).frame(width: 0.5).allowsHitTesting(false) }
    }
    private var closePanel: some View {
        Button { workspace.showInspector = false; workspace.showServices = false } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Close side panel").accessibilityLabel("Close side panel")
    }
    private var statusBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "internaldrive").font(.system(size: 10))
            Text(handwriting.isReading ? "Reading handwriting on this Mac…" : session.status).lineLimit(1)
            Spacer(minLength: 4)
            if session.tabletDetected { Text("Pressure \(Int(session.livePressure * 100))%").foregroundStyle(.teal).monospacedDigit() }
            Menu {
                ForEach(TabletWorkspaceMode.allCases) { mode in Button(mode.rawValue) { session.tabletWorkspaceMode = mode } }
            } label: { Text(session.tabletWorkspaceMode.rawValue) }.menuStyle(.borderlessButton).frame(width: 70)
                .help("Quick Keys workspace mode")
            Text("1:\(BoardRenderer.formatted(session.board.scaleDenominator))").help("Drawing scale")
            Divider().frame(height: 12)
            Button { session.zoom = max(0.05, session.zoom / 1.2) } label: { Image(systemName: "minus") }.accessibilityLabel("Zoom out")
            Menu {
                ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { zoom in Button("\(Int(zoom * 100))%") { session.zoom = zoom } }
            } label: { Text("\(Int(session.zoom * 100))%").monospacedDigit() }.menuStyle(.borderlessButton).frame(width: 44)
            Button { session.zoom = min(16, session.zoom * 1.2) } label: { Image(systemName: "plus") }.accessibilityLabel("Zoom in")
        }.buttonStyle(.borderless).font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8).glassChrome(material: .headerView)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5) }
    }
}
