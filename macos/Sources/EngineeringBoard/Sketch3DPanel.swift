import SwiftUI
import AppKit
import SceneKit

@MainActor
final class Sketch3DViewport: ObservableObject {
    weak var view: Sketch3DSceneView?
    func snapshot() throws -> (Data, CGSize) {
        guard let view, view.window != nil, view.bounds.width >= 100, view.bounds.height >= 100,
              view.renderingAPI == .metal, view.device != nil else {
            throw BoardFileError.invalid("the 3D viewport is not ready. Wait for the scene to appear, then insert again.")
        }
        view.state?.finishStroke()
        view.synchronise()
        let image = view.snapshot()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw BoardFileError.invalid("the 3D viewport couldn't produce a PNG image.")
        }
        return (png, CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
    }
    func fit() {
        guard let view else { return }
        view.state?.fit(aspect: view.bounds.width / max(1, view.bounds.height))
        view.synchronise()
    }
}

@MainActor
struct Sketch3DPanel: View {
    @ObservedObject var session: DrawingSession
    @StateObject private var state: Sketch3DState
    @StateObject private var viewport = Sketch3DViewport()
    @Environment(\.dismiss) private var dismiss
    @State private var showAdvanced = false
    private let sourceID: UUID?

    init(session: DrawingSession) {
        self.session = session
        let source = session.selectedSketch3DElement
        sourceID = source?.locked == false ? source?.id : nil
        var initial = source?.sketch3D ?? .init()
        if source == nil { initial.plane = .xy; initial.camera.yaw = 0; initial.camera.pitch = 0 }
        let state = Sketch3DState(document: initial)
        state.configureDraft(boardID: session.board.id, sourceID: source?.id)
        _state = StateObject(wrappedValue: state)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "cube.transparent").font(.title2).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("3D Sketchbook").font(.headline)
                    Text("Choose a side, sketch on the grid, then look around in 3D").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("0.2 TEST").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
                Button("Done") { state.finishStroke(); dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            HStack(spacing: 12) {
                Button { sketchView() } label: { Label("Sketch", systemImage: "pencil.tip") }
                    .buttonStyle(.bordered).tint(state.mode == .draw ? .teal : .secondary).help("Look straight at the paper and draw")
                Button { threeDView() } label: { Label("Look around", systemImage: "cube.transparent") }
                    .buttonStyle(.bordered).tint(state.mode == .orbit ? .teal : .secondary).help("Drag to rotate your sketch")
                Divider().frame(height: 24)
                Picker("Draw on", selection: Binding(get: { state.document.plane }, set: {
                    state.setPlane($0); if state.mode == .draw { state.facePlane() }
                })) {
                    Text("Front").tag(Sketch3DPlane.xy)
                    Text("Top").tag(Sketch3DPlane.xz)
                    Text("Side").tag(Sketch3DPlane.yz)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 210).help("Choose which side to draw on")
                Button("Fit view") { viewport.fit() }.help("Bring the whole sketch into view")
                Spacer()
                Button { state.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!state.canUndo).help("Undo 3D change")
                Button { state.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!state.canRedo).help("Redo 3D change")
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Sketch3DSceneHost(state: state, viewport: viewport)
                    VStack(alignment: .leading, spacing: 4) {
                        Label(state.mode == .draw ? "Drag your pen to sketch" : "Drag to rotate · scroll to zoom", systemImage: state.mode == .draw ? "hand.draw" : "rotate.3d")
                        Text("\(planeName) · \(state.document.gridSpacing, specifier: "%.0f") mm squares").foregroundStyle(.secondary)
                    }.font(.caption).foregroundStyle(.primary).padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(12).allowsHitTesting(false)
                }
                Divider()
                inspector.frame(width: 238)
            }.frame(minHeight: 360)
            Divider()
            HStack(spacing: 14) {
                Text(state.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text("\(state.document.strokes.count) strokes · \(state.document.primitives.count) shapes").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.vertical, 9)
            Divider()
            HStack(spacing: 10) {
                Button("Open 3D…") { open() }
                Button("Save 3D…") { save() }
                Button("Clear") { state.clear() }.disabled(state.document.isEmpty)
                Spacer()
                Text("Concept sketches").font(.caption2).foregroundStyle(.secondary)
                Button(sourceID == nil ? "Insert on board" : "Update on board") { insert() }
                    .buttonStyle(.borderedProminent).disabled(state.document.isEmpty && state.activeStroke == nil)
            }.padding(14)
        }
        .frame(minWidth: 1_000, idealWidth: 1_180, minHeight: 700, idealHeight: 790)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("3D sketch", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .onDisappear { state.finishStroke(); state.saveDraft() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            state.finishStroke(); state.saveDraft()
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                TextField("Sketch title", text: Binding(get: { state.document.title }, set: { state.setTitle($0) })).textFieldStyle(.roundedBorder)
                Text("Your pen").font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach(Array(InkColor.palette.enumerated()), id: \.offset) { _, color in
                        Button { state.color = color; state.updateSelection(color: color) } label: {
                            Circle().fill(color.swift).frame(width: 23, height: 23)
                                .overlay(Circle().stroke(state.color == color ? Color.primary : .clear, lineWidth: 2).padding(-3))
                        }.buttonStyle(.plain).help("Set ink and selected object colour")
                    }
                }.padding(.vertical, 3)
                HStack {
                    Text("Width")
                    Spacer()
                    Text("\(state.width, specifier: "%.1f") mm").monospacedDigit()
                }.font(.caption)
                Slider(value: $state.width, in: 0.2...10, step: 0.1, onEditingChanged: { editing in
                    if !editing { state.updateSelection(width: state.width) }
                })
                Divider()
                Text("Add a shape").font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    ForEach(Sketch3DPrimitive.Kind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) { state.addPrimitive(kind); threeDView() }.font(.caption)
                    }
                }
                Divider()
                HStack {
                    Text("Objects").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { state.deleteSelection() } label: { Image(systemName: "trash") }.disabled(state.selectedID == nil).help("Remove the selected 3D object")
                }
                if state.document.isEmpty {
                    Text("Draw a stroke on the active plane or add a shape.").font(.caption).foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 3) {
                    ForEach(Array(state.document.strokes.enumerated()), id: \.element.id) { index, stroke in
                        objectRow(stroke.id, title: "Stroke \(index + 1)", detail: "\(stroke.points.count) points", icon: "scribble", color: stroke.color)
                    }
                    ForEach(Array(state.document.primitives.enumerated()), id: \.element.id) { index, primitive in
                        objectRow(primitive.id, title: "\(primitive.kind.rawValue) \(index + 1)", detail: "\(Int(primitive.size.x)) mm", icon: "cube", color: primitive.color)
                    }
                }
                if state.selectedPosition != nil {
                    Divider()
                    if let primitive = state.document.primitives.first(where: { $0.id == state.selectedID }) {
                        Text(primitive.kind == .box ? "Dimensions in mm" : primitive.kind == .cylinder ? "Diameter and height in mm" : "Diameter in mm").font(.caption.weight(.semibold))
                        dimensions(primitive)
                    }
                }
                Divider()
                DisclosureGroup("Depth and pen settings", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Move the drawing surface to add strokes at another depth.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Depth (mm)").font(.caption)
                            TextField("Depth in mm", value: Binding(get: { state.document.planeOffset }, set: { state.setOffset($0); if state.mode == .draw { state.facePlane() } }), format: .number.precision(.fractionLength(0...1))).textFieldStyle(.roundedBorder)
                        }
                        if state.selectedPosition != nil { Text("Object position (mm)").font(.caption); coordinates }
                        Toggle("Use pen pressure", isOn: $state.pressureEnabled).font(.caption)
                        Text("Mouse drawing uses a steady width. X, Y and Z axes are red, green and blue.").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                }.font(.caption)
                Text("Sketch → draw on a flat grid. Look around → rotate. Scroll to zoom; Shift-drag in Look around moves the view.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
    }

    private var planeName: String {
        switch state.document.plane { case .xy: return "Front (XY)"; case .xz: return "Top (XZ)"; case .yz: return "Side (YZ)" }
    }
    private func sketchView() { state.finishStroke(); state.mode = .draw; state.facePlane() }
    private func threeDView() {
        state.finishStroke()
        if state.mode != .orbit {
            var camera = state.document.camera; camera.yaw = 0.65; camera.pitch = 0.5; state.setCamera(camera)
        }
        state.mode = .orbit
    }

    private func objectRow(_ id: UUID, title: String, detail: String, icon: String, color: InkColor) -> some View {
        Button {
            state.finishStroke(); state.selectedID = id
            state.color = color
            if let stroke = state.document.strokes.first(where: { $0.id == id }) { state.width = stroke.width }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(color.swift)
                Text(title)
                Spacer()
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }.font(.caption).padding(7).contentShape(Rectangle())
                .background(state.selectedID == id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
    private var coordinates: some View {
        HStack(spacing: 6) {
            ForEach(["X", "Y", "Z"], id: \.self) { axis in
                VStack(alignment: .leading, spacing: 3) {
                    Text(axis).font(.caption2).foregroundStyle(.secondary)
                    TextField(axis, value: Binding(get: {
                        let p = state.selectedPosition ?? .zero
                        return axis == "X" ? p.x : axis == "Y" ? p.y : p.z
                    }, set: { value in
                        guard var p = state.selectedPosition else { return }
                        if axis == "X" { p.x = value } else if axis == "Y" { p.y = value } else { p.z = value }
                        state.setPosition(p)
                    }), format: .number.precision(.fractionLength(0...1))).textFieldStyle(.roundedBorder)
                }
            }
        }
    }
    private func dimensions(_ primitive: Sketch3DPrimitive) -> some View {
        HStack(spacing: 6) {
            ForEach(primitive.kind == .box ? ["X", "Y", "Z"] : primitive.kind == .cylinder ? ["Ø", "H"] : ["Ø"], id: \.self) { axis in
                VStack(alignment: .leading, spacing: 3) {
                    Text(axis).font(.caption2).foregroundStyle(.secondary)
                    TextField(axis, value: Binding(get: {
                        let size = state.document.primitives.first(where: { $0.id == primitive.id })?.size ?? primitive.size
                        return axis == "Y" || axis == "H" ? size.y : axis == "Z" ? size.z : size.x
                    }, set: { value in
                        var size = state.document.primitives.first(where: { $0.id == primitive.id })?.size ?? primitive.size
                        if axis == "Y" || axis == "H" { size.y = value } else if axis == "Z" { size.z = value } else { size.x = value }
                        if primitive.kind == .sphere { size.y = size.x; size.z = size.x }
                        if primitive.kind == .cylinder { size.z = size.x }
                        state.updateSelection(size: size)
                    }), format: .number.precision(.fractionLength(0...1))).textFieldStyle(.roundedBorder)
                }
            }
        }
    }
    private func open() {
        state.finishStroke()
        let panel = NSOpenPanel(); panel.allowedContentTypes = [Sketch3DFile.fileType, .json]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Open a .karim3d sketch. It replaces this scene; Undo restores it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { state.load(try Sketch3DFile.read(url)); state.status = "Opened \(url.lastPathComponent)." }
        catch { state.error = error.localizedDescription }
    }
    private func save() {
        state.finishStroke()
        let panel = NSSavePanel(); panel.allowedContentTypes = [Sketch3DFile.fileType]; panel.canCreateDirectories = true
        panel.nameFieldStringValue = BoardFile.filename(for: state.document.title, extension: "karim3d")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Sketch3DFile.encode(state.document).write(to: url, options: .atomic); state.status = "Saved \(url.lastPathComponent)." }
        catch { state.error = error.localizedDescription }
    }
    private func insert() {
        do {
            let (png, size) = try viewport.snapshot()
            try session.insertSketch3D(state.document, png: png, imageSize: size, replacing: sourceID)
            state.discardInsertedDraft()
            dismiss()
        } catch { state.error = error.localizedDescription }
    }
}

@MainActor
struct Sketch3DSceneHost: NSViewRepresentable {
    @ObservedObject var state: Sketch3DState
    var viewport: Sketch3DViewport
    func makeNSView(context: Context) -> Sketch3DSceneView {
        let view = Sketch3DSceneView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.state = state; viewport.view = view; view.configure(); view.synchronise()
        return view
    }
    func updateNSView(_ view: Sketch3DSceneView, context: Context) { view.state = state; viewport.view = view; view.synchronise() }
    static func dismantleNSView(_ view: Sketch3DSceneView, coordinator: ()) { view.state?.finishStroke(); view.state = nil }
}

@MainActor
final class Sketch3DSceneView: SCNView {
    weak var state: Sketch3DState?
    private let objects = SCNNode(), grid = SCNNode(), cameraNode = SCNNode()
    private var preview: SCNNode?
    private var lastStrokes: [Sketch3DStroke] = []
    private var lastPrimitives: [Sketch3DPrimitive] = []
    private var lastSelection: UUID?
    private var objectNodes: [UUID: SCNNode] = [:]
    private var strokeModels: [UUID: Sketch3DStroke] = [:]
    private var primitiveModels: [UUID: Sketch3DPrimitive] = [:]
    private var lastCamera: Sketch3DCamera?
    private(set) var geometryBuilds = 0
    private var lastPlane: Sketch3DPlane?
    private var lastOffset: Double?
    private var lastSpacing: Double?
    private var lastPreview: Sketch3DStroke?
    private var gesture: Sketch3DState.Mode?
    private var lastMouse = CGPoint.zero
    override var acceptsFirstResponder: Bool { true }

    func configure() {
        scene = SCNScene()
        updateCanvasAppearance()
        allowsCameraControl = false; autoenablesDefaultLighting = false
        antialiasingMode = .multisampling4X
        isPlaying = false; rendersContinuously = false; preferredFramesPerSecond = 120
        scene?.rootNode.addChildNode(objects); scene?.rootNode.addChildNode(grid)
        let camera = SCNCamera(); camera.fieldOfView = 45; camera.zNear = 0.1; camera.zFar = 100_000
        cameraNode.camera = camera; scene?.rootNode.addChildNode(cameraNode); pointOfView = cameraNode
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 650; scene?.rootNode.addChildNode(ambient)
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .omni; light.light?.intensity = 900; light.position = SCNVector3(200, 400, 300); scene?.rootNode.addChildNode(light)
        for (end, color) in [(Sketch3DPoint(x: 80, y: 0, z: 0), NSColor.systemRed), (Sketch3DPoint(x: 0, y: 80, z: 0), NSColor.systemGreen), (Sketch3DPoint(x: 0, y: 0, z: 80), NSColor.systemBlue)] {
            scene?.rootNode.addChildNode(Sketch3DGeometry.line(.zero, end, color: color))
        }
    }
    private func updateCanvasAppearance() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        backgroundColor = dark ? NSColor(srgbRed: 0.075, green: 0.10, blue: 0.15, alpha: 1)
            : NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1)
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateCanvasAppearance() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); updateCanvasAppearance()
        preferredFramesPerSecond = min(120, window?.screen?.maximumFramesPerSecond ?? 60)
    }
    func synchronise() {
        guard let state else { return }
        let document = state.document
        let changedObjects = lastStrokes != document.strokes || lastPrimitives != document.primitives || lastSelection != state.selectedID
        let changedGrid = lastPlane != document.plane || lastOffset != document.planeOffset || lastSpacing != document.gridSpacing
        let changedPreview = lastPreview != state.activeStroke
        let changedCamera = lastCamera != document.camera
        guard changedObjects || changedGrid || changedPreview || changedCamera else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0; SCNTransaction.disableActions = true
        if changedObjects {
            let ids = Set(document.strokes.map(\.id) + document.primitives.map(\.id))
            for id in Array(objectNodes.keys) where !ids.contains(id) {
                objectNodes.removeValue(forKey: id)?.removeFromParentNode(); strokeModels.removeValue(forKey: id); primitiveModels.removeValue(forKey: id)
            }
            for stroke in document.strokes {
                let selectionChanged = lastSelection != state.selectedID && (stroke.id == lastSelection || stroke.id == state.selectedID)
                if strokeModels[stroke.id] != stroke || selectionChanged {
                    objectNodes[stroke.id]?.removeFromParentNode()
                    let node = Sketch3DGeometry.stroke(stroke, selected: stroke.id == state.selectedID); node.name = stroke.id.uuidString; objects.addChildNode(node)
                    objectNodes[stroke.id] = node; strokeModels[stroke.id] = stroke; geometryBuilds += 1
                }
            }
            for primitive in document.primitives {
                let selectionChanged = lastSelection != state.selectedID && (primitive.id == lastSelection || primitive.id == state.selectedID)
                if primitiveModels[primitive.id] != primitive || selectionChanged {
                    objectNodes[primitive.id]?.removeFromParentNode()
                    let node = Sketch3DGeometry.primitive(primitive, selected: primitive.id == state.selectedID); node.name = primitive.id.uuidString; objects.addChildNode(node)
                    objectNodes[primitive.id] = node; primitiveModels[primitive.id] = primitive; geometryBuilds += 1
                }
            }
            lastStrokes = document.strokes; lastPrimitives = document.primitives; lastSelection = state.selectedID
        }
        if changedGrid {
            grid.childNodes.forEach { $0.removeFromParentNode() }
            let extent = document.gridSpacing * 10
            for i in -10...10 {
                let value = Double(i) * document.gridSpacing
                let color = NSColor.gray.withAlphaComponent(i == 0 ? 0.5 : 0.23)
                grid.addChildNode(Sketch3DGeometry.line(document.plane.point(value, -extent, offset: document.planeOffset), document.plane.point(value, extent, offset: document.planeOffset), color: color))
                grid.addChildNode(Sketch3DGeometry.line(document.plane.point(-extent, value, offset: document.planeOffset), document.plane.point(extent, value, offset: document.planeOffset), color: color))
            }
            lastPlane = document.plane; lastOffset = document.planeOffset; lastSpacing = document.gridSpacing
        }
        if changedPreview {
            preview?.removeFromParentNode(); preview = nil
            if let stroke = state.activeStroke { preview = Sketch3DGeometry.stroke(stroke); if let preview { scene?.rootNode.addChildNode(preview) } }
            lastPreview = state.activeStroke
        }
        let camera = document.camera
        let offset = Sketch3DPoint(x: sin(camera.yaw) * cos(camera.pitch), y: sin(camera.pitch), z: cos(camera.yaw) * cos(camera.pitch)) * camera.distance
        cameraNode.position = (camera.target + offset).vector
        cameraNode.look(at: camera.target.vector)
        lastCamera = camera
        SCNTransaction.commit()
        needsDisplay = true
    }
    func drawingPoint(at location: CGPoint, pressure: Double) -> Sketch3DPoint? {
        guard let state, bounds.width > 0, bounds.height > 0, bounds.contains(location) else { return nil }
        let near = unprojectPoint(SCNVector3(location.x, location.y, 0)), far = unprojectPoint(SCNVector3(location.x, location.y, 1))
        guard var point = state.document.plane.intersect(near: .init(x: Double(near.x), y: Double(near.y), z: Double(near.z)), far: .init(x: Double(far.x), y: Double(far.y), z: Double(far.z)), offset: state.document.planeOffset) else { return nil }
        point.pressure = max(0, min(1, pressure.isFinite ? pressure : 1)); return point
    }
    private func eventPressure(_ event: NSEvent) -> Double {
        guard state?.pressureEnabled == true else { return 1 }
        return event.subtype == .tabletPoint ? max(0, min(1, Double(event.pressure))) : 1
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastMouse = convert(event.locationInWindow, from: nil)
        gesture = event.modifierFlags.contains(.option) ? .orbit : state?.mode
        if gesture == .draw {
            if let point = drawingPoint(at: lastMouse, pressure: eventPressure(event)) {
                state?.beginStroke(at: point); state?.status = "Drawing on \(state!.document.plane.rawValue) · coordinates in mm"
            } else { state?.status = "The camera is parallel to the drawing plane. Choose Face plane." }
        }
        synchronise()
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if gesture == .draw {
            if let world = drawingPoint(at: point, pressure: eventPressure(event)) { state?.appendPoint(world) }
        } else if gesture == .orbit { orbit(point, pan: event.modifierFlags.contains(.shift)) }
        lastMouse = point; synchronise()
    }
    override func mouseUp(with event: NSEvent) {
        if gesture == .draw { state?.finishStroke() }; gesture = nil; synchronise()
    }
    override func rightMouseDown(with event: NSEvent) {
        state?.finishStroke(); gesture = .orbit; lastMouse = convert(event.locationInWindow, from: nil)
    }
    override func rightMouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil); orbit(point, pan: event.modifierFlags.contains(.shift)); lastMouse = point; synchronise()
    }
    override func rightMouseUp(with event: NSEvent) { gesture = nil }
    override func scrollWheel(with event: NSEvent) {
        guard var camera = state?.document.camera else { return }
        state?.finishStroke()
        let delta = max(-100, min(100, event.scrollingDeltaY))
        camera.distance = max(20, min(60_000, camera.distance * exp(delta * 0.015))); state?.setCamera(camera); synchronise()
    }
    private func orbit(_ point: CGPoint, pan: Bool) {
        guard var camera = state?.document.camera else { return }
        let dx = Double(point.x - lastMouse.x), dy = Double(point.y - lastMouse.y)
        if pan {
            let right = Sketch3DPoint(x: cos(camera.yaw), y: 0, z: -sin(camera.yaw))
            let up = Sketch3DPoint(x: -sin(camera.yaw) * sin(camera.pitch), y: cos(camera.pitch), z: -cos(camera.yaw) * sin(camera.pitch))
            let scale = camera.distance / max(100, Double(bounds.height)) * 0.8
            camera.target = camera.target - right * (dx * scale) - up * (dy * scale)
        } else {
            camera.yaw = (camera.yaw - dx * 0.008).truncatingRemainder(dividingBy: 2 * .pi)
            camera.pitch = max(-1.49, min(1.49, camera.pitch + dy * 0.008))
        }
        state?.setCamera(camera)
    }
}
