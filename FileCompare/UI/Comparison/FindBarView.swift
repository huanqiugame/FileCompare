import AppKit
import SwiftUI

/// Transient find overlay. It floats over the top-trailing corner of the content
/// and is never present unless explicitly opened.
struct FindBarView: View {
    let session: ComparisonSession

    @FocusState private var isFieldFocused: Bool

    private var query: Binding<String> {
        Binding(
            get: { session.findQuery },
            set: { session.setFindQuery($0) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(
                    String(localized: "find.placeholder", defaultValue: "Find"),
                    text: query
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFieldFocused)
                .frame(width: 150)
                .onSubmit {
                    if NSEvent.modifierFlags.contains(.shift) {
                        session.findPrevious()
                    } else {
                        session.findNext()
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(0.055))
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }

            if session.findMatchCount > 0 {
                Text(verbatim: "\(session.currentFindIndex + 1) / \(session.findMatchCount)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .leading)
            } else if !session.findQuery.isEmpty {
                Text(String(localized: "find.noResults", defaultValue: "No results"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 2) {
                barButton(
                    "chevron.up",
                    title: String(localized: "find.previous", defaultValue: "Previous Match")
                ) {
                    session.findPrevious()
                    isFieldFocused = true
                }
                .disabled(session.findMatchCount == 0)

                barButton(
                    "chevron.down",
                    title: String(localized: "find.next", defaultValue: "Next Match")
                ) {
                    session.findNext()
                    isFieldFocused = true
                }
                .disabled(session.findMatchCount == 0)

                barButton(
                    "xmark",
                    title: String(localized: "find.close", defaultValue: "Close")
                ) {
                    session.dismissFindBar()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
        }
        .glassEffect(.regular, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(.capsule)
        .onTapGesture {
            isFieldFocused = true
        }
        .onExitCommand {
            session.dismissFindBar()
        }
        .onKeyPress(.escape) {
            session.dismissFindBar()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.shift) else { return .ignored }
            session.findPrevious()
            return .handled
        }
        .task {
            try? await Task.sleep(for: .milliseconds(20))
            isFieldFocused = true
        }
        .onChange(of: session.findFocusRequest) { _, _ in
            isFieldFocused = true
        }
    }

    private func barButton(
        _ systemName: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .frame(width: 20, height: 20)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(0.055))
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
    }
}
