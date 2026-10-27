import SwiftUI

/// Centered progress state shown before a document exists.
struct ComparisonLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "comparison.loading", defaultValue: "Comparing…"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Compact, centered error card. Old content remains visible behind it, which
/// keeps context while a reload is attempted.
struct ComparisonErrorView: View {
    let message: String
    let retry: () -> Void

    private var retryTitle: String {
        String(localized: "comparison.retry", defaultValue: "Retry")
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button(action: retry) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(Color.accentColor)
                    }
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help(retryTitle)
            .accessibilityLabel(Text(retryTitle))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 14, y: 5)
    }
}
