import AppKit
import ImageIO

/// Inspect encoded headers before decoding any pixels. Original bytes remain in
/// editable boards; rendering uses a bounded first-frame thumbnail.
enum SafeImage {
    static let maximumBytes = 64 * 1024 * 1024
    static let maximumDimension = 32_768
    static let maximumSourcePixels = 128_000_000
    static let maximumDecodedEdge = 4_096

    struct Metadata: Equatable {
        let width: Int
        let height: Int
        let orientation: Int
        init(width: Int, height: Int, orientation: Int = 1) {
            self.width = width; self.height = height; self.orientation = orientation
        }
    }

    enum Failure: LocalizedError {
        case tooLarge, invalid, oversizedPixels, unsupportedFile
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "This image exceeds the 64 MB image limit. Resize it before importing."
            case .invalid: return "This image is damaged or isn't a supported raster image."
            case .oversizedPixels: return "This image is larger than the supported 128 megapixels or 32,768 pixel edge. Resize it before importing."
            case .unsupportedFile: return "Choose a regular local image file."
            }
        }
    }

    private static func source(_ data: Data) throws -> (CGImageSource, Metadata) {
        guard !data.isEmpty else { throw Failure.invalid }
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw Failure.invalid }
        let width = widthNumber.doubleValue, height = heightNumber.doubleValue
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width.rounded() == width, height.rounded() == height else { throw Failure.invalid }
        guard width <= Double(maximumDimension), height <= Double(maximumDimension),
              width * height <= Double(maximumSourcePixels) else { throw Failure.oversizedPixels }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (source, Metadata(width: Int(width), height: Int(height), orientation: orientation))
    }

    @discardableResult
    static func validate(_ data: Data) throws -> Metadata { try source(data).1 }

    static func readFile(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw Failure.unsupportedFile }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw Failure.unsupportedFile }
        guard let count = values.fileSize, count <= maximumBytes else { throw Failure.tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // A bounded read also handles a file growing after the metadata check.
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        try validate(data)
        return data
    }

    private final class CachedImage {
        let bytes: Data
        let image: NSImage
        init(bytes: Data, image: NSImage) { self.bytes = bytes; self.image = image }
    }
    private static let cache: NSCache<NSString, CachedImage> = {
        let cache = NSCache<NSString, CachedImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static func decode(_ data: Data, cacheID: UUID? = nil) throws -> NSImage {
        let key = cacheID.map { $0.uuidString as NSString }
        if let key, let cached = cache.object(forKey: key), cached.bytes == data { return cached.image }
        let (source, metadata) = try source(data)
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: maximumDecodedEdge,
                       kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              bitmap.width <= maximumDecodedEdge, bitmap.height <= maximumDecodedEdge else { throw Failure.invalid }
        // Thumbnail pixel rounding must not distort thin diagrams. Orient and
        // scale the logical size using the original header's exact aspect ratio.
        let swapped = (5...8).contains(metadata.orientation)
        let width = Double(swapped ? metadata.height : metadata.width)
        let height = Double(swapped ? metadata.width : metadata.height)
        let scale = min(1, Double(maximumDecodedEdge) / max(width, height))
        let image = NSImage(cgImage: bitmap, size: NSSize(width: width * scale, height: height * scale))
        if let key {
            cache.setObject(CachedImage(bytes: data, image: image), forKey: key,
                            cost: data.count + bitmap.bytesPerRow * bitmap.height)
        }
        return image
    }
}
