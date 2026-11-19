import SwiftUI

/// Popover from the top bar's "Juz N" button: the juz's page range with the current page
/// marked, a slider for picking an exact page, and a row of jumps: first page, 2/4, 3/4, 4/4, last page.
struct JuzRangePopover: View {
    let juz: NavigationSegment
    /// Every juz of the mushaf; dragging the juz title switches between them.
    var allJuz: [NavigationSegment] = []
    let currentPage: Int
    let mushafID: Int
    /// The mushaf's own quarter marks (start of juz, الربع, النصف, الثلثة), when it prints them.
    var printedQuarterStartPages: [Int]? = nil
    let onGoToPage: (Int) -> Void

    @State private var draftPage: Double = 0
    @State private var isDragging = false
    /// Juz being previewed while the title is dragged.
    @State private var scrubJuz: NavigationSegment?

    private var orderedJuz: [NavigationSegment] {
        allJuz.sorted { ($0.categoryPosition ?? 0) < ($1.categoryPosition ?? 0) }
    }

    /// The juz the header describes: the one being scrubbed to, else the current one.
    private var headerJuz: NavigationSegment { scrubJuz ?? juz }

    private var pageCount: Int { juz.endPage - juz.startPage + 1 }

    private var shownPage: Int {
        isDragging ? Int(draftPage.rounded()) : currentPage
    }

    /// First page of each quarter of the juz: the printed marks, else split evenly by page count.
    private var quarterStartPages: [Int] {
        if let printedQuarterStartPages, printedQuarterStartPages.count == 4 {
            return printedQuarterStartPages
        }
        return (0..<4).map { juz.startPage + Int((Double($0 * pageCount) / 4).rounded()) }
    }

    private var currentQuarterIndex: Int {
        quarterStartPages.lastIndex { $0 <= shownPage } ?? 0
    }

    private func printed(_ page: Int) -> Int {
        PrintedPage.display(page, mushafID: mushafID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                if orderedJuz.count > 1 {
                    JuzScrubber(juz: juz, orderedJuz: orderedJuz, scrubJuz: $scrubJuz) { target in
                        draftPage = Double(target.startPage)
                        onGoToPage(target.startPage)
                    }
                } else {
                    Text("Juz \(juz.categoryPosition ?? 0)")
                        .font(.headline)
                }
                Spacer(minLength: 12)
                Text("Pages \(printed(headerJuz.startPage))–\(printed(headerJuz.endPage))")
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(scrubJuz == nil ? Color.secondary : AppTheme.accent)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: headerJuz.startPage)
            }

            VStack(spacing: 4) {
                Text("Page \(printed(shownPage))")
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: shownPage)
                Text("\(shownPage - juz.startPage + 1) of \(pageCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            // Right-to-left like the mushaf: first page on the right, last on the left.
            if pageCount > 1 {
                VStack(spacing: 2) {
                    Slider(
                        value: $draftPage,
                        in: Double(juz.startPage)...Double(juz.endPage),
                        step: 1
                    ) { editing in
                        isDragging = editing
                        if !editing {
                            onGoToPage(Int(draftPage.rounded()))
                        }
                    }
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Page in juz")
                    .accessibilityValue("Page \(printed(shownPage))")

                    HStack {
                        Text("\(printed(juz.startPage))")
                        Spacer()
                        Text("\(printed(juz.endPage))")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .environment(\.layoutDirection, .rightToLeft)
            }

            jumpRow
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { draftPage = Double(currentPage) }
        .onChange(of: currentPage) { _, page in
            if !isDragging { draftPage = Double(page) }
        }
    }

    /// Right-to-left like the slider: first page on the right edge, then 2/4, 3/4, 4/4, last page on the left.
    /// The 1st quarter is the juz start, so the first-page button covers it.
    private var jumpRow: some View {
        HStack(spacing: 8) {
            jumpButton(systemImage: "forward.end.fill", label: "First page of juz", page: juz.startPage)
            if pageCount >= 4 {
                ForEach(1..<4, id: \.self) { index in
                    quarterButton(index: index, page: quarterStartPages[index])
                }
            } else {
                Spacer(minLength: 0)
            }
            jumpButton(systemImage: "backward.end.fill", label: "Last page of juz", page: juz.endPage)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func quarterButton(index: Int, page: Int) -> some View {
        let isCurrent = currentQuarterIndex == index
        let ordinals = ["1st", "2nd", "3rd", "4th"]
        return Button {
            draftPage = Double(page)
            onGoToPage(page)
        } label: {
            VStack(spacing: 2) {
                Text("\(index + 1)/4")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                Text("p. \(printed(page))")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .opacity(0.8)
            }
            // Dark text on the bright accent; primary text on a solid-enough fill otherwise.
            .foregroundStyle(isCurrent ? Color.black : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? AppTheme.accent : Color.primary.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isCurrent ? Color.clear : Color.primary.opacity(0.18), lineWidth: 1)
            )
            .environment(\.layoutDirection, .leftToRight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ordinals[index]) quarter of juz, page \(printed(page))")
    }

    private func jumpButton(systemImage: String, label: String, page: Int) -> some View {
        let isCurrent = currentPage == page
        return Button {
            draftPage = Double(page)
            onGoToPage(page)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.secondary : Color.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.14)))
                .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                // Glyphs are chosen for their on-screen side; don't let RTL mirror them.
                .environment(\.layoutDirection, .leftToRight)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .accessibilityLabel(label)
    }
}

/// The popover's "Juz N" title as a horizontal scrubber: drag (or tap the chevrons) to switch juz.
/// Right-to-left like the mushaf: dragging left moves to the next juz, right to the previous one.
private struct JuzScrubber: View {
    let juz: NavigationSegment
    let orderedJuz: [NavigationSegment]
    @Binding var scrubJuz: NavigationSegment?
    let onCommit: (NavigationSegment) -> Void

    /// Drag distance per juz step.
    private let stepWidth: CGFloat = 26
    @State private var dragStartIndex: Int?
    @State private var nudge: CGFloat = 0
    @AppStorage("juzScrubber.hasScrubbed") private var hasScrubbed = false

    private var currentIndex: Int {
        orderedJuz.firstIndex { $0.categoryPosition == juz.categoryPosition } ?? 0
    }

    private var shownIndex: Int {
        scrubJuz.flatMap { target in orderedJuz.firstIndex { $0.categoryPosition == target.categoryPosition } }
            ?? currentIndex
    }

    private var isScrubbing: Bool { dragStartIndex != nil }

    private func number(at index: Int) -> Int? {
        orderedJuz.indices.contains(index) ? orderedJuz[index].categoryPosition : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                stepButton(systemImage: "chevron.left", label: "Next juz", delta: 1)

                HStack(spacing: 8) {
                    // Neighbours fade in while dragging, like a ticker.
                    neighbour(number(at: shownIndex + 1))
                    Text("Juz \(number(at: shownIndex) ?? 0)")
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText(value: Double(shownIndex)))
                        .fixedSize()
                    neighbour(number(at: shownIndex - 1))
                }

                stepButton(systemImage: "chevron.right", label: "Previous juz", delta: -1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isScrubbing ? AppTheme.accent.opacity(0.22) : Color.primary.opacity(0.1))
            )
            .overlay(
                Capsule().stroke(isScrubbing ? AppTheme.accent : Color.primary.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(isScrubbing ? 1.06 : 1)
            .offset(x: nudge)
            .animation(.snappy(duration: 0.2), value: isScrubbing)
            .animation(.snappy(duration: 0.15), value: shownIndex)
            .contentShape(Capsule())
            .gesture(scrubGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Juz \(number(at: shownIndex) ?? 0)")
            .accessibilityHint("Swipe up or down to change juz")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(by: 1)
                case .decrement: step(by: -1)
                @unknown default: break
                }
            }

            if !hasScrubbed {
                Label("Drag to switch juz", systemImage: "hand.draw")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .transition(.opacity)
            }
        }
        .task {
            guard !hasScrubbed else { return }
            // One gentle sideways nudge hints that the chip moves.
            try? await Task.sleep(for: .milliseconds(450))
            for x: CGFloat in [-7, 6, -3, 0] {
                withAnimation(.easeInOut(duration: 0.12)) { nudge = x }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    @ViewBuilder
    private func neighbour(_ number: Int?) -> some View {
        if isScrubbing {
            Text(number.map(String.init) ?? "")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                // Room for two digits so the chip doesn't shift between 9 and 10.
                .frame(minWidth: 20)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    private func stepButton(systemImage: String, label: String, delta: Int) -> some View {
        let enabled = orderedJuz.indices.contains(currentIndex + delta)
        return Button {
            step(by: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? Color.primary.opacity(0.7) : Color.primary.opacity(0.2))
                .frame(width: 22, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isScrubbing)
        .accessibilityLabel(label)
    }

    private func step(by delta: Int) {
        let target = currentIndex + delta
        guard orderedJuz.indices.contains(target) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        markScrubbed()
        onCommit(orderedJuz[target])
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragStartIndex == nil {
                    dragStartIndex = currentIndex
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                let start = dragStartIndex ?? currentIndex
                // Leftward drag moves forward through the juz, as pages do in the mushaf.
                let steps = Int((-value.translation.width / stepWidth).rounded())
                let index = min(max(start + steps, 0), orderedJuz.count - 1)
                if index != shownIndex {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                scrubJuz = index == currentIndex ? nil : orderedJuz[index]
            }
            .onEnded { _ in
                let target = scrubJuz
                dragStartIndex = nil
                scrubJuz = nil
                guard let target else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                markScrubbed()
                onCommit(target)
            }
    }

    private func markScrubbed() {
        guard !hasScrubbed else { return }
        withAnimation { hasScrubbed = true }
    }
}
