import SwiftUI

struct AddPageToBundleSheet: View {
    let currentPage: Int
    @Bindable var bundleStore: BundleStore
    let onCreateBundle: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if bundleStore.bundles.isEmpty {
                    ContentUnavailableView(
                        "No Bundles",
                        systemImage: "square.stack.3d.up",
                        description: Text("Create a bundle first, then add page \(currentPage).")
                    )
                } else {
                    List(bundleStore.bundles) { bundle in
                        Button {
                            addToBundle(bundle)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bundle.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if !bundle.description.isEmpty {
                                        Text(bundle.description)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    if bundle.pageNumbers.isEmpty {
                                        Text("No pages yet")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(pagePreview(for: bundle))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if bundleStore.containsPage(currentPage, in: bundle.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                        .disabled(bundleStore.containsPage(currentPage, in: bundle.id))
                    }
                }
            }
            .navigationTitle("Add to Bundle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Bundle", action: onCreateBundle)
                }
            }
        }
        .presentationDetents([.medium, .large])
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
