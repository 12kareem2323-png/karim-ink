import XCTest
@testable import EngineeringBoard

final class ToolsTests: XCTestCase {
    func testPrecedenceAndPowers() throws {
        for (source, expected) in [("2+3*4", 14.0), ("2^3^2", 512), ("-2^2", -4), ("sqrt(169)", 13), ("sin(pi/2)", 1), ("1e-3*1000", 1)] {
            var p = ExpressionParser(source)
            XCTAssertEqual(try p.evaluate(), expected, accuracy: 1e-10)
        }
    }
    func testRejectsInvalidMath() {
        for source in ["1/0", "sqrt(-1)", "2+", "sin(1", "2garbage", "1.2.3", "system(1)"] { var p = ExpressionParser(source); XCTAssertThrowsError(try p.evaluate(), source) }
    }
    func testGraphVariableAndUnits() throws {
        var p = ExpressionParser("x^2 - 2*x + 1", x: 3)
        XCTAssertEqual(try p.evaluate(), 4)
        XCTAssertEqual(try UnitFamily.length.convert(1, from: "in", to: "mm"), 25.4, accuracy: 1e-9)
        XCTAssertEqual(try UnitFamily.pressure.convert(1, from: "MPa", to: "Pa"), 1_000_000)
        XCTAssertThrowsError(try UnitFamily.force.convert(1, from: "N", to: "mm"))
    }
}
