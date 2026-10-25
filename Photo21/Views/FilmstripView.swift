import SwiftUI

/// Thumbnails of the whole queue with status badges.
struct FilmstripView: View {
    @Environment(PhotoQueue.self) private var queue

    private let thumbSize: CGFloat = 56

    var body: some View {
        HStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                            thumb(for: item, selected: index == queue.currentIndex && !queue.finished)
                                .id(item.id)
                                .onTapGesture { queue.select(index) }
                                .onAppear { item.ensureLoaded(defaultAspect: queue.stickyAspect) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: queue.currentIndex, initial: true) { _, index in
                    if let index, queue.items.indices.contains(index) {
                        withAnimation { proxy.scrollTo(queue.items[index].id, anchor: .center) }
                    }
                }
            }
            counter
                .padding(.trailing, 12)
        }
        .frame(height: thumbSize + 16)
        .background(Theme.filmstrip)
    }

    private var counter: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let i = queue.currentIndex {
                Text(queue.finished ? "Done" : "\(i + 1) of \(queue.items.count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.label)
            }
            if queue.pendingSaves > 0 {
                Text("Saving \(queue.pendingSaves)…").font(.caption).foregroundStyle(Theme.secondaryLabel)
            } else {
                Text("\(queue.savedCount) saved").font(.caption).foregroundStyle(Theme.secondaryLabel)
            }
        }
        .frame(minWidth: 70, alignment: .trailing)
    }

    @ViewBuilder
    private func thumb(for item: PhotoItem, selected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Theme.control)
            if let thumbnail = item.thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
            } else if item.loadError != nil {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .overlay(alignment: .bottomTrailing) { badge(for: item.status).padding(3) }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(selected ? Color.white : Color.clear, lineWidth: 2)
        }
        .help(item.fileName + (statusText(item.status).map { " — \($0)" } ?? ""))
    }

    @ViewBuilder
    private func badge(for status: PhotoItem.Status) -> some View {
        switch status {
        case .pending:
            EmptyView()
        case .saving:
            ProgressView().controlSize(.mini)
        case .saved:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green)
        case .skipped:
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.white, .gray)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .red)
        }
    }

    private func statusText(_ status: PhotoItem.Status) -> String? {
        switch status {
        case .pending: nil
        case .saving: "saving…"
        case .saved(let url): "saved to \(url.lastPathComponent)"
        case .skipped: "skipped"
        case .failed(let message): "failed: \(message)"
        }
    }
}
