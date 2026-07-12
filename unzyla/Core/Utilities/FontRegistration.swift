import CoreText
import UIKit

enum FontRegistration {
    private static let bundleFontFiles = [
        "aswaat-one.otf",
        "DigitalKhattV2.otf",
        "surah-name-v2.ttf",
        "nastaleeq.ttf",
    ]

    static func registerAll() {
        for file in bundleFontFiles {
            let parts = file.split(separator: ".")
            guard parts.count == 2 else { continue }
            let name = String(parts[0])
            let ext = String(parts[1])

            let candidates = [
                Bundle.main.url(forResource: name, withExtension: ext),
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Fonts"),
            ].compactMap { $0 }

            for url in candidates {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            }
        }
        MushafTypography.verifyFonts()
    }
}
