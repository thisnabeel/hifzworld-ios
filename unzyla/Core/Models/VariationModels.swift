import Foundation

struct Variation: Codable, Identifiable, Hashable {
    var id: String { "\(wordID)-\(narratorIDString)" }

    let wordID: Int
    let narratorID: NarratorIDValue
    let content: String
    let specialCharacters: SpecialCharacters?
    let word: VariationWord?
    let narrator: VariationNarrator?

    var narratorIDString: String {
        narratorID.stringValue
    }

    enum CodingKeys: String, CodingKey {
        case content, word, narrator
        case wordID = "word_id"
        case narratorID = "narrator_id"
        case specialCharacters = "special_characters"
    }
}

enum NarratorIDValue: Codable, Hashable {
    case string(String)
    case int(Int)

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        }
    }
}

struct SpecialCharacters: Codable, Hashable {
    let imalah: ImalahData?
    let diamond: DiamondData?
}

struct ImalahData: Codable, Hashable {
    let indices: [Int]?
}

struct DiamondData: Codable, Hashable {
    let indices: [Int]?
}

struct VariationWord: Codable, Hashable {
    let id: Int
    let content: String?
    let ayah: String?
    let line: VariationLine?
}

struct VariationLine: Codable, Hashable {
    let page: VariationPage?
}

struct VariationPage: Codable, Hashable {
    let position: Int?
}

struct VariationNarrator: Codable, Hashable {
    let id: NarratorIDValue?
    let title: String?
    let highlightColor: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case highlightColor = "highlight_color"
    }
}

struct VariationSaveRequest: Codable {
    let wordID: Int
    let narratorID: String
    let content: String
    let specialCharacters: SpecialCharacters?

    enum CodingKeys: String, CodingKey {
        case content
        case wordID = "word_id"
        case narratorID = "narrator_id"
        case specialCharacters = "special_characters"
    }
}
