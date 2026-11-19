import SwiftUI

/// A page layout the reader can pick: a digital mushaf, or a printed scan drawn over it.
struct MushafLayout: Hashable, Identifiable {
    let mushaf: MushafID
    let isScanned: Bool

    var id: Int { isScanned ? -mushaf.rawValue : mushaf.rawValue }

    /// The scan edition shown over the digital mushaf (nil for the digital layouts).
    var scan: ScanStore? { isScanned ? ScanStore.forMushaf(mushaf.rawValue) : nil }

    var title: String { scan?.edition.title ?? mushaf.title }

    var subtitle: String {
        guard isScanned else { return mushaf.subtitle }
        switch mushaf {
        case .indoPak: return "Printed Taj page · 13 lines per page"
        case .uthmani: return "Printed Madinah page · 15 lines per page"
        }
    }

    /// Every layout on offer, each scan next to its digital mushaf.
    static var all: [MushafLayout] {
        [MushafID.indoPak, .uthmani].flatMap { mushaf in
            let scanned = MushafLayout(mushaf: mushaf, isScanned: true)
            return [MushafLayout(mushaf: mushaf, isScanned: false)] + (scanned.scan?.isAvailable == true ? [scanned] : [])
        }
    }

    static func current(mushafID: Int) -> MushafLayout {
        let mushaf = MushafID(rawValue: mushafID) ?? .uthmani
        let scan = ScanStore.forMushaf(mushafID)
        return MushafLayout(mushaf: mushaf, isScanned: scan.map { $0.isEnabled && $0.isAvailable } ?? false)
    }

    /// Switch the scans to match. A scan runs on its digital mushaf (marks, decks and page numbers carry
    /// over), so callers still switch to `mushaf`.
    func applyScans() {
        let scan = scan
        for store in ScanStore.all { store.isEnabled = store === scan }
    }

    /// Whether to offer downloading the whole scan, so big page jumps never wait on a download.
    var needsFullDownload: Bool {
        guard let scan, scan.edition.baseURL != nil else { return false }
        return !scan.isFullyDownloaded && !scan.isDownloadingAll
    }
}

/// Mushaf chooser with portrait + landscape previews: shown on first launch, and from Settings ▸ Layout.
struct MushafOnboardingView: View {
    var isFirstLaunch = true
    let onContinue: (MushafLayout) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: MushafLayout
    @State private var previewRightPage: MushafPage?
    @State private var previewLeftPage: MushafPage?
    @State private var previewRightScan: UIImage?
    @State private var previewLeftScan: UIImage?
    @State private var isLoadingPreview = false
    @State private var previewError: String?
    @State private var isSaving = false

    private let api = APIClient()
    /// Odd page on the right in landscape (natural mushaf pair 9|10).
    private let previewRightPageNumber = 9
    private let previewLeftPageNumber = 10

    init(
        initial: MushafLayout = MushafLayout(mushaf: .uthmani, isScanned: false),
        isFirstLaunch: Bool = true,
        onContinue: @escaping (MushafLayout) async -> Void
    ) {
        self.isFirstLaunch = isFirstLaunch
        self.onContinue = onContinue
        self._selected = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose your Mushaf")
                        .font(.title2.bold())
                    Text(isFirstLaunch
                         ? "Pick the page layout you read with. You can change this later in Settings."
                         : "Pick the page layout you read with. Your marks and decks carry over.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(MushafLayout.all) { layout in
                        mushafOptionCard(layout)
                    }
                }
                .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 16) {
                        portraitPreview
                        landscapePreview
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: .infinity)

                Button {
                    Task { await confirm() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("\(isFirstLaunch ? "Continue with" : "Use") \(selected.title)")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(isSaving)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(isFirstLaunch)
            .toolbar {
                if !isFirstLaunch {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task(id: selected) {
                await loadPreview(for: selected)
            }
        }
    }

    private func mushafOptionCard(_ layout: MushafLayout) -> some View {
        let isSelected = selected == layout
        return Button {
            selected = layout
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(layout.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(layout.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var portraitPreview: some View {
        previewSection(
            title: "Portrait · Page \(previewRightPageNumber)",
            caption: "Single page"
        ) {
            if let previewRightScan {
                ScanPreviewImage(image: previewRightScan)
            } else if let previewRightPage {
                MushafPreviewPageView(
                    page: previewRightPage,
                    mushafID: selected.mushaf.rawValue,
                    scale: 1.3,
                    lineLimit: 7
                )
            }
        }
        .frame(height: 220)
    }

    private var landscapePreview: some View {
        previewSection(
            title: "Landscape · Pages \(previewRightPageNumber)–\(previewLeftPageNumber)",
            caption: "Two-page spread (turn sideways)"
        ) {
            if let previewRightScan, let previewLeftScan {
                HStack(spacing: 0) {
                    ScanPreviewImage(image: previewLeftScan)
                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 1)
                    ScanPreviewImage(image: previewRightScan)
                }
            } else if let previewRightPage, let previewLeftPage {
                // Screen left = even page, screen right = odd page (open book).
                HStack(spacing: 0) {
                    MushafPreviewPageView(
                        page: previewLeftPage,
                        mushafID: selected.mushaf.rawValue,
                        scale: 0.8,
                        lineLimit: 6,
                        compactPadding: true
                    )
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 1)

                    MushafPreviewPageView(
                        page: previewRightPage,
                        mushafID: selected.mushaf.rawValue,
                        scale: 0.8,
                        lineLimit: 6,
                        compactPadding: true
                    )
                    .frame(maxWidth: .infinity)
                }
            } else if let previewRightPage {
                MushafPreviewPageView(
                    page: previewRightPage,
                    mushafID: selected.mushaf.rawValue,
                    scale: 0.8,
                    lineLimit: 6,
                    compactPadding: true
                )
            }
        }
        .frame(height: 160)
    }

    private func previewSection<Content: View>(
        title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)

                if isLoadingPreview {
                    ProgressView("Loading preview…")
                } else if let previewError {
                    Text(previewError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    content()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }

    private func loadPreview(for layout: MushafLayout) async {
        isLoadingPreview = true
        previewError = nil
        previewRightPage = nil
        previewLeftPage = nil
        previewRightScan = nil
        previewLeftScan = nil
        defer { isLoadingPreview = false }
        if let scan = layout.scan {
            async let right = scan.previewImage(previewRightPageNumber)
            async let left = scan.previewImage(previewLeftPageNumber)
            let (rightImage, leftImage) = await (right, left)
            guard !Task.isCancelled else { return }
            guard let rightImage, let leftImage else {
                previewError = "Couldn’t load preview. You can still continue — check your connection."
                return
            }
            previewRightScan = rightImage
            previewLeftScan = leftImage
            return
        }
        do {
            async let right = api.fetchPage(mushafID: layout.mushaf.rawValue, position: previewRightPageNumber)
            async let left = api.fetchPage(mushafID: layout.mushaf.rawValue, position: previewLeftPageNumber)
            let (rightPage, leftPage) = try await (right, left)
            previewRightPage = rightPage
            previewLeftPage = leftPage
        } catch {
            previewError = "Couldn’t load preview. You can still continue — check your connection."
        }
    }

    private func confirm() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        await onContinue(selected)
    }
}

/// The top of a printed page, filling the preview's width.
private struct ScanPreviewImage: View {
    let image: UIImage

    var body: some View {
        Color.white
            .overlay(alignment: .top) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .frame(maxWidth: .infinity)
    }
}

private struct MushafPreviewPageView: View {
    let page: MushafPage
    let mushafID: Int
    var scale: CGFloat = 0.85
    var lineLimit: Int = 8
    var compactPadding: Bool = false

    private var previewLines: [MushafLine] {
        page.lines
            .sorted { $0.position < $1.position }
            .filter { line in
                line.words.contains { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            .prefix(lineLimit)
            .map { $0 }
    }

    private var fontSize: CGFloat {
        MushafTypography.baseFontSize(mushafID: mushafID) * scale
    }

    /// Lines are set larger than they fit and shrink to the width, so each fills it like a justified mushaf line.
    private var lineHeight: CGFloat {
        MushafTypography.lineHeight(mushafID: mushafID) * scale * 0.8
    }

    private var fontName: String {
        MushafTypography.quranFontName(mushafID: mushafID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(previewLines, id: \.id) { line in
                    Text(line.words.map(\.content).joined(separator: " "))
                        .font(.custom(fontName, size: fontSize))
                        .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .frame(maxWidth: .infinity, minHeight: lineHeight, alignment: .center)
                        .environment(\.layoutDirection, .rightToLeft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.2)
                }
            }
            .padding(.horizontal, compactPadding ? 8 : 14)
            .padding(.vertical, compactPadding ? 10 : 16)
        }
        .allowsHitTesting(false)
    }
}
