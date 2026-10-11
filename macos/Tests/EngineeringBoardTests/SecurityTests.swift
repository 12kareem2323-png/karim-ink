import XCTest
import AppKit
import ImageIO
@testable import EngineeringBoard

final class SecurityTests: XCTestCase {
    private func png(width: Int = 8, height: Int = 5) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A tiny PNG with a hostile dimension header: no oversized pixel allocation.
    private func headerOnlyDimensions(width: UInt32, height: UInt32) throws -> Data {
        var data = [UInt8](try png(width: 1, height: 1))
        func put(_ value: UInt32, at index: Int) {
            for offset in 0..<4 { data[index + offset] = UInt8((value >> (24 - offset * 8)) & 255) }
        }
        put(width, at: 16); put(height, at: 20)
        var crc: UInt32 = 0xffffffff
        for value in data[12..<29] {
            crc ^= UInt32(value)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        put(crc ^ 0xffffffff, at: 29)
        return Data(data)
    }

    func testImageHeaderAndBoundedThumbnail() throws {
        let data = try png(width: 6_000, height: 2)
        XCTAssertEqual(try SafeImage.validate(data), .init(width: 6_000, height: 2))
        let image = try SafeImage.decode(data)
        XCTAssertLessThanOrEqual(image.size.width, Double(SafeImage.maximumDecodedEdge))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertEqual(image.size.width / image.size.height, 3_000, accuracy: 0.0001)
    }

    func testDamagedOrEmptyImagesAreRejected() {
        XCTAssertThrowsError(try SafeImage.validate(Data()))
        XCTAssertThrowsError(try SafeImage.validate(Data("not image data".utf8)))
        XCTAssertThrowsError(try SafeImage.decode(Data([0, 1, 2, 3])))
    }

    func testHugeDimensionsAreRejectedBeforePixelDecode() throws {
        XCTAssertThrowsError(try SafeImage.validate(headerOnlyDimensions(width: 32_769, height: 1)))
        XCTAssertThrowsError(try SafeImage.validate(headerOnlyDimensions(width: 12_000, height: 12_000)))
    }

    func testOversizedFileIsRejectedBeforeRead() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("oversized.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SafeImage.maximumBytes + 1)); try handle.close()
        XCTAssertThrowsError(try SafeImage.readFile(url))
        XCTAssertThrowsError(try SafeImage.readFile(folder))
        XCTAssertThrowsError(try SafeImage.readFile(URL(string: "https://example.com/image.png")!))
    }

    func testImageCacheCannotReturnPreviousBytesForSameIdentifier() throws {
        let id = UUID()
        XCTAssertEqual(try SafeImage.decode(png(width: 8, height: 5), cacheID: id).size.width, 8)
        XCTAssertEqual(try SafeImage.decode(png(width: 3, height: 2), cacheID: id).size.width, 3)
    }

    func testBoardRejectsInvalidImageWithoutAcceptingHiddenPayload() throws {
        let bad = DrawingElement(kind: .image, points: [InkPoint(x: 0, y: 0), InkPoint(x: 20, y: 20)], imageData: Data([1, 2, 3]))
        XCTAssertThrowsError(try BoardFile.validate(Board(elements: [bad])))
        var valid = bad
        valid.imageData = try png()
        XCTAssertNoThrow(try BoardFile.validate(Board(elements: [valid])))
    }

    func testAuthenticatedSessionHasNoPersistentCacheOrCookies() {
        let configuration = SecureNetwork.configuration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testRedirectAndUnexpectedResponseEndpointsAreRejected() throws {
        let endpoint = URL(string: "https://api.openai.com/v1/responses")!
        func response(_ url: String, status: Int = 200) throws -> HTTPURLResponse {
            try XCTUnwrap(HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil))
        }
        XCTAssertTrue(SecureNetwork.acceptsResponse(try response(endpoint.absoluteString), for: endpoint))
        XCTAssertTrue(SecureNetwork.acceptsResponse(try response(endpoint.absoluteString, status: 401), for: endpoint))
        XCTAssertFalse(SecureNetwork.acceptsResponse(try response(endpoint.absoluteString, status: 302), for: endpoint))
        XCTAssertFalse(SecureNetwork.acceptsResponse(try response("https://example.com/v1/responses"), for: endpoint))
        XCTAssertFalse(SecureNetwork.acceptsResponse(try response("http://api.openai.com/v1/responses"), for: endpoint))
        XCTAssertFalse(SecureNetwork.acceptsResponse(try response("https://api.openai.com/other"), for: endpoint))
        XCTAssertFalse(SecureNetwork.acceptsResponse(try response("https://api.openai.com/v1/responses?unexpected=1"), for: endpoint))
    }

    @MainActor
    func testCloudConstructionReadsCredentialsOnlyForExplicitRequest() throws {
        var reads = 0
        let client = AIClient(keyProvider: { reads += 1; return "verification-placeholder" }, modelProvider: { "test-model" })
        XCTAssertEqual(reads, 0)
        let request = try client.request(text: "Synthetic test", instructions: "Test only")
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(request.url?.host, "api.openai.com")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertFalse(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains("input_image"))
    }
}
