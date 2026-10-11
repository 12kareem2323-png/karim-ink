import AppKit
import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct Sketch3DPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double
    var pressure: Double = 1
    static let zero = Sketch3DPoint(x: 0, y: 0, z: 0)
    var vector: SCNVector3 { SCNVector3(x, y, z) }
    var length: Double { sqrt(x * x + y * y + z * z) }
    static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: Self, b: Double) -> Self { .init(x: a.x * b, y: a.y * b, z: a.z * b) }
    func dot(_ b: Self) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: Self) -> Self { .init(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x) }
    var normalised: Self { length > 0.000001 ? self * (1 / length) : .init(x: 0, y: 1, z: 0) }
}

enum Sketch3DPlane: String, Codable, CaseIterable {
    case xy = "XY", xz = "XZ", yz = "YZ"
    var normal: Sketch3DPoint {
        switch self { case .xy: return .init(x: 0, y: 0, z: 1); case .xz: return .init(x: 0, y: 1, z: 0); case .yz: return .init(x: 1, y: 0, z: 0) }
    }
    var depthAxis: String { switch self { case .xy: return "Z"; case .xz: return "Y"; case .yz: return "X" } }
    func point(_ u: Double, _ v: Double, offset: Double) -> Sketch3DPoint {
        switch self { case .xy: return .init(x: u, y: v, z: offset); case .xz: return .init(x: u, y: offset, z: v); case .yz: return .init(x: offset, y: u, z: v) }
    }
    /// Intersects the finite camera ray with the active drawing plane in millimetres.
    func intersect(near: Sketch3DPoint, far: Sketch3DPoint, offset: Double) -> Sketch3DPoint? {
        let direction = far - near
        let denominator = direction.dot(normal)
        guard denominator.isFinite, abs(denominator) > 0.00000001 else { return nil }
        let fraction = (offset - near.dot(normal)) / denominator
        guard fraction.isFinite, (0...1).contains(fraction) else { return nil }
        let result = near + direction * fraction
        guard [result.x, result.y, result.z].allSatisfy({ $0.isFinite && abs($0) <= Sketch3DFile.coordinateLimit }) else { return nil }
        return result
    }
}

struct Sketch3DStroke: Codable, Identifiable, Equatable {
    var id = UUID()
    var points: [Sketch3DPoint]
    var color: InkColor = .blue
    var width: Double = 2
}

struct Sketch3DPrimitive: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case box = "Box", cylinder = "Cylinder", sphere = "Sphere" }
    var id = UUID()
    var kind: Kind
    var center: Sketch3DPoint = .zero
    /// XYZ dimensions in mm. Cylinders and spheres use X as their diameter.
    var size = Sketch3DPoint(x: 40, y: 40, z: 40)
    var color: InkColor = .teal
}

struct Sketch3DCamera: Codable, Equatable {
    var yaw: Double = 0.65
    var pitch: Double = 0.5
    var distance: Double = 360
    var target: Sketch3DPoint = .zero
}

struct Sketch3DDocument: Codable, Equatable {
    var version = 1
    var title = "3D sketch"
    var units = "mm"
    var plane: Sketch3DPlane = .xz
    var planeOffset: Double = 0
    var gridSpacing: Double = 10
    var strokes: [Sketch3DStroke] = []
    var primitives: [Sketch3DPrimitive] = []
    var camera = Sketch3DCamera()
    var isEmpty: Bool { strokes.isEmpty && primitives.isEmpty }
}

enum Sketch3DFile {
    static let fileType = UTType(exportedAs: "com.karim.engineeringboard.sketch3d", conformingTo: .json)
    static let maximumBytes = 16 * 1024 * 1024
    static let coordinateLimit: Double = 10_000
    static let maximumStrokes = 200
    static let maximumPoints = 40_000
    static let maximumPointsPerStroke = 4_096
    static let maximumPrimitives = 100

    static func validate(_ document: Sketch3DDocument) throws {
        func invalid(_ reason: String) -> BoardFileError { .invalid("3D sketch: " + reason) }
        guard document.version == 1, document.units == "mm" else { throw invalid("unsupported file version or coordinate units.") }
        guard document.title.utf8.count <= 1_024 else { throw invalid("the title is too long.") }
        guard document.planeOffset.isFinite, abs(document.planeOffset) <= coordinateLimit,
              document.gridSpacing.isFinite, (1...1_000).contains(document.gridSpacing) else { throw invalid("invalid drawing plane or grid.") }
        func validPoint(_ point: Sketch3DPoint) -> Bool {
            [point.x, point.y, point.z].allSatisfy { $0.isFinite && abs($0) <= coordinateLimit } && point.pressure.isFinite && (0...1).contains(point.pressure)
        }
        func validColor(_ color: InkColor) -> Bool { [color.r, color.g, color.b, color.a].allSatisfy { $0.isFinite && (0...1).contains($0) } }
        let camera = document.camera
        guard camera.yaw.isFinite, abs(camera.yaw) <= 1_000,
              camera.pitch.isFinite, abs(camera.pitch) <= 1.5,
              camera.distance.isFinite, (20...60_000).contains(camera.distance), validPoint(camera.target) else { throw invalid("invalid camera.") }
        guard document.strokes.count <= maximumStrokes, document.primitives.count <= maximumPrimitives else { throw invalid("too many objects (200 strokes or 100 shapes maximum).") }
        var identifiers = Set<UUID>()
        var points = 0
        for stroke in document.strokes {
            points += stroke.points.count
            guard identifiers.insert(stroke.id).inserted, !stroke.points.isEmpty,
                  stroke.points.count <= maximumPointsPerStroke, points <= maximumPoints,
                  stroke.points.allSatisfy(validPoint), validColor(stroke.color),
                  stroke.width.isFinite, (0.2...10).contains(stroke.width) else { throw invalid("invalid or oversized stroke.") }
        }
        for primitive in document.primitives {
            guard identifiers.insert(primitive.id).inserted, validPoint(primitive.center), validColor(primitive.color),
                  [primitive.size.x, primitive.size.y, primitive.size.z].allSatisfy({ $0.isFinite && (1...2_000).contains($0) }) else { throw invalid("invalid shape dimensions, position or colour.") }
        }
    }

    static func encode(_ document: Sketch3DDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw BoardFileError.invalid("the 3D file exceeds 16 MB.") }
        return data
    }

    static func decode(_ data: Data) throws -> Sketch3DDocument {
        guard data.count <= maximumBytes else { throw BoardFileError.invalid("the 3D file exceeds 16 MB.") }
        let document = try JSONDecoder().decode(Sketch3DDocument.self, from: data)
        try validate(document)
        return document
    }

    static func read(_ url: URL) throws -> Sketch3DDocument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw BoardFileError.invalid("the 3D file exceeds 16 MB.") }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }
}

@MainActor
final class Sketch3DState: ObservableObject {
    enum Mode: String, CaseIterable { case draw = "Draw", orbit = "Orbit" }
    @Published private(set) var document: Sketch3DDocument
    @Published var mode: Mode = .draw
    @Published var color: InkColor = .blue
    @Published var width: Double = 2
    @Published var pressureEnabled = true
    @Published var selectedID: UUID?
    @Published private(set) var activeStroke: Sketch3DStroke?
    @Published var status = "Draw on the grid. Right-drag to orbit; scroll to zoom."
    @Published var error: String?
    @Published private(set) var revision = 0
    private var undoStack: [Sketch3DDocument] = []
    private var redoStack: [Sketch3DDocument] = []
    private var draftURL: URL?
    private var draftFingerprint: Data?
    private var draftBlocked = false
    private var lastDraftSave = Date.distantPast
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var pointCount: Int { document.strokes.reduce(0) { $0 + $1.points.count } }
    init(document: Sketch3DDocument = .init()) {
        if (try? Sketch3DFile.validate(document)) != nil { self.document = document }
        else { self.document = .init(); self.error = "The selected 3D scene is invalid and couldn't be opened." }
    }

    func commit(_ next: Sketch3DDocument) {
        guard next != document else { return }
        do {
            try Sketch3DFile.validate(next)
            undoStack.append(document)
            if undoStack.count > 30 { undoStack.removeFirst() }
            redoStack.removeAll(); document = next; revision += 1; saveDraft()
        } catch { self.error = error.localizedDescription }
    }
    func undo() {
        finishStroke()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document); document = previous; selectedID = nil; revision += 1; saveDraft()
    }
    func redo() {
        finishStroke()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document); document = next; selectedID = nil; revision += 1; saveDraft()
    }
    func clear() {
        finishStroke(); var next = document; next.strokes = []; next.primitives = []; commit(next); selectedID = nil
    }
    func load(_ next: Sketch3DDocument) { finishStroke(); commit(next); selectedID = nil }
    func setPlane(_ plane: Sketch3DPlane) { finishStroke(); var next = document; next.plane = plane; commit(next) }
    func setOffset(_ offset: Double) { finishStroke(); var next = document; next.planeOffset = offset; commit(next) }
    func setTitle(_ title: String) { var next = document; next.title = title; commit(next) }
    func setCamera(_ camera: Sketch3DCamera) {
        // A camera drag cannot change any saved object. Validate only its new
        // values, instead of scanning up to 40,000 geometry points each event.
        guard camera != document.camera, camera.yaw.isFinite, abs(camera.yaw) <= 1_000,
              camera.pitch.isFinite, abs(camera.pitch) <= 1.5,
              camera.distance.isFinite, (20...60_000).contains(camera.distance),
              [camera.target.x, camera.target.y, camera.target.z].allSatisfy({ $0.isFinite && abs($0) <= Sketch3DFile.coordinateLimit }),
              camera.target.pressure.isFinite, (0...1).contains(camera.target.pressure) else { return }
        document.camera = camera
    }

    func beginStroke(at point: Sketch3DPoint) {
        guard document.strokes.count < Sketch3DFile.maximumStrokes, pointCount < Sketch3DFile.maximumPoints else {
            status = "Scene limit reached. Remove an object or open a new 3D sketch."; return
        }
        selectedID = nil
        let stroke = Sketch3DStroke(points: [point], color: color, width: width)
        var candidate = document; candidate.strokes.append(stroke)
        guard (try? Sketch3DFile.validate(candidate)) != nil else { status = "This pen point or width is outside the scene limits."; return }
        activeStroke = stroke; saveDraft(includeActiveStroke: true)
    }
    func appendPoint(_ point: Sketch3DPoint) {
        guard var stroke = activeStroke, let last = stroke.points.last else { return }
        guard [point.x, point.y, point.z].allSatisfy({ $0.isFinite && abs($0) <= Sketch3DFile.coordinateLimit }),
              point.pressure.isFinite, (0...1).contains(point.pressure) else { return }
        guard stroke.points.count < Sketch3DFile.maximumPointsPerStroke, pointCount + stroke.points.count < Sketch3DFile.maximumPoints else {
            status = "Stroke point limit reached. Lift the pen and start another stroke."; return
        }
        guard (point - last).length >= 0.25 else { return }
        stroke.points.append(point); activeStroke = stroke
        if Date().timeIntervalSince(lastDraftSave) >= 0.75 { saveDraft(includeActiveStroke: true) }
    }
    func finishStroke() {
        guard let stroke = activeStroke else { return }
        activeStroke = nil
        var next = document; next.strokes.append(stroke); commit(next)
    }
    func addPrimitive(_ kind: Sketch3DPrimitive.Kind) {
        finishStroke(); var next = document
        let primitive = Sketch3DPrimitive(kind: kind, center: document.plane.point(0, 20, offset: document.planeOffset), color: color)
        next.primitives.append(primitive); commit(next)
        if document.primitives.contains(where: { $0.id == primitive.id }) { selectedID = primitive.id }
    }
    func deleteSelection() {
        guard let id = selectedID else { return }
        var next = document; next.strokes.removeAll { $0.id == id }; next.primitives.removeAll { $0.id == id }; commit(next); selectedID = nil
    }
    var selectedPosition: Sketch3DPoint? {
        if let primitive = document.primitives.first(where: { $0.id == selectedID }) { return primitive.center }
        if let stroke = document.strokes.first(where: { $0.id == selectedID }), let first = stroke.points.first {
            let bounds = stroke.points.reduce((first, first)) { pair, point in
                (.init(x: min(pair.0.x, point.x), y: min(pair.0.y, point.y), z: min(pair.0.z, point.z)),
                 .init(x: max(pair.1.x, point.x), y: max(pair.1.y, point.y), z: max(pair.1.z, point.z)))
            }
            return (bounds.0 + bounds.1) * 0.5
        }
        return nil
    }
    func setPosition(_ position: Sketch3DPoint) {
        guard let id = selectedID, let old = selectedPosition else { return }
        let delta = position - old
        var next = document
        if let i = next.primitives.firstIndex(where: { $0.id == id }) { next.primitives[i].center = position }
        if let i = next.strokes.firstIndex(where: { $0.id == id }) {
            next.strokes[i].points = next.strokes[i].points.map { point in var p = point + delta; p.pressure = point.pressure; return p }
        }
        commit(next)
    }
    func updateSelection(color: InkColor? = nil, width: Double? = nil, size: Sketch3DPoint? = nil) {
        guard let id = selectedID else { return }
        var next = document
        if let i = next.strokes.firstIndex(where: { $0.id == id }) {
            if let color { next.strokes[i].color = color }; if let width { next.strokes[i].width = width }
        }
        if let i = next.primitives.firstIndex(where: { $0.id == id }) {
            if let color { next.primitives[i].color = color }; if let size { next.primitives[i].size = size }
        }
        commit(next)
    }
    func facePlane() {
        var camera = document.camera
        switch document.plane { case .xy: camera.yaw = 0; camera.pitch = 0; case .xz: camera.yaw = 0; camera.pitch = 1.49; case .yz: camera.yaw = .pi / 2; camera.pitch = 0 }
        camera.target = document.plane.point(0, 0, offset: document.planeOffset); setCamera(camera)
    }
    func fit(aspect: Double = 1.5) {
        var points = document.strokes.flatMap(\.points)
        for primitive in document.primitives {
            let half = primitive.size * 0.5; points.append(primitive.center - half); points.append(primitive.center + half)
        }
        var camera = document.camera
        if let first = points.first {
            let bounds = points.reduce((first, first)) { pair, p in
                (.init(x: min(pair.0.x, p.x), y: min(pair.0.y, p.y), z: min(pair.0.z, p.z)), .init(x: max(pair.1.x, p.x), y: max(pair.1.y, p.y), z: max(pair.1.z, p.z)))
            }
            camera.target = (bounds.0 + bounds.1) * 0.5
            let radius = max(35, (bounds.1 - bounds.0).length / 2 + 10)
            camera.distance = min(60_000, max(120, radius / sin(22.5 * .pi / 180) * 1.2 / min(1, max(0.25, aspect))))
        } else { camera = .init(); camera.target = document.plane.point(0, 0, offset: document.planeOffset) }
        setCamera(camera)
    }

    /// Separate drafts protect scene work before a PNG is inserted into a board.
    /// A changed or corrupt draft is preserved, never silently replaced.
    func configureDraft(boardID: UUID, sourceID: UUID?, directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EngineeringBoard/3D Drafts", isDirectory: true)
        draftURL = base.appendingPathComponent("\(boardID.uuidString)-\(sourceID?.uuidString ?? "new").karim3d")
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            if let data = try draftData() {
                let recovered = try Sketch3DFile.decode(data)
                draftFingerprint = data
                if recovered != document { undoStack.append(document); document = recovered; revision += 1 }
                status = "Recovered your previous 3D draft. Undo returns to the board's saved scene."
            }
        } catch {
            draftBlocked = true
            self.error = "The existing 3D draft has been kept untouched. Automatic draft recovery is unavailable; use Save 3D to keep your work. \(error.localizedDescription)"
        }
    }
    private func draftData() throws -> Data? {
        guard let draftURL, FileManager.default.fileExists(atPath: draftURL.path) else { return nil }
        let size = try draftURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Sketch3DFile.maximumBytes else { throw BoardFileError.invalid("the draft exceeds 16 MB.") }
        let data = try Data(contentsOf: draftURL)
        guard data.count <= Sketch3DFile.maximumBytes else { throw BoardFileError.invalid("the draft exceeds 16 MB.") }
        return data
    }
    func saveDraft(includeActiveStroke: Bool = false) {
        guard let draftURL, !draftBlocked else { return }
        do {
            guard try draftData() == draftFingerprint else { throw BoardFileError.invalid("another window or app changed the draft file.") }
            var recovered = document
            if includeActiveStroke, let activeStroke { recovered.strokes.append(activeStroke) }
            let data = try Sketch3DFile.encode(recovered)
            try data.write(to: draftURL, options: .atomic)
            draftFingerprint = data; lastDraftSave = Date()
        } catch {
            draftBlocked = true
            self.error = "Automatic 3D draft saving stopped. The existing file has been preserved; use Save 3D to keep your changes. \(error.localizedDescription)"
        }
    }
    func discardInsertedDraft() {
        guard let draftURL, !draftBlocked else { return }
        do {
            guard try draftData() == draftFingerprint else { return }
            if draftFingerprint != nil { try FileManager.default.removeItem(at: draftURL) }
            self.draftURL = nil; draftFingerprint = nil
        } catch { status = "Inserted on the board; the recovery draft couldn't be removed." }
    }
}

/// Builds real 3D tube geometry; one SceneKit node per stroke, with bounded rings.
enum Sketch3DGeometry {
    static func material(_ color: InkColor, selected: Bool = false) -> SCNMaterial {
        let material = SCNMaterial(); material.diffuse.contents = color.ns
        material.roughness.contents = 0.7
        material.emission.contents = selected ? color.ns.withAlphaComponent(0.28) : NSColor.black
        material.isDoubleSided = true
        return material
    }
    static func stroke(_ stroke: Sketch3DStroke, selected: Bool = false) -> SCNNode {
        guard stroke.points.count > 1 else {
            let geometry = SCNSphere(radius: stroke.width / 2 * max(0.15, stroke.points.first?.pressure ?? 1)); geometry.segmentCount = 12
            geometry.materials = [material(stroke.color, selected: selected)]
            let node = SCNNode(geometry: geometry); node.position = stroke.points.first?.vector ?? SCNVector3Zero; return node
        }
        let sides = 8
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        for (i, point) in stroke.points.enumerated() {
            let tangent = (stroke.points[min(i + 1, stroke.points.count - 1)] - stroke.points[max(0, i - 1)]).normalised
            let reference = abs(tangent.y) < 0.9 ? Sketch3DPoint(x: 0, y: 1, z: 0) : Sketch3DPoint(x: 1, y: 0, z: 0)
            let u = tangent.cross(reference).normalised, v = tangent.cross(u).normalised
            let radius = stroke.width / 2 * (0.15 + 0.85 * point.pressure)
            for side in 0..<sides {
                let angle = Double(side) * 2 * .pi / Double(sides)
                let normal = u * cos(angle) + v * sin(angle)
                vertices.append((point + normal * radius).vector); normals.append(normal.vector)
                if i > 0 {
                    let a = Int32((i - 1) * sides + side), b = Int32((i - 1) * sides + (side + 1) % sides)
                    let c = Int32(i * sides + side), d = Int32(i * sides + (side + 1) % sides)
                    indices += [a, c, b, b, c, d]
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material(stroke.color, selected: selected)]
        return SCNNode(geometry: geometry)
    }
    static func primitive(_ primitive: Sketch3DPrimitive, selected: Bool = false) -> SCNNode {
        let size = primitive.size
        let geometry: SCNGeometry
        switch primitive.kind {
        case .box: geometry = SCNBox(width: size.x, height: size.y, length: size.z, chamferRadius: 0)
        case .cylinder: let cylinder = SCNCylinder(radius: size.x / 2, height: size.y); cylinder.radialSegmentCount = 32; geometry = cylinder
        case .sphere: let sphere = SCNSphere(radius: size.x / 2); sphere.segmentCount = 24; geometry = sphere
        }
        geometry.materials = [material(primitive.color, selected: selected)]
        let node = SCNNode(geometry: geometry); node.position = primitive.center.vector
        return node
    }
    static func line(_ a: Sketch3DPoint, _ b: Sketch3DPoint, color: NSColor) -> SCNNode {
        let source = SCNGeometrySource(vertices: [a.vector, b.vector])
        let geometry = SCNGeometry(sources: [source], elements: [SCNGeometryElement(indices: [Int32(0), Int32(1)], primitiveType: .line)])
        let material = SCNMaterial(); material.diffuse.contents = color; material.lightingModel = .constant; geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}

extension DrawingSession {
    var selectedSketch3DElement: DrawingElement? {
        guard selectedIDs.count == 1 else { return nil }
        return board.elements.first { selectedIDs.contains($0.id) && $0.kind == .image && $0.sketch3D != nil }
    }
    /// Keeps the editable scene beside its rendered image in the normal board file.
    func insertSketch3D(_ document: Sketch3DDocument, png: Data, imageSize: CGSize, replacing id: UUID? = nil) throws {
        finishActiveInput?()
        try Sketch3DFile.validate(document)
        guard !document.isEmpty, !png.isEmpty, png.count <= Sketch3DFile.maximumBytes,
              imageSize.width.isFinite, imageSize.height.isFinite, imageSize.width > 0, imageSize.height > 0,
              let image = NSImage(data: png), image.size.width > 0, image.size.height > 0 else {
            throw BoardFileError.invalid("the 3D snapshot couldn't be inserted.")
        }
        var next = board
        var insertedID: UUID
        if let id, let index = next.elements.firstIndex(where: { $0.id == id && $0.kind == .image && !$0.locked }) {
            next.elements[index].imageData = png; next.elements[index].sketch3D = document
            insertedID = id
        } else {
            let width = min(640, max(100, board.width * 0.5))
            let height = width * imageSize.height / imageSize.width
            let center = CGPoint(x: board.width / 2, y: board.height / 2)
            let element = DrawingElement(kind: .image, points: [.init(x: center.x - width / 2, y: center.y - height / 2), .init(x: center.x + width / 2, y: center.y + height / 2)], text: document.title, imageData: png, sketch3D: document)
            next.elements.append(element); insertedID = element.id
        }
        try BoardFile.validate(next)
        checkpoint(); board = next; selectedIDs = [insertedID]; changed()
        status = "3D sketch saved on the board. Select it and open 3D Sketch to edit."
    }
}
