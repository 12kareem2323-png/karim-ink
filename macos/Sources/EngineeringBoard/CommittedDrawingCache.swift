import AppKit
import Dispatch

/// A disposable, screen-density cache. The document stays vector based. Tiles
/// are regenerated at each zoom/backing-scale change and evicted by bitmap cost.
@MainActor
final class CommittedDrawingCache {
    enum Layer: Int { case all, highlighters, foreground }
    private struct Key: Hashable { let x: Int; let y: Int; let layer: Int }
    private struct Tile { let image: CGImage; let rect: CGRect; let cost: Int; var used: UInt64 }
    private var tiles: [Key: Tile] = [:]
    private var clock: UInt64 = 0
    private var boardID: UUID?
    private var revision = -1
    private var density: Double = 0
    private var style: String = ""
    private var previous: [UUID: DrawingElement] = [:]
    private var previousBounds: [UUID: CGRect] = [:]
    private var order: [UUID] = []
    private(set) var bitmapBytes = 0
    private(set) var renderedTiles = 0
    private(set) var cacheHits = 0
    private let budget = 48 * 1024 * 1024
    private let side = 512
    private let gutter = 3
    private var memoryPressure: DispatchSourceMemoryPressure?

    init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.clear() } }
        source.resume(); memoryPressure = source
    }
    deinit { memoryPressure?.cancel() }

    func clear() { tiles.removeAll(); bitmapBytes = 0 }
    func reset() { clear(); previous.removeAll(); previousBounds.removeAll(); order.removeAll(); boardID = nil; revision = -1 }

    func synchronise(board: Board, revision: Int, bounds: [UUID: CGRect], density requested: Double) {
        let nextDensity = min(32, max(0.05, requested))
        let nextStyle = "\(board.background.rawValue)|\(board.pointsPerMM)|\(board.scaleDenominator)"
        if boardID != board.id || density != nextDensity || style != nextStyle {
            clear(); boardID = board.id; density = nextDensity; style = nextStyle
            self.revision = -1
        }
        guard self.revision != revision else { return }
        let current = Dictionary(uniqueKeysWithValues: board.elements.map { ($0.id, $0) })
        let ids = board.elements.map(\.id)
        let oldIDs = Set(order), newIDs = Set(ids)
        // Reordering existing objects can change blending anywhere they overlap.
        if order.filter({ newIDs.contains($0) }) != ids.filter({ oldIDs.contains($0) }) { clear() }
        else {
            let appended = ids.count > order.count && Array(ids.prefix(order.count)) == order
                && previous.allSatisfy { current[$0.key] == $0.value }
            if appended {
                let additions = board.elements.dropFirst(order.count)
                for key in Array(tiles.keys) {
                    guard var tile = tiles[key] else { continue }
                    let relevant = additions.filter { element in
                        let highlighter = element.kind == .stroke && element.pen == .highlighter
                        return (key.layer == Layer.highlighters.rawValue ? highlighter : !highlighter)
                            && bounds[element.id]?.intersects(tile.rect) == true
                    }
                    guard !relevant.isEmpty else { continue }
                    if let image = raster(rect: tile.rect, board: board, elements: relevant, base: tile.image) {
                        tile = Tile(image: image, rect: tile.rect, cost: tile.cost, used: tile.used)
                        tiles[key] = tile; renderedTiles += 1
                    } else { tiles.removeValue(forKey: key); bitmapBytes -= tile.cost }
                }
                previous = current; previousBounds = bounds; order = ids; self.revision = revision
                return
            }
            var changed: [CGRect] = []
            for (id, old) in previous {
                if current[id] != old, let rect = previousBounds[id] { changed.append(rect) }
            }
            for (id, item) in current {
                if previous[id] != item, let rect = bounds[id] { changed.append(rect) }
            }
            if !changed.isEmpty {
                let invalid = tiles.filter { _, tile in changed.contains { tile.rect.intersects($0) } }.map(\.key)
                for key in invalid { if let tile = tiles.removeValue(forKey: key) { bitmapBytes -= tile.cost } }
            }
        }
        previous = current; previousBounds = bounds; order = ids; self.revision = revision
    }

    func draw(world: CGRect, board: Board, layer: Layer, context: CGContext,
              elements: (CGRect) -> [DrawingElement]) {
        guard density > 0, !world.isEmpty else { return }
        if layer == .all {
            draw(world: world, board: board, layer: .highlighters, context: context, elements: elements)
            draw(world: world, board: board, layer: .foreground, context: context, elements: elements)
            return
        }
        let span = Double(side) / density
        let x0 = Int(floor(world.minX / span)), x1 = Int(floor(world.maxX / span))
        let y0 = Int(floor(world.minY / span)), y1 = Int(floor(world.maxY / span))
        // The native viewport is bounded, including at extreme document zoom.
        guard x1 - x0 < 64, y1 - y0 < 64 else { return }
        context.saveGState(); context.clip(to: world)
        defer { context.restoreGState() }
        for y in y0...y1 { for x in x0...x1 {
            let key = Key(x: x, y: y, layer: layer.rawValue)
            let cell = CGRect(x: Double(x) * span, y: Double(y) * span, width: span, height: span)
            clock &+= 1
            let tile: Tile
            if var cached = tiles[key] {
                cached.used = clock; tiles[key] = cached; tile = cached; cacheHits += 1
            } else {
                let rect = cell.insetBy(dx: -Double(gutter) / density, dy: -Double(gutter) / density)
                let pixels = side + 2 * gutter
                let candidates = elements(rect)
                let drawn = candidates.filter { element in
                    let highlighter = element.kind == .stroke && element.pen == .highlighter
                    return layer == .highlighters ? highlighter : !highlighter
                }
                guard let image = raster(rect: rect, board: board, elements: drawn) else { continue }
                tile = Tile(image: image, rect: rect, cost: pixels * pixels * 4, used: clock)
                while bitmapBytes + tile.cost > budget, let oldest = tiles.min(by: { $0.value.used < $1.value.used })?.key {
                    if let removed = tiles.removeValue(forKey: oldest) { bitmapBytes -= removed.cost }
                }
                tiles[key] = tile; bitmapBytes += tile.cost; renderedTiles += 1
            }
            context.saveGState(); context.setShouldAntialias(false); context.clip(to: cell)
            context.translateBy(x: tile.rect.minX, y: tile.rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .low
            context.draw(tile.image, in: CGRect(origin: .zero, size: tile.rect.size))
            context.restoreGState()
        }}
    }
    private func raster(rect: CGRect, board: Board, elements: some Sequence<DrawingElement>, base: CGImage? = nil) -> CGImage? {
        let pixels = side + 2 * gutter
        guard let bitmap = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if let base { bitmap.draw(base, in: CGRect(x: 0, y: 0, width: pixels, height: pixels)) }
        bitmap.translateBy(x: 0, y: Double(pixels)); bitmap.scaleBy(x: density, y: -density)
        bitmap.translateBy(x: -rect.minX, y: -rect.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)
        for element in elements { BoardRenderer.draw(element: element, on: board, context: bitmap) }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.makeImage()
    }

}
