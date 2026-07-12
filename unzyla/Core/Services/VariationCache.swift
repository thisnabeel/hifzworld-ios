import Foundation

@MainActor
final class VariationCache {
    private var map: [String: Variation] = [:]

    func key(wordID: Int, narratorID: String) -> String {
        "\(wordID)-\(narratorID)"
    }

    func variation(wordID: Int, narratorID: String) -> Variation? {
        map[key(wordID: wordID, narratorID: narratorID)]
    }

    func store(_ variations: [Variation]) {
        for v in variations {
            map[v.id] = v
        }
    }

    func allVariations() -> [Variation] {
        Array(map.values)
    }

    func variations(on page: MushafPage) -> [Variation] {
        let wordIDs = Set(page.lines.flatMap { $0.words.map(\.id) })
        return map.values.filter { wordIDs.contains($0.wordID) }
    }

    func remove(wordID: Int, narratorID: String) {
        map.removeValue(forKey: key(wordID: wordID, narratorID: narratorID))
    }

    func removeAll() {
        map.removeAll()
    }
}
