import SwiftUI

enum AppTheme {
    static let mushafBackground = Color.white
    static let mushafDarkBackground = Color(red: 0.12, green: 0.13, blue: 0.14)
    static let drawerBackground = Color(red: 0.19, green: 0.20, blue: 0.22)
    static let accent = Color(red: 0.0, green: 0.83, blue: 1.0)
    static let variationSheetBackground = Color(red: 0.19, green: 0.19, blue: 0.22)

    static func mushafTextColor(dark: Bool) -> Color {
        dark ? .white : .black
    }

    static func pageBackground(dark: Bool) -> Color {
        dark ? mushafDarkBackground : mushafBackground
    }
}

struct ArabicComparisonText: View {
    let original: String
    let variation: String
    let fontName: String
    let fontSize: CGFloat
    let defaultColor: Color
    let highlightColor: Color

    var body: some View {
        let segments = ComparisonEngine.segments(original: original, variation: variation)
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                Text(segment.text)
                    .font(.custom(fontName, size: fontSize))
                    .foregroundStyle(segment.isDifferent ? highlightColor : defaultColor)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
