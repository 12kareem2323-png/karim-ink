import SwiftUI
import AppKit

/// Publisher links come from the signed bundle. Private files and credentials are never attached.
enum ReleaseSupport {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2" }
    static var repository: URL? { validatedURL("KarimRepositoryURL", hosts: ["github.com"]) }
    static var website: URL? { validatedURL("KarimWebsiteURL", hosts: nil) }
    static var donationLinks: [(String, URL)] {
        [("Buy Me a Coffee", "KarimBuyMeACoffeeURL", ["buymeacoffee.com", "www.buymeacoffee.com"]),
         ("Ko-fi", "KarimKoFiURL", ["ko-fi.com", "www.ko-fi.com"]),
         ("PayPal", "KarimPayPalURL", ["paypal.me", "www.paypal.me", "paypal.com", "www.paypal.com"])]
            .compactMap { name, key, hosts in validatedURL(key, hosts: hosts).map { (name, $0) } }
    }
    static func validatedURL(_ key: String, hosts: [String]?) -> URL? {
        guard let value=Bundle.main.object(forInfoDictionaryKey:key) as? String,
              let components=URLComponents(string:value), components.scheme == "https", let host=components.host?.lowercased(),
              components.user == nil, components.password == nil, components.port == nil,
              hosts == nil || hosts!.contains(host), let url=components.url else { return nil }
        return url
    }
    static var systemSummary: String {
        let os=ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture="Apple silicon (ARM64)"
        #else
        let architecture="Intel (x86_64)"
        #endif
        return "SketchGlide \(version) (build \(build))\nmacOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)\n\(architecture)"
    }
    static func issueURL(title: String, body: String) -> URL? {
        guard let repository else { return nil }
        var components=URLComponents(url:repository.appendingPathComponent("issues/new"),resolvingAgainstBaseURL:false)
        // Keep browser URLs bounded. Longer feedback can be copied or saved for manual submission.
        let shortBody=String(body.prefix(1800))
        components?.queryItems=[URLQueryItem(name:"title",value:String(title.prefix(120))),URLQueryItem(name:"body",value:shortBody)]
        return components?.url
    }
}

struct ReleaseSupportView: View {
    @State private var kind="Bug report"
    @State private var summary=""
    @State private var details=""
    @State private var includeSystem=true
    @State private var status=""
    private var feedback: String {
        "## \(kind)\n\(summary)\n\n\(details)" + (includeSystem ? "\n\n## Basic system details\n\(ReleaseSupport.systemSummary)" : "")
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Help shape SketchGlide").font(.title2.weight(.semibold))
                Text("0.2 Test is a personal project made by Kareem. Help improve it with feedback or a contribution on GitHub.").foregroundStyle(.secondary)
                Picker("Feedback type",selection:$kind) { ForEach(["Bug report","Feature idea","Tablet feedback"],id:\.self) { Text($0) } }
                TextField("Short summary",text:$summary)
                Text("Describe what happened, what you expected, and how to repeat it.").font(.caption).foregroundStyle(.secondary)
                TextEditor(text:$details).font(.body).frame(minHeight:130).border(Color.secondary.opacity(0.2))
                Toggle("Include app version, macOS version and processor type",isOn:$includeSystem)
                Text("No drawings, account names, serial numbers, API keys or logs are attached. GitHub issues are public: review your text before submitting.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Review on GitHub") { if let url=ReleaseSupport.issueURL(title:summary,body:feedback) { NSWorkspace.shared.open(url) } }
                        .disabled(ReleaseSupport.repository == nil || summary.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    Button("Copy feedback") { NSPasteboard.general.clearContents();NSPasteboard.general.setString(feedback,forType:.string);status="Feedback copied." }
                    Button("Save feedback…") { saveFeedback() }
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
                Divider()
                Text("Support development").font(.headline)
                Text("Donations are optional and do not unlock app features. Payments happen on the provider’s website; the app never receives your card details.").font(.callout).foregroundStyle(.secondary)
                if ReleaseSupport.donationLinks.isEmpty {
                    Text("Support links are configured by the project publisher.").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack { ForEach(ReleaseSupport.donationLinks,id:\.0) { name,url in Link(name,destination:url) } }
                }
                if let website=ReleaseSupport.website { Link("Project website and latest support options",destination:website) }
                if let repository=ReleaseSupport.repository { Link("Downloads, release notes and known issues",destination:repository) }
                Text("Security concerns: use the repository’s private vulnerability report if enabled. Keep sensitive drawings and credentials out of public feedback.").font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }
    }
    private func saveFeedback() {
        let panel=NSSavePanel();panel.nameFieldStringValue="SketchGlide-feedback.txt"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try feedback.write(to:url,atomically:true,encoding:.utf8);status="Feedback saved."}
        catch {status="Feedback could not be saved: \(error.localizedDescription)"}
    }
}
