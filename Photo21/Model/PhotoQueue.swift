import AppKit
import Foundation
import Observation

/// The list of photos to go through, the current position, and all user actions.
@MainActor
@Observable
final class PhotoQueue {
    static let shared = PhotoQueue()

    private static let aspectDefaultsKey = "stickyAspect"

    private(set) var items: [PhotoItem] = []
    private(set) var currentIndex: Int?
    /// True after advancing past the last photo.
    private(set) var finished = false
    private(set) var pendingSaves = 0
    var lastError: String?

    private let defaults: UserDefaults

    /// The aspect ratio applied to every newly loaded photo. Persisted.
    var stickyAspect: AspectRatio {
        didSet { defaults.set(stickyAspect.name, forKey: Self.aspectDefaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.aspectDefaultsKey)
        stickyAspect = saved.flatMap(AspectRatio.named) ?? .free
    }

    var current: PhotoItem? {
        guard let i = currentIndex, items.indices.contains(i) else { return nil }
        return items[i]
    }

    var savedCount: Int {
        items.filter { if case .saved = $0.status { true } else { false } }.count
    }

    // MARK: - Intake

    func add(urls: [URL]) {
        Task {
            let collected = await Task.detached { ImageLoader.collectImageURLs(from: urls) }.value
            let existing = Set(items.map(\.url.path))
            let fresh = collected.filter { !existing.contains($0.path) }.map(PhotoItem.init(url:))
            guard !fresh.isEmpty else { return }
            let wasEmpty = items.isEmpty || finished
            items.append(contentsOf: fresh)
            if wasEmpty {
                finished = false
                select(items.count - fresh.count)
            } else {
                preload()
            }
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .folder]
        panel.message = "Choose photos or folders to edit"
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    // MARK: - Navigation

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        finished = false
        preload()
    }

    func next() {
        guard let i = currentIndex else { return }
        if i + 1 < items.count {
            select(i + 1)
        } else {
            finished = true
        }
    }

    func previous() {
        guard let i = currentIndex else { return }
        if finished {
            finished = false
        } else if i > 0 {
            select(i - 1)
        }
    }

    private func preload() {
        guard let i = currentIndex else { return }
        items[i].ensureLoaded(defaultAspect: stickyAspect)
        if i + 1 < items.count { items[i + 1].ensureLoaded(defaultAspect: stickyAspect) }
        // Thumbnails for the filmstrip load lazily via ensureLoaded as well; keep it to neighbours.
        if i > 0 { items[i - 1].ensureLoaded(defaultAspect: stickyAspect) }
    }

    // MARK: - Editing the current photo

    private func mutate(_ body: (inout EditState, CGSize) -> Void) {
        guard let item = current, var edit = item.edit, let size = item.imageSize else { return }
        body(&edit, size)
        item.edit = edit
    }

    func setAspect(_ aspect: AspectRatio) {
        stickyAspect = aspect
        mutate { $0.setAspect(aspect, imageSize: $1) }
    }

    func toggleOrientation() {
        mutate { $0.toggleOrientation(imageSize: $1) }
    }

    func toggleMirror() {
        mutate { edit, _ in edit.mirrored.toggle() }
    }

    func rotate(quarterTurns: Int) {
        mutate { $0.rotate(quarterTurns: quarterTurns, imageSize: $1) }
    }

    func setFineAngle(_ angle: Double) {
        mutate { $0.setFineAngle(angle, imageSize: $1) }
    }

    func nudgeAngle(by delta: Double) {
        mutate { $0.setFineAngle($0.fineAngle + delta, imageSize: $1) }
    }

    func resetEdit() {
        mutate { $0.reset(imageSize: $1) }
    }

    // MARK: - Saving

    /// Snapshots the current edit, advances immediately, and writes in the background.
    func saveCurrentAndAdvance(asCopy: Bool = false) {
        guard let item = current, let size = item.imageSize, let edit = item.edit else { return }
        if !asCopy && edit.isIdentity(imageSize: size) {
            if item.status == .pending { item.status = .skipped }
            next()
            return
        }
        item.status = .saving
        pendingSaves += 1
        let url = item.url
        let aspect = stickyAspect
        next()
        Task {
            let result: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let full = try ImageLoader.decodeFull(url: url)
                    let rendered = try Renderer.render(source: full, edit: edit, nominalSize: size)
                    let encoded = try ImageWriter.encode(rendered, sourceURL: url)
                    let written = asCopy
                        ? try ImageWriter.saveCopy(encoded, originalURL: url)
                        : try ImageWriter.saveInPlace(encoded, originalURL: url)
                    return .success(written)
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case .success(let written):
                item.status = .saved(written)
                if written == url {
                    item.reload(defaultAspect: aspect)
                }
            case .failure(let error):
                item.status = .failed(error.localizedDescription)
                lastError = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
            pendingSaves -= 1
        }
    }
}
