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
    @State private var actionError: String?

    private var bundle: MushafBundle? {
        bundleStore.bundle(id: bundleID)
    }

    private var pages: [Int] {
        bundle?.pageNumbers ?? []
    }

    private var pageGroups: [BundlePageGroup] {
        BundlePageGrouping.groups(for: pages)
    }

    var body: some View {
        Group {
            if let bundle {
                if pages.isEmpty {
                    ContentUnavailableView(
                        "No Pages Yet",
                        systemImage: "book",
                        description: Text("Add pages from the Mushaf tab using the bundle button in the top bar.")
                    )
                    .navigationTitle(bundle.title)
                    .toolbar { bundleToolbar(bundle) }
                    .sheet(isPresented: $showShareSheet) {
                        ShareBundleSheet(bundleTitle: bundle.title) { email in
                            try await shareBundle(bundle, email: email)
                        }
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
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if !bundle.description.isEmpty {
                                    Text(bundle.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 12)
                                        .padding(.bottom, 4)
                                }

                                Text("Pages")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                    .padding(.bottom, 6)

                                ForEach(pageGroups) { group in
                                    surahHeaderRow(group)
                                    ForEach(Array(group.pages.enumerated()), id: \.element) { offset, page in
                                        let flatIndex = group.startIndex + offset
                                        pageRow(page: page, flatIndex: flatIndex)
                                    }
                                }

                                Text("Drag a page handle onto another page to fill the range in between. Swipe a page left to remove it.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                    .padding(.bottom, 24)
                            }
                        }
                        .scrollDisabled(isDragging)
                    }
                    .navigationTitle(bundle.title)
                    .toolbar { bundleToolbar(bundle) }
                    .sheet(isPresented: $showShareSheet) {
                        ShareBundleSheet(bundleTitle: bundle.title) { email in
                            try await shareBundle(bundle, email: email)
                        }
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
                ContentUnavailableView("Bundle Not Found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func surahHeaderRow(_ group: BundlePageGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.surahTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if let subtitle = group.surahSubtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func pageRow(page: Int, flatIndex: Int) -> some View {
        let isSource = draggedPage == page
        let isTargeted = dropTargetPage == page && draggedPage != nil && draggedPage != page

        return HStack(spacing: 12) {
            dragHandle(for: page, isSource: isSource, isTargeted: isTargeted)

            SwipeToDeleteRow(isEnabled: !isDragging, onDelete: { removePageFromBundle(page) }) {
                pageRowContent(page: page, flatIndex: flatIndex, isSource: isSource, isTargeted: isTargeted)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
            } else if isSource && isDragging {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            }
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .opacity(isSource && isDragging ? 0.55 : 1)
        .padding(.horizontal, 8)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PageRowFrameKey.self,
                    value: [page: proxy.frame(in: .global)]
                )
            }
        }
    }

    private func pageRowContent(page: Int, flatIndex: Int, isSource: Bool, isTargeted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("Page \(page)")
                    .foregroundStyle(isSource && isDragging ? .secondary : .primary)

                Spacer()

                if isTargeted, let source = draggedPage, let preview = rangeAdditionPreview(from: source, to: page) {
                    Text(preview)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                } else if flatIndex == currentIndex {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if isTargeted, let source = draggedPage, let detail = rangeAdditionDetail(from: source, to: page) {
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
        .contextMenu {
            Button("Open in Mushaf") {
                currentIndex = flatIndex
                onOpenInMushaf(bundleID, page)
            }
            Button("Remove Page", role: .destructive) {
                removePageFromBundle(page)
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
    }

    private func dragHandle(for page: Int, isSource: Bool, isTargeted: Bool) -> some View {
        let isActiveSource = isDragging && isSource
        let isActiveTarget = isDragging && isTargeted
        let isHighlighted = isActiveSource || isActiveTarget

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(handleFill(isActiveSource: isActiveSource, isActiveTarget: isActiveTarget))
            .frame(width: 40, height: 44)
            .overlay {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(handleIconColor(isActiveSource: isActiveSource, isActiveTarget: isActiveTarget))
                    .symbolEffect(.bounce, value: isActiveSource)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        handleBorderColor(isActiveSource: isActiveSource, isActiveTarget: isActiveTarget),
                        lineWidth: isHighlighted ? 2 : 1
                    )
            }
            .shadow(color: isActiveSource ? Color.accentColor.opacity(0.25) : .clear, radius: 6, y: 2)
            .scaleEffect(isActiveSource ? 1.1 : (isActiveTarget ? 1.05 : 1))
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isHighlighted)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .gesture(dragHandleGesture(for: page))
            .accessibilityLabel("Drag page \(page)")
            .accessibilityHint("Drag onto another page to add the pages in between")
    }

    private func handleFill(isActiveSource: Bool, isActiveTarget: Bool) -> Color {
        if isActiveSource { return Color.accentColor.opacity(0.2) }
        if isActiveTarget { return Color.accentColor.opacity(0.12) }
        return Color(.tertiarySystemFill)
    }

    private func handleIconColor(isActiveSource: Bool, isActiveTarget: Bool) -> Color {
        if isActiveSource || isActiveTarget { return Color.accentColor }
        return Color.secondary
    }

    private func handleBorderColor(isActiveSource: Bool, isActiveTarget: Bool) -> Color {
        if isActiveSource { return Color.accentColor }
        if isActiveTarget { return Color.accentColor.opacity(0.7) }
        return Color(.separator)
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
                    Text("Page \(pages[safe: currentIndex] ?? 0)")
                        .font(.title3.bold())
                    if let page = pages[safe: currentIndex] {
                        Text(BundlePageGrouping.surahTitle(for: page))
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

    private func rangeAdditionPreview(from source: Int, to target: Int) -> String? {
        guard source != target else { return nil }
        let low = min(source, target)
        let high = max(source, target)
        let newPages = (low...high).filter { !pages.contains($0) }
        guard !newPages.isEmpty else { return "In bundle" }
        if newPages.count == 1 { return "+\(newPages[0])" }
        return "+\(newPages.first!)–\(newPages.last!)"
    }

    private func rangeAdditionDetail(from source: Int, to target: Int) -> String? {
        guard source != target else { return nil }
        let low = min(source, target)
        let high = max(source, target)
        let newPages = (low...high).filter { !pages.contains($0) }
        guard !newPages.isEmpty else { return "All pages in this range are already in the bundle." }
        let count = newPages.count
        return "Will add \(count) page\(count == 1 ? "" : "s") between \(low) and \(high)"
    }

    private func fillRange(from source: Int, to target: Int) {
        defer { clearDragState() }
        guard source != target, let bundle else { return }
        let added = bundleStore.addPageRange(from: source, through: target, to: bundle.id)
        if added > 0 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if let index = bundleStore.bundle(id: bundle.id)?.pageNumbers.firstIndex(of: target) {
                currentIndex = index
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }


    @ToolbarContentBuilder
    private func bundleToolbar(_ bundle: MushafBundle) -> some ToolbarContent {
        if auth.isSignedIn, !bundle.isShared {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share Bundle") { showShareSheet = true }
                    if bundle.serverID != nil, let listenerID = bundle.collaboratorUserID {
                        Button("Start Review") {
                            Task { await startReview(bundle: bundle, listenerID: listenerID) }
                        }
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

    private func shareBundle(_ bundle: MushafBundle, email: String) async throws {
        guard let serverID = bundle.serverID else {
            let service = RemoteBundleService()
            try await service.uploadLocalBundles(from: bundleStore, mushafID: reciteVM.mushafID)
            guard let updated = bundleStore.bundle(id: bundle.id), let serverID = updated.serverID else {
                throw APIError.httpStatus(422, message: "Bundle must be synced before sharing")
            }
            let share = try await service.share(bundleServerID: serverID, email: email)
            bundleStore.setCollaborator(userID: share.sharedWithID, name: email, for: bundle.id)
            return
        }
        let share = try await RemoteBundleService().share(bundleServerID: serverID, email: email)
        bundleStore.setCollaborator(userID: share.sharedWithID, name: email, for: bundle.id)
    }

    private func startReview(bundle: MushafBundle, listenerID: UUID) async {
        guard let serverID = bundle.serverID else {
            actionError = "Sync the bundle before starting a review"
            return
        }
        do {
            let session = try await ReviewSessionService().start(bundleServerID: serverID, listenerID: listenerID)
            let context = ReviewSessionContext(
                sessionID: session.id,
                bundleServerID: serverID,
                role: .reciter,
                partnerName: session.listener?.displayName ?? "Listener",
                livekitURL: session.livekit?.url,
                livekitToken: session.livekit?.token
            )
            let startPage = bundle.pageNumbers.first ?? 1
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
                livekitURL: session.livekit?.url,
                livekitToken: session.livekit?.token
            )
            let startPage = bundle.pageNumbers.first ?? 1
            reciteVM.enterReviewSession(context, bundle: bundle, startingPage: startPage)
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

    private let revealWidth: CGFloat = 88

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    offset = 0
                }
                onDelete()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                    Text("Remove")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(Color.red)
            }
            .buttonStyle(.plain)

            content()
                .background(Color(.systemBackground))
                .offset(x: min(0, offset + dragOffset))
                .gesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                guard isEnabled, isHorizontalSwipe(value) else { return }
                state = max(value.translation.width, -revealWidth)
            }
            .onEnded { value in
                guard isEnabled, isHorizontalSwipe(value) else { return }
                let translation = value.translation.width
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    if translation < -revealWidth * 1.4 {
                        offset = 0
                        onDelete()
                    } else if translation < -revealWidth / 2 {
                        offset = -revealWidth
                    } else {
                        offset = 0
                    }
                }
            }
    }

    private func isHorizontalSwipe(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height)
    }
}
