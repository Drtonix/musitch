/// musitch — DSP-движок: текстуры, чипы, сэмплер, эффекты, секвенсор, микшер.
/// renderBlock(n) наполняет mixL/mixR; аудио-колбэк и офлайн-рендер делят его.
import AVFoundation
import Accelerate

// MARK: - Текстуры (шумовые генераторы-фактуры)

class Source: ObservableObject {
    let title: String
    @Published var on = false
    var level: Float = 0.8
    var p1: Float = 0.5
    var p2: Float = 0.5
    init(_ title: String) { self.title = title }
    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {}
}

final class NoiseSrc: Source {
    private var mem: Float = 0
    override func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        let a = 0.02 + p1 * 0.25
        let gain = 1 + 6 * p1
        var m = mem
        for i in 0..<n {
            let w = Float.random(in: -1...1)
            m += a * (w - m)
            buf[i] = m * gain
        }
        mem = m
    }
}

final class BuzzSrc: Source {
    private var ph: [Float] = [0, 0, 0, 0, 0]
    private let harms: [Float] = [1, 2, 3, 5, 7]
    private let gains: [Float] = [1, 0.45, 0.3, 0.12, 0.07]
    override func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        let f0: Float = 50
        let sr = Float(SR)
        for i in 0..<n {
            var s: Float = 0
            for h in 0..<5 {
                ph[h] += f0 * harms[h] / sr
                if ph[h] >= 1 { ph[h] -= 1 }
                s += gains[h] * (ph[h] < 0.5 ? 1 : -1)
            }
            s *= 0.6
            if p2 > 0.05, Float.random(in: 0...1) < p2 * 0.002 {
                s += Float.random(in: -1...1)
            }
            buf[i] = s * 0.25
        }
    }
}

final class GlitchSrc: Source {
    private var buf = [Float](repeating: 0, count: 4096)
    private var len = 1
    private var pos = 1
    private var cnt = 0
    override func render(into out: UnsafeMutableBufferPointer<Float>, n: Int) {
        let grain = max(32, Int((1 - p1) * 2200))
        let rep = max(1, Int(p2 * 8))
        var i = 0
        while i < n {
            if pos >= len {
                len = min(grain, buf.count)
                switch Int.random(in: 0..<3) {
                case 0:
                    for j in 0..<len { buf[j] = Float.random(in: -1...1) }
                case 1:
                    let f = Float.random(in: 200...4000)
                    let m = max(len - 1, 1)
                    for j in 0..<len {
                        let t = Float(j) / Float(SR)
                        let w = 0.5 * (1 - cos(2 * .pi * Float(j) / Float(m)))
                        buf[j] = sin(2 * .pi * f * t) * w
                    }
                default:
                    for j in 0..<len { buf[j] = 0 }
                    for j in 0..<min(64, len) { buf[j] = Float.random(in: -1...1) }
                }
                pos = 0
                cnt = rep
            }
            let take = min(n - i, len - pos)
            for j in 0..<take { out[i + j] = buf[pos + j] }
            pos += take
            i += take
            if pos >= len {
                cnt -= 1
                if cnt > 0 { pos = 0 }
            }
        }
        let m = max(n - 1, 1)
        for i in 0..<n {
            let w = 0.5 * (1 - cos(2 * .pi * Float(i) / Float(m)))
            out[i] *= pow(w, 0.15) * 0.7
        }
    }
}

final class TapeSrc: Source {
    private var wowPh: Float = 0
    private var dronePh: Float = 0
    override func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        let sr = Float(SR)
        for i in 0..<n {
            wowPh += 0.6 / sr
            if wowPh >= 1 { wowPh -= 1 }
            let f = 110 + sin(2 * .pi * wowPh) * p2 * 6
            dronePh += f / sr
            if dronePh >= 1 { dronePh -= 1 }
            let drone = sin(2 * .pi * dronePh) * 0.4 + sin(4 * .pi * dronePh) * 0.15
            var s = drone * 0.5 + Float.random(in: -1...1) * 0.06
            if Float.random(in: 0...1) < p1 * 0.0008 {
                s += Float.random(in: -1...1) * 0.8
            }
            buf[i] = s
        }
    }
}

final class TVSrc: Source {
    private var buf = [Float](repeating: 0, count: 8192)
    private var len = 0
    private var pos = 0
    override func render(into out: UnsafeMutableBufferPointer<Float>, n: Int) {
        var i = 0
        while i < n {
            if pos >= len {
                guard Float.random(in: 0...1) < p1 * 0.0009 else { break }
                let ln = Int(0.02 * SR) + Int(Float.random(in: 0...1) * 0.08 * Float(SR))
                let f = 300 + p2 * 2000 + Float.random(in: 0...800)
                len = min(12 + ln, buf.count)
                for j in 0..<12 { buf[j] = Float.random(in: -1...1) }
                for j in 0..<(len - 12) {
                    let t = Float(j) / Float(SR)
                    buf[12 + j] = sin(2 * .pi * f * t) * exp(-t * 60)
                }
                pos = 0
            }
            let take = min(n - i, len - pos)
            for j in 0..<take { out[i + j] = buf[pos + j] }
            pos += take
            i += take
        }
    }
}

final class DriveSrc: Source {
    private var ph: [Float] = [0, 0, 0]
    private let mult: [Float] = [1.0, 1.005, 0.5]
    override func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        let base = 27.5 * powf(2, p2 * 4)
        let d = 1 + p1 * 24
        let sr = Float(SR)
        for i in 0..<n {
            var s: Float = 0
            for h in 0..<3 {
                ph[h] += base * mult[h] / sr
                if ph[h] >= 1 { ph[h] -= 1 }
                s += ph[h] * 2 - 1
            }
            buf[i] = tanhf(s / 3 * d) * 0.5
        }
    }
}

final class SubSrc: Source {
    private var ph: Float = 0
    private var lfoPh: Float = 0
    override func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        let f = 30 + p1 * 40
        let beat = 0.5 + p2 * 6
        let sr = Float(SR)
        for i in 0..<n {
            ph += f / sr
            if ph >= 1 { ph -= 1 }
            lfoPh += beat / sr
            if lfoPh >= 1 { lfoPh -= 1 }
            let lfo = 0.75 + 0.25 * sin(2 * .pi * lfoPh)
            buf[i] = sin(2 * .pi * ph) * lfo * 0.8
        }
    }
}

// MARK: - Эффекты

final class FX {
    var crush: Float = 0
    var dist: Float = 0
    var delayMix: Float = 0
    var delayTime: Float = 0.35
    var delayFb: Float = 0.45
    var cutoff: Float = 1
    var reso: Float = 0
    var varispeed: Float = 0
    var stutter = false
    var stepSamples: Double = Double(SR) * 60 / 128 / 4

    private var dlL = [Float](repeating: 0, count: Int(SR * 2))
    private var dlR = [Float](repeating: 0, count: Int(SR * 2))
    private var dlW = 0

    private var bq: (b0: Float, b1: Float, b2: Float,
                     a1: Float, a2: Float) = (1, 0, 0, 0, 0)
    private var bqKey: Float = -1
    private var x1L: Float = 0, x2L: Float = 0, y1L: Float = 0, y2L: Float = 0
    private var x1R: Float = 0, x2R: Float = 0, y1R: Float = 0, y2R: Float = 0

    private var vsL = [Float](repeating: 0, count: 131072)
    private var vsR = [Float](repeating: 0, count: 131072)
    private var vsW = 0
    private var vsRead = 0.0
    private var vsActive = false

    private var stL = [Float](repeating: 0, count: 65536)
    private var stR = [Float](repeating: 0, count: 65536)
    private var stW = 0
    private var stActive = false
    private var stSegStart = 0
    private var stSegLen = 0

    func process(_ L: UnsafeMutableBufferPointer<Float>,
                 _ R: UnsafeMutableBufferPointer<Float>, n: Int) {
        if crush > 0.01 {
            let bits = 16 - Int(crush * 12)
            let q = powf(2, Float(bits - 1))
            for i in 0..<n {
                L[i] = (L[i] * q).rounded() / q
                R[i] = (R[i] * q).rounded() / q
            }
        }
        if dist > 0.01 {
            let d = 1 + dist * 20
            for i in 0..<n {
                L[i] = tanhf(L[i] * d)
                R[i] = tanhf(R[i] * d)
            }
        }
        if delayMix > 0.01 {
            let N = dlL.count
            let dly = max(1, min(Int(delayTime * Float(SR)), N - 2))
            let fb = min(delayFb, 0.95)
            let mix = delayMix * 0.5
            for i in 0..<n {
                let rpos = (dlW - dly + N) % N
                let dl = dlL[rpos] * fb
                let dr = dlR[rpos] * fb
                dlL[dlW] = L[i] + dl
                dlR[dlW] = R[i] + dr
                L[i] += dlL[rpos] * mix
                R[i] += dlR[rpos] * mix
                dlW = (dlW + 1) % N
            }
        }
        if cutoff < 0.995 || reso > 0.01 {
            let key = cutoff * 1000 + reso
            if key != bqKey {
                bqKey = key
                let fc = 200 * powf(100, cutoff)
                let Q = 0.5 + reso * 8
                let w0 = 2 * Float.pi * min(fc, 20000) / Float(SR)
                let alpha = sin(w0) / (2 * Q)
                let cw = cos(w0)
                let a0 = 1 + alpha
                bq = ((1 - cw) / 2 / a0, (1 - cw) / a0, (1 - cw) / 2 / a0,
                      -2 * cw / a0, (1 - alpha) / a0)
            }
            for i in 0..<n {
                let xl = L[i]
                let yl = bq.b0 * xl + bq.b1 * x1L + bq.b2 * x2L
                    - bq.a1 * y1L - bq.a2 * y2L
                x2L = x1L; x1L = xl; y2L = y1L; y1L = yl
                L[i] = yl
                let xr = R[i]
                let yr = bq.b0 * xr + bq.b1 * x1R + bq.b2 * x2R
                    - bq.a1 * y1R - bq.a2 * y2R
                x2R = x1R; x1R = xr; y2R = y1R; y1R = yr
                R[i] = yr
            }
        }
        if abs(varispeed) > 0.005 {
            let N = vsL.count
            if !vsActive {
                vsActive = true
                vsW = 4096
                vsRead = 0
            }
            let rate = Double(powf(2, varispeed))
            for i in 0..<n {
                vsL[vsW] = L[i]
                vsR[vsW] = R[i]
                vsW = (vsW + 1) % N
                let r0 = Int(vsRead) % N
                let r1 = (r0 + 1) % N
                let fr = Float(vsRead - Double(Int(vsRead)))
                L[i] = vsL[r0] * (1 - fr) + vsL[r1] * fr
                R[i] = vsR[r0] * (1 - fr) + vsR[r1] * fr
                vsRead += rate
                let dist = (vsW - Int(vsRead) + N) % N
                if dist < 128 || dist > N - 512 {
                    vsRead = Double((vsW - 4096 + N) % N)
                }
            }
        } else if vsActive {
            vsActive = false
        }
        let stN = stL.count
        if stutter {
            if !stActive {
                stActive = true
                stSegLen = max(256, min(Int(stepSamples), stN / 2))
                stSegStart = (stW - stSegLen + stN) % stN
            }
            var p = stSegStart
            for i in 0..<n {
                L[i] = stL[p]
                R[i] = stR[p]
                p = (p + 1) % stN
                if p == (stSegStart + stSegLen) % stN { p = stSegStart }
            }
        } else {
            stActive = false
            for i in 0..<n {
                stL[stW] = L[i]
                stR[stW] = R[i]
                stW = (stW + 1) % stN
            }
        }
    }
}

// MARK: - Движок

final class Engine: ObservableObject, @unchecked Sendable {
    // текстуры
    let textures: [Source]
    // чипы
    let gbP1 = GBPulse(sweep: true)
    let gbP2 = GBPulse(sweep: false)
    let gbW = GBWave()
    let gbN = GBNoise()
    let nesP1 = NESPulse()
    let nesP2 = NESPulse()
    let nesT = NESTri()
    let nesN = NESNoise()
    let fm1 = YMChannel()
    let fm2 = YMChannel()
    let psg1 = PSGSquare()
    let psg2 = PSGSquare()
    let psg3 = PSGSquare()
    let psgN = PSGNoise()
    // сэмплер и остальное
    let sampler = SamplerSrc("SAMPLER")
    let fx = FX()
    let seq = Seq()

    var master: Float = 0.9
    @Published var playing = false {
        didSet {
            seq.playing = playing
            if !playing { seq.reset() }
        }
    }
    @Published var recording = false
    @Published var bpm: Double = 128 {
        didSet { seq.bpm = bpm }
    }

    private(set) var lastL = [Float](repeating: 0, count: 1024)

    private var recorded: [Float] = []
    private let recLock = NSLock()
    private let maxRecord = Int(SR) * 2 * 600

    private var mixL = [Float](repeating: 0, count: 8192)
    private var mixR = [Float](repeating: 0, count: 8192)
    private var scratch = [Float](repeating: 0, count: 8192)
    private var gate: Float = 0

    private var audioEngine: AVAudioEngine?

    init() {
        textures = [NoiseSrc("NOISE"), BuzzSrc("BUZZ"), GlitchSrc("GLITCH"),
                    TapeSrc("TAPE"), TVSrc("TV"), DriveSrc("DRIVE"),
                    SubSrc("SUB")]
        seq.channels = [
            Channel(name: "GB·P1", voice: gbP1),
            Channel(name: "GB·P2", voice: gbP2),
            Channel(name: "GB·W", voice: gbW),
            Channel(name: "GB·N", voice: gbN),
            Channel(name: "NES·P1", voice: nesP1),
            Channel(name: "NES·P2", voice: nesP2),
            Channel(name: "NES·TRI", voice: nesT),
            Channel(name: "NES·N", voice: nesN),
            Channel(name: "GEN·FM1", voice: fm1),
            Channel(name: "GEN·FM2", voice: fm2),
            Channel(name: "SMS·1", voice: psg1),
            Channel(name: "SMS·2", voice: psg2),
            Channel(name: "SMS·3", voice: psg3),
            Channel(name: "SMS·N", voice: psgN),
        ]
        startAudio()
    }

    private func startAudio() {
        let eng = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 2)!
        let node = AVAudioSourceNode(format: format) {
            [weak self] _, _, frameCount, abl -> OSStatus in
            self?.render(frameCount: Int(frameCount), audioBufferList: abl)
            return noErr
        }
        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: format)
        do {
            try eng.start()
        } catch {
            print("musitch: не удалось запустить аудио — \(error)")
        }
        audioEngine = eng
    }

    /// общий проход микшера: секвенсор → каналы/текстуры/сэмплер → FX →
    /// лимитер → транспортный гейт. Результат в mixL/mixR.
    private func renderBlock(_ n: Int) {
        mixL.withUnsafeMutableBufferPointer { Lp in
            mixR.withUnsafeMutableBufferPointer { Rp in
                let L = UnsafeMutableBufferPointer(start: Lp.baseAddress!,
                                                   count: n)
                let R = UnsafeMutableBufferPointer(start: Rp.baseAddress!,
                                                   count: n)
                for i in 0..<n { L[i] = 0; R[i] = 0 }

                seq.advance(n)

                scratch.withUnsafeMutableBufferPointer { sp in
                    let S = UnsafeMutableBufferPointer(start: sp.baseAddress!,
                                                       count: n)
                    for src in textures where src.on {
                        for i in 0..<n { S[i] = 0 }
                        src.render(into: S, n: n)
                        let lv = src.level
                        for i in 0..<n {
                            let v = S[i] * lv
                            L[i] += v
                            R[i] += v
                        }
                    }
                    for ch in seq.channels where !ch.muted && ch.voice.on {
                        for i in 0..<n { S[i] = 0 }
                        ch.voice.render(into: S, n: n)
                        for i in 0..<n {
                            L[i] += S[i]
                            R[i] += S[i]
                        }
                    }
                    if sampler.on {
                        for i in 0..<n { S[i] = 0 }
                        sampler.render(into: S, n: n)
                        let lv = sampler.level
                        for i in 0..<n {
                            let v = S[i] * lv
                            L[i] += v
                            R[i] += v
                        }
                    }
                }

                fx.stepSamples = SR * 60 / bpm / 4
                fx.process(L, R, n: n)
                let m = master
                for i in 0..<n {
                    L[i] = tanhf(L[i] * m)
                    R[i] = tanhf(R[i] * m)
                }

                let target: Float = playing ? 1 : 0
                var g = gate
                for i in 0..<n {
                    g += (target - g) * 0.003
                    L[i] *= g
                    R[i] *= g
                }
                gate = g
            }
        }
    }

    private func render(frameCount: Int,
                        audioBufferList abl: UnsafeMutablePointer<AudioBufferList>) {
        var n = frameCount
        if n > mixL.count {
            mixL = [Float](repeating: 0, count: n)
            mixR = [Float](repeating: 0, count: n)
            scratch = [Float](repeating: 0, count: n)
        }
        n = min(n, mixL.count)
        renderBlock(n)

        if recording {
            recLock.lock()
            if recorded.count < maxRecord {
                var block: [Float] = []
                block.reserveCapacity(n * 2)
                for i in 0..<n {
                    block.append(mixL[i])
                    block.append(mixR[i])
                }
                recorded.append(contentsOf: block)
            }
            recLock.unlock()
        }

        let k = min(n, 1024)
        for i in 0..<k { lastL[i] = mixL[i] }

        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        if buffers.count >= 2,
           let pL = buffers[0].mData?.assumingMemoryBound(to: Float.self),
           let pR = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
            for i in 0..<n { pL[i] = mixL[i]; pR[i] = mixR[i] }
        } else if let p = buffers.first?.mData?
            .assumingMemoryBound(to: Float.self) {
            for i in 0..<n {
                p[i * 2] = mixL[i]
                p[i * 2 + 1] = mixR[i]
            }
        }
    }

    /// офлайн-рендер для проверки и скрин-экспорта (interleaved)
    func renderOffline(_ seconds: Double) -> [Float] {
        let total = Int(seconds * SR)
        var out: [Float] = []
        out.reserveCapacity(total * 2)
        var done = 0
        while done < total {
            let n = min(1024, total - done)
            renderBlock(n)
            for i in 0..<n {
                out.append(mixL[i])
                out.append(mixR[i])
            }
            done += n
        }
        return out
    }

    func takeRecording() -> [Float] {
        recLock.lock()
        let out = recorded
        recorded = []
        recLock.unlock()
        return out
    }
}
