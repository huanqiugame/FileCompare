import SwiftUI

/// One aligned pair of diff cells. Both sides share the same row, so wrapped
/// text can never drift out of sync.
struct DiffRowView: View {
    let row: DiffRow
    let renderer: DiffTextRenderer
    let rendererKey: DiffTextRenderer.Key
    let metrics: DiffRowMetrics
    let leftMatches: [NSRange]
    let rightMatches: [NSRange]
    let currentMatch: FindMatch?
    let isHighlighted: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = renderer.presentation(for: row, key: rendererKey)
        let leftText = decorated(
            presentation.left,
            text: row.left?.text ?? "",
            ranges: leftMatches,
            currentRange: currentMatch?.side == .left ? currentMatch?.range : nil
        )
        let rightText = decorated(
            presentation.right,
            text: row.right?.text ?? "",
            ranges: rightMatches,
            currentRange: currentMatch?.side == .right ? currentMatch?.range : nil
        )

        HStack(alignment: .top, spacing: 0) {
            cell(row.left, text: leftText, minHeight: minimumCellHeight)
            cell(row.right, text: rightText, minHeight: minimumCellHeight)
        }
        .frame(width: metrics.width, alignment: .leading)
        .background {
            HStack(spacing: 0) {
                DiffPalette.rowTint(for: row.kind, side: .left, colorScheme: colorScheme)
                    .frame(width: metrics.columnWidth)
                DiffPalette.divider(colorScheme: colorScheme)
                    .frame(width: metrics.dividerWidth)
                DiffPalette.rowTint(for: row.kind, side: .right, colorScheme: colorScheme)
                    .frame(width: metrics.columnWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .overlay {
            if isHighlighted {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.10))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isHighlighted)
    }

    private func cell(_ diffCell: DiffCell?, text: AttributedString, minHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if metrics.showLineNumbers {
                Text(lineNumber(for: diffCell))
                    .font(.system(size: metrics.lineNumberFontSize, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: metrics.gutterDigitsWidth, alignment: .trailing)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
            }

            Text(text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: metrics.textWidth, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 12)
        }
        .frame(width: metrics.columnWidth, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(.vertical, 3)
    }

    /// Blank lines have no text height, so they get one line's worth of height to
    /// keep the rows evenly spaced. Rows with content stay exactly as tall as
    /// their tallest wrapped side.
    private var minimumCellHeight: CGFloat {
        let leftIsBlank = row.left?.text.isEmpty ?? true
        let rightIsBlank = row.right?.text.isEmpty ?? true
        guard leftIsBlank, rightIsBlank else { return 0 }
        return max(metrics.fontSize * 1.35, 17)
    }

    private func lineNumber(for cell: DiffCell?) -> String {
        guard let cell else { return "" }
        return String(cell.lineNumber)
    }

    private func decorated(
        _ base: AttributedString,
        text: String,
        ranges: [NSRange],
        currentRange: NSRange?
    ) -> AttributedString {
        guard !ranges.isEmpty || currentRange != nil else { return base }

        var result = base
        let color = DiffPalette.findHighlight(colorScheme: colorScheme)
        for range in ranges {
            apply(range, color: color, to: &result, text: text)
        }
        if let currentRange {
            apply(
                currentRange,
                color: DiffPalette.currentFindHighlight(colorScheme: colorScheme),
                to: &result,
                text: text
            )
        }
        return result
    }

    private func apply(
        _ nsRange: NSRange,
        color: Color,
        to attributed: inout AttributedString,
        text: String
    ) {
        guard nsRange.length > 0, let stringRange = Range(nsRange, in: text) else { return }

        let lowerOffset = text.distance(from: text.startIndex, to: stringRange.lowerBound)
        let upperOffset = text.distance(from: text.startIndex, to: stringRange.upperBound)
        let characterCount = attributed.characters.count
        guard lowerOffset < upperOffset, upperOffset <= characterCount else { return }

        let lower = attributed.index(attributed.startIndex, offsetByCharacters: lowerOffset)
        let upper = attributed.index(attributed.startIndex, offsetByCharacters: upperOffset)
        attributed[lower..<upper].backgroundColor = color
    }
}
