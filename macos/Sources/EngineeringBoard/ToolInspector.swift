import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct ToolInspector: View {
    @ObservedObject var session: DrawingSession
    @Binding var showRecognition: Bool
    @Binding var showCalculator: Bool
    @State private var showGraph = false
    @State private var showMath = false
    @State private var showMathSymbols = false
    @State private var section = "Pen"
    @State private var component = "Resistor"
    @State private var text = ""
    @State private var showWritingTools = false
    init(session: DrawingSession, showRecognition: Binding<Bool>, showCalculator: Binding<Bool>, initialSection: String = "Pen") {
        self.session = session
        _showRecognition = showRecognition
        _showCalculator = showCalculator
        _section = State(initialValue: ["Pen", "Paper", "Engineering"].contains(initialSection) ? initialSection : "Pen")
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section == "Pen" ? "Pen studio" : section == "Paper" ? "Paper & scale" : "Precision tools")
                    .font(.system(size: 16, weight: .semibold))
                Text(section == "Pen" ? "Make every stroke your own." : section == "Paper" ? "Choose a surface for your work." : "Draw, measure and solve.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 17).padding(.bottom, 13)
            Picker("Tool settings", selection: $section) {
                Text("Pen").tag("Pen"); Text("Paper").tag("Paper"); Text("Precision").tag("Engineering")
            }.labelsHidden().pickerStyle(.segmented).padding(.horizontal, 15).padding(.bottom, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if section == "Pen" { inkSettings }
                    else if section == "Paper" { paperSettings }
                    else { engineeringSettings }
                    if !session.selectedIDs.isEmpty { selectionSettings }
                }.font(.system(size: 12)).padding(.horizontal, 17).padding(.bottom, 22)
            }
        }
        .sheet(isPresented: $showGraph) { GraphPlotView(session: session).frame(width: 530, height: 440) }
        .sheet(isPresented: $showMath) { MathEditor(session: session) }
        .sheet(isPresented: $showMathSymbols) { MathSymbolPanel(session: session) }
    }
    private var inkSettings: some View {
        VStack(alignment: .leading, spacing: 15) {
            BrushControls(session: session)
            VStack(alignment: .leading, spacing: 10) {
                heading("DRAWING ASSIST", "scribble")
                Toggle("Hold to straighten", isOn: $session.autoShape)
                Text("Pause for half a second at the end of a stroke to make a clean shape.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack { Text("Smoothing"); Spacer(); Text("\(Int(session.smoothing / 0.85 * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                    .font(.system(size: 11))
                Slider(value: $session.smoothing, in: 0...0.85).accessibilityLabel("Ink smoothing")
            }.inspectorCard()
            DisclosureGroup("Handwriting tools", isExpanded: $showWritingTools) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Button("Smooth ink") { Handwriting.smoothSelection(session: session) }
                            .disabled(!session.board.elements.contains { session.selectedIDs.contains($0.id) && $0.kind == .stroke })
                        Button("Read writing") { showRecognition = true }
                    }.buttonStyle(.bordered).controlSize(.small)
                    Text("Lasso the handwriting you want to improve. Review recognised text before inserting it.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.font(.system(size: 11, weight: .medium))
        }
    }
    private var paperSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("CHOOSE YOUR PAPER", "square.grid.3x3")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(BackgroundKind.allCases, id: \.self) { kind in
                    Button {
                        session.finishActiveInput?(); session.checkpoint(); session.board.background = kind; session.changed()
                    } label: {
                        VStack(spacing: 8) {
                            PaperSample(kind: kind).frame(height: 43)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text(kind.rawValue).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }.padding(8).frame(maxWidth: .infinity)
                            .background(session.board.background == kind ? Color.teal.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(session.board.background == kind ? .teal.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel(kind.rawValue + " background").accessibilityValue(session.board.background == kind ? "Selected" : "")
                }
            }
            HStack { Text("Grid spacing"); Spacer(); Text(BoardRenderer.formatted(session.board.gridSpacing) + " pt").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $session.board.gridSpacing, in: 10...80, step: 5).onChange(of: session.board.gridSpacing) { _, _ in session.changed() }
            Toggle("Snap to grid", isOn: $session.snap)
            Divider()
            heading("DRAWING SCALE", "ruler")
            Picker("Scale", selection: $session.board.scaleDenominator) {
                ForEach([1.0, 2, 5, 10, 20, 50, 100], id: \.self) { Text("1:\(Int($0))").tag($0) }
            }.onChange(of: session.board.scaleDenominator) { _, _ in session.changed() }
            HStack {
                Text("Points per mm")
                TextField("4", value: $session.board.pointsPerMM, format: .number).frame(width: 76)
                    .onSubmit { session.board.pointsPerMM = session.board.pointsPerMM.isFinite ? min(1_000_000, max(0.01, session.board.pointsPerMM)) : 4; session.changed() }
            }
            Text("Zoom changes your view. Scale sets real dimensions in mm; print exported PDFs at 100%.").font(.caption).foregroundStyle(.secondary)
            Menu("Export paper size") {
                Button("Landscape · 1800 × 1200") { resize(1800, 1200) }
                Button("Portrait · 1200 × 1800") { resize(1200, 1800) }
                Button("Large · 2800 × 1800") { resize(2800, 1800) }
            }
            TextField("Folder", text: $session.board.folder).textFieldStyle(.roundedBorder).onChange(of: session.board.folder) { _, _ in session.changed() }
        }
    }
    private var engineeringSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 11) {
                heading("GUIDES & LINES", "ruler")
                Toggle("Ruler guide", isOn: $session.showRuler)
                Toggle("Protractor guide", isOn: $session.showProtractor)
                Picker("Line style", selection: $session.dash) {
                    Text("Solid").tag("Solid"); Text("Hidden").tag("Hidden"); Text("Centre").tag("Centre")
                }
                Toggle("Fill shapes", isOn: $session.fillShapes)
                HStack(spacing: 6) {
                    Text("Line length")
                    Spacer()
                    TextField("0", value: $session.fixedLineLengthMM, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 63)
                        .onSubmit { session.fixedLineLengthMM = session.fixedLineLengthMM.isFinite ? min(1_000_000, max(0, session.fixedLineLengthMM)) : 0 }
                        .accessibilityLabel("Fixed line length in millimetres")
                    Text("mm").foregroundStyle(.secondary)
                }
                Toggle("Keep length labels", isOn: $session.keepLineLengthLabels)
                Text("Use 0 for free length. Isometric paper with snapping locks directions to 30° steps.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.controlSize(.small).inspectorCard()
            VStack(alignment: .leading, spacing: 10) {
                heading("MATHS & STUDY", "function")
                HStack(spacing: 8) {
                    Button { showCalculator = true } label: { Label("Calculate", systemImage: "plus.forwardslash.minus").frame(maxWidth: .infinity) }
                    Button { showGraph = true } label: { Label("Plot", systemImage: "chart.xyaxis.line").frame(maxWidth: .infinity) }
                }
                Button { showMath = true } label: { Label("Maths notation / LaTeX", systemImage: "textformat").frame(maxWidth: .infinity, alignment: .leading) }
                Button { showMathSymbols = true } label: { Label("Draw a maths symbol", systemImage: "scribble").frame(maxWidth: .infinity, alignment: .leading) }
            }.buttonStyle(.bordered).controlSize(.small).inspectorCard()
            VStack(alignment: .leading, spacing: 10) {
                heading("QUICK INSERT", "plus.square")
                Picker("Circuit", selection: $component) {
                    ForEach(["Resistor", "Capacitor", "Inductor", "Diode", "Ground", "Voltage source", "Switch"], id: \.self) { Text($0).tag($0) }
                }
                Button("Insert circuit symbol") { insertSymbol() }.buttonStyle(.bordered)
                HStack(spacing: 6) {
                    TextField("Text or equation", text: $text).textFieldStyle(.roundedBorder)
                        .onSubmit { if !text.isEmpty { insertText() } }
                    Button { insertText() } label: { Image(systemName: "plus") }
                        .disabled(text.isEmpty).accessibilityLabel("Insert text")
                }
                Button { importImage() } label: { Label("Image or PDF page…", systemImage: "photo").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.bordered)
            }.controlSize(.small).inspectorCard()
        }
    }
    private var selectionSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("SELECTED · \(session.selectedIDs.count)", "cursorarrow")
            HStack { Button("Duplicate") { session.duplicateSelection() }; Button("Delete") { session.deleteSelection() } }.buttonStyle(.bordered)
            HStack { Button("To front") { session.moveLayer(forward: true) }; Button("To back") { session.moveLayer(forward: false) } }.buttonStyle(.bordered)
            HStack { Button("Rotate 90°") { rotateSelection() }; Button("Lock / unlock") { lockSelection() } }.buttonStyle(.bordered)
        }.controlSize(.small).inspectorCard()
    }
    private func backgroundIcon(_ kind: BackgroundKind) -> String {
        switch kind {
        case .plain: return "square"
        case .lined: return "line.3.horizontal"
        case .grid, .graph: return "square.grid.3x3"
        case .dots: return "circle.grid.3x3"
        case .engineering: return "ruler"
        case .blueprint: return "square.dashed"
        case .isometric: return "cube.transparent"
        case .polar: return "scope"
        case .dark: return "moon.stars"
        }
    }
    func heading(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
    }
    func resize(_ width: Double, _ height: Double) { session.finishActiveInput?(); session.checkpoint(); session.board.width = width; session.board.height = height; session.changed() }
    func insertText() {
        session.add(DrawingElement(kind: .text, points: [.init(x: session.cameraOffset.x + 140, y: session.cameraOffset.y + 150)], color: session.color, text: text, fontSize: 24)); text = ""; session.tool = .select
    }
    func insertSymbol() {
        let offset = Double(session.board.elements.count % 8) * 30
        session.add(DrawingElement(kind: .symbol, points: [.init(x: session.cameraOffset.x + 250 + offset, y: session.cameraOffset.y + 300 + offset), .init(x: session.cameraOffset.x + 410 + offset, y: session.cameraOffset.y + 380 + offset)], color: session.color, width: session.lineWidth, text: component)); session.tool = .select
    }
    func lockSelection() {
        session.checkpoint()
        for i in session.board.elements.indices where session.selectedIDs.contains(session.board.elements[i].id) { session.board.elements[i].locked.toggle() }
        session.changed()
    }
    func rotateSelection() {
        session.checkpoint()
        for i in session.board.elements.indices where session.selectedIDs.contains(session.board.elements[i].id) && !session.board.elements[i].locked {
            session.board.elements[i].rotation += 90
        }
        session.changed()
    }
    func importImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image, .pdf]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let image: NSImage?
        if url.pathExtension.lowercased() == "pdf" { image = PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 1600, height: 1600), for: .mediaBox) }
        else { image = NSImage(contentsOf: url) }
        guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { session.error = "This image could not be opened."; return }
        let factor = min(1, 800 / max(image.size.width, image.size.height))
        let x = session.cameraOffset.x + 100, y = session.cameraOffset.y + 100
        session.add(DrawingElement(kind: .image, points: [.init(x: x, y: y), .init(x: x + image.size.width * factor, y: y + image.size.height * factor)], imageData: png)); session.tool = .select
    }
}

/// A real sample from the saved-board renderer, redrawn only when paper changes.
private struct PaperSample: NSViewRepresentable {
    var kind: BackgroundKind
    func makeNSView(context: Context) -> PaperSampleView { PaperSampleView() }
    func updateNSView(_ view: PaperSampleView, context: Context) {
        if view.kind != kind { view.kind = kind; view.needsDisplay = true }
    }
}
private final class PaperSampleView: NSView {
    var kind: BackgroundKind = .plain
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 0, bounds.height > 0 else { return }
        context.saveGState()
        context.scaleBy(x: bounds.width / 400, y: bounds.height / 160)
        var paper = Board(background: kind, width: 400, height: 160)
        paper.title = ""; paper.gridSpacing = 48
        BoardRenderer.draw(board: paper)
        context.restoreGState()
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Make it your drawing space").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Draw with a mouse, trackpad or a macOS tablet driver. Choose a shape and drag to draw it. Hold Shift to constrain a shape. Select objects to move them; drag a corner to resize.")
            Grid(alignment: .leading, horizontalSpacing: 35, verticalSpacing: 12) {
                row("B / E / V", "Draw / erase / select")
                row("L / R / O / T", "Line / rectangle / circle / text")
                row("⌘Z / ⇧⌘Z", "Undo / redo")
                row("⌘D / Delete", "Duplicate / delete selection")
                row("⌘[ / ⌘]", "Send to back / bring to front")
                row("⌘N / ⌘S", "New drawing / save")
                row("⇧⌘H", "Return to drawing library")
            }.padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Text("Map Quick Keys to these shortcuts in the Xencelabs driver. The Tablet menu adds zoom, brush-size and pen-cycle shortcuts. Tablet settings includes separate pen responses and a live test area. Driver tilt widens pencil shading; fountain strokes use pressure and speed.").font(.callout)
            Text("Your boards are stored locally. Export PDF for printing or PNG/JPEG for Craft and Notion. “Notes & web” opens those services beside the canvas; it doesn't embed Microsoft Whiteboard inside the official Notion app.").font(.callout).foregroundStyle(.secondary)
            Spacer()
        }.padding(25)
    }
    func row(_ key: String, _ description: String) -> some View { GridRow { Text(key).font(.system(.body, design: .monospaced)); Text(description) } }
}
