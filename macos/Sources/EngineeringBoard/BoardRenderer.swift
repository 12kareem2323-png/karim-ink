import AppKit

/// All board coordinates use points measured from the upper-left of the sheet.
@MainActor
enum BoardRenderer {
    static func image(board: Board, scale: CGFloat = 1) -> NSImage {
        let width = max(1, board.width.isFinite ? board.width : 1)
        let height = max(1, board.height.isFinite ? board.height : 1)
        let requested = scale.isFinite && scale > 0 ? min(scale, 8) : 1
        let validScale = min(requested, 8192 / max(width, height), sqrt(32_000_000 / (width * height)))
        return NSImage(size: NSSize(width: board.width * validScale, height: board.height * validScale), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.scaleBy(x: validScale, y: validScale)
            draw(board: board)
            context.restoreGState()
            return true
        }
    }

    static func draw(board: Board) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShouldAntialias(true)
        context.clip(to: CGRect(x: 0, y: 0, width: board.width, height: board.height))
        drawBackground(board, context: context)
        for element in board.elements { draw(element: element, on: board, context: context) }
        context.restoreGState()
    }

    static func visibleColor(_ color: InkColor, board: Board) -> NSColor {
        if (board.background == .blueprint || board.background == .dark) && color == .graphite {
            return NSColor(srgbRed: 0.91, green: 0.96, blue: 1, alpha: color.a)
        }
        return color.ns
    }

    private static func drawBackground(_ board: Board, context: CGContext) {
        let blueprint = board.background == .blueprint
        let dark = blueprint || board.background == .dark
        let paper = board.background == .dark ? NSColor(srgbRed: 0.10, green: 0.12, blue: 0.15, alpha: 1) : (blueprint ? NSColor(srgbRed: 0.075, green: 0.20, blue: 0.36, alpha: 1) : NSColor(srgbRed: 0.998, green: 0.994, blue: 0.98, alpha: 1))
        paper.setFill()
        context.fill(CGRect(x: 0, y: 0, width: board.width, height: board.height))
        let spacing = max(8, min(board.gridSpacing, 200))
        let thin = dark ? NSColor.white.withAlphaComponent(0.13) : NSColor(srgbRed: 0.41, green: 0.57, blue: 0.67, alpha: 0.15)
        let strong = dark ? NSColor.white.withAlphaComponent(0.27) : NSColor(srgbRed: 0.30, green: 0.46, blue: 0.58, alpha: 0.24)
        switch board.background {
        case .plain: break
        case .lined:
            context.setStrokeColor(thin.cgColor); context.setLineWidth(0.8)
            for y in stride(from: spacing, through: board.height, by: spacing) {
                context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: board.width, y: y))
            }
            context.strokePath()
            context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.23).cgColor)
            context.move(to: CGPoint(x: 80, y: 0)); context.addLine(to: CGPoint(x: 80, y: board.height)); context.strokePath()
        case .dots:
            // AppKit tiles the pattern in the graphics engine; giant imported sheets
            // do not create millions of individual dot draw calls.
            let tile = NSImage(size: NSSize(width: spacing, height: spacing), flipped: true) { _ in
                strong.setFill()
                NSBezierPath(ovalIn: CGRect(x: spacing / 2 - 1, y: spacing / 2 - 1, width: 2, height: 2)).fill()
                return true
            }
            NSColor(patternImage: tile).setFill()
            context.fill(CGRect(x: 0, y: 0, width: board.width, height: board.height))
        case .isometric:
            context.setStrokeColor(thin.cgColor); context.setLineWidth(0.7)
            for y in stride(from: 0.0, through: board.height, by: spacing * sqrt(3) / 2) {
                context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: board.width, y: y))
            }
            let offset = board.height / sqrt(3)
            for x in stride(from: -offset, through: board.width + offset, by: spacing) {
                context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x + offset, y: board.height))
                context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x - offset, y: board.height))
            }
            context.strokePath()
        case .polar:
            let centre = CGPoint(x: board.width / 2, y: board.height / 2)
            let radius = hypot(board.width / 2, board.height / 2)
            context.setStrokeColor(thin.cgColor); context.setLineWidth(0.7)
            for r in stride(from: spacing, through: radius, by: spacing) {
                context.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
            }
            for i in 0..<24 {
                let angle = Double(i) * .pi / 12
                context.move(to: centre)
                context.addLine(to: CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius))
            }
            context.strokePath()
        case .grid, .graph, .engineering, .blueprint, .dark:
            let graph = board.background == .graph
            let fineSpacing = graph ? max(3, spacing / 5) : spacing
            context.setStrokeColor(thin.cgColor); context.setLineWidth(graph ? 0.4 : 0.7)
            for x in stride(from: fineSpacing, through: board.width, by: fineSpacing) {
                context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: board.height))
            }
            for y in stride(from: fineSpacing, through: board.height, by: fineSpacing) {
                context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: board.width, y: y))
            }
            context.strokePath()
            if graph || blueprint || board.background == .engineering {
                let majorSpacing = graph ? spacing : spacing * 5
                context.setStrokeColor(strong.cgColor); context.setLineWidth(0.9)
                for x in stride(from: majorSpacing, through: board.width, by: majorSpacing) {
                    context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: board.height))
                }
                for y in stride(from: majorSpacing, through: board.height, by: majorSpacing) {
                    context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: board.width, y: y))
                }
                context.strokePath()
            }
        }
        if board.background == .engineering {
            let margin: CGFloat = 36
            let border = CGRect(x: margin, y: margin, width: max(0, board.width - 2 * margin), height: max(0, board.height - 2 * margin))
            context.setStrokeColor(NSColor(srgbRed: 0.29, green: 0.38, blue: 0.45, alpha: 0.72).cgColor)
            context.setLineWidth(1.3); context.stroke(border)
            let boxWidth = min(620.0, max(240, border.width))
            let box = CGRect(x: border.maxX - boxWidth, y: border.maxY - 98, width: boxWidth, height: 98)
            context.stroke(box)
            context.move(to: CGPoint(x: box.minX, y: box.minY + 52)); context.addLine(to: CGPoint(x: box.maxX, y: box.minY + 52))
            context.move(to: CGPoint(x: box.minX + boxWidth * 0.56, y: box.minY + 52)); context.addLine(to: CGPoint(x: box.minX + boxWidth * 0.56, y: box.maxY)); context.strokePath()
            label(board.title, at: CGPoint(x: box.minX + 14, y: box.minY + 10), font: 21, color: .darkGray)
            label("DRAWING SCALE  1:\(formatted(board.scaleDenominator))", at: CGPoint(x: box.minX + 14, y: box.minY + 63), font: 14, color: .darkGray)
            label("DIMENSIONS IN mm", at: CGPoint(x: box.minX + boxWidth * 0.56 + 14, y: box.minY + 63), font: 14, color: .darkGray)
        }
    }

    static func draw(element: DrawingElement, on board: Board, context: CGContext) {
        guard let first = element.points.first else { return }
        context.saveGState()
        if element.rotation != 0 {
            let bounds = element.bounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: element.rotation * .pi / 180)
            context.translateBy(x: -center.x, y: -center.y)
        }
        let color = visibleColor(element.color, board: board)
        context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor)
        context.setLineWidth(max(0.2, element.width)); context.setLineCap(.round); context.setLineJoin(.round)
        switch element.dash {
        case "Dashed", "Hidden": context.setLineDash(phase: 0, lengths: [element.width * 4 + 6, element.width * 2 + 4])
        case "Centre": context.setLineDash(phase: 0, lengths: [20, 5, 3, 5])
        case "Dotted": context.setLineDash(phase: 0, lengths: [1, element.width * 2 + 3])
        default: break
        }
        let last = element.points.last ?? first
        let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
        switch element.kind {
        case .stroke:
            // Texture grains create short-lived Cocoa colour objects. Drain them
            // per stroke rather than retaining a large board's whole render pass.
            autoreleasepool { drawStroke(element, color: color, context: context) }
        case .line, .arrow:
            context.move(to: first.cg); context.addLine(to: last.cg); context.strokePath()
            if element.kind == .arrow { arrowHead(at: last.cg, toward: first.cg, size: max(12, element.width * 4), context: context) }
        case .rectangle:
            context.addRect(rect); finishShape(element, color: color, context: context)
        case .ellipse:
            context.addEllipse(in: rect); finishShape(element, color: color, context: context)
        case .triangle:
            if element.points.count >= 3 {
                context.move(to: element.points[0].cg); context.addLine(to: element.points[1].cg); context.addLine(to: element.points[2].cg)
            } else {
                context.move(to: CGPoint(x: rect.midX, y: rect.minY)); context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            }
            context.closePath(); finishShape(element, color: color, context: context)
        case .arc:
            context.saveGState(); context.translateBy(x: rect.midX, y: rect.maxY)
            context.scaleBy(x: max(0.001, rect.width / 2), y: max(0.001, rect.height))
            context.setLineWidth(element.width / max(1, rect.width / 2))
            context.addArc(center: .zero, radius: 1, startAngle: .pi, endAngle: 0, clockwise: false); context.strokePath(); context.restoreGState()
        case .dimension: drawDimension(first: first.cg, last: last.cg, board: board, element: element, color: color, context: context)
        case .text:
            let font = NSFont.systemFont(ofSize: element.fontSize)
            (element.text as NSString).draw(at: first.cg, withAttributes: [.font: font, .foregroundColor: color])
        case .image:
            if let data = element.imageData, let image = try? SafeImage.decode(data, cacheID: element.id) {
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            }
        case .symbol:
            if element.text.hasPrefix("mathlatex:") {
                NativeMathRenderer.draw(latex: String(element.text.dropFirst(10)), in: rect, context: context, color: color)
            } else if element.text.hasPrefix("catalog:"), let definition = SymbolCatalog.definition(id: String(element.text.dropFirst(8))) {
                DiagramRenderer.draw(definition: definition, in: rect, context: context, color: color)
            } else { drawSymbol(element.text.lowercased(), rect: rect, context: context) }
        }
        context.restoreGState()
    }

    private static func drawStroke(_ element: DrawingElement, color: NSColor, context: CGContext) {
        guard !element.points.isEmpty else { return }
        context.setLineDash(phase: 0, lengths: [])
        let settings = element.effectiveBrushSettings
        // Pressure coverage, calligraphy and spray do not need a second complete
        // silhouette. Build it only for brushes which fill or clip to that shape.
        var cachedPath: CGPath?
        func coveragePath() -> CGPath {
            if let cachedPath { return cachedPath }
            let path = strokePath(element)
            cachedPath = path
            return path
        }
        let meanPressure = element.points.reduce(0) { $0 + $1.pressure } / Double(element.points.count)
        let averageAlpha = BrushMetrics.opacity(element: element, point: InkPoint(x: 0, y: 0, pressure: meanPressure))
        func fill(_ alpha: Double) {
            context.setFillColor(color.withAlphaComponent(color.alphaComponent * max(0, min(1, alpha))).cgColor)
            context.addPath(coveragePath()); context.fillPath()
        }
        switch element.pen {
        case .technical:
            fill(averageAlpha)
        case .fountain, .liquid:
            drawPressureCoverage(element, color: color, context: context)
        case .calligraphy:
            let samples = resampled(element, spacing: max(0.8, settings.maxWidth * 0.055))
            let angle = Double.pi / 4
            context.beginTransparencyLayer(in: element.bounds, auxiliaryInfo: nil)
            context.setBlendMode(.copy)
            for point in samples {
                let nib = CGMutablePath()
                let width = settings.width(pressure: point.pressure)
                let along = CGPoint(x: cos(angle) * width / 2, y: sin(angle) * width / 2)
                let across = CGPoint(x: -sin(angle) * width * 0.075, y: cos(angle) * width * 0.075)
                nib.move(to: CGPoint(x: point.x - along.x - across.x, y: point.y - along.y - across.y))
                nib.addLine(to: CGPoint(x: point.x + along.x - across.x, y: point.y + along.y - across.y))
                nib.addLine(to: CGPoint(x: point.x + along.x + across.x, y: point.y + along.y + across.y))
                nib.addLine(to: CGPoint(x: point.x - along.x + across.x, y: point.y - along.y + across.y)); nib.closeSubpath()
                context.setFillColor(color.withAlphaComponent(color.alphaComponent * BrushMetrics.opacity(element: element, point: point)).cgColor)
                context.addPath(nib); context.fillPath()
            }
            context.setBlendMode(.normal); context.endTransparencyLayer()
        case .highlighter, .marker:
            // One coverage path keeps a single sweep even; separate sweeps accumulate colour.
            if settings.pressureEnabled { drawPressureCoverage(element, color: color, context: context) }
            else { fill(averageAlpha) }
            if element.pen == .marker {
                context.saveGState(); context.addPath(coveragePath()); context.clip()
                context.setStrokeColor(color.withAlphaComponent(color.alphaComponent * averageAlpha * 0.18).cgColor)
                context.setLineWidth(max(0.5, settings.maxWidth * 0.09))
                let offset = settings.maxWidth * 0.28
                context.move(to: CGPoint(x: element.points[0].x + offset, y: element.points[0].y))
                for point in element.points.dropFirst() { context.addLine(to: CGPoint(x: point.x + offset, y: point.y)) }
                context.strokePath(); context.restoreGState()
            }
        case .pencil, .chalk:
            let pencil = element.pen == .pencil
            fill(averageAlpha * (pencil ? settings.pencilGrade.darkness * 0.10 : 0.14))
            context.saveGState(); context.addPath(coveragePath()); context.clip()
            var random = TextureRandom(element.id)
            let samples = resampled(element, spacing: max(0.55, settings.maxWidth * 0.12))
            for point in samples {
                let width = BrushMetrics.width(element: element, point: point)
                let alpha = BrushMetrics.opacity(element: element, point: point)
                let density = pencil ? 9 : 13
                for _ in 0..<density {
                    let x = point.x + (random.next() - 0.5) * width
                    let y = point.y + (random.next() - 0.5) * width
                    let radius = (pencil ? 0.12 + random.next() * 0.55 : 0.25 + random.next() * 1.05) * settings.textureScale
                    let darkness = pencil ? settings.pencilGrade.darkness : 0.88
                    context.setFillColor(color.withAlphaComponent(color.alphaComponent * alpha * darkness * (0.25 + random.next() * 0.6)).cgColor)
                    context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * (pencil ? 1.1 : 1.7)))
                }
            }
            context.restoreGState()
        case .airbrush:
            let samples = resampled(element, spacing: max(1, settings.maxWidth * 0.22))
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            for point in samples {
                let radius = BrushMetrics.width(element: element, point: point) / 2
                let alpha = BrushMetrics.opacity(element: element, point: point) * 0.35
                guard let gradient = CGGradient(colorsSpace: space, colors: [color.withAlphaComponent(color.alphaComponent * alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) else { continue }
                context.drawRadialGradient(gradient, startCenter: point.cg, startRadius: 0, endCenter: point.cg, endRadius: radius, options: [])
            }
        case .dryErase:
            context.beginTransparencyLayer(in: element.bounds, auxiliaryInfo: nil)
            drawPressureCoverage(element, color: color, context: context)
            context.saveGState(); context.addPath(coveragePath()); context.clip()
            context.setBlendMode(.clear)
            var random = TextureRandom(element.id)
            for point in resampled(element, spacing: max(1, settings.maxWidth * 0.3)) {
                let width = BrushMetrics.width(element: element, point: point)
                let side = random.next() > 0.5 ? 1.0 : -1.0
                let size = max(0.25, settings.textureScale * (0.25 + random.next() * 0.55))
                context.fillEllipse(in: CGRect(x: point.x + side * width * 0.34, y: point.y - size, width: size * 0.7, height: size * 3.2))
            }
            context.restoreGState()
            context.endTransparencyLayer()
        }
    }

    private static func drawPressureCoverage(_ element: DrawingElement, color: NSColor, context: CGContext) {
        // Copy blending inside a transparent group keeps each pressure segment's
        // opacity while preventing multiple translucent joins from getting darker.
        context.beginTransparencyLayer(in: element.bounds, auxiliaryInfo: nil)
        context.setBlendMode(.copy)
        if element.points.count == 1, let point = element.points.first {
            context.setFillColor(color.withAlphaComponent(color.alphaComponent * BrushMetrics.opacity(element: element, point: point)).cgColor)
            context.addPath(strokePath(element)); context.fillPath()
        } else {
            for i in 1..<element.points.count {
                var segment = element; segment.points = Array(element.points[(i - 1)...i])
                let alpha = (BrushMetrics.opacity(element: element, point: segment.points[0]) + BrushMetrics.opacity(element: element, point: segment.points[1])) / 2
                context.setFillColor(color.withAlphaComponent(color.alphaComponent * alpha).cgColor)
                context.addPath(strokePath(segment)); context.fillPath()
            }
        }
        context.setBlendMode(.normal)
        context.endTransparencyLayer()
    }

    private static func strokePath(_ element: DrawingElement) -> CGPath {
        let path = CGMutablePath()
        guard let first = element.points.first else { return path }
        if element.points.count == 1 {
            let width = BrushMetrics.width(element: element, point: first)
            path.addEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width)); return path
        }
        let settings = element.effectiveBrushSettings
        let constantWidth = element.pen == .technical ||
            (!settings.pressureEnabled && element.pen != .pencil && element.pen != .calligraphy && element.pen != .fountain && element.pen != .liquid)
        if constantWidth && element.points.count >= 16 {
            // Dense constant-width strokes use one round-joined outline rather
            // than overlapping rectangles and discs. Sparse corners keep the
            // existing capsule construction, including its exact tap behavior.
            let centerline = CGMutablePath()
            centerline.move(to: first.cg)
            var previous = first
            var hasSegment = false
            for point in element.points.dropFirst() {
                if hypot(point.x - previous.x, point.y - previous.y) > 0.001 { hasSegment = true }
                centerline.addLine(to: point.cg)
                previous = point
            }
            guard hasSegment else { return path }
            return centerline.copy(strokingWithWidth: BrushMetrics.width(element: element, point: first), lineCap: .round, lineJoin: .round, miterLimit: 10)
        }
        var lastCap: (center: CGPoint, radius: Double)?
        for i in 1..<element.points.count {
            let a = element.points[i - 1], b = element.points[i]
            let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
            guard length > 0.001 else { continue }
            let tangent = CGPoint(x: dx, y: dy)
            let wa = BrushMetrics.width(element: element, point: a, tangent: tangent) / 2
            let wb = BrushMetrics.width(element: element, point: b, tangent: tangent) / 2
            let nx = -dy / length, ny = dx / length
            path.move(to: CGPoint(x: a.x - nx * wa, y: a.y - ny * wa))
            path.addLine(to: CGPoint(x: b.x - nx * wb, y: b.y - ny * wb))
            path.addLine(to: CGPoint(x: b.x + nx * wb, y: b.y + ny * wb))
            path.addLine(to: CGPoint(x: a.x + nx * wa, y: a.y + ny * wa)); path.closeSubpath()
            // Adjacent segments share the same round join unless nib direction
            // changes its width. Avoid adding that identical disc twice.
            if lastCap?.center != a.cg || lastCap?.radius != wa {
                path.addEllipse(in: CGRect(x: a.x - wa, y: a.y - wa, width: wa * 2, height: wa * 2))
            }
            path.addEllipse(in: CGRect(x: b.x - wb, y: b.y - wb, width: wb * 2, height: wb * 2))
            lastCap = (b.cg, wb)
        }
        return path
    }

    private static func resampled(_ element: DrawingElement, spacing: Double) -> [InkPoint] {
        guard let first = element.points.first else { return [] }
        var result = [first]
        for i in 1..<element.points.count {
            let a = element.points[i - 1], b = element.points[i]
            let count = max(1, min(1000, Int(hypot(b.x - a.x, b.y - a.y) / max(0.2, spacing))))
            for j in 1...count {
                let t = Double(j) / Double(count)
                result.append(InkPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t,
                                       pressure: a.pressure + (b.pressure - a.pressure) * t,
                                       tiltX: a.tiltX + (b.tiltX - a.tiltX) * t, tiltY: a.tiltY + (b.tiltY - a.tiltY) * t,
                                       velocity: (a.velocity ?? 0) + ((b.velocity ?? 0) - (a.velocity ?? 0)) * t))
                if result.count >= 25000 { return result }
            }
        }
        return result
    }

    private struct TextureRandom {
        var state: UInt64
        init(_ id: UUID) { state = id.uuidString.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 } }
        mutating func next() -> Double {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Double(state & 0xFFFFFF) / Double(0xFFFFFF)
        }
    }

    private static func finishShape(_ element: DrawingElement, color: NSColor, context: CGContext) {
        if element.fill { context.setFillColor(color.withAlphaComponent(0.14).cgColor); context.drawPath(using: .fillStroke) }
        else { context.strokePath() }
    }

    private static func drawDimension(first: CGPoint, last: CGPoint, board: Board, element: DrawingElement, color: NSColor, context: CGContext) {
        let length = hypot(last.x - first.x, last.y - first.y)
        guard length > 0.01 else { return }
        let ux = (last.x - first.x) / length, uy = (last.y - first.y) / length
        let nx = -uy, ny = ux
        context.move(to: first); context.addLine(to: last)
        for point in [first, last] {
            context.move(to: CGPoint(x: point.x - nx * 9, y: point.y - ny * 9)); context.addLine(to: CGPoint(x: point.x + nx * 9, y: point.y + ny * 9))
        }
        context.strokePath()
        arrowHead(at: first, toward: last, size: 10, context: context)
        arrowHead(at: last, toward: first, size: 10, context: context)
        let value = length / max(0.0001, board.pointsPerMM) * max(0.0001, board.scaleDenominator)
        let text = "\(formatted(value)) mm"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: max(16, element.fontSize), weight: .medium), .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let position = CGPoint(x: (first.x + last.x) / 2 - size.width / 2 + nx * 17, y: (first.y + last.y) / 2 - size.height / 2 + ny * 17)
        (board.background == .dark ? NSColor(srgbRed: 0.10, green: 0.12, blue: 0.15, alpha: 1) : (board.background == .blueprint ? NSColor(srgbRed: 0.075, green: 0.20, blue: 0.36, alpha: 1) : NSColor(srgbRed: 0.998, green: 0.994, blue: 0.98, alpha: 1))).setFill()
        context.fill(CGRect(origin: position, size: size).insetBy(dx: -4, dy: -2))
        (text as NSString).draw(at: position, withAttributes: attrs)
    }

    private static func arrowHead(at tip: CGPoint, toward other: CGPoint, size: CGFloat, context: CGContext) {
        let angle = atan2(other.y - tip.y, other.x - tip.x)
        context.move(to: CGPoint(x: tip.x + cos(angle - 0.43) * size, y: tip.y + sin(angle - 0.43) * size))
        context.addLine(to: tip); context.addLine(to: CGPoint(x: tip.x + cos(angle + 0.43) * size, y: tip.y + sin(angle + 0.43) * size)); context.strokePath()
    }

    private static func drawSymbol(_ name: String, rect: CGRect, context: CGContext) {
        let w = max(30, rect.width), h = max(30, rect.height), x = rect.minX, y = rect.minY
        let cy = y + h / 2, cx = x + w / 2
        func segment(_ a: CGPoint, _ b: CGPoint) { context.move(to: a); context.addLine(to: b) }
        if name.contains("ground") {
            segment(CGPoint(x: cx, y: y), CGPoint(x: cx, y: y + h * 0.5))
            for i in 0..<3 {
                let half = w * (0.38 - Double(i) * 0.11), yy = y + h * (0.5 + Double(i) * 0.17)
                segment(CGPoint(x: cx - half, y: yy), CGPoint(x: cx + half, y: yy))
            }
        } else if name.contains("capacitor") {
            segment(CGPoint(x: x, y: cy), CGPoint(x: x + w * 0.44, y: cy)); segment(CGPoint(x: x + w * 0.56, y: cy), CGPoint(x: x + w, y: cy))
            for xx in [x + w * 0.44, x + w * 0.56] { segment(CGPoint(x: xx, y: y + h * 0.15), CGPoint(x: xx, y: y + h * 0.85)) }
        } else if name.contains("inductor") {
            segment(CGPoint(x: x, y: cy), CGPoint(x: x + w * 0.15, y: cy))
            let unit = w * 0.7 / 4
            for i in 0..<4 {
                let start = x + w * 0.15 + Double(i) * unit
                context.move(to: CGPoint(x: start, y: cy))
                context.addCurve(to: CGPoint(x: start + unit, y: cy), control1: CGPoint(x: start, y: cy - h * 0.55), control2: CGPoint(x: start + unit, y: cy - h * 0.55))
            }
            segment(CGPoint(x: x + w * 0.85, y: cy), CGPoint(x: x + w, y: cy))
        } else if name.contains("diode") {
            segment(CGPoint(x: x, y: cy), CGPoint(x: x + w * 0.35, y: cy)); segment(CGPoint(x: x + w * 0.65, y: cy), CGPoint(x: x + w, y: cy))
            context.move(to: CGPoint(x: x + w * 0.35, y: y + h * 0.16)); context.addLine(to: CGPoint(x: x + w * 0.65, y: cy)); context.addLine(to: CGPoint(x: x + w * 0.35, y: y + h * 0.84)); context.closePath()
            segment(CGPoint(x: x + w * 0.65, y: y + h * 0.16), CGPoint(x: x + w * 0.65, y: y + h * 0.84))
        } else if name.contains("source") || name.contains("voltage") {
            let diameter = min(w * 0.65, h * 0.86)
            context.addEllipse(in: CGRect(x: cx - diameter / 2, y: cy - diameter / 2, width: diameter, height: diameter))
            segment(CGPoint(x: x, y: cy), CGPoint(x: cx - diameter / 2, y: cy)); segment(CGPoint(x: cx + diameter / 2, y: cy), CGPoint(x: x + w, y: cy))
            segment(CGPoint(x: cx - diameter * 0.12, y: cy - diameter * 0.2), CGPoint(x: cx + diameter * 0.12, y: cy - diameter * 0.2))
            segment(CGPoint(x: cx, y: cy - diameter * 0.32), CGPoint(x: cx, y: cy - diameter * 0.08))
            segment(CGPoint(x: cx - diameter * 0.12, y: cy + diameter * 0.22), CGPoint(x: cx + diameter * 0.12, y: cy + diameter * 0.22))
        } else {
            // IEC-style rectangular resistor symbol with terminal leads.
            segment(CGPoint(x: x, y: cy), CGPoint(x: x + w * 0.2, y: cy)); segment(CGPoint(x: x + w * 0.8, y: cy), CGPoint(x: x + w, y: cy))
            context.addRect(CGRect(x: x + w * 0.2, y: y + h * 0.25, width: w * 0.6, height: h * 0.5))
        }
        context.strokePath()
    }

    private static func label(_ text: String, at point: CGPoint, font: CGFloat, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: font, weight: .medium), .foregroundColor: color])
    }

    static func formatted(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 { return String(format: "%.0f", value) }
        return String(format: "%.2f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}
