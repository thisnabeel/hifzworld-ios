import Foundation

/// Local queue for Mushaf marks created/removed while offline (or when the API is unreachable).
/// Ops flush in `createdAt` order once connectivity returns.
@MainActor
@Observable
final class PendingMushafMarksStore {
    static let shared = PendingMushafMarksStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "pendingMushafMarkOps"
    private(set) var items: [PendingMushafMarkOp] = []

    private init() {
        items = load()
    }

    var hasPending: Bool { !items.isEmpty }

    func ops(subjectID: UUID, mushafID: Int? = nil) -> [PendingMushafMarkOp] {
        items.filter { op in
            op.subjectID == subjectID && (mushafID == nil || op.mushafID == mushafID)
        }
    }

    /// Latest intended mark type per word after applying pending ops.
    func overlayTypes(
        onto base: [Int: MistakeMarkType],
        subjectID: UUID,
        mushafID: Int
    ) -> [Int: MistakeMarkType] {
        var map = base
        for op in ops(subjectID: subjectID, mushafID: mushafID).sorted(by: { $0.createdAt < $1.createdAt }) {
            switch op.kind {
            case .upsert:
                map[op.wordID] = MistakeMarkType.resolved(from: op.markType)
            case .delete:
                map.removeValue(forKey: op.wordID)
            }
        }
        return map
    }

    func enqueueUpsert(
        subjectID: UUID,
        wordID: Int,
        verseKey: String,
        pageNumber: Int,
        mushafID: Int,
        markType: MistakeMarkType,
        lineNumber: Int?,
        wordPosition: Int?,
        note: String? = nil,
        at date: Date = Date()
    ) {
        removeOps(subjectID: subjectID, wordID: wordID, mushafID: mushafID)
        items.append(
            PendingMushafMarkOp(
                id: UUID(),
                kind: .upsert,
                subjectID: subjectID,
                wordID: wordID,
                verseKey: verseKey,
                pageNumber: pageNumber,
                mushafID: mushafID,
                markType: markType.rawValue,
                lineNumber: lineNumber,
                wordPosition: wordPosition,
                serverMarkID: nil,
                createdAt: date,
                note: note
            )
        )
        save()
    }

    /// Queues a server delete, or cancels an unsynced upsert for the same word.
    func enqueueDelete(
        subjectID: UUID,
        wordID: Int,
        pageNumber: Int,
        mushafID: Int,
        serverMarkID: UUID?,
        at date: Date = Date()
    ) {
        let hadUnsyncedUpsert = items.contains {
            $0.kind == .upsert
                && $0.subjectID == subjectID
                && $0.wordID == wordID
                && $0.mushafID == mushafID
        }
        removeOps(subjectID: subjectID, wordID: wordID, mushafID: mushafID)
        if hadUnsyncedUpsert {
            save()
            return
        }
        items.append(
            PendingMushafMarkOp(
                id: UUID(),
                kind: .delete,
                subjectID: subjectID,
                wordID: wordID,
                verseKey: "",
                pageNumber: pageNumber,
                mushafID: mushafID,
                markType: MistakeMarkType.mistake.rawValue,
                lineNumber: nil,
                wordPosition: nil,
                serverMarkID: serverMarkID,
                createdAt: date,
                note: nil
            )
        )
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func removeOps(subjectID: UUID, wordID: Int, mushafID: Int) {
        items.removeAll {
            $0.subjectID == subjectID && $0.wordID == wordID && $0.mushafID == mushafID
        }
    }

    private func load() -> [PendingMushafMarkOp] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PendingMushafMarkOp].self, from: data)
        else { return [] }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

struct PendingMushafMarkOp: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case upsert
        case delete
    }

    let id: UUID
    let kind: Kind
    let subjectID: UUID
    let wordID: Int
    let verseKey: String
    let pageNumber: Int
    let mushafID: Int
    let markType: String
    let lineNumber: Int?
    let wordPosition: Int?
    let serverMarkID: UUID?
    let createdAt: Date
    let note: String?
}
