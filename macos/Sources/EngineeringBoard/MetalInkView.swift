import AppKit
import MetalKit
import simd

/// A transparent, viewport-sized Metal layer. It renders active ink on demand.
/// Saved artwork and export use the shared vector renderer.
@MainActor
final class MetalInkView: MTKView, MTKViewDelegate {
    private var pipeline: MTLRenderPipelineState?
    private var queue: MTLCommandQueue?
    private let diagnostics = FrameDiagnostics()
    private var vertices: [InkVertex] = []
    private var meshElement: DrawingElement?
    private var meshZoom: Double = 0
    private var meshCamera = CGPoint.zero
    private var screenPoints: [SIMD2<Float>] = []
    private var halfWidths: [Float] = []
    private var opacities: [Float] = []
    private var distances: [Float] = []
    private var normals: [SIMD2<Float>] = []
    private(set) var geometryPointsUpdated = 0
    private var inkColor = SIMD4<Float>(0, 0, 0, 1)
    private var brushID: UInt32 = 0
    private var textureScale: Float = 1
    private var pendingPreview: Preview?
    private var geometryDirty = false
    private let inFlight = DispatchSemaphore(value: 2)
    private var vertexBuffers: [MTLBuffer?] = [nil, nil]
    private var bufferIndex = 0
    private var screenObserver: NSObjectProtocol?
    private var idleTimer: Timer?
    private var lastInkSample: CFTimeInterval = 0
    private(set) var targetFramesPerSecond = 120
    private(set) var available = false
    private(set) var failureReason: String?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    struct RenderingStatus {
        let targetFramesPerSecond: Int
        let displayMaximumFramesPerSecond: Int
        let isDrawing: Bool
        let submittedFramesPerSecond: Double?
        let medianCPUMilliseconds: Double?
        let medianGPUMilliseconds: Double?
    }
    var renderingStatus: RenderingStatus {
        let summary = diagnostics.summary()
        return RenderingStatus(targetFramesPerSecond: targetFramesPerSecond,
                               displayMaximumFramesPerSecond: window?.screen?.maximumFramesPerSecond ?? 60,
                               isDrawing: pendingPreview != nil,
                               submittedFramesPerSecond: summary.submittedFramesPerSecond,
                               medianCPUMilliseconds: summary.medianCPUMilliseconds,
                               medianGPUMilliseconds: summary.medianGPUMilliseconds)
    }

    private struct Preview {
        let element: DrawingElement
        let settings: BrushSettings
        let zoom: Double
        let camera: CGPoint
    }

    private struct InkVertex {
        var position: SIMD2<Float>
        var texture: SIMD2<Float>
        var pressure: Float
        var tilt: Float
        var velocity: Float
        var pad: Float = 1
    }
    private struct Uniforms {
        var color: SIMD4<Float>
        var viewport: SIMD2<Float>
        var brush: UInt32
        var textureScale: Float
    }

    init() {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        wantsLayer = true
        layer?.isOpaque = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true
        enableSetNeedsDisplay = true
        isPaused = true
        preferredFramesPerSecond = 120
        autoResizeDrawable = true
        delegate = self
        configurePipeline()
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.maximumDrawableCount = 2
            metalLayer.presentsWithTransaction = false
            metalLayer.allowsNextDrawableTimeout = true
        }
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        idleTimer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
        if let window {
            screenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateDisplayRate() }
            }
        }
        updateDisplayRate()
        if window == nil { isPaused = true }
    }

    private func updateDisplayRate() {
        let maximum = window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60
        targetFramesPerSecond = Self.targetRate(displayMaximum: maximum)
        preferredFramesPerSecond = targetFramesPerSecond
    }

    static func targetRate(displayMaximum: Int) -> Int { min(120, displayMaximum > 0 ? displayMaximum : 60) }

    private func configurePipeline() {
        guard let device else { failureReason = "Metal device unavailable"; return }
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "inkVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "inkFragment")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            queue = device.makeCommandQueue()
            available = queue != nil
        } catch { failureReason = error.localizedDescription }
    }

    private func scheduleIdlePause() {
        lastInkSample = CACurrentMediaTime()
        guard idleTimer == nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                guard CACurrentMediaTime() - self.lastInkSample >= 0.05 else { return }
                self.isPaused = true; self.enableSetNeedsDisplay = true
                self.idleTimer?.invalidate(); self.idleTimer = nil
                if self.geometryDirty { self.setNeedsDisplay(self.bounds) }
            }
        }
    }

    func showInk(_ element: DrawingElement?, zoom: Double, camera: CGPoint, board: Board) {
        guard available else { return }
        if let element, element.kind == .stroke, !element.points.isEmpty {
            scheduleIdlePause()
            let settings = element.effectiveBrushSettings
            brushID = UInt32(PenKind.allCases.firstIndex(of: element.pen) ?? 0)
            textureScale = Float(max(0.1, settings.textureScale))
            let color = BoardRenderer.visibleColor(element.color, board: board).usingColorSpace(.deviceRGB) ?? .black
            inkColor = SIMD4(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), Float(color.alphaComponent))
            // Keep all captured points. Multiple input events may arrive between two display frames;
            // only their latest complete geometry needs to be uploaded to the GPU.
            pendingPreview = Preview(element: element, settings: settings, zoom: zoom, camera: camera)
            geometryDirty = true
            enableSetNeedsDisplay = false
            isPaused = window == nil
        } else {
            guard pendingPreview != nil || !vertices.isEmpty else { return }
            scheduleIdlePause()
            pendingPreview = nil; geometryDirty = true
            // Present one transparent frame to remove the live layer, then stop the display clock.
            enableSetNeedsDisplay = window == nil
            isPaused = window == nil
            if window == nil { setNeedsDisplay(bounds) }
        }
    }

    private func buildGeometry(_ element: DrawingElement, settings: BrushSettings, zoom: Double, camera: CGPoint) {
        let points = element.points
        var common = 0
        if let old = meshElement, old.id == element.id, old.pen == element.pen,
           old.width == element.width, old.effectiveBrushSettings == settings,
           meshZoom == zoom, meshCamera == camera {
            let count = min(old.points.count, points.count)
            while common < count && old.points[common] == points[common] { common += 1 }
        }
        let from = max(0, common - 1)
        let firstSegment = max(1, from)
        let retainedVertices = min(vertices.count, (firstSegment - 1) * 6)
        vertices.removeSubrange(retainedVertices..<vertices.count)
        func resize<T>(_ array: inout [T], default value: T) {
            if array.count > points.count { array.removeLast(array.count - points.count) }
            if array.count < points.count { array.append(contentsOf: repeatElement(value, count: points.count - array.count)) }
        }
        resize(&screenPoints, default: .zero); resize(&halfWidths, default: 0)
        resize(&opacities, default: 0); resize(&distances, default: 0)
        resize(&normals, default: SIMD2<Float>(0, 1))
        func screen(_ p: InkPoint) -> SIMD2<Float> { SIMD2(Float((p.x - camera.x) * zoom), Float((p.y - camera.y) * zoom)) }
        func width(_ index: Int) -> Float {
            let previous = points[max(0, index - 1)], next = points[min(points.count - 1, index + 1)]
            let tangent = CGPoint(x: next.x - previous.x, y: next.y - previous.y)
            return Float(max(0.2, BrushMetrics.width(element: element, point: points[index], tangent: tangent) * zoom))
        }
        func opacity(_ point: InkPoint) -> Float {
            let grade = element.pen == .pencil ? settings.pencilGrade.darkness : 1
            return Float(BrushMetrics.opacity(element: element, point: point) * grade)
        }
        // Brush response and world-to-view conversion are identical for every triangle
        // sharing a point. Calculate them once rather than four times per segment.
        for index in from..<points.count {
            screenPoints[index] = screen(points[index]); halfWidths[index] = width(index) / 2
            opacities[index] = opacity(points[index])
        }
        geometryPointsUpdated += points.count - from
        for index in from..<points.count {
            let previous = screenPoints[max(0, index - 1)], next = screenPoints[min(points.count - 1, index + 1)]
            let tangent = next - previous, magnitude = simd_length(tangent)
            normals[index] = magnitude > 0.001 ? SIMD2(-tangent.y, tangent.x) / magnitude : SIMD2(0, 1)
            if index == 0 { distances[index] = 0 }
            if index > 0 { distances[index] = distances[index - 1] + simd_length(screenPoints[index] - screenPoints[index - 1]) }
        }
        func vertex(_ index: Int, side: Float) -> InkVertex {
            let point = points[index], half = halfWidths[index]
            return InkVertex(position: screenPoints[index] + normals[index] * half * side, texture: SIMD2(distances[index] / max(1, Float(settings.maxWidth * zoom)), side), pressure: Float(point.pressure), tilt: Float(min(1, hypot(point.tiltX, point.tiltY))), velocity: Float(min(1, (point.velocity ?? 0) / 1200)), pad: opacities[index])
        }
        if points.count > 1 {
            vertices.reserveCapacity(points.count * 6 + 36)
            for index in firstSegment..<points.count {
                let a = vertex(index - 1, side: -1), b = vertex(index - 1, side: 1)
                let c = vertex(index, side: -1), d = vertex(index, side: 1)
                vertices.append(a); vertices.append(b); vertices.append(c)
                vertices.append(c); vertices.append(b); vertices.append(d)
            }
        }
        // Half-disc caps stop without a second translucent layer across the strip.
        for (index, direction) in [(0, Float(-1)), (points.count - 1, Float(1))] {
            let p = points[index], center = screenPoints[index], normal = normals[index], tangent = SIMD2(normal.y, -normal.x) * direction
            let radius = halfWidths[index]
            func capVertex(_ angle: Float) -> InkVertex {
                let offset = normal * cos(angle) + tangent * sin(angle)
                return InkVertex(position: center + offset * radius, texture: SIMD2(distances[index], cos(angle)), pressure: Float(p.pressure), tilt: Float(min(1, hypot(p.tiltX, p.tiltY))), velocity: Float(min(1, (p.velocity ?? 0) / 1200)), pad: opacities[index])
            }
            let c = InkVertex(position: center, texture: SIMD2(distances[index], 0), pressure: Float(p.pressure), tilt: Float(min(1, hypot(p.tiltX, p.tiltY))), velocity: Float(min(1, (p.velocity ?? 0) / 1200)), pad: opacities[index])
            for section in 0..<10 {
                vertices.append(c); vertices.append(capVertex(Float(section) * .pi / 10)); vertices.append(capVertex(Float(section + 1) * .pi / 10))
            }
        }
        meshElement = element; meshZoom = zoom; meshCamera = camera
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard pendingPreview != nil else { return }
        geometryDirty = true
    }
    func draw(in view: MTKView) {
        guard geometryDirty else { return }
        // Never wait on the main thread for an older GPU frame. The newest ink remains pending.
        guard inFlight.wait(timeout: .now()) == .success else { return }
        var committed = false
        defer { if !committed { inFlight.signal() } }
        let cpuStarted = CACurrentMediaTime()
        guard let descriptor = currentRenderPassDescriptor, let drawable = currentDrawable, let queue, let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        if let preview = pendingPreview {
            buildGeometry(preview.element, settings: preview.settings, zoom: preview.zoom, camera: preview.camera)
        } else {
            vertices.removeAll(keepingCapacity: false); meshElement = nil
            screenPoints.removeAll(); halfWidths.removeAll(); opacities.removeAll(); distances.removeAll(); normals.removeAll()
            for index in vertexBuffers.indices where (vertexBuffers[index]?.length ?? 0) > 8 * 1024 * 1024 { vertexBuffers[index] = nil }
        }
        if !vertices.isEmpty, let pipeline, let device {
            let needed = vertices.count * MemoryLayout<InkVertex>.stride
            if (vertexBuffers[bufferIndex]?.length ?? 0) < needed {
                vertexBuffers[bufferIndex] = device.makeBuffer(length: max(16_384, needed + needed / 2), options: .storageModeShared)
            }
            guard let vertexBuffer = vertexBuffers[bufferIndex] else { encoder.endEncoding(); return }
            vertices.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { vertexBuffer.contents().copyMemory(from: base, byteCount: needed) }
            }
            var uniforms = Uniforms(color: inkColor, viewport: SIMD2(Float(max(1, bounds.width)), Float(max(1, bounds.height))), brush: brushID, textureScale: textureScale)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }
        encoder.endEncoding(); buffer.present(drawable)
        diagnostics.record(commandBuffer: buffer, cpuStartedAt: cpuStarted)
        let semaphore = inFlight
        buffer.addCompletedHandler { _ in semaphore.signal() }
        geometryDirty = false
        bufferIndex = (bufferIndex + 1) % vertexBuffers.count
        committed = true
        buffer.commit()
        // Keep the display link stable during incoming samples. The coalesced
        // idle timer pauses it after 50 ms without new geometry.
        if pendingPreview == nil { isPaused = true; enableSetNeedsDisplay = true }
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float2 position; float2 texture; float pressure; float tilt; float velocity; float pad; };
    struct Uniforms { float4 color; float2 viewport; uint brush; float textureScale; };
    struct Output { float4 position [[position]]; float2 texture; float pressure; float tilt; float velocity; float opacity; };
    float noise(float2 p) { return fract(sin(dot(p,float2(127.1,311.7))) * 43758.5453); }
    vertex Output inkVertex(uint index [[vertex_id]], device const Vertex *vertices [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
        Vertex v=vertices[index]; Output o;
        o.position=float4(v.position.x/u.viewport.x*2-1, 1-v.position.y/u.viewport.y*2,0,1);
        o.texture=v.texture; o.pressure=v.pressure; o.tilt=v.tilt; o.velocity=v.velocity; o.opacity=v.pad; return o;
    }
    fragment float4 inkFragment(Output in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
        float edge=abs(in.texture.y);
        float antialias=max(fwidth(in.texture.y)*1.1,0.015);
        float alpha=1-smoothstep(1-antialias,1,edge);
        float grain=noise(floor(in.position.xy*u.textureScale));
        if (u.brush==1) { alpha*=0.84+0.16*(1-in.velocity); } // Fountain
        if (u.brush==2) { alpha*=mix(0.22,0.93,grain); } // Graphite
        if (u.brush==3) { alpha*=smoothstep(0.18,0.78,grain)*0.82; } // Chalk
        if (u.brush==4) { alpha*=0.94+0.06*grain; } // Marker
        if (u.brush==5) { alpha*=0.92; } // Calligraphy
        if (u.brush==6) { alpha*=pow(max(0.0,1-edge),1.7)*0.54; } // Airbrush
        if (u.brush==7) { alpha*=0.82+0.18*cos(in.texture.y*3.14159); } // Liquid
        if (u.brush==8) { alpha*=1; } // Highlighter
        if (u.brush==9) { alpha*=0.82+0.18*grain; } // Dry erase
        return float4(u.color.rgb,u.color.a*in.opacity*alpha);
    }
    """
}
