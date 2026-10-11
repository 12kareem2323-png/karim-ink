import CoreGraphics
import XCTest
@testable import EngineeringBoard

final class StrokeGeometryTests: XCTestCase {
    func testDisabledSmoothingPreservesDeliveredPositions() {
        var filter = AdaptiveInkFilter()
        for i in 0..<30 {
            let point = CGPoint(x: Double(i) * 3, y: sin(Double(i)) * 5)
            XCTAssertEqual(filter.sample(point, at: Double(i) / 120, smoothing: 0, zoom: 1), point)
        }
    }

    func testDampsSteadyNoiseWhileFollowingFastInk() {
        var steady = AdaptiveInkFilter(), fast = AdaptiveInkFilter()
        var inputEnergy = 0.0, outputEnergy = 0.0
        for i in 0..<240 {
            let point = CGPoint(x: 100, y: 100 + (i.isMultiple(of: 2) ? -2.0 : 2.0))
            let output = steady.sample(point, at: Double(i) / 120, smoothing: 0.6, zoom: 1)
            if i > 30 {
                inputEnergy += pow(point.y - 100, 2)
                outputEnergy += pow(output.y - 100, 2)
            }
        }
        XCTAssertLessThan(outputEnergy, inputEnergy * 0.35)
        var tip = CGPoint.zero
        for i in 0..<120 {
            tip = fast.sample(CGPoint(x: Double(i) * 6, y: 0), at: Double(i) / 120, smoothing: 0.6, zoom: 1)
        }
        XCTAssertLessThan(714 - tip.x, 9)
    }

    func testZoomDoesNotChangePhysicalFilteringResponse() {
        var normal = AdaptiveInkFilter(), zoomed = AdaptiveInkFilter()
        for i in 0..<120 {
            let point = CGPoint(x: Double(i) * 2, y: sin(Double(i) / 20) * 40)
            let a = normal.sample(point, at: Double(i) / 120, smoothing: 0.5, zoom: 1)
            let b = zoomed.sample(CGPoint(x: point.x / 2, y: point.y / 2), at: Double(i) / 120, smoothing: 0.5, zoom: 2)
            XCTAssertEqual(a.x, b.x * 2, accuracy: 0.000_01)
            XCTAssertEqual(a.y, b.y * 2, accuracy: 0.000_01)
        }
        normal.reset()
        XCTAssertEqual(normal.sample(CGPoint(x: 2, y: 2), at: 0, smoothing: 0.6, zoom: 1), CGPoint(x: 2, y: 2))
    }
}
