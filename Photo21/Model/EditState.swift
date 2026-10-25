import Foundation

/// Everything the user has done to one photo. Pure value, cheap to snapshot.
///
/// Coordinate model: the source image (orientation already baked in) is rotated by
/// `angleDegrees` about its centre. The axis-aligned bounding box of that rotated image is the
/// *canvas*; `crop` is expressed in canvas pixels (y-down, origin top-left) and must lie entirely
/// inside the rotated image polygon.
struct EditState: Equatable, Sendable {
    static let maxFineAngle: Double = 45
    static let minCropSize: CGFloat = 16

    var quarterTurns: Int = 0
    var fineAngle: Double = 0
    var aspect: AspectRatio = .free
    var flipOrientation = false
    /// Horizontal mirror of the source, applied before rotation.
    var mirrored = false
    var crop: CGRect

    var angleDegrees: Double { Double(quarterTurns) * 90 + fineAngle }

    /// Full-image default: no rotation, crop covering the whole image.
    static func identity(imageSize: CGSize) -> EditState {
        EditState(crop: CGRect(origin: .zero, size: imageSize))
    }

    func isIdentity(imageSize: CGSize) -> Bool {
        quarterTurns == 0 && fineAngle == 0 && !mirrored && Geometry.approximatelyEqual(crop, CGRect(origin: .zero, size: imageSize))
    }

    /// Size of the image after quarter turns only (fine angle ignored).
    func turnedSize(imageSize: CGSize) -> CGSize {
        quarterTurns % 2 == 0 ? imageSize : CGSize(width: imageSize.height, height: imageSize.width)
    }

    /// Whether the crop should be portrait: follows the turned image, XOR the user's flip.
    func isPortrait(imageSize: CGSize) -> Bool {
        let turned = turnedSize(imageSize: imageSize)
        return (turned.height > turned.width) != flipOrientation
    }

    /// Effective width/height ratio of the crop, nil when free.
    func effectiveRatio(imageSize: CGSize) -> Double? {
        aspect.ratio(imageSize: turnedSize(imageSize: imageSize), portrait: isPortrait(imageSize: imageSize))
    }

    /// Ratio used when fitting the crop: the effective one, or the turned image's own when free.
    func fittingRatio(imageSize: CGSize) -> Double {
        if let r = effectiveRatio(imageSize: imageSize) { return r }
        let t = turnedSize(imageSize: imageSize)
        return t.width / t.height
    }

    func canvasSize(imageSize: CGSize) -> CGSize {
        Geometry.canvasSize(imageSize: imageSize, angleDegrees: angleDegrees)
    }

    /// Integral output size in pixels.
    var outputSize: CGSize {
        CGSize(width: crop.width.rounded(), height: crop.height.rounded())
    }

    // MARK: - Mutations that keep the crop valid

    /// Re-fit the crop: keep its centre (relative to the canvas centre) and the current
    /// fitting ratio, scale to the largest rect inside the rotated image.
    mutating func refitCrop(imageSize: CGSize, keepCenter: Bool) {
        let polygon = Geometry.imagePolygon(imageSize: imageSize, angleDegrees: angleDegrees)
        let canvas = Geometry.canvasSize(imageSize: imageSize, angleDegrees: angleDegrees)
        let canvasCenter = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let center = keepCenter ? CGPoint(x: crop.midX, y: crop.midY) : canvasCenter
        var fitted = Geometry.largestRect(ratio: fittingRatio(imageSize: imageSize), center: center, polygon: polygon, canvasSize: canvas)
        if fitted.width < EditState.minCropSize || fitted.height < EditState.minCropSize {
            fitted = Geometry.largestRect(ratio: fittingRatio(imageSize: imageSize), center: canvasCenter, polygon: polygon, canvasSize: canvas)
        }
        crop = fitted
    }

    mutating func setFineAngle(_ angle: Double, imageSize: CGSize) {
        let old = Geometry.canvasSize(imageSize: imageSize, angleDegrees: angleDegrees)
        fineAngle = min(max(angle, -EditState.maxFineAngle), EditState.maxFineAngle)
        let new = Geometry.canvasSize(imageSize: imageSize, angleDegrees: angleDegrees)
        // Keep the crop centre at the same position relative to the canvas centre.
        crop.origin.x += (new.width - old.width) / 2
        crop.origin.y += (new.height - old.height) / 2
        refitCropIfNeeded(imageSize: imageSize)
    }

    mutating func rotate(quarterTurns delta: Int, imageSize: CGSize) {
        let old = Geometry.canvasSize(imageSize: imageSize, angleDegrees: angleDegrees)
        let oldCenter = CGPoint(x: crop.midX - old.width / 2, y: crop.midY - old.height / 2)
        quarterTurns = ((quarterTurns + delta) % 4 + 4) % 4
        let new = Geometry.canvasSize(imageSize: imageSize, angleDegrees: angleDegrees)
        // Rotate the crop with the image: 90° CW maps (x, y) -> (-y, x) around the centre.
        let turns = ((delta % 4) + 4) % 4
        var c = oldCenter
        var size = crop.size
        for _ in 0..<turns {
            c = CGPoint(x: -c.y, y: c.x)
            size = CGSize(width: size.height, height: size.width)
        }
        crop = CGRect(x: c.x + new.width / 2 - size.width / 2, y: c.y + new.height / 2 - size.height / 2, width: size.width, height: size.height)
        refitCropIfNeeded(imageSize: imageSize)
    }

    mutating func setAspect(_ newAspect: AspectRatio, imageSize: CGSize) {
        aspect = newAspect
        refitCrop(imageSize: imageSize, keepCenter: true)
    }

    mutating func toggleOrientation(imageSize: CGSize) {
        flipOrientation.toggle()
        if aspect.kind == .free {
            // Free ratio: swap the crop's sides around its centre.
            let c = CGPoint(x: crop.midX, y: crop.midY)
            crop = CGRect(x: c.x - crop.height / 2, y: c.y - crop.width / 2, width: crop.height, height: crop.width)
            refitCropIfNeeded(imageSize: imageSize)
        } else {
            refitCrop(imageSize: imageSize, keepCenter: true)
        }
    }

    mutating func reset(imageSize: CGSize) {
        let keepAspect = aspect
        self = .identity(imageSize: imageSize)
        aspect = keepAspect
        refitCrop(imageSize: imageSize, keepCenter: false)
    }

    private mutating func refitCropIfNeeded(imageSize: CGSize) {
        let polygon = Geometry.imagePolygon(imageSize: imageSize, angleDegrees: angleDegrees)
        if !Geometry.isValid(rect: crop, polygon: polygon) {
            refitCrop(imageSize: imageSize, keepCenter: true)
        }
    }
}
