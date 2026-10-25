import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class PhotoItem: Identifiable {
    enum Status: Equatable {
        case pending
        case saving
        case saved(URL)
        case skipped
        case failed(String)
    }

    let id = UUID()
    private(set) var url: URL
    private(set) var imageSize: CGSize?
    private(set) var preview: CGImage?
    private(set) var thumbnail: CGImage?
    private(set) var loadError: String?
    var edit: EditState?
    var status: Status = .pending

    private var loadTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    var fileName: String { url.lastPathComponent }
    var isLoaded: Bool { preview != nil && edit != nil }

    /// Loads size, preview and thumbnail off the main actor. Safe to call repeatedly.
    func ensureLoaded(defaultAspect: AspectRatio) {
        guard loadTask == nil, preview == nil, loadError == nil else { return }
        let url = url
        loadTask = Task { [weak self] in
            let result: Result<(ImageInfo, CGImage, CGImage), Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let info = try ImageLoader.info(for: url)
                    let preview = try ImageLoader.decode(url: url, maxPixels: ImageLoader.previewMaxPixels)
                    let thumb = try ImageLoader.decode(url: url, maxPixels: ImageLoader.thumbnailMaxPixels)
                    return .success((info, preview, thumb))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let (info, preview, thumb)):
                self.imageSize = info.pixelSize
                self.preview = preview
                self.thumbnail = thumb
                var edit = EditState.identity(imageSize: info.pixelSize)
                edit.aspect = defaultAspect
                edit.refitCrop(imageSize: info.pixelSize, keepCenter: false)
                self.edit = edit
            case .failure(let error):
                self.loadError = error.localizedDescription
            }
            self.loadTask = nil
        }
    }

    /// Called after the file on disk was replaced: forget decoded data and edits.
    func reload(defaultAspect: AspectRatio) {
        loadTask?.cancel()
        loadTask = nil
        preview = nil
        thumbnail = nil
        imageSize = nil
        edit = nil
        loadError = nil
        ensureLoaded(defaultAspect: defaultAspect)
    }
}
