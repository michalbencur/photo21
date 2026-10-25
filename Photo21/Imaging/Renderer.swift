import CoreGraphics
import Foundation

enum RenderError: Error, LocalizedError {
    case contextFailed
    case emptyCrop

    var errorDescription: String? {
        switch self {
        case .contextFailed: "Couldn't create a drawing context."
        case .emptyCrop: "The crop area is empty."
        }
    }
}

/// Single-pass rotate + crop with Core Graphics, in the source's colour space.
enum Renderer {
    /// `edit.crop` is expected in canvas pixels of an image of `source`'s size.
    /// If the edit was made against a different nominal size, pass it as `nominalSize`
    /// and the crop is scaled accordingly.
    static func render(source: CGImage, edit: EditState, nominalSize: CGSize? = nil) throws -> CGImage {
        let w = CGFloat(source.width), h = CGFloat(source.height)
        var crop = edit.crop
        if let n = nominalSize, n.width > 0, n.height > 0, n.width != w || n.height != h {
            let sx = w / n.width, sy = h / n.height
            crop = CGRect(x: crop.minX * sx, y: crop.minY * sy, width: crop.width * sx, height: crop.height * sy)
        }
        let rect = CGRect(x: crop.minX.rounded(), y: crop.minY.rounded(),
                          width: crop.width.rounded(), height: crop.height.rounded())
        guard rect.width >= 1, rect.height >= 1 else { throw RenderError.emptyCrop }

        if edit.fineAngle == 0 && edit.quarterTurns == 0 && !edit.mirrored {
            // Pixel-exact fast path.
            let clipped = rect.intersection(CGRect(x: 0, y: 0, width: w, height: h))
            guard let out = source.cropping(to: clipped) else { throw RenderError.contextFailed }
            return out
        }

        let outW = Int(rect.width), outH = Int(rect.height)
        let hasAlpha = Renderer.hasAlpha(source)
        let colorSpace = source.colorSpace.flatMap { $0.model == .rgb || $0.model == .monochrome ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let gray = colorSpace.model == .monochrome
        let bitmapInfo: UInt32 = gray
            ? (hasAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.none.rawValue)
            : (hasAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw RenderError.contextFailed
        }
        ctx.interpolationQuality = edit.fineAngle == 0 ? .none : .high
        ctx.setAllowsAntialiasing(true)

        let canvas = Geometry.canvasSize(imageSize: CGSize(width: w, height: h), angleDegrees: edit.angleDegrees)
        // Flip to y-down so the model's coordinates apply directly.
        ctx.translateBy(x: 0, y: CGFloat(outH))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
        ctx.rotate(by: edit.angleDegrees * .pi / 180)
        ctx.translateBy(x: -w / 2, y: -h / 2)
        if edit.mirrored {
            ctx.translateBy(x: w, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        // CGContext.draw expects a y-up image; flip locally.
        ctx.translateBy(x: 0, y: h)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let out = ctx.makeImage() else { throw RenderError.contextFailed }
        return out
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
}
