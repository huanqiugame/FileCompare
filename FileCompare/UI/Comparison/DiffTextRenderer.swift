import AppKit
import SwiftUI

/// The precomputed text of one diff row.
struct DiffRowPresentation {
    var left: AttributedString
    var right: AttributedString
}

/// Builds and caches attributed diff text. Building is done once per row per
/// document revision / font size / color scheme; scrolling only reads the cache.
@MainActor
final class DiffTextRenderer {
    struct Key: Equatable {
        var documentRevision: Int
        var fontSize: CGFloat
        var colorScheme: ColorScheme
    }

    private var key: Key?
    private var cache: [Int: DiffRowPresentation] = [:]
    private let cacheLimit = 20_000

    func presentation(for row: DiffRow, key: Key) -> DiffRowPresentation {
        if self.key != key {
            self.key = key
            cache.removeAll(keepingCapacity: true)
        }

        if let cached = cache[row.id] {
            return cached
        }

        let presentation = Self.makePresentation(
            for: row,
            fontSize: key.fontSize,
            colorScheme: key.colorScheme
        )
        if cache.count >= cacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[row.id] = presentation
        return presentation
    }

    private static func makePresentation(
        for row: DiffRow,
        fontSize: CGFloat,
        colorScheme: ColorScheme
    ) -> DiffRowPresentation {
        DiffRowPresentation(
            left: attributedText(
                for: row.left,
                kind: row.kind,
                side: .left,
                fontSize: fontSize,
                colorScheme: colorScheme
            ),
            right: attributedText(
                for: row.right,
                kind: row.kind,
                side: .right,
                fontSize: fontSize,
                colorScheme: colorScheme
            )
        )
    }

    private static func attributedText(
        for cell: DiffCell?,
        kind: DiffRowKind,
        side: ComparisonSide,
        fontSize: CGFloat,
        colorScheme: ColorScheme
    ) -> AttributedString {
        guard let cell else { return AttributedString() }

        var result = AttributedString()
        let font = Font.system(size: fontSize)
        let underlineColor = DiffPalette.wordUnderline(side: side, colorScheme: colorScheme)

        for run in cell.runs {
            var piece = AttributedString(run.text)
            piece.font = font
            // The engine marks a whole one-sided line as `.word`, but a removed
            // or added row already has its line tint; only paired modified lines
            // should get the stronger word-level treatment.
            if run.emphasis == .word, kind == .modified {
                piece.backgroundColor = DiffPalette.wordBackground(
                    kind: kind,
                    side: side,
                    colorScheme: colorScheme
                )
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: underlineColor)
            }
            result += piece
        }
        return result
    }
}

/// Shared diff colors. Row tints are subtle; word-level emphasis is stronger and
/// always paired with an underline so changes are not communicated by color only.
enum DiffPalette {
    static func rowTint(
        for kind: DiffRowKind,
        side: ComparisonSide,
        colorScheme: ColorScheme
    ) -> Color {
        let opacity: Double = colorScheme == .dark ? 0.11 : 0.06
        switch (kind, side) {
        case (.removed, .left), (.modified, .left):
            return Color(nsColor: .systemRed).opacity(opacity)
        case (.added, .right), (.modified, .right):
            return Color(nsColor: .systemGreen).opacity(opacity)
        default:
            return .clear
        }
    }

    static func wordBackground(
        kind: DiffRowKind,
        side: ComparisonSide,
        colorScheme: ColorScheme
    ) -> Color {
        let opacity: Double = colorScheme == .dark ? 0.32 : 0.18
        switch (kind, side) {
        case (.removed, .left), (.modified, .left):
            return Color(nsColor: .systemRed).opacity(opacity)
        case (.added, .right), (.modified, .right):
            return Color(nsColor: .systemGreen).opacity(opacity)
        default:
            return Color(nsColor: .systemYellow).opacity(opacity)
        }
    }

    static func wordUnderline(
        side: ComparisonSide,
        colorScheme: ColorScheme
    ) -> Color {
        let opacity: Double = colorScheme == .dark ? 0.8 : 0.6
        switch side {
        case .left:
            return Color(nsColor: .systemRed).opacity(opacity)
        case .right:
            return Color(nsColor: .systemGreen).opacity(opacity)
        }
    }

    static func findHighlight(colorScheme: ColorScheme) -> Color {
        Color(nsColor: .systemYellow)
            .opacity(colorScheme == .dark ? 0.30 : 0.42)
    }

    static func currentFindHighlight(colorScheme: ColorScheme) -> Color {
        Color(nsColor: .systemOrange)
            .opacity(colorScheme == .dark ? 0.52 : 0.58)
    }

    static func divider(colorScheme: ColorScheme) -> Color {
        Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.7 : 0.55)
    }
}
