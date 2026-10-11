import Foundation
import AppKit

/// A small Responses API client. Credentials are read only for an explicit request.
@MainActor
final class AIClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport
    private let keyProvider: () throws -> String?
    private let modelProvider: () -> String

    init(transport: @escaping Transport = { try await SecureNetwork.session.data(for: $0) },
         keyProvider: @escaping () throws -> String? = { try AIKeychain.read() },
         modelProvider: @escaping () -> String = {
             UserDefaults.standard.string(forKey: "engineeringboard.ai.model") ?? "gpt-4.1"
         }) {
        self.transport = transport
        self.keyProvider = keyProvider
        self.modelProvider = modelProvider
    }

    func request(text: String, history: [AssistantMessage] = [], board: Board? = nil,
                 instructions: String) throws -> URLRequest {
        guard let key = try keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw AssistantConversation.APIError.message("Add your OpenAI API key in AI Settings before sending.")
        }
        let model = modelProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw AssistantConversation.APIError.message("Enter a model ID in AI Settings.") }
        var input: [[String: Any]] = history.suffix(20).map {
            let text = $0.attachedBoard
                ? $0.text + "\n[An earlier board image is not included in this request.]" : $0.text
            return ["role": $0.role, "content": text]
        }
        var content: [[String: Any]] = [["type": "input_text", "text": text]]
        if let board {
            guard let dataURL = Self.boardDataURL(board) else {
                throw AssistantConversation.APIError.message("The board image couldn't be prepared. Try sending without it.")
            }
            content.append(["type": "input_image", "image_url": dataURL, "detail": "auto"])
        }
        input.append(["role": "user", "content": content])
        let body: [String: Any] = ["model": model, "instructions": instructions, "input": input,
                                   "store": false, "max_output_tokens": 2200]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func perform(_ request: URLRequest, requiresComplete: Bool = false) async throws -> String {
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let endpoint = request.url, SecureNetwork.acceptsResponse(response, for: endpoint),
              let http = response as? HTTPURLResponse else {
            throw AssistantConversation.APIError.message("OpenAI returned an invalid response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AssistantConversation.APIError.message(Self.failureMessage(status: http.statusCode))
        }
        if requiresComplete, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if object["status"] as? String == "incomplete" {
                throw AssistantConversation.APIError.message("The wording correction was cut short. Your preview was kept. Select a shorter section and try again.")
            }
            let output = object["output"] as? [[String: Any]] ?? []
            let parts = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
            if parts.contains(where: { $0["type"] as? String == "refusal" }) {
                throw AssistantConversation.APIError.message("OpenAI didn't provide a wording correction. Your preview was kept. Try local spelling or a shorter section.")
            }
        }
        return try AssistantConversation.replyText(data: data)
    }

    private static func boardDataURL(_ source: Board) -> String? {
        let board = BoardExport.normalized(board: source)
        let scale = min(1, 1600 / max(board.width, board.height))
        let image = BoardRenderer.image(board: board, scale: scale)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }

    private static func failureMessage(status: Int) -> String {
        // Provider error bodies may contain private request details: do not echo them.
        switch status {
        case 401: return "OpenAI rejected the API key. Check it in AI Settings."
        case 403: return "Your OpenAI account doesn't have permission for this request."
        case 404: return "This model isn't available to your account. Check the model ID."
        case 429: return "OpenAI reports a usage limit or unavailable API credit. Check API billing and limits."
        case 400: return "OpenAI couldn't accept this request. Check the model supports Responses and any board image."
        case 500...599: return "OpenAI is temporarily unavailable. Try again later."
        default: return "OpenAI returned HTTP \(status). Check your API settings."
        }
    }
}
