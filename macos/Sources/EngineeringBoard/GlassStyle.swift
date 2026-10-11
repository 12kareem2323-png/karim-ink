import SwiftUI
import AppKit

/// Decorative backdrops never intercept pen, mouse or trackpad events.
final class GlassBackdropView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Native frosted material, with an opaque accessibility fallback.
struct GlassSurface: View {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if reduceTransparency {
                ChromePalette.surface
            } else {
                NativeGlassBackdrop(material: material, blendingMode: blendingMode, colorScheme: colorScheme)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct NativeGlassBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let colorScheme: ColorScheme
    func makeNSView(context: Context) -> GlassBackdropView {
        let view = GlassBackdropView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        return view
    }
    func updateNSView(_ view: GlassBackdropView, context: Context) {
        if view.material != material { view.material = material }
        if view.blendingMode != blendingMode { view.blendingMode = blendingMode }
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if view.appearance?.name != appearanceName { view.appearance = NSAppearance(named: appearanceName) }
    }
}

struct GlassPanel: ViewModifier {
    var radius: CGFloat
    var interactive = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        // Resolve the default foreground before glassEffect's material styling.
        // Semantic .primary can otherwise resolve to dark text inside a dark glass panel.
        let styledContent = content.foregroundStyle(colorScheme == .dark
            ? Color(red: 0.94, green: 0.96, blue: 0.98)
            : Color(red: 0.14, green: 0.20, blue: 0.28))
        Group {
            if reduceTransparency {
                styledContent.background(ChromePalette.surface, in: RoundedRectangle(cornerRadius: radius))
            } else if #available(macOS 26.0, *) {
                // Keep the substrate clear so native glass can sample the canvas.
                styledContent.glassEffect(.regular.interactive(interactive && !reduceMotion), in: RoundedRectangle(cornerRadius: radius))
            } else {
                styledContent.background(GlassSurface(blendingMode: .withinWindow))
                    .clipShape(RoundedRectangle(cornerRadius: radius))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(
            LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.36 : 0.88), .white.opacity(colorScheme == .dark ? 0.08 : 0.22), Color.primary.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5).allowsHitTesting(false))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.09), radius: 14, x: 0, y: 6)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 2, x: 0, y: 1)
    }
}

/// Large chrome uses one AppKit backdrop; nested cards use inexpensive tints.
private struct GlassChrome: ViewModifier {
    var material: NSVisualEffectView.Material
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            GlassSurface(material: material)
                .overlay {
                    if !reduceTransparency {
                        LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.04 : 0.16), .white.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

private struct InspectorCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.padding(13)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(ChromePalette.control.opacity(reduceTransparency ? 1 : (colorScheme == .dark ? 0.48 : 0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.035 : 0.16), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.17 : 0.7), Color.primary.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5).allowsHitTesting(false))
    }
}

extension View {
    func glassPanel(radius: CGFloat = 18, interactive: Bool = false) -> some View { modifier(GlassPanel(radius: radius, interactive: interactive)) }
    func glassChrome(material: NSVisualEffectView.Material = .sidebar) -> some View { modifier(GlassChrome(material: material)) }

    /// Calm inspector cards use an inexpensive solid tint; reserve glass for floating chrome.
    func inspectorCard() -> some View {
        modifier(InspectorCard())
    }
}

/// A variable-width sibling of the square tool button, for compact Mac command bars.
struct GlassCommandButtonStyle: ButtonStyle {
    var isSelected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).frame(height: 30)
            .modifier(GlassButtonFace(isSelected: isSelected, isPressed: configuration.isPressed, radius: 9, idleOpacity: 0.025))
    }
}

enum DrawingDimensions {
    static func endpoint(start: InkPoint, end: InkPoint, lengthMM: Double, pointsPerMM: Double, scaleDenominator: Double) -> InkPoint? {
        guard lengthMM.isFinite, lengthMM > 0, lengthMM <= 1_000_000,
              pointsPerMM.isFinite, pointsPerMM > 0, scaleDenominator.isFinite, scaleDenominator > 0 else { return nil }
        let distance = hypot(end.x - start.x, end.y - start.y)
        let modelLength = lengthMM * pointsPerMM / scaleDenominator
        guard distance.isFinite, distance > 0, modelLength.isFinite else { return nil }
        var result = end
        result.x = start.x + (end.x - start.x) / distance * modelLength
        result.y = start.y + (end.y - start.y) / distance * modelLength
        guard result.x.isFinite, result.y.isFinite, abs(result.x) <= 1_000_000, abs(result.y) <= 1_000_000 else { return nil }
        return result
    }
}

struct DimensionPopover: View {
    @ObservedObject var session: DrawingSession
    @State private var length = ""
    @State private var error = ""
    @FocusState private var focused: Bool
    var element: DrawingElement? { session.board.elements.first { $0.id == session.pendingDimensionID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Exact line length", systemImage: "ruler").font(.headline)
                Spacer()
                Button { session.pendingDimensionID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            HStack {
                TextField("145", text: $length).textFieldStyle(.roundedBorder).frame(width: 100).focused($focused).onSubmit { apply() }
                Text("mm").foregroundStyle(.secondary)
                Button("Set length") { apply() }.buttonStyle(.borderedProminent)
            }
            Text("Measured at drawing scale 1:\(BoardRenderer.formatted(session.board.scaleDenominator)).").font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(18).frame(width: 320).glassPanel()
        .onAppear {
            if let element, let a = element.points.first, let b = element.points.last {
                length = String(format: "%.2f", hypot(b.x - a.x, b.y - a.y) / session.board.pointsPerMM * session.board.scaleDenominator)
            }
        }
    }
    func apply() {
        let input = length.lowercased().replacingOccurrences(of: "mm", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Double(input), value.isFinite, value > 0, value <= 1_000_000, let id = session.pendingDimensionID,
              let index = session.board.elements.firstIndex(where: { $0.id == id }), let a = session.board.elements[index].points.first, let b = session.board.elements[index].points.last else { error = "Enter a positive length in mm."; return }
        guard let end = DrawingDimensions.endpoint(start: a, end: b, lengthMM: value, pointsPerMM: session.board.pointsPerMM, scaleDenominator: session.board.scaleDenominator) else { error = "The line direction or requested size is outside the supported range."; return }
        session.checkpoint()
        session.board.elements[index].points = [a, end]
        session.changed(); session.status = "Line set to \(input) mm"; session.pendingDimensionID = nil
    }
}

struct GlassToolbarButtonStyle: ButtonStyle {
    var isSelected = false
    var size: CGFloat = 34
    func makeBody(configuration: Configuration) -> some View {
        GlassToolbarButtonBody(configuration: configuration, isSelected: isSelected, size: size)
    }
}
private struct GlassToolbarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let size: CGFloat
    var body: some View {
        configuration.label
            .frame(width: size, height: size)
            .modifier(GlassButtonFace(isSelected: isSelected, isPressed: configuration.isPressed, radius: 10, idleOpacity: 0))
    }
}

/// Interaction-only feedback; there is no continuously animating glass layer.
private struct GlassButtonFace: ViewModifier {
    let isSelected: Bool
    let isPressed: Bool
    let radius: CGFloat
    let idleOpacity: Double
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    private var dark: Bool { colorScheme == .dark }
    func body(content: Content) -> some View {
        content
            .foregroundStyle(isSelected ? (dark ? Color(red: 0.37, green: 0.90, blue: 0.82) : Color(red: 0.03, green: 0.43, blue: 0.39)) : (dark ? Color(red: 0.94, green: 0.96, blue: 0.98) : Color(red: 0.14, green: 0.20, blue: 0.28)))
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(isSelected ? Color.teal.opacity(dark ? 0.25 : 0.14) : Color.primary.opacity(isEnabled && (hovering || isPressed) ? 0.08 : idleOpacity))
                    .overlay(RoundedRectangle(cornerRadius: radius).fill(LinearGradient(colors: [.white.opacity(isSelected || hovering ? (dark ? 0.07 : 0.28) : 0), .clear], startPoint: .top, endPoint: .bottom)))
            }
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(LinearGradient(colors: [.white.opacity(isSelected || hovering ? (dark ? 0.30 : 0.85) : 0), isSelected ? Color.teal.opacity(0.18) : .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5).allowsHitTesting(false))
            .opacity(isEnabled ? 1 : 0.3)
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovering = $0 }
    }
}
