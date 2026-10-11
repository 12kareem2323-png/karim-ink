import SwiftUI
import Security
import LocalAuthentication

extension Notification.Name {
    static let aiConfigurationChanged = Notification.Name("engineeringboard.ai.configurationChanged")
}

enum AIKeychain {
    enum Presence { case missing, saved, unavailable }

    /// Check existence without requesting or loading the secret into the UI.
    static func presence() -> Presence {
        var request = query
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(request as CFDictionary, nil)
        if status == errSecSuccess { return .saved }
        if status == errSecItemNotFound { return .missing }
        return .unavailable
    }

    private static let service = "local.engineeringboard.openai"
    private static let account = "api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return key
    }

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let result = SecItemUpdate(query as CFDictionary,
                                  [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        } else if result != errSecSuccess {
            throw KeychainError(status: result)
        }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Error \(status)"
            return "Keychain could not complete this action: \(detail)"
        }
    }
}

struct AISettingsView: View {
    @AppStorage("engineeringboard.ai.model") private var model = "gpt-4.1"
    @AppStorage("engineeringboard.handwriting.autoReview") private var automaticWritingReview = true
    @State<String> private var enteredKey = ""
    @State<String> private var status = "Checking Keychain…"
    @State<Bool> private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("AI Assistant setup", systemImage: "sparkles")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
            ScrollView { content }
        }
        .frame(width: 530).frame(maxHeight: 520)
        .onAppear { refresh() }
        .onChange(of: model) { _, _ in
            NotificationCenter.default.post(name: .aiConfigurationChanged, object: nil)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Use your own OpenAI API key for cloud chat. API usage is billed separately from a ChatGPT subscription. Cloud chat needs internet; on-device chat works locally when Apple's model is ready.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("API key").font(.headline)
                SecureField("Paste an API key", text: $enteredKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save to Keychain") { save() }
                        .disabled(enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove saved key", role: .destructive) { remove() }
                }
                Text(status).font(.caption).foregroundStyle(failed ? Color.red : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Model ID").font(.headline)
                TextField("gpt-4.1", text: $model).textFieldStyle(.roundedBorder)
                Text("Choose a Responses API model available to your account. Board attachments need an image-capable model. The default is gpt-4.1.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Label("Local tools work without a key", systemImage: "desktopcomputer").font(.headline)
            Text(AILocalAssistant.availability.explanation).font(.caption).foregroundStyle(.secondary)
            Toggle("Automatically read recent handwriting after a pause", isOn: $automaticWritingReview)
            Text("Reads up to 60 recent ink strokes locally after 2.2 seconds of idle time. Suggestions are reviewed before insertion; original ink is retained.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Ink smoothing, Apple Vision text recognition, spelling suggestions and the maths symbol recognizer run on this Mac. Cloud chat and cloud wording correction need an API key and internet.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Nothing is sent to OpenAI automatically. On this Mac uses Apple's local model. Auto chooses local text chat or OpenAI for complex questions; the next-send route is shown before you click Send. OpenAI mode transmits your prompt and the recent chat to OpenAI. A board image is included only when you turn on Attach current board before sending. Chat history stays in memory for the current drawing while you switch panels; it isn't saved in drawing files.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Your key stays in macOS Keychain. It isn't written into drawings or exports. Requests use store: false; that setting does not guarantee zero provider retention.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
                Link("API pricing", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 4)
    }

    private func refresh() {
        switch AIKeychain.presence() {
            case .saved: status = "API key saved. The next explicit Send uses it; no test request has been made."; failed = false
            case .missing: status = "No API key saved."; failed = false
            case .unavailable: status = "Keychain is currently unavailable. Unlock your Mac and try again."; failed = true
        }
    }

    private func save() {
        do {
            try AIKeychain.save(enteredKey.trimmingCharacters(in: .whitespacesAndNewlines))
            enteredKey = ""
            status = "API key saved in macOS Keychain. No test request has been made."
            failed = false
            NotificationCenter.default.post(name: .aiConfigurationChanged, object: nil)
        } catch { status = error.localizedDescription; failed = true }
    }

    private func remove() {
        do {
            try AIKeychain.remove()
            enteredKey = ""
            status = "API key removed."
            failed = false
            NotificationCenter.default.post(name: .aiConfigurationChanged, object: nil)
        } catch { status = error.localizedDescription; failed = true }
    }
}
