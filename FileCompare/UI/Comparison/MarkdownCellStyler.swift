import AppKit
import SwiftUI

/// Syntax-highlights the canonical Markdown text of a diff cell.
///
/// The renderer deliberately keeps every character, including Markdown
/// delimiters. That keeps the string offsets used by word-level diff emphasis
/// and find highlighting valid; only attributes are added. Headings are larger,
/// emphasis is bold or italic, and code is monospaced, so the canonical diff
/// reads like rendered Markdown rather than raw source.
enum MarkdownCellStyler {
    private struct Style {
        var size: CGFloat
        var bold = false
        var italic = false
        var code = false
        var strikethrough = false
        var color: Color?
        var link: URL?
        var inlineCodeBackground: Color?
    }

    static func attributedString(
        _ text: String,
        fontSize: CGFloat,
        colorScheme: ColorScheme
    ) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }

        var result = AttributedString()
        var style = Style(size: fontSize)
        var contentStart = text.startIndex

        if let heading = headingPrefix(in: text, fontSize: fontSize) {
            appendMarker(
                text[text.startIndex..<heading.contentStart],
                style: heading.markerStyle,
                colorScheme: colorScheme,
                into: &result
            )
            style = heading.contentStyle
            contentStart = heading.contentStart
        } else if let marker = blockMarkerPrefix(in: text, fontSize: fontSize) {
            appendMarker(
                text[text.startIndex..<marker.end],
                style: marker.style,
                colorScheme: colorScheme,
                into: &result
            )
            contentStart = marker.end
        }

        let content = text[contentStart...]
        if isFenceLine(content) {
            var codeStyle = Style(
                size: fontSize,
                code: true,
                color: Color(nsColor: .secondaryLabelColor)
            )
            codeStyle.inlineCodeBackground = nil
            appendPlain(
                content,
                style: codeStyle,
                colorScheme: colorScheme,
                into: &result
            )
        } else {
            renderInline(
                content,
                style: style,
                colorScheme: colorScheme,
                into: &result
            )
        }

        return result
    }

    // MARK: - Block prefixes

    private static func headingPrefix(
        in text: String,
        fontSize: CGFloat
    ) -> (markerStyle: Style, contentStyle: Style, contentStart: String.Index)? {
        var index = text.startIndex
        var level = 0
        while index < text.endIndex, text[index] == "#", level < 6 {
            level += 1
            index = text.index(after: index)
        }
        guard level > 0, index < text.endIndex, text[index] == " " else { return nil }

        index = text.index(after: index)
        let scale: CGFloat
        switch level {
        case 1: scale = 1.55
        case 2: scale = 1.35
        case 3: scale = 1.18
        case 4: scale = 1.08
        default: scale = 1
        }
        let size = (fontSize * scale).rounded()
        let markerStyle = Style(
            size: size,
            bold: true,
            color: Color(nsColor: .tertiaryLabelColor)
        )
        let contentStyle = Style(size: size, bold: true)
        return (markerStyle, contentStyle, index)
    }

    private static func blockMarkerPrefix(
        in text: String,
        fontSize: CGFloat
    ) -> (end: String.Index, style: Style)? {
        var index = text.startIndex

        // Nested block quotes: "> > text".
        var quoteCount = 0
        while index < text.endIndex, text[index] == ">" {
            quoteCount += 1
            index = text.index(after: index)
            if index < text.endIndex, text[index] == " " {
                index = text.index(after: index)
            }
        }
        if quoteCount > 0 {
            return (
                index,
                Style(size: fontSize, color: Color(nsColor: .tertiaryLabelColor))
            )
        }

        // Leading indentation plus an unordered/ordered list marker.
        var markerStart = text.startIndex
        while markerStart < text.endIndex,
              text[markerStart] == " " || text[markerStart] == "\t" {
            markerStart = text.index(after: markerStart)
        }
        guard markerStart < text.endIndex else { return nil }

        var cursor = markerStart
        if "-*+".contains(text[cursor]) {
            cursor = text.index(after: cursor)
            if cursor < text.endIndex, text[cursor] == " " {
                cursor = text.index(after: cursor)
                return (
                    cursor,
                    Style(size: fontSize, color: Color(nsColor: .tertiaryLabelColor))
                )
            }
            return nil
        }

        var digits = 0
        while cursor < text.endIndex, text[cursor].isNumber {
            digits += 1
            cursor = text.index(after: cursor)
        }
        if digits > 0, cursor < text.endIndex, text[cursor] == "." {
            cursor = text.index(after: cursor)
            if cursor < text.endIndex, text[cursor] == " " {
                cursor = text.index(after: cursor)
                return (
                    cursor,
                    Style(size: fontSize, color: Color(nsColor: .tertiaryLabelColor))
                )
            }
        }
        return nil
    }

    private static func isFenceLine(_ text: Substring) -> Bool {
        let trimmed = text.drop { $0 == " " || $0 == "\t" }
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    // MARK: - Inline parsing

    private static func renderInline(
        _ text: Substring,
        style: Style,
        colorScheme: ColorScheme,
        into result: inout AttributedString
    ) {
        var index = text.startIndex
        var plainStart = index

        while index < text.endIndex {
            let character = text[index]

            if character == "`" {
                if let span = codeSpan(in: text, at: index) {
                    flushPlain(text[plainStart..<index], style: style, colorScheme: colorScheme, into: &result)
                    appendMarker(text[index..<span.openEnd], style: style, colorScheme: colorScheme, into: &result)
                    var codeStyle = style
                    codeStyle.code = true
                    codeStyle.inlineCodeBackground = colorScheme == .dark
                        ? Color.white.opacity(0.10)
                        : Color.black.opacity(0.06)
                    appendPlain(text[span.openEnd..<span.closeStart], style: codeStyle, colorScheme: colorScheme, into: &result)
                    appendMarker(text[span.closeStart..<span.end], style: style, colorScheme: colorScheme, into: &result)
                    index = span.end
                    plainStart = index
                    continue
                }
            }

            if character == "*" || character == "_" {
                let delimiter = character == "*" ? "**" : "__"
                if let span = delimitedSpan(in: text, at: index, delimiter: delimiter) {
                    flushPlain(text[plainStart..<index], style: style, colorScheme: colorScheme, into: &result)
                    appendMarker(text[index..<span.contentStart], style: style, colorScheme: colorScheme, into: &result)
                    var strongStyle = style
                    strongStyle.bold = true
                    renderInline(text[span.contentStart..<span.closeStart], style: strongStyle, colorScheme: colorScheme, into: &result)
                    appendMarker(text[span.closeStart..<span.end], style: style, colorScheme: colorScheme, into: &result)
                    index = span.end
                    plainStart = index
                    continue
                }

                let single = String(character)
                if let span = delimitedSpan(in: text, at: index, delimiter: single) {
                    flushPlain(text[plainStart..<index], style: style, colorScheme: colorScheme, into: &result)
                    appendMarker(text[index..<span.contentStart], style: style, colorScheme: colorScheme, into: &result)
                    var emphasisStyle = style
                    emphasisStyle.italic = true
                    renderInline(text[span.contentStart..<span.closeStart], style: emphasisStyle, colorScheme: colorScheme, into: &result)
                    appendMarker(text[span.closeStart..<span.end], style: style, colorScheme: colorScheme, into: &result)
                    index = span.end
                    plainStart = index
                    continue
                }
            }

            if character == "~", let span = delimitedSpan(in: text, at: index, delimiter: "~~") {
                flushPlain(text[plainStart..<index], style: style, colorScheme: colorScheme, into: &result)
                appendMarker(text[index..<span.contentStart], style: style, colorScheme: colorScheme, into: &result)
                var strikeStyle = style
                strikeStyle.strikethrough = true
                renderInline(text[span.contentStart..<span.closeStart], style: strikeStyle, colorScheme: colorScheme, into: &result)
                appendMarker(text[span.closeStart..<span.end], style: style, colorScheme: colorScheme, into: &result)
                index = span.end
                plainStart = index
                continue
            }

            if character == "[", let link = linkSpan(in: text, at: index) {
                flushPlain(text[plainStart..<index], style: style, colorScheme: colorScheme, into: &result)
                appendMarker(text[index..<link.textStart], style: style, colorScheme: colorScheme, into: &result)
                var linkStyle = style
                linkStyle.color = .accentColor
                linkStyle.link = link.url
                renderInline(text[link.textStart..<link.textEnd], style: linkStyle, colorScheme: colorScheme, into: &result)
                appendMarker(text[link.textEnd..<link.end], style: style, colorScheme: colorScheme, into: &result)
                index = link.end
                plainStart = index
                continue
            }

            if character == "!", index < text.index(before: text.endIndex) {
                let next = text.index(after: index)
                if text[next] == "[", let link = linkSpan(in: text, at: next) {
                    flushPlain(text[plainStart..<index], style: style, colorScheme: colorScheme, into: &result)
                    appendMarker(text[index..<link.textStart], style: style, colorScheme: colorScheme, into: &result)
                    var imageStyle = style
                    imageStyle.color = Color(nsColor: .secondaryLabelColor)
                    renderInline(text[link.textStart..<link.textEnd], style: imageStyle, colorScheme: colorScheme, into: &result)
                    appendMarker(text[link.textEnd..<link.end], style: style, colorScheme: colorScheme, into: &result)
                    index = link.end
                    plainStart = index
                    continue
                }
            }

            index = text.index(after: index)
        }

        flushPlain(text[plainStart..<text.endIndex], style: style, colorScheme: colorScheme, into: &result)
    }

    private struct Span {
        var contentStart: String.Index
        var closeStart: String.Index
        var end: String.Index
    }

    private struct CodeSpan {
        var openEnd: String.Index
        var closeStart: String.Index
        var end: String.Index
    }

    private struct LinkSpan {
        var textStart: String.Index
        var textEnd: String.Index
        var end: String.Index
        var url: URL?
    }

    private static func codeSpan(in text: Substring, at start: String.Index) -> CodeSpan? {
        var openEnd = start
        while openEnd < text.endIndex, text[openEnd] == "`" {
            openEnd = text.index(after: openEnd)
        }
        let delimiter = String(text[start..<openEnd])
        guard let close = text.range(of: delimiter, range: openEnd..<text.endIndex) else {
            return nil
        }
        return CodeSpan(openEnd: openEnd, closeStart: close.lowerBound, end: close.upperBound)
    }

    private static func delimitedSpan(
        in text: Substring,
        at start: String.Index,
        delimiter: String
    ) -> Span? {
        let contentStart = text.index(start, offsetBy: delimiter.count)
        guard contentStart <= text.endIndex else { return nil }
        guard let close = text.range(of: delimiter, range: contentStart..<text.endIndex) else {
            return nil
        }
        return Span(
            contentStart: contentStart,
            closeStart: close.lowerBound,
            end: close.upperBound
        )
    }

    private static func linkSpan(
        in text: Substring,
        at start: String.Index
    ) -> LinkSpan? {
        let openEnd = text.index(after: start)
        guard let separator = text.range(of: "](", range: openEnd..<text.endIndex) else {
            return nil
        }
        guard let close = text.range(of: ")", range: separator.upperBound..<text.endIndex) else {
            return nil
        }
        let destination = String(text[separator.upperBound..<close.lowerBound])
        return LinkSpan(
            textStart: openEnd,
            textEnd: separator.lowerBound,
            end: close.upperBound,
            url: URL(string: destination)
        )
    }

    // MARK: - Appending

    private static func flushPlain(
        _ text: Substring,
        style: Style,
        colorScheme: ColorScheme,
        into result: inout AttributedString
    ) {
        guard !text.isEmpty else { return }
        appendPlain(text, style: style, colorScheme: colorScheme, into: &result)
    }

    private static func appendPlain(
        _ text: Substring,
        style: Style,
        colorScheme: ColorScheme,
        into result: inout AttributedString
    ) {
        guard !text.isEmpty else { return }
        var piece = AttributedString(String(text))
        piece.font = font(for: style)
        if let color = style.color {
            piece.foregroundColor = color
        }
        if style.strikethrough {
            piece.strikethroughStyle = .single
        }
        if let background = style.inlineCodeBackground {
            piece.backgroundColor = background
        }
        if let link = style.link {
            piece.link = link
        }
        result += piece
    }

    private static func appendMarker(
        _ text: Substring,
        style: Style,
        colorScheme: ColorScheme,
        into result: inout AttributedString
    ) {
        var markerStyle = style
        markerStyle.color = Color(nsColor: .tertiaryLabelColor)
        appendPlain(text, style: markerStyle, colorScheme: colorScheme, into: &result)
    }

    private static func font(for style: Style) -> Font {
        var font = Font.system(
            size: style.size > 0 ? style.size : 14,
            weight: style.bold ? .semibold : .regular,
            design: style.code ? .monospaced : .default
        )
        if style.bold {
            font = font.bold()
        }
        if style.italic {
            font = font.italic()
        }
        return font
    }
}
