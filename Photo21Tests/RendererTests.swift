import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Photo21

struct RendererTests {
    /// 400x200 image: white, with a 40x40 red square in the top-left corner and a blue one bottom-right.
    static func makeImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 160, width: 40, height: 40)) // CG is y-up: this is the visual top-left
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 360, y: 0, width: 40, height: 40)) // visual bottom-right
        return ctx.makeImage()!
    }

    enum Colour { case red, blue, white, other }

    /// Classifies the pixel at a visual (x, y), y measured from the top.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> Colour {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let o = y * w * 4 + x * 4
        let (r, g, b) = (Int(p[o]), Int(p[o + 1]), Int(p[o + 2]))
        if r > 200 && g < 90 && b < 90 { return .red }
        if b > 200 && r < 90 && g < 90 { return .blue }
        if r > 230 && g > 230 && b > 230 { return .white }
        return .other
    }

    @Test func exactCropAtZero() throws {
        let img = Self.makeImage()
        var edit = EditState.identity(imageSize: CGSize(width: 400, height: 200))
        edit.crop = CGRect(x: 20, y: 20, width: 100, height: 50)
        let out = try Renderer.render(source: img, edit: edit)
        #expect(out.width == 100 && out.height == 50)
        #expect(Self.pixel(out, x: 5, y: 5) == .red)   // still inside the red square
        #expect(Self.pixel(out, x: 50, y: 25) == .white)
    }

    @Test func quarterTurnClockwiseMovesTopLeftToTopRight() throws {
        let img = Self.makeImage()
        var edit = EditState.identity(imageSize: CGSize(width: 400, height: 200))
        edit.rotate(quarterTurns: 1, imageSize: CGSize(width: 400, height: 200))
        #expect(edit.crop.width == 200 && edit.crop.height == 400)
        let out = try Renderer.render(source: img, edit: edit)
        #expect(out.width == 200 && out.height == 400)
        #expect(Self.pixel(out, x: 190, y: 10) == .red)   // red went to the top-right
        #expect(Self.pixel(out, x: 10, y: 390) == .blue)   // blue went to the bottom-left
        #expect(Self.pixel(out, x: 100, y: 200) == .white)
    }

    @Test func fineAngleKeepsCornerInsideAndMatchesPreviewMath() throws {
        let img = Self.makeImage()
        let size = CGSize(width: 400, height: 200)
        var edit = EditState.identity(imageSize: size)
        edit.setFineAngle(30, imageSize: size)
        // Crop a small window around where the red square should land in the canvas.
        let poly = Geometry.imagePolygon(imageSize: size, angleDegrees: 30)
        let redCorner = poly[0] // source top-left after rotation
        // Move 30px inward along both source axes (diagonal of the red square) to land inside it.
        let rad = 30 * Double.pi / 180
        let inward = CGPoint(x: redCorner.x + 20 * cos(rad) - 20 * sin(rad), y: redCorner.y + 20 * sin(rad) + 20 * cos(rad))
        edit.crop = CGRect(x: inward.x - 10, y: inward.y - 10, width: 20, height: 20)
        #expect(Geometry.isValid(rect: edit.crop, polygon: poly))
        let out = try Renderer.render(source: img, edit: edit)
        #expect(Self.pixel(out, x: 10, y: 10) == .red)
        // Far from the red square the image must be white (proves rotation direction and placement).
        var centre = EditState.identity(imageSize: size)
        centre.setFineAngle(30, imageSize: size)
        let out2 = try Renderer.render(source: img, edit: centre)
        #expect(Self.pixel(out2, x: out2.width / 2, y: out2.height / 2) == .white)
    }

    @Test func mirrorSwapsSides() throws {
        let img = Self.makeImage()
        var edit = EditState.identity(imageSize: CGSize(width: 400, height: 200))
        edit.mirrored = true
        let out = try Renderer.render(source: img, edit: edit)
        #expect(out.width == 400 && out.height == 200)
        #expect(Self.pixel(out, x: 390, y: 10) == .red)
        #expect(Self.pixel(out, x: 10, y: 190) == .blue)
        #expect(Self.pixel(out, x: 10, y: 10) == .white)
    }

    @Test func nominalSizeScalesCrop() throws {
        let img = Self.makeImage()
        var edit = EditState.identity(imageSize: CGSize(width: 800, height: 400))
        edit.crop = CGRect(x: 0, y: 0, width: 80, height: 80)
        let out = try Renderer.render(source: img, edit: edit, nominalSize: CGSize(width: 800, height: 400))
        #expect(out.width == 40 && out.height == 40)
        #expect(Self.pixel(out, x: 20, y: 20) == .red)
    }

    @Test func encodeKeepsMetadataAndResetsOrientation() throws {
        let img = Self.makeImage()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("photo21-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("in.jpg")

        // Write a JPEG with orientation 6 and some EXIF/GPS.
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "hello", kCGImagePropertyExifDateTimeOriginal: "2024:01:02 03:04:05"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.2, kCGImagePropertyGPSLatitudeRef: "N"],
        ]
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))

        let info = try ImageLoader.info(for: url)
        #expect(info.pixelSize == CGSize(width: 200, height: 400)) // orientation 6 swaps
        let full = try ImageLoader.decodeFull(url: url)
        #expect(full.width == 200 && full.height == 400)

        var edit = EditState.identity(imageSize: info.pixelSize)
        edit.crop = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rendered = try Renderer.render(source: full, edit: edit, nominalSize: info.pixelSize)
        let encoded = try ImageWriter.encode(rendered, sourceURL: url)
        #expect(encoded.type == .jpeg && encoded.keepsSourceFormat)

        let outURL = try ImageWriter.saveCopy(encoded, originalURL: url)
        #expect(outURL.lastPathComponent == "in-1.jpg")
        let src = CGImageSourceCreateWithURL(outURL as CFURL, nil)!
        let outProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        #expect((outProps[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(outProps[kCGImagePropertyPixelWidth] as? Int == 100)
        let exif = outProps[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2024:01:02 03:04:05")
        let gps = outProps[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        #expect(gps?[kCGImagePropertyGPSLatitude] != nil)
    }
}
