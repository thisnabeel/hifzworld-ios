import SwiftUI
import UIKit

private struct PageRowFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct BundleDetailView: View {
    let bundleID: UUID
    @Bindable var bundleStore: BundleStore
    @Bindable var auth: AuthService
    @Bindable var reciteVM: ReciteViewModel
    let onOpenInMushaf: (UUID, Int) -> Void

    @State private var currentIndex = 0
    @State private var draggedPage: Int?
    @State private var dropTargetPage: Int?
    @State private var rowFrames: [Int: CGRect] = [:]
    @State private var isDragging = false
    @State private var showShareSheet = false
    @State private var showEditTitleSheet = false
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var actionError: String?

    private var bundle: MushafBundle? {
        bundleStore.bundle(id: bundleID)
    }

    private var pages: [Int] {
        bundle?.pageNumbers ?? []
    }

    private var pageGroups: [BundlePageGroup] {
        BundlePageGrouping.groups(for: pages, surahOverrides: bundle?.pageSurahOverrides ?? [:])
    }

    private var surahOverrides: [Int: Int] {
        bundle?.pageSurahOverrides ?? [:]
    }

    var body: some View {
        Group {
            if let bundle {
                if pages.isEmpty {
                    ContentUnavailableView(
                        "No Pages Yet",
                        systemImage: "book",
                        description: Text("Add pages from the Mushaf tab using the deck button in the top bar.")
                    )
                    .navigationTitle(bundle.title)
                    .toolbar { bundleToolbar(bundle) }
                    .sheet(isPresented: $showShareSheet) {
                        ShareBundleSheet(bundleTitle: bundle.title) {
                            try await createInviteLink(for: bundle)
                        }
                    }
                    .sheet(isPresented: $showEditTitleSheet) {
                        EditBundleSheet(
                            title: $editTitle,
                            description: $editDescription,
                            onSave: { saveEditedTitle() }
                        )
                    }
                    .alert("Error", isPresented: Binding(
                        get: { actionError != nil },
                        set: { if !$0 { actionError = nil } }
                    )) {
                        Button("OK") { actionError = nil }
                    } message: {
                        Text(actionError ?? "")
                    }
                } else {
                    VStack(spacing: 0) {
                        traversalBar
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                if !bundle.description.isEmpty {
                                    Text(bundle.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 12)
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("Pages")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                        Spacer()
                                        Text("\(pages.count)")
                                            .font(.caption.monospacedDigit().weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)

                                    ForEach(pageGroups) { group in
                                        surahSection(group)
                                    }
                                }

                                Text("Drag a handle onto another page to fill a range, or onto another surah’s pages to regroup a boundary page. Swipe left to remove.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 28)
                            }
                        }
                        .scrollDisabled(isDragging)
                    }
                    .navigationTitle(bundle.title)
                    .toolbar { bundleToolbar(bundle) }
                    .sheet(isPresented: $showShareSheet) {
                        ShareBundleSheet(bundleTitle: bundle.title) {
                            try await createInviteLink(for: bundle)
                        }
                    }
                    .sheet(isPresented: $showEditTitleSheet) {
                        EditBundleSheet(
                            title: $editTitle,
                            description: $editDescription,
                            onSave: { saveEditedTitle() }
                        )
                    }
                    .alert("Error", isPresented: Binding(
                        get: { actionError != nil },
                        set: { if !$0 { actionError = nil } }
                    )) {
                        Button("OK") { actionError = nil }
                    } message: {
                        Text(actionError ?? "")
                    }
                    .onPreferenceChange(PageRowFrameKey.self) { rowFrames = $0 }
                    .onAppear {
                        currentIndex = min(currentIndex, max(pages.count - 1, 0))
                    }
                    .onChange(of: pages.count) { _, count in
                        if count == 0 {
                            currentIndex = 0
                        } else if currentIndex >= count {
                            currentIndex = count - 1
                        }
                    }
                }
            } else {
                ContentUnavailableView("Deck Not Found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func surahSection(_ group: BundlePageGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.surahTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle = group.surahSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(pageRangeLabel(for: group.pages))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(group.pages.enumerated()), id: \.element) { offset, page in
                    let flatIndex = group.startIndex + offset
                    if offset > 0 {
                        Divider()
                            .padding(.leading, 54)
                    }
                    pageRow(page: page, flatIndex: flatIndex)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func pageRangeLabel(for pages: [Int]) -> String {
        guard let first = pages.first, let last = pages.last else { return "" }
        if pages.count == 1 { return "p. \(PrintedPage.display(first))" }
        let contiguous = zip(pages, pages.dropFirst()).allSatisfy { $1 == $0 + 1 }
        if contiguous {
            return "p. \(PrintedPage.display(first))–\(PrintedPage.display(last))"
        }
        return "\(pages.count) pages"
    }

    private func pageRow(page: Int, flatIndex: Int) -> some View {
        let isSource = draggedPage == page
        let isTargeted = dropTargetPage == page && draggedPage != nil && draggedPage != page
        let isSelected = flatIndex == currentIndex && !isDragging

        return SwipeToDeleteRow(isEnabled: !isDragging, onDelete: { removePageFromBundle(page) }) {
            HStack(spacing: 12) {
                dragHandle(for: page, isSource: isSource, isTargeted: isTargeted)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Page \(PrintedPage.display(page))")
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSource && isDragging ? .secondary : .primary)

                        if isTargeted, let source = draggedPage, let preview = dropPreview(from: source, to: page) {
                            Text(preview)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }

                        Spacer(minLength: 0)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    if isTargeted, let source = draggedPage, let detail = dropDetail(from: source, to: page) {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isDragging else { return }
                    currentIndex = flatIndex
                    onOpenInMushaf(bundleID, page)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isTargeted {
                    Color.accentColor.opacity(0.12)
                } else if isSource && isDragging {
                    Color.primary.opacity(0.06)
                } else if isSelected {
                    Color.accentColor.opacity(0.08)
                } else {
                    Color(.secondarySystemGroupedBackground)
                }
            }
            .contextMenu {
                Button("Open in Mushaf") {
                    currentIndex = flatIndex
                    onOpenInMushaf(bundleID, page)
                }
                ForEach(BundlePageGrouping.groupingCandidates(for: page), id: \.self) { surahNumber in
                    let isCurrent = BundlePageGrouping.resolvedSurahNumber(for: page, overrides: surahOverrides) == surahNumber
                    Button {
                        bundleStore.setPageSurahOverride(surahNumber, for: page, in: bundleID)
                    } label: {
                        if isCurrent {
                            Label("Show under \(BundlePageGrouping.englishName(forSurahNumber: surahNumber))", systemImage: "checkmark")
                        } else {
                            Text("Show under \(BundlePageGrouping.englishName(forSurahNumber: surahNumber))")
                        }
                    }
                    .disabled(isCurrent)
                }
                Button("Remove Page", role: .destructive) {
                    removePageFromBundle(page)
                }
            }
        }
        .opacity(isSource && isDragging ? 0.55 : 1)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PageRowFrameKey.self,
                    value: [page: proxy.frame(in: .global)]
                )
            }
        }
    }

    private func removePageFromBundle(_ page: Int) {
        guard let idx = pages.firstIndex(of: page) else { return }
        bundleStore.removePage(page, from: bundleID)
        let newCount = bundleStore.bundle(id: bundleID)?.pageNumbers.count ?? 0
        if newCount == 0 {
            currentIndex = 0
        } else if idx < currentIndex {
            currentIndex -= 1
        } else if idx == currentIndex {
            currentIndex = min(currentIndex, newCount - 1)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await pushBundleIfNeeded() }
    }

    private func pushBundleIfNeeded() async {
        guard let bundle = bundleStore.bundle(id: bundleID), bundle.serverID != nil else { return }
        do {
            try await RemoteBundleService().updateBundle(bundle, mushafID: reciteVM.mushafID)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func dragHandle(for page: Int, isSource: Bool, isTargeted: Bool) -> some View {
        let isActiveSource = isDragging && isSource
        let isActiveTarget = isDragging && isTargeted
        let isHighlighted = isActiveSource || isActiveTarget

        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(handleIconColor(isActiveSource: isActiveSource, isActiveTarget: isActiveTarget))
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(handleFill(isActiveSource: isActiveSource, isActiveTarget: isActiveTarget))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        handleBorderColor(isActiveSource: isActiveSource, isActiveTarget: isActiveTarget),
                        lineWidth: isHighlighted ? 1.5 : 0
                    )
            }
            .scaleEffect(isActiveSource ? 1.08 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isHighlighted)
            .contentShape(Rectangle())
            .gesture(dragHandleGesture(for: page))
            .accessibilityLabel("Drag page \(PrintedPage.display(page))")
            .accessibilityHint("Drag onto another page to add the pages in between")
    }

    private func handleFill(isActiveSource: Bool, isActiveTarget: Bool) -> Color {
        if isActiveSource { return Color.accentColor.opacity(0.22) }
        if isActiveTarget { return Color.accentColor.opacity(0.14) }
        return Color(.tertiarySystemFill)
    }

    private func handleIconColor(isActiveSource: Bool, isActiveTarget: Bool) -> Color {
        if isActiveSource || isActiveTarget { return Color.accentColor }
        return Color.secondary
    }

    private func handleBorderColor(isActiveSource: Bool, isActiveTarget: Bool) -> Color {
        if isActiveSource { return Color.accentColor }
        if isActiveTarget { return Color.accentColor.opacity(0.7) }
        return .clear
    }

    private func dragHandleGesture(for page: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if draggedPage == nil {
                    draggedPage = page
                    isDragging = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }

                let hovered = pageAt(location: value.location)
                if dropTargetPage != hovered {
                    dropTargetPage = hovered
                    if hovered != nil, hovered != draggedPage {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    }
                }
            }
            .onEnded { _ in
                if let source = draggedPage, let target = dropTargetPage, source != target {
                    fillRange(from: source, to: target)
                } else {
                    clearDragState()
                }
            }
    }

    private func pageAt(location: CGPoint) -> Int? {
        rowFrames
            .filter { $0.value.contains(location) }
            .max(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height })?
            .key
    }

    private var traversalBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    currentIndex = max(0, currentIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .disabled(currentIndex == 0)

                Spacer()

                VStack(spacing: 2) {
                    Text("Page \(PrintedPage.display(pages[safe: currentIndex] ?? 0))")
                        .font(.title3.bold())
                    if let page = pages[safe: currentIndex] {
                        Text(BundlePageGrouping.surahTitle(for: page, overrides: surahOverrides))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(currentIndex + 1) of \(pages.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    currentIndex = min(pages.count - 1, currentIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .disabled(currentIndex >= pages.count - 1)
            }

            Button("Open in Mushaf") {
                if let page = pages[safe: currentIndex] {
                    onOpenInMushaf(bundleID, page)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private func dropPreview(from source: Int, to target: Int) -> String? {
        guard source != target else { return nil }
        if let moveLabel = surahMovePreview(from: source, to: target) {
            return moveLabel
        }
        return rangeAdditionPreview(from: source, to: target)
    }

    private func dropDetail(from source: Int, to target: Int) -> String? {
        guard source != target else { return nil }
        if let moveDetail = surahMoveDetail(from: source, to: target) {
            if let rangeDetail = rangeAdditionDetail(from: source, to: target),
               !rangeDetail.hasPrefix("All pages") {
                return "\(moveDetail) \(rangeDetail)"
            }
            return moveDetail
        }
        return rangeAdditionDetail(from: source, to: target)
    }

    private func surahMovePreview(from source: Int, to target: Int) -> String? {
        guard let targetSurah = BundlePageGrouping.resolvedSurahNumber(for: target, overrides: surahOverrides) else {
            return nil
        }
        let sourceSurah = BundlePageGrouping.resolvedSurahNumber(for: source, overrides: surahOverrides)
        guard sourceSurah != targetSurah else { return nil }
        let candidates = BundlePageGrouping.groupingCandidates(for: source)
        guard candidates.contains(targetSurah) else { return nil }
        return "→ \(BundlePageGrouping.englishName(forSurahNumber: targetSurah))"
    }

    private func surahMoveDetail(from source: Int, to target: Int) -> String? {
        guard let targetSurah = BundlePageGrouping.resolvedSurahNumber(for: target, overrides: surahOverrides) else {
            return nil
        }
        let sourceSurah = BundlePageGrouping.resolvedSurahNumber(for: source, overrides: surahOverrides)
        guard sourceSurah != targetSurah else { return nil }
        let candidates = BundlePageGrouping.groupingCandidates(for: source)
        guard candidates.contains(targetSurah) else { return nil }
        return "Show page \(PrintedPage.display(source)) under \(BundlePageGrouping.englishName(forSurahNumber: targetSurah))."
    }

    private func rangeAdditionPreview(from source: Int, to target: Int) -> String? {
        guard source != target else { return nil }
        let low = min(source, target)
        let high = max(source, target)
        let newPages = (low...high).filter { !pages.contains($0) }
        guard !newPages.isEmpty else { return "In deck" }
        if newPages.count == 1 { return "+\(newPages[0])" }
        return "+\(newPages.first!)–\(newPages.last!)"
    }

    private func rangeAdditionDetail(from source: Int, to target: Int) -> String? {
        guard source != target else { return nil }
        let low = min(source, target)
        let high = max(source, target)
        let newPages = (low...high).filter { !pages.contains($0) }
        guard !newPages.isEmpty else { return "All pages in this range are already in the deck." }
        let count = newPages.count
        return "Will add \(count) page\(count == 1 ? "" : "s") between \(low) and \(high)"
    }

    private func fillRange(from source: Int, to target: Int) {
        defer { clearDragState() }
        guard source != target, let bundle else { return }

        var didChange = false
        if let targetSurah = BundlePageGrouping.resolvedSurahNumber(for: target, overrides: surahOverrides) {
            let sourceSurah = BundlePageGrouping.resolvedSurahNumber(for: source, overrides: surahOverrides)
            let candidates = BundlePageGrouping.groupingCandidates(for: source)
            if sourceSurah != targetSurah, candidates.contains(targetSurah) {
                bundleStore.setPageSurahOverride(targetSurah, for: source, in: bundle.id)
                didChange = true
            }
        }

        let added = bundleStore.addPageRange(from: source, through: target, to: bundle.id)
        if added > 0 {
            didChange = true
            if let index = bundleStore.bundle(id: bundle.id)?.pageNumbers.firstIndex(of: target) {
                currentIndex = index
            }
        }

        if didChange {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await pushBundleIfNeeded() }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }


    @ToolbarContentBuilder
    private func bundleToolbar(_ bundle: MushafBundle) -> some ToolbarContent {
        if !bundle.isShared {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Title") {
                    editTitle = bundle.title
                    editDescription = bundle.description
                    showEditTitleSheet = true
                }
            }
        }
        if auth.isSignedIn, !bundle.isShared {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share Deck") { showShareSheet = true }
                    if bundle.serverID != nil,
                       let listenerID = bundle.collaboratorUserID,
                       bundle.shareStatus == "accepted" {
                        Button("Start Review") {
                            Task { await startReview(bundle: bundle, listenerID: listenerID) }
                        }
                    } else if bundle.collaboratorUserID != nil, bundle.shareStatus != "accepted" {
                        Button("Waiting for accept…") {}
                            .disabled(true)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        if auth.isSignedIn, bundle.isShared, bundle.serverID != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Join Review") {
                    Task { await joinAsListener(bundle: bundle) }
                }
            }
        }
    }

    private func saveEditedTitle() {
        bundleStore.updateBundle(
            id: bundleID,
            title: editTitle,
            description: editDescription
        )
        Task { await pushBundleIfNeeded() }
    }

    private func createInviteLink(for bundle: MushafBundle) async throws -> URL {
        let service = RemoteBundleService()
        let serverID: UUID
        if let existing = bundle.serverID {
            serverID = existing
        } else {
            try await service.uploadLocalBundles(from: bundleStore, mushafID: reciteVM.mushafID)
            guard let updated = bundleStore.bundle(id: bundle.id), let synced = updated.serverID else {
                throw APIError.httpStatus(422, message: "Deck must be synced before sharing")
            }
            serverID = synced
        }
        let invite = try await service.createInviteLink(bundleServerID: serverID)
        guard let url = URL(string: invite.url) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func startReview(bundle: MushafBundle, listenerID: UUID) async {
        guard let serverID = bundle.serverID else {
            actionError = "Sync the deck before starting a review"
            return
        }
        do {
            let session = try await ReviewSessionService().start(bundleServerID: serverID, listenerID: listenerID)
            let context = ReviewSessionContext(
                sessionID: session.id,
                bundleServerID: serverID,
                role: .reciter,
                partnerName: session.listener?.displayName ?? "Listener",
                reciterID: session.reciterID
            )
            let startPage = session.currentPage ?? bundle.pageNumbers.first ?? 1
            reciteVM.enterReviewSession(context, bundle: bundle, startingPage: startPage)
            onOpenInMushaf(bundle.id, startPage)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func joinAsListener(bundle: MushafBundle) async {
        guard let serverID = bundle.serverID else { return }
        do {
            let pending = try await ReviewSessionService().pendingSession(bundleServerID: serverID)
            let session = try await ReviewSessionService().join(sessionID: pending.id)
            let context = ReviewSessionContext(
                sessionID: session.id,
                bundleServerID: serverID,
                role: .listener,
                partnerName: session.reciter?.displayName ?? "Reciter",
                reciterID: session.reciterID
            )
            let startPage = session.currentPage ?? bundle.pageNumbers.first ?? 1
            reciteVM.enterReviewSession(context, bundle: bundle, startingPage: startPage)
            onOpenInMushaf(bundle.id, startPage)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func clearDragState() {
        draggedPage = nil
        dropTargetPage = nil
        isDragging = false
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct SwipeToDeleteRow<Content: View>: View {
    var isEnabled = true
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    private let revealWidth: CGFloat = 76

    private var totalOffset: CGFloat {
        min(0, max(offset + dragOffset, -revealWidth))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    offset = 0
                }
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove page")

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: totalOffset)
                .gesture(swipeGesture)
        }
        .clipped()
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                guard isEnabled, isHorizontalSwipe(value) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isEnabled, isHorizontalSwipe(value) else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        offset = 0
                    }
                    return
                }
                let projected = offset + value.translation.width
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    if projected < -revealWidth * 1.35 {
                        offset = 0
                        onDelete()
                    } else if projected < -revealWidth / 2 {
                        offset = -revealWidth
                    } else {
                        offset = 0
                    }
                }
            }
    }

    private func isHorizontalSwipe(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height) * 1.25
    }
}
