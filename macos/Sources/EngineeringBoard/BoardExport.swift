import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable {
    case pdf = "PDF", png = "PNG", jpeg = "JPEG"
    var fileExtension: String { rawValue.lowercased() }
    var contentType: UTType {
        switch self { case .pdf: return .pdf; case .png: return .png; case .jpeg: return .jpeg }
    }
}

enum BoardExportError: LocalizedError {
    case rendererUnavailable
    case encodingFailed
    case invalidPaperSize
    var errorDescription: String? {
        switch self {
        case .rendererUnavailable: return "The drawing couldn't be rendered for export."
        case .encodingFailed: return "The exported image couldn't be encoded."
        case .invalidPaperSize: return "The drawing scale produces a paper size outside the supported range. Set a practical points-per-mm value before exporting."
        }
    }
}

@MainActor
enum BoardExport {
    static func export(board: Board, format: ExportFormat) throws {
        let panel = NSSavePanel()
        panel.title = "Export \(format.rawValue)"
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = BoardFile.filename(for: board.title, extension: format.fileExtension)
        if format == .pdf { panel.message = "The PDF uses this drawing's scale. To keep dimensions correct, print at 100% / Actual Size." }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data(board: board, format: format).write(to: url, options: .atomic)
    }

    static func data(board: Board, format: ExportFormat) throws -> Data {
        try BoardFile.validate(board)
        let board = normalized(board: board)
        switch format {
        case .pdf: return try pdfData(board: board)
        case .png, .jpeg:
            let bitmap = try raster(board: board)
            // Explicitly encode a fresh raster. Imported image metadata isn't forwarded.
            let encoding: NSBitmapImageRep.FileType = format == .png ? .png : .jpeg
            let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg ? [.compressionFactor: 0.92] : [:]
            guard let data = bitmap.representation(using: encoding, properties: properties) else {
                throw BoardExportError.encodingFailed
            }
            return data
        }
    }

    /// Fits off-sheet drawing into a temporary paper snapshot. Project coordinates
    /// and the user's scale are unchanged in the original editable drawing.
    static func normalized(board: Board) -> Board {
        let sheet = CGRect(x: 0, y: 0, width: board.width, height: board.height)
        var bounds = sheet
        for element in board.elements {
            let rect = element.bounds
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let angle = element.rotation * .pi / 180
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            let visual = corners.reduce(CGRect.null) { result, point in
                let dx = point.x - center.x, dy = point.y - center.y
                let rotated = CGPoint(x: center.x + dx * cos(angle) - dy * sin(angle),
                                      y: center.y + dx * sin(angle) + dy * cos(angle))
                return result.union(CGRect(origin: rotated, size: .zero))
            }
            if !sheet.contains(visual) { bounds = bounds.union(visual.insetBy(dx: -24, dy: -24)) }
        }
        guard bounds != sheet else { return board }
        // Whole grid increments keep the grid aligned with the original canvas.
        let spacing = max(1, board.gridSpacing)
        let left = floor(bounds.minX / spacing) * spacing
        let top = floor(bounds.minY / spacing) * spacing
        let right = ceil(bounds.maxX / spacing) * spacing
        let bottom = ceil(bounds.maxY / spacing) * spacing
        var copy = board
        copy.width = right - left
        copy.height = bottom - top
        copy.elements = board.elements.map { item in var item = item; item.translate(dx: -left, dy: -top); return item }
        return copy
    }

    private static func raster(board: Board) throws -> NSBitmapImageRep {
        // Explicit pixel sizing makes exports independent of Retina display backing.
        // Bound both the longest edge and total pixels for large imported boards.
        let scale = min(2, min(8_000 / max(board.width, board.height),
                               sqrt(32_000_000 / (board.width * board.height))))
        let width = max(1, Int(ceil(board.width * scale)))
        let height = max(1, Int(ceil(board.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BoardExportError.rendererUnavailable
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / board.width, y: -CGFloat(height) / board.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        BoardRenderer.draw(board: board)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { throw BoardExportError.rendererUnavailable }
        return NSBitmapImageRep(cgImage: image)
    }

    static func paperSize(board: Board) throws -> CGSize {
        try BoardFile.validate(board)
        return try paperSize(ofSnapshot: normalized(board: board))
    }

    /// The original editable board is validated before normalization. A temporary
    /// export snapshot can span more than the persisted sheet-size limit when
    /// valid objects sit elsewhere on the infinite canvas.
    private static func paperSize(ofSnapshot board: Board) throws -> CGSize {
        // The board model uses drawing points. Convert paper mm to PDF points.
        // scaleDenominator belongs in real-world dimension labels, not this conversion.
        let width = board.width / board.pointsPerMM * 72 / 25.4
        let height = board.height / board.pointsPerMM * 72 / 25.4
        guard width.isFinite, height.isFinite, width >= 1, height >= 1, width <= 14_400, height <= 14_400 else {
            throw BoardExportError.invalidPaperSize
        }
        return CGSize(width: width, height: height)
    }

    private static func pdfData(board: Board) throws -> Data {
        let size = try paperSize(ofSnapshot: board)
        var mediaBox = CGRect(origin: .zero, size: size)
        let buffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: buffer as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw BoardExportError.rendererUnavailable
        }
        context.beginPDFPage(nil)
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: size.width / board.width, y: -size.height / board.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        BoardRenderer.draw(board: board)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()
        return buffer as Data
    }
}
