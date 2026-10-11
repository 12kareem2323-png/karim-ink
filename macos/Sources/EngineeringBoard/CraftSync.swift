import SwiftUI
import Foundation
import Security

struct CraftConnection: Codable {
    let endpoint: String
    let bearerToken: String

    var baseURL: URL {
        get throws {
            let cleaned = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let components = URLComponents(string: cleaned), components.scheme == "https",
                  components.host?.lowercased() == "connect.craft.do", components.port == nil,
                  components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
                  !components.percentEncodedPath.contains("%"),
                  let url = components.url else { throw CraftSyncError.invalidConnection }
            let path = components.path.split(separator: "/")
            guard path.count == 4, path[0] == "link", path[2] == "api", path[3] == "v1",
                  Self.validIdentifier(String(path[1])) else { throw CraftSyncError.invalidConnection }
            return url
        }
    }

    static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 200 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0)
        }
    }
}

/// The connection URL is a credential too. Neither it nor the optional token is
/// stored in UserDefaults, drawing files, exports or diagnostic output.
enum CraftConnectionKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.engineeringboard.craft",
         kSecAttrAccount as String: "api-connection"]
    }
    static func save(_ connection: CraftConnection) throws {
        _ = try connection.baseURL
        let data = try JSONEncoder().encode(connection)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CraftSyncError.keychain }
        } else if result != errSecSuccess { throw CraftSyncError.keychain }
    }
    static func read() throws -> CraftConnection {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { throw CraftSyncError.noConnection }
        guard status == errSecSuccess, let data = result as? Data,
              let connection = try? JSONDecoder().decode(CraftConnection.self, from: data) else { throw CraftSyncError.keychain }
        _ = try connection.baseURL
        return connection
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CraftSyncError.keychain }
    }
}

enum CraftSyncError: LocalizedError {
    case invalidConnection, invalidTarget, noConnection, keychain, unexpectedResponse, network, status(Int), incompleteVerification, ownershipCollision
    var errorDescription: String? {
        switch self {
        case .invalidConnection: return "Use the API URL from Craft's Imagine tab: https://connect.craft.do/link/…/api/v1."
        case .invalidTarget: return "Enter the block ID of the Craft whiteboard you want to update."
        case .noConnection: return "Save your Craft API connection first."
        case .keychain: return "macOS Keychain could not access the Craft connection."
        case .unexpectedResponse: return "Craft returned an unexpected response. The local drawing is unchanged."
        case .network: return "Craft could not be reached. Check your connection, then send again."
        case .status(let code):
            if code == 401 || code == 403 { return "Craft rejected this API connection. Check its document scope and access settings." }
            if code == 404 { return "This Craft whiteboard could not be found within the connection's document scope." }
            return "Craft could not complete the update (HTTP \(code)). Send again to reconcile the current objects."
        case .incompleteVerification: return "Craft accepted changes but the verification did not match every imported object. Send again to reconcile; the local drawing is unchanged."
        case .ownershipCollision: return "An imported object ID is already used by an unrelated Craft object. Choose a separate whiteboard; this object will not be overwritten."
        }
    }
}

/// Each update reconciles server IDs first, including after an uncertain POST.
/// Only IDs owned by this native board are changed; unrelated Craft objects stay intact.
@MainActor
final class CraftSyncClient {
    private let connection: CraftConnection
    private let network: URLSession
    init(connection: CraftConnection, network: URLSession = SecureNetwork.session) {
        self.connection = connection; self.network = network
    }

    func sync(board: Board, whiteboardID: String) async throws -> Int {
        guard CraftConnection.validIdentifier(whiteboardID) else { throw CraftSyncError.invalidTarget }
        let desired = try CraftExchange.vectorElements(board: board)
        let prefix = "karim-" + board.id.uuidString.lowercased() + "-"
        let path = "whiteboards/\(whiteboardID)/elements"
        let initial = try await request(method: "GET", path: path)
        guard let remote = initial["elements"] as? [[String: Any]] else { throw CraftSyncError.unexpectedResponse }
        let remoteByID = Dictionary(remote.compactMap { item -> (String, [String: Any])? in
            guard let id = item["id"] as? String else { return nil }
            return (id, item)
        }, uniquingKeysWith: { _, newest in newest })
        let wantedIDs = Set(desired.compactMap { $0["id"] as? String })
        for id in wantedIDs {
            if let previous = remoteByID[id] {
                guard let custom = previous["customData"] as? [String: Any],
                      custom["boardID"] as? String == board.id.uuidString,
                      custom["app"] as? String == "Karim Eldamaty" else { throw CraftSyncError.ownershipCollision }
            }
        }
        let add = desired.filter { value in (value["id"] as? String).map { remoteByID[$0] == nil } ?? false }
        let update = desired.compactMap { value -> [String: Any]? in
            guard let id = value["id"] as? String, let previous = remoteByID[id] else { return nil }
            var next = value
            next["version"] = min(Int.max - 1, max(1, previous["version"] as? Int ?? 1)) + 1
            next["versionNonce"] = Int.random(in: 1...Int(Int32.max))
            return next
        }
        let remove = remoteByID.keys.filter { id in
            guard id.hasPrefix(prefix), !wantedIDs.contains(id),
                  remoteByID[id]?["isDeleted"] as? Bool != true,
                  let custom = remoteByID[id]?["customData"] as? [String: Any] else { return false }
            return custom["boardID"] as? String == board.id.uuidString && custom["app"] as? String == "Karim Eldamaty"
        }
        for batch in Self.batches(add) { _ = try await request(method: "POST", path: path, body: ["elements": batch]) }
        // Craft's append endpoint can omit freehand points even while accepting
        // their pressure array. Initialize all newly added geometry with PUT in
        // this same send, so the first send produces a verified complete board.
        let initialize = add.map { value -> [String: Any] in
            var next = value
            next["version"] = 2
            next["versionNonce"] = Int.random(in: 1...Int(Int32.max))
            return next
        }
        for batch in Self.batches(update + initialize) { _ = try await request(method: "PUT", path: path, body: ["elements": batch]) }
        for batch in Self.batches(Array(remove)) { _ = try await request(method: "DELETE", path: path, body: ["elementIds": batch]) }
        let final = try await request(method: "GET", path: path)
        guard let finalElements = final["elements"] as? [[String: Any]] else { throw CraftSyncError.unexpectedResponse }
        let activeFinal = finalElements.filter { $0["isDeleted"] as? Bool != true }
        let finalIDs = Set(activeFinal.compactMap { $0["id"] as? String })
        guard wantedIDs.isSubset(of: finalIDs), Set(remove).isDisjoint(with: finalIDs) else { throw CraftSyncError.incompleteVerification }
        let finalByID = Dictionary(activeFinal.compactMap { value -> (String, [String: Any])? in
            guard let id = value["id"] as? String else { return nil }; return (id, value)
        }, uniquingKeysWith: { _, last in last })
        for value in desired {
            guard let id = value["id"] as? String, let persisted = finalByID[id] else { throw CraftSyncError.incompleteVerification }
            for key in ["type", "x", "y", "width", "height", "angle", "strokeColor", "backgroundColor", "strokeWidth", "opacity", "points", "pressures", "text"] where value[key] != nil {
                guard let actual = persisted[key], NSDictionary(dictionary: [key: value[key]!]).isEqual(to: [key: actual]) else {
                    throw CraftSyncError.incompleteVerification
                }
            }
        }
        return desired.count
    }

    private func request(method: String, path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var url = try connection.baseURL
        for component in path.split(separator: "/") { url.appendPathComponent(String(component)) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !connection.bearerToken.isEmpty { request.setValue("Bearer " + connection.bearerToken, forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await network.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw CraftSyncError.network }
        guard SecureNetwork.acceptsResponse(response, for: url),
              let http = response as? HTTPURLResponse else { throw CraftSyncError.unexpectedResponse }
        guard (200..<300).contains(http.statusCode) else { throw CraftSyncError.status(http.statusCode) }
        if data.isEmpty { return [:] }
        guard data.count <= BoardFile.maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CraftSyncError.unexpectedResponse }
        return object
    }

    private static func batches<T>(_ values: [T]) -> [[T]] {
        stride(from: 0, to: values.count, by: 500).map { Array(values[$0..<min($0 + 500, values.count)]) }
    }
}

@MainActor
final class CraftSyncController: ObservableObject {
    @Published var live = false
    @Published private(set) var busy = false
    @Published private(set) var status = "Set a Craft API connection and choose one target whiteboard."
    @Published private(set) var failed = false
    private var pending: Task<Void, Never>?
    private var queued: (board: Board, target: String)?

    func schedule(board: Board, target: String) {
        guard live else { return }
        if busy { queued = (board, target); return }
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_000_000_000) }
            catch { return }
            guard let self, self.live else { return }
            self.send(board: board, target: target)
        }
    }
    func send(board: Board, target: String) {
        if busy { queued = (board, target); return }
        pending?.cancel(); pending = nil
        busy = true; failed = false; status = "Updating the chosen Craft whiteboard…"
        pending = Task { [weak self] in
            guard let self else { return }
            do {
                let client = CraftSyncClient(connection: try CraftConnectionKeychain.read())
                let count = try await client.sync(board: board, whiteboardID: target)
                self.status = "Verified \(count) imported objects in Craft."
            } catch is CancellationError { self.status = "Craft update stopped. Send again to reconcile any accepted changes." }
            catch { self.status = error.localizedDescription; self.failed = true; self.live = false }
            self.busy = false; self.pending = nil
            if let next = self.queued {
                self.queued = nil
                if self.live { self.schedule(board: next.board, target: next.target) }
            }
        }
    }
    func stop() {
        live = false; pending?.cancel(); queued = nil
    }
}

struct CraftSyncPanel: View {
    @ObservedObject var session: DrawingSession
    @StateObject private var sync = CraftSyncController()
    @State private var endpoint = ""
    @State private var token = ""
    @State private var target = ""
    @State private var setupStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Craft whiteboard", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                Text("Keep your native drawing linked to one editable Craft whiteboard. Basic pen paths, shapes, text and mm labels can update there.")
                    .font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("Connection setup") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("Craft API connection URL", text: $endpoint).textFieldStyle(.roundedBorder).disabled(sync.busy || sync.live)
                        SecureField("Bearer token, if required", text: $token).textFieldStyle(.roundedBorder).disabled(sync.busy || sync.live)
                        Button("Save connection in Keychain") { saveConnection() }.disabled(endpoint.isEmpty || sync.busy || sync.live)
                        Button("Remove saved connection", role: .destructive) { removeConnection() }.disabled(sync.busy)
                        Text("Create a document-scoped API connection in Craft's Imagine tab. The connection URL is kept private in Keychain.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Craft API setup", destination: URL(string: "https://connect.craft.do/api-docs/documents/")!)
                    }.padding(.top, 8)
                }
                if !setupStatus.isEmpty { Text(setupStatus).font(.caption).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target whiteboard block ID").font(.subheadline.weight(.semibold))
                    TextField("Paste a Craft whiteboard block ID", text: $target).textFieldStyle(.roundedBorder)
                        .disabled(sync.busy || sync.live)
                    Text("The connection must include the document containing this whiteboard. A document ID or ordinary page link is not a whiteboard block ID.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Send / update") { send() }.buttonStyle(.borderedProminent).disabled(sync.busy || target.isEmpty)
                    if sync.busy { ProgressView().controlSize(.small); Button("Stop") { sync.stop() } }
                }
                Toggle("Live updates to this target", isOn: $sync.live)
                    .disabled(target.isEmpty || sync.busy)
                    .onChange(of: sync.live) { _, active in if active { send() } else { sync.stop() } }
                Text(sync.status).font(.caption).foregroundStyle(sync.failed ? Color.red : Color.secondary)
                Text("Live updates run while this Craft panel is open. The local drawing controls its imported objects; edits to those objects in Craft may be replaced. Other Craft objects stay intact. Images, textured brushes and complex symbols need a file or image export.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Button("Copy native drawing link") { session.finishActiveInput?(); if BoardLinks.copy(for: session.board) { session.status = "Native drawing link copied" } }
                Button("Export editable whiteboard file…") {
                    session.finishActiveInput?()
                    do { try CraftExchange.export(board: session.board) }
                    catch { setupStatus = error.localizedDescription }
                }
            }.padding(16)
        }
        .onAppear { target = UserDefaults.standard.string(forKey: targetPreference) ?? "" }
        .onChange(of: target) { _, next in UserDefaults.standard.set(next, forKey: targetPreference) }
        .onChange(of: session.revision) { _, _ in sync.schedule(board: session.board, target: target) }
        .onDisappear { sync.stop() }
    }

    private var targetPreference: String { "engineeringboard.craft.target." + session.board.id.uuidString }
    private func send() { session.finishActiveInput?(); sync.send(board: session.board, target: target.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private func saveConnection() {
        do {
            try CraftConnectionKeychain.save(CraftConnection(endpoint: endpoint, bearerToken: token.trimmingCharacters(in: .whitespacesAndNewlines)))
            endpoint = ""; token = ""; setupStatus = "Craft connection saved in Keychain."
        } catch { setupStatus = error.localizedDescription }
    }
    private func removeConnection() {
        sync.stop()
        do { try CraftConnectionKeychain.remove(); setupStatus = "Craft connection removed." }
        catch { setupStatus = error.localizedDescription }
    }
}
