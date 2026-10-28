import AppKit
import SwiftUI

/// Root of a comparison window: the filename header placed in the standard
/// title bar followed by the document. Everything else (menus, pickers,
/// settings) lives outside this view.
struct ComparisonRootView: View {
    let session: ComparisonSession
    let onPickFile: (ComparisonSide) -> Void

    private static let titlebarHeight = NSWindow.standardTitlebarHeight(
        for: [.titled, .closable, .miniaturizable, .resizable]
    )

    var body: some View {
        VStack(spacing: 0) {
            ComparisonHeaderView(session: session, onPickFile: onPickFile)
                .frame(height: Self.titlebarHeight)
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
        .ignoresSafeArea(.container, edges: .top)
        .onExitCommand(
            perform: session.isFindBarVisible
                ? { session.dismissFindBar() }
                : nil
        )
        .frame(minWidth: 560, minHeight: 360)
    }
}

extension NSWindow {
    /// Height of the standard title bar for a window with the given style.
    static func standardTitlebarHeight(for styleMask: NSWindow.StyleMask) -> CGFloat {
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 800)
        let frameRect = frameRect(forContentRect: contentRect, styleMask: styleMask)
        return max(frameRect.height - contentRect.height, 28)
    }
}
