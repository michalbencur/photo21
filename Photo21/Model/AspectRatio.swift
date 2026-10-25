import Foundation

/// A preset crop aspect ratio. The list is intentionally hard-coded.
/// Portrait/landscape orientation is handled separately (see `EditState.flipOrientation`),
/// so each ratio is listed once.
struct AspectRatio: Hashable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case free
        case original
        case fixed(Double, Double)
    }

    let name: String
    let kind: Kind
    var id: String { name }

    static let all: [AspectRatio] = [
        AspectRatio(name: "Original", kind: .original),
        AspectRatio(name: "Freeform", kind: .free),
        AspectRatio(name: "Square", kind: .fixed(1, 1)),
        AspectRatio(name: "16:9", kind: .fixed(16, 9)),
        AspectRatio(name: "4:5", kind: .fixed(4, 5)),
        AspectRatio(name: "5:7", kind: .fixed(5, 7)),
        AspectRatio(name: "4:3", kind: .fixed(4, 3)),
        AspectRatio(name: "3:5", kind: .fixed(3, 5)),
        AspectRatio(name: "3:2", kind: .fixed(3, 2)),
    ]

    static let free = all[1]

    static func named(_ name: String) -> AspectRatio? {
        all.first { $0.name == name }
    }

    /// Width/height ratio for the given image (after quarter turns) and orientation.
    /// Returns nil for the free ratio.
    func ratio(imageSize: CGSize, portrait: Bool) -> Double? {
        let base: Double
        switch kind {
        case .free:
            return nil
        case .original:
            guard imageSize.width > 0, imageSize.height > 0 else { return nil }
            base = imageSize.width / imageSize.height
        case .fixed(let w, let h):
            base = w / h
        }
        let landscape = max(base, 1 / base)
        return portrait ? 1 / landscape : landscape
    }
}
