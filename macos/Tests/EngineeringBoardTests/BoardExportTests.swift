import AppKit
import CoreGraphics
import XCTest
@testable import EngineeringBoard

final class BoardExportTests: XCTestCase {
    private func fixture() -> Board {
        var board = Board()
        board.width = 840
        board.height = 1188
        board.pointsPerMM = 4
        board.background = .plain
        board.title = "PDF orientation check"
        board.elements = [
            DrawingElement(kind: .rectangle, points: [InkPoint(x: 30, y: 30), InkPoint(x: 170, y: 130)], color: .red, width: 2, fill: true),
            DrawingElement(kind: .text, points: [InkPoint(x: 210, y: 40)], text: "TOP · 25 mm · Ω", fontSize: 24),
            DrawingElement(kind: .dimension, points: [InkPoint(x: 100, y: 300), InkPoint(x: 500, y: 300)], width: 2)
        ]
        return board
    }

    @MainActor
    func testPDFKeepsA4PaperSizeAndDrawingScaleWithoutExtraPages() async throws {
        var board = fixture()
        board.scaleDenominator = 5
        let data = try BoardExport.data(board: board, format: .pdf)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(document.numberOfPages, 1)
        let page = try XCTUnwrap(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 210 * 72 / 25.4, accuracy: 0.001)
        XCTAssertEqual(box.height, 297 * 72 / 25.4, accuracy: 0.001)
        // Changing drawing scale updates annotation lengths, not paper size.
        var otherScale = board
        otherScale.scaleDenominator = 1
        XCTAssertEqual(try BoardExport.paperSize(board: otherScale), try BoardExport.paperSize(board: board))
    }

    @MainActor
    func testPNGAndJPEGAreRealDecodableImagesWithExpectedAspectRatio() async throws {
        let board = fixture()
        for format in [ExportFormat.png, .jpeg] {
            let data = try BoardExport.data(board: board, format: format)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, 1680)
            XCTAssertEqual(bitmap.pixelsHigh, 2376)
            XCTAssertGreaterThan(data.count, 1_000)
            if format == .png {
                XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
            } else {
                XCTAssertEqual(Array(data.prefix(2)), [255, 216])
            }
            // A red marker near the top left catches vertical flips and blank exports.
            let color = try XCTUnwrap(bitmap.colorAt(x: 60, y: 130)?.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(color.redComponent, 0.6)
            XCTAssertLessThan(color.greenComponent, 0.4)
            XCTAssertLessThan(color.blueComponent, 0.4)
        }
    }

    @MainActor
    func testPDFDrawingHasSameTopLeftOrientationAsImage() async throws {
        let board = fixture()
        let data = try BoardExport.data(board: board, format: .pdf)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 840, height: 1188, bitsPerComponent: 8,
                                            bytesPerRow: 840 * 4, space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 840 / page.getBoxRect(.mediaBox).width, y: 1188 / page.getBoxRect(.mediaBox).height)
        context.drawPDFPage(page)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        let color = try XCTUnwrap(bitmap.colorAt(x: 30, y: 65)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(color.redComponent, 0.6)
        XCTAssertLessThan(color.greenComponent, 0.4)
        XCTAssertLessThan(color.blueComponent, 0.4)
    }

    @MainActor
    func testInvalidGeometryFailsBeforeRendering() async throws {
        var board = fixture()
        board.pointsPerMM = 0
        XCTAssertThrowsError(try BoardExport.data(board: board, format: .pdf))
        board.pointsPerMM = 4
        board.width = .infinity
        XCTAssertThrowsError(try BoardExport.data(board: board, format: .png))
    }

    @MainActor
    func testDemoExportsReopenInEveryFormat() async throws {
        let board = BoardStore.demoBoard()
        for format in ExportFormat.allCases {
            let bytes = try BoardExport.data(board: board, format: format)
            if format == .pdf {
                let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
                XCTAssertEqual(CGPDFDocument(provider)?.numberOfPages, 1)
            } else {
                XCTAssertNotNil(NSBitmapImageRep(data: bytes))
            }
            // Set this environment variable for an explicit visual-QA run.
            if let path = ProcessInfo.processInfo.environment["ENGINEERINGBOARD_QA_DIRECTORY"] {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try bytes.write(to: directory.appendingPathComponent("engineering-demo.\(format.fileExtension)"), options: .atomic)
            }
        }
    }

    func testExportFilenamePreservesTechnicalUnicodeAndRemovesPathSeparators() {
        XCTAssertEqual(BoardFile.filename(for: "Plate / 25 mm · Ω", extension: "png"), "Plate - 25 mm · Ω.png")
    }
}
