import Foundation

/// A decoded, normalized text file ready for comparison and display.
///
/// `lines` never contains the empty trailing element produced by a final
/// newline. A file that is empty has zero lines; a file containing only a
/// newline has one empty line.
struct LoadedTextFile: Identifiable, Hashable, Sendable {
    let url: URL
    let displayName: String
    let text: String
    let lines: [String]
    let encodingName: String
    let byteCount: Int
    let hadFinalNewline: Bool
    /// How the file was decoded. Rich documents are converted to Markdown
    /// source before this value is created.
    var sourceFormat: DocumentFormat = .plainText

    /// For Markdown-rendered files, marks the first line of every top-level
    /// block. The diff view uses it to leave breathing room between blocks.
    /// Plain text files leave this empty.
    var lineBlockStarts: [Bool] = []

    var id: URL { url }
    var lineCount: Int { lines.count }

    func line(at index: Int) -> String? {
        guard lines.indices.contains(index) else { return nil }
        return lines[index]
    }

    /// Whether the 1-based line number starts a top-level Markdown block.
    func startsBlock(atLine lineNumber: Int) -> Bool {
        let index = lineNumber - 1
        guard lineBlockStarts.indices.contains(index) else { return false }
        return lineBlockStarts[index]
    }
}
