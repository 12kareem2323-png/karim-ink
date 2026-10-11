import Foundation
import XCTest
@testable import EngineeringBoard

final class BoardStoreConflictTests: XCTestCase {
    @MainActor
    func testStaleInstanceCannotOverwriteNewerDiskDrawing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = BoardStore(directory: folder)
        let original = first.create(title: "Conflict fixture")
        let second = BoardStore(directory: folder)
        var external = original
        external.notes = "Saved by first instance"; external.modified = Date()
        XCTAssertTrue(first.save(external))
        var stale = original
        stale.notes = "Edited later using an older baseline"; stale.modified = external.modified.addingTimeInterval(5)
        XCTAssertFalse(second.save(stale))
        XCTAssertEqual(second.conflictingBoardID, original.id)
        XCTAssertEqual(try BoardFile.read(from: first.url(for: original.id)), external)
        let backups = first.archiveDirectory.appendingPathComponent("Conflicts").appendingPathComponent(original.id.uuidString)
        let files = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        let versions = try files.map { try BoardFile.read(from: $0) }
        XCTAssertEqual(versions.count, 2)
        XCTAssertTrue(versions.contains(stale))
        XCTAssertTrue(versions.contains(external))
        XCTAssertTrue(second.reload())
        XCTAssertNil(second.conflictingBoardID)
        XCTAssertEqual(second.boards.first, external)
    }

    @MainActor
    func testExternalDeletionIsNotSilentlyResurrected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BoardStore(directory: folder)
        let board = store.create(title: "Deletion fixture")
        try FileManager.default.removeItem(at: store.url(for: board.id))
        XCTAssertFalse(store.save(board))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: board.id).path))
        XCTAssertEqual(store.conflictingBoardID, board.id)
    }

    @MainActor
    func testEquivalentJSONRewriteDoesNotCreateFalseConflict() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BoardStore(directory: folder)
        let board = store.create(title: "Equivalent rewrite fixture")
        let object = try JSONSerialization.jsonObject(with: BoardFile.encode(board))
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: store.url(for: board.id), options: .atomic)
        XCTAssertTrue(store.save(board))
        XCTAssertNil(store.conflictingBoardID)
    }
}
