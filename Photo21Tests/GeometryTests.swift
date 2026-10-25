import CoreGraphics
import Testing
@testable import Photo21

struct GeometryTests {
    let size = CGSize(width: 600, height: 400)

    @Test func canvasAtZeroEqualsImage() {
        #expect(Geometry.canvasSize(imageSize: size, angleDegrees: 0) == size)
        let turned = Geometry.canvasSize(imageSize: size, angleDegrees: 90)
        #expect(abs(turned.width - 400) < 1e-6 && abs(turned.height - 600) < 1e-6)
    }

    @Test func polygonContainment() {
        let poly = Geometry.imagePolygon(imageSize: size, angleDegrees: 10)
        let canvas = Geometry.canvasSize(imageSize: size, angleDegrees: 10)
        #expect(Geometry.contains(polygon: poly, point: CGPoint(x: canvas.width / 2, y: canvas.height / 2)))
        #expect(!Geometry.contains(polygon: poly, point: .zero))
        #expect(!Geometry.contains(polygon: poly, point: CGPoint(x: canvas.width, y: canvas.height)))
    }

    @Test func fullRectValidAtZero() {
        let poly = Geometry.imagePolygon(imageSize: size, angleDegrees: 0)
        #expect(Geometry.isValid(rect: CGRect(origin: .zero, size: size), polygon: poly))
    }

    @Test func largestRectFitsAndIsTight() {
        for angle in [0.0, 5, 17, 45, 90, 123] {
            let poly = Geometry.imagePolygon(imageSize: size, angleDegrees: angle)
            let canvas = Geometry.canvasSize(imageSize: size, angleDegrees: angle)
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let rect = Geometry.largestRect(ratio: 1.5, center: center, polygon: poly, canvasSize: canvas)
            #expect(Geometry.isValid(rect: rect, polygon: poly), "angle \(angle)")
            #expect(abs(rect.width / rect.height - 1.5) < 1e-6)
            let bigger = rect.insetBy(dx: -2, dy: -2 / 1.5)
            #expect(!Geometry.isValid(rect: bigger, polygon: poly), "angle \(angle) should be tight")
        }
    }

    @Test func clampStopsAtEdge() {
        let poly = Geometry.imagePolygon(imageSize: size, angleDegrees: 0)
        let from = CGRect(x: 100, y: 100, width: 200, height: 100)
        let clamped = Geometry.clamp(candidate: from.offsetBy(dx: 1000, dy: 0), from: from, polygon: poly)
        #expect(abs(clamped.maxX - 600) < 0.1)
        #expect(clamped.minY == 100 && clamped.width == 200)
    }

    @Test func editRotateKeepsCropValid() {
        var edit = EditState.identity(imageSize: size)
        edit.setAspect(AspectRatio.named("16:9")!, imageSize: size)
        edit.setFineAngle(12, imageSize: size)
        let poly = Geometry.imagePolygon(imageSize: size, angleDegrees: 12)
        #expect(Geometry.isValid(rect: edit.crop, polygon: poly))
        edit.rotate(quarterTurns: 1, imageSize: size)
        #expect(edit.angleDegrees == 102)
        let poly2 = Geometry.imagePolygon(imageSize: size, angleDegrees: 102)
        #expect(Geometry.isValid(rect: edit.crop, polygon: poly2))
        #expect(edit.isPortrait(imageSize: size))
        #expect(abs(edit.crop.width / edit.crop.height - 9.0 / 16.0) < 1e-6)
    }

    @Test func handleDragKeepsAspect() {
        let start = CGRect(x: 100, y: 100, width: 300, height: 200)
        let r = CropCanvasView.apply(handle: .bottomRight, to: start, delta: CGSize(width: 60, height: 0), ratio: 1.5)
        #expect(abs(r.width / r.height - 1.5) < 1e-6)
        #expect(r.minX == 100 && r.minY == 100)
        let l = CropCanvasView.apply(handle: .left, to: start, delta: CGSize(width: 30, height: 0), ratio: nil)
        #expect(l.width == 270 && l.maxX == 400 && l.height == 200)
    }
}
