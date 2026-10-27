import CoreFoundation
import Darwin
import Foundation

/// Reads and decodes text files for comparison.
///
/// The loader is fully synchronous and free of global state, so it can be
/// called from a detached task or from `Task.detached` without hopping actors.
enum TextFileLoader {
    /// Largest file accepted, in bytes (50 MiB).
    static let maximumByteCount = 50 * 1024 * 1024

    /// Largest number of lines accepted.
    static let maximumLineCount = 200_000

    /// Largest UTF-8 byte count accepted in one line. A single gigantic line
    /// is pathological for text layout and would make the app allocate hundreds
    /// of megabytes; documents keep well below this limit.
    static let maximumLineLength = 50_000

    /// Number of leading bytes inspected when scoring BOM-less UTF-16 and
    /// measuring the control-byte ratio.
    static let binarySniffByteCount = 8 * 1024

    /// Fraction of control bytes that marks a file as binary.
    static let controlByteThreshold = 0.1

    /// GB18030 (`GB_18030_2000`) as a `String.Encoding`.
    static let gb18030: String.Encoding = {
        let cfEncoding = CFStringEncodings.GB_18030_2000
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(cfEncoding.rawValue)
        )
        return String.Encoding(rawValue: nsEncoding)
    }()

    // MARK: - Reading

    /// Reads, validates, decodes, and normalizes the file at `url`.
    ///
    /// Metadata comes from `stat(2)` rather than `URL.resourceValues(forKeys:)`:
    /// the latter caches values per `URL` instance and can keep reporting a
    /// stale size or existence state, which would let a grown file bypass the
    /// size limit (or a truncated file stay rejected).
    ///
    /// - Throws: `FileLoadError` describing why the file cannot be compared.
    static func read(url: URL) throws -> LoadedTextFile {
        let info: stat
        do {
            info = try fileStatus(at: url)
        } catch {
            throw FileLoadError.unreadable
        }

        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw FileLoadError.notAFile
        }

        if info.st_size > off_t(maximumByteCount) {
            throw FileLoadError.tooLarge(bytes: Int(info.st_size))
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw FileLoadError.unreadable
        }

        return try decode(data: data, url: url)
    }

    private static func fileStatus(at url: URL) throws -> stat {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return stat(path, &info)
        }
        guard result == 0 else { throw FileLoadError.unreadable }
        return info
    }

    // MARK: - Decoding

    /// Decodes already-read bytes. Exposed for tests so encodings can be
    /// exercised without creating large files on disk.
    static func decode(data: Data, url: URL) throws -> LoadedTextFile {
        if data.count > maximumByteCount {
            throw FileLoadError.tooLarge(bytes: data.count)
        }

        // Reject UTF-32 before the binary scan and before the UTF-16 BOM
        // checks: `FF FE 00 00` also starts with the UTF-16 LE BOM.
        if isUTF32ByteOrderMark(data) {
            throw FileLoadError.unsupportedEncoding
        }

        if isBinary(data) {
            throw FileLoadError.binary
        }

        let decoded = try decodeText(data)
        let text = normalizeLineEndings(decoded.text)
        let hadFinalNewline = text.utf8.last == 0x0A

        // Split on the UTF-8 newline byte instead of walking Characters. This
        // keeps large documents linear and avoids the expensive per-character
        // path of `String.split` for multi-megabyte files.
        var lines: [String] = []
        if !text.isEmpty {
            lines = text.utf8
                .split(separator: 0x0A, omittingEmptySubsequences: false)
                .map { String(decoding: $0, as: UTF8.self) }
        }

        if hadFinalNewline, !lines.isEmpty {
            lines.removeLast()
        }

        guard lines.count <= maximumLineCount else {
            throw FileLoadError.tooManyLines(count: lines.count)
        }

        for line in lines where line.utf8.count > maximumLineLength {
            throw FileLoadError.lineTooLong(length: line.utf8.count)
        }

        return LoadedTextFile(
            url: url,
            displayName: displayName(for: url),
            text: text,
            lines: lines,
            encodingName: decoded.encodingName,
            byteCount: data.count,
            hadFinalNewline: hadFinalNewline
        )
    }

    private struct DecodedText {
        var text: String
        var encodingName: String
    }

    private static func decodeText(_ data: Data) throws -> DecodedText {
        let bom = [UInt8](data.prefix(4))

        if bom.count >= 3, bom[0] == 0xEF, bom[1] == 0xBB, bom[2] == 0xBF {
            return try decodeUTF8(data.dropFirst(3))
        }

        if isUTF32ByteOrderMark(data) {
            throw FileLoadError.unsupportedEncoding
        }

        if bom.count >= 2, bom[0] == 0xFF, bom[1] == 0xFE {
            return try decodeUTF16(data.dropFirst(2), littleEndian: true)
        }

        if bom.count >= 2, bom[0] == 0xFE, bom[1] == 0xFF {
            return try decodeUTF16(data.dropFirst(2), littleEndian: false)
        }

        // BOM-less UTF-16 with a decisive signature must be tried before
        // UTF-8: ASCII-ish UTF-16 is also valid UTF-8 (NUL bytes are legal),
        // and decoding it as UTF-8 would yield NUL-laden lines. The check is
        // deliberately conservative so ordinary UTF-8 is never stolen.
        if let detection = utf16Detection(data),
           detection.isStrong(containsNul: data.contains(0)) {
            return try decodeUTF16(data, littleEndian: detection.littleEndian)
        }

        if let text = String(data: data, encoding: .utf8) {
            if text.unicodeScalars.contains(where: { $0.value == 0 }) {
                // Valid UTF-16 can also be valid UTF-8 when its high bytes
                // are nonzero (ASCII-ish CJK). Prefer the UTF-16 reading
                // instead of rejecting the NUL as binary.
                if let detection = utf16Detection(data), detection.isPlausible {
                    return try decodeUTF16(data, littleEndian: detection.littleEndian)
                }
                throw FileLoadError.binary
            }
            return DecodedText(text: stripByteOrderMark(text), encodingName: "UTF-8")
        }

        // UTF-8 failed. A plausible BOM-less UTF-16 reading (typically short
        // CJK text, whose byte pairs can score closely in both endiannesses)
        // is tried before GB18030. GB18030 accepts almost any byte stream, but
        // its Chinese two-byte sequences read as Hangul when byte-swapped, and
        // Hangul is not counted as prose, so genuine GB18030 files do not look
        // plausible here.
        if let detection = utf16Detection(data), detection.isPlausible {
            return try decodeUTF16(data, littleEndian: detection.littleEndian)
        }

        // Last resort: GB18030. A NUL produced by this decode means it is not
        // text, so reject rather than accept NUL-laden lines.
        if let text = String(data: data, encoding: gb18030),
           !text.unicodeScalars.contains(where: { $0.value == 0 }) {
            return DecodedText(text: stripByteOrderMark(text), encodingName: "GB18030")
        }

        throw FileLoadError.unsupportedEncoding
    }

    private static func decodeUTF8(_ data: Data) throws -> DecodedText {
        guard let text = String(data: data, encoding: .utf8) else {
            throw FileLoadError.unsupportedEncoding
        }
        try rejectNulBytes(in: text)
        return DecodedText(text: stripByteOrderMark(text), encodingName: "UTF-8")
    }

    private static func decodeUTF16(_ data: Data, littleEndian: Bool) throws -> DecodedText {
        // An odd payload would silently lose the trailing byte, so reject it.
        guard data.count.isMultiple(of: 2) else {
            throw FileLoadError.unsupportedEncoding
        }
        guard let text = String(
            data: data,
            encoding: littleEndian ? .utf16LittleEndian : .utf16BigEndian
        ) else {
            throw FileLoadError.unsupportedEncoding
        }
        return DecodedText(
            text: stripByteOrderMark(text),
            encodingName: littleEndian ? "UTF-16 LE" : "UTF-16 BE"
        )
    }

    /// A U+0000 produced by a single-byte/UTF-8 decoder is a binary signal,
    /// not text. UTF-16 decoding is exempt because its NUL bytes are part of
    /// the encoding.
    private static func rejectNulBytes(in text: String) throws {
        if text.unicodeScalars.contains(where: { $0.value == 0 }) {
            throw FileLoadError.binary
        }
    }

    /// Removes a single leading U+FEFF left behind by lenient decoders.
    private static func stripByteOrderMark(_ text: String) -> String {
        guard text.unicodeScalars.first == "\u{FEFF}" else { return text }
        return String(text.unicodeScalars.dropFirst())
    }

    // MARK: - Binary detection

    private static func isUTF32ByteOrderMark(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(4))
        guard bytes.count == 4 else { return false }
        return (bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0x00 && bytes[3] == 0x00)
            || (bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0xFE && bytes[3] == 0xFF)
    }

    private static func isBinary(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }

        // UTF-16 text contains NUL bytes that are not a binary signal. The
        // BOM cases are obvious; the sniff below covers BOM-less files.
        if data.count >= 2 {
            let first = data[data.startIndex]
            let second = data[data.index(after: data.startIndex)]
            if (first == 0xFF && second == 0xFE) || (first == 0xFE && second == 0xFF) {
                return false
            }
        }

        if utf16Detection(data) != nil {
            return false
        }

        // Scan the entire file, not just the sniff window: a NUL at any
        // offset means the file is binary.
        if data.contains(0) {
            return true
        }

        // Control-byte heuristics stay sample-based so huge files stay cheap.
        let sample = [UInt8](data.prefix(binarySniffByteCount))
        var controlCount = 0

        for byte in sample {
            if byte < 0x20, byte != 0x09, byte != 0x0A, byte != 0x0D {
                controlCount += 1
            }
        }

        guard !sample.isEmpty else { return false }
        return Double(controlCount) / Double(sample.count) > controlByteThreshold
    }

    // MARK: - UTF-16 heuristics

    private struct UTF16Score {
        var pairCount = 0
        var validCount = 0
        var textCount = 0
        var commonCJKCount = 0
        var zeroHighByteCount = 0
        var surrogatePairCount = 0

        var validRatio: Double { ratio(validCount) }
        var textRatio: Double { ratio(textCount) }
        var commonCJKRatio: Double { ratio(commonCJKCount) }
        var zeroHighByteRatio: Double { ratio(zeroHighByteCount) }
        var surrogatePairRatio: Double { ratio(surrogatePairCount * 2) }

        var score: Double {
            validRatio
                + 0.5 * zeroHighByteRatio
                + 0.5 * textRatio
                + 0.25 * commonCJKRatio
                + 0.5 * surrogatePairRatio
        }

        var isPlausible: Bool {
            validRatio >= 0.98 && textRatio >= 0.85
        }

        private func ratio(_ count: Int) -> Double {
            pairCount == 0 ? 0 : Double(count) / Double(pairCount)
        }
    }

    private struct UTF16Detection {
        var littleEndian: Bool
        var score: UTF16Score
        var alternate: UTF16Score

        var isPlausible: Bool { score.isPlausible }

        /// Decisive enough to be tried before UTF-8, so ordinary UTF-8 is
        /// never misclassified just because its even-length bytes happen to
        /// split into plausible-looking UTF-16.
        ///
        /// A strong signal is either:
        /// - NUL-heavy high bytes (ASCII-ish UTF-16), which is not valid text
        ///   for any other decoder, or
        /// - a majority of frequent Han characters in one endianness only,
        ///   which covers short CJK files whose bytes are otherwise valid
        ///   ASCII (the LE bytes of 你好 are `O}Y when read as UTF-8).
        func isStrong(containsNul: Bool) -> Bool {
            guard isPlausible else { return false }
            if containsNul, score.zeroHighByteRatio >= 0.2 {
                return true
            }
            return score.commonCJKRatio >= 0.5 && alternate.commonCJKRatio < 0.5
        }
    }

    /// Returns the more likely endianness for BOM-less UTF-16, or `nil` when
    /// the bytes are ambiguous or not plausibly UTF-16 at all.
    ///
    /// - Returns: A detection whose `littleEndian` is `true` for LE data.
    private static func utf16Detection(_ data: Data) -> UTF16Detection? {
        guard data.count >= 4, data.count.isMultiple(of: 2) else { return nil }

        let little = utf16Score(data, littleEndian: true)
        let big = utf16Score(data, littleEndian: false)
        guard little.score != big.score else { return nil }

        let littleWins = little.score > big.score
        let winner = littleWins ? little : big
        guard winner.isPlausible else { return nil }

        return UTF16Detection(
            littleEndian: littleWins,
            score: winner,
            alternate: littleWins ? big : little
        )
    }

    private static func utf16Score(_ data: Data, littleEndian: Bool) -> UTF16Score {
        let bytes = [UInt8](data.prefix(binarySniffByteCount))
        var score = UTF16Score()
        var pendingHighSurrogate = false
        var index = 0

        while index + 1 < bytes.count {
            defer { index += 2 }

            let first = bytes[index]
            let second = bytes[index + 1]
            let unit = littleEndian
                ? UInt16(first) | (UInt16(second) << 8)
                : (UInt16(first) << 8) | UInt16(second)
            let highByte = littleEndian ? second : first

            score.pairCount += 1
            if highByte == 0 {
                score.zeroHighByteCount += 1
            }

            if pendingHighSurrogate {
                pendingHighSurrogate = false
                if (0xDC00...0xDFFF).contains(unit) {
                    // The high half was counted when it appeared; count it
                    // and its low half only once the pair is valid.
                    score.validCount += 2
                    score.textCount += 2
                    score.surrogatePairCount += 1
                }
                continue
            }

            switch unit {
            case 0x0000, 0xFFFE, 0xFFFF:
                break
            case 0xD800...0xDBFF:
                pendingHighSurrogate = true
            case 0xDC00...0xDFFF:
                break
            default:
                if isUTF16TextUnit(unit) {
                    score.validCount += 1
                    score.textCount += 1
                    if commonCJKScalars.contains(unit) {
                        score.commonCJKCount += 1
                    }
                } else if unit < 0x0020 || (0x007F...0x009F).contains(unit) {
                    break
                } else {
                    // Valid code unit, but not a range typical of prose.
                    score.validCount += 1
                }
            }
        }

        return score
    }

    /// Unicode ranges that are common in prose. Hangul syllables are
    /// deliberately absent: GB18030's two-byte Chinese sequences often
    /// byte-swap into plausible Hangul, so counting Hangul as prose would let
    /// GB18030 files masquerade as UTF-16. Korean UTF-16 files still win via
    /// the NUL high-byte signal whenever they contain a newline or space.
    private static func isUTF16TextUnit(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x0009, 0x000A, 0x000D:
            return true
        case 0x0020...0x007E:
            return true
        case 0x00A0...0x024F, 0x2000...0x206F, 0x20A0...0x20CF,
             0x2100...0x214F, 0x2190...0x21FF, 0x2200...0x22FF,
             0x2500...0x257F, 0x25A0...0x25FF, 0x2600...0x27BF,
             0x3000...0x303F, 0x3040...0x30FF, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xF900...0xFAFF,
             0xFE30...0xFE4F, 0xFF00...0xFFEF:
            return true
        default:
            return false
        }
    }

    /// Frequent Han characters used only to break endianness ties on short
    /// BOM-less CJK strings. This is a heuristic, not a full frequency table.
    private static let commonCJKScalars: Set<UInt16> = Set(
        "的一是不了在人有我他这个们中来上大为和国地到以说时要就出会可也你对生能而子那得于着下自之年过发后作里用道行所然家种事成方多经去法学如都同现当没动面起看定天分还进好小部其些主样理心她本前开但因只从想实日军者意无力它与长把机十民第公此已工使情明性知全三又关点正业外将两高间由问很最重并物手应战向头文体政美相见被利什二等产或新己制身果加西斯月话合回特代内信表化老给世位次度门任常先海通教儿原东声提立及比员解水名真论处走义各入几口认条平系气题活尔更别打女变四神总何电数安少报才结反受目太量再感建务做接必场件计管期市直德资命山金指克许统区保至队形社便空决治展马科司五基眼书非则听白却界达光放强即像难且权思王象完设式色路记南品住告类求据程北边死张该交规万取拉格望觉术领共确传师观清今切院让识候带导争运笑飞风步改收根干造言联持组每济车亲极林服快办议往元英士证近失转夫令准布始怎呢存未远叫台单影具罗字爱击流备兵连汉字"
            .unicodeScalars
            .filter { $0.value <= 0xFFFF }
            .map { UInt16($0.value) }
    )

    // MARK: - Normalization

    private static func normalizeLineEndings(_ text: String) -> String {
        // `"\r\n"` is a single grapheme cluster, so check raw scalars rather
        // than `contains("\r")`.
        guard text.utf8.contains(0x0D) else { return text }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}
