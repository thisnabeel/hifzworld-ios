import Foundation

enum ArabicIndicNumerals {
    /// Standard Arabic-Indic digits (U+0660…U+0669). Used by Madani / DigitalKhatt.
    private static let arabicMap: [Character: Character] = [
        "0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
        "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩",
    ]

    /// Extended Arabic-Indic / Persian digits (U+06F0…U+06F9).
    /// IndoPak Nastaleeq ships real glyphs here; U+0660… are mostly empty stubs.
    private static let indoPakMap: [Character: Character] = [
        "0": "۰", "1": "۱", "2": "۲", "3": "۳", "4": "۴",
        "5": "۵", "6": "۶", "7": "۷", "8": "۸", "9": "۹",
    ]

    static func string(from number: Int) -> String {
        mapped(number, using: arabicMap)
    }

    /// Digits that render in the bundled IndoPak Quran font.
    static func indoPakString(from number: Int) -> String {
        mapped(number, using: indoPakMap)
    }

    private static func mapped(_ number: Int, using map: [Character: Character]) -> String {
        String(String(number).map { map[$0] ?? $0 })
    }
}
