import SwiftUI

enum AppGuideTopic: String, CaseIterable, Identifiable, Hashable {
    case mushaf
    case spread
    case marks
    case decks
    case taraweeh
    case coach
    case journal
    case feedback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mushaf: return "Mushaf"
        case .spread: return "Two-page spread"
        case .marks: return "Marks & paint"
        case .decks: return "Decks"
        case .taraweeh: return "Taraweeh"
        case .coach: return "Recite with a friend"
        case .journal: return "Journal"
        case .feedback: return "Feedback & Pop Quiz"
        }
    }

    var systemImage: String {
        switch self {
        case .mushaf: return "book.fill"
        case .spread: return "rectangle.split.2x1"
        case .marks: return "pencil.tip.crop.circle"
        case .decks: return "rectangle.stack.fill"
        case .taraweeh: return "moon.stars.fill"
        case .coach: return "person.2.fill"
        case .journal: return "book.pages.fill"
        case .feedback: return "checklist"
        }
    }

    var summary: String {
        switch self {
        case .mushaf: return "Read, bookmark, and jump to any page or verse"
        case .spread: return "Rotate to see facing pages like an open mushaf"
        case .marks: return "Highlight words, mark mistakes, and review them"
        case .decks: return "Save page sets and open only those pages"
        case .taraweeh: return "Plan nightly juz portions for Ramadan"
        case .coach: return "Let a friend mark while you recite"
        case .journal: return "Track days, marks, and recordings"
        case .feedback: return "Filter marks and quiz yourself from them"
        }
    }

    var imageName: String {
        switch self {
        case .mushaf: return "GuideMushaf"
        case .spread: return "GuideSpread"
        case .marks: return "GuideMarks"
        case .decks: return "GuideDecks"
        case .taraweeh: return "GuideTaraweeh"
        case .coach: return "GuideCoach"
        case .journal: return "GuideJournal"
        case .feedback: return "GuideFeedback"
        }
    }

    var paragraphs: [String] {
        switch self {
        case .mushaf:
            return [
                "The Mushaf tab is your main reading surface. Swipe pages, tap the search icon to jump by page, juz, surah, or verse (for example 2:186), and the matching ayah lights up briefly so you can find your place.",
                "Use the bookmark icon to save a page, and the plus icon to add the current page to a deck.",
            ]
        case .spread:
            return [
                "Turn the phone sideways to open a two-page spread — odd page on the right, even on the left — just like a printed mushaf.",
                "Search, bookmarks, and marks still work in landscape. Rotate back to portrait anytime for a single-page view.",
            ]
        case .marks:
            return [
                "Tap the pencil to enter paint or marking mode. Highlight words you want to remember, or mark mistakes as you recite.",
                "Use Next / Prev mistake to jump between marked words. Invert and visibility controls help you focus on only what you marked.",
            ]
        case .decks:
            return [
                "Decks are collections of mushaf pages — a surah, weak pages, or tonight’s review set.",
                "Open a deck to page only through those pages. Record from a deck when you want a take tied to that set.",
            ]
        case .taraweeh:
            return [
                "Open Taraweeh from the moon icon on the Decks tab. It builds a night-by-night plan for Ramadan so you know which juz (or part of a juz) to recite each night.",
                "Set your finish night in Leading plan — the calendar updates the load per night. Tap a night to open those pages in the Mushaf. Green strength shows how much you’ve practiced that night’s pages.",
            ]
        case .coach:
            return [
                "Sign in, then tap the person icon to mark for yourself or pick a friend. While coaching, a banner shows who you’re marking for.",
                "Send them mail with page links from the envelope, and check Inbox in the sidebar for messages back. Sign in is required for sharing and inbox.",
            ]
        case .journal:
            return [
                "Journal is your day-by-day history: which surahs you touched, how many mistakes you marked, and any recordings from that day.",
                "Use the red microphone on the Mushaf to start a recording; pages you view while recording are saved with the take.",
            ]
        case .feedback:
            return [
                "Open the Marks tab to filter feedback by who marked you and which deck it came from.",
                "Pop Quiz builds a short quiz from your marks so you can re-test weak spots without hunting through the mushaf.",
            ]
        }
    }

    var tips: [String] {
        switch self {
        case .mushaf:
            return [
                "Verse search highlights the ayah in light blue for a couple of seconds.",
                "Use Go to Page for juz, surah, manzil, or phonetic search.",
            ]
        case .spread:
            return ["The drawer tip card reminds you: rotate for both pages."]
        case .marks:
            return [
                "Repeated marks on the same word darken (heat) so weak spots stand out.",
                "Helper / prompt mode can hide words so you recall them from memory.",
            ]
        case .decks:
            return ["Create a deck from the current page, a surah range, or selected pages."]
        case .taraweeh:
            return [
                "Strength comes from marks and recordings on that night’s pages.",
                "Adjust finish night anytime — the calendar recalculates portions.",
            ]
        case .coach:
            return ["Exit coaching from the banner when you’re done."]
        case .journal:
            return ["Days with marks or recordings fill in on the calendar."]
        case .feedback:
            return ["Pop Quiz is on the Marks screen when you’re signed in."]
        }
    }
}

struct AppGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A short tour of Hifzworld’s main features. Tap any topic for a screenshot and how-to.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("Contents") {
                    ForEach(AppGuideTopic.allCases) { topic in
                        NavigationLink(value: topic) {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(topic.title)
                                        .font(.body.weight(.semibold))
                                    Text(topic.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } icon: {
                                Image(systemName: topic.systemImage)
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: AppGuideTopic.self) { topic in
                AppGuideTopicDetailView(topic: topic)
            }
        }
    }
}

private struct AppGuideTopicDetailView: View {
    let topic: AppGuideTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                guideScreenshot

                VStack(alignment: .leading, spacing: 10) {
                    Label(topic.title, systemImage: topic.systemImage)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.body)
                            .foregroundStyle(.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !topic.tips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tips")
                            .font(.headline)
                        ForEach(Array(topic.tips.enumerated()), id: \.offset) { _, tip in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.12))
                                    .padding(.top, 2)
                                Text(tip)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.95, green: 0.45, blue: 0.12).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var guideScreenshot: some View {
        Image(topic.imageName)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .accessibilityLabel("Screenshot of \(topic.title)")
    }
}
