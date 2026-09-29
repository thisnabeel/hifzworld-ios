import SwiftUI
import UIKit

/// Local appearance for Mushaf mark types (order + highlight colors).
@MainActor
enum MarkTypeAppearance {
    static let defaultYellowHex = "#FFEB3B"

    static let presetHexes: [String] = [
        "#FFEB3B", // yellow
        "#FF726B", // coral
        "#4C9AFF", // blue
        "#57D9A3", // green
        "#FF9F43", // orange
        "#B388FF", // purple
    ]

    static var defaultOrder: [MistakeMarkType] { Array(MistakeMarkType.allCases) }

    static var defaultColors: [String: String] {
        [
            MistakeMarkType.mistake.rawValue: defaultYellowHex,
            MistakeMarkType.tajweed.rawValue: defaultYellowHex,
        ]
    }

    static func orderedTypes(from prefs: PreferencesStore? = nil) -> [MistakeMarkType] {
        let prefs = prefs ?? PreferencesStore.shared
        var seen = Set<MistakeMarkType>()
        var ordered: [MistakeMarkType] = []
        for raw in prefs.markTypeOrder {
            guard let type = MistakeMarkType(rawValue: raw), !seen.contains(type) else { continue }
            ordered.append(type)
            seen.insert(type)
        }
        for type in MistakeMarkType.allCases where !seen.contains(type) {
            ordered.append(type)
        }
        return ordered
    }

    static func hex(for type: MistakeMarkType, prefs: PreferencesStore? = nil) -> String {
        let prefs = prefs ?? PreferencesStore.shared
        if let hex = prefs.markTypeColors[type.rawValue], Color(hex: hex) != nil {
            let normalized = normalizedHex(hex)
            // Migrate the previous Mistake coral default to match Tajweed yellow.
            if type == .mistake, normalized == "#FF726B" {
                return defaultYellowHex
            }
            return normalized
        }
        return defaultColors[type.rawValue] ?? defaultYellowHex
    }

    static func color(for type: MistakeMarkType, prefs: PreferencesStore? = nil) -> Color {
        Color(hex: hex(for: type, prefs: prefs)) ?? Color(red: 1, green: 0.92, blue: 0.23)
    }

    static func uiColor(for type: MistakeMarkType, prefs: PreferencesStore? = nil) -> UIColor {
        UIColor(hex: hex(for: type, prefs: prefs)) ?? UIColor(red: 1, green: 0.94, blue: 0.35, alpha: 1)
    }

    static func uiColorMap(prefs: PreferencesStore? = nil) -> [MistakeMarkType: UIColor] {
        Dictionary(uniqueKeysWithValues: MistakeMarkType.allCases.map { ($0, uiColor(for: $0, prefs: prefs)) })
    }

    static func setOrder(_ types: [MistakeMarkType], prefs: PreferencesStore? = nil) {
        let prefs = prefs ?? PreferencesStore.shared
        var seen = Set<MistakeMarkType>()
        var cleaned: [MistakeMarkType] = []
        for type in types where !seen.contains(type) {
            cleaned.append(type)
            seen.insert(type)
        }
        for type in MistakeMarkType.allCases where !seen.contains(type) {
            cleaned.append(type)
        }
        prefs.markTypeOrder = cleaned.map(\.rawValue)
    }

    static func setColor(_ color: Color, for type: MistakeMarkType, prefs: PreferencesStore? = nil) {
        let prefs = prefs ?? PreferencesStore.shared
        var colors = prefs.markTypeColors
        colors[type.rawValue] = color.toHexString() ?? defaultYellowHex
        prefs.markTypeColors = colors
    }

    static func setHex(_ hex: String, for type: MistakeMarkType, prefs: PreferencesStore? = nil) {
        let prefs = prefs ?? PreferencesStore.shared
        var colors = prefs.markTypeColors
        colors[type.rawValue] = normalizedHex(hex)
        prefs.markTypeColors = colors
    }

    static func resetDefaults(prefs: PreferencesStore? = nil) {
        let prefs = prefs ?? PreferencesStore.shared
        prefs.markTypeOrder = defaultOrder.map(\.rawValue)
        prefs.markTypeColors = defaultColors
    }

    private static func normalizedHex(_ hex: String) -> String {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !value.hasPrefix("#") { value = "#\(value)" }
        return value
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    func toHexString() -> String? {
        let ui = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
    }
}
