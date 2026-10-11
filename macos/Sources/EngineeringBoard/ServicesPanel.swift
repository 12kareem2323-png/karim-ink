import SwiftUI
import WebKit

struct ServicesPanel: View {
    @ObservedObject var session: DrawingSession
    @State private var mode = "Notes"
    @State private var input = ""
    @State private var loadedURL: URL?
    @State private var message = ""
    init(session: DrawingSession, initialMode: String = "Notes") {
        self.session = session
        let validMode = ["Notes", "Craft", "Notion", "Whiteboard"].contains(initialMode) ? initialMode : "Notes"
        _mode = State(initialValue: validMode)
        _input = State(initialValue: validMode == "Notion" ? session.board.notionURL : validMode == "Whiteboard" ? session.board.whiteboardURL : "")
    }

    var body: some View {
        // Native text editors and unavailable-content views have large ideal sizes.
        // Give every child the actual sidebar width instead of its intrinsic width.
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 28)
            VStack(alignment: .leading, spacing: 14) {
                modeChooser
                if mode == "Notes" {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Working notes").font(.system(size: 13, weight: .semibold))
                        Text("Keep your thoughts beside the drawing.").font(.system(size: 10)).foregroundStyle(.secondary)
                            .frame(width: width, alignment: .leading)
                        TextEditor(text: $session.board.notes)
                            .font(.system(size: 13)).scrollContentBackground(.hidden)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                            .onChange(of: session.board.notes) { _, _ in session.changed() }
                            .accessibilityLabel("Working notes for this drawing")
                    }.frame(width: width, alignment: .leading)
                } else if mode == "Craft" {
                    CraftSyncPanel(session: session).frame(width: width, alignment: .leading)
                } else {
                    webPane(width: width)
                }
            }
            .frame(width: width, height: max(0, geometry.size.height - 28), alignment: .topLeading)
            .padding(14)
        }
        .clipped()
        .onChange(of: mode) { _, _ in
            loadedURL = nil
            input = mode == "Notion" ? session.board.notionURL : session.board.whiteboardURL
            message = ""
        }
    }

    private var modeChooser: some View {
        HStack(spacing: 5) {
            ForEach(["Notes", "Craft", "Notion", "Whiteboard"], id: \.self) { name in
                Button { mode = name } label: {
                    VStack(spacing: 5) {
                        Image(systemName: modeIcon(name)).font(.system(size: 13, weight: .medium))
                        Text(name).font(.system(size: 9, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(mode == name ? Color.teal : Color.primary)
                    .background(mode == name ? Color.teal.opacity(0.10) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(mode == name ? Color.teal.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 0.5))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                    .help(name == "Whiteboard" ? "Open Microsoft Whiteboard beside your native drawing" : name + " workspace")
                    .accessibilityLabel(name + " workspace")
                    .accessibilityValue(mode == name ? "Selected" : "")
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("Choose notes or a connected service")
    }

    private func webPane(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if mode == "Notion" {
                HStack(spacing: 8) {
                    Button {
                        session.finishActiveInput?()
                        do { try NotionHTMLExport.export(board: session.board) }
                        catch { message = error.localizedDescription }
                    } label: { Label("Export HTML", systemImage: "square.and.arrow.up") }
                        .help("Export an interactive HTML copy for Notion")
                        .accessibilityLabel("Export interactive HTML for Notion")
                    Button { session.finishActiveInput?(); _ = BoardLinks.copy(for: session.board) } label: { Label("Copy link", systemImage: "link") }
                        .help("Copy the native drawing link").accessibilityLabel("Copy native drawing link")
                }.buttonStyle(.bordered).controlSize(.small)
                Text("In Notion, type /html and upload the exported copy. It has its own web ink; use the native board link for all pens and tablet tools.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).frame(width: width, alignment: .leading)
            }
            HStack(spacing: 6) {
                TextField(mode == "Notion" ? "Paste a Notion page URL" : "Paste a Whiteboard URL", text: $input)
                    .textFieldStyle(.roundedBorder).frame(minWidth: 0, maxWidth: .infinity)
                    .onSubmit { load() }
                Button("Open") { load() }.fixedSize()
            }.controlSize(.small).frame(width: width)
            Text("Sign in directly with the service. This web panel sits beside the native canvas.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(width: width, alignment: .leading)
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).frame(width: width, alignment: .leading)
            }
            if let loadedURL {
                ServiceWebView(url: loadedURL, onError: { message = $0 }).id(loadedURL.absoluteString)
                    .frame(width: width).clipShape(RoundedRectangle(cornerRadius: 12))
                Button("Open in your browser") { NSWorkspace.shared.open(loadedURL) }.font(.caption)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "globe").font(.system(size: 29, weight: .light)).foregroundStyle(.teal)
                    Text(mode).font(.system(size: 14, weight: .semibold))
                    Text("Open your page here. An organisation account may need your usual browser for sign-in.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20).frame(width: width).frame(minHeight: 140, maxHeight: .infinity)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            }
        }.frame(width: width, alignment: .leading).frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func modeIcon(_ name: String) -> String {
        switch name {
        case "Notes": return "note.text"
        case "Craft": return "arrow.triangle.2.circlepath"
        case "Notion": return "doc.text"
        default: return "rectangle.and.pencil.and.ellipsis"
        }
    }
    func load() {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned), url.scheme == "https", let host = url.host?.lowercased() else { message = "Use a full https:// page link."; return }
        let allowed = mode == "Notion" ? ["notion.so", "notion.com", "notion.site"] : ["whiteboard.microsoft.com", "app.whiteboard.microsoft.com", "whiteboard.office.com"]
        guard allowed.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { message = "Please use a \(mode) page link."; return }
        if mode == "Notion" { session.board.notionURL = cleaned } else { session.board.whiteboardURL = cleaned }
        session.changed(); message = ""; loadedURL = url
    }
}

struct ServiceWebView: NSViewRepresentable {
    let url: URL
    var onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.load(URLRequest(url: url)); return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onError: (String) -> Void
        init(onError: @escaping (String) -> Void) { self.onError = onError }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { onError("This page could not load: " + error.localizedDescription) } }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onError(error.localizedDescription) }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, url.scheme == "https" { NSWorkspace.shared.open(url) }
            return nil
        }
    }
}
