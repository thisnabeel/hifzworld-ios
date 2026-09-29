import SwiftUI

/// Traditional IndoPak (13-line) page header: surah · Arabic page · juz.
struct MushafPageHeaderBar: View {
    let surahName: String
    let surahNumber: Int
    let pageNumber: Int
    let juzNumber: Int
    let isDarkMode: Bool

    private let headerFont = MushafTypography.FontName.indoPakQuran
    /// Nastaleeq’s default line box is tall; compress for a slim printed-mushaf header.
    private let labelSize: CGFloat = 18
    private let pageSize: CGFloat = 20
    private let rowHeight: CGFloat = 22

    private var ink: Color {
        isDarkMode ? Color.white.opacity(0.88) : Color(red: 0.12, green: 0.11, blue: 0.10)
    }

    private var ruleInk: Color {
        isDarkMode ? Color.white.opacity(0.28) : Color(red: 0.22, green: 0.20, blue: 0.18).opacity(0.45)
    }

    private var softRuleInk: Color {
        isDarkMode ? Color.white.opacity(0.14) : Color(red: 0.22, green: 0.20, blue: 0.18).opacity(0.22)
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Text(surahLabel)
                    .font(.custom(headerFont, size: labelSize))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(ArabicIndicNumerals.indoPakString(from: pageNumber))
                    .font(.custom(headerFont, size: pageSize))
                    .foregroundStyle(ink)
                    .layoutPriority(1)

                Text(juzLabel)
                    .font(.custom(headerFont, size: labelSize))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(height: rowHeight)
            .clipped()

            ornateRule
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(surahLabel), page \(pageNumber), juz \(juzNumber)")
    }

    private var surahLabel: String {
        "\(surahName) \(ArabicIndicNumerals.indoPakString(from: surahNumber))"
    }

    private var juzLabel: String {
        "الجزء \(ArabicIndicNumerals.indoPakString(from: juzNumber))"
    }

    /// Light double rule suggesting a printed Mushaf header separator.
    private var ornateRule: some View {
        VStack(spacing: 1) {
            Rectangle()
                .fill(softRuleInk)
                .frame(height: 0.5)
            Rectangle()
                .fill(ruleInk)
                .frame(height: 0.75)
            Rectangle()
                .fill(softRuleInk)
                .frame(height: 0.5)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}
