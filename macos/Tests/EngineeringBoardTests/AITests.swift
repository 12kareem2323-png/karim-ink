import XCTest
@testable import EngineeringBoard

@MainActor
final class AITests: XCTestCase {
    func testResponsesTextExtractionWithoutNetwork() throws {
        let payload: [String: Any] = ["status": "completed", "output": [
            ["type": "reasoning", "summary": []],
            ["type": "message", "content": [
                ["type": "output_text", "text": "F = ma"],
                ["type": "output_text", "text": "Use newtons."]
            ]]
        ]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertEqual(try AssistantConversation.replyText(data: data), "F = ma\nUse newtons.")
    }

    func testRefusalCanBeDisplayed() throws {
        let payload: [String: Any] = ["output": [["content": [
            ["type": "refusal", "refusal": "I can't help with that request."]
        ]]]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertEqual(try AssistantConversation.replyText(data: data), "I can't help with that request.")
    }

    func testIncompleteResponseIsFlagged() throws {
        let payload: [String: Any] = ["status": "incomplete", "output": [["content": [
            ["type": "output_text", "text": "First step"]
        ]]]]
        let result = try AssistantConversation.replyText(data: JSONSerialization.data(withJSONObject: payload))
        XCTAssertTrue(result.contains("This response was cut short."))
    }

    func testEmptyOrMalformedResponseDoesNotPretendToSucceed() {
        XCTAssertThrowsError(try AssistantConversation.replyText(data: Data("{}".utf8)))
        XCTAssertThrowsError(try AssistantConversation.replyText(data: Data("{\"output\":[]}".utf8)))
        XCTAssertThrowsError(try AssistantConversation.replyText(data: Data("invalid JSON".utf8)))
    }

    func testBoardTextWrappingKeepsWordsAndSymbols() {
        let original = "The bending moment is M = F × d, with F = 120 N and d = 0.25 m.\nCheck the units."
        let wrapped = AssistantConversation.wrappedForBoard(original, columns: 28)
        XCTAssertGreaterThan(wrapped.components(separatedBy: "\n").count, 2)
        XCTAssertEqual(wrapped.split(whereSeparator: { $0.isWhitespace }), original.split(whereSeparator: { $0.isWhitespace }))
        XCTAssertTrue(wrapped.contains("120 N"))
    }

    func testInkSmoothingPreservesEndpointsPressureAndTilt() {
        let original = [
            InkPoint(x: 0, y: 0, pressure: 0.2, tiltX: 0.1, tiltY: 0.2),
            InkPoint(x: 8, y: 15, pressure: 0.8, tiltX: 0.3, tiltY: 0.4),
            InkPoint(x: 20, y: 0, pressure: 0.4, tiltX: 0.5, tiltY: 0.6)
        ]
        let result = Handwriting.smoothed(original)
        XCTAssertEqual(result.first, original.first)
        XCTAssertEqual(result.last, original.last)
        XCTAssertEqual(result[1].y, 10.5, accuracy: 0.00001)
        XCTAssertEqual(result[1].pressure, original[1].pressure)
        XCTAssertEqual(result[1].tiltX, original[1].tiltX)
        XCTAssertEqual(result[1].tiltY, original[1].tiltY)
        XCTAssertEqual(Handwriting.smoothed(Array(original.prefix(2))), Array(original.prefix(2)))
    }

    func testSmoothingOnlyChangesSelectedUnlockedInkAndUndoRestoresIt() {
        let points = [InkPoint(x: 0, y: 0), InkPoint(x: 8, y: 15), InkPoint(x: 20, y: 0)]
        let editable = DrawingElement(kind: .stroke, points: points)
        let locked = DrawingElement(kind: .stroke, points: points, locked: true)
        let untouched = DrawingElement(kind: .stroke, points: points)
        let board = Board(elements: [editable, locked, untouched])
        let session = DrawingSession(board: board)
        session.selectedIDs = [editable.id, locked.id]
        Handwriting.smoothSelection(session: session)
        XCTAssertNotEqual(session.board.elements[0].points, points)
        XCTAssertEqual(session.board.elements[1], locked)
        XCTAssertEqual(session.board.elements[2], untouched)
        session.undo()
        XCTAssertEqual(session.board.elements, board.elements)
    }

    func testOCRSelectionIgnoresTypedTextAndUnselectedInk() {
        let ink = DrawingElement(kind: .stroke, points: [InkPoint(x: 1, y: 2)])
        let other = DrawingElement(kind: .stroke, points: [InkPoint(x: 4, y: 5)])
        let text = DrawingElement(kind: .text, points: [InkPoint(x: 10, y: 10)], text: "42")
        let session = DrawingSession(board: Board(elements: [ink, other, text]))
        session.selectedIDs = [ink.id, text.id]
        XCTAssertEqual(Handwriting.strokeIDs(session: session), [ink.id])
        session.selectedIDs.removeAll()
        XCTAssertEqual(Handwriting.strokeIDs(session: session), [ink.id, other.id])
    }

    func testMathParserRejectsMalformedSourceAndKeepsItLiterally() {
        let sources = ["x}+y", "x^2^3", "x_1_2", "x^{2", "\\frac{F}", "\\unknown{x}", "\\sqrt[3]{x}", String(repeating: "x", count: 4097)]
        for source in sources {
            XCTAssertNotNil(MathParser.validationError(for: source))
            var parser = MathParser(source)
            guard case .text(let literal) = parser.parse() else { return XCTFail("Malformed source should stay literal") }
            XCTAssertEqual(literal, source)
        }
    }

    func testMathParserAcceptsSupportedNestedNotationAndWhitespace() {
        for source in ["\\sigma = \\frac{F}{A}", "\\frac {1} {\\sqrt{x^2+y^2}}", "x^{2^3}_{n+1}", "\\text{area_mm}", "\\alpha^2"] {
            XCTAssertNil(MathParser.validationError(for: source), source)
        }
    }

    func testTenBrushesAndLegacyPenNames() throws {
        XCTAssertEqual(PenKind.allCases.count, 10)
        XCTAssertEqual(BackgroundKind.allCases.count, 10)
        for name in ["Pen", "Pencil", "Fountain", "Marker", "Highlighter"] {
            let data = try JSONSerialization.data(withJSONObject: name, options: .fragmentsAllowed)
            let pen = try JSONDecoder().decode(PenKind.self, from: data)
            XCTAssertTrue(PenKind.allCases.contains(pen))
        }
    }

    func testFinelinerConstantWidthAndPencilPressureWidthOpacity() {
        let low = InkPoint(x: 0, y: 0, pressure: 0.1), high = InkPoint(x: 10, y: 0, pressure: 1)
        var element = DrawingElement(kind: .stroke, points: [low, high], pen: .technical, brushSettings: .defaults(for: .technical))
        XCTAssertEqual(BrushMetrics.width(element: element, point: low), BrushMetrics.width(element: element, point: high))
        element.pen = .pencil; element.brushSettings = .defaults(for: .pencil)
        XCTAssertLessThan(BrushMetrics.width(element: element, point: low), BrushMetrics.width(element: element, point: high))
        XCTAssertLessThan(BrushMetrics.opacity(element: element, point: low), BrushMetrics.opacity(element: element, point: high))
    }
}
