import SwiftUI

struct ContentView: View {
    @Environment(PhotoQueue.self) private var queue

    var body: some View {
        @Bindable var queue = queue
        Group {
            if queue.items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Group {
                            if queue.finished {
                                doneState
                            } else if let item = queue.current {
                                CropCanvasView(item: item)
                                    .id(item.id)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.canvas)
                        if let item = queue.current, !queue.finished {
                            Rectangle().fill(Theme.separator).frame(width: 1)
                            ControlsView(item: item)
                        }
                    }
                    Rectangle().fill(Theme.separator).frame(height: 1)
                    FilmstripView()
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.canvas)
        .preferredColorScheme(.dark)
        .dropDestination(for: URL.self) { urls, _ in
            queue.add(urls: urls)
            return true
        }
        .navigationTitle(queue.current.map(\.fileName) ?? "Photo21")
        .navigationSubtitle(queue.currentIndex.map { "\($0 + 1) of \(queue.items.count)" } ?? "")
        .alert("Save failed", isPresented: Binding(get: { queue.lastError != nil }, set: { if !$0 { queue.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(queue.lastError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "crop.rotate").font(.system(size: 56, weight: .light)).foregroundStyle(Theme.secondaryLabel)
            Text("Drop photos or folders here").font(.title2).foregroundStyle(Theme.label)
            Text("or drop them on the Dock icon").foregroundStyle(Theme.secondaryLabel)
            Button("Open…") { queue.openPanel() }
                .keyboardShortcut("o")
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(Theme.separator)
                .padding(24)
        }
    }

    private var doneState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 56)).foregroundStyle(.green)
            Text("All done").font(.title2).foregroundStyle(Theme.label)
            Text("\(queue.savedCount) of \(queue.items.count) photos saved").foregroundStyle(Theme.secondaryLabel)
            if queue.pendingSaves > 0 {
                ProgressView("Finishing \(queue.pendingSaves) save(s)…").padding(.top, 8)
            }
            HStack {
                Button("Back") { queue.previous() }.keyboardShortcut(.leftArrow)
                Button("Open more…") { queue.openPanel() }.buttonStyle(.borderedProminent)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 8)
        }
    }
}
