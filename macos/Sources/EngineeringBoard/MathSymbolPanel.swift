import SwiftUI
import AppKit

@MainActor
final class SymbolPadState: ObservableObject {
    @Published var strokes: [[CGPoint]] = []
    @Published var revision = 0
    func clear() { strokes = []; revision += 1 }
    func undoStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast(); revision += 1
    }
    func importInk(from session: DrawingSession) {
        let source = session.board.elements.filter { session.selectedIDs.contains($0.id) && $0.kind == .stroke }
            .map { element in
                let center = CGPoint(x: element.bounds.midX, y: element.bounds.midY)
                let angle = element.rotation * .pi / 180
                return element.points.map { sample in
                    let dx = sample.x - center.x, dy = sample.y - center.y
                    return CGPoint(x: center.x + dx * cos(angle) - dy * sin(angle), y: center.y + dx * sin(angle) + dy * cos(angle))
                }
            }
        let points = source.flatMap { $0 }
        guard let first = points.first, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { clear(); return }
        let extent = points.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        let scale = min(392 / max(1, extent.width), 248 / max(1, extent.height))
        strokes = source.map { $0.map { CGPoint(x: 216 + ($0.x - extent.midX) * scale, y: 144 + ($0.y - extent.midY) * scale) } }
        revision += 1
    }
}

struct MathSymbolPanel: View {
    @ObservedObject var session: DrawingSession
    var embedded = false
    var onUseInFormula: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pad = SymbolPadState()
    @State private var query = ""
    @State private var candidates: [MathSymbolCandidate] = []
    @State private var busy = false
    @State private var message = "Draw one symbol, then choose Recognise."
    @State private var recognitionTask: Task<Void, Never>?
    private var hasSelectedInk: Bool { session.board.elements.contains { session.selectedIDs.contains($0.id) && $0.kind == .stroke } }
    private var matches: [MathSymbolDefinition] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if term.isEmpty { return candidates.map(\.definition) }
        return Array(MathSymbolCatalog.all.filter { $0.command.lowercased().contains(term) || ($0.package?.lowercased().contains(term) ?? false) }.prefix(100))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !embedded {
                HStack {
                    Label("DeTeXt maths", systemImage: "function").font(.title2.bold())
                    Spacer()
                    Button("Done") { dismiss() }
                }
            }
            Text("Draw one symbol or use selected ink, then choose a match. Recognition runs on your Mac and keeps your original ink.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    SymbolPad(state: pad, enabled: !busy).frame(width: 432, height: 288)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))
                        .accessibilityLabel("Single maths symbol drawing pad")
                    HStack {
                        Button("Clear") { pad.clear(); candidates = []; message = "Draw one symbol, then choose Recognise." }
                        Button("Undo stroke") { pad.undoStroke() }.disabled(pad.strokes.isEmpty)
                        Button("Use selected ink") { pad.importInk(from: session); candidates = []; message = "Selected ink loaded. Choose Recognise." }.disabled(!hasSelectedInk)
                        Spacer()
                        Button("Recognise") { recognize() }.buttonStyle(.borderedProminent).disabled(pad.strokes.isEmpty)
                    }.disabled(busy)
                    HStack {
                        if busy { ProgressView().controlSize(.small) }
                        Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(minHeight: 38, alignment: .topLeading)
                    Text("One symbol at a time: ∞, ∫, Greek letters or arrows. Assemble a complete expression in the formula editor.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 432)
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search LaTeX commands", text: $query).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Search DeTeXt LaTeX commands")
                    Text(query.isEmpty ? "Suggested matches" : "Command search · up to 100 results").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(matches) { definition in resultRow(definition) }
                            if matches.isEmpty {
                                Text(query.isEmpty ? "Your matches will appear here." : "No matching command.").font(.callout).foregroundStyle(.secondary).padding(.top, 24)
                            }
                        }
                    }
                }.frame(minWidth: 270, maxWidth: .infinity, maxHeight: .infinity)
            }
            if !embedded {
                Link("Public DeTeXt model · Venkat · MIT licence", destination: URL(string: "https://github.com/venkatasg/DeTeXt-Supplementary")!)
                    .font(.caption2)
            }
        }.padding(embedded ? 0 : 20).frame(width: embedded ? nil : 790, height: embedded ? nil : 590)
        .onChange(of: pad.revision) { _, _ in
            if !busy {
                candidates = []
                message = pad.strokes.isEmpty ? "Draw one symbol, then choose Recognise." : "Drawing changed. Choose Recognise for new matches."
            }
        }
        .onAppear { if let error = MathSymbolCatalog.loadingError { message = error } }
        .onDisappear { recognitionTask?.cancel() }
    }
    @ViewBuilder
    private func resultRow(_ definition: MathSymbolDefinition) -> some View {
        let unicode = MathSymbolCatalog.nativeUnicode(for: definition)
        let supported = definition.command.hasPrefix("\\") && MathParser.validationError(for: definition.command) == nil
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center) {
                if let unicode {
                    Text(unicode).font(.system(size: 30, design: .serif)).frame(width: 42, height: 38)
                } else if supported {
                    MathPreview(latex: definition.command).frame(width: 42, height: 38).background(.white, in: RoundedRectangle(cornerRadius: 4))
                }
                Text(definition.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let package = definition.package, !package.isEmpty { Text("Package: " + package).font(.caption2).foregroundStyle(.secondary) }
            HStack {
                Button("Insert") { insert(definition, unicode: unicode) }.disabled(unicode == nil && !supported)
                Button("Copy LaTeX") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(definition.command, forType: .string)
                    message = "Copied " + definition.command
                }
            }.controlSize(.small)
            if let onUseInFormula {
                Button("Send to formula") { onUseInFormula(definition.command) }.controlSize(.small)
                    .help("Add this command to the formula editor")
            }
            if unicode == nil && !supported { Text("Copy this command to a LaTeX editor.").font(.caption2).foregroundStyle(.secondary) }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
    private func recognize() {
        busy = true; query = ""; candidates = []; message = "Finding symbol matches…"
        let strokes = pad.strokes
        recognitionTask?.cancel()
        recognitionTask = Task {
            do {
                let result = try await MathSymbolRecognizer.shared.recognize(strokes: strokes)
                try Task.checkCancellation()
                candidates = result
                message = "\(candidates.count) suggestions. Choose the symbol you meant."
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
            busy = false
        }
    }
    private func insert(_ definition: MathSymbolDefinition, unicode: String?) {
        let zoom = max(0.05, min(16, session.zoom))
        let x = session.cameraOffset.x + 120 / zoom, y = session.cameraOffset.y + 120 / zoom
        if let unicode {
            session.add(DrawingElement(kind: .text, points: [.init(x: x, y: y)], color: session.color, text: unicode, fontSize: 40 / zoom), select: false)
        } else {
            guard definition.command.hasPrefix("\\"), MathParser.validationError(for: definition.command) == nil else { return }
            session.add(DrawingElement(kind: .symbol, points: [.init(x: x, y: y), .init(x: x + 150 / zoom, y: y + 110 / zoom)], color: session.color, text: "mathlatex:" + definition.command), select: false)
        }
        session.status = "Inserted " + definition.command
        message = "Inserted " + definition.command + ". Your ink was preserved."
    }
}

private struct SymbolPad: NSViewRepresentable {
    @ObservedObject var state: SymbolPadState
    var enabled: Bool
    func makeNSView(context: Context) -> SymbolPadView { SymbolPadView(state: state) }
    func updateNSView(_ view: SymbolPadView, context: Context) { view.enabled = enabled; view.needsDisplay = true }
}

@MainActor
private final class SymbolPadView: NSView {
    let state: SymbolPadState
    var enabled = true
    private var drawing = false
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(state: SymbolPadState) { self.state = state; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) {
        guard enabled, state.strokes.count < 500, state.strokes.reduce(0, { $0 + $1.count }) < 100_000 else { return }
        state.strokes.append([point(event)]); drawing = true; state.revision += 1; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard enabled, drawing, let index = state.strokes.indices.last, state.strokes[index].count < 10_000,
              state.strokes.reduce(0, { $0 + $1.count }) < 100_000 else { return }
        state.strokes[index].append(point(event)); state.revision += 1; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { if drawing { mouseDragged(with: event) }; drawing = false }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(bounds.width, max(0, p.x)), y: min(bounds.height, max(0, p.y)))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        let all = state.strokes.flatMap { $0 }
        guard let first = all.first, let context = NSGraphicsContext.current?.cgContext else { return }
        var extent = CGRect(origin: first, size: .zero)
        for p in all { extent = extent.union(CGRect(origin: p, size: .zero)) }
        // Imported board ink is a fitted temporary copy; the saved board is untouched.
        // This fallback also keeps externally supplied pad coordinates visible.
        let inPad = extent.minX >= 0 && extent.minY >= 0 && extent.maxX <= bounds.width && extent.maxY <= bounds.height
        context.saveGState()
        if !inPad {
            let scale = min((bounds.width - 40) / max(1, extent.width), (bounds.height - 40) / max(1, extent.height))
            context.translateBy(x: bounds.midX, y: bounds.midY); context.scaleBy(x: scale, y: scale); context.translateBy(x: -extent.midX, y: -extent.midY)
            context.setLineWidth(3 / scale)
        } else { context.setLineWidth(3) }
        context.setStrokeColor(NSColor.black.cgColor); context.setLineCap(.round); context.setLineJoin(.round)
        for stroke in state.strokes {
            guard let start = stroke.first else { continue }
            context.beginPath(); context.move(to: start)
            if stroke.count == 1 { context.addLine(to: CGPoint(x: start.x + 0.01, y: start.y)) }
            else { for point in stroke.dropFirst() { context.addLine(to: point) } }
            context.strokePath()
        }
        context.restoreGState()
    }
}
