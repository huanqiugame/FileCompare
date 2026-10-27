import AppKit
import SwiftUI

/// A clickable filename. Hovering reveals the real file icon, which can be
/// dragged out as a file; clicking the name opens the file picker for that side.
struct FileTitleLabel: View {
    let url: URL?
    let displayName: String
    let side: ComparisonSide
    let onPick: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            if let url {
                fileIcon(for: url)
                    .frame(width: isHovering ? 15 : 0, height: 15)
                    .opacity(isHovering ? 1 : 0)
                    .clipped()
                    .padding(.trailing, isHovering ? 5 : 0)
                    .onDrag {
                        NSItemProvider(contentsOf: url) ?? NSItemProvider()
                    }
                    .onTapGesture(perform: onPick)
                    .accessibilityHidden(true)
            }

            Button(action: onPick) {
                Text(displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isHovering ? Color.primary : Color.primary.opacity(0.88))
                    .frame(
                        minWidth: 0,
                        maxWidth: 260,
                        alignment: side == .left ? .trailing : .leading
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(url?.path ?? displayName)
        .animation(.easeInOut(duration: 0.16), value: isHovering)
    }

    private func fileIcon(for url: URL) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 15, height: 15)
    }
}
