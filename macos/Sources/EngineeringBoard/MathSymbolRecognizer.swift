import Foundation
import CoreGraphics
import CoreML
import CoreVideo

struct MathSymbolDefinition: Codable, Identifiable, Sendable {
    let id: String
    let command: String
    let package: String?

    var nativeUnicode: String? { MathSymbolCatalog.nativeUnicode(for: self) }
}

struct MathSymbolCandidate: Identifiable, Sendable {
    let definition: MathSymbolDefinition
    let score: Double
    var id: String { definition.id }
}

enum MathSymbolRecognitionError: LocalizedError {
    case emptyDrawing
    case invalidCoordinates
    case degenerateDrawing
    case drawingTooLarge
    case missingResource(String)
    case invalidCatalog
    case modelUnavailable
    case predictionFailed

    var errorDescription: String? {
        switch self {
        case .emptyDrawing: return "Draw or select one handwritten symbol first."
        case .invalidCoordinates: return "This drawing has invalid coordinates or lies outside the supported range. Select a different symbol."
        case .degenerateDrawing: return "The selected drawing has no visible stroke length. Draw one symbol and try again."
        case .drawingTooLarge: return "Select a smaller drawing of one symbol (at most 2,048 strokes and 100,000 points)."
        case .missingResource(let name): return "The offline symbol resource \(name) is missing. Reinstall SketchGlide."
        case .invalidCatalog: return "The offline symbol catalogue couldn't be read. Reinstall SketchGlide."
        case .modelUnavailable: return "The offline symbol model couldn't be loaded on this Mac."
        case .predictionFailed: return "The offline model couldn't recognize this symbol. Try drawing it more clearly."
        }
    }
}

enum MathSymbolCatalog {
    private static let loaded: Result<[MathSymbolDefinition], Error> = Result {
        let url = try MathSymbolResources.url(for: "symbols.json")
        let definitions: [MathSymbolDefinition]
        do { definitions = try JSONDecoder().decode([MathSymbolDefinition].self, from: Data(contentsOf: url)) }
        catch { throw MathSymbolRecognitionError.invalidCatalog }
        guard !definitions.isEmpty, Set(definitions.map(\.id)).count == definitions.count,
              definitions.allSatisfy({ !$0.id.isEmpty && !$0.command.isEmpty }) else {
            throw MathSymbolRecognitionError.invalidCatalog
        }
        return definitions
    }

    static var all: [MathSymbolDefinition] { (try? loaded.get()) ?? [] }
    static let byID: [String: MathSymbolDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static var loadingError: String? {
        if case .failure(let error) = loaded { return error.localizedDescription }
        return nil
    }

    static func load() throws -> [MathSymbolDefinition] { try loaded.get() }

    /// A small independent mapping. No upstream Unicode table or SVG assets are imported.
    static func nativeUnicode(for definition: MathSymbolDefinition) -> String? {
        nativeUnicode(for: definition.command)
    }

    static func nativeUnicode(for command: String) -> String? {
        if command.hasPrefix("\\"), let value = MathParser.commands[String(command.dropFirst())] { return value }
        if let value = additionalGlyphs[command] { return value }
        if command.count == 1, let character = command.first, !character.isWhitespace, character != "\\" {
            return command
        }
        return nil
    }

    private static let additionalGlyphs: [String: String] = [
        "\\le": "≤", "\\ge": "≥", "\\ne": "≠", "\\equiv": "≡", "\\propto": "∝",
        "\\mp": "∓", "\\div": "÷", "\\cdotp": "·", "\\ldots": "…", "\\cdots": "⋯",
        "\\forall": "∀", "\\exists": "∃", "\\nexists": "∄", "\\in": "∈", "\\notin": "∉",
        "\\emptyset": "∅", "\\varnothing": "∅", "\\subset": "⊂", "\\supset": "⊃",
        "\\subseteq": "⊆", "\\supseteq": "⊇", "\\cup": "∪", "\\cap": "∩",
        "\\vee": "∨", "\\wedge": "∧", "\\perp": "⊥", "\\parallel": "∥", "\\angle": "∠",
        "\\surd": "√", "\\hbar": "ℏ", "\\ell": "ℓ", "\\aleph": "ℵ",
        "\\leftrightarrow": "↔", "\\Rightarrow": "⇒", "\\Leftarrow": "⇐", "\\Leftrightarrow": "⇔",
        "\\uparrow": "↑", "\\downarrow": "↓", "\\mapsto": "↦", "\\chi": "χ", "\\psi": "ψ",
        "\\zeta": "ζ", "\\eta": "η", "\\kappa": "κ", "\\xi": "ξ", "\\upsilon": "υ",
        "\\Gamma": "Γ", "\\Theta": "Θ", "\\Lambda": "Λ", "\\Xi": "Ξ", "\\Pi": "Π", "\\Psi": "Ψ"
    ]
}

private enum MathSymbolResources {
    static func url(for name: String) throws -> URL {
        var directories: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            directories.append(resourceURL.appendingPathComponent("MathSymbols", isDirectory: true))
        }
        #if DEBUG
        // Development-only fallback. Public release resources come exclusively
        // from the signed app bundle; never embed an author's checkout path.
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        directories.append(projectURL.appendingPathComponent("Resources/MathSymbols", isDirectory: true))
        #endif
        for directory in directories {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        throw MathSymbolRecognitionError.missingResource(name)
    }
}

actor MathSymbolRecognizer {
    static let shared = MathSymbolRecognizer()
    private var cachedModel: MLModel?

    /// Recognizes one symbol locally. Scores indicate ranking, not a guarantee of correctness.
    func recognize(strokes: [[CGPoint]]) async throws -> [MathSymbolCandidate] {
        try Task.checkCancellation()
        // Validate before loading or running the model, including empty/degenerate input.
        let pixelBuffer = try Self.rasterize(strokes: strokes)
        _ = try MathSymbolCatalog.load()
        let model = try loadModel()
        try Task.checkCancellation()
        let result: MLFeatureProvider
        do {
            let input = try MLDictionaryFeatureProvider(dictionary: ["drawing": MLFeatureValue(pixelBuffer: pixelBuffer)])
            result = try await model.prediction(from: input)
        } catch is CancellationError { throw CancellationError() }
        catch { throw MathSymbolRecognitionError.predictionFailed }
        try Task.checkCancellation()
        guard let scores = result.featureValue(for: "classLabelProbs")?.dictionaryValue else {
            throw MathSymbolRecognitionError.predictionFailed
        }
        let candidates = scores.compactMap { key, value -> MathSymbolCandidate? in
            guard let id = key as? String, let definition = MathSymbolCatalog.byID[id],
                  value.doubleValue.isFinite, value.doubleValue >= 0 else { return nil }
            return MathSymbolCandidate(definition: definition, score: value.doubleValue)
        }.sorted {
            $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
        }
        guard !candidates.isEmpty else { throw MathSymbolRecognitionError.predictionFailed }
        return Array(candidates.prefix(20))
    }

    private func loadModel() throws -> MLModel {
        if let cachedModel { return cachedModel }
        let compiledURL: URL
        if let bundledCompiled = try? MathSymbolResources.url(for: "deTeX.mlmodelc") {
            compiledURL = bundledCompiled
        } else {
            let sourceURL = try MathSymbolResources.url(for: "deTeX.mlmodel")
            do { compiledURL = try MLModel.compileModel(at: sourceURL) }
            catch { throw MathSymbolRecognitionError.modelUnavailable }
        }
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
            cachedModel = model
            return model
        } catch { throw MathSymbolRecognitionError.modelUnavailable }
    }

    /// Produces only a 300 × 200 opaque bitmap, independent of board colours and textures.
    /// Bitmap row coordinates match input top-left drawing coordinates.
    nonisolated static func rasterize(strokes: [[CGPoint]]) throws -> CVPixelBuffer {
        guard strokes.count <= 2_048 else { throw MathSymbolRecognitionError.drawingTooLarge }
        var count = 0
        for stroke in strokes {
            guard stroke.count <= 100_000 - count else { throw MathSymbolRecognitionError.drawingTooLarge }
            count += stroke.count
        }
        guard count > 0 else { throw MathSymbolRecognitionError.emptyDrawing }
        guard count <= 100_000 else { throw MathSymbolRecognitionError.drawingTooLarge }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for stroke in strokes {
            for point in stroke {
                guard point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000_000, abs(point.y) <= 1_000_000_000 else {
                    throw MathSymbolRecognitionError.invalidCoordinates
                }
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
        }
        let spanX = maxX - minX, spanY = maxY - minY
        guard spanX.isFinite, spanY.isFinite else { throw MathSymbolRecognitionError.invalidCoordinates }
        guard max(spanX, spanY) > 0.000_001 else { throw MathSymbolRecognitionError.degenerateDrawing }
        let scale = min(250 / max(spanX, 0.000_001), (200 / 1.2) / max(spanY, 0.000_001))
        let offsetX = (300 - spanX * scale) / 2
        let offsetY = (200 - spanY * scale) / 2
        guard scale.isFinite, offsetX.isFinite, offsetY.isFinite else { throw MathSymbolRecognitionError.invalidCoordinates }

        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true,
                          kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, 300, 200, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer else { throw MathSymbolRecognitionError.predictionFailed }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw MathSymbolRecognitionError.predictionFailed }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 300, height: 200,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else {
            throw MathSymbolRecognitionError.predictionFailed
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        // Core Graphics bitmap coordinates point upward; pen coordinates point downward.
        context.translateBy(x: 0, y: 200)
        context.scaleBy(x: 1, y: -1)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        func normalized(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x - minX) * scale + offsetX, y: (point.y - minY) * scale + offsetY)
        }
        for stroke in strokes where !stroke.isEmpty {
            let first = normalized(stroke[0])
            if stroke.count == 1 {
                context.fillEllipse(in: CGRect(x: first.x - 2.5, y: first.y - 2.5, width: 5, height: 5))
            } else {
                context.beginPath()
                context.move(to: first)
                for point in stroke.dropFirst() { context.addLine(to: normalized(point)) }
                context.strokePath()
            }
        }
        return buffer
    }
}
