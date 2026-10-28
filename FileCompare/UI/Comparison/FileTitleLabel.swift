import AppKit
import SwiftUI

/// A filename flanked by a fixed file icon on the left and a chevron on the
/// right. Both appear as soon as the label is hovered. The icon can be dragged
/// out as a file; clicking or dragging the name opens the picker / moves the
/// window.
struct FileTitleLabel: View {
    let url: URL?
    let displayName: String
    let side: ComparisonSide
    let onPick: () -> Void

    @State private var isHovering = false

    private let iconSize: CGFloat = 13
    private let chevronWidth: CGFloat = 13

    var body: some View {
        HStack(spacing: 5) {
            icon
            nameAndChevron
        }
        .overlay {
            LabelHoverTrackingView(onHoverChanged: { isHovering = $0 })
        }
        .frame(maxWidth: .infinity, alignment: side == .left ? .trailing : .leading)
        .help(url?.path ?? displayName)
    }

    @ViewBuilder
    private var icon: some View {
        if let url {
            FileIconDragView(url: url, size: iconSize)
                .frame(width: iconSize, height: iconSize)
                .opacity(isHovering ? 1 : 0)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: iconSize, height: iconSize)
        }
    }

    private var nameAndChevron: some View {
        HStack(spacing: 5) {
            name
            chevron
        }
        .overlay {
            FilenameInteractionView(onClick: onPick)
                .accessibilityHidden(true)
        }
    }

    private var name: some View {
        Text(displayName)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(isHovering ? Color.primary : Color.primary.opacity(0.88))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(displayName))
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: chevronWidth, height: iconSize)
            .opacity(isHovering ? 1 : 0)
            .accessibilityHidden(true)
    }
}

/// Tracks hover over the whole label without taking part in hit testing, so it
/// works over the AppKit icon and the filename interaction view and keeps the
/// hover state continuous while the pointer moves between them.
private struct LabelHoverTrackingView: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
    }

    final class TrackingView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        private var hoverTrackingArea: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTrackingArea {
                removeTrackingArea(hoverTrackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            hoverTrackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
        }
    }
}
