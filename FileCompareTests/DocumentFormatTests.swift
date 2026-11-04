import Foundation
import Testing

@testable import FileCompare

struct DocumentFormatTests {
    @Test func detectsMarkdownExtensions() {
        for fileExtension in ["md", "markdown", "mkd", "MD"] {
            #expect(
                DocumentFormat.detect(URL(fileURLWithPath: "/tmp/notes.\(fileExtension)")) == .markdown
            )
        }
    }

    @Test func detectsRichDocumentExtensions() {
        for fileExtension in ["rtf", "RTF"] {
            #expect(
                DocumentFormat.detect(URL(fileURLWithPath: "/tmp/notes.\(fileExtension)")) == .rtf
            )
        }

        for fileExtension in ["html", "htm", "xhtml", "HTML"] {
            #expect(
                DocumentFormat.detect(URL(fileURLWithPath: "/tmp/page.\(fileExtension)")) == .html
            )
        }
    }

    @Test func detectsPlainTextAsFallback() {
        #expect(DocumentFormat.detect(URL(fileURLWithPath: "/tmp/notes.txt")) == .plainText)
        #expect(DocumentFormat.detect(URL(fileURLWithPath: "/tmp/source.swift")) == .plainText)
        #expect(DocumentFormat.detect(URL(fileURLWithPath: "/tmp/README")) == .plainText)
    }

    @Test func richDocumentsAreSemanticAndPlainTextIsNot() {
        #expect(DocumentFormat.rtf.isRichDocument)
        #expect(DocumentFormat.html.isRichDocument)
        #expect(!DocumentFormat.markdown.isRichDocument)
        #expect(!DocumentFormat.plainText.isRichDocument)

        #expect(DocumentFormat.markdown.isSemanticDocument)
        #expect(DocumentFormat.rtf.isSemanticDocument)
        #expect(DocumentFormat.html.isSemanticDocument)
        #expect(!DocumentFormat.plainText.isSemanticDocument)
    }

    @Test func loaderMarksMarkdownSourceFormat() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareFormatTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("note.md")
        try "# Title\n".write(to: url, atomically: true, encoding: .utf8)

        let file = try DocumentLoader.read(url: url)
        #expect(file.sourceFormat == .markdown)
    }

    @Test func displayNamesDescribeRichFormats() {
        #expect(DocumentFormat.rtf.displayName == "RTF")
        #expect(DocumentFormat.html.displayName == "HTML")
        #expect(DocumentFormat.markdown.displayName == "Markdown")
        #expect(DocumentFormat.plainText.displayName == nil)
    }
}
