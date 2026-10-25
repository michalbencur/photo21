import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Photo21

@MainActor
struct QueueTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("photo21-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeJPEG(to url: URL, orientation: Int) {
        let img = RendererTests.makeImage()
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, [kCGImagePropertyOrientation: orientation,
                                               kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "keep me"]] as CFDictionary)
        precondition(CGImageDestinationFinalize(dest))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(10)) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func rotateAndSaveInPlaceReplacesFileAndTrashesOriginal() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.jpg"), b = dir.appendingPathComponent("b.jpg")
        writeJPEG(to: a, orientation: 1)
        writeJPEG(to: b, orientation: 1)
        let oldCreation = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.creationDate: oldCreation], ofItemAtPath: a.path)

        let queue = PhotoQueue(defaults: UserDefaults(suiteName: "photo21-tests-\(UUID().uuidString)")!)
        queue.add(urls: [dir]) // folder expansion
        await waitUntil { queue.items.count == 2 && queue.current?.isLoaded == true }
        #expect(queue.items.map(\.fileName) == ["a.jpg", "b.jpg"])
        #expect(queue.current?.imageSize == CGSize(width: 400, height: 200))

        queue.rotate(quarterTurns: 1)
        #expect(queue.current?.edit?.outputSize == CGSize(width: 200, height: 400))
        queue.saveCurrentAndAdvance()
        #expect(queue.currentIndex == 1) // advanced immediately
        await waitUntil { queue.pendingSaves == 0 }

        if case .saved(let url) = queue.items[0].status { #expect(url == a) } else { Issue.record("not saved: \(queue.items[0].status)") }
        let info = try ImageLoader.info(for: a)
        #expect(info.pixelSize == CGSize(width: 200, height: 400))
        let attrs = try FileManager.default.attributesOfItem(atPath: a.path)
        #expect(attrs[.creationDate] as? Date == oldCreation)
        let src = CGImageSourceCreateWithURL(a as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        #expect((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] as? String == "keep me")
        // The original went to the Trash (a file called a.jpg or a-copy variant newer than our start).
        let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first!
        let trashed = (try? FileManager.default.contentsOfDirectory(atPath: trash.path))?.filter { $0.hasPrefix("a") && $0.hasSuffix(".jpg") } ?? []
        #expect(!trashed.isEmpty)

        // Second photo untouched + Save = skip, then finished.
        queue.saveCurrentAndAdvance()
        #expect(queue.items[1].status == .skipped)
        #expect(queue.finished)
        #expect(try ImageLoader.info(for: b).pixelSize == CGSize(width: 400, height: 200))
        queue.previous()
        #expect(!queue.finished && queue.currentIndex == 1)
    }

    @Test func saveCopyLeavesOriginal() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("c.jpg")
        writeJPEG(to: a, orientation: 6)
        let queue = PhotoQueue(defaults: UserDefaults(suiteName: "photo21-tests-\(UUID().uuidString)")!)
        queue.add(urls: [a])
        await waitUntil { queue.current?.isLoaded == true }
        #expect(queue.current?.imageSize == CGSize(width: 200, height: 400)) // orientation applied
        queue.setAspect(AspectRatio.named("Square")!)
        #expect(queue.current?.edit?.outputSize == CGSize(width: 200, height: 200))
        queue.saveCurrentAndAdvance(asCopy: true)
        await waitUntil { queue.pendingSaves == 0 }
        let copy = dir.appendingPathComponent("c-1.jpg")
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(try ImageLoader.info(for: copy).pixelSize == CGSize(width: 200, height: 200))
        #expect(try ImageLoader.info(for: a).pixelSize == CGSize(width: 200, height: 400))
    }
}
