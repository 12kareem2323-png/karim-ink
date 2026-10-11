import AppKit
import XCTest
@testable import EngineeringBoard

final class CanvasGeometryTests: XCTestCase {
    @MainActor
    func testUnfilledRectangleSelectsEdgesWithoutBlockingObjectsInsideIt() async {
        var rectangle = DrawingElement(kind: .rectangle,
                                       points: [InkPoint(x: 100, y: 100), InkPoint(x: 500, y: 400)], width: 2)
        XCTAssertFalse(EngineeringCanvasView.hit(rectangle, point: CGPoint(x: 300, y: 250), tolerance: 3))
        XCTAssertTrue(EngineeringCanvasView.hit(rectangle, point: CGPoint(x: 100, y: 250), tolerance: 3))
        rectangle.fill = true
        XCTAssertTrue(EngineeringCanvasView.hit(rectangle, point: CGPoint(x: 300, y: 250), tolerance: 3))
    }

    @MainActor
    func testDiagonalLineUsesDistanceToLineRatherThanBoundingBox() async {
        let line = DrawingElement(kind: .line,
                                  points: [InkPoint(x: 100, y: 100), InkPoint(x: 300, y: 300)], width: 2)
        XCTAssertTrue(EngineeringCanvasView.hit(line, point: CGPoint(x: 205, y: 205), tolerance: 3))
        XCTAssertFalse(EngineeringCanvasView.hit(line, point: CGPoint(x: 110, y: 290), tolerance: 3))
        XCTAssertFalse(EngineeringCanvasView.hit(line, point: CGPoint(x: 350, y: 350), tolerance: 3))
    }

    @MainActor
    func testRotatedLineCanBeSelectedAtItsVisiblePosition() async {
        let line = DrawingElement(kind: .line,
                                  points: [InkPoint(x: 100, y: 200), InkPoint(x: 300, y: 200)], width: 2, rotation: 90)
        XCTAssertTrue(EngineeringCanvasView.hit(line, point: CGPoint(x: 200, y: 280), tolerance: 3))
        XCTAssertFalse(EngineeringCanvasView.hit(line, point: CGPoint(x: 280, y: 200), tolerance: 3))
    }

    @MainActor
    func testUnfilledCircleDoesNotClaimItsEmptyCentre() async {
        var circle = DrawingElement(kind: .ellipse,
                                    points: [InkPoint(x: 100, y: 100), InkPoint(x: 300, y: 300)], width: 2)
        XCTAssertFalse(EngineeringCanvasView.hit(circle, point: CGPoint(x: 200, y: 200), tolerance: 3))
        XCTAssertTrue(EngineeringCanvasView.hit(circle, point: CGPoint(x: 300, y: 200), tolerance: 3))
        circle.fill = true
        XCTAssertTrue(EngineeringCanvasView.hit(circle, point: CGPoint(x: 200, y: 200), tolerance: 3))
    }

    @MainActor
    func testThickHighlighterCanBeSelectedAcrossItsVisibleWidth() async {
        var line = DrawingElement(kind: .stroke,
                                  points: [InkPoint(x: 100, y: 200), InkPoint(x: 300, y: 200)], width: 4, pen: .pen)
        XCTAssertFalse(EngineeringCanvasView.hit(line, point: CGPoint(x: 200, y: 206), tolerance: 1))
        line.pen = .highlighter
        XCTAssertTrue(EngineeringCanvasView.hit(line, point: CGPoint(x: 200, y: 206), tolerance: 1))
    }
}
