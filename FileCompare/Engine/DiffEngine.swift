import Foundation

/// Computes a line-level diff with word-level emphasis inside changed lines.
///
/// The algorithm is deliberately thin on top of Foundation:
/// 1. Each line is reduced to a comparison key (`ignoreWhitespace` removes all
///    whitespace, `ignoreCase` lowercases). The keys are diffed with
///    `CollectionDifference`, i.e. Apple's Myers implementation. Very large
///    inputs fall back to a linear prefix/suffix pairing so a compare can never
///    stall for minutes (see ``maxLinesForMyersDiff``).
/// 2. Removals and insertions are grouped into contiguous change blocks. A
///    block pairs its `n`th removed line with its `n`th inserted line; leftovers
///    become one-sided rows.
/// 3. Each paired line is tokenized (see ``Tokenizer``) and the token keys are
///    diffed with `CollectionDifference` again to find the emphasised words.
///    Over-long lines or token lists skip this step and mark the whole line.
///
/// Display text is never normalized: keys are only used for matching, every
/// cell is rebuilt from the original line characters.
struct DiffEngine: Sendable {
    /// Lines longer than this many UTF-8 bytes skip tokenization and word-level
    /// diffing entirely.
    ///
    /// The byte check happens *before* ``Tokenizer`` runs, so a pathological
    /// multi-megabyte line can never be expanded into millions of tokens just to
    /// be discarded by the token limit below.
    static let maxBytesForWordDiff = 8_000

    /// Lines with more tokens than this skip word-level diffing, which keeps a
    /// pathological single-line file from turning into a quadratic comparison.
    ///
    /// The limit leaves headroom for prose and code lines while keeping the
    /// worst case (`limit` × `limit` tokens) well under a tenth of a second.
    static let maxTokensForWordDiff = 2_000

    /// Myers line diffing is `O(n·m)` and cannot be cancelled. Above either
    /// bound the engine uses a linear fallback instead.
    static let maxLinesForMyersDiff = 20_000

    /// Combined line count above which the linear fallback is used.
    static let maxCombinedLinesForMyersDiff = 40_000

    /// Convenience entry point for callers that prefer an instance.
    ///
    /// Diffing is stateless and thread-safe, so this simply forwards to the
    /// static implementation.
    func compare(
        left: LoadedTextFile,
        right: LoadedTextFile,
        options: DiffOptions = DiffOptions()
    ) throws -> DiffDocument {
        try Self.compare(left: left, right: right, options: options)
    }

    /// Compares two loaded files and produces display-ready rows.
    ///
    /// - Parameters:
    ///   - left: The file shown on the left side.
    ///   - right: The file shown on the right side.
    ///   - options: Normalization used for line matching and word emphasis.
    /// - Returns: A document whose rows are ordered top to bottom, have
    ///   sequential ids starting at 0, and whose changed rows belong to at most
    ///   one ``DiffChangeGroup``.
    ///
    /// The signature is `throws` because large compares are cancellable:
    /// ``CancellationError`` is propagated when the surrounding task is
    /// cancelled while laying out rows or running the bounded fallback.
    static func compare(
        left: LoadedTextFile,
        right: LoadedTextFile,
        options: DiffOptions = DiffOptions()
    ) throws -> DiffDocument {
        let leftLines = left.lines
        let rightLines = right.lines
        let edits = try lineEdits(from: leftLines, to: rightLines, options: options)

        let removedOffsets = edits.removed
        let insertedOffsets = edits.inserted

        var rows: [DiffRow] = []
        rows.reserveCapacity(leftLines.count + insertedOffsets.count)

        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < leftLines.count || rightIndex < rightLines.count {
            try Task.checkCancellation()

            let leftIsRemoved = leftIndex < leftLines.count && removedOffsets.contains(leftIndex)
            let rightIsInserted = rightIndex < rightLines.count && insertedOffsets.contains(rightIndex)

            if leftIsRemoved || rightIsInserted {
                var removed: [Int] = []
                var inserted: [Int] = []

                while leftIndex < leftLines.count, removedOffsets.contains(leftIndex) {
                    removed.append(leftIndex)
                    leftIndex += 1
                }
                while rightIndex < rightLines.count, insertedOffsets.contains(rightIndex) {
                    inserted.append(rightIndex)
                    rightIndex += 1
                }

                appendChangeRows(
                    removed: removed,
                    inserted: inserted,
                    leftLines: leftLines,
                    rightLines: rightLines,
                    options: options,
                    rows: &rows
                )
            } else if leftIndex < leftLines.count, rightIndex < rightLines.count {
                // Both positions are part of the common subsequence.
                rows.append(
                    DiffRow(
                        id: rows.count,
                        kind: .unchanged,
                        left: DiffCell(
                            lineNumber: leftIndex + 1,
                            text: leftLines[leftIndex],
                            isLineChanged: false
                        ),
                        right: DiffCell(
                            lineNumber: rightIndex + 1,
                            text: rightLines[rightIndex],
                            isLineChanged: false
                        ),
                        changeGroup: nil
                    )
                )
                leftIndex += 1
                rightIndex += 1
            } else if leftIndex < leftLines.count {
                // Defensive: a well-formed difference never leaves unpaired
                // lines on one side only, but never loop forever if it does.
                appendChangeRows(
                    removed: [leftIndex],
                    inserted: [],
                    leftLines: leftLines,
                    rightLines: rightLines,
                    options: options,
                    rows: &rows
                )
                leftIndex += 1
            } else {
                appendChangeRows(
                    removed: [],
                    inserted: [rightIndex],
                    leftLines: leftLines,
                    rightLines: rightLines,
                    options: options,
                    rows: &rows
                )
                rightIndex += 1
            }
        }

        let changeGroups = assignChangeGroups(&rows)

        return DiffDocument(
            left: left,
            right: right,
            rows: rows,
            changeGroups: changeGroups,
            options: options,
            isIdentical: changeGroups.isEmpty
        )
    }

    // MARK: - Line matching

    /// Builds the comparison key for a line.
    ///
    /// Whitespace is removed *before* case folding; the order does not affect
    /// the result, but doing it first avoids lowercasing text that is dropped.
    static func lineKey(for line: String, options: DiffOptions) -> String {
        var key = line
        if options.ignoreWhitespace {
            key = key.filter { !$0.isWhitespace }
        }
        if options.ignoreCase {
            key = key.lowercased()
        }
        return key
    }

    /// Offsets that differ between the two line arrays.
    ///
    /// Both sets are expressed in the coordinate space of their own side; an
    /// offset present on both sides is paired into a modified row by
    /// ``appendChangeRows``.
    private struct LineEdits {
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
    }

    private static func lineEdits(
        from leftLines: [String],
        to rightLines: [String],
        options: DiffOptions
    ) throws -> LineEdits {
        let leftKeys = leftLines.map { lineKey(for: $0, options: options) }
        let rightKeys = rightLines.map { lineKey(for: $0, options: options) }

        let smallerCount = min(leftKeys.count, rightKeys.count)
        let combinedCount = leftKeys.count + rightKeys.count
        if smallerCount > maxLinesForMyersDiff || combinedCount > maxCombinedLinesForMyersDiff {
            if let anchored = try anchoredLineEdits(leftKeys: leftKeys, rightKeys: rightKeys) {
                return anchored
            }
            return try pairedLineEdits(leftKeys: leftKeys, rightKeys: rightKeys)
        }

        let difference = rightKeys.difference(from: leftKeys)
        var edits = LineEdits()
        edits.removed.reserveCapacity(difference.removals.count)
        edits.inserted.reserveCapacity(difference.insertions.count)

        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                edits.removed.insert(offset)
            case .insert(let offset, _, _):
                edits.inserted.insert(offset)
            }
        }
        return edits
    }

    /// Largest gap between unique anchors that still uses Myers. Anchors turn a
    /// huge document into many small gaps, so this stays cheap while preserving
    /// accuracy around edits. Larger gaps fall back to linear pairing.
    private static let maxGapForMyersDiff = 4_000

    /// Above this many changed line pairs in one block, word-level diffing is
    /// skipped and only the row tint is shown. This keeps a wholly dissimilar
    /// 200k-line file from doing 200k token diffs.
    private static let maxChangedLinesForWordDiff = 2_000

    /// Uses unique common lines (patience-style anchors) to split large inputs
    /// into small gaps, then diffs each gap. This preserves the unchanged lines
    /// around edits instead of marking the whole middle changed.
    private static func anchoredLineEdits(
        leftKeys: [String],
        rightKeys: [String]
    ) throws -> LineEdits? {
        try Task.checkCancellation()

        func uniquePositions(_ keys: [String]) -> [String: Int] {
            var unique: [String: Int] = [:]
            var repeated: Set<String> = []
            unique.reserveCapacity(keys.count)
            for (index, key) in keys.enumerated() {
                if unique[key] != nil {
                    unique.removeValue(forKey: key)
                    repeated.insert(key)
                } else if !repeated.contains(key) {
                    unique[key] = index
                }
            }
            return unique
        }

        let leftUnique = uniquePositions(leftKeys)
        guard !leftUnique.isEmpty else { return nil }
        let rightUnique = uniquePositions(rightKeys)
        guard !rightUnique.isEmpty else { return nil }

        var candidates: [(left: Int, right: Int)] = []
        candidates.reserveCapacity(min(leftUnique.count, rightUnique.count))
        for (key, leftIndex) in leftUnique {
            if let rightIndex = rightUnique[key] {
                candidates.append((leftIndex, rightIndex))
            }
        }
        guard !candidates.isEmpty else { return nil }
        candidates.sort { $0.left < $1.left }
        try Task.checkCancellation()

        // Longest increasing subsequence of right positions: the anchors must
        // not cross, and the LIS gives the largest non-crossing set.
        var tailValues: [Int] = []
        var tailIndices: [Int] = []
        var previous = [Int](repeating: -1, count: candidates.count)

        for candidateIndex in candidates.indices {
            let value = candidates[candidateIndex].right
            var low = 0
            var high = tailValues.count
            while low < high {
                let middle = (low + high) / 2
                if tailValues[middle] < value {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            if low > 0 {
                previous[candidateIndex] = tailIndices[low - 1]
            }
            if low == tailValues.count {
                tailValues.append(value)
                tailIndices.append(candidateIndex)
            } else {
                tailValues[low] = value
                tailIndices[low] = candidateIndex
            }
        }

        guard let finalIndex = tailIndices.last else { return nil }
        var anchors: [(left: Int, right: Int)] = []
        var cursor: Int? = finalIndex
        while let index = cursor {
            anchors.append(candidates[index])
            cursor = previous[index] >= 0 ? previous[index] : nil
        }
        anchors.reverse()
        guard !anchors.isEmpty else { return nil }

        var edits = LineEdits()
        var previousLeft = -1
        var previousRight = -1
        let finalAnchor = (left: leftKeys.count, right: rightKeys.count)

        for anchor in anchors + [finalAnchor] {
            try diffGap(
                leftKeys: leftKeys,
                rightKeys: rightKeys,
                leftRange: (previousLeft + 1)..<anchor.left,
                rightRange: (previousRight + 1)..<anchor.right,
                edits: &edits
            )
            previousLeft = anchor.left
            previousRight = anchor.right
        }

        try Task.checkCancellation()
        return edits
    }

    private static func diffGap(
        leftKeys: [String],
        rightKeys: [String],
        leftRange: Range<Int>,
        rightRange: Range<Int>,
        edits: inout LineEdits
    ) throws {
        try Task.checkCancellation()

        if leftRange.isEmpty {
            for offset in rightRange {
                edits.inserted.insert(offset)
            }
            return
        }
        if rightRange.isEmpty {
            for offset in leftRange {
                edits.removed.insert(offset)
            }
            return
        }

        let leftCount = leftRange.count
        let rightCount = rightRange.count
        if min(leftCount, rightCount) <= maxGapForMyersDiff,
           leftCount + rightCount <= maxGapForMyersDiff * 2 {
            let leftSlice = Array(leftKeys[leftRange])
            let rightSlice = Array(rightKeys[rightRange])
            let difference = rightSlice.difference(from: leftSlice)
            for change in difference {
                switch change {
                case .remove(let offset, _, _):
                    edits.removed.insert(leftRange.lowerBound + offset)
                case .insert(let offset, _, _):
                    edits.inserted.insert(rightRange.lowerBound + offset)
                }
            }
            return
        }

        let fallback = try pairedLineEdits(
            leftKeys: Array(leftKeys[leftRange]),
            rightKeys: Array(rightKeys[rightRange])
        )
        for offset in fallback.removed {
            edits.removed.insert(leftRange.lowerBound + offset)
        }
        for offset in fallback.inserted {
            edits.inserted.insert(rightRange.lowerBound + offset)
        }
    }

    /// Linear fallback used for inputs too large for Myers diffing.
    ///
    /// Common prefix and suffix lines are matched exactly; the remaining middle
    /// is paired by index, with leftovers becoming one-sided rows. This does not
    /// find common subsequences inside the middle (a large dissimilar middle is
    /// reported as changed), but it is structurally equivalent to a diff, and
    /// its cost is linear in the number of lines.
    private static func pairedLineEdits(
        leftKeys: [String],
        rightKeys: [String]
    ) throws -> LineEdits {
        try Task.checkCancellation()

        let leftCount = leftKeys.count
        let rightCount = rightKeys.count

        var prefix = 0
        let prefixLimit = min(leftCount, rightCount)
        while prefix < prefixLimit, leftKeys[prefix] == rightKeys[prefix] {
            prefix += 1
            try Task.checkCancellation()
        }

        var leftEnd = leftCount
        var rightEnd = rightCount
        while leftEnd > prefix,
              rightEnd > prefix,
              leftKeys[leftEnd - 1] == rightKeys[rightEnd - 1] {
            leftEnd -= 1
            rightEnd -= 1
            try Task.checkCancellation()
        }

        var edits = LineEdits()
        edits.removed.reserveCapacity(leftEnd - prefix)
        edits.inserted.reserveCapacity(rightEnd - prefix)

        for offset in prefix..<leftEnd {
            edits.removed.insert(offset)
            try Task.checkCancellation()
        }
        for offset in prefix..<rightEnd {
            edits.inserted.insert(offset)
            try Task.checkCancellation()
        }

        return edits
    }

    // MARK: - Change blocks

    private static func appendChangeRows(
        removed: [Int],
        inserted: [Int],
        leftLines: [String],
        rightLines: [String],
        options: DiffOptions,
        rows: inout [DiffRow]
    ) {
        let pairCount = max(removed.count, inserted.count)
        guard pairCount > 0 else { return }
        let skipWordDiff = pairCount > maxChangedLinesForWordDiff

        for index in 0..<pairCount {
            let leftIndex = index < removed.count ? removed[index] : nil
            let rightIndex = index < inserted.count ? inserted[index] : nil

            let leftCell: DiffCell?
            let rightCell: DiffCell?
            let kind: DiffRowKind

            switch (leftIndex, rightIndex) {
            case let (old?, new?):
                if skipWordDiff {
                    leftCell = DiffCell(
                        lineNumber: old + 1,
                        text: leftLines[old],
                        isLineChanged: true
                    )
                    rightCell = DiffCell(
                        lineNumber: new + 1,
                        text: rightLines[new],
                        isLineChanged: true
                    )
                } else {
                    let runs = wordRuns(
                        oldLine: leftLines[old],
                        newLine: rightLines[new],
                        options: options
                    )
                    leftCell = DiffCell(
                        lineNumber: old + 1,
                        runs: runs.left,
                        isLineChanged: true
                    )
                    rightCell = DiffCell(
                        lineNumber: new + 1,
                        runs: runs.right,
                        isLineChanged: true
                    )
                }
                kind = .modified

            case let (old?, nil):
                leftCell = DiffCell(
                    lineNumber: old + 1,
                    runs: [DiffRun(leftLines[old], emphasis: .word)],
                    isLineChanged: true
                )
                rightCell = nil
                kind = .removed

            case let (nil, new?):
                leftCell = nil
                rightCell = DiffCell(
                    lineNumber: new + 1,
                    runs: [DiffRun(rightLines[new], emphasis: .word)],
                    isLineChanged: true
                )
                kind = .added

            case (nil, nil):
                continue
            }

            rows.append(
                DiffRow(
                    id: rows.count,
                    kind: kind,
                    left: leftCell,
                    right: rightCell,
                    changeGroup: nil
                )
            )
        }
    }

    // MARK: - Word-level diff

    /// Highlights the words that differ between two paired lines.
    ///
    /// Both sides keep their original characters; only emphasis changes. When
    /// either line is too long in bytes, or has too many tokens, the whole line
    /// is treated as one emphasised run instead of running the token diff.
    ///
    /// The byte check intentionally runs first: tokenizing a multi-megabyte line
    /// would allocate millions of tokens before the token-count guard could
    /// reject it.
    private static func wordRuns(
        oldLine: String,
        newLine: String,
        options: DiffOptions
    ) -> (left: [DiffRun], right: [DiffRun]) {
        let wholeLine = (
            left: [DiffRun(oldLine, emphasis: .word)],
            right: [DiffRun(newLine, emphasis: .word)]
        )

        guard oldLine.utf8.count <= maxBytesForWordDiff,
              newLine.utf8.count <= maxBytesForWordDiff
        else {
            return wholeLine
        }

        let oldTokens = Tokenizer.tokenize(oldLine)
        let newTokens = Tokenizer.tokenize(newLine)

        guard oldTokens.count <= maxTokensForWordDiff,
              newTokens.count <= maxTokensForWordDiff
        else {
            return wholeLine
        }

        var oldKeys: [String] = []
        var newKeys: [String] = []
        var oldTokenIndices: [Int] = []
        var newTokenIndices: [Int] = []

        collectComparisonKeys(
            tokens: oldTokens,
            options: options,
            keys: &oldKeys,
            indices: &oldTokenIndices
        )
        collectComparisonKeys(
            tokens: newTokens,
            options: options,
            keys: &newKeys,
            indices: &newTokenIndices
        )

        var oldEmphasis = [DiffEmphasis](repeating: .normal, count: oldTokens.count)
        var newEmphasis = [DiffEmphasis](repeating: .normal, count: newTokens.count)

        let difference = newKeys.difference(from: oldKeys)
        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                oldEmphasis[oldTokenIndices[offset]] = .word
            case .insert(let offset, _, _):
                newEmphasis[newTokenIndices[offset]] = .word
            }
        }

        return (
            mergeRuns(tokens: oldTokens, emphases: oldEmphasis),
            mergeRuns(tokens: newTokens, emphases: newEmphasis)
        )
    }

    /// Appends the comparison keys of `tokens` that participate in the word
    /// diff, along with their original token indices.
    ///
    /// Whitespace tokens are skipped for comparison when `ignoreWhitespace` is
    /// set. They are never removed from the output runs.
    private static func collectComparisonKeys(
        tokens: [TextToken],
        options: DiffOptions,
        keys: inout [String],
        indices: inout [Int]
    ) {
        for (index, token) in tokens.enumerated() {
            if options.ignoreWhitespace, token.isWhitespace { continue }
            keys.append(token.comparisonKey(ignoreCase: options.ignoreCase))
            indices.append(index)
        }
    }

    /// Collapses adjacent tokens that share an emphasis into a single run.
    private static func mergeRuns(tokens: [TextToken], emphases: [DiffEmphasis]) -> [DiffRun] {
        guard !tokens.isEmpty else {
            // Keep `runs` non-empty so a blank line still has renderable text.
            return [DiffRun("")]
        }

        var runs: [DiffRun] = []
        runs.reserveCapacity(8)

        for index in tokens.indices {
            let emphasis = emphases[index]
            let token = tokens[index]

            if let last = runs.last, last.emphasis == emphasis {
                runs[runs.count - 1].text.append(token.text)
            } else {
                runs.append(DiffRun(token.text, emphasis: emphasis))
            }
        }

        return runs
    }

    // MARK: - Change groups

    /// Assigns every maximal run of changed rows to a change group.
    private static func assignChangeGroups(_ rows: inout [DiffRow]) -> [DiffChangeGroup] {
        var groups: [DiffChangeGroup] = []
        var index = 0

        while index < rows.count {
            guard rows[index].isChanged else {
                index += 1
                continue
            }

            let start = index
            while index < rows.count, rows[index].isChanged {
                index += 1
            }

            let group = DiffChangeGroup(id: groups.count, rows: start..<index)
            for rowIndex in start..<index {
                rows[rowIndex].changeGroup = group.id
            }
            groups.append(group)
        }

        return groups
    }
}
