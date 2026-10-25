import SwiftUI

/// Right-hand panel in the style of Photos' Crop tool.
struct ControlsView: View {
    @Environment(PhotoQueue.self) private var queue
    let item: PhotoItem

    private var edit: EditState? { item.edit }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CROP")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.bottom, 14)

            StraightenDial(angle: edit?.fineAngle ?? 0) { queue.setFineAngle($0) }
                .padding(.bottom, 12)

            row(icon: "rotate.left", title: "Rotate") {
                HStack(spacing: 2) {
                    iconButton("rotate.left", help: "Rotate 90° counter-clockwise (⇧⌘R)") { queue.rotate(quarterTurns: -1) }
                    iconButton("rotate.right", help: "Rotate 90° clockwise (⌘R)") { queue.rotate(quarterTurns: 1) }
                }
            }
            row(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: "Flip") {
                Toggle("", isOn: Binding(get: { edit?.mirrored ?? false }, set: { _ in queue.toggleMirror() }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("Flip horizontally (⇧⌘F)")
            }
            row(icon: "aspectratio", title: "Aspect") { EmptyView() }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(AspectRatio.all.enumerated()), id: \.element.id) { index, aspect in
                    AspectRow(name: aspect.name, shortcut: "⌘\(index)", selected: edit?.aspect == aspect) {
                        queue.setAspect(aspect)
                    }
                }
            }
            .padding(.leading, 2)
            .padding(.top, 2)

            Rectangle().fill(Theme.separator).frame(height: 1).padding(.vertical, 12)

            HStack(spacing: 28) {
                Spacer()
                OrientationToggle(portrait: true, selected: isPortrait) { if !isPortrait { queue.toggleOrientation() } }
                OrientationToggle(portrait: false, selected: !isPortrait) { if isPortrait { queue.toggleOrientation() } }
                Spacer()
            }
            .disabled(edit?.aspect.kind == .free)
            .opacity(edit?.aspect.kind == .free ? 0.4 : 1)

            Spacer(minLength: 12)

            if let size = item.imageSize, let edit {
                Text("\(String(Int(size.width))) × \(String(Int(size.height)))  →  \(String(Int(edit.outputSize.width))) × \(String(Int(edit.outputSize.height)))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 12)
            }

            HStack(spacing: 8) {
                Button("Reset") { queue.resetEdit() }
                    .disabled(!item.isLoaded)
                    .help("Discard edits (⌘⌫)")
                Button("Skip") { queue.next() }
                    .help("Next without saving (⌘→)")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            Button {
                queue.saveCurrentAndAdvance()
            } label: {
                Text("Save & Next").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!item.isLoaded)
        }
        .padding(16)
        .frame(width: Theme.sidebarWidth)
        .background(Theme.sidebar)
    }

    private var isPortrait: Bool {
        guard let edit, let size = item.imageSize else { return false }
        return edit.isPortrait(imageSize: size)
    }

    @ViewBuilder
    private func row<Trailing: View>(icon: String, title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryLabel)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.label)
            Spacer()
            trailing()
        }
        .frame(height: 26)
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.label)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 5))
        .help(help)
    }
}

/// One line of the aspect list: checkmark gutter + name, like Photos.
private struct AspectRow: View {
    let name: String
    let shortcut: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.label)
                .frame(width: 14)
                .opacity(selected ? 1 : 0)
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Theme.label : Theme.secondaryLabel)
            Spacer()
            Text(shortcut)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryLabel.opacity(hovering ? 1 : 0))
        }
        .padding(.horizontal, 6)
        .frame(height: 27)
        .background(hovering ? Theme.control : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
    }
}

/// Small portrait / landscape rectangle with a checkmark when selected.
private struct OrientationToggle: View {
    let portrait: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(selected ? Theme.label : Theme.secondaryLabel, lineWidth: 1.5)
                    .frame(width: portrait ? 18 : 24, height: portrait ? 24 : 18)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.label)
                }
            }
        }
        .buttonStyle(.plain)
        .help(portrait ? "Portrait" : "Landscape")
    }
}

/// Photos-style straighten scrubber: drag horizontally to rotate, double-click to reset.
struct StraightenDial: View {
    let angle: Double
    let onChange: (Double) -> Void

    @State private var startAngle: Double?
    private let pixelsPerDegree: CGFloat = 4

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Theme.control)
            Canvas { ctx, size in
                let centerX = size.width / 2
                for tick in stride(from: -EditState.maxFineAngle, through: EditState.maxFineAngle, by: 1) {
                    let x = centerX + (tick - angle) * pixelsPerDegree
                    guard x > 4, x < size.width - 4 else { continue }
                    let major = tick.truncatingRemainder(dividingBy: 5) == 0
                    let h: CGFloat = major ? 8 : 4
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height - 1))
                    path.addLine(to: CGPoint(x: x, y: size.height - 1 - h))
                    ctx.stroke(path, with: .color(.white.opacity(major ? 0.3 : 0.15)), lineWidth: 1)
                }
                var center = Path()
                center.move(to: CGPoint(x: centerX, y: 2))
                center.addLine(to: CGPoint(x: centerX, y: size.height - 2))
                ctx.stroke(center, with: .color(angle == 0 ? .white.opacity(0.5) : .yellow), lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Text("Straighten")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label)
                Spacer()
                Text(angle.formatted(.number.precision(.fractionLength(0...1))) + "°")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(angle == 0 ? Theme.secondaryLabel : Theme.label)
            }
            .padding(.horizontal, 8)
            .allowsHitTesting(false)
        }
        .frame(height: 26)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if startAngle == nil { startAngle = angle }
                    onChange((startAngle ?? angle) + value.translation.width / pixelsPerDegree)
                }
                .onEnded { _ in startAngle = nil }
        )
        .onTapGesture(count: 2) { onChange(0) }
        .help("Drag to straighten, double-click to reset. ← → nudge 0.1°, ⇧ for 1°.")
    }
}
