import SwiftUI

/// The header sitting in the window's standard title bar. Both filenames are
/// anchored to the window's center line — the left name is right-aligned to it
/// and the right name is left-aligned from it — so changes in name length or
/// hover state never move either title.
struct ComparisonHeaderView: View {
    let session: ComparisonSession
    let onPickFile: (ComparisonSide) -> Void

    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        HStack(spacing: 0) {
            FileTitleLabel(
                url: session.leftURL,
                displayName: session.leftDisplayName,
                side: .left
            ) {
                onPickFile(.left)
            }

            SwapControl(session: session)
                .padding(.horizontal, 14)

            FileTitleLabel(
                url: session.rightURL,
                displayName: session.rightDisplayName,
                side: .right
            ) {
                onPickFile(.right)
            }
        }
        .padding(.horizontal, 78)
        .opacity(appearsActive ? 1 : 0.78)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
