import SwiftUI

/// The only chrome above the document: a centered glass capsule with both file
/// titles and the swap control. Space is left at the leading edge for the
/// window's traffic lights.
struct ComparisonHeaderView: View {
    let session: ComparisonSession
    let onPickFile: (ComparisonSide) -> Void

    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                FileTitleLabel(
                    url: session.leftURL,
                    displayName: session.leftDisplayName,
                    side: .left
                ) {
                    onPickFile(.left)
                }

                SwapControl(session: session)

                FileTitleLabel(
                    url: session.rightURL,
                    displayName: session.rightDisplayName,
                    side: .right
                ) {
                    onPickFile(.right)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(0.025))
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 3)

            Spacer(minLength: 0)
        }
        .padding(.leading, 78)
        .padding(.trailing, 78)
        .opacity(appearsActive ? 1 : 0.78)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}
