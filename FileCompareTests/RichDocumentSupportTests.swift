import AppKit
import Foundation
import SwiftUI
import Testing

@testable import FileCompare

struct RichDocumentSupportTests {
    private func markdown(fromHTML html: String) throws -> String {
        try RichDocumentSupport.markdownSource(from: Data(html.utf8), format: .html)
    }

    // MARK: - HTML

    @Test func htmlPreservesHeadingsListsTablesAndInlineFormatting() throws {
        let markdown = try markdown(fromHTML: """
        <!doctype html>
        <html>
          <body>
            <h1>Title</h1>
            <p>Hello <strong>bold</strong> and <em>italic</em>.</p>
            <ul><li>One</li><li>Two</li></ul>
            <ol><li>First</li><li>Second</li></ol>
            <table>
              <tr><th>A</th><th>B</th></tr>
              <tr><td>1</td><td>2</td></tr>
            </table>
            <pre><code>let value = 1</code></pre>
          </body>
        </html>
        """)

        #expect(markdown.contains("# Title"))
        #expect(markdown.contains("**bold**"))
        #expect(markdown.contains("*italic*"))
        #expect(markdown.contains("- One"))
        #expect(markdown.contains("- Two"))
        #expect(markdown.contains("1. First"))
        #expect(markdown.contains("2. Second"))
        #expect(markdown.contains("| A | B |"))
        #expect(markdown.contains("| 1 | 2 |"))
        #expect(markdown.contains("let value = 1"))
    }

    @Test func htmlAsteriskAtEndOfLineSurvivesStyling() throws {
        // A required-field asterisk used to leave a lone `*` at the end of a
        // canonical line, which crashed MarkdownCellStyler while it probed for
        // a `**` delimiter.
        let markdown = try markdown(fromHTML: "<p>姓名 <span>*</span></p>")
        let file = try TextFileLoader.makeLoadedTextFile(
            url: URL(fileURLWithPath: "/virtual/required.html"),
            text: markdown,
            encodingName: "HTML",
            byteCount: 0,
            sourceFormat: .html,
            maximumLineLength: TextFileLoader.maximumSemanticLineLength
        )
        let rendered = MarkdownSupport.renderedFile(from: file)

        #expect(rendered.lines == ["姓名 *"])
        let styled = MarkdownCellStyler.attributedString(
            try #require(rendered.lines.first),
            fontSize: 14,
            colorScheme: .light
        )
        #expect(String(styled.characters) == rendered.lines[0])
    }

    @Test func htmlPreservesHardBreaksAndNestedLists() throws {
        let markdown = try markdown(fromHTML: """
        <p>One<br>Two</p>
        <ul><li>Outer<ul><li>Inner</li></ul></li></ul>
        """)

        #expect(markdown.contains("One  \nTwo"))
        #expect(markdown.contains("  - Inner"))

        let file = try TextFileLoader.makeLoadedTextFile(
            url: URL(fileURLWithPath: "/virtual/breaks.html"),
            text: markdown,
            encodingName: "HTML",
            byteCount: 0,
            sourceFormat: .html,
            maximumLineLength: TextFileLoader.maximumSemanticLineLength
        )
        let rendered = MarkdownSupport.renderedFile(from: file)
        #expect(rendered.lines.contains("One"))
        #expect(rendered.lines.contains("Two"))
    }

    @Test func htmlDropsHeadScriptsStylesAndMedia() throws {
        let markdown = try markdown(fromHTML: """
        <html>
          <head>
            <title>Hidden title</title>
            <style>p { color: red; }</style>
            <script>window.secret = true;</script>
          </head>
          <body>
            <p>Visible text</p>
            <script>alert('secret')</script>
            <img src="file:///private/tmp/secret.png" alt="secret image">
            <video src="file:///private/tmp/secret.mp4"></video>
            <iframe src="https://example.com/secret"></iframe>
          </body>
        </html>
        """)

        #expect(markdown.contains("Visible text"))
        #expect(!markdown.contains("Hidden title"))
        #expect(!markdown.contains("color: red"))
        #expect(!markdown.contains("alert"))
        #expect(!markdown.contains("secret.png"))
        #expect(!markdown.contains("secret.mp4"))
        #expect(!markdown.contains("example.com/secret"))
        #expect(!markdown.contains("secret image"))
    }

    @Test func htmlDecodesEntitiesAndCJK() throws {
        let markdown = try markdown(fromHTML: """
        <p>&#20320;&#22909; &amp; &lt;tags&gt; &quot;quoted&quot; &nbsp;world</p>
        """)

        #expect(markdown.contains("你好"))
        #expect(markdown.contains("& \\<tags\\>"))
        #expect(markdown.contains("\"quoted\""))
        #expect(markdown.contains("world"))
    }

    @Test func htmlToleratesMalformedMarkup() throws {
        let markdown = try markdown(fromHTML: "<p>One<p>Two <b>bold")

        #expect(markdown.contains("One"))
        #expect(markdown.contains("Two"))
        #expect(markdown.contains("**bold"))
    }

    @Test func htmlHonorsDeclaredGB18030MetaCharset() throws {
        let html = "<meta charset=\"gb2312\"><p>你好世界</p>"
        let data = try #require(html.data(using: TextFileLoader.gb18030))

        let markdown = try RichDocumentSupport.markdownSource(from: data, format: .html)
        #expect(markdown.contains("你好世界"))
    }

    @Test func htmlHonorsWindows1252MetaCharset() throws {
        let html = "<meta charset=\"windows-1252\"><p>café — “quoted”</p>"
        let data = try #require(html.data(using: .windowsCP1252))

        let markdown = try RichDocumentSupport.markdownSource(from: data, format: .html)
        #expect(markdown.contains("café"))
        #expect(markdown.contains("“quoted”"))
    }

    @Test func htmlStripsUTF8ByteOrderMark() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("<p>你好</p>".utf8))

        let markdown = try RichDocumentSupport.markdownSource(from: data, format: .html)
        #expect(markdown.contains("你好"))
    }

    @Test func htmlRejectsInputAboveItsSizeLimit() {
        let oversized = Data(count: RichDocumentSupport.maximumHTMLByteCount + 1)

        #expect(throws: FileLoadError.self) {
            try RichDocumentSupport.markdownSource(from: oversized, format: .html)
        }
    }

    @Test func htmlEmptyDocumentProducesEmptyMarkdown() throws {
        #expect(try markdown(fromHTML: "") == "")
    }

    // MARK: - RTF

    @Test func rtfPreservesTextEmphasisAndCJK() throws {
        let rtf = #"{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0 Helvetica;}}\f0\fs24 Hello \b bold\b0  and \i italic\i0 .\par \u20320?\u22909? CJK.\par}"#
        let data = try #require(rtf.data(using: .ascii))

        let markdown = try RichDocumentSupport.markdownSource(from: data, format: .rtf)

        #expect(markdown.contains("Hello **bold** and *italic*"))
        #expect(markdown.contains("你好 CJK"))
    }

    @Test @MainActor func rtfPreservesLists() throws {
        let text = NSMutableAttributedString(string: "One\nTwo\nThree\n")
        let style = NSMutableParagraphStyle()
        style.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        text.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: text.length)
        )

        let data = try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let markdown = try RichDocumentSupport.markdownSource(from: data, format: .rtf)

        #expect(markdown.contains("- One"))
        #expect(markdown.contains("- Two"))
        #expect(markdown.contains("- Three"))
    }

    @Test @MainActor func rtfPreservesLinks() throws {
        let text = NSMutableAttributedString(string: "Visit example")
        text.addAttribute(
            .link,
            value: try #require(URL(string: "https://example.com")),
            range: NSRange(location: 6, length: 7)
        )

        let data = try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let markdown = try RichDocumentSupport.markdownSource(from: data, format: .rtf)

        #expect(markdown.contains("[example](https://example.com)"))
    }

    @Test @MainActor func rtfPreservesTables() throws {
        let text = NSMutableAttributedString()
        let table = NSTextTable()
        table.numberOfColumns = 2

        for row in 0..<2 {
            for column in 0..<2 {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: row,
                    rowSpan: 1,
                    startingColumn: column,
                    columnSpan: 1
                )
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                let cell = NSMutableAttributedString(string: "R\(row)C\(column)\n")
                cell.addAttribute(
                    .paragraphStyle,
                    value: style,
                    range: NSRange(location: 0, length: cell.length)
                )
                text.append(cell)
            }
        }

        let data = try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let markdown = try RichDocumentSupport.markdownSource(from: data, format: .rtf)

        #expect(markdown.contains("| R0C0 | R0C1 |"))
        #expect(markdown.contains("| R1C0 | R1C1 |"))
    }

    @Test func htmlTableSurvivesCanonicalMarkdownRendering() throws {
        let markdown = try markdown(fromHTML: """
        <table>
          <tr><th>A</th><th>B</th></tr>
          <tr><td>1</td><td>2</td></tr>
        </table>
        """)
        let file = try TextFileLoader.makeLoadedTextFile(
            url: URL(fileURLWithPath: "/virtual/table.html"),
            text: markdown,
            encodingName: "HTML",
            byteCount: 0,
            sourceFormat: .html,
            maximumLineLength: TextFileLoader.maximumSemanticLineLength
        )
        let rendered = MarkdownSupport.renderedFile(from: file)

        #expect(rendered.lines.contains("|A|B|"))
        #expect(rendered.lines.contains("|1|2|"))
    }

    @Test func rtfRejectsMalformedInput() {
        #expect(throws: FileLoadError.self) {
            try RichDocumentSupport.markdownSource(
                from: Data("{this is not a valid rtf document".utf8),
                format: .rtf
            )
        }
    }

    @Test func rtfEmptyDocumentProducesEmptyMarkdown() throws {
        let rtf = #"{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}}"#
        let markdown = try RichDocumentSupport.markdownSource(
            from: try #require(rtf.data(using: .ascii)),
            format: .rtf
        )

        #expect(markdown.isEmpty)
    }

    // MARK: - Loader

    @Test func documentLoaderProducesConvertedMarkdownFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareRichLoader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("page.html")
        try "<h1>Title</h1><p>Body text.</p>".write(to: url, atomically: true, encoding: .utf8)

        let file = try DocumentLoader.read(url: url)

        #expect(file.sourceFormat == .html)
        #expect(file.encodingName == "HTML")
        #expect(file.displayName == "page.html")
        #expect(file.lines.contains("# Title"))
        #expect(file.lines.contains("Body text."))
        #expect(file.url == url)
    }

    @Test func documentLoaderConvertsRTF() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareRichLoader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rtf = #"{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}\f0\fs24 Hello \b bold\b0 .\par}"#
        let url = directory.appendingPathComponent("note.rtf")
        try #require(rtf.data(using: .ascii)).write(to: url)

        let file = try DocumentLoader.read(url: url)

        #expect(file.sourceFormat == .rtf)
        #expect(file.encodingName == "RTF")
        #expect(file.lines == ["Hello **bold**."])
    }

    @Test func documentLoaderRejectsDirectories() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareRichLoader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("package.rtf", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        #expect(throws: FileLoadError.self) {
            try DocumentLoader.read(url: url)
        }
    }

    @Test func documentLoaderAllowsLongParagraphLinesAfterConversion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareRichLoader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A single paragraph longer than the plain-text line limit but below
        // the relaxed semantic limit. Minified HTML has the same shape.
        let sentence = String(repeating: "word ", count: 12_000)
        let url = directory.appendingPathComponent("long.html")
        try "<p>\(sentence)</p>".write(to: url, atomically: true, encoding: .utf8)

        let file = try DocumentLoader.read(url: url)
        #expect(file.lineCount == 1)
        #expect(file.lines[0].utf8.count > TextFileLoader.maximumLineLength)
    }
}
