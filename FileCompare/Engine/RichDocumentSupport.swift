import AppKit
import CoreFoundation
import Foundation

/// Converts RTF and HTML documents into canonical Markdown source.
///
/// Both formats are normalized before diffing because their raw source is not
/// comparable text: RTF is a stream of control words and HTML is markup. The
/// existing Markdown pipeline then canonicalizes inline markers, headings and
/// block boundaries and feeds the result to the same line diff used for `.md`
/// files.
///
/// RTF has no maintained pure-Swift parser. AppKit's `NSAttributedString`
/// importer is the system-provided parser; it is asked to export HTML, and the
/// same Kanna/libxml2 HTML-to-Markdown renderer handles both formats. This
/// keeps the RTF path free of a second parser and preserves bold, italic,
/// lists, links and CJK text without bundling a large HTML parser.
enum RichDocumentSupport {
    /// HTML is parsed into a full DOM, so it gets a lower ceiling than plain
    /// text. The document still fits comfortably in memory for a 20 MiB cap.
    static let maximumHTMLByteCount = 20 * 1024 * 1024

    /// RTF goes through two full document conversions (attributed string and
    /// HTML), so it gets a slightly higher but still bounded ceiling.
    static let maximumRTFByteCount = 30 * 1024 * 1024

    static func maximumByteCount(for format: DocumentFormat) -> Int {
        switch format {
        case .html:
            return maximumHTMLByteCount
        case .rtf:
            return maximumRTFByteCount
        default:
            return TextFileLoader.maximumByteCount
        }
    }

    /// Converts one rich document into Markdown source.
    ///
    /// - Throws: `FileLoadError` for unsupported formats, oversized input and
    ///   parser failures; `CancellationError` when the surrounding load is
    ///   cancelled.
    static func markdownSource(from data: Data, format: DocumentFormat) throws -> String {
        guard format.isRichDocument else {
            throw FileLoadError.unsupportedDocument
        }
        guard data.count <= maximumByteCount(for: format) else {
            throw FileLoadError.tooLarge(bytes: data.count)
        }

        try Task.checkCancellation()

        switch format {
        case .html:
            let html = try decodeHTML(data)
            try Task.checkCancellation()
            return try convertHTML(html)
        case .rtf:
            return try convertRTF(data)
        default:
            throw FileLoadError.unsupportedDocument
        }
    }

    // MARK: - RTF

    private static func convertRTF(_ data: Data) throws -> String {
        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } catch {
            throw FileLoadError.documentConversionFailed
        }

        try Task.checkCancellation()

        guard attributed.length > 0 else { return "" }

        let htmlData: Data
        do {
            htmlData = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
            )
        } catch {
            throw FileLoadError.documentConversionFailed
        }

        guard let html = String(data: htmlData, encoding: .utf8) else {
            throw FileLoadError.documentConversionFailed
        }

        try Task.checkCancellation()
        return try convertHTML(html)
    }

    // MARK: - HTML

    private static func convertHTML(_ html: String) throws -> String {
        guard !html.isEmpty else { return "" }

        do {
            return try HTMLMarkdownRenderer.markdown(fromHTML: html)
        } catch {
            throw FileLoadError.documentConversionFailed
        }
    }

    /// Decodes HTML bytes while honoring a `<meta charset>` declaration.
    ///
    /// The generic text detector in `TextFileLoader` is still used as a
    /// fallback: it already knows about BOMs, UTF-16 and GB18030.
    private static func decodeHTML(_ data: Data) throws -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return text
        }

        if let declared = declaredHTMLEncoding(in: data),
           let text = String(data: data, encoding: declared) {
            return text
        }

        if let text = String(data: data, encoding: .utf8) {
            return text.unicodeScalars.first == "\u{FEFF}"
                ? String(text.unicodeScalars.dropFirst())
                : text
        }

        return try TextFileLoader.decodeText(data).text
    }

    private static func declaredHTMLEncoding(in data: Data) -> String.Encoding? {
        let prefix = [UInt8](data.prefix(4096))
        guard !prefix.isEmpty else { return nil }

        // Latin-1 cannot fail, and the declaration itself is ASCII.
        let head = String(decoding: prefix, as: UTF8.self)
        let patterns = [
            #"(?i)<meta[^>]+charset\s*=\s*["']?\s*([a-zA-Z0-9._:-]+)"#,
            #"(?i)charset\s*=\s*["']?\s*([a-zA-Z0-9._:-]+)"#
        ]

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                    in: head,
                    range: NSRange(head.startIndex..<head.endIndex, in: head)
                  ),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: head) else {
                continue
            }

            let name = String(head[range])
            if let encoding = stringEncoding(forIANAName: name) {
                return encoding
            }
        }

        return nil
    }

    private static func stringEncoding(forIANAName name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }
}
