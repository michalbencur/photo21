import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageInfo: Sendable {
    /// Pixel size after applying the EXIF orientation.
    let pixelSize: CGSize
    let type: UTType?
}

enum ImageLoadError: Error, LocalizedError {
    case unreadable(URL)
    case decodeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Can't read \(url.lastPathComponent)."
        case .decodeFailed(let url): "Can't decode \(url.lastPathComponent)."
        }
    }
}

/// ImageIO-based decoding. All functions are synchronous and thread-safe; call them off the main actor.
enum ImageLoader {
    static let previewMaxPixels = 2560
    static let thumbnailMaxPixels = 200

    static let readableTypes: Set<String> = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])

    static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) && readableTypes.contains(type.identifier)
    }

    private static func source(for url: URL) throws -> CGImageSource {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageLoadError.unreadable(url)
        }
        return src
    }

    static func info(for url: URL) throws -> ImageInfo {
        let src = try source(for: url)
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double else {
            throw ImageLoadError.decodeFailed(url)
        }
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let swapped = orientation >= 5
        let type = (CGImageSourceGetType(src) as String?).flatMap { UTType($0) }
        return ImageInfo(pixelSize: swapped ? CGSize(width: h, height: w) : CGSize(width: w, height: h), type: type)
    }

    /// Decodes the image with EXIF orientation baked in, downsampled so its longer side is at most `maxPixels`.
    static func decode(url: URL, maxPixels: Int) throws -> CGImage {
        let src = try source(for: url)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw ImageLoadError.decodeFailed(url)
        }
        return image
    }

    /// Full-resolution decode with orientation baked in.
    static func decodeFull(url: URL) throws -> CGImage {
        let info = try info(for: url)
        return try decode(url: url, maxPixels: Int(max(info.pixelSize.width, info.pixelSize.height)))
    }

    /// Expands folders (one level), keeps readable images, de-duplicates and sorts like Finder.
    static func collectImageURLs(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for child in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
                where isSupportedImage(child) && seen.insert(child.standardizedFileURL.path).inserted {
                    result.append(child.standardizedFileURL)
                }
            } else if isSupportedImage(url), seen.insert(url.standardizedFileURL.path).inserted {
                result.append(url.standardizedFileURL)
            }
        }
        return result
    }
}
