import SwiftUI

struct GoToPageSheet: View {
    @Binding var pageField: String
    let juzSegments: [NavigationSegment]
    let surahSegments: [NavigationSegment]
    let totalPages: Int
    let mushafID: Int
    let onGo: (Int) -> Void
    var onGoToVerse: ((Int, String) -> Void)?

    private enum BrowseTab: String, CaseIterable, Identifiable {
        case juz = "Juz"
        case surah = "Surah"
        case bookmarks = "Bookmarks"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isPageFieldFocused: Bool
    @State private var searchText = ""
    @State private var browseTab: BrowseTab = .surah
    @State private var selectedManzil: Int? = nil
    @State private var phoneticResults: [PhoneticVerseHit] = []
    @State private var phoneticSearchTask: Task<Void, Never>?
    @Bindable private var bookmarkStore = MushafBookmarkStore.shared
    @Bindable private var voiceSearch = VoiceVerseSearch.shared

    private let accent = Color(red: 0.2, green: 0.45, blue: 0.95)

    private var isDark: Bool { colorScheme == .dark }

    private var canvas: Color {
        isDark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.94, green: 0.95, blue: 0.96)
    }

    private var card: Color {
        isDark ? Color(red: 0.18, green: 0.18, blue: 0.20) : .white
    }

    private var primaryText: Color {
        isDark ? Color.white.opacity(0.95) : Color.black.opacity(0.90)
    }

    private var secondaryText: Color {
        isDark ? Color.white.opacity(0.72) : Color.black.opacity(0.55)
    }

    private var tertiaryText: Color {
        isDark ? Color.white.opacity(0.48) : Color.black.opacity(0.40)
    }

    private var stroke: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    private var fieldFill: Color {
        isDark ? Color.white.opacity(0.06) : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    private var sortedJuz: [NavigationSegment] {
        juzSegments.sorted {
            ($0.categoryPosition ?? $0.startPage) < ($1.categoryPosition ?? $1.startPage)
        }
    }

    private var sortedSurahs: [NavigationSegment] {
        surahSegments.sorted {
            ($0.categoryPosition ?? $0.startPage) < ($1.categoryPosition ?? $1.startPage)
        }
    }

    private var filteredJuz: [NavigationSegment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sortedJuz }
        return sortedJuz.filter { segment in
            let number = segment.categoryPosition ?? segment.startPage
            return "\(number)".contains(query)
                || segment.title.localizedCaseInsensitiveContains(query)
                || "juz \(number)".localizedCaseInsensitiveContains(query)
        }
    }

    private var manzilSurahs: [NavigationSegment] {
        guard let selectedManzil else { return sortedSurahs }
        return sortedSurahs.filter { segment in
            guard let number = segment.categoryPosition else { return false }
            return SurahMeta.manzil(forSurah: number) == selectedManzil
        }
    }

    private var filteredSurahs: [NavigationSegment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return manzilSurahs }
        return manzilSurahs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.categoryPosition.map { "\($0)" } ?? "").contains(query)
                || ($0.categoryPosition.map { SurahMeta.englishName($0).localizedCaseInsensitiveContains(query) } ?? false)
        }
    }

    private var bookmarkedPages: [Int] {
        bookmarkStore.pages.filter { $0 >= 1 && $0 <= totalPages }
    }

    private var filteredBookmarks: [Int] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return bookmarkedPages }
        return bookmarkedPages.filter { page in
            if "\(page)".contains(query) || "p. \(page)".localizedCaseInsensitiveContains(query) {
                return true
            }
            let surahNumber = BundlePageGrouping.resolvedSurahNumber(for: page, overrides: [:])
            if let surahNumber {
                if SurahMeta.englishName(surahNumber).localizedCaseInsensitiveContains(query) {
                    return true
                }
                if SurahMeta.arabicName(surahNumber).localizedCaseInsensitiveContains(query) {
                    return true
                }
                if "\(surahNumber)".contains(query) {
                    return true
                }
            }
            return false
        }
    }

    private var showsPhoneticResults: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PhoneticVerseSearch.looksLikePhoneticQuery(trimmed) else { return false }
        // Avoid noisy empty phonetic panels while filtering surah names like "Rahman".
        if PhoneticVerseSearch.parseVerseKey(trimmed) != nil { return true }
        if trimmed.contains(" ") { return true }
        return !phoneticResults.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    pageJumpCard
                    searchField
                    tabPicker
                    if browseTab == .surah {
                        manzilTabs
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if voiceSearch.isActive {
                            voiceResultsSection
                        }
                        if showsPhoneticResults {
                            phoneticResultsSection
                        }
                        Group {
                            switch browseTab {
                            case .juz:
                                juzGrid
                            case .surah:
                                surahList
                            case .bookmarks:
                                bookmarksList
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .background(canvas.ignoresSafeArea())
            .navigationTitle("Go to Page")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                bookmarkStore.reload(mushafID: mushafID)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .frame(width: 32, height: 32)
                            .background(fieldFill)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(canvas, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
            .onChange(of: searchText) { _, newValue in
                schedulePhoneticSearch(newValue)
            }
        }
        .preferredColorScheme(colorScheme)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { isPageFieldFocused = true }
        .onDisappear {
            phoneticSearchTask?.cancel()
            voiceSearch.cancel()
        }
    }

    private var pageJumpCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Page")

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField("0", text: $pageField)
                        .keyboardType(.numberPad)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .focused($isPageFieldFocused)
                        .frame(minWidth: 72)

                    Text("of \(totalPages)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fieldFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )

                Button(action: submitPage) {
                    Text("Go")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 56)
                        .background(canSubmitPage ? accent : accent.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitPage)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(card)
                .shadow(color: .black.opacity(isDark ? 0.35 : 0.08), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(secondaryText)
            TextField(
                "",
                text: $searchText,
                prompt: Text("Surah, 13:31, or “wa law anna…”").foregroundStyle(tertiaryText)
            )
            .font(.subheadline)
            .foregroundStyle(primaryText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(secondaryText)
                }
                .buttonStyle(.plain)
            }
            Button {
                isPageFieldFocused = false
                voiceSearch.toggle()
            } label: {
                Image(systemName: voiceSearch.isListening ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(voiceSearch.isActive ? accent : secondaryText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voiceSearch.isListening ? "Stop listening" : "Search by reciting")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(BrowseTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        browseTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(browseTab == tab ? primaryText : secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(browseTab == tab ? fieldFill : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
    }

    private var manzilTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Manzil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tertiaryText)
                    .textCase(.uppercase)
                    .tracking(0.4)
                manzilChip(title: "All", isSelected: selectedManzil == nil) {
                    selectedManzil = nil
                }
                ForEach(1...7, id: \.self) { manzil in
                    manzilChip(title: "\(manzil)", isSelected: selectedManzil == manzil) {
                        selectedManzil = manzil
                    }
                }
            }
        }
    }

    private func manzilChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? accent : card)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? accent : stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var juzGrid: some View {
        Group {
            if filteredJuz.isEmpty {
                emptyState("No juz match your search")
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                    spacing: 10
                ) {
                    ForEach(filteredJuz) { segment in
                        juzChip(segment)
                    }
                }
            }
        }
    }

    private func juzChip(_ segment: NavigationSegment) -> some View {
        let number = segment.categoryPosition ?? segment.startPage
        return Button {
            go(to: segment.startPage)
        } label: {
            VStack(spacing: 2) {
                Text("\(number)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)
                    .monospacedDigit()
                Text("Juz")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var surahList: some View {
        Group {
            if filteredSurahs.isEmpty {
                emptyState("No surahs match your search")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredSurahs) { segment in
                        surahRow(segment)
                    }
                }
            }
        }
    }

    private var bookmarksList: some View {
        Group {
            if bookmarkedPages.isEmpty {
                emptyState("No bookmarks yet. Tap the bookmark icon on a mushaf page.")
            } else if filteredBookmarks.isEmpty {
                emptyState("No bookmarks match your search")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredBookmarks, id: \.self) { page in
                        bookmarkRow(page)
                    }
                }
            }
        }
    }

    private func bookmarkRow(_ page: Int) -> some View {
        let surahNumber = BundlePageGrouping.resolvedSurahNumber(for: page, overrides: [:])
        let english = surahNumber.map { SurahMeta.englishName($0) } ?? ""
        let arabic = surahNumber.map { SurahMeta.arabicName($0) } ?? ""

        return Button {
            go(to: page)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    if !english.isEmpty {
                        Text(english)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                    }
                    if let surahNumber {
                        Text("Surah \(surahNumber)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !arabic.isEmpty {
                    Text(arabic)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(primaryText)
                        .environment(\.layoutDirection, .rightToLeft)
                }

                Text("p. \(page)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tertiaryText)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Bookmark", role: .destructive) {
                bookmarkStore.remove(page: page, mushafID: mushafID)
            }
        }
    }

    private func surahRow(_ segment: NavigationSegment) -> some View {
        let number = segment.categoryPosition ?? 0
        let arabic = number > 0 ? SurahMeta.arabicName(number) : segment.title
        let english = number > 0 ? SurahMeta.englishName(number) : ""

        return Button {
            go(to: segment.startPage)
        } label: {
            HStack(spacing: 14) {
                Text(number > 0 ? "\(number)" : "—")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .frame(width: 28, alignment: .center)

                if !english.isEmpty {
                    Text(english)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                Text(arabic)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, .rightToLeft)

                Text("p. \(segment.startPage)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tertiaryText)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var voiceResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Recitation")
                Spacer()
                if !voiceSearch.isBusy {
                    Button("Clear") { voiceSearch.dismissPanel() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tertiaryText)
                        .buttonStyle(.plain)
                }
            }
            voiceStatus
            let heard = voiceHits(voiceSearch.matches.isEmpty
                ? voiceSearch.candidate.map { [$0] } ?? []
                : voiceSearch.matches)
            if !heard.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(heard) { hit in
                        phoneticRow(hit)
                    }
                }
            }
            let others = voiceHits(voiceSearch.alternatives)
            if !others.isEmpty {
                Text(heard.isEmpty ? "Closest verses" : "Could also be")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tertiaryText)
                    .padding(.top, 4)
                LazyVStack(spacing: 8) {
                    ForEach(others) { hit in
                        phoneticRow(hit)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var voiceStatus: some View {
        switch voiceSearch.phase {
        case .needsDownload:
            voiceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recite any verse and we'll find it — recognition runs fully on your device.")
                        .font(.subheadline)
                        .foregroundStyle(primaryText)
                    Text("Needs a one-time \(voiceSearch.downloadSizeText) download.")
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                    HStack(spacing: 10) {
                        Button {
                            voiceSearch.download()
                        } label: {
                            Text("Download")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Button("Not now") { voiceSearch.dismissPanel() }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(secondaryText)
                            .buttonStyle(.plain)
                    }
                }
            }
        case .downloading(let fraction):
            voiceCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Downloading recognizer… \(Int((fraction * 100).rounded()))%")
                        .font(.subheadline)
                        .foregroundStyle(primaryText)
                        .monospacedDigit()
                    ProgressView(value: fraction)
                        .tint(accent)
                }
            }
        case .preparing:
            voiceCard {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Getting ready…")
                        .font(.subheadline)
                        .foregroundStyle(secondaryText)
                }
            }
        case .listening:
            voiceCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.18))
                            .frame(width: 40, height: 40)
                            .scaleEffect(1 + CGFloat(voiceSearch.level) * 0.6)
                            .animation(.easeOut(duration: 0.12), value: voiceSearch.level)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listening…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryText)
                        Text("Recite a verse, then tap Done")
                            .font(.caption)
                            .foregroundStyle(secondaryText)
                    }
                    Spacer()
                    Button {
                        voiceSearch.stop()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .finishing:
            voiceCard {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding the verse…")
                        .font(.subheadline)
                        .foregroundStyle(secondaryText)
                }
            }
        case .failed(let message):
            voiceCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(primaryText)
                    Button("Try again") { voiceSearch.begin() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .buttonStyle(.plain)
                }
            }
        case .idle:
            if voiceSearch.hasFinished && voiceSearch.matches.isEmpty && voiceSearch.alternatives.isEmpty {
                emptyState("Couldn't place that — try reciting a little longer")
            }
        }
    }

    private func voiceCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }

    private func voiceHits(_ verses: [TilawaVerseMatch]) -> [PhoneticVerseHit] {
        verses.compactMap { PhoneticVerseSearch.search(query: $0.verseKey, mushafID: mushafID, limit: 1).first }
    }

    private var phoneticResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Phonetic")
            if phoneticResults.isEmpty {
                emptyState("No verses match yet — try more words")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(phoneticResults) { hit in
                        phoneticRow(hit)
                    }
                }
            }
        }
    }

    private func phoneticRow(_ hit: PhoneticVerseHit) -> some View {
        Button {
            goToVerse(hit)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(hit.verseKey)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                    Spacer()
                    if let page = hit.page {
                        Text("p. \(page)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tertiaryText)
                            .monospacedDigit()
                    }
                }

                Text(PhoneticVerseSearch.highlightedSnippet(
                    hit.arabic,
                    matchWordRange: hit.matchWordRange,
                    maxChars: 90,
                    baseColor: primaryText,
                    highlightColor: accent,
                    font: .system(size: 18, weight: .medium)
                ))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .lineLimit(2)

                Text(PhoneticVerseSearch.highlightedSnippet(
                    hit.transliteration,
                    matchWordRange: hit.matchWordRange,
                    maxChars: 110,
                    baseColor: secondaryText,
                    highlightColor: accent,
                    font: .caption
                ))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(hit.page == nil)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(secondaryText)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private var canSubmitPage: Bool {
        guard let page = Int(pageField) else { return false }
        return (1...totalPages).contains(page)
    }

    private func submitPage() {
        guard let page = Int(pageField), (1...totalPages).contains(page) else { return }
        go(to: page)
    }

    private func go(to page: Int) {
        onGo(page)
        dismiss()
    }

    private func goToVerse(_ hit: PhoneticVerseHit) {
        guard let page = hit.page else { return }
        if let onGoToVerse {
            onGoToVerse(page, hit.verseKey)
        } else {
            onGo(page)
        }
        dismiss()
    }

    private func schedulePhoneticSearch(_ query: String) {
        phoneticSearchTask?.cancel()
        guard PhoneticVerseSearch.looksLikePhoneticQuery(query) else {
            phoneticResults = []
            return
        }
        let mushafID = self.mushafID
        phoneticSearchTask = Task(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let hits = PhoneticVerseSearch.search(query: query, mushafID: mushafID)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                phoneticResults = hits
            }
        }
    }
}
