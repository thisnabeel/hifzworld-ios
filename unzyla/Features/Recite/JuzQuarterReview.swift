import Observation
import SwiftUI
import UIKit

/// Reviewer-only walkthrough for confirming juz quarter boundaries on the scanned Taj 13-line mushaf.
/// Each juz has five checkpoints (start, الربع, النصف, الثلثة, last page). The reviewer moves to the
/// right page, taps the verse circle where the boundary falls, and confirms; results persist on device
/// and can be copied as JSON for `segments.json`.
@MainActor
@Observable
final class JuzQuarterReview {
    enum Kind: Int, CaseIterable, Codable {
        case start, secondQuarter, half, fourthQuarter, lastPage

        var title: String {
            switch self {
            case .start: "Juz start"
            case .secondQuarter: "2nd quarter — الربع"
            case .half: "3rd quarter — النصف"
            case .fourthQuarter: "4th quarter — الثلثة"
            case .lastPage: "Last page of juz"
            }
        }

        var verseHint: String {
            switch self {
            case .start: "Tap the circle of the last verse before this juz"
            case .lastPage: "Tap the circle of this juz's last verse"
            default: "Tap the circle of the verse just before this quarter"
            }
        }
    }

    struct Checkpoint: Hashable {
        let juz: Int
        let kind: Kind
        var key: String { "\(juz)-\(kind.rawValue)" }
    }

    struct Confirmation: Codable, Hashable {
        let page: Int
        /// Verse whose ending circle the reviewer tapped (the boundary falls right after it).
        let verseBefore: String?
    }

    static let mushafID = MushafID.indoPak.rawValue
    private static let reviewerEmails: Set<String> = ["rockystorm@gmail.com"]

    /// Only the reviewer's account sees the walkthrough.
    static func isAvailable(for user: HifzworldUser?) -> Bool {
        guard let email = user?.email?.lowercased() else { return false }
        return reviewerEmails.contains(email)
    }
    private static let confirmedKey = "juzQuarterReview.confirmed"
    private static let indexKey = "juzQuarterReview.index"

    let checkpoints: [Checkpoint] = (1...30).flatMap { juz in Kind.allCases.map { Checkpoint(juz: juz, kind: $0) } }
    private(set) var confirmed: [String: Confirmation] = [:]
    var index: Int {
        didSet { UserDefaults.standard.set(index, forKey: Self.indexKey) }
    }

    init() {
        index = min(UserDefaults.standard.integer(forKey: Self.indexKey), 149)
        if let data = UserDefaults.standard.data(forKey: Self.confirmedKey),
           let saved = try? JSONDecoder().decode([String: Confirmation].self, from: data) {
            confirmed = saved
        }
    }

    var current: Checkpoint { checkpoints[index] }

    /// Proposed page for a checkpoint, from the bundled juz ranges and quarter segments.
    func proposedPage(_ checkpoint: Checkpoint, juzSegments: [NavigationSegment], quarterStarts: [Int: [Int]]) -> Int? {
        guard let juz = juzSegments.first(where: { $0.categoryPosition == checkpoint.juz }) else { return nil }
        switch checkpoint.kind {
        case .start: return juz.startPage
        case .lastPage: return juz.endPage
        default:
            guard let starts = quarterStarts[checkpoint.juz], starts.count == 4 else { return nil }
            return starts[checkpoint.kind.rawValue]
        }
    }

    func confirm(page: Int, verseBefore: String?) {
        confirmed[current.key] = Confirmation(page: page, verseBefore: verseBefore)
        save()
    }

    func clearCurrent() {
        confirmed[current.key] = nil
        save()
    }

    var exportJSON: String {
        let rows = checkpoints.compactMap { checkpoint -> [String: Any]? in
            guard let confirmation = confirmed[checkpoint.key] else { return nil }
            var row: [String: Any] = ["juz": checkpoint.juz, "kind": "\(checkpoint.kind)", "page": confirmation.page]
            if let verse = confirmation.verseBefore { row["verse_before"] = verse }
            return row
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(confirmed) {
            UserDefaults.standard.set(data, forKey: Self.confirmedKey)
        }
    }
}

/// Bar shown under the top bar while reviewing juz quarters.
struct JuzQuarterReviewBar: View {
    @Bindable var review: JuzQuarterReview
    let currentPage: Int
    let selectedVerseKey: String?
    let proposedPage: (JuzQuarterReview.Checkpoint) -> Int?
    let onGoToPage: (Int) -> Void
    /// Clears the tapped verse so it doesn't carry over to the next checkpoint.
    let onClearVerse: () -> Void
    let onExit: () -> Void

    @State private var copied = false

    private func printed(_ page: Int) -> Int {
        PrintedPage.display(page, mushafID: JuzQuarterReview.mushafID)
    }

    var body: some View {
        let checkpoint = review.current
        let proposed = proposedPage(checkpoint)
        let confirmation = review.confirmed[checkpoint.key]

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Juz \(checkpoint.juz) · \(checkpoint.kind.title)")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("\(review.index + 1)/\(review.checkpoints.count) · \(review.confirmed.count) done")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if let proposed {
                    Button("Proposed p\(printed(proposed))") { onGoToPage(proposed) }
                        .font(.subheadline.weight(.medium))
                        .disabled(proposed == currentPage)
                }
                if let confirmation {
                    Label(
                        "p\(printed(confirmation.page))" + (confirmation.verseBefore.map { " after \($0)" } ?? ""),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.green)
                }
                Spacer(minLength: 0)
            }

            Text(selectedVerseKey.map { "Verse circle: \($0)" } ?? checkpoint.kind.verseHint)
                .font(.caption)
                .foregroundStyle(selectedVerseKey == nil ? Color.secondary : Color.orange)

            HStack(spacing: 10) {
                barButton("chevron.left", label: "Previous") { move(by: -1) }
                    .disabled(review.index == 0)

                Button {
                    review.confirm(page: currentPage, verseBefore: selectedVerseKey)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    move(by: 1)
                } label: {
                    Label("Confirm p\(printed(currentPage))", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.green))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                barButton("chevron.right", label: "Skip") { move(by: 1) }
                    .disabled(review.index == review.checkpoints.count - 1)

                Menu {
                    Button(copied ? "Copied" : "Copy results JSON", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = review.exportJSON
                        print("[JuzQuarterReview]\n\(review.exportJSON)")
                        copied = true
                    }
                    if confirmation != nil {
                        Button("Clear this checkpoint", systemImage: "arrow.uturn.backward", role: .destructive) {
                            review.clearCurrent()
                        }
                    }
                    Button("Exit review", systemImage: "xmark", action: onExit)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.orange).frame(height: 2)
        }
    }

    private func barButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Steps to another checkpoint and opens its confirmed page, else the proposed one.
    private func move(by delta: Int) {
        let next = min(max(review.index + delta, 0), review.checkpoints.count - 1)
        guard next != review.index else { return }
        review.index = next
        copied = false
        onClearVerse()
        let checkpoint = review.current
        if let page = review.confirmed[checkpoint.key]?.page ?? proposedPage(checkpoint) {
            onGoToPage(page)
        }
    }
}
