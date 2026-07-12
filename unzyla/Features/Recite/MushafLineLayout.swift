import Foundation
import CoreGraphics

enum MushafLineLayout {
    struct Config {
        static let widthSlackPx: CGFloat = 2
        static let fitFudge: CGFloat = 0.985
        static let minFontScale: CGFloat = 0.48
        static let maxFontScale: CGFloat = 1.0
        static let scaleEpsilon: CGFloat = 0.006
    }

    static func fontScale(
        wordWidths: [CGFloat],
        rowWidth: CGFloat,
        previousScale: CGFloat = 1,
        baseFontSize: CGFloat = 24
    ) -> CGFloat {
        guard !wordWidths.isEmpty, rowWidth > 0 else { return 1 }
        let sum = wordWidths.reduce(0, +)
        guard sum > 0 else { return previousScale }
        let raw = ((rowWidth - Config.widthSlackPx) / sum) * Config.fitFudge
        let clamped = min(Config.maxFontScale, max(Config.minFontScale, raw))
        if abs(clamped - previousScale) < Config.scaleEpsilon {
            return previousScale
        }
        return clamped
    }
}
