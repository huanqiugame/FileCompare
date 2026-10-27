import Foundation
import Testing

@testable import FileCompare

@Suite(.serialized)
@MainActor
struct ComparisonSessionTests {
    private func makeFiles() throws -> (directory: URL, left: URL, right: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let left = directory.appendingPathComponent("left.txt")
        let right = directory.appendingPathComponent("right.txt")
        try "alpha\nbravo\ncharlie\n".write(to: left, atomically: true, encoding: .utf8)
        try "alpha\nbravo changed\ncharlie\ndelta\n".write(to: right, atomically: true, encoding: .utf8)
        return (directory, left, right)
    }

    private func waitForLoad(_ session: ComparisonSession) async {
        for _ in 0..<200 {
            if session.document != nil, !session.isLoading { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for comparison session to load")
    }

    @Test func loadsAndSwapsWithoutRecomputing() async throws {
        let files = try makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let session = ComparisonSession(leftURL: files.left, rightURL: files.right, settings: AppSettings.shared)
        session.load()
        await waitForLoad(session)

        let document = try #require(session.document)
        #expect(session.title == "left.txt vs right.txt")
        #expect(document.changeGroups.count == 2)
        #expect(session.changeCount == 2)
        #expect(session.errorMessage == nil)

        let beforeRows = document.rows
        session.swap()

        let swapped = try #require(session.document)
        #expect(session.title == "right.txt vs left.txt")
        #expect(swapped.rows.count == beforeRows.count)
        #expect(swapped.rows.first?.left?.text == beforeRows.first?.right?.text)
        #expect(swapped.rows.first?.right?.text == beforeRows.first?.left?.text)

        session.setAutoReload(false)
    }

    @Test func changeNavigationCyclesAndPublishesScrollRequests() async throws {
        let files = try makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let session = ComparisonSession(leftURL: files.left, rightURL: files.right, settings: AppSettings.shared)
        session.load()
        await waitForLoad(session)

        #expect(session.changeCount == 2)
        #expect(session.currentChangeIndex == -1)

        session.nextChange()
        #expect(session.currentChangeIndex == 0)
        #expect(session.scrollRequest != nil)
        #expect(session.highlightedRowID != nil)

        session.nextChange()
        #expect(session.currentChangeIndex == 1)
        session.previousChange()
        #expect(session.currentChangeIndex == 0)
        session.previousChange()
        #expect(session.currentChangeIndex == 1)

        session.setAutoReload(false)
    }

    @Test func findFindsBothSidesAndCycles() async throws {
        let files = try makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let session = ComparisonSession(leftURL: files.left, rightURL: files.right, settings: AppSettings.shared)
        session.load()
        await waitForLoad(session)

        session.presentFindBar()
        session.setFindQuery("bravo")
        #expect(session.findMatchCount == 2)
        #expect(session.currentFindIndex == 0)

        session.findNext()
        #expect(session.currentFindIndex == 1)
        session.findNext()
        #expect(session.currentFindIndex == 0)
        session.findPrevious()
        #expect(session.currentFindIndex == 1)

        session.setFindQuery("")
        #expect(session.findMatchCount == 0)
        session.dismissFindBar()
        #expect(session.isFindBarVisible == false)

        session.setAutoReload(false)
    }

    @Test func ignoreWhitespaceReloadsWithFewerChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let left = directory.appendingPathComponent("left.txt")
        let right = directory.appendingPathComponent("right.txt")
        try "one   two\nsame\n".write(to: left, atomically: true, encoding: .utf8)
        try "one two\nsame\n".write(to: right, atomically: true, encoding: .utf8)

        let session = ComparisonSession(leftURL: left, rightURL: right, settings: AppSettings.shared)
        session.load()
        await waitForLoad(session)
        #expect(session.changeCount == 1)

        session.setIgnoreWhitespace(true)
        for _ in 0..<200 {
            if !session.isLoading, session.document?.options.ignoreWhitespace == true { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.changeCount == 0)
        #expect(session.document?.options.ignoreWhitespace == true)

        session.setAutoReload(false)
    }
}
