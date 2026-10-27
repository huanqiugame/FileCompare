import SwiftUI

struct LauncherView: View {
    @Bindable var model: LauncherModel
    var onPick: (ComparisonSide) -> Void
    var onCompare: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 18) {
                DropZoneView(
                    side: .left,
                    url: model.leftURL,
                    onPick: { onPick(.left) },
                    onRemove: { model.clear(.left) },
                    onDrop: { urls in handleDrop(urls, onto: .left) }
                )
                DropZoneView(
                    side: .right,
                    url: model.rightURL,
                    onPick: { onPick(.right) },
                    onRemove: { model.clear(.right) },
                    onDrop: { urls in handleDrop(urls, onto: .right) }
                )
            }

            Button(action: onCompare) {
                Text("Compare")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 9)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .background {
                Capsule()
                    .fill(Color.accentColor.opacity(model.canCompare ? 0.12 : 0.04))
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(model.canCompare ? 0.22 : 0.08), lineWidth: 0.5)
            }
            .opacity(model.canCompare ? 1 : 0.45)
            .disabled(!model.canCompare)
            .keyboardShortcut(.return, modifiers: [])

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func handleDrop(_ urls: [URL], onto side: ComparisonSide) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        if files.count >= 2 {
            model.setPair(files[0], files[1])
        } else {
            model.set(files[0], for: side)
        }
    }
}
