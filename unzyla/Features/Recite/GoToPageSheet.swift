import SwiftUI

struct GoToPageSheet: View {
    @Binding var pageField: String
    let juzSegments: [NavigationSegment]
    let surahSegments: [NavigationSegment]
    let totalPages: Int
    let onGo: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isPageFieldFocused: Bool
    @State private var surahSearch = ""

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

    private var filteredSurahs: [NavigationSegment] {
        guard !surahSearch.isEmpty else { return sortedSurahs }
        return sortedSurahs.filter {
            $0.title.localizedCaseInsensitiveContains(surahSearch) ||
            ($0.categoryPosition.map { SurahMeta.englishName($0).localizedCaseInsensitiveContains(surahSearch) } ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    pageJumpCard
                    juzSection
                    surahSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(canvas.ignoresSafeArea())
            .navigationTitle("Go to Page")
            .navigationBarTitleDisplayMode(.inline)
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
        }
        .preferredColorScheme(colorScheme)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { isPageFieldFocused = true }
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

    private var juzSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Juz")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                spacing: 10
            ) {
                ForEach(sortedJuz) { segment in
                    juzChip(segment)
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

    private var surahSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Surah")

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(secondaryText)
                TextField(
                    "",
                    text: $surahSearch,
                    prompt: Text("Search by name").foregroundStyle(tertiaryText)
                )
                .font(.subheadline)
                .foregroundStyle(primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                if !surahSearch.isEmpty {
                    Button {
                        surahSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )

            LazyVStack(spacing: 8) {
                ForEach(filteredSurahs) { segment in
                    surahRow(segment)
                }
            }

            if filteredSurahs.isEmpty {
                Text("No surahs match your search")
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
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
}
