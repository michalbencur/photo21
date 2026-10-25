import SwiftUI

@main
struct Photo21App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let queue = PhotoQueue.shared

    var body: some Scene {
        Window("Photo21", id: "main") {
            ContentView()
                .environment(queue)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { queue.openPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save & Next") { queue.saveCurrentAndAdvance() }
                    .keyboardShortcut("s")
                    .disabled(queue.current?.isLoaded != true || queue.finished)
                Button("Save Copy & Next") { queue.saveCurrentAndAdvance(asCopy: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(queue.current?.isLoaded != true || queue.finished)
            }
            CommandMenu("Photo") {
                Button("Previous") { queue.previous() }
                    .keyboardShortcut(.leftArrow)
                    .disabled(queue.current == nil)
                Button("Next (Skip)") { queue.next() }
                    .keyboardShortcut(.rightArrow)
                    .disabled(queue.current == nil || queue.finished)
                Divider()
                Button("Rotate 90° Clockwise") { queue.rotate(quarterTurns: 1) }
                    .keyboardShortcut("r")
                Button("Rotate 90° Counter-clockwise") { queue.rotate(quarterTurns: -1) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Straighten (0°)") { queue.setFineAngle(0) }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
                Divider()
                Button("Swap Orientation") { queue.toggleOrientation() }
                    .keyboardShortcut("/")
                Button("Flip Horizontal") { queue.toggleMirror() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Reset Edits") { queue.resetEdit() }
                    .keyboardShortcut(.delete)
            }
            CommandMenu("Aspect") {
                ForEach(Array(AspectRatio.all.enumerated()), id: \.element.id) { index, aspect in
                    Toggle(aspect.name, isOn: Binding(
                        get: { queue.current?.edit?.aspect == aspect },
                        set: { if $0 { queue.setAspect(aspect) } }
                    ))
                    .keyboardShortcut(KeyEquivalent(Character(String(index))))
                }
            }
        }
    }
}
