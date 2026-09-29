import SwiftUI
import UIKit

/// Single hairline on the outer edge of a Mushaf page
/// (odd = trailing / right, even = leading / left). Notes gutter sits outside this rule.
struct MushafOuterBorder: View {
    let edge: HorizontalEdge
    let isDarkMode: Bool

    private var ink: Color {
        isDarkMode
            ? Color.white.opacity(0.28)
            : Color(red: 0.22, green: 0.20, blue: 0.18).opacity(0.38)
    }

    private var shadowColor: Color {
        isDarkMode
            ? Color.black.opacity(0.28)
            : Color.black.opacity(0.08)
    }

    var body: some View {
        HStack(spacing: 0) {
            if edge == .leading {
                shadowStrip(towardOuter: true)
                rule
            } else {
                rule
                shadowStrip(towardOuter: true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var rule: some View {
        Rectangle()
            .fill(ink)
            .frame(width: 1 / UIScreen.main.scale)
    }

    /// Soft falloff into the notes gutter so the rule feels slightly lifted.
    private func shadowStrip(towardOuter: Bool) -> some View {
        let colors: [Color] = edge == .trailing
            ? [shadowColor, shadowColor.opacity(0)]
            : [shadowColor.opacity(0), shadowColor]

        return LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 7)
        .opacity(towardOuter ? 1 : 0)
    }
}
