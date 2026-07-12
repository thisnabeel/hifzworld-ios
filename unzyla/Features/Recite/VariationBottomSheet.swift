import SwiftUI

struct VariationBottomSheet: View {
    let variations: [Variation]
    let mushafID: Int
    let isDarkMode: Bool
    let activeWordID: Int?
    let onSelect: (Variation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Text("Variations on this page")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            if variations.isEmpty {
                Text("No variations on this page")
                    .foregroundStyle(.gray)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
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
                                    } else {
                                        Text(variation.content)
                                            .font(.custom(MushafFonts.quranFontFamily(mushafID: mushafID), size: 18))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(10)
                                .background(activeWordID == variation.wordID ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.variationSheetBackground)
    }
}
