import Darwin
import Foundation

/// Chooses the correct loader for a file and returns a `LoadedTextFile`.
///
/// Plain text and Markdown keep the existing byte decoder. RTF and HTML are
/// read as raw data, converted to Markdown source, then passed through the same
/// line-splitting and limit checks as every other comparison input.
enum DocumentLoader {
    static func read(url: URL, format: DocumentFormat? = nil) throws -> LoadedTextFile {
        let resolvedFormat = format ?? DocumentFormat.detect(url)

        switch resolvedFormat {
        case .plainText:
            return try TextFileLoader.read(url: url)
        case .markdown:
            var file = try TextFileLoader.read(url: url)
            file.sourceFormat = .markdown
            return file
        case .rtf, .html:
            return try readRichDocument(url: url, format: resolvedFormat)
        }
    }

    private static func readRichDocument(
        url: URL,
        format: DocumentFormat
    ) throws -> LoadedTextFile {
        let info: stat
        do {
            info = try TextFileLoader.fileStatus(at: url)
        } catch {
            throw FileLoadError.unreadable
        }

        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw FileLoadError.notAFile
        }

        let maximumByteCount = RichDocumentSupport.maximumByteCount(for: format)
        if info.st_size > off_t(maximumByteCount) {
            throw FileLoadError.tooLarge(bytes: Int(info.st_size))
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw FileLoadError.unreadable
        }

        if data.count > maximumByteCount {
            throw FileLoadError.tooLarge(bytes: data.count)
        }

        let markdown = try RichDocumentSupport.markdownSource(from: data, format: format)

        return try TextFileLoader.makeLoadedTextFile(
            url: url,
            text: markdown,
            encodingName: format.displayName ?? "UTF-8",
            byteCount: data.count,
            sourceFormat: format,
            maximumLineLength: TextFileLoader.maximumSemanticLineLength
        )
    }
}
