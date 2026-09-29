import Foundation

// Ported from `@tilawa/core` `recitation/fbank.ts` + `recitation/ctcDecoder.ts` (MIT).

/// Streaming Kaldi-compatible 80-bin log-mel filterbank (25 ms Povey window, 10 ms hop, 16 kHz).
nonisolated final class TilawaFbank {
    private static let fftSize = 512
    private static let preemph = 0.97
    private static let lowFreq = 20.0
    private static let highFreq = 7600.0
    private static let logFloor = 1.1920929e-7
    private static let trimExtra = 1600
    private static let frameLength = TilawaAudio.frameLength
    private static let frameShift = TilawaAudio.frameShift
    private static let bins = TilawaAudio.fbankBins

    private struct MelFilter {
        let firstBin: Int
        let weights: [Double]
    }

    private static let povey: [Double] = (0..<frameLength).map { i in
        let hann = 0.5 - 0.5 * cos((2 * Double.pi * Double(i)) / Double(frameLength - 1))
        return pow(hann, 0.85)
    }

    private static func hzToMel(_ f: Double) -> Double {
        1127 * log(1 + f / 700)
    }

    private static let mel: [MelFilter] = {
        let melLow = hzToMel(lowFreq)
        let melHigh = hzToMel(highFreq)
        let points = (0..<(bins + 2)).map { i in
            melLow + (Double(i) * (melHigh - melLow)) / Double(bins + 1)
        }
        let binHz = Double(TilawaAudio.sampleRate) / Double(fftSize)
        var filters: [MelFilter] = []
        for b in 0..<bins {
            let left = points[b]
            let center = points[b + 1]
            let right = points[b + 2]
            var weights: [Double] = []
            var first = -1
            for k in 0..<(fftSize / 2) {
                let m = hzToMel(Double(k) * binHz)
                if !(m > left && m < right) { continue }
                let w = m < center ? (m - left) / (center - left) : (right - m) / (right - center)
                if first < 0 { first = k }
                weights.append(w)
            }
            filters.append(MelFilter(firstBin: max(first, 0), weights: weights))
        }
        return filters
    }()

    private var buffer: [Float] = []
    private var sampleOffset = 0
    private var framesProduced = 0
    private var trueLength = 0
    private var win = [Double](repeating: 0, count: TilawaFbank.frameLength)
    private var re = [Double](repeating: 0, count: TilawaFbank.fftSize)
    private var im = [Double](repeating: 0, count: TilawaFbank.fftSize)

    private static func frameStart(_ f: Int) -> Int { f * frameShift - 120 }
    private static func frameEnd(_ f: Int) -> Int { f * frameShift + 280 }

    func acceptWaveform(_ samples: [Float]) -> [[Float]] {
        buffer.append(contentsOf: samples)
        trueLength = sampleOffset + buffer.count
        var out: [[Float]] = []
        while Self.frameEnd(framesProduced) <= sampleOffset + buffer.count {
            out.append(computeFrame(framesProduced, n: Int.max))
            framesProduced += 1
        }
        trim()
        return out
    }

    func inputFinished() -> [[Float]] {
        let n = trueLength
        let total = (n + Self.frameShift / 2) / Self.frameShift
        var out: [[Float]] = []
        while framesProduced < total {
            out.append(computeFrame(framesProduced, n: n))
            framesProduced += 1
        }
        return out
    }

    func reset() {
        buffer = []
        sampleOffset = 0
        framesProduced = 0
        trueLength = 0
    }

    private func trim() {
        let firstNeeded = max(0, Self.frameStart(framesProduced))
        let extra = firstNeeded - sampleOffset
        guard extra > Self.trimExtra else { return }
        buffer.removeFirst(extra)
        sampleOffset += extra
    }

    private static func reflectIndex(_ index: Int, _ n: Int) -> Int {
        var s = index
        while s < 0 || s >= n {
            if s < 0 { s = -s - 1 } else { s = 2 * n - 1 - s }
        }
        return s
    }

    private func computeFrame(_ f: Int, n: Int) -> [Float] {
        let start = Self.frameStart(f)
        let len = Self.frameLength
        for i in 0..<len {
            var s = start + i
            if s < 0 || s >= n { s = Self.reflectIndex(s, n) }
            win[i] = Double(buffer[s - sampleOffset])
        }
        var mean = 0.0
        for i in 0..<len { mean += win[i] }
        mean /= Double(len)
        for i in 0..<len { win[i] -= mean }
        var i = len - 1
        while i >= 1 {
            win[i] -= Self.preemph * win[i - 1]
            i -= 1
        }
        win[0] -= Self.preemph * win[0]
        for k in 0..<Self.fftSize {
            re[k] = 0
            im[k] = 0
        }
        for k in 0..<len { re[k] = win[k] * Self.povey[k] }
        Self.fft512(&re, &im)
        var frame = [Float](repeating: 0, count: Self.bins)
        for b in 0..<Self.bins {
            let filt = Self.mel[b]
            var energy = 0.0
            for w in 0..<filt.weights.count {
                let k = filt.firstBin + w
                energy += (re[k] * re[k] + im[k] * im[k]) * filt.weights[w]
            }
            frame[b] = Float(log(max(energy, Self.logFloor)))
        }
        return frame
    }

    private static func fft512(_ re: inout [Double], _ im: inout [Double]) {
        let n = fftSize
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }
        var len = 2
        while len <= n {
            let ang = (-2 * Double.pi) / Double(len)
            let wlenRe = cos(ang)
            let wlenIm = sin(ang)
            let half = len >> 1
            var i = 0
            while i < n {
                var wRe = 1.0
                var wIm = 0.0
                for k in 0..<half {
                    let ur = re[i + k]
                    let ui = im[i + k]
                    let vr = re[i + k + half] * wRe - im[i + k + half] * wIm
                    let vi = re[i + k + half] * wIm + im[i + k + half] * wRe
                    re[i + k] = ur + vr
                    im[i + k] = ui + vi
                    re[i + k + half] = ur - vr
                    im[i + k + half] = ui - vi
                    let nwRe = wRe * wlenRe - wIm * wlenIm
                    wIm = wRe * wlenIm + wIm * wlenRe
                    wRe = nwRe
                }
                i += len
            }
            len <<= 1
        }
    }
}

nonisolated struct TilawaCtcToken {
    let sym: PhonemeUnits
    let frame: Int
    let margin: Double
}

nonisolated struct TilawaHeardChar {
    let ch: UInt16
    let frame: Int
    let margin: Double
}

/// Greedy CTC decoding with per-token confidence margins (top-1 minus top-2 probability at the peak frame).
nonisolated final class TilawaCtcDecoder {
    private struct Run {
        let id: Int
        let frame: Int
        var p1: Float
        var p2: Float
    }

    let blank = TilawaTokens.blankID
    private var previousBest = TilawaTokens.blankID
    private(set) var framesDecoded = 0
    private var run: Run?

    func reset() {
        previousBest = blank
        framesDecoded = 0
        run = nil
    }

    func consume(_ logProbs: [Float], frames: Int, classes: Int) -> [TilawaCtcToken] {
        var out: [TilawaCtcToken] = []
        logProbs.withUnsafeBufferPointer { lp in
            for t in 0..<frames {
                let row = t * classes
                var best = 0
                var p1 = lp[row]
                var p2 = -Float.infinity
                for c in 1..<classes {
                    let p = lp[row + c]
                    if p > p1 {
                        p2 = p1
                        p1 = p
                        best = c
                    } else if p > p2 {
                        p2 = p
                    }
                }
                step(best: best, p1: p1, p2: p2, out: &out)
            }
        }
        return out
    }

    func flush() -> [TilawaCtcToken] {
        var out: [TilawaCtcToken] = []
        if let run {
            out.append(emit(run))
            self.run = nil
        }
        previousBest = blank
        return out
    }

    private func step(best: Int, p1: Float, p2: Float, out: inout [TilawaCtcToken]) {
        if best != blank && best != previousBest {
            if let run { out.append(emit(run)) }
            run = Run(id: best, frame: framesDecoded, p1: p1, p2: p2)
        } else if best != blank && best == previousBest, let current = run, p1 > current.p1 {
            run?.p1 = p1
            run?.p2 = p2
        } else if best == blank, let run {
            out.append(emit(run))
            self.run = nil
        }
        previousBest = best
        framesDecoded += 1
    }

    private func emit(_ run: Run) -> TilawaCtcToken {
        TilawaCtcToken(
            sym: TilawaTokens.units[run.id],
            frame: run.frame,
            margin: exp(Double(run.p1)) - exp(Double(run.p2))
        )
    }

    static func expand(_ tokens: [TilawaCtcToken]) -> [TilawaHeardChar] {
        var out: [TilawaHeardChar] = []
        for t in tokens {
            for unit in t.sym {
                out.append(TilawaHeardChar(ch: unit, frame: t.frame, margin: t.margin))
            }
        }
        return out
    }
}
