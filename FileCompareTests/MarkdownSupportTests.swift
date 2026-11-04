import Foundation
import SwiftUI
import Testing

@testable import FileCompare

private func makeMarkdownFile(
    _ text: String,
    name: String = "sample.md"
) -> LoadedTextFile {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if text.hasSuffix("\n") {
        lines.removeLast()
    }
    return LoadedTextFile(
        url: URL(fileURLWithPath: "/virtual/\(name)"),
        displayName: name,
        text: text,
        lines: lines,
        encodingName: "UTF-8",
        byteCount: text.utf8.count,
        hadFinalNewline: text.hasSuffix("\n")
    )
}

private func render(_ text: String) -> [String] {
    MarkdownSupport.renderedLines(from: text)
}

struct MarkdownSupportTests {
    @Test func detectsMarkdownExtensions() {
        #expect(MarkdownSupport.isMarkdownFile(URL(fileURLWithPath: "/tmp/a.md")))
        #expect(MarkdownSupport.isMarkdownFile(URL(fileURLWithPath: "/tmp/a.MARKDOWN")))
        #expect(MarkdownSupport.isMarkdownFile(URL(fileURLWithPath: "/tmp/a.mkd")))
        #expect(!MarkdownSupport.isMarkdownFile(URL(fileURLWithPath: "/tmp/a.txt")))
        #expect(!MarkdownSupport.isMarkdownFile(URL(fileURLWithPath: "/tmp/a.swift")))
    }

    @Test func onlyRendersWhenBothSidesAreMarkdown() {
        let md = URL(fileURLWithPath: "/tmp/a.md")
        let txt = URL(fileURLWithPath: "/tmp/a.txt")

        #expect(MarkdownSupport.shouldRender(left: md, right: md))
        #expect(!MarkdownSupport.shouldRender(left: md, right: txt))
        #expect(!MarkdownSupport.shouldRender(left: nil, right: md))
    }

    @Test func atxAndSetextHeadingsRenderIdentically() {
        #expect(render("# Title") == render("Title\n====="))
        #expect(render("## Subtitle") == render("Subtitle\n--------"))
    }

    @Test func emphasisMarkerAndStrongMarkerStyleAreCanonicalized() {
        #expect(render("An *emphasised* word.") == render("An _emphasised_ word."))
        #expect(render("A **strong** word.") == render("A __strong__ word."))
    }

    @Test func unorderedListMarkersAreCanonicalized() {
        #expect(render("- one\n- two") == render("* one\n* two"))
        #expect(render("- one\n- two") == render("+ one\n+ two"))
    }

    @Test func orderedListNumberingIsCanonicalized() {
        #expect(render("1. one\n2. two") == render("1. one\n1. two"))
        #expect(render("3. one\n4. two") == render("1. one\n2. two"))
    }

    @Test func indentedAndFencedCodeBlocksRenderIdentically() {
        let indented = "    let value = 1\n    print(value)"
        let fenced = "```\nlet value = 1\nprint(value)\n```"
        #expect(render(indented) == render(fenced))
    }

    @Test func reflowedParagraphsRenderIdentically() {
        let wrapped = "This paragraph is split\nacross two source lines."
        let unwrapped = "This paragraph is split across two source lines."
        #expect(render(wrapped) == render(unwrapped))
    }

    @Test func headingLevelChangesRemainVisible() {
        #expect(render("# Title") != render("## Title"))
    }

    @Test func renderedFilePreservesMetadata() {
        let file = makeMarkdownFile("# Title\n\nBody text.\n", name: "notes.md")
        let rendered = MarkdownSupport.renderedFile(from: file)

        #expect(rendered.url == file.url)
        #expect(rendered.displayName == file.displayName)
        #expect(rendered.encodingName == file.encodingName)
        #expect(rendered.byteCount == file.byteCount)
        #expect(rendered.lines == render(file.text))
    }

    @Test func renderedContentMarksTopLevelBlocks() {
        let content = MarkdownSupport.renderedContent(
            from: "# Title\n\nA paragraph.\n\n- one\n- two\n\n```swift\nlet value = 1\n```\n"
        )

        #expect(content.lines == [
            "# Title",
            "A paragraph.",
            "- one",
            "- two",
            "```swift",
            "let value = 1",
            "```"
        ])
        #expect(content.blockStarts == [
            true,
            true,
            true,
            false,
            true,
            false,
            false
        ])
    }

    @Test func blockStartsSurviveIntoTheDiffDocument() throws {
        let file = MarkdownSupport.renderedFile(
            from: makeMarkdownFile("# Title\n\nA paragraph.\n\n- one\n- two\n")
        )

        #expect(file.startsBlock(atLine: 1))
        #expect(file.startsBlock(atLine: 2))
        #expect(file.startsBlock(atLine: 3))
        #expect(!file.startsBlock(atLine: 4))

        let document = try DiffEngine.compare(left: file, right: file)
        #expect(document.startsBlock(for: document.rows[0]))
        #expect(document.startsBlock(for: document.rows[1]))
        #expect(document.startsBlock(for: document.rows[2]))
        #expect(!document.startsBlock(for: document.rows[3]))
    }

    @Test func equivalentMarkdownProducesNoDiff() throws {
        let left = MarkdownSupport.renderedFile(
            from: makeMarkdownFile("# Title\n\nA *small* paragraph.\n", name: "left.md")
        )
        let right = MarkdownSupport.renderedFile(
            from: makeMarkdownFile("Title\n=====\n\nA _small_ paragraph.\n", name: "right.md")
        )

        let document = try DiffEngine.compare(left: left, right: right)
        #expect(document.isIdentical)
        #expect(document.changeGroups.isEmpty)
    }

    @Test func codeBlockLanguageIsPartOfTheComparison() {
        let swift = render("```swift\nlet value = 1\n```")
        let plain = render("```\nlet value = 1\n```")

        #expect(swift == ["```swift", "let value = 1", "```"])
        #expect(swift != plain)
    }

    @Test func syntaxStylingPreservesEveryCharacter() {
        let samples = [
            "# Heading with *emphasis* and `code`",
            "- item with **strong** text and a [link](https://example.com)",
            "> quoted ~~struck~~ text",
            "```swift",
            "| a | b |",
            "plain text",
            "*",
            "_",
            "text *",
            "text _",
            "**",
            "__",
            "a * b",
            "a _ b"
        ]

        for sample in samples {
            let styled = MarkdownCellStyler.attributedString(
                sample,
                fontSize: 14,
                colorScheme: .light
            )
            #expect(String(styled.characters) == sample)
        }
    }

    @Test func changedMarkdownTextStillProducesDiff() throws {
        let left = MarkdownSupport.renderedFile(
            from: makeMarkdownFile("# Title\n\nOld text.\n", name: "left.md")
        )
        let right = MarkdownSupport.renderedFile(
            from: makeMarkdownFile("# Title\n\nNew text.\n", name: "right.md")
        )

        let document = try DiffEngine.compare(left: left, right: right)
        #expect(!document.isIdentical)
        #expect(document.changeGroups.count == 1)
    }
}
