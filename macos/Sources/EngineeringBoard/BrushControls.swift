import SwiftUI
import AppKit

struct BrushControls: View {
    @ObservedObject var session: DrawingSession
    @State<String> private var hex = ""
    @State<String> private var colorError = ""
    @State private var showRGB = false
    @State private var showAdvanced = false
    @State private var showPenGallery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: session.pen.symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(.teal)
                        .frame(width: 34, height: 34).background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.pen.name).font(.system(size: 13, weight: .semibold))
                        Text(session.pen.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                BrushStrokePreview(pen: session.pen, color: session.color, settings: session.brushSettings)
                    .frame(height: 40).background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 9))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel("Preview of your current brush")
            }
            .inspectorCard()
            VStack(spacing: 12) {
                settingSlider(session.brushSettings.pressureEnabled ? "Maximum width" : "Stroke width", keyPath: \.maxWidth, range: 0.5...60, suffix: "pt")
                settingSlider("Opacity", keyPath: \.opacity, range: 0.05...1, suffix: "", percentage: true)
            }.inspectorCard()
            if session.pen != .technical {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("Use pen pressure", isOn: Binding(get: { session.brushSettings.pressureEnabled }, set: { value in
                        var settings = session.brushSettings; settings.pressureEnabled = value; session.brushSettings = settings
                    })).font(.system(size: 11, weight: .medium))
                    HStack(spacing: 5) {
                        ForEach(Array(zip(["Soft", "Natural", "Firm"], [0.65, 1.0, 1.8])), id: \.0) { name, gamma in
                            Button {
                                var settings = session.brushSettings; settings.pressureGamma = gamma; settings.pressureEnabled = true
                                session.brushSettings = settings
                            } label: { Text(name).frame(maxWidth: .infinity) }
                                .buttonStyle(GlassCommandButtonStyle(isSelected: session.brushSettings.pressureEnabled && abs(session.brushSettings.pressureGamma - gamma) < 0.001))
                                .help("\(name) pressure curve")
                        }
                    }
                    Text("Soft responds sooner. Firm needs more pressure.").font(.system(size: 10)).foregroundStyle(.secondary)
                }.inspectorCard()
            }
            DisclosureGroup("Choose a pen · 10 styles", isExpanded: $showPenGallery) {
                if showPenGallery { penGallery.padding(.top, 9) }
            }.font(.system(size: 11, weight: .medium))
            Divider().padding(.vertical, 2)
            ColorPicker("Ink colour", selection: colorBinding, supportsOpacity: true)
                .font(.system(size: 12, weight: .medium))
            HStack(spacing: 8) {
                ForEach(Array(InkColor.palette.enumerated()), id: \.offset) { index, color in
                    Button { session.color = color } label: {
                        Circle().fill(color.swift).frame(width: 23, height: 23)
                            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
                            .padding(2)
                            .overlay(Circle().strokeBorder(Color.accentColor.opacity(session.color == color ? 0.85 : 0), lineWidth: 1.5))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(["Graphite", "Blue", "Teal", "Red", "Amber", "Violet"][index] + " ink")
                        .accessibilityValue(session.color == color ? "Selected" : "")
                }
            }
            HStack(spacing: 6) {
                TextField("#RRGGBB", text: $hex).textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced)).onSubmit { applyHex() }
                    .accessibilityLabel("Ink colour hex code")
                    .help("Six colour digits, or eight including transparency")
                Button("Set") { applyHex() }.controlSize(.small)
                    .accessibilityLabel("Apply ink colour hex code")
            }
            if !colorError.isEmpty { Text(colorError).font(.caption2).foregroundStyle(.red) }
            DisclosureGroup("RGB channels", isExpanded: $showRGB) {
                HStack(spacing: 8) {
                    rgbField("R", keyPath: \.r)
                    rgbField("G", keyPath: \.g)
                    rgbField("B", keyPath: \.b)
                }
                .padding(.top, 7)
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            if session.pen == .pencil {
                Picker("Pencil grade", selection: Binding(get: { session.brushSettings.pencilGrade }, set: { grade in
                    var settings = session.brushSettings; settings.pencilGrade = grade; session.brushSettings = settings
                })) {
                    ForEach(PencilGrade.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.font(.caption)
                Text("Tilt widens graphite shading when your tablet supplies tilt.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            DisclosureGroup("Advanced response", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    settingSlider("Minimum width", keyPath: \.minWidth, range: 0.2...max(0.2, session.brushSettings.maxWidth), suffix: "pt")
                        .disabled(session.pen == .technical)
                    if session.pen == .technical {
                        Text("Fineliner width stays constant at every pressure.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    settingSlider("Pressure curve", keyPath: \.pressureGamma, range: 0.2...3, suffix: "γ")
                        .disabled(!session.brushSettings.pressureEnabled || session.pen == .technical)
                    BrushPressureCurve(settings: session.brushSettings)
                        .frame(height: 64).opacity(session.brushSettings.pressureEnabled ? 1 : 0.5)
                    HStack { Text("Light touch"); Spacer(); Text("Full pressure") }
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    if session.pen != .technical {
                        settingSlider("Light pressure opacity", keyPath: \.minOpacity, range: 0...max(0.01, session.brushSettings.maxOpacity), suffix: "", percentage: true)
                        settingSlider("Full pressure opacity", keyPath: \.maxOpacity, range: max(0.01, session.brushSettings.minOpacity)...1, suffix: "", percentage: true)
                    }
                    if [.pencil, .chalk, .dryErase, .marker, .airbrush].contains(session.pen) {
                        settingSlider("Texture scale", keyPath: \.textureScale, range: 0.25...3, suffix: "×")
                    }
                    Button("Reset this brush") { session.brushSettings = .defaults(for: session.pen) }
                        .font(.caption).buttonStyle(.borderless)
                    Text("Colour and response are saved for each brush on this Mac.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }.font(.system(size: 12, weight: .medium))
        }
        .onAppear { refreshHex() }
        .onChange(of: session.color) { _, _ in refreshHex() }
    }

    private var penGallery: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(PenKind.allCases) { style in
                    Button {
                        session.pen = style
                        session.tool = .ink
                        session.status = style.name + " selected"
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Image(systemName: style.symbol).font(.system(size: 10, weight: .medium))
                                Text(shortName(style)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 0)
                                if session.pen == style {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                                }
                            }
                            BrushStrokePreview(pen: style, color: session.color,
                                               settings: session.pen == style ? session.brushSettings : .defaults(for: style))
                                .frame(height: 24)
                                .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 5))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .padding(8).frame(maxWidth: .infinity, minHeight: 55)
                        .foregroundStyle(session.pen == style ? Color.accentColor : Color.primary)
                        .background(session.pen == style ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                            session.pen == style ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: 0.8))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).help(style.detail)
                        .accessibilityLabel(style.name)
                        .accessibilityValue(session.pen == style ? "Selected" : "")
                        .accessibilityHint("Select this brush for drawing")
                }
            }
    }

    private func shortName(_ pen: PenKind) -> String {
        switch pen {
        case .technical: return "Fineliner"
        case .fountain: return "Fountain"
        case .pencil: return "Graphite"
        case .chalk: return "Chalk"
        case .marker: return "Marker"
        case .calligraphy: return "Calligraphy"
        case .airbrush: return "Airbrush"
        case .liquid: return "Liquid ink"
        case .highlighter: return "Highlighter"
        case .dryErase: return "Dry erase"
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { session.color.swift }, set: { newColor in
            guard let color = NSColor(newColor).usingColorSpace(.sRGB) else { return }
            session.color = InkColor(r: color.redComponent, g: color.greenComponent, b: color.blueComponent, a: color.alphaComponent)
        })
    }

    private func rgbField(_ label: String, keyPath: WritableKeyPath<InkColor, Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(label, value: Binding(get: { Int((session.color[keyPath: keyPath] * 255).rounded()) }, set: { new in
                var color = session.color; color[keyPath: keyPath] = Double(max(0, min(255, new))) / 255; session.color = color
            }), format: .number).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                .accessibilityLabel(label + " colour channel value")
            Slider(value: Binding(get: { session.color[keyPath: keyPath] }, set: { value in
                var color = session.color; color[keyPath: keyPath] = value; session.color = color
            }), in: 0...1).controlSize(.mini).accessibilityLabel(label + " colour channel")
        }
    }

    private func settingSlider(_ title: String, keyPath: WritableKeyPath<BrushSettings, Double>, range: ClosedRange<Double>, suffix: String, percentage: Bool = false) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(percentage ? "\(Int(session.brushSettings[keyPath: keyPath] * 100))%" : String(format: "%.1f %@", session.brushSettings[keyPath: keyPath], suffix))
                    .monospacedDigit().foregroundStyle(.secondary)
            }.font(.caption)
            Slider(value: Binding(get: { session.brushSettings[keyPath: keyPath] }, set: { value in
                var settings = session.brushSettings
                settings[keyPath: keyPath] = value
                if settings.minWidth > settings.maxWidth { settings.minWidth = settings.maxWidth }
                if settings.minOpacity > settings.maxOpacity { settings.minOpacity = settings.maxOpacity }
                if session.pen == .technical { settings.minWidth = settings.maxWidth; settings.pressureEnabled = false }
                session.brushSettings = settings
            }), in: range).accessibilityLabel(title)
        }
    }

    private func refreshHex() {
        let color = session.color
        hex = String(format: "#%02X%02X%02X", Int((color.r * 255).rounded()), Int((color.g * 255).rounded()), Int((color.b * 255).rounded()))
        if color.a < 1 { hex += String(format: "%02X", Int((color.a * 255).rounded())) }
        colorError = ""
    }

    private func applyHex() {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard (value.count == 6 || value.count == 8), let number = UInt64(value, radix: 16) else {
            colorError = "Use six hex digits, such as #2463EB, or eight with alpha."; return
        }
        let rgb = value.count == 8 ? number >> 8 : number
        let alpha = value.count == 8 ? Double(number & 0xFF) / 255 : session.color.a
        session.color = InkColor(r: Double((rgb >> 16) & 0xFF) / 255, g: Double((rgb >> 8) & 0xFF) / 255, b: Double(rgb & 0xFF) / 255, a: alpha)
        refreshHex()
    }
}

struct BrushPressureCurve: View {
    var settings: BrushSettings
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05))
                Path { path in
                    path.move(to: CGPoint(x: 8, y: size.height - 8))
                    path.addLine(to: CGPoint(x: size.width - 8, y: 8))
                }.stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Path { path in
                    for i in 0...60 {
                        let p = Double(i) / 60
                        let response = pow(p, settings.pressureGamma)
                        let point = CGPoint(x: 8 + p * (size.width - 16), y: size.height - 8 - response * (size.height - 16))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(Color.accentColor, lineWidth: 2)
            }
        }.accessibilityLabel("Pressure response curve")
    }
}

/// Uses the same renderer as saved ink, rather than a decorative brush icon.
struct BrushStrokePreview: NSViewRepresentable {
    var pen: PenKind
    var color: InkColor
    var settings: BrushSettings
    func makeNSView(context: Context) -> BrushSampleView { BrushSampleView() }
    func updateNSView(_ view: BrushSampleView, context: Context) {
        if view.pen != pen || view.color != color || view.settings != settings {
            view.pen = pen; view.color = color; view.settings = settings; view.needsDisplay = true
        }
    }
}

final class BrushSampleView: NSView {
    var pen: PenKind = .technical
    var color = InkColor.graphite
    var settings = BrushSettings.defaults(for: .technical)
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 8 else { return }
        var brush = settings
        let fit = min(1, 12 / max(brush.maxWidth, 0.2))
        brush.maxWidth *= fit; brush.minWidth *= fit
        let points = (0...48).map { i -> InkPoint in
            let t = Double(i) / 48
            return InkPoint(x: 4 + t * (bounds.width - 8), y: bounds.midY + sin(t * .pi * 2) * 3,
                            pressure: 0.12 + sin(t * .pi) * 0.88, tiltX: pen == .pencil ? 0.35 : 0)
        }
        let element = DrawingElement(kind: .stroke, points: points, color: color, width: brush.maxWidth, pen: pen, brushSettings: brush)
        BoardRenderer.draw(element: element, on: Board(background: .plain, width: bounds.width, height: bounds.height), context: context)
    }
}
