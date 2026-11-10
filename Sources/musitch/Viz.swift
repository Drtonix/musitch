/// musitch — визуализаторы: осциллограф с послесвечением и лог-спектр.
import SwiftUI
import Accelerate

// MARK: - FFT-обёртка (vDSP)

final class FFT1024 {
    let n = 1024
    private let setup: vDSP.FFT<DSPSplitComplex>?
    private let window: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var outR: [Float]
    private var outI: [Float]

    init() {
        setup = vDSP.FFT(log2n: 10, radix: .radix2,
                         ofType: DSPSplitComplex.self)
        window = vDSP.window(ofType: Float.self,
                             usingSequence: .hanningDenormalized,
                             count: 1024, isHalfWindow: false)
        real = [Float](repeating: 0, count: 1024)
        imag = [Float](repeating: 0, count: 1024)
        outR = [Float](repeating: 0, count: 1024)
        outI = [Float](repeating: 0, count: 1024)
    }

    /// магнитуды первых 512 бинов
    func magnitudes(_ input: [Float]) -> [Float] {
        let k = min(input.count, n)
        for i in 0..<n { real[i] = i < k ? input[i] : 0 }
        real = vDSP.multiply(real, window)
        for i in 0..<n { imag[i] = 0 }
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                outR.withUnsafeMutableBufferPointer { orp in
                    outI.withUnsafeMutableBufferPointer { oip in
                        let inp = DSPSplitComplex(realp: rp.baseAddress!,
                                                  imagp: ip.baseAddress!)
                        var outp = DSPSplitComplex(realp: orp.baseAddress!,
                                                   imagp: oip.baseAddress!)
                        setup?.forward(input: inp, output: &outp)
                    }
                }
            }
        }
        var mags = [Float](repeating: 0, count: n / 2)
        for i in 0..<(n / 2) {
            mags[i] = (outR[i] * outR[i] + outI[i] * outI[i]).squareRoot()
        }
        return mags
    }
}

// MARK: - Осциллограф

final class ScopeStore {
    var trail: [[Float]] = []
}

struct ScopeView: View {
    let engine: Engine
    @State private var store = ScopeStore()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(rect), with: .color(Color(white: 0.04)))

                // сетка
                var grid = Path()
                for gy in 1..<4 {
                    let y = size.height * CGFloat(gy) / 4
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                for gx in 1..<8 {
                    let x = size.width * CGFloat(gx) / 8
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                ctx.stroke(grid, with: .color(.white.opacity(0.11)),
                           lineWidth: 1)

                // снимок волны с послесвечением
                let block = engine.lastL
                let stride = max(1, block.count / 512)
                var sig: [Float] = []
                sig.reserveCapacity(512)
                var i = 0
                while i < block.count {
                    sig.append(block[i])
                    i += stride
                }
                store.trail.append(sig)
                if store.trail.count > 3 { store.trail.removeFirst() }

                for (idx, s) in store.trail.enumerated() {
                    let alpha = 0.15 + 0.85 * Double(idx + 1)
                        / Double(store.trail.count)
                    var path = Path()
                    for (j, v) in s.enumerated() {
                        let x = size.width * CGFloat(j)
                            / CGFloat(max(s.count - 1, 1))
                        let y = size.height / 2
                            - CGFloat(v) * size.height * 0.45
                        if j == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(path,
                               with: .color(.white.opacity(alpha)),
                               lineWidth: 1.2)
                }

                ctx.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                           with: .color(Color.line), lineWidth: 1)
            }
        }
        .frame(minHeight: 130)
    }
}

// MARK: - Спектр

final class SpectrumStore {
    let fft = FFT1024()
    var smooth = [Float](repeating: 0, count: 32)
    var peak: Float = 1e-9
    let bandEdges: [Int] = (0...32).map {
        min(511, Int(pow(512.0, Double($0) / 32.0)))
    }
}

struct SpectrumView: View {
    let engine: Engine
    @State private var store = SpectrumStore()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(rect), with: .color(Color(white: 0.04)))

                let mags = store.fft.magnitudes(engine.lastL)
                let edges = store.bandEdges
                var vals = [Float](repeating: 0, count: 32)
                for b in 0..<32 {
                    let a = edges[b]
                    let c = max(edges[b + 1], a + 1)
                    var s: Float = 0
                    var cnt = 0
                    var k = a
                    while k < c && k < mags.count {
                        s += mags[k]
                        k += 1
                        cnt += 1
                    }
                    vals[b] = s / Float(max(cnt, 1))
                }
                let peakNow = vals.max() ?? 0
                store.peak = max(store.peak * 0.98, peakNow, 1e-9)
                let norm = store.peak
                let bw = size.width / 32
                for b in 0..<32 {
                    let mag = log1pf(vals[b] / norm * 6) / log1pf(6)
                    store.smooth[b] = max(mag, store.smooth[b] * 0.75)
                    let v = store.smooth[b]
                    if v <= 0.01 { continue }
                    let bh = max(2, CGFloat(min(v, 1)) * (size.height - 8))
                    let col: Color = v > 0.9 ? .ledR
                        : (v > 0.75 ? .ledG : .txt)
                    ctx.fill(Path(CGRect(x: CGFloat(b) * bw + 1,
                                         y: size.height - bh,
                                         width: bw - 2, height: bh)),
                             with: .color(col))
                }

                ctx.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                           with: .color(Color.line), lineWidth: 1)
            }
        }
        .frame(minHeight: 130)
    }
}
