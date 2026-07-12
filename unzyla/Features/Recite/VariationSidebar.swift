import SwiftUI

struct VariationSidebar: View {
    let variations: [Variation]
    let mushafID: Int
    let onSelect: (Variation) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("All variations")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                }
            }
            .padding()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(variations, id: \.id) { variation in
                        Button {
                            onSelect(variation)
                        } label: {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(variation.narrator?.title ?? variation.narratorIDString)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
                                if let original = variation.word?.content {
                                    ArabicComparisonText(
                                        original: original,
                                        variation: variation.content,
                                        fontName: MushafFonts.quranFontFamily(mushafID: mushafID),
                                        fontSize: 18,
                                        defaultColor: .white,
                                        highlightColor: AppTheme.accent
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Divider().overlay(Color.gray.opacity(0.3))
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 280)
        .background(AppTheme.drawerBackground)
    }
}
