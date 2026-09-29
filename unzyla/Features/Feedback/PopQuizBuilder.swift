import Foundation

struct PopQuizLineRef: Hashable, Comparable {
    let mushafID: Int
    let pageNumber: Int
    let lineNumber: Int

    var isRightPage: Bool { !pageNumber.isMultiple(of: 2) }

    var pageSideTitle: String { isRightPage ? "Right page" : "Left page" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.mushafID != rhs.mushafID { return lhs.mushafID < rhs.mushafID }
        if lhs.pageNumber != rhs.pageNumber { return lhs.pageNumber < rhs.pageNumber }
        return lhs.lineNumber < rhs.lineNumber
    }

    func previous(maxLines: Int) -> PopQuizLineRef? {
        if lineNumber > 1 {
            return PopQuizLineRef(mushafID: mushafID, pageNumber: pageNumber, lineNumber: lineNumber - 1)
        }
        guard pageNumber > 1 else { return nil }
        return PopQuizLineRef(mushafID: mushafID, pageNumber: pageNumber - 1, lineNumber: maxLines)
    }

    func next(maxLines: Int) -> PopQuizLineRef? {
        if lineNumber < maxLines {
            return PopQuizLineRef(mushafID: mushafID, pageNumber: pageNumber, lineNumber: lineNumber + 1)
        }
        return PopQuizLineRef(mushafID: mushafID, pageNumber: pageNumber + 1, lineNumber: 1)
    }

    func isConsecutive(to other: PopQuizLineRef, maxLines: Int) -> Bool {
        next(maxLines: maxLines) == other
    }
}

struct PopQuizRenderedLine: Identifiable {
    let id: String
    let ref: PopQuizLineRef
    let line: MushafLine
    let paintedWords: [Int: WordPaintStyle]
}

struct PopQuizPageSegment: Identifiable {
    let id: String
    let mushafID: Int
    let pageNumber: Int
    let isRightPage: Bool
    let pageSideTitle: String
    let lines: [PopQuizRenderedLine]
}

struct PopQuizItem: Identifiable {
    let id: String
    let segments: [PopQuizPageSegment]
    let firstMarkRef: PopQuizLineRef
    let lastMarkRef: PopQuizLineRef
    let firstWordID: Int
    let firstWordPosition: Int

    var mushafID: Int { firstMarkRef.mushafID }

    var earliestPageNumber: Int {
        segments.map(\.pageNumber).min() ?? firstMarkRef.pageNumber
    }

    var earliestRef: PopQuizLineRef? {
        segments.first?.lines.first?.ref
    }
}

enum PopQuizBuilder {
    private struct AnchoredMark {
        let ref: PopQuizLineRef
        let wordPosition: Int
        let wordID: Int
    }

    static func neededPages(for marks: [MushafMarkDTO]) -> [(mushafID: Int, page: Int)] {
        var needed = Set<String>()
        var result: [(Int, Int)] = []
        func add(_ mushafID: Int, _ page: Int) {
            guard page > 0 else { return }
            let key = "\(mushafID):\(page)"
            guard needed.insert(key).inserted else { return }
            result.append((mushafID, page))
        }
        for mark in marks {
            add(mark.mushafID, mark.pageNumber)
            add(mark.mushafID, mark.pageNumber - 1)
            add(mark.mushafID, mark.pageNumber + 1)
        }
        return result
    }

    static func build(marks: [MushafMarkDTO], pages: [String: MushafPage]) -> [PopQuizItem] {
        let anchored = marks.compactMap { resolve($0, pages: pages) }
            .sorted {
                if $0.ref != $1.ref { return $0.ref < $1.ref }
                if $0.wordPosition != $1.wordPosition { return $0.wordPosition < $1.wordPosition }
                return $0.wordID < $1.wordID
            }
        guard !anchored.isEmpty else { return [] }

        var clusters: [[AnchoredMark]] = []
        var current: [AnchoredMark] = [anchored[0]]
        for mark in anchored.dropFirst() {
            let last = current.last!
            let maxLines = Self.maxLines(mushafID: last.ref.mushafID)
            if mark.ref.mushafID == last.ref.mushafID,
               last.ref == mark.ref || last.ref.isConsecutive(to: mark.ref, maxLines: maxLines) {
                current.append(mark)
            } else {
                clusters.append(current)
                current = [mark]
            }
        }
        clusters.append(current)

        return clusters.compactMap { cluster in
            makeQuiz(cluster: cluster, extraLeadingVerses: 0, pages: pages)
        }
    }

    static func rebuild(
        _ item: PopQuizItem,
        extraLeadingVerses: Int,
        pages: [String: MushafPage]
    ) -> PopQuizItem? {
        makeQuiz(
            firstMark: AnchoredMark(
                ref: item.firstMarkRef,
                wordPosition: item.firstWordPosition,
                wordID: item.firstWordID
            ),
            lastMarkRef: item.lastMarkRef,
            id: item.id,
            extraLeadingVerses: extraLeadingVerses,
            pages: pages
        )
    }

    nonisolated static func pageKey(mushafID: Int, page: Int) -> String { "\(mushafID):\(page)" }

    private static func maxLines(mushafID: Int) -> Int {
        MushafID(rawValue: mushafID)?.maxLines ?? 15
    }

    private static func resolve(_ mark: MushafMarkDTO, pages: [String: MushafPage]) -> AnchoredMark? {
        let key = pageKey(mushafID: mark.mushafID, page: mark.pageNumber)
        guard let page = pages[key] else { return nil }

        if let lineNumber = mark.lineNumber, lineNumber > 0 {
            let wordPosition = mark.wordPosition ?? 0
            return AnchoredMark(
                ref: PopQuizLineRef(mushafID: mark.mushafID, pageNumber: mark.pageNumber, lineNumber: lineNumber),
                wordPosition: wordPosition,
                wordID: mark.wordID
            )
        }

        for line in page.lines {
            if let word = line.words.first(where: { $0.id == mark.wordID }) {
                return AnchoredMark(
                    ref: PopQuizLineRef(mushafID: mark.mushafID, pageNumber: mark.pageNumber, lineNumber: line.position),
                    wordPosition: word.position,
                    wordID: mark.wordID
                )
            }
        }
        return nil
    }

    private static func line(on page: MushafPage, number: Int) -> MushafLine? {
        page.lines.first { $0.position == number }
    }

    private static func makeQuiz(cluster: [AnchoredMark], extraLeadingVerses: Int, pages: [String: MushafPage]) -> PopQuizItem? {
        guard let first = cluster.first, let last = cluster.last else { return nil }
        let id = cluster.map { "\($0.wordID)" }.joined(separator: "-")
        return makeQuiz(
            firstMark: first,
            lastMarkRef: last.ref,
            id: id,
            extraLeadingVerses: extraLeadingVerses,
            pages: pages
        )
    }

    private static func makeQuiz(
        firstMark: AnchoredMark,
        lastMarkRef: PopQuizLineRef,
        id: String,
        extraLeadingVerses: Int,
        pages: [String: MushafPage]
    ) -> PopQuizItem? {
        let first = firstMark
        let maxLines = maxLines(mushafID: first.ref.mushafID)
        let contextStart = leadingStart(
            firstMark: first.ref,
            extraLeadingVerses: extraLeadingVerses,
            pages: pages,
            maxLines: maxLines
        ) ?? first.ref.previous(maxLines: maxLines)?.previous(maxLines: maxLines)
            ?? first.ref.previous(maxLines: maxLines)
            ?? first.ref
        let blackoutEnd = lastMarkRef.next(maxLines: maxLines)

        var walk: [PopQuizLineRef] = []
        var cursor = contextStart
        let end = blackoutEnd ?? lastMarkRef
        var guardCount = 0
        let walkLimit = 40 + extraLeadingVerses * 20
        while cursor <= end, guardCount < walkLimit {
            walk.append(cursor)
            guard let next = cursor.next(maxLines: maxLines) else { break }
            if next > end { break }
            cursor = next
            guardCount += 1
        }
        if walk.last != end, end >= first.ref {
            walk.append(end)
        }
        if !walk.contains(first.ref) {
            walk.insert(first.ref, at: 0)
            walk.sort()
        }

        var rendered: [PopQuizRenderedLine] = []
        for ref in walk {
            let key = pageKey(mushafID: ref.mushafID, page: ref.pageNumber)
            guard let page = pages[key], let mushafLine = line(on: page, number: ref.lineNumber) else {
                continue
            }
            let painted = blackoutMap(
                line: mushafLine,
                ref: ref,
                first: first,
                lastMarked: lastMarkRef
            )
            rendered.append(
                PopQuizRenderedLine(
                    id: "\(ref.mushafID)-\(ref.pageNumber)-\(ref.lineNumber)-\(mushafLine.id)",
                    ref: ref,
                    line: mushafLine,
                    paintedWords: painted
                )
            )
        }
        guard !rendered.isEmpty else { return nil }

        var segments: [PopQuizPageSegment] = []
        var bucket: [PopQuizRenderedLine] = []
        var bucketPage: Int?
        for row in rendered {
            if bucketPage != nil, bucketPage != row.ref.pageNumber {
                segments.append(segment(from: bucket))
                bucket = [row]
                bucketPage = row.ref.pageNumber
            } else {
                bucket.append(row)
                bucketPage = row.ref.pageNumber
            }
        }
        if !bucket.isEmpty {
            segments.append(segment(from: bucket))
        }

        return PopQuizItem(
            id: id,
            segments: segments,
            firstMarkRef: first.ref,
            lastMarkRef: lastMarkRef,
            firstWordID: first.wordID,
            firstWordPosition: first.wordPosition
        )
    }

    /// Default: two lines before the mark. Each extra verse walks back to the start of one more ayah.
    private static func leadingStart(
        firstMark: PopQuizLineRef,
        extraLeadingVerses: Int,
        pages: [String: MushafPage],
        maxLines: Int
    ) -> PopQuizLineRef? {
        if extraLeadingVerses <= 0 {
            return firstMark.previous(maxLines: maxLines)?.previous(maxLines: maxLines)
                ?? firstMark.previous(maxLines: maxLines)
        }

        var endsFound = 0
        var cursor = firstMark.previous(maxLines: maxLines)
        var lastSeen = cursor
        while let ref = cursor {
            lastSeen = ref
            if lineHasAyahEnding(ref, pages: pages) {
                endsFound += 1
                if endsFound == extraLeadingVerses + 1 {
                    return ref.next(maxLines: maxLines) ?? ref
                }
            }
            cursor = ref.previous(maxLines: maxLines)
        }
        return lastSeen ?? firstMark
    }

    private static func lineHasAyahEnding(_ ref: PopQuizLineRef, pages: [String: MushafPage]) -> Bool {
        let key = pageKey(mushafID: ref.mushafID, page: ref.pageNumber)
        guard let page = pages[key], let mushafLine = line(on: page, number: ref.lineNumber) else {
            return false
        }
        return mushafLine.words.contains { MushafWordVerse.isAyahEndingToken($0, mushafID: ref.mushafID) }
    }

    private static func segment(from lines: [PopQuizRenderedLine]) -> PopQuizPageSegment {
        let ref = lines[0].ref
        return PopQuizPageSegment(
            id: "\(ref.mushafID)-\(ref.pageNumber)",
            mushafID: ref.mushafID,
            pageNumber: ref.pageNumber,
            isRightPage: ref.isRightPage,
            pageSideTitle: ref.pageSideTitle,
            lines: lines
        )
    }

    private static func blackoutMap(
        line: MushafLine,
        ref: PopQuizLineRef,
        first: AnchoredMark,
        lastMarked: PopQuizLineRef
    ) -> [Int: WordPaintStyle] {
        if ref < first.ref {
            return [:]
        }
        if ref > lastMarked {
            return Dictionary(uniqueKeysWithValues: line.words.map { ($0.id, WordPaintStyle.blackout) })
        }
        if ref == first.ref {
            let sorted = line.words
            let startIndex = sorted.firstIndex(where: { $0.id == first.wordID })
                ?? sorted.firstIndex(where: { $0.position >= first.wordPosition })
                ?? sorted.startIndex
            return Dictionary(uniqueKeysWithValues: sorted[startIndex...].map { ($0.id, WordPaintStyle.blackout) })
        }
        return Dictionary(uniqueKeysWithValues: line.words.map { ($0.id, WordPaintStyle.blackout) })
    }
}
