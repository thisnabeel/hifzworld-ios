import SwiftUI

struct PopQuizSheet: View {
    let marks: [MushafMarkDTO]
    let isDarkMode: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var quizzes: [PopQuizItem] = []
    @State private var index = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var revealedWordIDs: Set<Int> = []
    @State private var loadedPages: [String: MushafPage] = [:]
    @State private var extraLeadingVerses: [String: Int] = [:]
    @State private var isPullingBack = false
    @State private var availableHeight: CGFloat = 0

    private var current: PopQuizItem? {
        guard quizzes.indices.contains(index) else { return nil }
        return quizzes[index]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                content
            }
            .navigationTitle("Pop Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if current != nil {
                    footer
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Preparing quiz…")
                .tint(isDarkMode ? .white : .black)
        } else if let loadError {
            Text(loadError)
                .foregroundStyle(.secondary)
                .padding()
        } else if quizzes.isEmpty {
            Text("No marked lines to quiz with these filters.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        } else if let quiz = current {
            GeometryReader { geo in
                VStack(spacing: 16) {
                    pullBackButton

                    ForEach(Array(quiz.segments.enumerated()), id: \.element.id) { offset, segment in
                        if offset > 0 {
                            pageDivider
                        }
                        segmentView(segment)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .overlay {
                    PopQuizRevealPaintOverlay { word in
                        revealWord(word)
                    }
                    .allowsHitTesting(false)
                }
                .onAppear { availableHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, newHeight in
                    availableHeight = newHeight
                }
            }
        }
    }

    private var background: Color {
        isDarkMode ? AppTheme.mushafDarkBackground : AppTheme.mushafBackground
    }

    private var ink: Color { isDarkMode ? .white : .black }

    private var canPullMoreBack: Bool {
        guard let quiz = current, let earliest = quiz.earliestRef else { return false }
        guard !(earliest.pageNumber <= 1 && earliest.lineNumber <= 1) else { return false }
        return hasRoomForMoreLines(quiz)
    }

    private var pullBackButton: some View {
        Button {
            Task { await pullMoreVersesBack() }
        } label: {
            HStack(spacing: 8) {
                if isPullingBack {
                    ProgressView()
                        .controlSize(.small)
                        .tint(ink)
                } else {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("Earlier verses")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(canPullMoreBack && !isPullingBack ? ink : ink.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ink.opacity(isDarkMode ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ink.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPullingBack || !canPullMoreBack)
        .accessibilityHint("Adds the previous ayah as visible context above the quiz")
    }

    private var pageDivider: some View {
        Rectangle()
            .fill(ink.opacity(0.22))
            .frame(height: 1)
            .padding(.vertical, 4)
            .accessibilityLabel("Page break")
    }

    private func segmentView(_ segment: PopQuizPageSegment) -> some View {
        let lineHeight = MushafTypography.lineHeight(mushafID: segment.mushafID)
        let borderEdge: HorizontalEdge = segment.isRightPage ? .trailing : .leading
        return VStack(alignment: .leading, spacing: 8) {
            Text(segment.pageSideTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: segment.isRightPage ? .trailing : .leading)

            VStack(spacing: 0) {
                ForEach(segment.lines) { row in
                    quizLine(row, mushafID: segment.mushafID, lineHeight: lineHeight)
                }
            }
            .padding(.leading, segment.isRightPage ? 10 : 14)
            .padding(.trailing, segment.isRightPage ? 14 : 10)
            .overlay(alignment: borderEdge == .trailing ? .trailing : .leading) {
                MushafOuterBorder(edge: borderEdge, isDarkMode: isDarkMode)
            }
        }
    }

    @ViewBuilder
    private func quizLine(_ row: PopQuizRenderedLine, mushafID: Int, lineHeight: CGFloat) -> some View {
        let hasRenderableWords = row.line.words.contains {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let isGlyphHeader = mushafID == MushafID.indoPak.rawValue && !hasRenderableWords
        if isGlyphHeader {
            SurahHeaderLineView(
                surahHeaderPosition: row.line.surahHeaderPosition ?? 0,
                lineHeight: lineHeight,
                isDarkMode: isDarkMode
            )
        } else {
            MushafLineUIKitView(
                line: row.line,
                mushafID: mushafID,
                isDarkMode: isDarkMode,
                isJuzFirstLine: false,
                variationLookup: { _ in (nil, nil) },
                activeWordID: nil,
                paintedWords: visiblePaint(for: row),
                arePaintedWordsVisible: true,
                isPaintInverted: false,
                isAyahPromptMode: false,
                ayahPromptVisibleWordIDs: [],
                sessionMarks: [:],
                allowsWordTap: false,
                onWordTap: { _ in }
            )
            .frame(height: lineHeight)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button(areAllBlocksRevealed ? "Hide all" : "Reveal all") {
                toggleRevealAll()
            }
            .font(.body.weight(.semibold))
            .disabled(hiddenWordIDs(in: current).isEmpty)

            Spacer(minLength: 0)

            Text("\(index + 1) of \(quizzes.count)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink.opacity(0.7))

            Button("Next") {
                guard !quizzes.isEmpty else { return }
                index = (index + 1) % quizzes.count
                revealedWordIDs = []
            }
            .font(.body.weight(.semibold))
            .disabled(quizzes.count < 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var areAllBlocksRevealed: Bool {
        let hidden = hiddenWordIDs(in: current)
        return !hidden.isEmpty && hidden.isSubset(of: revealedWordIDs)
    }

    private func hiddenWordIDs(in quiz: PopQuizItem?) -> Set<Int> {
        guard let quiz else { return [] }
        var ids = Set<Int>()
        for segment in quiz.segments {
            for row in segment.lines {
                for (wordID, style) in row.paintedWords where style == .blackout {
                    ids.insert(wordID)
                }
            }
        }
        return ids
    }

    private func visiblePaint(for row: PopQuizRenderedLine) -> [Int: WordPaintStyle] {
        Dictionary(uniqueKeysWithValues: row.paintedWords.map { wordID, style in
            if revealedWordIDs.contains(wordID), style == .blackout {
                return (wordID, WordPaintStyle.highlight)
            }
            return (wordID, style)
        })
    }

    private func revealWord(_ word: MushafWord) {
        guard hiddenWordIDs(in: current).contains(word.id) else { return }
        revealedWordIDs.insert(word.id)
    }

    private func toggleRevealAll() {
        let hidden = hiddenWordIDs(in: current)
        if hidden.isSubset(of: revealedWordIDs) {
            revealedWordIDs.subtract(hidden)
        } else {
            revealedWordIDs.formUnion(hidden)
        }
    }

    /// Rough vertical budget for quiz chrome + mushaf lines (no scrolling).
    private func estimatedHeight(for quiz: PopQuizItem) -> CGFloat {
        let topPad: CGFloat = 12
        let bottomPad: CGFloat = 8
        let pullButton: CGFloat = 44
        let stackSpacing: CGFloat = 16
        let pageLabel: CGFloat = 20
        let segmentInnerSpacing: CGFloat = 8
        let dividerBlock: CGFloat = 9

        var height = topPad + pullButton + bottomPad
        height += stackSpacing

        for (offset, segment) in quiz.segments.enumerated() {
            if offset > 0 {
                height += stackSpacing
                height += dividerBlock
            }
            height += pageLabel + segmentInnerSpacing
            let lineHeight = MushafTypography.lineHeight(mushafID: segment.mushafID)
            height += CGFloat(segment.lines.count) * lineHeight
        }
        return height
    }

    private func hasRoomForMoreLines(_ quiz: PopQuizItem) -> Bool {
        guard availableHeight > 0 else { return true }
        let lineHeight = MushafTypography.lineHeight(mushafID: quiz.mushafID)
        // Need room for at least one more mushaf line before offering another verse.
        return estimatedHeight(for: quiz) + lineHeight <= availableHeight
    }

    private func pullMoreVersesBack() async {
        guard let quiz = current, quizzes.indices.contains(index), !isPullingBack else { return }
        guard hasRoomForMoreLines(quiz) else { return }
        isPullingBack = true
        defer { isPullingBack = false }

        let nextCount = (extraLeadingVerses[quiz.id] ?? 0) + 1
        let before = quiz.earliestRef
        await fetchPagesIfNeeded(mushafID: quiz.mushafID, beforePage: quiz.earliestPageNumber)

        guard let rebuilt = PopQuizBuilder.rebuild(
            quiz,
            extraLeadingVerses: nextCount,
            pages: loadedPages
        ) else { return }

        var candidate = rebuilt
        if candidate.earliestRef == before {
            await fetchPagesIfNeeded(mushafID: quiz.mushafID, beforePage: (before?.pageNumber ?? quiz.earliestPageNumber) - 1)
            if let again = PopQuizBuilder.rebuild(quiz, extraLeadingVerses: nextCount, pages: loadedPages) {
                candidate = again
            }
        }

        if availableHeight > 0, estimatedHeight(for: candidate) > availableHeight {
            return
        }

        extraLeadingVerses[quiz.id] = nextCount
        quizzes[index] = candidate
    }

    private func fetchPagesIfNeeded(mushafID: Int, beforePage: Int) async {
        let start = max(1, beforePage - 1)
        let needed = (start...max(start, beforePage)).filter { page in
            loadedPages[PopQuizBuilder.pageKey(mushafID: mushafID, page: page)] == nil && page >= 1
        }
        guard !needed.isEmpty else { return }
        await withTaskGroup(of: (String, MushafPage)?.self) { group in
            for page in needed {
                group.addTask {
                    do {
                        let loaded = try await APIClient.shared.fetchPage(mushafID: mushafID, position: page)
                        return (PopQuizBuilder.pageKey(mushafID: mushafID, page: page), loaded)
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let (key, page) = result {
                    loadedPages[key] = page
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        var pages: [String: MushafPage] = [:]
        let needed = PopQuizBuilder.neededPages(for: marks)
        await withTaskGroup(of: (String, MushafPage)?.self) { group in
            for item in needed {
                group.addTask {
                    do {
                        let page = try await APIClient.shared.fetchPage(mushafID: item.mushafID, position: item.page)
                        return (PopQuizBuilder.pageKey(mushafID: item.mushafID, page: item.page), page)
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let (key, page) = result {
                    pages[key] = page
                }
            }
        }
        loadedPages = pages
        quizzes = PopQuizBuilder.build(marks: marks, pages: pages)
        extraLeadingVerses = [:]
        index = 0
        revealedWordIDs = []
        isLoading = false
    }
}
