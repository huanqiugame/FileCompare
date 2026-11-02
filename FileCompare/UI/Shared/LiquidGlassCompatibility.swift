import SwiftUI

extension View {
    /// Applies Liquid Glass on macOS 26 and later. Older systems keep the
    /// background, border, and shadow supplied by the call site, so the same
    /// layout still reads as a floating surface.
    @ViewBuilder
    func liquidGlass(
        interactive: Bool = false,
        in shape: some Shape
    ) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            self
        }
    }
}
