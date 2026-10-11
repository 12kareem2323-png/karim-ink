import Foundation
import Metal
import QuartzCore

/// Local performance instrumentation. GPU time is not input-to-photon latency.
final class FrameDiagnostics: @unchecked Sendable {
    struct Sample {
        let cpuMilliseconds: Double
        let gpuMilliseconds: Double?
        let submittedAt: CFTimeInterval
    }
    struct Summary {
        let submittedFramesPerSecond: Double?
        let medianCPUMilliseconds: Double?
        let medianGPUMilliseconds: Double?
    }
    private let lock = NSLock()
    private var samples: [Sample] = []
    func record(commandBuffer: MTLCommandBuffer, cpuStartedAt start: CFTimeInterval) {
        let cpu = max(0, (CACurrentMediaTime() - start) * 1000)
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let gpu: Double? = buffer.gpuEndTime > buffer.gpuStartTime && buffer.gpuStartTime > 0 ? (buffer.gpuEndTime - buffer.gpuStartTime) * 1000 : nil
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.samples.append(.init(cpuMilliseconds: cpu, gpuMilliseconds: gpu, submittedAt: start))
            if self.samples.count > 240 { self.samples.removeFirst(self.samples.count - 240) }
        }
    }
    func snapshot() -> [Sample] { lock.lock(); defer { lock.unlock() }; return samples }
    func summary(now: CFTimeInterval = CACurrentMediaTime()) -> Summary {
        let recent = snapshot().filter { now - $0.submittedAt < 2 && now >= $0.submittedAt }
        func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted(), middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }
        let span = (recent.last?.submittedAt ?? 0) - (recent.first?.submittedAt ?? 0)
        let rate: Double? = recent.count >= 3 && span > 0.02 ? Double(recent.count - 1) / span : nil
        return Summary(submittedFramesPerSecond: rate,
                       medianCPUMilliseconds: median(recent.map(\.cpuMilliseconds)),
                       medianGPUMilliseconds: median(recent.compactMap(\.gpuMilliseconds)))
    }
}
