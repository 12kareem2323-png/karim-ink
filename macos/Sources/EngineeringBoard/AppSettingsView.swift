import SwiftUI
import AppKit

/// This check writes and removes only its own unique, hidden probe file.
/// It does not read, rewrite or migrate any saved drawing.
enum LibraryAccessCheck {
    static func verify(directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.missingLibrary
        }
        let probe = directory.appendingPathComponent(".access-check-\(UUID().uuidString)")
        var created = false
        defer { if created { try? FileManager.default.removeItem(at: probe) } }
        // Exclusive creation cannot overwrite an existing file, even if its name collides.
        try Data("SketchGlide library access check".utf8).write(to: probe, options: [.withoutOverwriting])
        created = true
        guard try Data(contentsOf: probe) == Data("SketchGlide library access check".utf8) else {
            throw Failure.readBack
        }
        try FileManager.default.removeItem(at: probe)
        created = false
    }

    enum Failure: LocalizedError {
        case missingLibrary, readBack
        var errorDescription: String? {
            switch self {
            case .missingLibrary: return "The drawing library folder is missing. Reopen the app or choose a file export to keep your drawing."
            case .readBack: return "The library check could not read back its temporary file."
            }
        }
    }
}

struct AppSettingsView: View {
    @ObservedObject var appearance: AppAppearance
    let libraryDirectory: URL

    var body: some View {
        TabView {
            AppearanceSettings(appearance: appearance)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            AISettingsView().frame(maxWidth: .infinity)
                .tabItem { Label("Assistant", systemImage: "sparkles") }
            AccessSettingsView(libraryDirectory: libraryDirectory)
                .tabItem { Label("Access", systemImage: "lock.shield") }
            ReleaseSupportView().tabItem { Label("Feedback & support", systemImage: "bubble.left.and.bubble.right") }
        }
        .padding(16)
        .frame(width: 680, height: 590)
        .preferredColorScheme(appearance.preferredColorScheme)
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var appearance: AppAppearance
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Image(systemName: "pencil.and.ruler.fill").font(.system(size: 28, weight: .light)).foregroundStyle(.teal)
                        .frame(width: 56, height: 56).background(Color.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Make this desk yours").font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("SketchGlide · 0.2 Test").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 13) {
                    Text("Appearance").font(.headline)
                    HStack(spacing: 13) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Button { appearance.mode = mode } label: { themeCard(mode) }.buttonStyle(.plain)
                                .accessibilityLabel(mode.title + " appearance")
                                .accessibilityValue(appearance.mode == mode ? "Selected" : "Not selected")
                        }
                    }
                    Text("System follows your Mac. Switch between light and dark at any time using the sun or moon button in the drawing window.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Your paper has its own style", systemImage: "doc").font(.headline)
                    Text("The theme changes your toolbars, library and panels. Your drawing keeps the paper and ink you chose, including when you export it. Use the Paper panel to change a drawing's background.")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(19).frame(maxWidth: .infinity, alignment: .leading).librarySurface(radius: 14)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "accessibility").foregroundStyle(.teal)
                    Text("Native controls follow your Mac's Reduce Transparency and Reduce Motion settings.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(25)
        }
    }
    private func themeCard(_ mode: AppAppearanceMode) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(mode == .dark ? Color(red: 0.12, green: 0.15, blue: 0.19) : Color(red: 0.96, green: 0.96, blue: 0.95))
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(.teal.opacity(0.8)).frame(width: 20, height: 4)
                        ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 2).fill(mode == .dark ? .white.opacity(0.18) : .black.opacity(0.10)).frame(width: 26, height: 3) }
                        Spacer()
                    }.padding(8).frame(width: 43).background(mode == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.025))
                    VStack(spacing: 8) {
                        HStack(spacing: 5) { ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 3).fill(Color.teal.opacity(0.13)).frame(height: 15) } }
                        RoundedRectangle(cornerRadius: 3).strokeBorder(Color.teal.opacity(0.35), lineWidth: 1).overlay(Image(systemName: "pencil.tip").font(.system(size: 16)).foregroundStyle(.teal))
                    }.padding(9)
                }.clipShape(RoundedRectangle(cornerRadius: 8))
                if mode == .system {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.16)).frame(width: 55).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }.frame(height: 87).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            HStack(spacing: 6) {
                Image(systemName: mode.symbol).font(.system(size: 11))
                Text(mode.title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 2)
                Image(systemName: appearance.mode == mode ? "checkmark.circle.fill" : "circle").foregroundStyle(appearance.mode == mode ? Color.teal : Color.secondary.opacity(0.3))
            }
        }.padding(12).frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(appearance.mode == mode ? Color.teal.opacity(0.65) : Color.primary.opacity(0.07), lineWidth: appearance.mode == mode ? 1.5 : 0.5))
    }
}

struct AccessSettingsView: View {
    let libraryDirectory: URL
    @State private var libraryStatus = "Check the library to verify local saving."
    @State private var libraryFailed = false
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("App access").font(.title2.weight(.semibold))
                Text("Core drawing works offline. Set up the optional services you use below.")
                    .foregroundStyle(.secondary)
                accessCard("Drawing library", symbol: "externaldrive", detail: "Drawings save in your user Library. Imports and exports use the Mac's file chooser so you can select the files and folders you need.") {
                    Text(libraryStatus).font(.caption).foregroundStyle(libraryFailed ? Color.red : Color.secondary)
                    HStack {
                        Button("Check local saving") { checkLibrary() }
                        Button("Show drawings in Finder") { NSWorkspace.shared.activateFileViewerSelecting([libraryDirectory]) }
                    }
                }
                accessCard("Chat and API key", symbol: "sparkles", detail: "Cloud answers need internet and an OpenAI API key saved in macOS Keychain. Configure the connection in the Assistant tab. Your key is never included in drawing files or exports.") {
                    Text("The app sends a board image only when you choose Attach current board and send a message.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                accessCard("Drawing tablet", symbol: "hand.draw", detail: "Pressure, tilt, hover and pen buttons use standard macOS tablet events from your installed driver. Wacom, Huion, XP-Pen, Xencelabs and other brands depend on the features their driver supplies. Use the Tablet panel to test your pen.") {
                    Button("Open Xencelabs Settings") { openDriverSettings() }
                    Text("Allow the permissions requested by the official driver in its setup. Normal drawing inside this app does not use global keyboard monitoring.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                accessCard("Quick Keys remote", symbol: "keyboard", detail: "Driver shortcuts work with the normal tablet setup. Optional direct Quick Keys control starts only when you connect it in the Tablet panel; it may be blocked by the driver or macOS input policy.") {
                    Button("Open Input Monitoring settings") { openInputSettings() }
                    Text("Use this only if macOS requests access for optional direct control. Physical hardware operation still needs a test on your remote.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Full Disk Access, camera, microphone and screen recording are not required for normal drawing, file export or typed chat.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .alert("Couldn't open settings", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func accessCard<Actions: View>(_ title: String, symbol: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
            actions()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).glassPanel(radius: 14)
    }

    private func checkLibrary() {
        do {
            try LibraryAccessCheck.verify(directory: libraryDirectory)
            libraryStatus = "Local saving checked: writing and reading succeeded."
            libraryFailed = false
        } catch {
            libraryStatus = error.localizedDescription
            libraryFailed = true
        }
    }

    private func openDriverSettings() {
        let candidates = ["/Applications/Xencelabs.app", "/Applications/Xencelabs/Xencelabs.app",
                          "/Applications/Xencelabs/PenTablet.app", "/Applications/PenTablet.app"]
        if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            if !NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
                actionError = "Open Xencelabs Settings from Applications to check your driver."
            }
        } else {
            actionError = "Xencelabs Settings was not found in Applications. Install the official driver, then open its settings and select SketchGlide as an application profile."
        }
    }

    private func openInputSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"), NSWorkspace.shared.open(url) else {
            actionError = "Open System Settings → Privacy & Security → Input Monitoring."
            return
        }
    }
}
