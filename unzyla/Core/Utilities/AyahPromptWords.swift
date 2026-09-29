import Foundation

enum AyahPromptWords {
    /// Word IDs that stay visible at the start of prompt mode: up to `cueCount`
    /// non-marker words after each ayah circle / surah header, and at the start
    /// of each page (e.g. when the previous page ended on a verse circle).
    /// `cueCount` of 0 means only verse circles/headers stay unblacked.
    static func cueWordIDs(on page: MushafPage, mushafID: Int, cueCount: Int = 2) -> Set<Int> {
        let cuesPerBreak = min(2, max(0, cueCount))
        let lines = page.lines.sorted { $0.position < $1.position }
        var cues = Set<Int>()
        // Page boundary: previous page may have ended on an ayah circle.
        var pendingCues = cuesPerBreak

        for line in lines {
            if line.suppressLine == true { continue }

            let isHeader = (line.surahHeaderPosition ?? 0) != 0
                || (mushafID == MushafID.indoPak.rawValue
                    && !line.words.contains { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    && line.surahHeaderPosition != nil)

            if isHeader {
                pendingCues = cuesPerBreak
            }

            for word in line.words {
                let trimmed = word.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }

                if MushafWordVerse.isAyahEndingToken(word, mushafID: mushafID) {
                    pendingCues = cuesPerBreak
                    continue
                }

                if pendingCues > 0 {
                    cues.insert(word.id)
                    pendingCues -= 1
                }
            }
        }

        return cues
    }

    static func cueWordIDs(onPages pages: [MushafPage], mushafID: Int, cueCount: Int = 2) -> Set<Int> {
        pages.reduce(into: Set<Int>()) { result, page in
            result.formUnion(cueWordIDs(on: page, mushafID: mushafID, cueCount: cueCount))
        }
    }
}
