import Foundation

struct NarratorDTO: Codable, Identifiable {
    let id: Int
    let title: String
    let highlightColor: String?
    let narratorID: Int?
    let narrator: NarratorParentDTO?
    let region: NarratorRegionDTO?

    enum CodingKeys: String, CodingKey {
        case id, title, narrator, region
        case highlightColor = "highlight_color"
        case narratorID = "narrator_id"
    }
}

struct NarratorParentDTO: Codable {
    let id: Int
    let title: String
    let highlightColor: String?
    let region: NarratorRegionDTO?

    enum CodingKeys: String, CodingKey {
        case id, title, region
        case highlightColor = "highlight_color"
    }
}

struct NarratorRegionDTO: Codable {
    let title: String
}

struct NarratorChild: Identifiable, Hashable {
    let id: String
    let title: String
    let highlightColor: String
    let regionTitle: String
    let isHafs: Bool
}

struct ParentNarrator: Identifiable, Hashable {
    let id: Int
    let title: String
    let highlightColor: String?
    let regionTitle: String
    var children: [NarratorChild]
}

enum NarratorCatalog {
    static let hafsID = "hafs-an-asim"

    static func build(from dtos: [NarratorDTO]) -> [ParentNarrator] {
        var parentMap: [Int: ParentNarrator] = [:]

        for child in dtos {
            guard child.narratorID != nil, let parent = child.narrator else { continue }
            if parentMap[parent.id] == nil {
                parentMap[parent.id] = ParentNarrator(
                    id: parent.id,
                    title: parent.title,
                    highlightColor: parent.highlightColor,
                    regionTitle: parent.region?.title ?? "",
                    children: []
                )
            }
            parentMap[parent.id]?.children.append(
                NarratorChild(
                    id: String(child.id),
                    title: child.title,
                    highlightColor: child.highlightColor ?? "#f9ca24",
                    regionTitle: child.region?.title ?? "",
                    isHafs: false
                )
            )
        }

        var parents = parentMap.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        if let asimIndex = parents.firstIndex(where: { parent in
            let t = parent.title.lowercased()
            return t.contains("asim") || t.contains("aasim") || t.contains("asem")
        }) {
            parents[asimIndex].children.insert(
                NarratorChild(
                    id: hafsID,
                    title: "Hafs",
                    highlightColor: "#00d4ff",
                    regionTitle: "Kufa",
                    isHafs: true
                ),
                at: 0
            )
        }

        return parents
    }

    static func recitationSlug(for narratorID: String, parents: [ParentNarrator]) -> String? {
        if narratorID == hafsID || narratorID == "hafs" { return hafsID }
        for parent in parents {
            for child in parent.children where child.id == narratorID {
                let t = child.title.lowercased()
                if t.contains("shubah") || (t.contains("shu") && t.contains("bah")) {
                    return "shubah-an-asim"
                }
                if t.contains("hafs") { return hafsID }
            }
        }
        return nil
    }
}
