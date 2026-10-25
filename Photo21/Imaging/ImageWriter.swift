import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageWriteError: Error, LocalizedError {
    case encodeFailed
    case trashFailed(Error)

    var errorDescription: String? {
        switch self {
        case .encodeFailed: "Couldn't encode the image."
        case .trashFailed(let e): "Couldn't move the original to the Trash: \(e.localizedDescription)"
        }
    }
}

struct EncodedImage: Sendable {
    let data: Data
    let type: UTType
    /// False when the source format can't be written (e.g. RAW) and we fell back to JPEG.
    let keepsSourceFormat: Bool
}

/// ImageIO encoding plus the file dance (trash original, atomic write, keep creation date).
enum ImageWriter {
    static let lossyQuality = 0.92
    static let writableTypes: Set<String> = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    static func encode(_ image: CGImage, sourceURL: URL) throws -> EncodedImage {
        let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)
        let sourceType = src.flatMap { CGImageSourceGetType($0) as String? }.flatMap { UTType($0) }
        let writable = sourceType.map { writableTypes.contains($0.identifier) && $0 != .gif } ?? false
        let type = writable ? sourceType! : UTType.jpeg

        var properties: [CFString: Any] = [:]
        if let src, var props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            props[kCGImagePropertyOrientation] = 1
            props.removeValue(forKey: kCGImagePropertyPixelWidth)
            props.removeValue(forKey: kCGImagePropertyPixelHeight)
            if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                props[kCGImagePropertyTIFFDictionary] = tiff
            }
            if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif[kCGImagePropertyExifPixelXDimension] = image.width
                exif[kCGImagePropertyExifPixelYDimension] = image.height
                props[kCGImagePropertyExifDictionary] = exif
            }
            properties = props
        }
        properties[kCGImagePropertyOrientation] = 1
        if type == .jpeg || type == .heic || type == .heif {
            properties[kCGImageDestinationLossyCompressionQuality] = lossyQuality
        }

        var metadata: CGMutableImageMetadata?
        if let src, let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil) {
            let mutable = CGImageMetadataCreateMutableCopy(meta)
            if let mutable {
                CGImageMetadataSetValueWithPath(mutable, nil, "tiff:Orientation" as CFString, "1" as CFString)
                CGImageMetadataSetValueWithPath(mutable, nil, "exif:PixelXDimension" as CFString, "\(image.width)" as CFString)
                CGImageMetadataSetValueWithPath(mutable, nil, "exif:PixelYDimension" as CFString, "\(image.height)" as CFString)
            }
            metadata = mutable
        }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ImageWriteError.encodeFailed
        }
        if let metadata {
            CGImageDestinationAddImageAndMetadata(dest, image, metadata, properties as CFDictionary)
        } else {
            CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw ImageWriteError.encodeFailed }
        return EncodedImage(data: data as Data, type: type, keepsSourceFormat: writable)
    }

    /// Replaces `url` with `encoded`. The original goes to the Trash first.
    /// When the format changed, the original is left untouched and a sibling file is written instead.
    /// Returns the URL that was written.
    @discardableResult
    static func saveInPlace(_ encoded: EncodedImage, originalURL url: URL) throws -> URL {
        guard encoded.keepsSourceFormat else {
            return try saveCopy(encoded, originalURL: url)
        }
        let fm = FileManager.default
        let creationDate = (try? fm.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw ImageWriteError.trashFailed(error)
        }
        try encoded.data.write(to: url, options: .atomic)
        if let creationDate {
            try? fm.setAttributes([.creationDate: creationDate], ofItemAtPath: url.path)
        }
        return url
    }

    /// Writes `name-1.ext` (first free number) next to the original. Returns the new URL.
    @discardableResult
    static func saveCopy(_ encoded: EncodedImage, originalURL url: URL) throws -> URL {
        let ext = encoded.keepsSourceFormat ? url.pathExtension : (encoded.type.preferredFilenameExtension ?? "jpg")
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        var n = 1
        var target = dir.appendingPathComponent("\(base)-\(n)").appendingPathExtension(ext)
        while FileManager.default.fileExists(atPath: target.path) {
            n += 1
            target = dir.appendingPathComponent("\(base)-\(n)").appendingPathExtension(ext)
        }
        try encoded.data.write(to: target, options: .atomic)
        return target
    }
}
