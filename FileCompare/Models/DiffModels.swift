import Foundation

enum ComparisonSide: String, Sendable, CaseIterable, Hashable {
    case left
    case right
}

struct DiffOptions: Hashable, Sendable {
    var ignoreWhitespace = false
    var ignoreCase = false
}

enum DiffEmphasis: Hashable, Sendable {
    case normal
    case word
}

struct DiffRun: Hashable, Sendable {
    var text: String
    var emphasis: DiffEmphasis

    init(_ text: String, emphasis: DiffEmphasis = .normal) {
        self.text = text
        self.emphasis = emphasis
    }
}

struct DiffCell: Hashable, Sendable {
    var lineNumber: Int
    var runs: [DiffRun]
    var isLineChanged: Bool

    var text: String {
        runs.map(\.text).joined()
    }

    init(lineNumber: Int, runs: [DiffRun], isLineChanged: Bool) {
        self.lineNumber = lineNumber
        self.runs = runs
        self.isLineChanged = isLineChanged
    }

    init(lineNumber: Int, text: String, isLineChanged: Bool) {
        self.init(
            lineNumber: lineNumber,
            runs: [DiffRun(text)],
            isLineChanged: isLineChanged
        )
    }
}

enum DiffRowKind: Hashable, Sendable {
    case unchanged
    case modified
    case removed
    case added
}

struct DiffRow: Identifiable, Hashable, Sendable {
    var id: Int
    var kind: DiffRowKind
    var left: DiffCell?
    var right: DiffCell?
    var changeGroup: Int?

    var leftLineNumber: Int? { left?.lineNumber }
    var rightLineNumber: Int? { right?.lineNumber }
    var isChanged: Bool { kind != .unchanged }
}

struct DiffChangeGroup: Identifiable, Hashable, Sendable {
    var id: Int
    /// Half-open range of row indices.
    var rows: Range<Int>

    var firstRow: Int { rows.lowerBound }
    var lastRow: Int { max(rows.lowerBound, rows.upperBound - 1) }
}

struct DiffDocument: Sendable {
    var left: LoadedTextFile
    var right: LoadedTextFile
    var rows: [DiffRow]
    var changeGroups: [DiffChangeGroup]
    var options: DiffOptions
    var isIdentical: Bool

    var leftMaxLineNumber: Int { left.lineCount }
    var rightMaxLineNumber: Int { right.lineCount }
    var maxLineNumber: Int { max(left.lineCount, right.lineCount) }

    /// Swaps both sides without recomputing the diff. Removed rows become
    /// added rows, added rows become removed rows, and word emphasis moves
    /// with its text.
    func swapped() -> DiffDocument {
        let swappedRows = rows.map { row -> DiffRow in
            let kind: DiffRowKind
            switch row.kind {
            case .unchanged: kind = .unchanged
            case .modified: kind = .modified
            case .removed: kind = .added
            case .added: kind = .removed
            }
            return DiffRow(
                id: row.id,
                kind: kind,
                left: row.right,
                right: row.left,
                changeGroup: row.changeGroup
            )
        }

        return DiffDocument(
            left: right,
            right: left,
            rows: swappedRows,
            changeGroups: changeGroups,
            options: options,
            isIdentical: isIdentical
        )
    }
}
