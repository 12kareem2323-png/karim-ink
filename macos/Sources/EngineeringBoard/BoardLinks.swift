import AppKit
import Foundation

/// A local link reopens the saved drawing; it is not a web-hosted copy.
enum BoardLinks {
    static let scheme = "karimboard"

    static func url(for id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "board"
        components.path = "/" + id.uuidString
        return components.url!
    }

    static func boardID(from url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == "board",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let path = components.percentEncodedPath
        // Reject extra paths, escaped separators and non-canonical UUID spellings.
        guard path.count == 37, path.first == "/", !path.contains("%"),
              let id = UUID(uuidString: String(path.dropFirst())),
              String(path.dropFirst()).uppercased() == id.uuidString else { return nil }
        return id
    }

    @MainActor
    @discardableResult
    static func copy(for board: Board) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let link = url(for: board.id).absoluteString
        let urlWritten = pasteboard.setString(link, forType: .URL)
        let textWritten = pasteboard.setString(link, forType: .string)
        return urlWritten && textWritten
    }
}
