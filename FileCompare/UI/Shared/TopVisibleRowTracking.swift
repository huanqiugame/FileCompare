import SwiftUI

/// Tracks the topmost visible row of a scroll target layout.
///
/// macOS 15 added `onScrollTargetVisibilityChange`, which reports every
/// visible target and is the most precise option. macOS 14 only offers
/// `scrollPosition(id:)`, which reports the target at the scroll view's top
/// anchor; using it there keeps reading-position restoration working on
/// Sonoma instead of falling back to the first row.
struct TopVisibleRowTracking: ViewModifier {
    @Binding var topRowID: Int?
    let onChange: (Int?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { visibleIDs in
                onChange(visibleIDs.min())
            }
        } else {
            content
                .scrollPosition(id: $topRowID)
                .onChange(of: topRowID) { _, newValue in
                    onChange(newValue)
                }
        }
    }
}
