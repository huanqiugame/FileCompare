import SwiftUI

/// Root of a comparison window: a single glass title strip followed by the
/// document. Everything else (menus, pickers, settings) lives outside this view.
struct ComparisonRootView: View {
    let session: ComparisonSession
    let onPickFile: (ComparisonSide) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ComparisonHeaderView(session: session, onPickFile: onPickFile)
                .zIndex(2)

            ZStack(alignment: .topTrailing) {
                DiffContentView(session: session)

                if session.isFindBarVisible {
                    FindBarView(session: session)
                        .padding(.top, 10)
                        .padding(.trailing, 14)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing))
                        )
                        .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.16), value: session.isFindBarVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .ignoresSafeArea(edges: .top)
        .onExitCommand(
            perform: session.isFindBarVisible
                ? { session.dismissFindBar() }
                : nil
        )
        .frame(minWidth: 560, minHeight: 360)
    }
}
