import Foundation

enum Semver {
    static func parts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .map { segment in
                let digits = segment.filter(\.isNumber)
                return Int(digits) ?? 0
            }
    }

    static func isLessThan(_ a: String, _ b: String) -> Bool {
        let pa = parts(a)
        let pb = parts(b)
        let len = max(pa.count, pb.count, 1)
        for i in 0..<len {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return true }
            if x > y { return false }
        }
        return false
    }
}
