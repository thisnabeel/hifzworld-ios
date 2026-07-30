import SwiftUI

/// First-launch chooser: pick a mushaf with portrait + landscape previews.
struct MushafOnboardingView: View {
    let onContinue: (Int) async -> Void

    @State private var selected: MushafID = .uthmani
    @State private var previewRightPage: MushafPage?
    @State private var previewLeftPage: MushafPage?
    @State private var isLoadingPreview = false
    @State private var previewError: String?
    @State private var isSaving = false

    private let api = APIClient()
    /// Odd page on the right in landscape (natural mushaf pair 9|10).
    private let previewRightPageNumber = 9
    private let previewLeftPageNumber = 10

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose your Mushaf")
                        .font(.title2.bold())
                    Text("Pick the page layout you read with. You can change this later in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    ForEach(MushafID.allCases) { mushaf in
                        mushafOptionCard(mushaf)
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
                            Text("Continue with \(selected.title)")
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
            .interactiveDismissDisabled(true)
            .task(id: selected) {
                await loadPreview(for: selected)
            }
        }
    }

    private func mushafOptionCard(_ mushaf: MushafID) -> some View {
        let isSelected = selected == mushaf
        return Button {
            selected = mushaf
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(mushaf.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(mushaf.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
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
            if let previewRightPage {
                MushafPreviewPageView(
                    page: previewRightPage,
                    mushafID: selected.rawValue,
                    scale: 0.78,
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
            if let previewRightPage, let previewLeftPage {
                // Screen left = even page, screen right = odd page (open book).
                HStack(spacing: 0) {
                    MushafPreviewPageView(
                        page: previewLeftPage,
                        mushafID: selected.rawValue,
                        scale: 0.55,
                        lineLimit: 6,
                        compactPadding: true
                    )
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 1)

                    MushafPreviewPageView(
                        page: previewRightPage,
                        mushafID: selected.rawValue,
                        scale: 0.55,
                        lineLimit: 6,
                        compactPadding: true
                    )
                    .frame(maxWidth: .infinity)
                }
            } else if let previewRightPage {
                MushafPreviewPageView(
                    page: previewRightPage,
                    mushafID: selected.rawValue,
                    scale: 0.55,
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

    private func loadPreview(for mushaf: MushafID) async {
        isLoadingPreview = true
        previewError = nil
        previewRightPage = nil
        previewLeftPage = nil
        defer { isLoadingPreview = false }
        do {
            async let right = api.fetchPage(mushafID: mushaf.rawValue, position: previewRightPageNumber)
            async let left = api.fetchPage(mushafID: mushaf.rawValue, position: previewLeftPageNumber)
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
        await onContinue(selected.rawValue)
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

    private var lineHeight: CGFloat {
        MushafTypography.lineHeight(mushafID: mushafID) * scale
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
                        .minimumScaleFactor(0.45)
                }
            }
            .padding(.horizontal, compactPadding ? 8 : 14)
            .padding(.vertical, compactPadding ? 10 : 16)
        }
        .allowsHitTesting(false)
    }
}
