import Foundation

// Ported from `@tilawa/core` `recitation/phonemeCost.ts` + `recitation/alignment.ts` (MIT).
//
// Phoneme strings are handled as UTF-16 code units, exactly like the JS original indexes strings.
// Cost matrices are Float32 like the original's Float32Array stores; comparisons against freshly
// computed insert/delete costs happen in Double, as JS does.

typealias PhonemeUnits = [UInt16]

nonisolated extension String {
    var phonemeUnits: PhonemeUnits { Array(utf16) }
}

nonisolated enum TilawaPhoneme {
    static let alphabet: PhonemeUnits = "\u{621}\u{627}\u{628}\u{62A}\u{62B}\u{62C}\u{62D}\u{62E}\u{62F}\u{630}\u{631}\u{632}\u{633}\u{634}\u{635}\u{636}\u{637}\u{638}\u{639}\u{63A}\u{641}\u{642}\u{643}\u{644}\u{645}\u{646}\u{647}\u{648}\u{64A}\u{6E5}\u{6E6}\u{6BA}\u{6FE}\u{672}\u{623}\u{625}\u{622}\u{624}\u{626}\u{671}\u{649}\u{64E}\u{64F}\u{650}\u{687}\u{619}\u{6E3}\u{65E}\u{6DC}\u{6EA}\u{640}".phonemeUnits
    static let alphabetSize = 51
    static let tableSize = 52
    static let unknownID: UInt8 = 51
    static let insertDeleteCost: Double = 1

    static let fatha: UInt16 = 0x64E
    static let damma: UInt16 = 0x64F
    static let kasra: UInt16 = 0x650
    static let shortVowels: Set<UInt16> = [fatha, damma, kasra]

    private static let canonicalMap: [UInt16: UInt16] = [
        0x6E6: 0x64A,
        0x6E5: 0x648,
        0x6BA: 0x646,
        0x6FE: 0x645,
        0x671: 0x627,
        0x649: 0x64A,
    ]
    private static let hamza: Set<UInt16> = [0x621, 0x623, 0x625, 0x622, 0x627, 0x624, 0x626, 0x672]
    private static let otherMarks: Set<UInt16> = [0x687, 0x619, 0x6E3, 0x65E, 0x6DC, 0x6EA, 0x640]
    private static let marks: Set<UInt16> = shortVowels.union(otherMarks)
    private static let neighborGroups: [PhonemeUnits] = [
        "\u{630}\u{62F}\u{636}\u{62A}\u{637}",
        "\u{638}\u{632}\u{630}\u{635}\u{633}\u{62B}",
        "\u{62C}\u{632}\u{634}",
        "\u{629}\u{647}\u{62A}",
        "\u{642}\u{643}\u{63A}",
        "\u{641}\u{628}\u{645}",
    ].map(\.phonemeUnits)
    private static let neighborPairs: [(UInt16, UInt16)] = [
        (0x647, 0x62D),
        (0x63A, 0x62E),
        (0x621, 0x639),
        (0x646, 0x645),
        (0x646, 0x644),
        (0x638, 0x636),
    ]

    private static func pairKey(_ a: UInt16, _ b: UInt16) -> UInt32 {
        a < b ? (UInt32(a) << 16) | UInt32(b) : (UInt32(b) << 16) | UInt32(a)
    }

    private static let neighbors: Set<UInt32> = {
        var s = Set<UInt32>()
        for g in neighborGroups {
            for i in 0..<g.count {
                for j in (i + 1)..<g.count { s.insert(pairKey(g[i], g[j])) }
            }
        }
        for (a, b) in neighborPairs { s.insert(pairKey(a, b)) }
        return s
    }()

    private static let idByUnit: [UInt16: UInt8] = {
        var map: [UInt16: UInt8] = [:]
        for (i, u) in alphabet.enumerated() where map[u] == nil { map[u] = UInt8(i) }
        return map
    }()

    static func charID(_ unit: UInt16) -> UInt8 {
        idByUnit[unit] ?? unknownID
    }

    static func canonical(_ unit: UInt16) -> UInt16 {
        canonicalMap[unit] ?? unit
    }

    static func charCost(heard: UInt16, expected: UInt16) -> Double {
        if heard == expected { return 0 }
        let ch = canonical(heard)
        let ce = canonical(expected)
        if ch == ce { return 0 }
        let hm = marks.contains(heard)
        let em = marks.contains(expected)
        if hm || em {
            if hm && em {
                if shortVowels.contains(heard) && shortVowels.contains(expected) { return 0.1 }
                return 0.25
            }
            return 1
        }
        if hamza.contains(ch) && hamza.contains(ce) { return 0.1 }
        if neighbors.contains(pairKey(ch, ce)) { return 0.25 }
        return 1
    }
}

nonisolated final class TilawaCostTable: @unchecked Sendable {
    static let shared = TilawaCostTable()

    let size = TilawaPhoneme.tableSize
    let matrix: [Float]

    private init() {
        let n = TilawaPhoneme.tableSize
        var m = [Float](repeating: 0, count: n * n)
        let alpha = TilawaPhoneme.alphabet
        for i in 0..<TilawaPhoneme.alphabetSize {
            for j in 0..<TilawaPhoneme.alphabetSize {
                m[i * n + j] = Float(TilawaPhoneme.charCost(heard: alpha[i], expected: alpha[j]))
            }
        }
        let unk = Int(TilawaPhoneme.unknownID)
        for i in 0..<n {
            m[unk * n + i] = 1
            m[i * n + unk] = 1
        }
        matrix = m
    }

    @inline(__always)
    func id(_ unit: UInt16) -> UInt8 { TilawaPhoneme.charID(unit) }

    func encode(_ units: PhonemeUnits) -> [UInt8] {
        units.map { TilawaPhoneme.charID($0) }
    }

    func encode(_ units: ArraySlice<UInt16>) -> [UInt8] {
        units.map { TilawaPhoneme.charID($0) }
    }

    @inline(__always)
    func cost(_ heardID: UInt8, _ expectedID: UInt8) -> Float {
        matrix[Int(heardID) * size + Int(expectedID)]
    }
}

nonisolated struct TilawaSemiGlobalResult {
    let cost: Float
    let distance: Double
    let refStart: Int
    let refEnd: Int
    let queryStart: Int
}

nonisolated enum TilawaAlignment {
    static func weightedLevenshtein(_ a: [UInt8], _ b: [UInt8], _ table: TilawaCostTable) -> Float {
        let n = a.count
        let m = b.count
        if n == 0 && m == 0 { return 0 }
        var prev = [Float](repeating: 0, count: m + 1)
        var cur = [Float](repeating: 0, count: m + 1)
        for j in 0...m { prev[j] = Float(j) }
        guard n > 0 else { return prev[m] }
        let ins = TilawaPhoneme.insertDeleteCost
        table.matrix.withUnsafeBufferPointer { mat in
            let size = table.size
            for i in 1...n {
                cur[0] = Float(i)
                let row = Int(a[i - 1]) * size
                if m > 0 {
                    for j in 1...m {
                        var c = prev[j - 1] + mat[row + Int(b[j - 1])]
                        let up = Double(prev[j]) + ins
                        let left = Double(cur[j - 1]) + ins
                        if up < Double(c) { c = Float(up) }
                        if left < Double(c) { c = Float(left) }
                        cur[j] = c
                    }
                }
                swap(&prev, &cur)
            }
        }
        return prev[m]
    }

    static func normalizedDistance(_ a: [UInt8], _ b: [UInt8], _ table: TilawaCostTable) -> Double {
        if a.isEmpty && b.isEmpty { return 0 }
        if a.isEmpty || b.isEmpty { return 1 }
        return Double(weightedLevenshtein(a, b, table)) / Double(max(a.count, b.count))
    }

    /// For each heard index, the ref index it aligns to (or -1).
    static func alignGlobal(
        heard: [UInt8],
        ref: [UInt8],
        from: Int,
        to: Int,
        table: TilawaCostTable
    ) -> [Int] {
        let n = heard.count
        let m = to - from
        if n == 0 { return [] }
        if m <= 0 { return [Int](repeating: -1, count: n) }
        let cols = m + 1
        var c = [Float](repeating: 0, count: (n + 1) * cols)
        var t = [UInt8](repeating: 0, count: (n + 1) * cols)
        for j in 0...m { c[j] = Float(j) }
        for i in 1...n { c[i * cols] = Float(i) }
        let ins = TilawaPhoneme.insertDeleteCost
        let size = table.size
        table.matrix.withUnsafeBufferPointer { mat in
            for i in 1...n {
                let hrow = Int(heard[i - 1]) * size
                let row = i * cols
                let prev = (i - 1) * cols
                for j in 1...m {
                    var v = c[prev + j - 1] + mat[hrow + Int(ref[from + j - 1])]
                    var tr: UInt8 = 0
                    let up = Double(c[prev + j]) + ins
                    let left = Double(c[row + j - 1]) + ins
                    if up < Double(v) {
                        v = Float(up)
                        tr = 1
                    }
                    if left < Double(v) {
                        v = Float(left)
                        tr = 2
                    }
                    c[row + j] = v
                    t[row + j] = tr
                }
            }
        }
        var assign = [Int](repeating: -1, count: n)
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i == 0 {
                j -= 1
                continue
            }
            if j == 0 {
                assign[i - 1] = -1
                i -= 1
                continue
            }
            let tr = t[i * cols + j]
            if tr == 0 {
                assign[i - 1] = from + j - 1
                i -= 1
                j -= 1
            } else if tr == 1 {
                assign[i - 1] = -1
                i -= 1
            } else {
                j -= 1
            }
        }
        return assign
    }

    static func alignSemiGlobal(
        query: [UInt8],
        ref: [UInt8],
        from: Int,
        to: Int,
        table: TilawaCostTable,
        headSkipCost: Double = 0.5
    ) -> TilawaSemiGlobalResult {
        let n = query.count
        let m = max(0, to - from)
        if n == 0 {
            return TilawaSemiGlobalResult(cost: 0, distance: 1, refStart: from, refEnd: from, queryStart: 0)
        }
        var prevCost = [Float](repeating: 0, count: m + 1)
        var curCost = [Float](repeating: 0, count: m + 1)
        var prevStart = [Int32](repeating: 0, count: m + 1)
        var curStart = [Int32](repeating: 0, count: m + 1)
        var prevQ = [Int32](repeating: 0, count: m + 1)
        var curQ = [Int32](repeating: 0, count: m + 1)
        for j in 0...m { prevStart[j] = Int32(j) }
        let size = table.size
        table.matrix.withUnsafeBufferPointer { mat in
            for i in 1...n {
                let hrow = Int(query[i - 1]) * size
                let skip = Float(Double(i) * headSkipCost)
                curCost[0] = skip
                curStart[0] = 0
                curQ[0] = Int32(i)
                if m > 0 {
                    for j in 1...m {
                        let diagCost = prevCost[j - 1] + mat[hrow + Int(ref[from + j - 1])]
                        let upCost = prevCost[j] + 1
                        let leftCost = curCost[j - 1] + 1
                        var cost = diagCost
                        var start = prevStart[j - 1]
                        var q = prevQ[j - 1]
                        if upCost < cost {
                            cost = upCost
                            start = prevStart[j]
                            q = prevQ[j]
                        }
                        if leftCost < cost {
                            cost = leftCost
                            start = curStart[j - 1]
                            q = curQ[j - 1]
                        }
                        if skip < cost {
                            cost = skip
                            start = Int32(j)
                            q = Int32(i)
                        }
                        curCost[j] = cost
                        curStart[j] = start
                        curQ[j] = q
                    }
                }
                swap(&prevCost, &curCost)
                swap(&prevStart, &curStart)
                swap(&prevQ, &curQ)
            }
        }
        var bestJ = 0
        var best = prevCost[0]
        if m > 0 {
            for j in 1...m where prevCost[j] < best {
                best = prevCost[j]
                bestJ = j
            }
        }
        return TilawaSemiGlobalResult(
            cost: best,
            distance: Double(best) / Double(n),
            refStart: from + Int(prevStart[bestJ]),
            refEnd: from + bestJ,
            queryStart: Int(prevQ[bestJ])
        )
    }
}
