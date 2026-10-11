import SwiftUI
import AppKit
import QuartzCore

/// AppKit's coalescing switch is global, so overlapping native canvases share ownership.
@MainActor
enum TabletCoalescingScope {
    private static var owners = Set<UUID>()
    private static var previousValue: Bool?
    static func acquire(_ owner: UUID) {
        guard owners.insert(owner).inserted else { return }
        if owners.count == 1 { previousValue = NSEvent.isMouseCoalescingEnabled; NSEvent.isMouseCoalescingEnabled = false }
    }
    static func release(_ owner: UUID) {
        guard owners.remove(owner) != nil, owners.isEmpty else { return }
        if let previousValue { NSEvent.isMouseCoalescingEnabled = previousValue }
        previousValue = nil
    }
}

struct BoardCanvas: NSViewRepresentable {
    @ObservedObject var session: DrawingSession
    func makeNSView(context: Context) -> EngineeringCanvasView { EngineeringCanvasView(session: session) }
    func updateNSView(_ view: EngineeringCanvasView, context: Context) { view.update(session: session) }
}

@MainActor
final class EngineeringCanvasView: NSView {
    var session: DrawingSession
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var previewElement: DrawingElement?
    private var previewElements: [DrawingElement]?
    private var originals: [DrawingElement] = []
    private var erasingIDs = Set<UUID>()
    private var gestureTool: DrawTool = .ink
    private var resizeCorner: Int?
    private var initialSelectionRect = CGRect.zero
    private var tabletEraser = false
    private var proximityMonitor: Any?
    private var lastRevision = -1
    private var lastBoardID: UUID?
    private var lastZoom: Double = 0
    private var lastTool: DrawTool = .ink
    private var lastSelected = Set<UUID>()
    private var lastRuler = false
    private var lastProtractor = false
    private var lastBackground: BackgroundKind?
    private var lastSpacing: Double = 0
    private var lastCamera = CGPoint.zero
    private let metalInk = MetalInkView()
    var renderingStatus: MetalInkView.RenderingStatus { metalInk.renderingStatus }
    private let committedForeground = CommittedInkForeground()
    private let penHover = PenHoverView()
    private var foregroundRevision = -1
    private var foregroundCamera = CGPoint.zero
    private var foregroundZoom: Double = 0
    private var foregroundSize = CGSize.zero
    private var holdAnchor = CGPoint.zero
    private var tileIndex = SpatialTileIndex()
    private var elementMap: [UUID: DrawingElement] = [:]
    private var indexedBounds: [UUID: CGRect] = [:]
    private let drawingCache = CommittedDrawingCache()
    var cachedArtworkStatistics: (bytes: Int, rendered: Int, hits: Int) {
        (drawingCache.bitmapBytes, drawingCache.renderedTiles, drawingCache.cacheHits)
    }
    private var elementOrder: [UUID: Int] = [:]
    private var indexedRevision = -1
    private var holdTimer: Timer?
    private var heldShape = false
    private var rawInkBeforeHold: DrawingElement?
    private var lassoPoints: [CGPoint] = []
    private var forceTouchPressure: Double? = nil
    private var previousSampleTime: TimeInterval?
    private var previousSamplePoint: CGPoint?
    private var inkFilter = AdaptiveInkFilter()
    private var spaceHeld = false
    private var panning = false
    private var panStart = CGPoint.zero
    private var panCamera = CGPoint.zero
    private var activeSymbolID: UUID?
    private var animationStart: TimeInterval = 0
    private var animationTimer: Timer?
    private var tabletContactDeviceID: Int?
    private var tabletContactStarted = false
    private var tabletErasers = Set<Int>()
    private var lastTabletButtons: [Int: NSEvent.ButtonMask] = [:]
    private var lastTabletSignature: TabletSampleSignature?
    private var lastInputEvent: NSEvent?
    private var drawingWithTablet = false
    private var hoverLocation: CGPoint?
    private var lastHoverSample: InkPoint?
    private var lastContactRawPressure: [Int: Double] = [:]
    private var zoomAlreadyAnchored = false
    private var pointerTracking: NSTrackingArea?
    private var contextPopover: NSPopover?
    private var lastContextRequest = 0
    private let coalescingOwner = UUID()
    private var coalescingSuspended = false
    private var windowObservers: [NSObjectProtocol] = []
    private var acceptsMouseMovedBefore: Bool?
    private weak var observedWindow: NSWindow?

    private struct TabletSampleSignature: Equatable {
        let device: Int
        let time: TimeInterval
        let location: CGPoint
        let pressure: Double
        let tilt: CGPoint
        let contact: Bool
    }
    private enum TabletPhase { case automatic, began, changed, ended }

    init(session: DrawingSession) {
        self.session = session
        lastContextRequest = session.contextMenuRequest
        lastBoardID = session.board.id; lastZoom = session.zoom; lastCamera = session.cameraOffset
        super.init(frame: CGRect(x: 0, y: 0, width: 900, height: 650))
        wantsLayer = true
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryGeneric)
        layer?.backgroundColor = NSColor.white.cgColor
        addSubview(metalInk)
        addSubview(committedForeground); committedForeground.isHidden = true
        committedForeground.drawArtwork = { [weak self] world, context in
            guard let self else { return }
            self.refreshSpatialIndex()
            let density = self.session.zoom * (self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
            self.drawingCache.synchronise(board: self.session.board, revision: self.session.revision,
                                          bounds: self.indexedBounds, density: density)
            self.drawingCache.draw(world: world, board: self.session.board, layer: .foreground,
                                   context: context, elements: self.cachedElements(in:))
        }
        addSubview(penHover)
        registerForDraggedTypes([.fileURL, .png, .tiff, .string, NSPasteboard.PasteboardType("local.engineeringboard.symbol")])
        installTabletActionHook()
    }
    required init?(coder: NSCoder) { nil }
    deinit {
        if let proximityMonitor { NSEvent.removeMonitor(proximityMonitor) }
        holdTimer?.invalidate(); animationTimer?.invalidate()
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        let owner = coalescingOwner
        MainActor.assumeIsolated { TabletCoalescingScope.release(owner) }
    }
    override func layout() {
        super.layout()
        // Only a window viewport becomes a Metal texture, even at 1600% zoom.
        metalInk.frame = bounds; committedForeground.frame = bounds; penHover.frame = bounds
        updateMetalPreview()
        updatePenHover()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedWindow, let acceptsMouseMovedBefore { observedWindow.acceptsMouseMovedEvents = acceptsMouseMovedBefore }
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }; windowObservers.removeAll()
        observedWindow = window; acceptsMouseMovedBefore = window?.acceptsMouseMovedEvents
        if let proximityMonitor { NSEvent.removeMonitor(proximityMonitor); self.proximityMonitor = nil }
        if window != nil {
            window?.acceptsMouseMovedEvents = true
            proximityMonitor = NSEvent.addLocalMonitorForEvents(matching: .tabletProximity) { [weak self] event in
                guard let self, event.window == self.window || event.window == nil else { return event }
                self.handleProximity(event)
                return event
            }
            windowObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishInputForFocusLoss() }
            })
            windowObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishInputForFocusLoss() }
            })
        } else {
            finishInputForFocusLoss()
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        pointerTracking = area; addTrackingArea(area)
    }
    override func mouseMoved(with event: NSEvent) {
        if Self.isTabletPointEvent(event) { routeTabletPoint(event, phase: .automatic) }
    }
    override func mouseExited(with event: NSEvent) { hoverLocation = nil; updatePenHover() }
    override func resignFirstResponder() -> Bool { finishInputBeforeSessionChange(); spaceHeld = false; panning = false; return super.resignFirstResponder() }

    func update(session: DrawingSession) {
        let replacing = self.session !== session || lastBoardID != session.board.id
        if replacing { self.session.isInputActive = false }
        self.session = session
        if replacing {
            drawingCache.reset(); indexedBounds.removeAll()
            lastBoardID = session.board.id; indexedRevision = -1; lastRevision = -1; foregroundRevision = -1
            animationTimer?.invalidate(); animationTimer = nil; activeSymbolID = nil
            clearGesture()
            tabletContactDeviceID = nil; lastTabletSignature = nil
            installTabletActionHook()
        }
        if !replacing, lastZoom > 0, lastZoom != session.zoom, session.cameraOffset == lastCamera, !zoomAlreadyAnchored {
            let anchor = hoverLocation ?? CGPoint(x: bounds.midX, y: bounds.midY)
            let world = CGPoint(x: lastCamera.x + anchor.x / lastZoom, y: lastCamera.y + anchor.y / lastZoom)
            session.cameraOffset = CGPoint(x: world.x - anchor.x / session.zoom, y: world.y - anchor.y / session.zoom)
        }
        zoomAlreadyAnchored = false
        beginTabletCoalescingScope()
        updatePenHover()
        if lastContextRequest != session.contextMenuRequest {
            lastContextRequest = session.contextMenuRequest; showPenContext(at: hoverLocation ?? CGPoint(x: bounds.midX, y: bounds.midY))
        }
        // Pressure/status publications update the inspector without forcing canvas redraws.
        if lastRevision != session.revision || lastZoom != session.zoom || lastTool != session.tool || lastSelected != session.selectedIDs || lastRuler != session.showRuler || lastProtractor != session.showProtractor || lastBackground != session.board.background || lastSpacing != session.board.gridSpacing || lastCamera != session.cameraOffset {
            lastRevision = session.revision; lastZoom = session.zoom; lastTool = session.tool; lastSelected = session.selectedIDs
            lastRuler = session.showRuler; lastProtractor = session.showProtractor
            lastBackground = session.board.background; lastSpacing = session.board.gridSpacing
            lastCamera = session.cameraOffset
            updateMetalPreview(); needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.scaleBy(x: session.zoom, y: session.zoom)
        context.translateBy(x: -session.cameraOffset.x, y: -session.cameraOffset.y)
        var displayBoard = session.board
        if let previewElements {
            let replacements = Dictionary(uniqueKeysWithValues: previewElements.map { ($0.id, $0) })
            displayBoard.elements = displayBoard.elements.map { replacements[$0.id] ?? $0 }
        }
        if !erasingIDs.isEmpty { displayBoard.elements.removeAll { erasingIDs.contains($0.id) } }
        let world = visibleWorldRect
        drawWorldBackground(world, context: context)
        refreshSpatialIndex()
        let highlighting = previewElement?.kind == .stroke && previewElement?.pen == .highlighter && metalInk.available
        let transient = previewElements != nil || !erasingIDs.isEmpty || activeSymbolID != nil
        if !transient {
            // Match the display density. AppKit may interleave snapshot and layer
            // contexts; they must not evict one another on each redraw.
            let scale = session.zoom * (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
            drawingCache.synchronise(board: session.board, revision: session.revision, bounds: indexedBounds, density: scale)
            drawingCache.draw(world: world, board: session.board, layer: highlighting ? .highlighters : .all,
                              context: context, elements: cachedElements(in:))
        } else {
            var visibleIDs = tileIndex.query(world)
            if let previewElements { visibleIDs.formUnion(previewElements.filter { visibleBounds($0).intersects(world) }.map(\.id)) }
            let replacements = Dictionary(uniqueKeysWithValues: (previewElements ?? []).map { ($0.id, $0) })
            let visibleElements = visibleIDs.sorted { (elementOrder[$0] ?? 0) < (elementOrder[$1] ?? 0) }.compactMap { id -> DrawingElement? in
                guard !erasingIDs.contains(id) else { return nil }
                return replacements[id] ?? elementMap[id]
            }
            let layered = visibleElements.filter { $0.kind == .stroke && $0.pen == .highlighter } + visibleElements.filter { !($0.kind == .stroke && $0.pen == .highlighter) }
            for element in layered where element.id != activeSymbolID && (!highlighting || (element.kind == .stroke && element.pen == .highlighter)) {
                if visibleBounds(element).intersects(world) { BoardRenderer.draw(element: element, on: displayBoard, context: context) }
            }
        }
        if let id = activeSymbolID, let element = displayBoard.elements.first(where: { $0.id == id }),
           let definition = SymbolCatalog.definition(id: String(element.text.dropFirst("catalog:".count))) {
            let rect = elementRect(element)
            let phase = min(1, (Date.timeIntervalSinceReferenceDate - animationStart) / 1.5)
            DiagramRenderer.draw(definition: definition, in: rect, context: context, color: BoardRenderer.visibleColor(element.color, board: displayBoard), phase: phase)
        }
        if let previewElement, previewElement.kind != .stroke || !metalInk.available {
            BoardRenderer.draw(element: previewElement, on: displayBoard, context: context)
        }
        if session.tool == .select || session.tool == .lasso { drawSelection(displayBoard, context: context) }
        if !lassoPoints.isEmpty {
            context.saveGState(); context.setStrokeColor(NSColor.systemBlue.cgColor); context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.07).cgColor)
            context.setLineWidth(1.4 / session.zoom); context.setLineDash(phase: 0, lengths: [5 / session.zoom, 4 / session.zoom]); context.addLines(between: lassoPoints)
            context.closePath(); context.drawPath(using: .fillStroke); context.restoreGState()
        }
        if session.showRuler { drawRuler(context) }
        if session.showProtractor { drawProtractor(context) }
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        if Self.isTabletPointEvent(event) { routeTabletPoint(event, phase: .began); return }
        guard !rejectUnrelatedPointer, tabletContactDeviceID == nil else { return }
        drawingWithTablet = false; lastInputEvent = event
        beginDrawingGesture(with: event)
    }
    private func beginDrawingGesture(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handleTabletSample(event)
        // A new gesture returns any short teaching animation to its saved geometry.
        if activeSymbolID != nil {
            animationTimer?.invalidate(); animationTimer = nil; activeSymbolID = nil; needsDisplay = true
        }
        if spaceHeld { beginPan(event); return }
        let location = boardPoint(event)
        guard location.x.isFinite, location.y.isFinite else { return }
        session.isInputActive = true
        if let identifier = session.pendingStampSymbolID {
            clearGesture()
            if !session.isInputActive { session.isInputActive = true }
            session.pendingDimensionID = nil; session.showLineDimension = false
            if let definition = SymbolCatalog.definition(id: identifier) {
                let size = definition.diagram == .glyph ? CGSize(width: 120, height: 100) : CGSize(width: 220, height: 140)
                let center = snapped(location)
                let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
                let element = DrawingElement(kind: .symbol, points: [InkPoint(x: origin.x, y: origin.y), InkPoint(x: origin.x + size.width, y: origin.y + size.height)], color: session.color, width: session.lineWidth, text: "catalog:" + identifier)
                session.add(element); startPlacedAnimation(element: element, definition: definition)
                session.status = "\(definition.name) stamped • click again to repeat • Esc returns to drawing"
            } else {
                session.pendingStampSymbolID = nil; session.status = "That symbol is unavailable • choose another symbol"
            }
            needsDisplay = true; return
        }
        previousSampleTime = nil; previousSamplePoint = nil; forceTouchPressure = nil
        session.pendingDimensionID = nil; session.showLineDimension = false
        startPoint = location; currentPoint = location
        gestureTool = drawingWithTablet && tabletEraser ? .eraser : session.tool
        erasingIDs.removeAll(); previewElements = nil; resizeCorner = nil
        heldShape = false; rawInkBeforeHold = nil
        if gestureTool != .select && gestureTool != .lasso { session.selectedIDs.removeAll() }
        if gestureTool == .lasso {
            lassoPoints = [location]
            if !event.modifierFlags.contains(.shift) { session.selectedIDs.removeAll() }
            needsDisplay = true; return
        }
        if (gestureTool == .select || gestureTool == .text), Self.isMousePointerEvent(event), event.clickCount == 2,
           let existing = hitElement(at: location), (existing.kind == .text || (existing.kind == .symbol && existing.text.hasPrefix("mathlatex:"))), !existing.locked {
            session.selectedIDs = [existing.id]
            insertText(at: existing.points.first?.cg ?? location, editing: existing)
            clearGesture(); return
        }
        if gestureTool == .select {
            if let box = selectionBounds(session.board), let corner = cornerHit(location, rect: box) {
                resizeCorner = corner; initialSelectionRect = box
                originals = session.board.elements.filter { session.selectedIDs.contains($0.id) && !$0.locked }
                return
            }
            if let hit = hitElement(at: location) {
                if event.modifierFlags.contains(.shift) {
                    if session.selectedIDs.contains(hit.id) { session.selectedIDs.remove(hit.id) }
                    else { session.selectedIDs.insert(hit.id) }
                } else if !session.selectedIDs.contains(hit.id) { session.selectedIDs = [hit.id] }
                originals = session.board.elements.filter { session.selectedIDs.contains($0.id) && !$0.locked }
            } else {
                if !event.modifierFlags.contains(.shift) { session.selectedIDs.removeAll() }
                originals.removeAll()
            }
            needsDisplay = true; return
        }
        if gestureTool == .eraser { erase(at: location); return }
        if gestureTool == .text { insertText(at: snapped(location)); clearGesture(); return }
        let point = sample(event, at: gestureTool == .ink ? location : snapped(location))
        previewElement = DrawingElement(kind: kind(for: gestureTool), points: [point], color: session.color, width: session.lineWidth, pen: session.pen, brushSettings: gestureTool == .ink ? session.brushSettings : nil, dash: session.dash, fill: session.fillShapes)
        updateMetalPreview()
        if gestureTool == .ink { scheduleHold() }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if Self.isTabletPointEvent(event) { routeTabletPoint(event, phase: .changed); return }
        guard !rejectUnrelatedPointer, !drawingWithTablet else { return }
        lastInputEvent = event; updateGesture(with: event)
    }
    private func updateGesture(with event: NSEvent) {
        if panning { updatePan(event); return }
        guard let start = startPoint else { return }
        handleTabletSample(event)
        let location = boardPoint(event)
        currentPoint = location
        switch gestureTool {
        case .lasso:
            if let previous = lassoPoints.last, hypot(location.x - previous.x, location.y - previous.y) > 3 / session.zoom { lassoPoints.append(location) }
        case .select:
            if let corner = resizeCorner { previewElements = resizedElements(location: snapped(location), corner: corner, uniform: event.modifierFlags.contains(.shift)) }
            else if !originals.isEmpty {
                let delta = CGPoint(x: location.x - start.x, y: location.y - start.y)
                let adjusted = session.snap ? CGPoint(x: (delta.x / grid).rounded() * grid, y: (delta.y / grid).rounded() * grid) : delta
                previewElements = originals.map { element in var value = element; value.translate(dx: adjusted.x, dy: adjusted.y); return value }
            }
        case .eraser: erase(at: location)
        case .ink:
            guard var element = previewElement else { return }
            if heldShape, let original = rawInkBeforeHold {
                if hypot(location.x - holdAnchor.x, location.y - holdAnchor.y) * session.zoom < 3 { return }
                element = original; heldShape = false; rawInkBeforeHold = nil; needsDisplay = true
            }
            let previous = element.points.last?.cg ?? start
            // Filter every delivered sample, even when movement is below the stored-point threshold.
            let smoothed = inkFilter.sample(location, at: event.timestamp, smoothing: session.smoothing, zoom: session.zoom)
            let pressureChanged = Self.isTabletPointEvent(event) && abs((element.points.last?.rawPressure ?? -1) - Double(event.pressure)) > 0.000_001
            let moved = hypot(smoothed.x - previous.x, smoothed.y - previous.y) > 0.25 / session.zoom
            if moved || pressureChanged {
                element.points.append(sample(event, at: smoothed, rawPoint: location)); previewElement = element
                if moved { scheduleHold() }
            }
        default:
            guard var element = previewElement, let first = element.points.first else { return }
            let end = constrained(snapped(location), from: first.cg, tool: gestureTool, shift: event.modifierFlags.contains(.shift))
            element.points = [first, sample(event, at: end)]; previewElement = element
        }
        updateMetalPreview()
        if gestureTool != .ink || !metalInk.available { needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        if Self.isTabletPointEvent(event) { routeTabletPoint(event, phase: .ended); return }
        guard !drawingWithTablet, !rejectUnrelatedPointer || startPoint != nil else { return }
        lastInputEvent = event; finishGesture(with: event)
    }
    private func finishGesture(with event: NSEvent) {
        session.isInputActive = false
        if panning { panning = false; return }
        holdTimer?.invalidate(); holdTimer = nil
        guard startPoint != nil else { return }
        switch gestureTool {
        case .lasso:
            if lassoPoints.count > 2 {
                let path = CGMutablePath(); path.addLines(between: lassoPoints); path.closeSubpath()
                let chosen = session.board.elements.filter { element in
                    let box = visibleBounds(element)
                    if !path.boundingBox.intersects(box) { return false }
                    let center = CGPoint(x: box.midX, y: box.midY)
                    return path.contains(center) || element.points.contains { path.contains($0.cg) }
                }
                session.selectedIDs.formUnion(chosen.map(\.id)); session.status = "Lasso selected \(session.selectedIDs.count) objects"
            }
        case .select:
            if let previewElements, previewElements != originals {
                session.checkpoint()
                let replacements = Dictionary(uniqueKeysWithValues: previewElements.map { ($0.id, $0) })
                session.board.elements = session.board.elements.map { replacements[$0.id] ?? $0 }
                session.changed(); session.status = "Selection updated"
            }
        case .eraser:
            if !erasingIDs.isEmpty {
                session.checkpoint(); session.board.elements.removeAll { erasingIDs.contains($0.id) }
                session.selectedIDs.subtract(erasingIDs); session.changed()
                session.status = "Erased \(erasingIDs.count) object\(erasingIDs.count == 1 ? "" : "s") • ⌘Z to undo"
            }
        case .ink:
            if var element = previewElement {
                let end = boardPoint(event)
                if element.kind == .stroke, let previous = element.points.last, hypot(previous.x - end.x, previous.y - end.y) > 0.3 {
                    // Endpoint catch-up keeps the last real contact metadata. Live tablet
                    // telemetry may already describe hover (zero pressure) at this point.
                    var final = previous
                    final.x = end.x; final.y = end.y
                    element.points.append(final)
                }
                guard let finished = committedLine(element) else { session.livePressure = 0; clearGesture(); return }
                element = finished
                session.add(element)
                if heldShape && (element.kind == .line || element.kind == .dimension) {
                    session.pendingDimensionID = element.id; session.showLineDimension = true
                }
                session.status = heldShape ? "Shape snapped • edit its exact size" : (drawingWithTablet ? "Drawing saved • tablet input received" : "Drawing saved locally")
            }
        default:
            if var element = previewElement, let first = element.points.first {
                let end = constrained(snapped(boardPoint(event)), from: first.cg, tool: gestureTool, shift: event.modifierFlags.contains(.shift))
                element.points = [first, sample(event, at: end)]
                if hypot(end.x - first.x, end.y - first.y) >= 1, let finished = committedLine(element) {
                    session.add(finished); session.status = "\(gestureTool.rawValue) added"
                }
            }
        }
        session.livePressure = 0; clearGesture()
    }

    override func pressureChange(with event: NSEvent) {
        // Force Touch has an explicit native pressure event, distinct from mouse pressure fields.
        guard event.type == .pressure, !rejectUnrelatedPointer, !drawingWithTablet else { return }
        if event.stage <= 0 { forceTouchPressure = nil; session.livePressure = 0; return }
        let value = Double(event.pressure)
        guard value.isFinite else { return }
        let firstPressureEvent = forceTouchPressure == nil
        forceTouchPressure = min(1, max(0, value)); session.livePressure = forceTouchPressure!
        session.publishTabletTelemetry()
        if firstPressureEvent { session.status = "Force Touch pressure received" }
        if session.pressureEnabled, var element = previewElement, element.kind == .stroke, !element.points.isEmpty {
            element.points[element.points.count - 1].pressure = forceTouchPressure!
            previewElement = element; updateMetalPreview()
            if !metalInk.available { needsDisplay = true }
        }
    }
    override func tabletPoint(with event: NSEvent) { routeTabletPoint(event, phase: .automatic) }
    override func tabletProximity(with event: NSEvent) { handleProximity(event) }
    private func handleProximity(_ event: NSEvent) {
        guard Self.isTabletProximityEvent(event) else { return }
        session.observeTabletProximity(event)
        if event.isEnteringProximity {
            if event.pointingDeviceType == .eraser { tabletErasers.insert(event.deviceID) } else { tabletErasers.remove(event.deviceID) }
            session.status = event.pointingDeviceType == .eraser ? "Tablet eraser event received" : "Tablet event received • pen input available"
        } else {
            tabletErasers.remove(event.deviceID); lastTabletButtons.removeValue(forKey: event.deviceID)
            if tabletContactDeviceID == event.deviceID { finishCapturedGesture(); tabletContactDeviceID = nil; tabletContactStarted = false; drawingWithTablet = false }
            if session.activeTabletDeviceID == nil || lastHoverSample?.inputDeviceKey == session.tabletInputKey(deviceID: event.deviceID) { hoverLocation = nil }
        }
        tabletEraser = session.activeTabletDeviceID.map { tabletErasers.contains($0) } ?? false
        if event.isEnteringProximity { coalescingSuspended = false }
        beginTabletCoalescingScope()
        updatePenHover()
    }
    private func handleTabletSample(_ event: NSEvent) {
        if Self.isTabletProximityEvent(event) { handleProximity(event) }
        if Self.isTabletPointEvent(event) {
            session.observeTabletSample(event)
            tabletEraser = tabletErasers.contains(event.deviceID)
        }
    }

    private var rejectUnrelatedPointer: Bool {
        session.tabletPreferences.rejectPointerWhileHovering && session.tabletInProximity && !coalescingSuspended
    }
    private var finishingSessionInput = false
    private func finishInputBeforeSessionChange() {
        guard !finishingSessionInput else { return }
        finishingSessionInput = true
        defer { finishingSessionInput = false }
        let stampContact = tabletContactStarted && session.pendingStampSymbolID != nil && startPoint == nil
        finishCapturedGesture()
        if tabletContactDeviceID != nil && !stampContact { tabletContactStarted = false }
    }
    private func installTabletActionHook() {
        session.finishActiveInput = { [weak self] in self?.finishInputBeforeSessionChange() }
        session.tabletActionWillPerform = { [weak self] action in self?.prepareForTabletAction(action) }
    }
    func restoreSessionInputHooks() { installTabletActionHook() }
    private func prepareForTabletAction(_ action: TabletShortcutAction) {
        switch action {
        case .undo, .redo, .ink, .eraser, .select, .nextPen, .previousPen, .brushLarger, .brushSmaller, .context:
            let stampContact = tabletContactStarted && session.pendingStampSymbolID != nil && startPoint == nil
            finishCapturedGesture()
            if tabletContactDeviceID != nil && !stampContact { tabletContactStarted = false }
        default: break
        }
    }

    private func routeTabletPoint(_ event: NSEvent, phase: TabletPhase) {
        guard Self.isTabletPointEvent(event) else { return }
        let point = localPoint(event), raw = Double(event.pressure)
        guard point.x.isFinite, point.y.isFinite, raw.isFinite else { return }
        let device = event.deviceID
        // Two pens cannot interleave samples inside the same saved stroke.
        guard tabletContactDeviceID == nil || tabletContactDeviceID == device else { return }
        coalescingSuspended = false
        beginTabletCoalescingScope()
        handleTabletSample(event)
        hoverLocation = point
        if raw > 0 { lastContactRawPressure[device] = raw }
        lastHoverSample = InkPoint(x: point.x, y: point.y, pressure: session.livePressure, tiltX: session.tabletTilt.x, tiltY: session.tabletTilt.y, rawPressure: session.tabletRawPressure, inputDeviceKey: session.tabletInputKey(deviceID: device))
        updatePenHover()
        handleBarrelButtons(event)
        let tipDown = phase != .ended && (phase == .began || event.buttonMask.contains(.penTip) || raw > 0)
        let signature = TabletSampleSignature(device: device, time: event.timestamp, location: point, pressure: raw, tilt: event.tilt, contact: tipDown)
        guard signature != lastTabletSignature else { return }
        lastTabletSignature = signature
        if contextPopover?.isShown == true {
            if !tipDown { tabletContactDeviceID = nil; tabletContactStarted = false; drawingWithTablet = false }
            return
        }
        if tipDown {
            if tabletContactDeviceID == nil {
                tabletContactDeviceID = device; tabletContactStarted = false; drawingWithTablet = true
            }
            if !session.isInputActive { session.isInputActive = true }
            guard session.tabletContactAllowed(raw: raw, deviceID: device) else {
                if tabletContactStarted, startPoint != nil, gestureTool == .ink {
                    // A calibrated dead zone splits ink instead of bridging an invisible gap.
                    finishCapturedGesture(); tabletContactStarted = false
                }
                if !session.isInputActive { session.isInputActive = true }
                return
            }
            lastInputEvent = event
            if !tabletContactStarted {
                tabletContactStarted = true
                beginTabletCoalescingScope()
                beginDrawingGesture(with: event)
            } else { updateGesture(with: event) }
        } else if tabletContactDeviceID == device {
            // Commit the last accepted tip sample, rather than extending ink across hover movement.
            finishCapturedGesture()
            tabletContactDeviceID = nil; tabletContactStarted = false; drawingWithTablet = false
            restoreTabletCoalescing()
        }
    }

    private func handleBarrelButtons(_ event: NSEvent) {
        guard Self.isTabletPointEvent(event) else { return }
        let buttons = event.buttonMask, previous = lastTabletButtons[event.deviceID] ?? []
        lastTabletButtons[event.deviceID] = buttons
        if buttons.contains(.penLowerSide) && !previous.contains(.penLowerSide) { performBarrelAction(session.tabletPreferences.lowerButton) }
        if buttons.contains(.penUpperSide) && !previous.contains(.penUpperSide) { performBarrelAction(session.tabletPreferences.upperButton) }
    }
    private func performBarrelAction(_ action: TabletBarrelAction) {
        switch action {
        case .driverControlled: return
        case .straighten: session.performTabletAction(.toggleStraighten)
        case .context, .colour, .dimension:
            finishCapturedGesture()
            session.performTabletAction(.context)
            lastContextRequest = session.contextMenuRequest
            showPenContext(at: hoverLocation ?? CGPoint(x: bounds.midX, y: bounds.midY))
        }
        updatePenHover()
    }
    private func beginTabletCoalescingScope() {
        if session.tabletPreferences.disableMouseCoalescing && session.tabletInProximity && !coalescingSuspended {
            TabletCoalescingScope.acquire(coalescingOwner)
        } else { TabletCoalescingScope.release(coalescingOwner) }
    }
    private func restoreTabletCoalescing() {
        // Tip-up leaves the opted-in scope active while a real pen remains in range.
        beginTabletCoalescingScope()
    }
    private func finishCapturedGesture() {
        if panning { panning = false; clearGesture() }
        else if startPoint != nil, let lastInputEvent { finishGesture(with: lastInputEvent) }
        else { clearGesture() }
        restoreTabletCoalescing()
    }
    private func finishInputForFocusLoss() {
        coalescingSuspended = true
        finishCapturedGesture()
        spaceHeld = false; panning = false; tabletContactDeviceID = nil; tabletContactStarted = false; drawingWithTablet = false
        hoverLocation = nil; lastTabletSignature = nil; lastTabletButtons.removeAll(); updatePenHover()
    }
    private func updatePenHover() {
        guard session.tabletPreferences.showHover, session.tabletInProximity, let location = hoverLocation, let sample = lastHoverSample, bounds.contains(location), contextPopover?.isShown != true else {
            penHover.hide(); return
        }
        var point = sample
        // Hover uses the last real contact pressure; a new pen starts with maximum width.
        // This preview never changes the live pressure reported by AppKit.
        if point.pressure <= 0 {
            if let device = session.activeTabletDeviceID, let raw = lastContactRawPressure[device] { point.pressure = session.calibratedPressure(raw: raw, deviceID: device) }
            else { point.pressure = 1 }
        }
        let element = DrawingElement(kind: .stroke, points: [point], color: session.color, width: session.lineWidth, pen: session.pen, brushSettings: session.brushSettings)
        let width = BrushMetrics.width(element: element, point: point) * session.zoom
        let color = BoardRenderer.visibleColor(session.color, board: session.board)
        penHover.present(at: location, diameter: width, tilt: session.pen == .pencil ? session.tabletTilt : .zero, color: color, eraser: tabletEraser || session.tool == .eraser, nib: session.pen == .calligraphy)
    }
    private func showPenContext(at location: CGPoint) {
        guard window != nil else { return }
        finishCapturedGesture()
        contextPopover?.close()
        let popover = NSPopover(); popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PenContextPanel(session: session, onDismiss: { [weak self, weak popover] in
            popover?.close(); self?.window?.makeFirstResponder(self); self?.updatePenHover()
        }))
        contextPopover = popover; updatePenHover()
        let anchor = CGRect(x: min(bounds.maxX - 1, max(0, location.x)), y: min(bounds.maxY - 1, max(0, location.y)), width: 1, height: 1)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxX)
        updatePenHover()
    }

    /// AppKit throws if `subtype` is requested on a standalone tablet event.
    private static func isMousePointerEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved:
            return true
        default: return false
        }
    }
    static func isTabletPointEvent(_ event: NSEvent) -> Bool {
        event.type == .tabletPoint || (isMousePointerEvent(event) && event.subtype == .tabletPoint)
    }
    static func isTabletProximityEvent(_ event: NSEvent) -> Bool {
        event.type == .tabletProximity || (isMousePointerEvent(event) && event.subtype == .tabletProximity)
    }

    override func keyDown(with event: NSEvent) {
        let text = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if let action = TabletShortcutAction.from(event: event) {
            if action == .context { finishCapturedGesture() }
            let anchor = hoverLocation ?? CGPoint(x: bounds.midX, y: bounds.midY)
            let oldZoom = session.zoom
            let world = CGPoint(x: session.cameraOffset.x + anchor.x / oldZoom, y: session.cameraOffset.y + anchor.y / oldZoom)
            session.performTabletAction(action)
            if session.zoom != oldZoom {
                zoomAlreadyAnchored = true
                session.cameraOffset = CGPoint(x: world.x - anchor.x / session.zoom, y: world.y - anchor.y / session.zoom)
                updateMetalPreview(); updatePenHover(); needsDisplay = true
            }
            if action == .context { lastContextRequest = session.contextMenuRequest; showPenContext(at: anchor) }
            return
        }
        if event.keyCode == 49 { spaceHeld = true; return }
        if event.modifierFlags.contains(.command) {
            switch text {
            case "z": event.modifierFlags.contains(.shift) ? session.redo() : session.undo(); clearGesture()
            case "v": paste(nil)
            case "a": session.selectedIDs = Set(session.board.elements.map(\.id)); session.tool = .select
            case "d": session.duplicateSelection()
            default: super.keyDown(with: event)
            }
            return
        }
        if event.keyCode == 53 {
            clearGesture(); session.selectedIDs.removeAll(); session.pendingStampSymbolID = nil
            session.pendingDimensionID = nil; session.showLineDimension = false; session.tool = .ink
            session.status = "Drawing tool • stamp cancelled"; return
        }
        if event.keyCode == 51 || event.keyCode == 117 { session.deleteSelection(); return }
        guard event.modifierFlags.intersection([.control, .option, .function, .help]).isEmpty else { super.keyDown(with: event); return }
        let shortcuts: [String: DrawTool] = ["v": .select, "q": .lasso, "b": .ink, "e": .eraser, "l": .line, "a": .arrow, "r": .rectangle, "o": .ellipse, "t": .text, "d": .dimension]
        if let tool = shortcuts[text] { session.tool = tool; session.status = "\(tool.rawValue) tool" }
        else { super.keyDown(with: event) }
    }

    @objc func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let origin = CGPoint(x: session.cameraOffset.x + bounds.midX / session.zoom - 150, y: session.cameraOffset.y + bounds.midY / session.zoom - 100)
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            _ = addImage(data: data, at: origin)
        }
        else if let string = pasteboard.string(forType: .string), !string.isEmpty {
            session.add(DrawingElement(kind: .text, points: [InkPoint(x: origin.x, y: origin.y)], color: session.color, text: string, fontSize: 24))
            session.status = "Text pasted"
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let local = convert(sender.draggingLocation, from: nil)
        let point = CGPoint(x: local.x / session.zoom + session.cameraOffset.x, y: local.y / session.zoom + session.cameraOffset.y)
        if let payload = pasteboard.string(forType: NSPasteboard.PasteboardType("local.engineeringboard.symbol")) ?? pasteboard.string(forType: .string) {
            let prefix = "engineeringboard-symbol:"
            let identifier = payload.hasPrefix(prefix) ? String(payload.dropFirst(prefix.count)) : payload
            if let definition = SymbolCatalog.definition(id: identifier) {
                let size = definition.diagram == .glyph ? CGSize(width: 120, height: 100) : CGSize(width: 220, height: 140)
                let element = DrawingElement(kind: .symbol, points: [InkPoint(x: point.x, y: point.y), InkPoint(x: point.x + size.width, y: point.y + size.height)], color: session.color, width: session.lineWidth, text: "catalog:" + identifier)
                session.add(element); startPlacedAnimation(element: element, definition: definition)
                session.status = "\(definition.name) added • select to move or resize"
                return true
            }
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                do {
                    let data = try SafeImage.readFile(url)
                    return addImage(data: data, at: point)
                } catch { session.error = error.localizedDescription }
            }
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) { return addImage(data: data, at: point) }
        if let text = pasteboard.string(forType: .string) {
            session.add(DrawingElement(kind: .text, points: [InkPoint(x: point.x, y: point.y)], color: session.color, text: text)); return true
        }
        return false
    }

    override func magnify(with event: NSEvent) {
        guard !rejectUnrelatedPointer else { return }
        let anchor = localPoint(event)
        let world = CGPoint(x: anchor.x / session.zoom + session.cameraOffset.x, y: anchor.y / session.zoom + session.cameraOffset.y)
        zoomAlreadyAnchored = true
        session.zoom = min(16, max(0.05, session.zoom * (1 + event.magnification)))
        session.cameraOffset = CGPoint(x: world.x - anchor.x / session.zoom, y: world.y - anchor.y / session.zoom)
        updateMetalPreview(); needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        guard !rejectUnrelatedPointer else { return }
        session.cameraOffset.x -= event.scrollingDeltaX / session.zoom
        session.cameraOffset.y -= event.scrollingDeltaY / session.zoom
        updateMetalPreview(); needsDisplay = true
    }
    override func keyUp(with event: NSEvent) { if event.keyCode == 49 { spaceHeld = false } else { super.keyUp(with: event) } }
    override func rightMouseDown(with event: NSEvent) {
        if Self.isTabletPointEvent(event) {
            handleTabletSample(event); hoverLocation = localPoint(event)
            let mapped = (event.buttonMask.contains(.penLowerSide) && session.tabletPreferences.lowerButton != .driverControlled) || (event.buttonMask.contains(.penUpperSide) && session.tabletPreferences.upperButton != .driverControlled)
            handleBarrelButtons(event)
            if mapped { return }
        }
        // The explicit context button remains usable while accidental pointer drawing is rejected.
        showPenContext(at: localPoint(event))
    }
    override func otherMouseDown(with event: NSEvent) {
        if Self.isTabletPointEvent(event) {
            handleTabletSample(event); hoverLocation = localPoint(event)
            let mapped = (event.buttonMask.contains(.penLowerSide) && session.tabletPreferences.lowerButton != .driverControlled) || (event.buttonMask.contains(.penUpperSide) && session.tabletPreferences.upperButton != .driverControlled)
            handleBarrelButtons(event); if mapped { return }
        } else if rejectUnrelatedPointer { return }
        finishCapturedGesture(); beginPan(event)
    }
    override func otherMouseDragged(with event: NSEvent) { if panning && (!rejectUnrelatedPointer || Self.isTabletPointEvent(event)) { updatePan(event) } }
    override func otherMouseUp(with event: NSEvent) { panning = false; session.isInputActive = false }
    private func beginPan(_ event: NSEvent) {
        session.isInputActive = true
        panning = true; panStart = localPoint(event); panCamera = session.cameraOffset
    }
    private func updatePan(_ event: NSEvent) {
        let local = localPoint(event)
        session.cameraOffset = CGPoint(x: panCamera.x - (local.x - panStart.x) / session.zoom, y: panCamera.y - (local.y - panStart.y) / session.zoom)
        updateMetalPreview(); needsDisplay = true
    }

    private func insertText(at point: CGPoint, editing existing: DrawingElement? = nil) {
        let alert = NSAlert(); alert.messageText = existing == nil ? "Add a note or equation" : "Edit your text"
        alert.informativeText = "Type your text. Handwritten maths recognition is available separately."
        alert.addButton(withTitle: existing == nil ? "Add text" : "Save text"); alert.addButton(withTitle: "Cancel")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 130)); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let input = NSTextView(frame: scroll.bounds); input.font = .systemFont(ofSize: 16); input.isRichText = false; input.textContainerInset = NSSize(width: 7, height: 7)
        let maths = existing?.text.hasPrefix("mathlatex:") ?? false
        input.string = maths ? String(existing!.text.dropFirst("mathlatex:".count)) : (existing?.text ?? "")
        scroll.documentView = input; alert.accessoryView = scroll
        alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn, !input.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let updatedText = (maths ? "mathlatex:" : "") + input.string
            if let existing, let index = session.board.elements.firstIndex(where: { $0.id == existing.id }), existing.text != updatedText {
                session.checkpoint(); session.board.elements[index].text = updatedText; session.changed(); session.status = "Text updated"
            } else if existing == nil {
                session.add(DrawingElement(kind: .text, points: [InkPoint(x: point.x, y: point.y)], color: session.color, text: input.string, fontSize: 24)); session.status = "Text added"
            }
        }
        window?.makeFirstResponder(self)
    }
    @discardableResult
    private func addImage(data: Data, at origin: CGPoint) -> Bool {
        do {
            let image = try SafeImage.decode(data)
            let width = min(500, session.board.width * 0.6), ratio = image.size.height / max(1, image.size.width)
            session.add(DrawingElement(kind: .image, points: [InkPoint(x: origin.x, y: origin.y), InkPoint(x: origin.x + width, y: origin.y + width * ratio)], imageData: data))
            session.status = "Image added • select to move or resize"
            return true
        } catch {
            session.error = error.localizedDescription
            return false
        }
    }

    private var grid: Double { max(8, session.board.gridSpacing) }
    private func snapped(_ point: CGPoint) -> CGPoint {
        guard session.snap else { return point }
        return CGPoint(x: (point.x / grid).rounded() * grid, y: (point.y / grid).rounded() * grid)
    }
    private func boardPoint(_ event: NSEvent) -> CGPoint {
        let point = localPoint(event)
        return CGPoint(x: point.x / session.zoom + session.cameraOffset.x, y: point.y / session.zoom + session.cameraOffset.y)
    }
    private func localPoint(_ event: NSEvent) -> CGPoint {
        // Standalone events without an attached NSWindow retain Cocoa screen coordinates.
        let windowPoint = event.window == nil && Self.isTabletPointEvent(event) ? (window?.convertPoint(fromScreen: event.locationInWindow) ?? event.locationInWindow) : event.locationInWindow
        return convert(windowPoint, from: nil)
    }
    private func sample(_ event: NSEvent, at point: CGPoint, rawPoint: CGPoint? = nil) -> InkPoint {
        let tablet = Self.isTabletPointEvent(event)
        let pressure: Double
        if tablet {
            let value = Double(event.pressure)
            pressure = session.calibratedPressure(raw: value, deviceID: event.deviceID)
        }
        else if session.pressureEnabled, let forceTouchPressure { pressure = forceTouchPressure }
        else { pressure = 1 }
        var velocity: Double? = nil
        let rawLocation = rawPoint ?? boardPoint(event)
        if let time = previousSampleTime, let previous = previousSamplePoint, event.timestamp > time {
            velocity = hypot(rawLocation.x - previous.x, rawLocation.y - previous.y) / (event.timestamp - time)
        }
        previousSampleTime = event.timestamp; previousSamplePoint = rawLocation
        if gestureTool == .ink, previewElement == nil {
            _ = inkFilter.sample(rawLocation, at: event.timestamp, smoothing: session.smoothing, zoom: session.zoom)
        }
        // A mouse has fixed stroke width; it never produces a pretend live-pressure reading.
        return InkPoint(x: point.x, y: point.y, pressure: pressure, tiltX: tablet ? session.tabletTilt.x : 0, tiltY: tablet ? session.tabletTilt.y : 0, velocity: velocity, rawPressure: tablet ? session.tabletRawPressure : nil, inputDeviceKey: tablet ? session.tabletInputKey(deviceID: event.deviceID) : nil)
    }
    private func kind(for tool: DrawTool) -> DrawingElement.Kind {
        switch tool {
        case .ink, .select, .lasso, .eraser: return .stroke
        case .line: return .line
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .triangle: return .triangle
        case .arc: return .arc
        case .dimension: return .dimension
        case .text: return .text
        }
    }
    private func constrained(_ end: CGPoint, from start: CGPoint, tool: DrawTool, shift: Bool) -> CGPoint {
        let directional = tool == .line || tool == .arrow || tool == .dimension
        let isometric = directional && session.snap && session.board.background == .isometric
        guard shift || isometric else { return end }
        let dx = end.x - start.x, dy = end.y - start.y
        if directional {
            let step = isometric ? Double.pi / 6 : Double.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step, length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        let length = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -length : length), y: start.y + (dy < 0 ? -length : length))
    }
    /// Exact length is stored in world coordinates, independent of the current zoom.
    private func committedLine(_ source: DrawingElement) -> DrawingElement? {
        guard source.kind == .line, let first = source.points.first, var last = source.points.last else { return source }
        var result = source
        let endpoint = constrained(last.cg, from: first.cg, tool: .line, shift: false)
        last.x = endpoint.x; last.y = endpoint.y
        if session.fixedLineLengthMM > 0 {
            guard let fixed = DrawingDimensions.endpoint(start: first, end: last, lengthMM: session.fixedLineLengthMM, pointsPerMM: session.board.pointsPerMM, scaleDenominator: session.board.scaleDenominator) else {
                session.error = "The fixed line length could not be applied. Check the length and drawing scale, or set 0 for a free line."
                session.status = "Fixed length could not be applied"; return nil
            }
            last = fixed
        }
        result.points = [first, last]
        if session.keepLineLengthLabels { result.kind = .dimension }
        return result
    }
    private func clearGesture() {
        session.isInputActive = false
        restoreTabletCoalescing()
        holdTimer?.invalidate(); holdTimer = nil; heldShape = false; rawInkBeforeHold = nil
        startPoint = nil; currentPoint = nil; previewElement = nil; previewElements = nil; originals.removeAll(); erasingIDs.removeAll(); resizeCorner = nil; lassoPoints.removeAll(); previousSampleTime = nil; previousSamplePoint = nil; forceTouchPressure = nil; inkFilter.reset()
        updateMetalPreview(); needsDisplay = true
    }

    private func erase(at point: CGPoint) {
        if let hit = hitElement(at: point), !hit.locked { erasingIDs.insert(hit.id); needsDisplay = true }
    }
    private func hitElement(at point: CGPoint) -> DrawingElement? {
        session.board.elements.reversed().first { !erasingIDs.contains($0.id) && Self.hit($0, point: point, tolerance: max(6, 7 / session.zoom)) }
    }
    static func hit(_ element: DrawingElement, point: CGPoint, tolerance: CGFloat) -> Bool {
        guard let first = element.points.first else { return false }
        let local = rotated(point, around: CGPoint(x: element.bounds.midX, y: element.bounds.midY), degrees: -element.rotation)
        let last = element.points.last ?? first
        let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
        let hitWidth = element.kind == .stroke ? element.effectiveBrushSettings.maxWidth : element.width
        let t = tolerance + hitWidth / 2
        switch element.kind {
        case .text, .image, .symbol: return element.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
        case .stroke:
            if element.points.count == 1 { return hypot(local.x - first.x, local.y - first.y) <= t }
            return zip(element.points, element.points.dropFirst()).contains { distance(local, segment: $0.cg, to: $1.cg) <= t }
        case .line, .arrow, .dimension: return distance(local, segment: first.cg, to: last.cg) <= t
        case .rectangle:
            if element.fill && rect.contains(local) { return true }
            return rectangleEdges(rect).contains { distance(local, segment: $0.0, to: $0.1) <= t }
        case .ellipse:
            guard rect.width > 0, rect.height > 0 else { return distance(local, segment: first.cg, to: last.cg) <= t }
            let rx = rect.width / 2, ry = rect.height / 2
            let normalized = hypot((local.x - rect.midX) / rx, (local.y - rect.midY) / ry)
            if element.fill && normalized <= 1 { return true }
            return abs(normalized - 1) * min(rx, ry) <= t && rect.insetBy(dx: -t, dy: -t).contains(local)
        case .triangle:
            let points = element.points.count >= 3 ? Array(element.points.prefix(3).map(\.cg)) : [CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            if element.fill {
                let path = CGMutablePath(); path.addLines(between: points); path.closeSubpath(); if path.contains(local) { return true }
            }
            return (0..<3).contains { distance(local, segment: points[$0], to: points[($0 + 1) % 3]) <= t }
        case .arc:
            let points = (0...40).map { index -> CGPoint in
                let angle = .pi + Double(index) * .pi / 40
                return CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.maxY + sin(angle) * rect.height)
            }
            return zip(points, points.dropFirst()).contains { distance(local, segment: $0, to: $1) <= t }
        }
    }
    private static func distance(_ p: CGPoint, segment a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, denominator = dx * dx + dy * dy
        if denominator < 0.0001 { return hypot(p.x - a.x, p.y - a.y) }
        let progress = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / denominator))
        return hypot(p.x - (a.x + progress * dx), p.y - (a.y + progress * dy))
    }
    private static func rotated(_ p: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        let angle = degrees * .pi / 180, dx = p.x - center.x, dy = p.y - center.y
        return CGPoint(x: center.x + dx * cos(angle) - dy * sin(angle), y: center.y + dx * sin(angle) + dy * cos(angle))
    }
    private static func rectangleEdges(_ rect: CGRect) -> [(CGPoint, CGPoint)] {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        return (0..<4).map { (corners[$0], corners[($0 + 1) % 4]) }
    }

    private func selectionBounds(_ board: Board) -> CGRect? {
        let selected = board.elements.filter { session.selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        return selected.reduce(CGRect.null) { result, element in
            let rect = element.bounds
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            let center = CGPoint(x: rect.midX, y: rect.midY)
            return corners.reduce(result) { $0.union(CGRect(origin: Self.rotated($1, around: center, degrees: element.rotation), size: .zero)) }
        }
    }
    private func corners(_ rect: CGRect) -> [CGPoint] { [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)] }
    private func cornerHit(_ point: CGPoint, rect: CGRect) -> Int? { corners(rect).firstIndex { hypot($0.x - point.x, $0.y - point.y) < 10 / session.zoom } }
    private func resizedElements(location: CGPoint, corner: Int, uniform: Bool) -> [DrawingElement] {
        let anchor = corners(initialSelectionRect)[(corner + 2) % 4], moving = corners(initialSelectionRect)[corner]
        var sx = (location.x - anchor.x) / (moving.x - anchor.x == 0 ? 1 : moving.x - anchor.x)
        var sy = (location.y - anchor.y) / (moving.y - anchor.y == 0 ? 1 : moving.y - anchor.y)
        sx = max(0.05, sx); sy = max(0.05, sy)
        if uniform { sx = max(sx, sy); sy = sx }
        return originals.map { source in
            var element = source
            element.points = source.points.map { p in var result = p; result.x = anchor.x + (p.x - anchor.x) * sx; result.y = anchor.y + (p.y - anchor.y) * sy; return result }
            if source.kind == .text { element.fontSize = max(4, min(400, source.fontSize * min(sx, sy))) }
            return element
        }
    }
    private func drawSelection(_ board: Board, context: CGContext) {
        guard let box = selectionBounds(board), !box.isNull else { return }
        context.saveGState(); context.setStrokeColor(NSColor.systemBlue.cgColor); context.setLineWidth(1.3 / session.zoom)
        context.setLineDash(phase: 0, lengths: [5 / session.zoom, 4 / session.zoom]); context.stroke(box)
        context.setLineDash(phase: 0, lengths: [])
        for point in corners(box) {
            let rect = CGRect(x: point.x - 4 / session.zoom, y: point.y - 4 / session.zoom, width: 8 / session.zoom, height: 8 / session.zoom)
            context.setFillColor(NSColor.white.cgColor); context.fill(rect); context.stroke(rect)
        }
        context.restoreGState()
    }

    private func updateMetalPreview() {
        let highlighting = previewElement?.kind == .stroke && previewElement?.pen == .highlighter && metalInk.available
        if highlighting {
            let changed = committedForeground.isHidden || foregroundRevision != session.revision || foregroundCamera != session.cameraOffset || foregroundZoom != session.zoom || foregroundSize != bounds.size
            committedForeground.isHidden = false
            if changed {
                foregroundRevision = session.revision; foregroundCamera = session.cameraOffset; foregroundZoom = session.zoom; foregroundSize = bounds.size
                committedForeground.board = session.board; committedForeground.camera = session.cameraOffset; committedForeground.zoom = session.zoom; committedForeground.needsDisplay = true
            }
        } else if !committedForeground.isHidden { committedForeground.isHidden = true; needsDisplay = true }
        metalInk.showInk(previewElement?.kind == .stroke ? previewElement : nil, zoom: session.zoom, camera: session.cameraOffset, board: session.board)
    }
    private func refreshSpatialIndex() {
        guard indexedRevision != session.revision else { return }
        let previous = elementMap, oldBounds = indexedBounds
        tileIndex = SpatialTileIndex(); elementMap.removeAll(keepingCapacity: true); elementOrder.removeAll(keepingCapacity: true); indexedBounds.removeAll(keepingCapacity: true)
        for (index, element) in session.board.elements.enumerated() {
            elementMap[element.id] = element; elementOrder[element.id] = index
            let rect = previous[element.id] == element ? (oldBounds[element.id] ?? visibleBounds(element)) : visibleBounds(element)
            indexedBounds[element.id] = rect
            tileIndex.upsert(id: element.id, bounds: rect)
        }
        indexedRevision = session.revision
    }
    private func cachedElements(in rect: CGRect) -> [DrawingElement] {
        tileIndex.query(rect).filter { indexedBounds[$0]?.intersects(rect) == true }
            .sorted { (elementOrder[$0] ?? 0) < (elementOrder[$1] ?? 0) }.compactMap { elementMap[$0] }
    }
    private var visibleWorldRect: CGRect {
        CGRect(origin: session.cameraOffset, size: CGSize(width: bounds.width / session.zoom, height: bounds.height / session.zoom))
    }
    private func visibleBounds(_ element: DrawingElement) -> CGRect {
        guard element.rotation != 0 else { return element.bounds }
        let rect = element.bounds, center = CGPoint(x: rect.midX, y: rect.midY)
        return corners(rect).reduce(CGRect.null) { $0.union(CGRect(origin: Self.rotated($1, around: center, degrees: element.rotation), size: .zero)) }
    }
    private func elementRect(_ element: DrawingElement) -> CGRect {
        guard let first = element.points.first, let last = element.points.last else { return .zero }
        return CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
    }
    private func startPlacedAnimation(element: DrawingElement, definition: SymbolDefinition) {
        let animationKey = "engineeringboard.symbolAnimations"
        if UserDefaults.standard.object(forKey: animationKey) != nil && !UserDefaults.standard.bool(forKey: animationKey) { return }
        guard definition.diagram.animated else { return }
        animationTimer?.invalidate()
        activeSymbolID = element.id; animationStart = Date.timeIntervalSinceReferenceDate
        let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(advancePlacedAnimation(_:)), userInfo: nil, repeats: true)
        animationTimer = timer; RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }
    @objc private func advancePlacedAnimation(_ timer: Timer) {
        let animationKey = "engineeringboard.symbolAnimations"
        let disabled = UserDefaults.standard.object(forKey: animationKey) != nil && !UserDefaults.standard.bool(forKey: animationKey)
        if disabled || Date.timeIntervalSinceReferenceDate - animationStart >= 1.5 {
            timer.invalidate(); animationTimer = nil; activeSymbolID = nil
        }
        needsDisplay = true
    }
    private func scheduleHold() {
        holdTimer?.invalidate(); holdTimer = nil
        guard session.autoShape, previewElement?.kind == .stroke else { return }
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(snapHeldInk(_:)), userInfo: nil, repeats: false)
        holdTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    @objc private func snapHeldInk(_ timer: Timer) {
        holdTimer = nil
        guard startPoint != nil, let original = previewElement, original.kind == .stroke else { return }
        var candidate = original
        if let end = currentPoint, let last = original.points.last, hypot(end.x - last.x, end.y - last.y) > 0.25 {
            var point = last; point.x = end.x; point.y = end.y; candidate.points.append(point)
        }
        let corrected = correctedShape(candidate)
        guard corrected.kind != .stroke else { return }
        rawInkBeforeHold = original; previewElement = corrected; heldShape = true; holdAnchor = currentPoint ?? corrected.points.last!.cg
        updateMetalPreview(); needsDisplay = true
        session.status = "Hold detected • \(corrected.kind.rawValue) snapped"
    }
    private func correctedShape(_ element: DrawingElement) -> DrawingElement {
        guard element.points.count >= 3, element.pen != .highlighter, element.pen != .airbrush else { return element }
        let points = element.points.map(\.cg), first = points[0], last = points.last!
        let raw = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let diagonal = hypot(raw.width, raw.height)
        guard diagonal * session.zoom > 20 else { return element }
        let pathLength = zip(points, points.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        let endDistance = hypot(first.x - last.x, first.y - last.y)
        var result = element
        if endDistance > diagonal * 0.75 && pathLength < endDistance * 1.14 && points.allSatisfy({ Self.distance($0, segment: first, to: last) < max(5 / session.zoom, diagonal * 0.05) }) {
            result.kind = .line; result.points = [element.points[0], element.points.last!]; return result
        }
        guard points.count >= 8, endDistance < diagonal * 0.22, pathLength > diagonal * 1.65 else { return element }
        let center = CGPoint(x: raw.midX, y: raw.midY), rx = raw.width / 2, ry = raw.height / 2
        guard rx * session.zoom > 8, ry * session.zoom > 8 else { return element }
        let ellipseError = points.reduce(0.0) { $0 + abs(hypot(($1.x - center.x) / rx, ($1.y - center.y) / ry) - 1) } / Double(points.count)
        let edgeError = points.reduce(0.0) { sum, point in sum + min(abs(point.x - raw.minX), abs(point.x - raw.maxX), abs(point.y - raw.minY), abs(point.y - raw.maxY)) } / Double(points.count)
        let coversCorners = corners(raw).allSatisfy { corner in points.contains { hypot($0.x - corner.x, $0.y - corner.y) < diagonal * 0.12 } }
        if coversCorners && edgeError < min(raw.width, raw.height) * 0.08 {
            result.kind = .rectangle
        } else if ellipseError < 0.11 {
            result.kind = .ellipse
        } else {
            let closed = points + [first]
            var simplified = simplify(closed, tolerance: diagonal * 0.06)
            if let final = simplified.last, hypot(first.x - final.x, first.y - final.y) < diagonal * 0.1 { simplified.removeLast() }
            if simplified.count == 3 {
                let twiceArea = abs((simplified[1].x - simplified[0].x) * (simplified[2].y - simplified[0].y) - (simplified[1].y - simplified[0].y) * (simplified[2].x - simplified[0].x))
                if twiceArea > diagonal * diagonal * 0.08 {
                    result.kind = .triangle; result.points = simplified.map { InkPoint(x: $0.x, y: $0.y) }; return result
                }
            }
            return element
        }
        result.points = [InkPoint(x: raw.minX, y: raw.minY), InkPoint(x: raw.maxX, y: raw.maxY)]
        return result
    }
    private func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var largest: CGFloat = 0, position = 0
        for index in 1..<(points.count - 1) {
            let value = Self.distance(points[index], segment: first, to: last)
            if value > largest { largest = value; position = index }
        }
        if largest > tolerance {
            let left = simplify(Array(points[...position]), tolerance: tolerance), right = simplify(Array(points[position...]), tolerance: tolerance)
            return Array(left.dropLast()) + right
        }
        return [first, last]
    }

    /// Pattern density adapts to zoom while remaining anchored in world coordinates.
    private func drawWorldBackground(_ rect: CGRect, context: CGContext) {
        let kind = session.board.background, dark = kind == .blueprint || kind == .dark
        let paper = kind == .blueprint ? NSColor(srgbRed: 0.075, green: 0.20, blue: 0.36, alpha: 1) : (kind == .dark ? NSColor(srgbRed: 0.10, green: 0.12, blue: 0.15, alpha: 1) : NSColor(srgbRed: 0.998, green: 0.994, blue: 0.98, alpha: 1))
        context.saveGState(); context.clip(to: rect); context.setFillColor(paper.cgColor); context.fill(rect)
        guard kind != .plain && kind != .dark else { context.restoreGState(); return }
        var spacing = max(8, min(session.board.gridSpacing, 200))
        while spacing * session.zoom < 8 { spacing *= 5 }
        let thin = dark ? NSColor.white.withAlphaComponent(0.13) : NSColor(srgbRed: 0.41, green: 0.57, blue: 0.67, alpha: 0.17)
        let strong = dark ? NSColor.white.withAlphaComponent(0.27) : NSColor(srgbRed: 0.30, green: 0.46, blue: 0.58, alpha: 0.26)
        context.setStrokeColor(thin.cgColor); context.setLineWidth(0.65 / session.zoom)
        func horizontal(_ step: Double) {
            for y in stride(from: floor(rect.minY / step) * step, through: rect.maxY, by: step) { context.move(to: CGPoint(x: rect.minX, y: y)); context.addLine(to: CGPoint(x: rect.maxX, y: y)) }
        }
        func vertical(_ step: Double) {
            for x in stride(from: floor(rect.minX / step) * step, through: rect.maxX, by: step) { context.move(to: CGPoint(x: x, y: rect.minY)); context.addLine(to: CGPoint(x: x, y: rect.maxY)) }
        }
        switch kind {
        case .plain, .dark: break
        case .lined: horizontal(spacing); context.strokePath()
        case .dots:
            context.setFillColor(strong.cgColor)
            let radius = 1 / session.zoom
            for x in stride(from: floor(rect.minX / spacing) * spacing, through: rect.maxX, by: spacing) {
                for y in stride(from: floor(rect.minY / spacing) * spacing, through: rect.maxY, by: spacing) { context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)) }
            }
        case .isometric:
            horizontal(spacing)
            for slope in [-sqrt(3.0), sqrt(3.0)] {
                let intercepts = corners(rect).map { $0.y - slope * $0.x }
                for intercept in stride(from: floor(intercepts.min()! / spacing) * spacing, through: intercepts.max()!, by: spacing) {
                    context.move(to: CGPoint(x: rect.minX, y: slope * rect.minX + intercept)); context.addLine(to: CGPoint(x: rect.maxX, y: slope * rect.maxX + intercept))
                }
            }
            context.strokePath()
        case .polar:
            let distances = corners(rect).map { hypot($0.x, $0.y) }, maximum = distances.max() ?? 1000
            let nearestX: CGFloat = rect.minX <= 0 && rect.maxX >= 0 ? 0 : min(abs(rect.minX), abs(rect.maxX))
            let nearestY: CGFloat = rect.minY <= 0 && rect.maxY >= 0 ? 0 : min(abs(rect.minY), abs(rect.maxY))
            let minimum = hypot(nearestX, nearestY)
            for radius in stride(from: max(spacing, floor(minimum / spacing) * spacing), through: maximum, by: spacing) { context.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)) }
            for degree in stride(from: 0.0, to: 360, by: 15) {
                let angle = degree * .pi / 180; context.move(to: .zero); context.addLine(to: CGPoint(x: cos(angle) * maximum, y: sin(angle) * maximum))
            }
            context.strokePath()
        case .grid, .graph, .engineering, .blueprint:
            let fine = kind == .graph && spacing / 5 * session.zoom >= 4 ? spacing / 5 : spacing
            horizontal(fine); vertical(fine); context.strokePath()
            if kind == .graph || kind == .engineering || kind == .blueprint {
                context.setStrokeColor(strong.cgColor); context.setLineWidth(1 / session.zoom)
                horizontal(spacing * 5); vertical(spacing * 5); context.strokePath()
            }
        }
        context.restoreGState()
    }

    private func drawRuler(_ context: CGContext) {
        let rect = CGRect(x: 36, y: 36, width: max(150, min(1000, bounds.width - 72)), height: 70)
        context.saveGState(); context.translateBy(x: session.cameraOffset.x, y: session.cameraOffset.y); context.scaleBy(x: 1 / session.zoom, y: 1 / session.zoom)
        context.setFillColor(NSColor(srgbRed: 0.92, green: 0.96, blue: 1, alpha: 0.84).cgColor); context.fill(rect)
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.6).cgColor); context.setLineWidth(1); context.stroke(rect)
        let step = session.board.pointsPerMM * session.zoom / max(0.0001, session.board.scaleDenominator)
        var increment = 1.0
        while increment * step < 8 { increment *= 10 }
        let minorStep = step * increment
        for x in stride(from: 0.0, through: Double(rect.width), by: minorStep) {
            let mm = x / max(0.0001, step)
            let major = abs(mm / 10 - (mm / 10).rounded()) < 0.001
            context.move(to: CGPoint(x: rect.minX + x, y: rect.minY)); context.addLine(to: CGPoint(x: rect.minX + x, y: rect.minY + (major ? 27 : 14)))
            if major { (BoardRenderer.formatted(mm) as NSString).draw(at: CGPoint(x: rect.minX + x + 3, y: rect.minY + 30), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.systemBlue]) }
        }
        context.strokePath()
        ("Ruler • real mm at 1:\(BoardRenderer.formatted(session.board.scaleDenominator)) • overlay only" as NSString).draw(at: CGPoint(x: rect.minX + 12, y: rect.maxY - 18), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemBlue])
        context.restoreGState()
    }
    private func drawProtractor(_ context: CGContext) {
        let radius: CGFloat = max(90, min(200, bounds.width / 2 - 35, bounds.height / 2 - 35))
        let center = CGPoint(x: bounds.midX, y: bounds.midY + radius / 2)
        context.saveGState(); context.translateBy(x: session.cameraOffset.x, y: session.cameraOffset.y); context.scaleBy(x: 1 / session.zoom, y: 1 / session.zoom)
        context.setFillColor(NSColor.systemTeal.withAlphaComponent(0.10).cgColor); context.setStrokeColor(NSColor.systemTeal.withAlphaComponent(0.70).cgColor); context.setLineWidth(1)
        context.addArc(center: center, radius: radius, startAngle: .pi, endAngle: 0, clockwise: false); context.closePath(); context.drawPath(using: .fillStroke)
        for degrees in stride(from: 0, through: 180, by: 5) {
            let angle = Double(degrees) * .pi / 180, inner = radius - (degrees % 10 == 0 ? 20 : 10)
            context.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y - sin(angle) * inner)); context.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y - sin(angle) * radius))
            if degrees % 30 == 0 {
                let text = "\(degrees)°", p = CGPoint(x: center.x + cos(angle) * (radius - 40) - 12, y: center.y - sin(angle) * (radius - 40) - 7)
                (text as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.systemTeal])
            }
        }
        context.strokePath(); context.fillEllipse(in: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
        ("Protractor • overlay only" as NSString).draw(at: CGPoint(x: center.x - 75, y: center.y + 12), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.systemTeal]); context.restoreGState()
    }
}

/// Native saved artwork above the live Metal highlighter. AppKit keeps this
/// viewport layer cached between input samples; it is absent for every other pen.
@MainActor
private final class CommittedInkForeground: NSView {
    var board: Board?
    var drawArtwork: ((CGRect, CGContext) -> Void)?
    var camera = CGPoint.zero
    var zoom: Double = 1
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true; layer?.isOpaque = false }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let board, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.clear(bounds)
        context.scaleBy(x: zoom, y: zoom); context.translateBy(x: -camera.x, y: -camera.y)
        let world = CGRect(origin: camera, size: CGSize(width: bounds.width / zoom, height: bounds.height / zoom))
        if let drawArtwork { drawArtwork(world, context) }
        else {
            for element in board.elements where !(element.kind == .stroke && element.pen == .highlighter) {
                if element.rotation != 0 || element.bounds.intersects(world) { BoardRenderer.draw(element: element, on: board, context: context) }
            }
        }
        context.restoreGState()
    }
}

/// A small composited cursor path. Hover never invalidates the completed board.
@MainActor
private final class PenHoverView: NSView {
    private let outline = CAShapeLayer()
    private let contrast = CAShapeLayer()
    private(set) var footprint = CGRect.zero
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.isOpaque = false; layer?.isGeometryFlipped = true
        contrast.fillColor = NSColor.clear.cgColor; contrast.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor; contrast.lineWidth = 3
        outline.lineWidth = 1; outline.lineJoin = .round
        layer?.addSublayer(contrast); layer?.addSublayer(outline); isHidden = true
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func hide() { isHidden = true }
    func present(at point: CGPoint, diameter: Double, tilt: CGPoint, color: NSColor, eraser: Bool, nib: Bool) {
        guard diameter.isFinite, diameter > 0, point.x.isFinite, point.y.isFinite else { hide(); return }
        let radius = min(4096, max(1.5, diameter / 2))
        let amount = min(1, hypot(tilt.x, tilt.y))
        let minor = radius * (nib ? 0.22 : 1 - amount * 0.45)
        let angle = nib ? Double.pi / 4 : atan2(tilt.y, tilt.x)
        let ellipse = CGPath(ellipseIn: CGRect(x: -radius, y: -minor, width: radius * 2, height: minor * 2), transform: nil)
        var transform = CGAffineTransform(translationX: point.x, y: point.y).rotated(by: angle)
        guard let path = ellipse.copy(using: &transform) else { hide(); return }
        footprint = path.boundingBoxOfPath
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for item in [contrast, outline] { item.path = path; item.contentsScale = window?.backingScaleFactor ?? 2 }
        outline.strokeColor = (eraser ? NSColor.secondaryLabelColor : color).cgColor
        outline.fillColor = (eraser ? NSColor.clear : color.withAlphaComponent(0.07)).cgColor
        outline.lineDashPattern = eraser ? [3, 3] : nil
        isHidden = false
        CATransaction.commit()
    }
}
