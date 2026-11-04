import Foundation
import Markdown

/// Detects Markdown files and turns their parsed syntax tree into the canonical
/// representation that is compared instead of the raw source.
///
/// Markdown has many equivalent spellings for the same rendered document:
/// ATX and setext headings, `*`/`_` emphasis, different bullet characters,
/// fenced and indented code blocks, ordered-list numbering, paragraph line
/// wrapping, and so on. Diffing the source reports all of those as changes even
/// though the rendered document is identical.
///
/// The normalizer parses each side with `swift-markdown` (CommonMark + GFM) and
/// re-serializes every top-level block with one canonical formatting style. The
/// result is one line per visual block (or per list item / code line), so the
/// existing line diff can compare rendered structure rather than source text.
enum MarkdownSupport {
    /// Extensions treated as Markdown. The set intentionally mirrors the
    /// extensions macOS and common editors associate with `net.daringfireball.markdown`.
    static let fileExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext"
    ]

    static func isMarkdownFile(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }

    /// Whether both sides of a comparison should use Markdown rendering.
    ///
    /// A mixed pair (one Markdown file and one text file) is compared as plain
    /// text, because comparing normalized Markdown against raw text would make
    /// every formatting marker look like a change.
    static func shouldRender(left: URL?, right: URL?) -> Bool {
        guard let left, let right else { return false }
        return isMarkdownFile(left) && isMarkdownFile(right)
    }

    /// Canonical formatting used for comparison.
    ///
    /// `preferredLineLimit` is set very high: the formatter removes soft breaks
    /// first, so re-wrapped paragraphs collapse to a single line. Hard breaks
    /// and code blocks keep their own line structure.
    private static func makeFormattingOptions() -> MarkupFormatter.Options {
        MarkupFormatter.Options(
            useCodeFence: .always,
            emphasisMarker: .star,
            preferredHeadingStyle: .atx,
            preferredLineLimit: .init(maxLength: 500_000, breakWith: .softBreak)
        )
    }

    /// The canonical lines of one rendered document plus block boundaries.
    struct RenderedContent: Sendable {
        var lines: [String]
        /// Parallel to `lines`; `true` at the first line of each top-level block.
        var blockStarts: [Bool]
    }

    /// Replaces the file's lines with the canonical rendering.
    ///
    /// Metadata (URL, display name, encoding, byte count) is preserved so the
    /// rest of the app can keep treating the value as the same file.
    static func renderedFile(from file: LoadedTextFile) -> LoadedTextFile {
        let content = renderedContent(from: file.text)
        return LoadedTextFile(
            url: file.url,
            displayName: file.displayName,
            text: content.lines.joined(separator: "\n"),
            lines: content.lines,
            encodingName: file.encodingName,
            byteCount: file.byteCount,
            hadFinalNewline: !content.lines.isEmpty,
            sourceFormat: file.sourceFormat,
            lineBlockStarts: content.blockStarts
        )
    }

    /// Parses `source` and returns one canonical line per rendered block line.
    ///
    /// Empty lines separating blocks are omitted; empty lines *inside* a block
    /// (for example a code block) are kept, because they are content.
    static func renderedLines(from source: String) -> [String] {
        renderedContent(from: source).lines
    }

    /// Parses `source` into canonical lines and records where each top-level
    /// block starts, so the diff view can separate blocks visually.
    static func renderedContent(from source: String) -> RenderedContent {
        guard !source.isEmpty else {
            return RenderedContent(lines: [], blockStarts: [])
        }

        let document = Document(parsing: source)
        var lines: [String] = []
        var blockStarts: [Bool] = []
        lines.reserveCapacity(document.childCount * 2)
        blockStarts.reserveCapacity(document.childCount * 2)

        let options = makeFormattingOptions()
        for block in document.children {
            let formatted = block.format(options: options)
            var blockLines = formatted
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { trimTrailingWhitespace(String($0)) }

            while blockLines.first?.isEmpty == true {
                blockLines.removeFirst()
            }
            while blockLines.last?.isEmpty == true {
                blockLines.removeLast()
            }

            guard !blockLines.isEmpty else { continue }
            lines.append(contentsOf: blockLines)
            blockStarts.append(true)
            blockStarts.append(contentsOf: repeatElement(false, count: blockLines.count - 1))
        }

        return RenderedContent(lines: lines, blockStarts: blockStarts)
    }

    private static func trimTrailingWhitespace(_ line: String) -> String {
        var end = line.endIndex
        while end > line.startIndex {
            let previous = line.index(before: end)
            let character = line[previous]
            guard character == " " || character == "\t" else { break }
            end = previous
        }
        return String(line[..<end])
    }
}
