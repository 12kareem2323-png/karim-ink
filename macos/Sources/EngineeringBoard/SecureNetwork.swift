import Foundation

/// Private prompts, artwork and credentials must never follow a server redirect.
/// Ephemeral storage also keeps authenticated payloads out of the disk cache.
enum SecureNetwork {
    private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let redirectDelegate = RedirectDelegate()

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        return configuration
    }

    static let session = URLSession(configuration: configuration(), delegate: redirectDelegate,
                                    delegateQueue: nil)

    /// Kept independent of transport for deterministic negative-path checks.
    static func acceptsResponse(_ response: URLResponse, for endpoint: URL) -> Bool {
        guard let response = response as? HTTPURLResponse,
              let finalURL = response.url,
              endpoint.scheme?.lowercased() == "https",
              finalURL.scheme?.lowercased() == "https",
              finalURL.host?.lowercased() == endpoint.host?.lowercased(),
              finalURL.port == endpoint.port,
              finalURL.user == nil, finalURL.password == nil,
              finalURL.path == endpoint.path,
              finalURL.query == endpoint.query,
              !(300...399).contains(response.statusCode) else { return false }
        return true
    }
}
