import Foundation

enum FileLoadError: Error, Equatable, Sendable {
    case notAFile
    case unreadable
    case tooLarge(bytes: Int)
    case tooManyLines(count: Int)
    case lineTooLong(length: Int)
    case binary
    case unsupportedEncoding
    case emptySelection
}
