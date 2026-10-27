import Foundation
import Testing

@testable import FileCompare

// MARK: - Helpers

/// Builds a `LoadedTextFile` without touching the file system.
private func makeFile(
    lines: [String],
    name: String,
    hadFinalNewline: Bool = true
) -> LoadedTextFile {
    var text = lines.joined(separator: "\n")
    if hadFinalNewline, !lines.isEmpty {
        text += "\n"
    }

    return LoadedTextFile(
        url: URL(fileURLWithPath: "/virtual/\(name)"),
        displayName: name,
        text: text,
        lines: lines,
        encodingName: "UTF-8",
        byteCount: text.utf8.count,
        hadFinalNewline: hadFinalNewline
    )
}

private func compare(
    _ leftLines: [String],
    _ rightLines: [String],
    options: DiffOptions = DiffOptions()
) throws -> DiffDocument {
    try DiffEngine.compare(
        left: makeFile(lines: leftLines, name: "left.txt"),
        right: makeFile(lines: rightLines, name: "right.txt"),
        options: options
    )
}

// MARK: - Tests

struct DiffEngineTests {
    @Test func identicalFilesProduceOnlyUnchangedRows() throws {
        let doc = try compare(
            ["alpha", "beta", "gamma"],
            ["alpha", "beta", "gamma"]
        )

        #expect(doc.isIdentical)
        #expect(doc.changeGroups.isEmpty)
        #expect(doc.rows.map(\.kind) == [.unchanged, .unchanged, .unchanged])
        #expect(doc.rows.map(\.id) == [0, 1, 2])
        #expect(doc.rows.map(\.leftLineNumber) == [1, 2, 3])
        #expect(doc.rows.map(\.rightLineNumber) == [1, 2, 3])
        #expect(doc.rows.allSatisfy { $0.changeGroup == nil })
        #expect(doc.rows[0].left?.text == "alpha")
        #expect(doc.rows[0].right?.text == "alpha")
    }

    @Test func modifiedLineEmphasisesChangedWords() throws {
        let doc = try compare(["The quick brown fox"], ["The quick red fox"])

        #expect(doc.isIdentical == false)
        #expect(doc.rows.count == 1)

        let row = try #require(doc.rows.first)
        #expect(row.kind == .modified)
        #expect(row.leftLineNumber == 1)
        #expect(row.rightLineNumber == 1)

        let left = try #require(row.left)
        let right = try #require(row.right)

        #expect(left.isLineChanged)
        #expect(right.isLineChanged)
        #expect(left.runs == [
            DiffRun("The quick "),
            DiffRun("brown", emphasis: .word),
            DiffRun(" fox"),
        ])
        #expect(right.runs == [
            DiffRun("The quick "),
            DiffRun("red", emphasis: .word),
            DiffRun(" fox"),
        ])
        #expect(left.text == "The quick brown fox")
        #expect(right.text == "The quick red fox")
    }

    @Test func chineseCharactersAreEmphasisedIndividually() throws {
        let oldLine = "我们今天去公园散步"
        let newLine = "我们明天去公园跑步"
        let doc = try compare([oldLine], [newLine])

        let row = try #require(doc.rows.first)
        #expect(row.kind == .modified)

        let left = try #require(row.left)
        let right = try #require(row.right)

        #expect(left.runs == [
            DiffRun("我们"),
            DiffRun("今", emphasis: .word),
            DiffRun("天去公园"),
            DiffRun("散", emphasis: .word),
            DiffRun("步"),
        ])
        #expect(right.runs == [
            DiffRun("我们"),
            DiffRun("明", emphasis: .word),
            DiffRun("天去公园"),
            DiffRun("跑", emphasis: .word),
            DiffRun("步"),
        ])
        #expect(left.text == oldLine)
        #expect(right.text == newLine)
    }

    @Test func insertionAddsOneSidedRow() throws {
        let doc = try compare(["a", "c"], ["a", "b", "c"])

        #expect(doc.rows.map(\.kind) == [.unchanged, .added, .unchanged])
        #expect(doc.changeGroups.map(\.rows) == [1..<2])

        let added = try #require(doc.rows.dropFirst().first)
        #expect(added.left == nil)
        #expect(added.rightLineNumber == 2)
        #expect(added.right?.isLineChanged == true)
        #expect(added.right?.text == "b")

        #expect(doc.rows[2].leftLineNumber == 2)
        #expect(doc.rows[2].rightLineNumber == 3)
        #expect(doc.rows[2].left?.isLineChanged == false)
    }

    @Test func deletionAddsOneSidedRow() throws {
        let doc = try compare(["a", "b", "c"], ["a", "c"])

        #expect(doc.rows.map(\.kind) == [.unchanged, .removed, .unchanged])
        #expect(doc.changeGroups.map(\.rows) == [1..<2])

        let removed = try #require(doc.rows.dropFirst().first)
        #expect(removed.right == nil)
        #expect(removed.leftLineNumber == 2)
        #expect(removed.left?.isLineChanged == true)
        #expect(removed.left?.runs == [DiffRun("b", emphasis: .word)])

        #expect(doc.rows[2].leftLineNumber == 3)
        #expect(doc.rows[2].rightLineNumber == 2)
    }

    @Test func multiLineReplacementIsOneChangeGroup() throws {
        let doc = try compare(
            ["one", "two", "three"],
            ["uno", "dos", "tres"]
        )

        #expect(doc.rows.count == 3)
        #expect(doc.rows.map(\.kind) == [.modified, .modified, .modified])
        #expect(doc.rows.map(\.leftLineNumber) == [1, 2, 3])
        #expect(doc.rows.map(\.rightLineNumber) == [1, 2, 3])
        #expect(doc.changeGroups.count == 1)
        #expect(doc.changeGroups.first?.rows == 0..<3)
        #expect(doc.changeGroups.first?.id == 0)
    }

    @Test func mixedBlockPairsByIndexAndLeavesExtraRemovalsOneSided() throws {
        let doc = try compare(
            ["start", "old1", "old2", "old3", "end"],
            ["start", "new1", "end"]
        )

        #expect(doc.rows.map(\.kind) == [.unchanged, .modified, .removed, .removed, .unchanged])
        #expect(doc.changeGroups.map(\.rows) == [1..<4])

        #expect(doc.rows[1].leftLineNumber == 2)
        #expect(doc.rows[1].rightLineNumber == 2)

        #expect(doc.rows[2].right == nil)
        #expect(doc.rows[2].leftLineNumber == 3)
        #expect(doc.rows[3].right == nil)
        #expect(doc.rows[3].leftLineNumber == 4)
    }

    @Test func blankLinesAreHandledLikeAnyOtherLine() throws {
        let doc = try compare(
            ["alpha", "", "gamma"],
            ["alpha", "delta", "gamma"]
        )

        #expect(doc.rows.map(\.kind) == [.unchanged, .modified, .unchanged])

        let row = try #require(doc.rows.dropFirst().first)
        #expect(row.leftLineNumber == 2)
        #expect(row.rightLineNumber == 2)

        let left = try #require(row.left)
        let right = try #require(row.right)
        #expect(left.text == "")
        #expect(right.text == "delta")
        #expect(left.isLineChanged)
        #expect(right.isLineChanged)
    }

    @Test func emptyFilesAndOneSidedEmptyFiles() throws {
        let empty = makeFile(lines: [], name: "empty.txt")

        let emptyDoc = try DiffEngine.compare(left: empty, right: empty, options: DiffOptions())
        #expect(emptyDoc.rows.isEmpty)
        #expect(emptyDoc.changeGroups.isEmpty)
        #expect(emptyDoc.isIdentical)

        let oneLine = makeFile(lines: ["x"], name: "one.txt")

        let addedDoc = try DiffEngine.compare(left: empty, right: oneLine, options: DiffOptions())
        #expect(addedDoc.rows.map(\.kind) == [.added])
        #expect(addedDoc.changeGroups.map(\.rows) == [0..<1])

        let added = try #require(addedDoc.rows.first)
        #expect(added.left == nil)
        #expect(added.leftLineNumber == nil)
        #expect(added.rightLineNumber == 1)
        #expect(added.right?.text == "x")

        let removedDoc = try DiffEngine.compare(left: oneLine, right: empty, options: DiffOptions())
        #expect(removedDoc.rows.map(\.kind) == [.removed])
        #expect(removedDoc.rows[0].leftLineNumber == 1)
        #expect(removedDoc.rows[0].right == nil)

        let blankDoc = try DiffEngine.compare(
            left: empty,
            right: makeFile(lines: [""], name: "blank.txt"),
            options: DiffOptions()
        )
        #expect(blankDoc.rows.map(\.kind) == [.added])
        #expect(blankDoc.rows[0].right?.text == "")
    }

    @Test func ignoreWhitespaceMatchesLinesAndKeepsDisplayText() throws {
        let left = makeFile(lines: ["    let x = 1;"], name: "ws-left.txt")
        let right = makeFile(lines: ["let  x=1;"], name: "ws-right.txt")

        let strict = try DiffEngine.compare(left: left, right: right, options: DiffOptions())
        #expect(strict.rows.map(\.kind) == [.modified])

        let relaxed = try DiffEngine.compare(
            left: left,
            right: right,
            options: DiffOptions(ignoreWhitespace: true, ignoreCase: false)
        )

        #expect(relaxed.isIdentical)
        #expect(relaxed.changeGroups.isEmpty)
        #expect(relaxed.rows.map(\.kind) == [.unchanged])

        let leftCell = try #require(relaxed.rows.first?.left)
        let rightCell = try #require(relaxed.rows.first?.right)
        #expect(leftCell.text == "    let x = 1;")
        #expect(rightCell.text == "let  x=1;")
        #expect(leftCell.isLineChanged == false)
        #expect(rightCell.isLineChanged == false)
    }

    @Test func ignoreCaseMatchesLinesAndWordEmphasis() throws {
        let left = makeFile(lines: ["Hello World"], name: "case-left.txt")
        let right = makeFile(lines: ["hello world"], name: "case-right.txt")

        let strict = try DiffEngine.compare(left: left, right: right, options: DiffOptions())
        #expect(strict.rows.map(\.kind) == [.modified])

        let relaxed = try DiffEngine.compare(
            left: left,
            right: right,
            options: DiffOptions(ignoreWhitespace: false, ignoreCase: true)
        )
        #expect(relaxed.isIdentical)
        #expect(relaxed.rows.map(\.kind) == [.unchanged])

        let relaxedLeft = try #require(relaxed.rows.first?.left)
        let relaxedRight = try #require(relaxed.rows.first?.right)
        #expect(relaxedLeft.runs == [DiffRun("Hello World")])
        #expect(relaxedRight.runs == [DiffRun("hello world")])

        // Only the truly different words are emphasised, and case is preserved
        // in the runs that survive.
        let edited = try DiffEngine.compare(
            left: makeFile(lines: ["Foo Bar"], name: "case-left-2.txt"),
            right: makeFile(lines: ["foo Baz"], name: "case-right-2.txt"),
            options: DiffOptions(ignoreWhitespace: false, ignoreCase: true)
        )

        let row = try #require(edited.rows.first)
        #expect(row.kind == .modified)

        let leftCell = try #require(row.left)
        let rightCell = try #require(row.right)
        #expect(leftCell.runs == [DiffRun("Foo "), DiffRun("Bar", emphasis: .word)])
        #expect(rightCell.runs == [DiffRun("foo "), DiffRun("Baz", emphasis: .word)])
    }

    @Test func ignoreWhitespaceAppliesToWordEmphasis() throws {
        let doc = try DiffEngine.compare(
            left: makeFile(lines: ["foo  bar baz"], name: "we-left.txt"),
            right: makeFile(lines: ["foo bar qux"], name: "we-right.txt"),
            options: DiffOptions(ignoreWhitespace: true, ignoreCase: false)
        )

        let row = try #require(doc.rows.first)
        #expect(row.kind == .modified)

        let left = try #require(row.left)
        let right = try #require(row.right)

        #expect(left.text == "foo  bar baz")
        #expect(right.text == "foo bar qux")
        #expect(left.runs.contains(DiffRun("baz", emphasis: .word)))
        #expect(right.runs.contains(DiffRun("qux", emphasis: .word)))

        let emphasisedWhitespace = left.runs.contains { run in
            run.emphasis == .word && run.text.contains(" ")
        }
        #expect(emphasisedWhitespace == false)
    }

    @Test func changeGroupsUseContiguousHalfOpenRanges() throws {
        let doc = try compare(
            ["a", "b", "c", "d", "e", "f", "g"],
            ["a", "B", "c", "d", "e", "F", "g"]
        )

        #expect(doc.rows.map(\.kind) == [
            .unchanged, .modified, .unchanged,
            .unchanged, .unchanged, .modified,
            .unchanged,
        ])
        #expect(doc.changeGroups.map(\.id) == [0, 1])
        #expect(doc.changeGroups.map(\.rows) == [1..<2, 5..<6])
        #expect(doc.rows[0].changeGroup == nil)
        #expect(doc.rows[1].changeGroup == 0)
        #expect(doc.rows[5].changeGroup == 1)
        #expect(doc.changeGroups[1].firstRow == 5)
        #expect(doc.changeGroups[1].lastRow == 5)
    }

    @Test func veryLongLinesSkipWordDiff() throws {
        let oldLine = String(repeating: "!", count: DiffEngine.maxTokensForWordDiff + 1)
        let newLine = String(repeating: "?", count: DiffEngine.maxTokensForWordDiff + 1)

        let doc = try compare([oldLine], [newLine])
        let row = try #require(doc.rows.first)
        let left = try #require(row.left)
        let right = try #require(row.right)

        #expect(left.runs == [DiffRun(oldLine, emphasis: .word)])
        #expect(right.runs == [DiffRun(newLine, emphasis: .word)])
        #expect(left.isLineChanged)
        #expect(right.isLineChanged)
    }

    @Test func tokenLimitBoundaryStillRunsWordDiff() throws {
        // 1 word token plus (limit - 1) punctuation tokens == exactly the limit.
        let oldTail = String(repeating: "!", count: DiffEngine.maxTokensForWordDiff - 1)
        let newTail = String(repeating: "?", count: DiffEngine.maxTokensForWordDiff - 1)
        let oldLine = "x" + oldTail
        let newLine = "x" + newTail

        #expect(Tokenizer.tokenize(oldLine).count == DiffEngine.maxTokensForWordDiff)
        #expect(Tokenizer.tokenize(newLine).count == DiffEngine.maxTokensForWordDiff)

        let doc = try compare([oldLine], [newLine])
        let row = try #require(doc.rows.first)
        let left = try #require(row.left)
        let right = try #require(row.right)

        // The shared "x" stays normal, so the token diff really did run.
        #expect(left.runs == [DiffRun("x"), DiffRun(oldTail, emphasis: .word)])
        #expect(right.runs == [DiffRun("x"), DiffRun(newTail, emphasis: .word)])
        #expect(left.text == oldLine)
        #expect(right.text == newLine)
    }

    @Test func tokenLimitAboveBoundarySkipsWordDiff() throws {
        let oldLine = "x" + String(repeating: "!", count: DiffEngine.maxTokensForWordDiff)
        let newLine = "x" + String(repeating: "?", count: DiffEngine.maxTokensForWordDiff)

        #expect(Tokenizer.tokenize(oldLine).count == DiffEngine.maxTokensForWordDiff + 1)
        #expect(Tokenizer.tokenize(newLine).count == DiffEngine.maxTokensForWordDiff + 1)

        let doc = try compare([oldLine], [newLine])
        let row = try #require(doc.rows.first)
        let left = try #require(row.left)
        let right = try #require(row.right)

        #expect(left.runs == [DiffRun(oldLine, emphasis: .word)])
        #expect(right.runs == [DiffRun(newLine, emphasis: .word)])
        #expect(left.text == oldLine)
        #expect(right.text == newLine)
    }

    @Test func overlongLinesSkipTokenizationEvenWithFewTokens() throws {
        // Three tokens only, but far above the byte threshold, so the byte
        // pre-check must reject the pair before tokenizing it.
        let body = String(repeating: "a", count: DiffEngine.maxBytesForWordDiff + 1_000)
        let oldLine = body + " b"
        let newLine = body + " c"

        #expect(Tokenizer.tokenize(oldLine).count == 3)
        #expect(oldLine.utf8.count > DiffEngine.maxBytesForWordDiff)

        let doc = try compare([oldLine], [newLine])
        let row = try #require(doc.rows.first)
        let left = try #require(row.left)
        let right = try #require(row.right)

        #expect(left.runs == [DiffRun(oldLine, emphasis: .word)])
        #expect(right.runs == [DiffRun(newLine, emphasis: .word)])
        #expect(left.text == oldLine)
        #expect(right.text == newLine)
    }

    @Test func veryLargeDissimilarFilesUseLinearFallback() throws {
        let lineCount = 30_000
        let leftLines = Array(repeating: "left", count: lineCount)
        let rightLines = Array(repeating: "right", count: lineCount)

        let doc = try compare(leftLines, rightLines)

        #expect(doc.isIdentical == false)
        #expect(doc.rows.count == lineCount)
        #expect(doc.rows.map(\.id) == Array(0..<lineCount))
        #expect(doc.rows.allSatisfy { $0.kind == .modified })
        #expect(doc.rows.map(\.leftLineNumber) == Array(1...lineCount))
        #expect(doc.rows.map(\.rightLineNumber) == Array(1...lineCount))
        #expect(doc.rows.allSatisfy { $0.left?.text == "left" })
        #expect(doc.rows.allSatisfy { $0.right?.text == "right" })
        #expect(doc.changeGroups.count == 1)
        #expect(doc.changeGroups.first?.rows == 0..<lineCount)
    }

    @Test func largeUniqueFilesKeepUnchangedTailUnchanged() throws {
        let count = 30_000
        let left = (0..<count).map { "line \($0)" }
        var right = left
        right[0] = "changed head"
        right[count - 1] = "changed tail"

        let doc = try compare(left, right)

        #expect(doc.rows.count == count)
        #expect(doc.rows[0].kind == .modified)
        #expect(doc.rows[1..<(count - 1)].allSatisfy { $0.kind == .unchanged })
        #expect(doc.rows[count - 1].kind == .modified)
        #expect(doc.changeGroups.count == 2)
        #expect(doc.changeGroups[0].rows == 0..<1)
        #expect(doc.changeGroups[1].rows == (count - 1)..<count)
    }

    @Test func largeUniqueFileChangesInTailAreStillColoured() throws {
        let count = 30_000
        let left = (0..<count).map { "line \($0)" }
        var right = left
        for index in (count - 5_000)..<count where index % 100 == 0 {
            right[index] = "changed \(index)"
        }

        let doc = try compare(left, right)

        #expect(doc.rows.prefix(count - 5_000).allSatisfy { $0.kind == .unchanged })
        for index in (count - 5_000)..<count {
            let expected: DiffRowKind = index % 100 == 0 ? .modified : .unchanged
            #expect(doc.rows[index].kind == expected)
        }
    }

    @Test func linearFallbackTrimsPrefixAndSuffixAndKeepsLineNumbers() throws {
        let prefixCount = 1_000
        let leftMiddleCount = 19_001
        let rightMiddleCount = 19_000
        let suffixCount = 1_000

        let prefix = (0..<prefixCount).map { "common \($0)" }
        let leftMiddle = (0..<leftMiddleCount).map { "old \($0)" }
        let rightMiddle = (0..<rightMiddleCount).map { "new \($0)" }
        let suffix = (0..<suffixCount).map { "tail \($0)" }

        let leftLines = prefix + leftMiddle + suffix
        let rightLines = prefix + rightMiddle + suffix

        // Force the bounded path: min(count) is above the Myers limit.
        #expect(min(leftLines.count, rightLines.count) > DiffEngine.maxLinesForMyersDiff)

        let doc = try compare(leftLines, rightLines)

        let leftTotal = leftLines.count
        let rightTotal = rightLines.count
        let firstChangedRow = prefixCount
        let lastChangedRow = prefixCount + leftMiddleCount // exclusive

        #expect(doc.rows.count == leftTotal)
        #expect(doc.rows.map(\.id) == Array(0..<leftTotal))
        #expect(doc.rows.map(\.leftLineNumber) == Array(1...leftTotal))
        // The single left-only row has no right cell, but every right line is
        // still represented exactly once.
        #expect(doc.rows.compactMap(\.rightLineNumber) == Array(1...rightTotal))
        #expect(doc.rows.filter { $0.rightLineNumber == nil }.count == 1)

        #expect(doc.rows[0].kind == .unchanged)
        #expect(doc.rows[prefixCount - 1].kind == .unchanged)
        #expect(doc.rows[firstChangedRow].kind == .modified)
        #expect(doc.rows[lastChangedRow - 2].kind == .modified)
        // One left-only row: left middle has one line more than the right one,
        // so the extra removal is the last row of the change block.
        #expect(doc.rows[lastChangedRow - 1].kind == .removed)
        #expect(doc.rows[lastChangedRow].kind == .unchanged)
        #expect(doc.rows[leftTotal - 1].kind == .unchanged)

        #expect(doc.changeGroups.count == 1)
        #expect(doc.changeGroups.first?.rows == firstChangedRow..<(firstChangedRow + leftMiddleCount))
        #expect(doc.isIdentical == false)
    }
}
