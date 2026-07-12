import SwiftUI

struct GoToPageSheet: View {
    @Binding var pageField: String
    let juzSegments: [NavigationSegment]
    let surahSegments: [NavigationSegment]
    let totalPages: Int
    let onGo: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isPageFieldFocused: Bool
    @State private var surahSearch = ""

    private let accent = Color(red: 0.2, green: 0.45, blue: 0.95)
    private let canvas = Color(red: 0.96, green: 0.97, blue: 0.95)

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
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { isPageFieldFocused = true }
    }

    private var pageJumpCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Page")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField("0", text: $pageField)
                        .keyboardType(.numberPad)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .focused($isPageFieldFocused)
                        .frame(minWidth: 72)

                    Text("of \(totalPages)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )

                Button(action: submitPage) {
                    Text("Go")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 56)
                        .background(canSubmitPage ? accent : accent.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitPage)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
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
                    .monospacedDigit()
                Text("Juz")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
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
                    .foregroundStyle(.secondary)
                TextField("Search by name", text: $surahSearch)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !surahSearch.isEmpty {
                    Button {
                        surahSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )

            LazyVStack(spacing: 8) {
                ForEach(filteredSurahs) { segment in
                    surahRow(segment)
                }
            }

            if filteredSurahs.isEmpty {
                Text("No surahs match your search")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                Text(arabic)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, .rightToLeft)

                Text("p. \(segment.startPage)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
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
