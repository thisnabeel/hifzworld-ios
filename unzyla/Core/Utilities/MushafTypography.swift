import UIKit

enum MushafTypography {
    // PostScript names from bundled font files (not Expo alias names).
    enum FontName {
        static let aswaatOne = "aswaat-one"
        static let digitalKhatt = "DigitalKhattNewMadinaRegular"
        static let indoPakQuran = "AlQuranIndoPakbyQuranWBW"
        static let surahNameV2 = "surah-name-v2"
        static let bismillah = indoPakQuran
    }

    static func quranFontName(mushafID: Int) -> String {
        switch mushafID {
        case MushafID.uthmani.rawValue:
            return FontName.digitalKhatt
        default:
            return FontName.indoPakQuran
        }
    }

    static func baseFontSize(mushafID: Int) -> CGFloat {
        mushafID == MushafID.uthmani.rawValue ? 18 : 24
    }

    static func lineHeight(mushafID: Int) -> CGFloat {
        mushafID == MushafID.uthmani.rawValue ? 39 : 46
    }

    static func uiFont(mushafID: Int, size: CGFloat) -> UIFont {
        let name = quranFontName(mushafID: mushafID)
        if let font = UIFont(name: name, size: size) {
            return font
        }
        return .systemFont(ofSize: size)
    }

    static func surahHeaderGlyph(position: Int) -> String? {
        guard position > 0 else { return nil }
        guard let scalar = UnicodeScalar(0xE000 + position) else { return nil }
        return String(scalar)
    }

    static let bismillahLigature = "\u{FDFD}"

    static func verifyFonts() {
        let required = [
            FontName.aswaatOne,
            FontName.digitalKhatt,
            FontName.indoPakQuran,
            FontName.surahNameV2,
            FontName.bismillah,
        ]
        for name in required where UIFont(name: name, size: 16) == nil {
            print("⚠️ Missing font: \(name)")
        }
    }
}

enum MushafFonts {
    static func quranFontFamily(mushafID: Int) -> String {
        MushafTypography.quranFontName(mushafID: mushafID)
    }
}
