import Foundation
import UniformTypeIdentifiers

/// The document families FileCompare knows how to turn into comparable lines.
///
/// Detection is extension/UTType based because the app never opens a document
/// picker from the engine; the URL is the only stable source of format
/// information. Content sniffing would make a malformed `.rtf` silently
/// compare as text instead of reporting a conversion error.
enum DocumentFormat: String, Hashable, Sendable {
    case plainText
    case markdown
    case rtf
    case html

    /// Detects the format from the URL extension and its uniform type.
    ///
    /// `public.rtf` and `public.html` both conform to `public.text`, which is
    /// why rich formats are checked before the generic text fallback.
    static func detect(_ url: URL) -> DocumentFormat {
        let fileExtension = url.pathExtension.lowercased()

        if MarkdownSupport.fileExtensions.contains(fileExtension) {
            return .markdown
        }

        if fileExtension == "rtf" {
            return .rtf
        }

        if ["html", "htm", "xhtml", "xht"].contains(fileExtension) {
            return .html
        }

        if let type = UTType(filenameExtension: fileExtension) {
            if type.conforms(to: .rtf) {
                return .rtf
            }
            if type.conforms(to: .html) {
                return .html
            }
        }

        return .plainText
    }

    /// Whether the format needs a parser before it can produce comparable text.
    var isRichDocument: Bool {
        self == .rtf || self == .html
    }

    /// Whether the format can be represented as semantic Markdown.
    ///
    /// Plain text cannot: treating raw text as Markdown would make punctuation
    /// such as `*` or `#` look like markup that the author never wrote.
    var isSemanticDocument: Bool {
        self != .plainText
    }

    /// Label shown in the comparison metadata instead of a character encoding.
    var displayName: String? {
        switch self {
        case .plainText:
            return nil
        case .markdown:
            return "Markdown"
        case .rtf:
            return "RTF"
        case .html:
            return "HTML"
        }
    }
}
