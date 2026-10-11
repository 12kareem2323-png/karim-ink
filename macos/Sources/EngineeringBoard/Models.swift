import SwiftUI
import AppKit

struct InkPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var pressure: Double = 1
    var tiltX: Double = 0
    var tiltY: Double = 0
    var velocity: Double? = nil
    var rawPressure: Double? = nil
    var inputDeviceKey: String? = nil
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

struct InkColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var swift: Color { Color(nsColor: ns) }
    static let graphite = InkColor(r: 0.14, g: 0.20, b: 0.28)
    static let blue = InkColor(r: 0.16, g: 0.39, b: 0.85)
    static let teal = InkColor(r: 0.06, g: 0.55, b: 0.49)
    static let red = InkColor(r: 0.83, g: 0.23, b: 0.26)
    static let amber = InkColor(r: 0.94, g: 0.65, b: 0.14)
    static let violet = InkColor(r: 0.49, g: 0.30, b: 0.75)
    static let palette: [InkColor] = [.graphite, .blue, .teal, .red, .amber, .violet]
}

enum PenKind: String, Codable, CaseIterable, Identifiable {
    case technical = "Technical Fineliner", fountain = "Fountain", pencil = "Pencil", chalk = "Chalk"
    case marker = "Marker", calligraphy = "Calligraphy", airbrush = "Airbrush", liquid = "Liquid Ink"
    case highlighter = "Highlighter", dryErase = "Dry Erase"
    static var pen: PenKind { .technical }
    var id: String { rawValue }
    var renderID: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    var name: String {
        switch self {
        case .fountain: return "Fountain pen"
        case .pencil: return "Graphite pencil"
        case .marker: return "Alcohol marker"
        case .liquid: return "Liquid ink"
        case .dryErase: return "Dry erase marker"
        default: return rawValue
        }
    }
    var symbol: String {
        switch self {
        case .technical: return "pencil.tip"
        case .fountain, .liquid: return "drop.fill"
        case .pencil: return "pencil"
        case .chalk: return "scribble.variable"
        case .marker, .dryErase: return "paintbrush.pointed.fill"
        case .calligraphy: return "textformat"
        case .airbrush: return "aqi.medium"
        case .highlighter: return "highlighter"
        }
    }
    var detail: String {
        switch self {
        case .technical: return "Clean, steady technical lines"
        case .fountain: return "Pressure and direction change the nib"
        case .pencil: return "Grain and tilt shading, with pencil grades"
        case .chalk: return "Broken, dusty texture"
        case .marker: return "Translucent colour, with darker overlap"
        case .calligraphy: return "Broad nib at a fixed angle"
        case .airbrush: return "Soft, layered spray"
        case .liquid: return "Flowing ink with tapered pressure"
        case .highlighter: return "Broad, translucent highlight"
        case .dryErase: return "Waxy streaks and slight edge gaps"
        }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        if name == "Pen" { self = .technical; return }
        guard let pen = Self(rawValue: name) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown pen style: \(name)")
        }
        self = pen
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(rawValue)
    }
}

enum PencilGrade: String, CaseIterable, Codable {
    case hard2 = "2H", hard = "H", normal = "HB", soft2 = "2B", soft4 = "4B", soft6 = "6B"
    var darkness: Double {
        switch self { case .hard2: return 0.48; case .hard: return 0.64; case .normal: return 0.78; case .soft2: return 0.87; case .soft4: return 0.96; case .soft6: return 1 }
    }
    var softness: Double {
        switch self { case .hard2: return 0.2; case .hard: return 0.35; case .normal: return 0.5; case .soft2: return 0.7; case .soft4: return 0.85; case .soft6: return 1 }
    }
}

struct BrushSettings: Codable, Equatable {
    var minWidth: Double = 1
    var maxWidth: Double = 4
    var opacity: Double = 1
    var minOpacity: Double = 0.35
    var maxOpacity: Double = 1
    var pressureGamma: Double = 1
    var pressureEnabled: Bool = true
    var textureScale: Double = 1
    var pencilGrade: PencilGrade = .normal
    func width(pressure: Double) -> Double {
        let p = pressureEnabled ? max(0, min(1, pressure.isFinite ? pressure : 1)) : 1
        return max(0.15, minWidth + (max(maxWidth, minWidth) - minWidth) * pow(p, max(0.15, min(4, pressureGamma))))
    }
    func alpha(pressure: Double) -> Double {
        let p = pressureEnabled ? max(0, min(1, pressure.isFinite ? pressure : 1)) : 1
        let response = pow(p, max(0.15, min(4, pressureGamma)))
        return max(0, min(1, opacity * (minOpacity + (maxOpacity - minOpacity) * response)))
    }
    static func defaults(for pen: PenKind) -> BrushSettings {
        switch pen {
        case .technical: return .init(minWidth: 1.2, maxWidth: 1.2, pressureEnabled: false, textureScale: 0.3)
        case .fountain: return .init(minWidth: 0.8, maxWidth: 6, opacity: 0.97, pressureGamma: 0.7, textureScale: 0.4)
        case .pencil: return .init(minWidth: 1, maxWidth: 5, opacity: 0.78, pressureGamma: 1.3)
        case .chalk: return .init(minWidth: 4, maxWidth: 12, opacity: 0.88, pressureGamma: 0.9, textureScale: 1.6)
        case .marker: return .init(minWidth: 6, maxWidth: 14, opacity: 0.42, pressureGamma: 0.7, textureScale: 0.6)
        case .calligraphy: return .init(minWidth: 1.5, maxWidth: 16, opacity: 0.95, pressureGamma: 0.85, textureScale: 0.5)
        case .airbrush: return .init(minWidth: 8, maxWidth: 36, opacity: 0.22, textureScale: 1)
        case .liquid: return .init(minWidth: 0.8, maxWidth: 8, pressureGamma: 0.55, textureScale: 0.25)
        case .highlighter: return .init(minWidth: 10, maxWidth: 24, opacity: 0.27, pressureEnabled: false, textureScale: 0.3)
        case .dryErase: return .init(minWidth: 3, maxWidth: 9, opacity: 0.88, pressureGamma: 0.8, textureScale: 0.9)
        }
    }
}

extension BrushSettings {
    enum CodingKeys: String, CodingKey {
        case minWidth, maxWidth, opacity, minOpacity, maxOpacity, pressureGamma, pressureEnabled, textureScale, pencilGrade
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minWidth = try c.decodeIfPresent(Double.self, forKey: .minWidth) ?? minWidth
        maxWidth = try c.decodeIfPresent(Double.self, forKey: .maxWidth) ?? maxWidth
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? opacity
        minOpacity = try c.decodeIfPresent(Double.self, forKey: .minOpacity) ?? minOpacity
        maxOpacity = try c.decodeIfPresent(Double.self, forKey: .maxOpacity) ?? maxOpacity
        pressureGamma = try c.decodeIfPresent(Double.self, forKey: .pressureGamma) ?? pressureGamma
        pressureEnabled = try c.decodeIfPresent(Bool.self, forKey: .pressureEnabled) ?? pressureEnabled
        textureScale = try c.decodeIfPresent(Double.self, forKey: .textureScale) ?? textureScale
        pencilGrade = try c.decodeIfPresent(PencilGrade.self, forKey: .pencilGrade) ?? pencilGrade
    }
}

enum BrushMetrics {
    static func width(element: DrawingElement, point: InkPoint, tangent: CGPoint = .zero) -> Double {
        let settings = element.effectiveBrushSettings
        if element.pen == .technical { return max(0.15, settings.maxWidth) }
        var width = settings.width(pressure: point.pressure)
        let velocity = max(0, point.velocity ?? 0)
        switch element.pen {
        case .pencil: width *= 1 + min(1, hypot(point.tiltX, point.tiltY)) * 1.7
        case .calligraphy:
            let length = hypot(tangent.x, tangent.y)
            if length > 0.001 { width *= 0.18 + 0.82 * abs((tangent.x - tangent.y) / (length * sqrt(2))) }
        case .fountain: width *= max(0.45, 1 - velocity / 2400)
        case .liquid: width *= max(0.6, 1 - velocity / 3000)
        default: break
        }
        return max(0.15, width)
    }
    static func opacity(element: DrawingElement, point: InkPoint) -> Double {
        let settings = element.effectiveBrushSettings
        return element.pen == .technical ? settings.opacity * settings.maxOpacity : settings.alpha(pressure: point.pressure)
    }
}

enum BackgroundKind: String, Codable, CaseIterable {
    case plain = "Plain", lined = "Lined", grid = "Square grid", dots = "Dot grid", graph = "Graph paper", engineering = "Engineering sheet", blueprint = "Blueprint", isometric = "Isometric", polar = "Polar grid", dark = "Dark board"
}

enum DrawTool: String, CaseIterable, Identifiable {
    case select = "Select", lasso = "Lasso", ink = "Draw", eraser = "Eraser", line = "Line", arrow = "Arrow", rectangle = "Rectangle", ellipse = "Circle", triangle = "Triangle", arc = "Arc", dimension = "Dimension", text = "Text"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .lasso: return "lasso"
        case .ink: return "pencil.tip"
        case .eraser: return "eraser"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .triangle: return "triangle"
        case .arc: return "circle.lefthalf.filled"
        case .dimension: return "arrow.left.and.right"
        case .text: return "textformat"
        }
    }
}

struct DrawingElement: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case stroke, line, arrow, rectangle, ellipse, triangle, arc, dimension, text, image, symbol }
    var id = UUID()
    var kind: Kind
    var points: [InkPoint]
    var color: InkColor = .graphite
    var width: Double = 3
    var pen: PenKind = .pen
    var brushSettings: BrushSettings? = nil
    var text: String = ""
    var fontSize: Double = 24
    var imageData: Data? = nil
    var sketch3D: Sketch3DDocument? = nil
    var dash: String = "Solid"
    var fill: Bool = false
    var rotation: Double = 0
    var locked: Bool = false
    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        var result = CGRect(x: first.x, y: first.y, width: 0, height: 0)
        for p in points.dropFirst() { result = result.union(CGRect(x: p.x, y: p.y, width: 0, height: 0)) }
        if kind == .text {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            result.size = CGSize(width: max(80, Double(lines.map(\.count).max() ?? 0) * fontSize * 0.57), height: max(fontSize * 1.5, Double(lines.count) * fontSize * 1.4))
        }
        let padding = kind == .stroke ? max(effectiveBrushSettings.maxWidth * 2, 2) : max(width / 2, 2)
        return result.insetBy(dx: -padding, dy: -padding)
    }
    var effectiveBrushSettings: BrushSettings {
        if let brushSettings { return brushSettings }
        var legacy = BrushSettings.defaults(for: pen)
        let multiplier = pen == .highlighter ? 4.0 : (pen == .marker ? 1.8 : 1.0)
        legacy.maxWidth = max(0.2, width * multiplier)
        legacy.minWidth = legacy.maxWidth * (pen == .technical ? 1 : 0.22)
        return legacy
    }
    mutating func translate(dx: Double, dy: Double) {
        points = points.map { var p = $0; p.x += dx; p.y += dy; return p }
    }
}

struct Board: Codable, Identifiable, Equatable {
    var version = 1
    var id = UUID()
    var title: String = "Untitled drawing"
    var created = Date()
    var modified = Date()
    var background: BackgroundKind = .grid
    var width: Double = 1800
    var height: Double = 1200
    var gridSpacing: Double = 30
    // Drawing model: points per real millimetre, independent of display pixels.
    var pointsPerMM: Double = 4
    var scaleDenominator: Double = 1
    var elements: [DrawingElement] = []
    var notes: String = ""
    var notionURL: String = ""
    var whiteboardURL: String = ""
    var folder: String = "General"
}

@MainActor
final class DrawingSession: ObservableObject {
    var storesPreferences = true
    @Published var board: Board
    @Published var tool: DrawTool = .ink { willSet { if newValue != tool { finishActiveInput?() } } didSet { if tool != .ink { pendingStampSymbolID = nil } } }
    @Published var pendingStampSymbolID: String? = nil
    @Published var fixedLineLengthMM: Double = 0
    @Published var keepLineLengthLabels = true
    @Published var pen: PenKind = .pen { willSet { if newValue != pen { finishActiveInput?() } } didSet { loadBrushSettings() } }
    @Published var brushSettings: BrushSettings = .defaults(for: .technical) {
        didSet {
            lineWidth = brushSettings.maxWidth
            pressureEnabled = brushSettings.pressureEnabled
            if storesPreferences, let data = try? JSONEncoder().encode(brushSettings) {
                UserDefaults.standard.set(data, forKey: "engineeringboard.brush.\(pen.rawValue)")
            }
        }
    }
    @Published var color: InkColor = .graphite {
        didSet {
            if storesPreferences, let data = try? JSONEncoder().encode(color) {
                UserDefaults.standard.set(data, forKey: "engineeringboard.brushColor.\(pen.rawValue)")
            }
        }
    }
    @Published var lineWidth: Double = 3
    @Published var dash: String = "Solid"
    @Published var fillShapes = false
    @Published var snap = false
    @Published var autoShape = true
    @Published var smoothing: Double = 0.35
    @Published var pressureEnabled = true
    @Published var zoom: Double = 0.55 { willSet { if newValue != zoom { finishActiveInput?() } } }
    @Published var cameraOffset: CGPoint = .zero
    @Published var showRuler = false
    @Published var showProtractor = false
    @Published var pendingDimensionID: UUID? = nil
    @Published var showLineDimension = false
    @Published var selectedIDs = Set<UUID>()
    @Published var status = "Local drawing • ready"
    // Ink reads every hardware sample. Inspector/status updates are throttled
    // separately so a pen event does not rebuild the entire SwiftUI workspace.
    var livePressure: Double = 0
    @Published var tabletDetected = false
    @Published var tabletPreferences = TabletPreferences.load() { didSet { if storesPreferences { tabletPreferences.save() } } }
    @Published var tabletInProximity = false
    @Published var activeTabletDeviceID: Int? = nil
    var tabletTilt: CGPoint = .zero
    var tabletRawPressure: Double = 0
    @Published var observedTabletDevices: [TabletDeviceIdentity] = []
    @Published var contextMenuRequest = 0
    @Published var tabletWorkspaceMode: TabletWorkspaceMode = .general
    var tabletDeviceKeys: [Int: String] = [:]
    var tabletProximityIDs: Set<Int> = []
    var finishActiveInput: (() -> Void)?
    var tabletActionWillPerform: ((TabletShortcutAction) -> Void)?
    @Published var recognizedText = ""
    @Published var recognitionBusy = false
    @Published var isInputActive = false
    @Published var error: String? = nil
    @Published var revision = 0
    private var undoStack: [Board] = []
    private var redoStack: [Board] = []
    private var lastTelemetryPublication: TimeInterval = 0
    private static let undoMetadataBudget = 48 * 1024 * 1024
    var onSave: ((Board) -> Void)?
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func publishTabletTelemetry(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastTelemetryPublication >= 1.0 / 20 else { return }
        lastTelemetryPublication = now
        objectWillChange.send()
    }
    init(board: Board, storesPreferences: Bool = true) { self.board = board; self.storesPreferences = storesPreferences; loadBrushSettings() }
    func loadBrushSettings() {
        if let data = UserDefaults.standard.data(forKey: "engineeringboard.brush.\(pen.rawValue)"),
           let saved = try? JSONDecoder().decode(BrushSettings.self, from: data),
           saved.minWidth.isFinite, saved.maxWidth.isFinite, saved.opacity.isFinite,
           saved.minOpacity.isFinite, saved.maxOpacity.isFinite,
           saved.pressureGamma.isFinite, saved.textureScale.isFinite,
           saved.minWidth > 0, saved.maxWidth >= saved.minWidth, saved.maxWidth <= 100,
           (0...1).contains(saved.opacity), (0.15...4).contains(saved.pressureGamma),
           (0...1).contains(saved.minOpacity), (saved.minOpacity...1).contains(saved.maxOpacity),
           (0.1...5).contains(saved.textureScale) {
            brushSettings = saved
        } else { brushSettings = .defaults(for: pen) }
        if pen == .technical {
            brushSettings.minWidth = brushSettings.maxWidth
            brushSettings.pressureEnabled = false
        }
        if let data = UserDefaults.standard.data(forKey: "engineeringboard.brushColor.\(pen.rawValue)"),
           let saved = try? JSONDecoder().decode(InkColor.self, from: data),
           [saved.r, saved.g, saved.b, saved.a].allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
            color = saved
        } else { color = .graphite }
    }
    func checkpoint() {
        undoStack.append(board)
        trimUndoHistory()
        redoStack.removeAll()
    }
    /// Point arrays and image data use copy-on-write storage, while every edit
    /// copies the element metadata array. Bound those arrays on large boards.
    private func trimUndoHistory() {
        let metadataPerElement = max(384, MemoryLayout<DrawingElement>.stride)
        var retainedBytes = 0
        var keep = 0
        for snapshot in undoStack.reversed() {
            let cost = max(1, snapshot.elements.count) * metadataPerElement
            if keep > 0 && (keep >= 80 || retainedBytes + cost > Self.undoMetadataBudget) { break }
            retainedBytes += cost; keep += 1
        }
        if undoStack.count > keep { undoStack.removeFirst(undoStack.count - keep) }
    }
    func changed() {
        board.modified = Date()
        revision += 1
        onSave?(board)
    }
    func add(_ element: DrawingElement, select: Bool = false) {
        checkpoint(); board.elements.append(element)
        if select { selectedIDs = [element.id] } else { selectedIDs.removeAll() }
        changed()
    }
    func undo() {
        finishActiveInput?()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(board); board = previous; selectedIDs.removeAll(); changed()
    }
    func redo() {
        finishActiveInput?()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(board); trimUndoHistory(); board = next; selectedIDs.removeAll(); changed()
    }
    func deleteSelection() {
        finishActiveInput?()
        guard !selectedIDs.isEmpty else { return }
        checkpoint(); board.elements.removeAll { selectedIDs.contains($0.id) && !$0.locked }; selectedIDs.removeAll(); changed()
    }
    func duplicateSelection() {
        finishActiveInput?()
        let copies = board.elements.filter { selectedIDs.contains($0.id) }.map { e -> DrawingElement in
            var c = e; c.id = UUID(); c.locked = false; c.translate(dx: 24, dy: 24); return c
        }
        guard !copies.isEmpty else { return }
        checkpoint(); board.elements += copies; selectedIDs = Set(copies.map(\.id)); changed()
    }
    func moveLayer(forward: Bool) {
        finishActiveInput?()
        guard !selectedIDs.isEmpty else { return }
        checkpoint()
        let selected = board.elements.filter { selectedIDs.contains($0.id) }
        board.elements.removeAll { selectedIDs.contains($0.id) }
        if forward { board.elements += selected } else { board.elements.insert(contentsOf: selected, at: 0) }
        changed()
    }
}
