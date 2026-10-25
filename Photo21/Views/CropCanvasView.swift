import SwiftUI

/// Shows the rotated preview with the crop frame on top. The crop frame is a pure view-space
/// transform of `edit.crop`, so dragging never re-renders the image.
struct CropCanvasView: View {
    @Environment(PhotoQueue.self) private var queue
    let item: PhotoItem

    enum Handle: CaseIterable {
        case move, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private struct DragSession {
        let handle: Handle
        let startCrop: CGRect
    }

    @State private var drag: DragSession?
    @FocusState private var focused: Bool

    private let inset: CGFloat = 40
    private let handleHitRadius: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            if let preview = item.preview, let size = item.imageSize, let edit = item.edit {
                let canvas = edit.canvasSize(imageSize: size)
                let scale = min((geo.size.width - 2 * inset) / canvas.width, (geo.size.height - 2 * inset) / canvas.height)
                let origin = CGPoint(x: (geo.size.width - canvas.width * scale) / 2,
                                     y: (geo.size.height - canvas.height * scale) / 2)
                let cropInView = CGRect(x: origin.x + edit.crop.minX * scale, y: origin.y + edit.crop.minY * scale,
                                        width: edit.crop.width * scale, height: edit.crop.height * scale)
                ZStack {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .scaleEffect(x: edit.mirrored ? -1 : 1, y: 1)
                        .rotationEffect(.degrees(edit.angleDegrees))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    CropOverlay(crop: cropInView, bounds: geo.size, dragging: drag != nil)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(scale: scale, origin: origin, cropInView: cropInView, imageSize: size))
            } else if let error = item.loadError {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            let step = press.modifiers.contains(.shift) ? 1.0 : 0.1
            queue.nudgeAngle(by: press.key == .leftArrow ? -step : step)
            return .handled
        }
        .onAppear { focused = true }
        .onChange(of: item.id) { focused = true }
    }

    private func dragGesture(scale: CGFloat, origin: CGPoint, cropInView: CGRect, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    focused = true
                    guard let edit = item.edit,
                          let handle = Self.hitTest(point: value.startLocation, crop: cropInView, radius: handleHitRadius) else {
                        return
                    }
                    drag = DragSession(handle: handle, startCrop: edit.crop)
                }
                guard let session = drag, var edit = item.edit else { return }
                let delta = CGSize(width: value.translation.width / scale, height: value.translation.height / scale)
                let ratio = edit.effectiveRatio(imageSize: imageSize)
                let candidate = Self.apply(handle: session.handle, to: session.startCrop, delta: delta, ratio: ratio)
                let polygon = Geometry.imagePolygon(imageSize: imageSize, angleDegrees: edit.angleDegrees)
                edit.crop = Geometry.clamp(candidate: candidate, from: session.startCrop, polygon: polygon)
                item.edit = edit
            }
            .onEnded { _ in drag = nil }
    }

    static func hitTest(point p: CGPoint, crop: CGRect, radius: CGFloat) -> Handle? {
        let candidates: [(Handle, CGPoint)] = [
            (.topLeft, CGPoint(x: crop.minX, y: crop.minY)),
            (.topRight, CGPoint(x: crop.maxX, y: crop.minY)),
            (.bottomRight, CGPoint(x: crop.maxX, y: crop.maxY)),
            (.bottomLeft, CGPoint(x: crop.minX, y: crop.maxY)),
            (.top, CGPoint(x: crop.midX, y: crop.minY)),
            (.right, CGPoint(x: crop.maxX, y: crop.midY)),
            (.bottom, CGPoint(x: crop.midX, y: crop.maxY)),
            (.left, CGPoint(x: crop.minX, y: crop.midY)),
        ]
        for (handle, center) in candidates where hypot(p.x - center.x, p.y - center.y) <= radius {
            return handle
        }
        // Edges anywhere along their length.
        let near: (CGFloat, CGFloat) -> Bool = { abs($0 - $1) <= radius }
        let insideX = p.x >= crop.minX - radius && p.x <= crop.maxX + radius
        let insideY = p.y >= crop.minY - radius && p.y <= crop.maxY + radius
        if insideX && near(p.y, crop.minY) { return .top }
        if insideX && near(p.y, crop.maxY) { return .bottom }
        if insideY && near(p.x, crop.minX) { return .left }
        if insideY && near(p.x, crop.maxX) { return .right }
        if crop.contains(p) { return .move }
        return nil
    }

    /// Geometry of a handle drag, before polygon clamping.
    static func apply(handle: Handle, to start: CGRect, delta: CGSize, ratio: Double?) -> CGRect {
        let minSize = EditState.minCropSize
        switch handle {
        case .move:
            return start.offsetBy(dx: delta.width, dy: delta.height)

        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            let sx: CGFloat = (handle == .topRight || handle == .bottomRight) ? 1 : -1
            let sy: CGFloat = (handle == .bottomLeft || handle == .bottomRight) ? 1 : -1
            let anchor = CGPoint(x: sx > 0 ? start.minX : start.maxX, y: sy > 0 ? start.minY : start.maxY)
            let moving = CGPoint(x: (sx > 0 ? start.maxX : start.minX) + delta.width,
                                 y: (sy > 0 ? start.maxY : start.minY) + delta.height)
            var w = max((moving.x - anchor.x) * sx, minSize)
            var h = max((moving.y - anchor.y) * sy, minSize)
            if let ratio {
                w = max(w, h * ratio)
                h = w / ratio
                if h < minSize { h = minSize; w = h * ratio }
            }
            return CGRect(x: sx > 0 ? anchor.x : anchor.x - w, y: sy > 0 ? anchor.y : anchor.y - h, width: w, height: h)

        case .left, .right:
            let sx: CGFloat = handle == .right ? 1 : -1
            var w = max(start.width + delta.width * sx, minSize)
            var h = start.height
            if let ratio {
                h = w / ratio
                if h < minSize { h = minSize; w = h * ratio }
            }
            let x = sx > 0 ? start.minX : start.maxX - w
            return CGRect(x: x, y: start.midY - h / 2, width: w, height: h)

        case .top, .bottom:
            let sy: CGFloat = handle == .bottom ? 1 : -1
            var h = max(start.height + delta.height * sy, minSize)
            var w = start.width
            if let ratio {
                w = h * ratio
                if w < minSize { w = minSize; h = w / ratio }
            }
            let y = sy > 0 ? start.minY : start.maxY - h
            return CGRect(x: start.midX - w / 2, y: y, width: w, height: h)
        }
    }
}

/// Photos-style frame: dimmed surround, thin border, thick corner brackets, edge ticks,
/// thirds grid only while dragging.
private struct CropOverlay: View {
    let crop: CGRect
    let bounds: CGSize
    let dragging: Bool

    private let bracketLength: CGFloat = 20
    private let bracketWidth: CGFloat = 3
    private let tickLength: CGFloat = 16

    var body: some View {
        ZStack {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: bounds))
                p.addRect(crop)
            }
            .fill(Color.black.opacity(dragging ? 0.45 : 0.6), style: FillStyle(eoFill: true))

            if dragging {
                Path { p in
                    for i in 1...2 {
                        let x = crop.minX + crop.width * CGFloat(i) / 3
                        let y = crop.minY + crop.height * CGFloat(i) / 3
                        p.move(to: CGPoint(x: x, y: crop.minY)); p.addLine(to: CGPoint(x: x, y: crop.maxY))
                        p.move(to: CGPoint(x: crop.minX, y: y)); p.addLine(to: CGPoint(x: crop.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
            }

            Rectangle()
                .path(in: crop)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)

            brackets
                .stroke(Color.white, style: StrokeStyle(lineWidth: bracketWidth, lineCap: .square))
                .shadow(color: .black.opacity(0.4), radius: 1)
        }
        .allowsHitTesting(false)
    }

    private var brackets: Path {
        var p = Path()
        let o = bracketWidth / 2 // sit just outside the thin border
        let l = min(bracketLength, crop.width / 3, crop.height / 3)
        let t = min(tickLength, crop.width / 4, crop.height / 4)
        let r = crop.insetBy(dx: -o, dy: -o)
        // Corners
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        // Edge midpoint ticks
        p.move(to: CGPoint(x: r.midX - t / 2, y: r.minY)); p.addLine(to: CGPoint(x: r.midX + t / 2, y: r.minY))
        p.move(to: CGPoint(x: r.midX - t / 2, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX + t / 2, y: r.maxY))
        p.move(to: CGPoint(x: r.minX, y: r.midY - t / 2)); p.addLine(to: CGPoint(x: r.minX, y: r.midY + t / 2))
        p.move(to: CGPoint(x: r.maxX, y: r.midY - t / 2)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY + t / 2))
        return p
    }
}
