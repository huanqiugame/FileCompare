import Foundation
import Testing

@testable import FileCompare

struct TextFileLoaderTests {
    // MARK: - Helpers

    private static let placeholderURL = URL(fileURLWithPath: "/tmp/FileCompareTests/sample.txt")

    private func decode(_ data: Data, name: String = "sample.txt") throws -> LoadedTextFile {
        let url = URL(fileURLWithPath: "/tmp/FileCompareTests/\(name)")
        return try TextFileLoader.decode(data: data, url: url)
    }

    /// Creates a unique temporary directory containing one file and returns
    /// the file URL. Callers remove `url.deletingLastPathComponent()`.
    private static func makeTempFile(_ data: Data, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private static func removeContainingDirectory(of url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Newlines

    @Test func utf8WithoutFinalNewline() throws {
        let loaded = try decode(Data("alpha\nbeta".utf8))

        #expect(loaded.text == "alpha\nbeta")
        #expect(loaded.lines == ["alpha", "beta"])
        #expect(loaded.hadFinalNewline == false)
        #expect(loaded.encodingName == "UTF-8")
    }

    @Test func utf8WithFinalNewline() throws {
        let loaded = try decode(Data("alpha\nbeta\n".utf8))

        #expect(loaded.text == "alpha\nbeta\n")
        #expect(loaded.lines == ["alpha", "beta"])
        #expect(loaded.hadFinalNewline == true)
    }

    @Test func crlfIsNormalizedToLF() throws {
        let loaded = try decode(Data("alpha\r\nbeta\r\n\r\ngamma\r\n".utf8))

        #expect(loaded.text == "alpha\nbeta\n\ngamma\n")
        #expect(loaded.lines == ["alpha", "beta", "", "gamma"])
        #expect(loaded.hadFinalNewline == true)
    }

    @Test func loneCarriageReturnsAreNormalized() throws {
        let loaded = try decode(Data("alpha\rbeta\r".utf8))

        #expect(loaded.text == "alpha\nbeta\n")
        #expect(loaded.lines == ["alpha", "beta"])
        #expect(loaded.hadFinalNewline == true)
    }

    @Test func mixedLineEndingsAreNormalized() throws {
        let loaded = try decode(Data("a\r\nb\rc\n".utf8))

        #expect(loaded.text == "a\nb\nc\n")
        #expect(loaded.lines == ["a", "b", "c"])
    }

    // MARK: - Encodings

    @Test func utf8ByteOrderMarkIsStripped() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("héllo\n".utf8))

        let loaded = try decode(data)

        #expect(loaded.text == "héllo\n")
        #expect(loaded.encodingName == "UTF-8")
        #expect(loaded.lines == ["héllo"])
    }

    @Test func utf16LittleEndianWithByteOrderMark() throws {
        var data = Data([0xFF, 0xFE])
        data.append(try #require("Hello\n".data(using: .utf16LittleEndian)))

        let loaded = try decode(data)

        #expect(loaded.text == "Hello\n")
        #expect(loaded.encodingName == "UTF-16 LE")
        #expect(loaded.lines == ["Hello"])
        #expect(loaded.byteCount == data.count)
    }

    @Test func utf16BigEndianWithByteOrderMark() throws {
        var data = Data([0xFE, 0xFF])
        data.append(try #require("Hello\n".data(using: .utf16BigEndian)))

        let loaded = try decode(data)

        #expect(loaded.text == "Hello\n")
        #expect(loaded.encodingName == "UTF-16 BE")
        #expect(loaded.lines == ["Hello"])
    }

    @Test func gb18030ChineseText() throws {
        let text = "你好，世界\n"
        let data = try #require(text.data(using: TextFileLoader.gb18030))

        let loaded = try decode(data)

        #expect(loaded.text == text)
        #expect(loaded.encodingName == "GB18030")
        #expect(loaded.lines == ["你好，世界"])
        #expect(loaded.byteCount == data.count)
    }

    @Test func gb18030EvenLengthChineseText() throws {
        // Even byte counts are ambiguous with UTF-16, and GB18030's two-byte
        // sequences can look like plausible UTF-16 in one endianness.
        let text = "你好世界"
        let data = try #require(text.data(using: TextFileLoader.gb18030))

        let loaded = try decode(data)

        #expect(loaded.text == text)
        #expect(loaded.encodingName == "GB18030")
    }

    // MARK: - BOM-less UTF-16

    @Test func bomlessUTF16LittleEndianASCII() throws {
        let text = "Hello, world!\n"
        let data = try #require(text.data(using: .utf16LittleEndian))

        let loaded = try decode(data)

        #expect(loaded.text == text)
        #expect(loaded.encodingName == "UTF-16 LE")
        #expect(loaded.lines == ["Hello, world!"])
        #expect(loaded.hadFinalNewline == true)
    }

    @Test func bomlessUTF16BigEndianASCII() throws {
        let text = "Hello, world!\n"
        let data = try #require(text.data(using: .utf16BigEndian))

        let loaded = try decode(data)

        #expect(loaded.text == text)
        #expect(loaded.encodingName == "UTF-16 BE")
        #expect(loaded.lines == ["Hello, world!"])
    }

    @Test func bomlessUTF16LittleEndianChinese() throws {
        let text = "你好，世界\n"
        let data = try #require(text.data(using: .utf16LittleEndian))

        let loaded = try decode(data)

        #expect(loaded.text == text)
        #expect(loaded.encodingName == "UTF-16 LE")
        #expect(loaded.lines == ["你好，世界"])
    }

    @Test func bomlessUTF16BigEndianChinese() throws {
        let text = "你好，世界\n"
        let data = try #require(text.data(using: .utf16BigEndian))

        let loaded = try decode(data)

        #expect(loaded.text == text)
        #expect(loaded.encodingName == "UTF-16 BE")
        #expect(loaded.lines == ["你好，世界"])
    }

    @Test func bomlessUTF16ChineseWithoutTrailingNewline() throws {
        // No newline means no NUL high byte to lean on, so this exercises the
        // Han-heavy tie-breaker.
        let text = "汉字"
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let data = try #require(text.data(using: encoding))
            let loaded = try decode(data)

            #expect(loaded.text == text)
            #expect(loaded.encodingName == (encoding == .utf16LittleEndian ? "UTF-16 LE" : "UTF-16 BE"))
        }
    }

    @Test func ordinaryUTF8IsNotMistakenForUTF16() throws {
        // Eight bytes with an even length; a naive UTF-16 sniff sees plausible
        // bytes in both endiannesses.
        for text in ["a,b;c:d\n", "hello\n", "function test() {}\n"] {
            let loaded = try decode(Data(text.utf8))
            #expect(loaded.text == text)
            #expect(loaded.encodingName == "UTF-8")
        }
    }

    @Test func utf16ByteOrderMarkWithOddPayloadIsRejected() throws {
        var littleEndian = Data([0xFF, 0xFE])
        littleEndian.append(contentsOf: [0x41, 0x00, 0x42])
        #expect(throws: FileLoadError.unsupportedEncoding) {
            _ = try self.decode(littleEndian)
        }

        var bigEndian = Data([0xFE, 0xFF])
        bigEndian.append(contentsOf: [0x41, 0x00, 0x42])
        #expect(throws: FileLoadError.unsupportedEncoding) {
            _ = try self.decode(bigEndian)
        }
    }

    @Test func utf32ByteOrderMarksAreRejected() throws {
        let payloads: [(String, [UInt8])] = [
            ("UTF-32 LE", [0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00]),
            ("UTF-32 BE", [0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x41])
        ]

        for (_, bytes) in payloads {
            #expect(throws: FileLoadError.unsupportedEncoding) {
                _ = try self.decode(Data(bytes))
            }
        }
    }

    @Test func undecodableBytesAreRejected() throws {
        #expect(throws: FileLoadError.unsupportedEncoding) {
            _ = try self.decode(Data([0xFF, 0xFF, 0xFF]))
        }
    }

    // MARK: - Binary detection

    @Test func nulBytesAreTreatedAsBinary() throws {
        #expect(throws: FileLoadError.binary) {
            _ = try self.decode(Data([0x41, 0x00, 0x42]))
        }
    }

    @Test func manyControlBytesAreTreatedAsBinary() throws {
        #expect(throws: FileLoadError.binary) {
            _ = try self.decode(Data(repeating: 0x07, count: 64))
        }
    }

    @Test func nulBytesBeyondSniffWindowAreTreatedAsBinary() throws {
        var data = Data(repeating: 0x41, count: TextFileLoader.binarySniffByteCount + 64)
        data.append(0x00)
        data.append(contentsOf: Data(repeating: 0x42, count: 16))

        #expect(throws: FileLoadError.binary) {
            _ = try self.decode(data)
        }
    }

    // MARK: - Empty content

    @Test func emptyFileHasNoLines() throws {
        let loaded = try decode(Data())

        #expect(loaded.text.isEmpty)
        #expect(loaded.lines.isEmpty)
        #expect(loaded.hadFinalNewline == false)
        #expect(loaded.byteCount == 0)
    }

    @Test func newlineOnlyFileHasOneEmptyLine() throws {
        let loaded = try decode(Data("\n".utf8))

        #expect(loaded.text == "\n")
        #expect(loaded.lines == [""])
        #expect(loaded.lineCount == 1)
        #expect(loaded.hadFinalNewline == true)
    }

    @Test func consecutiveTrailingNewlinesKeepEmptyLines() throws {
        let loaded = try decode(Data("a\n\n".utf8))

        #expect(loaded.lines == ["a", ""])
        #expect(loaded.hadFinalNewline == true)
    }

    // MARK: - File metadata

    @Test func readReportsDisplayNameAndByteCount() throws {
        let contents = "alpha\nbeta\n"
        let data = Data(contents.utf8)
        let url = try Self.makeTempFile(data, name: "notes.txt")
        defer { Self.removeContainingDirectory(of: url) }

        let loaded = try TextFileLoader.read(url: url)

        #expect(loaded.url == url)
        #expect(loaded.displayName == "notes.txt")
        #expect(loaded.byteCount == data.count)
        #expect(loaded.encodingName == "UTF-8")
        #expect(loaded.lines == ["alpha", "beta"])
        #expect(loaded.hadFinalNewline == true)
        #expect(loaded.line(at: 1) == "beta")
        #expect(loaded.line(at: 2) == nil)
    }

    @Test func directoriesAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: FileLoadError.notAFile) {
            _ = try TextFileLoader.read(url: directory)
        }
    }

    @Test func missingFilesAreUnreadable() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareTests-\(UUID().uuidString).txt")

        #expect(throws: FileLoadError.unreadable) {
            _ = try TextFileLoader.read(url: url)
        }
    }

    // MARK: - Limits

    @Test func filesLargerThanLimitAreRejected() throws {
        let url = try Self.makeTempFile(Data("a".utf8), name: "large.txt")
        defer { Self.removeContainingDirectory(of: url) }

        // Truncating past the end creates a sparse file, so this stays cheap.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(TextFileLoader.maximumByteCount + 1))
        try handle.close()

        #expect(throws: FileLoadError.tooLarge(bytes: TextFileLoader.maximumByteCount + 1)) {
            _ = try TextFileLoader.read(url: url)
        }
    }

    @Test func tooManyLinesAreRejected() throws {
        let data = Data(repeating: 0x0A, count: TextFileLoader.maximumLineCount + 1)

        #expect(throws: FileLoadError.tooManyLines(count: TextFileLoader.maximumLineCount + 1)) {
            _ = try self.decode(data)
        }
    }

    @Test func readUsesFreshMetadataWhenAFileGrows() throws {
        let url = try Self.makeTempFile(Data("alpha\n".utf8), name: "growing.txt")
        defer { Self.removeContainingDirectory(of: url) }

        _ = try TextFileLoader.read(url: url)

        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(TextFileLoader.maximumByteCount + 1))
        try handle.close()

        // Reusing the same URL value exposes stale URL resource caches.
        #expect(throws: FileLoadError.tooLarge(bytes: TextFileLoader.maximumByteCount + 1)) {
            _ = try TextFileLoader.read(url: url)
        }
    }

    @Test func readUsesFreshMetadataWhenAFileShrinks() throws {
        let url = try Self.makeTempFile(Data("alpha\n".utf8), name: "shrinking.txt")
        defer { Self.removeContainingDirectory(of: url) }

        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(TextFileLoader.maximumByteCount + 1))
        try handle.close()

        #expect(throws: FileLoadError.tooLarge(bytes: TextFileLoader.maximumByteCount + 1)) {
            _ = try TextFileLoader.read(url: url)
        }

        let rewritten = try FileHandle(forWritingTo: url)
        try rewritten.truncate(atOffset: 0)
        try rewritten.write(contentsOf: Data("beta\n".utf8))
        try rewritten.close()

        let loaded = try TextFileLoader.read(url: url)
        #expect(loaded.text == "beta\n")
        #expect(loaded.byteCount == 5)
    }

    @Test func overlongLineIsRejected() throws {
        let data = Data((String(repeating: "a", count: TextFileLoader.maximumLineLength + 1) + "\n").utf8)

        #expect(throws: FileLoadError.lineTooLong(length: TextFileLoader.maximumLineLength + 1)) {
            _ = try self.decode(data)
        }
    }

    @Test func lineAtLengthLimitIsAccepted() throws {
        let line = String(repeating: "a", count: TextFileLoader.maximumLineLength)
        let loaded = try decode(Data((line + "\n").utf8))

        #expect(loaded.lines == [line])
    }
}
