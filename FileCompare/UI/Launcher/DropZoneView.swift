import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let side: ComparisonSide
    let url: URL?
    var onPick: () -> Void
    var onRemove: () -> Void
    var onDrop: ([URL]) -> Void

    @State private var isTargeted = false
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            zoneContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture(perform: onPick)

            if url != nil, isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("Remove File")
                .padding(10)
                .transition(.opacity)
            }
        }
        .frame(width: 300, height: 158)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.28),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6, 4])
                )
        }
        .scaleEffect(isTargeted ? 1.012 : 1)
        .animation(.snappy(duration: 0.16), value: isTargeted)
        .onHover { isHovered = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            onDrop(urls)
            return true
        } isTargeted: {
            isTargeted = $0
        }
        .help(url?.path ?? String(localized: "Open File", defaultValue: "Open File"))
        .accessibilityLabel(url == nil ? Text("Open File") : Text(url?.lastPathComponent ?? ""))
    }

    @ViewBuilder
    private var zoneContent: some View {
        if let url {
            VStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                Text(url.lastPathComponent)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
        } else {
            VStack(spacing: 9) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 36, weight: .ultraLight))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)

                Text("Drop or Choose File")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
