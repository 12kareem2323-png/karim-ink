import XCTest
@testable import EngineeringBoard

final class WorldCameraTests: XCTestCase {
    func testAnchorRemainsFixedWhileZooming() {
        var camera = WorldCamera(center: CGPoint(x: -4000, y: 9000), zoom: 2)
        let anchor = CGPoint(x: 300, y: 200), before = camera.worldPoint(forScreen: anchor)
        camera.zoom(by: 3, anchoredAt: anchor)
        let after = camera.worldPoint(forScreen: anchor)
        XCTAssertEqual(before.x, after.x, accuracy: 1e-9); XCTAssertEqual(before.y, after.y, accuracy: 1e-9)
    }
    func testNegativeTilesAndRemoval() {
        var index = SpatialTileIndex(); let id = UUID()
        index.upsert(id: id, bounds: CGRect(x: -600, y: -100, width: 300, height: 200))
        XCTAssertTrue(index.query(CGRect(x: -550, y: -50, width: 20, height: 20)).contains(id))
        XCTAssertFalse(index.query(CGRect(x: 5000, y: 5000, width: 20, height: 20)).contains(id))
        index.remove(id: id)
        XCTAssertFalse(index.query(CGRect(x: -550, y: -50, width: 20, height: 20)).contains(id))
    }
}
