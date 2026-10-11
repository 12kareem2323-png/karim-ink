import XCTest
import AppKit
@testable import EngineeringBoard

final class Sketch3DTests: XCTestCase {
    func testAllDrawingPlanesIntersectCameraRayAtTheirOffsets() throws {
        let xy = try XCTUnwrap(Sketch3DPlane.xy.intersect(near: .init(x: 10, y: 20, z: 100), far: .init(x: 30, y: 40, z: -100), offset: 20))
        XCTAssertEqual(xy.x, 18, accuracy: 0.0001); XCTAssertEqual(xy.y, 28, accuracy: 0.0001); XCTAssertEqual(xy.z, 20, accuracy: 0.0001)
        let xz = try XCTUnwrap(Sketch3DPlane.xz.intersect(near: .init(x: 0, y: 100, z: 0), far: .init(x: 20, y: -100, z: 40), offset: 0))
        XCTAssertEqual(xz, Sketch3DPoint(x: 10, y: 0, z: 20))
        let yz = try XCTUnwrap(Sketch3DPlane.yz.intersect(near: .init(x: 100, y: 0, z: 0), far: .init(x: -100, y: 40, z: 20), offset: -20))
        XCTAssertEqual(yz.x, -20, accuracy: 0.0001); XCTAssertEqual(yz.y, 24, accuracy: 0.0001); XCTAssertEqual(yz.z, 12, accuracy: 0.0001)
    }

    func testParallelBehindCameraAndOversizedIntersectionsAreRejected() {
        XCTAssertNil(Sketch3DPlane.xy.intersect(near: .init(x: 0, y: 0, z: 3), far: .init(x: 10, y: 10, z: 3), offset: 0))
        XCTAssertNil(Sketch3DPlane.xy.intersect(near: .init(x: 0, y: 0, z: 1), far: .init(x: 0, y: 0, z: 2), offset: 0))
        XCTAssertNil(Sketch3DPlane.xy.intersect(near: .init(x: 20_000, y: 0, z: 1), far: .init(x: 20_000, y: 0, z: -1), offset: 0))
        XCTAssertNil(Sketch3DPlane.xy.intersect(near: .init(x: .nan, y: 0, z: 1), far: .init(x: 0, y: 0, z: -1), offset: 0))
    }

    private func scene() -> Sketch3DDocument {
        var document = Sketch3DDocument()
        document.strokes = [Sketch3DStroke(points: [.init(x: 0, y: 0, z: 0, pressure: 0.2), .init(x: 50, y: 30, z: 10, pressure: 0.9)], color: .violet, width: 3)]
        document.primitives = [Sketch3DPrimitive(kind: .box, center: .init(x: 10, y: 20, z: 30))]
        return document
    }

    func testSceneRoundTripPreservesUnitsPressureIDsAndCamera() throws {
        let original = scene()
        XCTAssertEqual(try Sketch3DFile.decode(Sketch3DFile.encode(original)), original)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sketch3d-\(UUID().uuidString).karim3d")
        defer { try? FileManager.default.removeItem(at: url) }
        try Sketch3DFile.encode(original).write(to: url, options: .atomic)
        XCTAssertEqual(try Sketch3DFile.read(url), original)
    }

    func testSceneValidationRejectsDuplicatesUnsupportedUnitsAndUnboundedGeometry() {
        var document = scene(); document.units = "inch"; XCTAssertThrowsError(try Sketch3DFile.validate(document))
        document = scene(); document.primitives[0].id = document.strokes[0].id; XCTAssertThrowsError(try Sketch3DFile.validate(document))
        document = scene(); document.strokes[0].points[0].pressure = .infinity; XCTAssertThrowsError(try Sketch3DFile.validate(document))
        document = scene(); document.primitives[0].size.y = -1; XCTAssertThrowsError(try Sketch3DFile.validate(document))
        document = scene(); document.camera.distance = .nan; XCTAssertThrowsError(try Sketch3DFile.validate(document))
        document = scene(); document.strokes[0].points = Array(repeating: .zero, count: 4_097); XCTAssertThrowsError(try Sketch3DFile.validate(document))
    }

    @MainActor
    func testUndoRedoEditingAndClearRetainTheWholeScene() async throws {
        let state = Sketch3DState(document: scene())
        let original = state.document
        state.selectedID = original.strokes[0].id
        state.setPosition(.init(x: 60, y: 20, z: 5))
        let moved = state.document
        XCTAssertNotEqual(moved, original)
        XCTAssertEqual(moved.strokes[0].points[0].pressure, 0.2)
        state.undo(); XCTAssertEqual(state.document, original)
        state.redo(); XCTAssertEqual(state.document, moved)
        state.clear(); XCTAssertTrue(state.document.isEmpty)
        state.undo(); XCTAssertEqual(state.document, moved)
    }

    @MainActor
    func testActiveStrokeFinishesAsOneUndoableObjectAndRejectsInvalidPoints() async {
        let state = Sketch3DState()
        state.beginStroke(at: .init(x: 1, y: 0, z: 2, pressure: 0.3))
        state.appendPoint(.init(x: 11, y: 0, z: 12, pressure: 0.8))
        state.appendPoint(.init(x: .nan, y: 0, z: 0))
        state.finishStroke()
        XCTAssertEqual(state.document.strokes.count, 1)
        XCTAssertEqual(state.document.strokes[0].points.count, 2)
        state.undo(); XCTAssertTrue(state.document.isEmpty)
        state.redo(); XCTAssertEqual(state.document.strokes[0].points[1].pressure, 0.8)
    }

    @MainActor
    func testRecoveryRestoresAnUninsertedActiveStrokeAndPreservesCorruptDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("3d-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let boardID = UUID()
        let state = Sketch3DState()
        state.configureDraft(boardID: boardID, sourceID: nil, directory: directory)
        state.beginStroke(at: .init(x: 1, y: 2, z: 3, pressure: 0.4))
        state.appendPoint(.init(x: 10, y: 20, z: 30, pressure: 0.7))
        state.saveDraft(includeActiveStroke: true)
        let recovered = Sketch3DState()
        recovered.configureDraft(boardID: boardID, sourceID: nil, directory: directory)
        XCTAssertEqual(recovered.document.strokes.first?.points.count, 2)
        XCTAssertEqual(recovered.document.strokes.first?.points.last?.pressure, 0.7)
        let draft = directory.appendingPathComponent("\(boardID.uuidString)-new.karim3d")
        let corrupt = Data("{ broken".utf8)
        try corrupt.write(to: draft)
        let blocked = Sketch3DState()
        blocked.configureDraft(boardID: boardID, sourceID: nil, directory: directory)
        blocked.addPrimitive(.box)
        XCTAssertNotNil(blocked.error)
        XCTAssertEqual(try Data(contentsOf: draft), corrupt)
    }

    @MainActor
    func testChangedDraftIsNotOverwrittenByAnotherWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("3d-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let boardID = UUID(), state = Sketch3DState()
        state.configureDraft(boardID: boardID, sourceID: nil, directory: directory)
        state.addPrimitive(.box)
        let url = directory.appendingPathComponent("\(boardID.uuidString)-new.karim3d")
        var other = scene(); other.title = "Other window"
        let data = try Sketch3DFile.encode(other); try data.write(to: url, options: .atomic)
        state.addPrimitive(.sphere)
        XCTAssertNotNil(state.error)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    @MainActor
    func testBoardPayloadRoundTripReplacementPlacementAndUndo() async throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let session = DrawingSession(board: Board(), storesPreferences: false)
        let document = scene()
        try session.insertSketch3D(document, png: png, imageSize: .init(width: 600, height: 400))
        let element = try XCTUnwrap(session.selectedSketch3DElement)
        XCTAssertEqual(try BoardFile.decode(BoardFile.encode(session.board)), session.board)
        var next = document; next.title = "Updated scene"
        try session.insertSketch3D(next, png: png, imageSize: .init(width: 600, height: 400), replacing: element.id)
        XCTAssertEqual(session.board.elements.count, 1)
        XCTAssertEqual(session.board.elements[0].id, element.id)
        XCTAssertEqual(session.board.elements[0].points, element.points)
        XCTAssertEqual(session.board.elements[0].sketch3D, next)
        session.undo(); XCTAssertEqual(session.board.elements[0].sketch3D, document)
        session.undo(); XCTAssertTrue(session.board.elements.isEmpty)
    }

    func testOlderBoardWithout3DPayloadStillDecodesAndInvalidPayloadFailsBoardValidation() throws {
        let board = Board(elements: [DrawingElement(kind: .line, points: [.init(x: 1, y: 2), .init(x: 3, y: 4)])])
        let encoded = try BoardFile.encode(board)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("sketch3D"))
        XCTAssertEqual(try BoardFile.decode(encoded), board)
        var invalid = board; invalid.elements[0].sketch3D = scene()
        XCTAssertThrowsError(try BoardFile.validate(invalid))
    }
}
