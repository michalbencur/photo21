import Foundation

/// Pure geometry for the rotate-then-crop model. All coordinates are y-down canvas pixels.
enum Geometry {
    static let tolerance: CGFloat = 0.01

    static func canvasSize(imageSize: CGSize, angleDegrees: Double) -> CGSize {
        let r = angleDegrees * .pi / 180
        let c = abs(cos(r)), s = abs(sin(r))
        return CGSize(width: imageSize.width * c + imageSize.height * s,
                      height: imageSize.width * s + imageSize.height * c)
    }

    /// Corners of the rotated image inside its canvas, in order (TL, TR, BR, BL of the source).
    static func imagePolygon(imageSize: CGSize, angleDegrees: Double) -> [CGPoint] {
        let canvas = canvasSize(imageSize: imageSize, angleDegrees: angleDegrees)
        let r = angleDegrees * .pi / 180
        let c = cos(r), s = sin(r)
        let hw = imageSize.width / 2, hh = imageSize.height / 2
        let cx = canvas.width / 2, cy = canvas.height / 2
        return [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)].map { (x, y) in
            // Positive angle rotates clockwise on screen (y-down), matching SwiftUI's rotationEffect.
            CGPoint(x: cx + x * c - y * s, y: cy + x * s + y * c)
        }
    }

    /// Point-in-convex-polygon using consistent cross-product signs.
    static func contains(polygon: [CGPoint], point p: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var sign = 0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if abs(cross) <= tolerance * hypot(b.x - a.x, b.y - a.y) { continue }
            let s = cross > 0 ? 1 : -1
            if sign == 0 { sign = s } else if s != sign { return false }
        }
        return true
    }

    static func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    static func isValid(rect: CGRect, polygon: [CGPoint]) -> Bool {
        rect.width >= EditState.minCropSize - tolerance
            && rect.height >= EditState.minCropSize - tolerance
            && corners(rect).allSatisfy { contains(polygon: polygon, point: $0) }
    }

    /// Largest rect with the given width/height ratio centred at `center` that fits in the polygon.
    static func largestRect(ratio: Double, center: CGPoint, polygon: [CGPoint], canvasSize: CGSize) -> CGRect {
        func rect(height: CGFloat) -> CGRect {
            let w = height * ratio
            return CGRect(x: center.x - w / 2, y: center.y - height / 2, width: w, height: height)
        }
        var lo: CGFloat = 0
        var hi = min(canvasSize.height, canvasSize.width / ratio)
        if corners(rect(height: hi)).allSatisfy({ contains(polygon: polygon, point: $0) }) {
            return rect(height: hi)
        }
        for _ in 0..<48 {
            let mid = (lo + hi) / 2
            if corners(rect(height: mid)).allSatisfy({ contains(polygon: polygon, point: $0) }) {
                lo = mid
            } else {
                hi = mid
            }
        }
        return rect(height: lo)
    }

    /// Returns `candidate` if valid, otherwise the furthest valid rect on the straight path
    /// from `from` (assumed valid) towards `candidate`.
    static func clamp(candidate: CGRect, from: CGRect, polygon: [CGPoint]) -> CGRect {
        if isValid(rect: candidate, polygon: polygon) { return candidate }
        func lerp(_ t: CGFloat) -> CGRect {
            CGRect(x: from.minX + (candidate.minX - from.minX) * t,
                   y: from.minY + (candidate.minY - from.minY) * t,
                   width: from.width + (candidate.width - from.width) * t,
                   height: from.height + (candidate.height - from.height) * t)
        }
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if isValid(rect: lerp(mid), polygon: polygon) { lo = mid } else { hi = mid }
        }
        return lerp(lo)
    }

    static func approximatelyEqual(_ a: CGRect, _ b: CGRect, epsilon: CGFloat = 0.5) -> Bool {
        abs(a.minX - b.minX) < epsilon && abs(a.minY - b.minY) < epsilon
            && abs(a.width - b.width) < epsilon && abs(a.height - b.height) < epsilon
    }
}
