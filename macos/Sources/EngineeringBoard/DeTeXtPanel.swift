import SwiftUI
import AppKit

enum DeTeXtSection: String, CaseIterable, Identifiable {
    case draw, formula, about
    var id: Self { self }
    var title: String {
        switch self {
        case .draw: return "Draw a symbol"
        case .formula: return "Formula editor"
        case .about: return "About DeTeXt"
        }
    }
}

/// A native DeTeXt maths section using the published local symbol model.
/// The separately installed DeTeXt application is launched, never embedded.
struct DeTeXtWorkbench: View {
    @ObservedObject var session: DrawingSession
    @Environment(\.dismiss) private var dismiss
    @State private var section: DeTeXtSection
    @State private var formula = "\\sigma = \\frac{F}{A}"

    init(session: DrawingSession, initialSection: DeTeXtSection = .draw) {
        self.session = session
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "function").font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.teal).frame(width: 46, height: 46)
                    .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("DeTeXt maths").font(.title2.bold())
                    Text("Symbols, LaTeX and editable engineering formulae").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("DeTeXt section", selection: $section) {
                ForEach(DeTeXtSection.allCases) { tab in Text(tab.title).tag(tab) }
            }.pickerStyle(.segmented)
            Divider()
            // Keep the temporary drawing and formula when moving between tabs.
            ZStack(alignment: .topLeading) {
                MathSymbolPanel(session: session, embedded: true) { command in
                    formula = DeTeXtFormulaActions.appending(command, to: formula)
                    section = .formula
                }
                .opacity(section == .draw ? 1 : 0)
                .disabled(section != .draw)
                .allowsHitTesting(section == .draw)
                .accessibilityHidden(section != .draw)
                DeTeXtFormulaEditor(session: session, source: $formula)
                    .opacity(section == .formula ? 1 : 0)
                    .disabled(section != .formula)
                    .allowsHitTesting(section == .formula)
                    .accessibilityHidden(section != .formula)
                DeTeXtAboutPanel()
                    .opacity(section == .about ? 1 : 0)
                    .disabled(section != .about)
                    .allowsHitTesting(section == .about)
                    .accessibilityHidden(section != .about)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                Label("Local symbol recognition", systemImage: "lock.shield").font(.caption)
                Spacer()
                Text("Review suggestions before inserting").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).frame(width: 840, height: 650)
    }
}

@MainActor
enum DeTeXtFormulaActions {
    static func appending(_ command: String, to source: String) -> String {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return command }
        return source + (source.last?.isWhitespace == true ? "" : " ") + command
    }

    @discardableResult
    static func insert(_ source: String, into session: DrawingSession) -> Bool {
        guard MathParser.validationError(for: source) == nil, session.zoom.isFinite,
              session.cameraOffset.x.isFinite, session.cameraOffset.y.isFinite else { return false }
        let zoom = max(0.05, min(16, session.zoom))
        let width = 560 / zoom, height = 160 / zoom
        let x = min(1_000_000 - width, max(-1_000_000, session.cameraOffset.x + 120 / zoom))
        let y = min(1_000_000 - height, max(-1_000_000, session.cameraOffset.y + 120 / zoom))
        session.add(DrawingElement(kind: .symbol,
                                   points: [.init(x: x, y: y), .init(x: x + width, y: y + height)],
                                   color: session.color, text: "mathlatex:" + source))
        session.status = "Inserted editable maths. Use Undo to remove it."
        return true
    }
}

private struct DeTeXtFormulaEditor: View {
    @ObservedObject var session: DrawingSession
    @Binding var source: String
    @State private var message = ""
    private var validationError: String? { MathParser.validationError(for: source) }
    private let examples: [(String, String)] = [
        ("Stress", "\\sigma = \\frac{F}{A}"),
        ("Ohm's law", "V = I R"),
        ("Kinetic energy", "E_k = \\frac{1}{2} m v^2"),
        ("Quadratic", "x = \\frac{-b \\pm \\sqrt{b^2 - 4 a c}}{2 a}")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type LaTeX or send a recognised symbol here. The preview becomes editable maths on your board.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Try a formula").font(.caption).foregroundStyle(.secondary)
                ForEach(examples, id: \.0) { example in
                    Button(example.0) { source = example.1; message = "" }.controlSize(.small)
                }
                Spacer()
                Button("Clear") { source = ""; message = "" }.controlSize(.small)
            }
            TextEditor(text: $source)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8).frame(height: 86)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
                .accessibilityLabel("Editable LaTeX formula source")
            Text("Preview").font(.caption.bold())
            MathPreview(latex: source).frame(height: 136)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)))
                .accessibilityLabel("Native maths preview")
            Group {
                if let validationError {
                    Text(validationError).foregroundStyle(.red)
                } else {
                    Text("Supports fractions, roots, powers, subscripts and common Greek letters and operators.")
                        .foregroundStyle(.secondary)
                }
            }.font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Copy LaTeX") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(source, forType: .string)
                    message = "LaTeX copied."
                }.disabled(source.isEmpty)
                Spacer()
                Button("Insert editable maths") {
                    if DeTeXtFormulaActions.insert(source, into: session) {
                        message = "Inserted on your board. Your formula stays here for further editing."
                    } else {
                        message = "Couldn't insert this formula. Check its source and the drawing view, then try again."
                    }
                }.buttonStyle(.borderedProminent).disabled(validationError != nil)
            }
            Text(message).font(.caption).foregroundStyle(.secondary)
                .frame(minHeight: 16, alignment: .leading)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: source) { _, _ in message = "" }
    }
}

private struct DeTeXtAboutPanel: View {
    @State private var launchMessage = ""
    private var installedApplication: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "Venkat.DeTeXt")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("A dedicated maths section").font(.title3.bold())
                    Text("Draw an individual symbol, review DeTeXt's suggested LaTeX commands, then copy or insert the match. Use Formula editor to assemble a complete expression.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Works locally", systemImage: "lock.shield").font(.headline)
                    Text("The public DeTeXt model recognises one symbol at a time. The drawing pad and symbol predictions stay on your Mac. Complete handwritten equations need to be assembled in the formula editor.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Model 0.95 by Venkata S Govindarajan (Venkat) · \(MathSymbolCatalog.all.count.formatted()) symbol commands · MIT licence")
                        .font(.caption).textSelection(.enabled)
                    HStack(spacing: 18) {
                        Link("Public model and source", destination: URL(string: "https://github.com/venkatasg/DeTeXt-Supplementary")!)
                        Link("DeTeXt project", destination: URL(string: "https://github.com/venkatasg/DeTeXt")!)
                    }.font(.caption)
                }.padding(16).glassPanel(radius: 12)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open the original DeTeXt app").font(.headline)
                    Text("The original app opens in its own window. This section uses its published symbol model with SketchGlide’s drawing and formula tools.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Open original DeTeXt") { openOriginalApplication() }
                        .buttonStyle(.bordered).disabled(installedApplication == nil)
                    if installedApplication == nil {
                        Link("Get DeTeXt", destination: URL(string: "https://venkatasg.net/apps/detext")!).font(.caption)
                    }
                    if !launchMessage.isEmpty { Text(launchMessage).font(.caption).foregroundStyle(.secondary) }
                }
                DisclosureGroup("Licence and training data attribution") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Public model and supplementary code: MIT License, copyright © 2020 Venkat. DeTeXt source: MIT License, copyright © 2025 Venkat. The full notices are included with the app's maths resources.")
                        Text("The developer trained the published model on Detexify samples. That sample database uses the Open Database License 1.0; the database isn't bundled with this app.")
                        Link("Detexify sample data and attribution", destination: URL(string: "https://github.com/kirel/detexify-data")!)
                        Link("Open Database License 1.0", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
            }.padding(.trailing, 4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func openOriginalApplication() {
        guard let url = installedApplication else {
            launchMessage = "Install DeTeXt to open the original app. The local symbol tools are ready here."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            Task { @MainActor in
                launchMessage = error.map { "Couldn't open DeTeXt: " + $0.localizedDescription } ?? "DeTeXt opened in its own window."
            }
        }
    }
}
