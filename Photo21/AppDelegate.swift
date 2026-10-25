import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        PhotoQueue.shared.add(urls: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard PhotoQueue.shared.pendingSaves > 0 else { return .terminateNow }
        Task { @MainActor in
            while PhotoQueue.shared.pendingSaves > 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
