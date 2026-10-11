import SwiftUI
import AppKit

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The same preference object is shared by the main window and Settings.
/// Appearance affects the app's controls; drawing paper remains part of the drawing.
@MainActor
final class AppAppearance: ObservableObject {
    static let preferenceKey = "engineeringboard.appearance"
    private let defaults: UserDefaults
    @Published var mode: AppAppearanceMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.preferenceKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.preferenceKey).flatMap(AppAppearanceMode.init(rawValue:)) ?? .system
    }

    var preferredColorScheme: ColorScheme? { mode.colorScheme }

    func toggle(resolvedScheme: ColorScheme) {
        mode = resolvedScheme == .dark ? .light : .dark
    }
}

/// One-click light/dark switch; the context menu also restores automatic appearance.
struct ThemeToggle: View {
    @ObservedObject var appearance: AppAppearance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button { appearance.toggle(resolvedScheme: colorScheme) } label: {
            Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                .font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(GlassToolbarButtonStyle())
        .help(colorScheme == .dark ? "Switch to light appearance" : "Switch to dark appearance")
        .accessibilityLabel(colorScheme == .dark ? "Switch to light appearance" : "Switch to dark appearance")
        .contextMenu {
            ForEach(AppAppearanceMode.allCases) { mode in
                Button { appearance.mode = mode } label: {
                    Label(mode.title + (appearance.mode == mode ? " ✓" : ""), systemImage: mode.symbol)
                }
            }
        }
    }
}

/// Semantic chrome colors are shared by the library and drawing workspace.
enum ChromePalette {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let control = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.10)
    static func backdrop(_ scheme: ColorScheme) -> LinearGradient {
        let colors: [Color] = scheme == .dark
            ? [Color(red: 0.10, green: 0.13, blue: 0.17), Color(red: 0.12, green: 0.17, blue: 0.19)]
            : [Color(red: 0.96, green: 0.98, blue: 1), Color(red: 0.91, green: 0.96, blue: 0.95)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
