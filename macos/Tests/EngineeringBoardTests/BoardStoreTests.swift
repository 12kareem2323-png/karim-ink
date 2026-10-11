import XCTest
@testable import EngineeringBoard

final class BoardStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EngineeringBoardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixture() -> Board {
        var board = Board()
        board.title = "Plate & equations"
        board.folder = "Unit 2"
        board.background = .graph
        board.scaleDenominator = 2
        board.notes = "A = 150 × 100 = 15,000 mm²\nDo not alter measurements."
        board.notionURL = "https://www.notion.so/example"
        board.elements = [
            DrawingElement(kind: .stroke, points: [InkPoint(x: 1, y: 2, pressure: 0.2, tiltX: 0.1, tiltY: -0.3), InkPoint(x: 10, y: 15, pressure: 0.8)], color: .blue, width: 4, pen: .pencil),
            DrawingElement(kind: .dimension, points: [InkPoint(x: 100, y: 250), InkPoint(x: 700, y: 250)], width: 2),
            DrawingElement(kind: .text, points: [InkPoint(x: 100, y: 300)], text: "V = IR · Ω · μF · ²", fontSize: 20)
        ]
        return board
    }

    @MainActor
    func testCompleteDrawingSurvivesReopeningWithPressureAndTechnicalSymbols() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        XCTAssertTrue(store.boards.isEmpty)
        let board = fixture()
        store.save(board)
        XCTAssertNil(store.error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: board.id).path))
        let reopened = BoardStore(directory: directory)
        XCTAssertNil(reopened.error)
        XCTAssertEqual(reopened.boards, [board])
    }

    @MainActor
    func testFailedValidationKeepsPreviousSavedDrawingAndReportsFailure() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let original = fixture()
        store.save(original)
        let savedBytes = try Data(contentsOf: store.url(for: original.id))
        var invalid = original
        invalid.title = "This edit cannot be saved"
        invalid.elements[0].points[0].x = .nan
        store.save(invalid)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.boards, [original])
        XCTAssertEqual(try Data(contentsOf: store.url(for: original.id)), savedBytes)
        XCTAssertEqual(BoardStore(directory: directory).boards, [original])
    }

    @MainActor
    func testDiskWriteFailureIsSurfacedWithoutPretendingDrawingWasSaved() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let board = fixture()
        // A directory at the destination deterministically makes the atomic rename fail.
        try FileManager.default.createDirectory(at: store.url(for: board.id), withIntermediateDirectories: false)
        store.save(board)
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.boards.isEmpty)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: board.id).path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    @MainActor
    func testCorruptFilesArePreservedAndValidDrawingsStillLoad() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = fixture()
        BoardStore(directory: directory).save(original)
        let damaged = directory.appendingPathComponent("broken.engboard")
        let bytes = Data("{ corrupt drawing".utf8)
        try bytes.write(to: damaged)
        let reopened = BoardStore(directory: directory)
        XCTAssertEqual(reopened.boards, [original])
        XCTAssertTrue(reopened.error?.contains("broken.engboard") == true)
        XCTAssertEqual(try Data(contentsOf: damaged), bytes)
    }

    @MainActor
    func testImportUsesNewIdentityAndDoesNotOverwriteOriginal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let original = fixture()
        store.save(original)
        let bytes = try Data(contentsOf: store.url(for: original.id))
        let imported = try store.importBoard(from: store.url(for: original.id))
        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertNotEqual(imported.elements[0].id, original.elements[0].id)
        XCTAssertEqual(imported.notes, original.notes)
        XCTAssertEqual(imported.elements[0].points, original.elements[0].points)
        XCTAssertEqual(store.boards.count, 2)
        XCTAssertEqual(try Data(contentsOf: store.url(for: original.id)), bytes)
        XCTAssertEqual(BoardStore(directory: directory).boards.count, 2)
    }

    @MainActor
    func testArchiveDeletionIsRecoverableByImport() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let original = fixture()
        store.save(original)
        let bytes = try Data(contentsOf: store.url(for: original.id))
        store.delete(original)
        XCTAssertNil(store.error)
        XCTAssertTrue(store.boards.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: original.id).path))
        let archived = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: store.archiveDirectory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: archived), bytes)
        let restored = try store.importBoard(from: archived)
        XCTAssertEqual(restored.notes, original.notes)
        XCTAssertEqual(store.boards.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.path))
    }

    @MainActor
    func testDuplicateCreatesIndependentBoardAndElements() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let original = fixture()
        store.save(original)
        var duplicate = store.duplicate(original)
        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertEqual(duplicate.title, original.title + " copy")
        XCTAssertEqual(Set(duplicate.elements.map(\.id)).intersection(Set(original.elements.map(\.id))).count, 0)
        duplicate.elements[0].points[0].x = 900
        store.save(duplicate)
        XCTAssertEqual(store.boards.first(where: { $0.id == original.id }), original)
    }

    @MainActor
    func testUnsupportedVersionRemainsUntouched() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var board = fixture()
        board.version = 99
        let url = directory.appendingPathComponent("\(board.id.uuidString).engboard")
        let bytes = try JSONEncoder().encode(board)
        try bytes.write(to: url)
        let store = BoardStore(directory: directory)
        XCTAssertTrue(store.boards.isEmpty)
        XCTAssertTrue(store.error?.contains("version 99") == true)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}
