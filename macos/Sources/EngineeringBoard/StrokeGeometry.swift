import Foundation
import CoreGraphics

/// A time-aware low-pass filter: steady handwriting receives more damping while
/// fast strokes follow the tip promptly. Filtering never fabricates pressure.
struct AdaptiveInkFilter {
    private var rawPoint: CGPoint?
    private var filteredPoint: CGPoint?
    private var filteredVelocity = CGPoint.zero
    private var timestamp: TimeInterval?

    mutating func reset() {
        rawPoint = nil; filteredPoint = nil; filteredVelocity = .zero; timestamp = nil
    }

    mutating func sample(_ point: CGPoint, at time: TimeInterval, smoothing: Double, zoom: Double) -> CGPoint {
        guard point.x.isFinite, point.y.isFinite, time.isFinite else { return filteredPoint ?? .zero }
        let amount = min(0.85, max(0, smoothing))
        guard amount > 0, let previousRaw = rawPoint, let previousFiltered = filteredPoint,
              let previousTime = timestamp, time > previousTime, time - previousTime < 0.25 else {
            rawPoint = point; filteredPoint = point; timestamp = time; filteredVelocity = .zero
            return point
        }
        let dt = max(0.000_1, time - previousTime)
        let derivativeGain = Self.gain(cutoff: 3, dt: dt)
        let velocity = CGPoint(x: (point.x - previousRaw.x) / dt, y: (point.y - previousRaw.y) / dt)
        filteredVelocity.x += (velocity.x - filteredVelocity.x) * derivativeGain
        filteredVelocity.y += (velocity.y - filteredVelocity.y) * derivativeGain
        // Speed is measured in view points so zooming does not alter the feel of the pen.
        let screenSpeed = hypot(filteredVelocity.x, filteredVelocity.y) * max(0.05, zoom)
        let cutoff = 2 + (1 - amount) * 16 + min(80, screenSpeed * amount * 0.055)
        let positionGain = Self.gain(cutoff: cutoff, dt: dt)
        let result = CGPoint(x: previousFiltered.x + (point.x - previousFiltered.x) * positionGain,
                             y: previousFiltered.y + (point.y - previousFiltered.y) * positionGain)
        rawPoint = point; filteredPoint = result; timestamp = time
        return result
    }

    private static func gain(cutoff: Double, dt: Double) -> Double {
        let interval = 1 / (2 * Double.pi * cutoff)
        return dt / (dt + interval)
    }
}
