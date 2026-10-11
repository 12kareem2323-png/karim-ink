import Foundation
import CoreGraphics

/// Unbounded world-coordinate foundation and reusable spatial tile index.
/// Editor ink stays in world coordinates; export creates a paper snapshot.
struct WorldCamera: Equatable {
    var center = CGPoint.zero
    var zoom: Double = 1
    var viewport = CGSize(width: 1000, height: 700)
    func worldPoint(forScreen point: CGPoint) -> CGPoint {
        CGPoint(x: center.x + (point.x - viewport.width / 2) / zoom,
                y: center.y + (point.y - viewport.height / 2) / zoom)
    }
    func screenPoint(forWorld point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - center.x) * zoom + viewport.width / 2,
                y: (point.y - center.y) * zoom + viewport.height / 2)
    }
    mutating func pan(screenDelta: CGSize) { center.x -= screenDelta.width / zoom; center.y -= screenDelta.height / zoom }
    mutating func zoom(by factor: Double, anchoredAt anchor: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }
        let fixed = worldPoint(forScreen: anchor)
        zoom = min(1024, max(0.01, zoom * factor))
        let after = worldPoint(forScreen: anchor)
        center.x += fixed.x - after.x; center.y += fixed.y - after.y
    }
    var visibleWorldRect: CGRect {
        CGRect(x: center.x - viewport.width / (2 * zoom), y: center.y - viewport.height / (2 * zoom), width: viewport.width / zoom, height: viewport.height / zoom)
    }
}

struct WorldTile: Hashable { var x: Int; var y: Int }

/// Maps geometry to visible tiles. No full-canvas texture allocation is needed.
struct SpatialTileIndex {
    let tileSize: Double
    private var buckets: [WorldTile: Set<UUID>] = [:]
    private var memberships: [UUID: [WorldTile]] = [:]
    private var oversized: Set<UUID> = []
    init(tileSize: Double = 512) { self.tileSize = max(1, tileSize) }
    mutating func upsert(id: UUID, bounds: CGRect) {
        remove(id: id)
        guard !bounds.isNull, bounds.minX.isFinite, bounds.maxX.isFinite, bounds.minY.isFinite, bounds.maxY.isFinite else { return }
        let columns = floor(bounds.maxX / tileSize) - floor(bounds.minX / tileSize) + 1
        let rows = floor(bounds.maxY / tileSize) - floor(bounds.minY / tileSize) + 1
        // Very long geometry is queried globally rather than filling huge tables.
        guard columns * rows <= 4096 else { oversized.insert(id); return }
        let tiles = keys(for: bounds)
        memberships[id] = tiles
        for key in tiles { buckets[key, default: []].insert(id) }
    }
    mutating func remove(id: UUID) {
        oversized.remove(id)
        for key in memberships.removeValue(forKey: id) ?? [] {
            buckets[key]?.remove(id)
            if buckets[key]?.isEmpty == true { buckets.removeValue(forKey: key) }
        }
    }
    func query(_ rect: CGRect) -> Set<UUID> { keys(for: rect).reduce(into: oversized) { result, key in result.formUnion(buckets[key] ?? []) } }
    private func keys(for rect: CGRect) -> [WorldTile] {
        guard !rect.isNull, rect.minX.isFinite, rect.maxX.isFinite, rect.minY.isFinite, rect.maxY.isFinite else { return [] }
        let x0 = floor(rect.minX / tileSize), x1 = floor(rect.maxX / tileSize)
        let y0 = floor(rect.minY / tileSize), y1 = floor(rect.maxY / tileSize)
        guard max(abs(x0), abs(x1), abs(y0), abs(y1)) < Double(Int.max) / 2, (x1 - x0 + 1) * (y1 - y0 + 1) <= 1_000_000 else { return [] }
        return (Int(y0)...Int(y1)).flatMap { y in (Int(x0)...Int(x1)).map { x in WorldTile(x: x, y: y) } }
    }
}
