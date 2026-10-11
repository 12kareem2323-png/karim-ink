import AppKit
import UniformTypeIdentifiers

/// Editable Excalidraw geometry for Craft's whiteboard format.
/// Brush textures are approximated; complex native diagrams are retained as PNG assets.
/// The .engboard drawing remains the authoritative native source.
@MainActor
enum CraftExchange {
    static func export(board: Board) throws {
        let panel = NSSavePanel()
        panel.title = "Export editable whiteboard"
        panel.nameFieldStringValue = BoardFile.filename(for: board.title, extension: "excalidraw")
        panel.allowedContentTypes = [UTType(filenameExtension: "excalidraw") ?? .json]
        panel.message = "Basic shapes, text and pen paths stay editable. Complex diagrams use image assets. Keep your .engboard file for native brushes and engineering tools."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data(board: board).write(to: url, options: .atomic)
    }

    static func data(board: Board) throws -> Data {
        try JSONSerialization.data(withJSONObject: scene(board: board), options: [.sortedKeys, .prettyPrinted])
    }

    static func scene(board: Board) throws -> [String: Any] {
        try BoardFile.validate(board)
        var elements: [[String: Any]] = []
        var files: [String: Any] = [:]
        for item in board.elements {
            guard !item.points.isEmpty else { continue }
            switch item.kind {
            case .stroke:
                var value = base(item: item, board: board, type: "freedraw")
                let first = item.points[0]
                value["x"] = first.x; value["y"] = first.y
                value["points"] = item.points.map { [$0.x - first.x, $0.y - first.y] }
                value["pressures"] = item.points.map(\.pressure)
                value["simulatePressure"] = false
                value["strokeWidth"] = item.effectiveBrushSettings.maxWidth
                value["strokeOptions"] = ["variability": item.effectiveBrushSettings.pressureEnabled ? "variable" : "constant", "streamline": 0] as [String: Any]
                value["opacity"] = Int((item.color.a * item.effectiveBrushSettings.opacity * 100).rounded())
                value["lastCommittedPoint"] = NSNull()
                elements.append(value)
            case .line, .arrow:
                elements.append(line(item: item, board: board, type: item.kind == .arrow ? "arrow" : "line"))
            case .rectangle, .ellipse:
                elements.append(base(item: item, board: board, type: item.kind == .rectangle ? "rectangle" : "ellipse"))
            case .triangle:
                var value = line(item: item, board: board, type: "line")
                let vertices: [InkPoint]
                if item.points.count >= 3 {
                    vertices = Array(item.points.prefix(3))
                } else {
                    let first = item.points[0], last = item.points.last!
                    let left = min(first.x, last.x), right = max(first.x, last.x)
                    let top = min(first.y, last.y), bottom = max(first.y, last.y)
                    vertices = [InkPoint(x: (left + right) / 2, y: top), InkPoint(x: right, y: bottom), InkPoint(x: left, y: bottom)]
                }
                value["x"] = vertices[0].x; value["y"] = vertices[0].y
                value["points"] = (vertices + [vertices[0]]).map { [$0.x - vertices[0].x, $0.y - vertices[0].y] }
                value["polygon"] = true
                elements.append(value)
            case .text:
                elements.append(text(item: item, board: board))
            case .dimension:
                var arrow = line(item: item, board: board, type: "arrow")
                arrow["startArrowhead"] = "arrow"
                elements.append(arrow)
                if let first = item.points.first, let last = item.points.last {
                    let length = hypot(last.x - first.x, last.y - first.y)
                    if length > 0.01 {
                        let label = BoardRenderer.formatted(length / board.pointsPerMM * board.scaleDenominator) + " mm"
                        var dimensionText = DrawingElement(kind: .text, points: [InkPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2 + 17)], color: item.color, text: label, fontSize: max(16, item.fontSize))
                        dimensionText.rotation = item.rotation
                        var value = text(item: dimensionText, board: board)
                        value["id"] = elementID(board: board, item: item) + "-mm"
                        value["groupIds"] = [elementID(board: board, item: item) + "-dimension"]
                        var groupedArrow = elements.removeLast()
                        groupedArrow["groupIds"] = value["groupIds"]
                        elements.append(groupedArrow); elements.append(value)
                    }
                }
            case .arc, .image, .symbol:
                let asset = try rasterAsset(item: item, board: board)
                var value = base(item: item, board: board, type: "image")
                value["x"] = asset.bounds.minX; value["y"] = asset.bounds.minY
                value["width"] = asset.bounds.width; value["height"] = asset.bounds.height
                // Rotation is already baked into the raster preview.
                value["angle"] = 0
                value["fileId"] = asset.id
                value["status"] = "saved"
                value["scale"] = [1, 1]
                value["crop"] = NSNull()
                elements.append(value)
                files[asset.id] = ["id": asset.id, "mimeType": "image/png", "dataURL": "data:image/png;base64," + asset.data.base64EncodedString(), "created": milliseconds(board.created), "lastRetrieved": milliseconds(board.modified)]
            }
        }
        let color = backgroundColor(board.background)
        return ["type": "excalidraw", "version": 2, "source": BoardLinks.url(for: board.id).absoluteString,
                "elements": elements,
                "appState": ["viewBackgroundColor": color, "gridSize": NSNull(), "name": board.title],
                "files": files,
                "karimEldamaty": ["boardID": board.id.uuidString, "pointsPerMM": board.pointsPerMM, "scaleDenominator": board.scaleDenominator,
                                  "paper": board.background.rawValue, "nativeLink": BoardLinks.url(for: board.id).absoluteString]]
    }

    /// API-only vectors. Craft's documented elements endpoint has no asset upload field.
    /// Failing explicitly prevents a user from unknowingly publishing missing image diagrams.
    static func vectorElements(board: Board) throws -> [[String: Any]] {
        let scene = try scene(board: board)
        guard let files = scene["files"] as? [String: Any], files.isEmpty else { throw Failure.assetsNeedFileExport }
        return scene["elements"] as? [[String: Any]] ?? []
    }

    private static func elementID(board: Board, item: DrawingElement) -> String {
        "karim-" + board.id.uuidString.lowercased() + "-" + item.id.uuidString.lowercased()
    }

    private static func base(item: DrawingElement, board: Board, type: String) -> [String: Any] {
        let first = item.points[0], last = item.points.last!
        let bounds: CGRect
        if item.kind == .text {
            bounds = item.bounds.insetBy(dx: max(item.width / 2, 2), dy: max(item.width / 2, 2))
        } else if item.kind == .stroke || item.kind == .triangle {
            let xs = item.points.map(\.x), ys = item.points.map(\.y)
            bounds = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        } else {
            bounds = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
        }
        let visible = BoardRenderer.visibleColor(item.color, board: board).usingColorSpace(.sRGB) ?? item.color.ns
        let stroke = String(format: "#%02X%02X%02X", Int((visible.redComponent * 255).rounded()), Int((visible.greenComponent * 255).rounded()), Int((visible.blueComponent * 255).rounded()))
        let custom: [String: Any] = ["app": "Karim Eldamaty", "boardID": board.id.uuidString, "elementID": item.id.uuidString,
                                     "nativeKind": item.kind.rawValue, "pen": item.pen.rawValue, "nativeLink": BoardLinks.url(for: board.id).absoluteString,
                                     "pointsPerMM": board.pointsPerMM, "scaleDenominator": board.scaleDenominator]
        return ["id": elementID(board: board, item: item), "type": type,
                "x": bounds.minX, "y": bounds.minY, "width": max(0, bounds.width), "height": max(0, bounds.height),
                "angle": item.rotation * .pi / 180, "strokeColor": stroke,
                "backgroundColor": item.fill ? stroke : "transparent", "fillStyle": "solid", "strokeWidth": item.width,
                "strokeStyle": item.dash == "Dotted" ? "dotted" : (item.dash == "Solid" ? "solid" : "dashed"),
                "roughness": 0, "opacity": Int((item.color.a * 100).rounded()), "seed": 1, "version": 1, "versionNonce": 1,
                "index": NSNull(), "isDeleted": false, "groupIds": [], "frameId": NSNull(), "roundness": NSNull(),
                "boundElements": NSNull(), "updated": milliseconds(board.modified), "created": milliseconds(board.created),
                "link": BoardLinks.url(for: board.id).absoluteString, "locked": item.locked, "customData": custom]
    }

    private static func line(item: DrawingElement, board: Board, type: String) -> [String: Any] {
        var value = base(item: item, board: board, type: type)
        let first = item.points[0], last = item.points.last!
        value["x"] = first.x; value["y"] = first.y
        value["points"] = [[0, 0], [last.x - first.x, last.y - first.y]]
        value["startBinding"] = NSNull(); value["endBinding"] = NSNull()
        value["startArrowhead"] = NSNull(); value["endArrowhead"] = type == "arrow" ? "arrow" : NSNull()
        value["elbowed"] = false; value["polygon"] = false
        return value
    }

    private static func text(item: DrawingElement, board: Board) -> [String: Any] {
        var value = base(item: item, board: board, type: "text")
        value["fontSize"] = item.fontSize; value["fontFamily"] = 2
        value["text"] = item.text; value["originalText"] = item.text
        value["textAlign"] = "left"; value["verticalAlign"] = "top"
        value["containerId"] = NSNull(); value["baseFontSize"] = NSNull()
        value["autoResize"] = true; value["lineHeight"] = 1.4
        return value
    }

    private static func rasterAsset(item: DrawingElement, board: Board) throws -> (id: String, data: Data, bounds: CGRect) {
        let original = item.bounds
        let center = CGPoint(x: original.midX, y: original.midY)
        let angle = item.rotation * .pi / 180
        let corners = [CGPoint(x: original.minX, y: original.minY), CGPoint(x: original.maxX, y: original.minY),
                       CGPoint(x: original.maxX, y: original.maxY), CGPoint(x: original.minX, y: original.maxY)]
        let bounds = corners.reduce(CGRect.null) { bounds, point in
            let dx = point.x - center.x, dy = point.y - center.y
            let rotated = CGPoint(x: center.x + dx * cos(angle) - dy * sin(angle), y: center.y + dx * sin(angle) + dy * cos(angle))
            return bounds.union(CGRect(origin: rotated, size: .zero))
        }
        let scale = min(2, 2048 / max(1, max(bounds.width, bounds.height)))
        let width = max(1, Int(ceil(bounds.width * scale))), height = max(1, Int(ceil(bounds.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.rasterUnavailable }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        BoardRenderer.draw(element: item, on: board, context: context)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw Failure.rasterUnavailable }
        return (elementID(board: board, item: item) + "-asset", data, bounds)
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1000
        guard value.isFinite else { return 0 }
        return Int64(max(-9_000_000_000_000_000, min(9_000_000_000_000_000, value)))
    }
    private static func backgroundColor(_ paper: BackgroundKind) -> String {
        switch paper { case .blueprint: return "#13335C"; case .dark: return "#1A1F26"; default: return "#FEFDF9" }
    }

    enum Failure: LocalizedError {
        case rasterUnavailable, assetsNeedFileExport
        var errorDescription: String? {
            switch self {
            case .rasterUnavailable: return "A diagram could not be rendered for the editable whiteboard export."
            case .assetsNeedFileExport: return "This board includes images or complex engineering diagrams. Export an Excalidraw file or PNG to preserve them; direct Craft vector sync currently supports basic shapes, text and pen paths."
            }
        }
    }
}
