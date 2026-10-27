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

    var id: URL { url }
    var lineCount: Int { lines.count }

    func line(at index: Int) -> String? {
        guard lines.indices.contains(index) else { return nil }
        return lines[index]
    }
}
