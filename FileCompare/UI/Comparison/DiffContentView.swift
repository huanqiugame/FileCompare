import SwiftUI

/// The scrollable diff body: one vertical scroller containing both columns, so
/// rows are always aligned. No column headers, no status bar.
struct DiffContentView: View {
    let session: ComparisonSession

    @State private var renderer = DiffTextRenderer()
    @State private var handledScrollRequestID: UUID?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            content

            if let message = session.errorMessage {
                ComparisonErrorView(message: message) {
                    session.reload()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.16), value: session.errorMessage)
    }

    @ViewBuilder
    private var content: some View {
        if let document = session.document {
            documentContent(document)
        } else if session.isLoading {
            ComparisonLoadingView()
        } else {
            Color.clear
        }
    }

    private func documentContent(_ document: DiffDocument) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 320)
            let fontSize = CGFloat(AppSettings.shared.fontSize)
            let showLineNumbers = AppSettings.shared.showLineNumbers
            let metrics = DiffRowMetrics(
                width: width,
                fontSize: fontSize,
                showLineNumbers: showLineNumbers,
                maxLineNumber: document.maxLineNumber
            )
            let rendererKey = DiffTextRenderer.Key(
                documentRevision: session.documentRevision,
                fontSize: fontSize,
                colorScheme: colorScheme
            )
            let currentMatch = session.currentMatch

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(document.rows) { row in
                            DiffRowView(
                                row: row,
                                renderer: renderer,
                                rendererKey: rendererKey,
                                metrics: metrics,
                                leftMatches: session.findHighlights[row.id]?[.left] ?? [],
                                rightMatches: session.findHighlights[row.id]?[.right] ?? [],
                                currentMatch: currentMatch?.rowID == row.id ? currentMatch : nil,
                                isHighlighted: session.highlightedRowID == row.id
                            )
                            .id(row.id)
                        }
                    }
                    .scrollTargetLayout()
                    .textSelection(.enabled)
                }
                .scrollIndicators(.automatic)
                .contentMargins(
                    .top,
                    session.isFindBarVisible ? 44 : 0,
                    for: .scrollContent
                )
                .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { visibleIDs in
                    session.updateTopRow(visibleIDs.min())
                }
                .onAppear {
                    revealCurrentScrollRequest(using: scrollProxy)
                }
                .onChange(of: session.scrollRequest) { _, _ in
                    revealCurrentScrollRequest(using: scrollProxy)
                }
            }
        }
    }

    private func revealCurrentScrollRequest(using proxy: ScrollViewProxy) {
        guard let request = session.scrollRequest, request.id != handledScrollRequestID else { return }
        handledScrollRequestID = request.id

        if request.animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(request.rowID, anchor: .center)
            }
        } else {
            proxy.scrollTo(request.rowID, anchor: .top)
        }
    }
}

/// Layout constants for one diff row. Computed once per content width instead
/// of inside each row, so resizing never triggers per-row measurement work.
struct DiffRowMetrics: Equatable {
    let width: CGFloat
    let columnWidth: CGFloat
    let dividerWidth: CGFloat
    let showLineNumbers: Bool
    let gutterDigitsWidth: CGFloat
    let textWidth: CGFloat
    let lineNumberFontSize: CGFloat
    let fontSize: CGFloat

    init(width: CGFloat, fontSize: CGFloat, showLineNumbers: Bool, maxLineNumber: Int) {
        let safeWidth = max(width, 2)
        let dividerWidth: CGFloat = 1
        let columnWidth = (safeWidth - dividerWidth) / 2

        let digits = max(1, String(max(maxLineNumber, 1)).count)
        let lineNumberFontSize = max(fontSize - 2, 9)
        let digitWidth = (lineNumberFontSize * 0.62).rounded(.up) + 1
        let gutterDigitsWidth = digitWidth * CGFloat(digits)
        let gutterTotal = showLineNumbers ? gutterDigitsWidth + 20 : 0
        let textWidth = max(columnWidth - gutterTotal - 24, 24)

        self.width = safeWidth
        self.columnWidth = columnWidth
        self.dividerWidth = dividerWidth
        self.showLineNumbers = showLineNumbers
        self.gutterDigitsWidth = gutterDigitsWidth
        self.textWidth = textWidth
        self.lineNumberFontSize = lineNumberFontSize
        self.fontSize = fontSize
    }
}
