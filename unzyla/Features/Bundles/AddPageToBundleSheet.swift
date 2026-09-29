import SwiftUI

struct AddPageToBundleSheet: View {
    let currentPage: Int
    let surahOffer: NavigationSegment?
    let surahTitle: String?
    @Bindable var bundleStore: BundleStore
    let onCreateBundle: () -> Void
    let onAddWholeSurah: () -> Void
    let onSelectEndRange: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let surahOffer {
                        Button {
                            onAddWholeSurah()
                        } label: {
                            optionRow(
                                title: "Whole surah",
                                subtitle: "\(surahTitle ?? surahOffer.title) · p. \(surahOffer.startPage)–\(surahOffer.endPage)",
                                systemImage: "text.book.closed"
                            )
                        }
                        .buttonStyle(.plain)

                        if let onSelectEndRange {
                            Button(action: onSelectEndRange) {
                                optionRow(
                                    title: "Select end page",
                                    subtitle: "Swipe to a page, then Done",
                                    systemImage: "arrow.left.and.right"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        onCreateBundle()
                    } label: {
                        optionRow(
                            title: "Just this page",
                            subtitle: "Page \(currentPage)",
                            systemImage: "doc"
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    sectionHeader("New deck")
                }

                Section {
                    if bundleStore.bundles.isEmpty {
                        Text("No decks yet — use New deck above.")
                            .foregroundStyle(.primary.opacity(0.72))
                    } else {
                        ForEach(bundleStore.bundles) { bundle in
                            let alreadyAdded = bundleStore.containsPage(currentPage, in: bundle.id)
                            Button {
                                addToBundle(bundle)
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bundle.title)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        if !bundle.description.isEmpty {
                                            Text(bundle.description)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary.opacity(0.72))
                                                .lineLimit(2)
                                        }
                                        Text(bundle.pageNumbers.isEmpty ? "No pages yet" : pagePreview(for: bundle))
                                            .font(.subheadline)
                                            .foregroundStyle(.primary.opacity(0.72))
                                    }
                                    Spacer(minLength: 8)
                                    if alreadyAdded {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .opacity(alreadyAdded ? 0.55 : 1)
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyAdded)
                        }
                    }
                } header: {
                    sectionHeader("Add page \(currentPage) to…")
                }
            }
            .tint(.primary)
            .navigationTitle("Add to Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.78))
            .textCase(nil)
    }

    private func optionRow(title: String, subtitle: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.72))
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func addToBundle(_ bundle: MushafBundle) {
        guard bundleStore.addPage(currentPage, to: bundle.id) else { return }
        dismiss()
    }

    private func pagePreview(for bundle: MushafBundle) -> String {
        let pages = bundle.pageNumbers
        let preview = pages.prefix(5).map(String.init).joined(separator: ", ")
        if pages.count > 5 {
            return "Pages \(preview)… (\(pages.count) total)"
        }
        return "Pages \(preview)"
    }
}
