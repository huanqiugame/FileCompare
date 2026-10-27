import SwiftUI

/// The divider between the two file titles. It reads "vs" at rest and becomes a
/// soft circular swap button on hover, with a fixed hit area so nothing jumps.
struct SwapControl: View {
    let session: ComparisonSession

    @State private var isHovering = false

    private var isEnabled: Bool {
        session.canSwap
    }

    var body: some View {
        Button {
            session.swap()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(isHovering && isEnabled ? 0.09 : 0))
                    .frame(width: 24, height: 24)

                Text("vs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering && isEnabled ? 0 : 1)
                    .scaleEffect(isHovering && isEnabled ? 0.8 : 1)

                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .opacity(isHovering && isEnabled ? 1 : 0)
                    .scaleEffect(isHovering && isEnabled ? 1 : 0.8)
            }
            .frame(width: 30, height: 24)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(String(localized: "header.swapSides", defaultValue: "Swap Sides"))
        .accessibilityLabel(Text(String(localized: "header.swapSides", defaultValue: "Swap Sides")))
        .animation(.easeInOut(duration: 0.16), value: isHovering)
    }
}
