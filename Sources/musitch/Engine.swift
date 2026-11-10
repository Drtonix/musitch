/// musitch — DSP-движок: генераторы глитча, эффекты, секвенсор, микшер.
/// Нативный порт Python-прототипа (prototype-py/dsp.py) — модель та же:
/// источники пишут моно-блок, движок суммирует в стерео → FX → tanh-лимитер.
import AVFoundation
import Accelerate

let SR: Double = 44100

// MARK: - Источники

class Source: ObservableObject {
    let title: String
    @Published var on = false
    var level: Float = 0.8
    var p1: Float = 0.5
    var p2: Float = 0.5
    init(_ title: String) { self.title = title }
    /// перезаписать buf[0..<n] своим сигналом (без level — его приложит движок)
    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {}
}

/// Белый шум через однополюсный фильтр. p1 — тон.
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

/// Электричество: 50 Гц + гармоники. p2 — треск/искры.
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

/// Статтер: дробит несущую на куски. p1 — плотность, p2 — повторы.
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
        // мягкая огибающая на блок, как в прототипе
        let m = max(n - 1, 1)
        for i in 0..<n {
            let w = 0.5 * (1 - cos(2 * .pi * Float(i) / Float(m)))
            out[i] *= pow(w, 0.15) * 0.7
        }
    }
}

/// Кассета: дрон 110 Гц с wow/flutter + шипение + треск. p1 — износ, p2 — расстройка.
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

/// Кнопки старого телевизора: щелчки + затухающие писки. p1 — частота, p2 — высота.
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

/// Чистый перегруз: стек пил через tanh. p1 — драйв, p2 — нота (A0..A4).
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

/// Саб-дрон: глубокий синус с биением. p1 — частота, p2 — биение.
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

// MARK: - Чип-синт

struct ChipVoice {
    var freq: Float
    var t: Int
    var dur: Int
    var duty: Float
    var amp: Float = 0.5
}

/// 8-бит канал: квадрат с регулируемой скважностью, играет секвенсор.
/// p1 — duty (10..50%), p2 — вибрато (вкл если > 0.55).
final class ChipSrc: Source {
    var voices: [ChipVoice] = []

    override init(_ title: String) {
        super.init(title)
        on = true
    }

    func noteOn(midi: Int, dur: Float) {
        let f = 440 * powf(2, Float(midi - 69) / 12)
        voices.append(ChipVoice(freq: f, t: 0, dur: Int(dur * Float(SR)),
                                duty: 0.1 + p1 * 0.4))
    }

    override func render(into out: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard !voices.isEmpty else { return }
        var alive: [ChipVoice] = []
        alive.reserveCapacity(voices.count)
        let sr = Float(SR)
        for var v in voices {
            let left = v.dur - v.t
            if left <= 0 { continue }
            let m = min(n, left)
            var ph: Float = 0
            let vib = p2 > 0.55
            for i in 0..<m {
                var f = v.freq
                if vib {
                    let tt = Float(v.t + i) / sr
                    f = v.freq * (1 + 0.02 * sin(2 * .pi * 8 * tt))
                }
                ph += f / sr
                let frac = ph - ph.rounded(.down)
                let sq: Float = frac < v.duty ? 1 : -1
                let pr = m > 1 ? Float(i) / Float(m - 1) : 0
                let env = min(1, powf(1 - pr, 0.3) + 0.15)
                out[i] += sq * env * v.amp * 0.4
            }
            v.t += m
            alive.append(v)
        }
        voices = alive
    }
}

// MARK: - Эффекты

/// Мастер-цепочка: bitcrush → distortion → delay → lowpass.
final class FX {
    var crush: Float = 0
    var dist: Float = 0
    var delay: Float = 0
    var lp: Float = 1            // 1 = открыт
    private var bufL = [Float](repeating: 0, count: Int(SR))
    private var bufR = [Float](repeating: 0, count: Int(SR))
    private var w = 0
    private var lL: Float = 0
    private var lR: Float = 0

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
        if delay > 0.01 {
            let N = Int(SR)
            let dly = Int(0.35 * SR)
            let fb: Float = 0.45
            let mix = 0.4 * delay
            for i in 0..<n {
                let rpos = (w - dly + N) % N
                let dl = bufL[rpos] * fb
                let dr = bufR[rpos] * fb
                bufL[w] = L[i] + dl
                bufR[w] = R[i] + dr
                L[i] += bufL[rpos] * mix
                R[i] += bufR[rpos] * mix
                w = (w + 1) % N
            }
        }
        if lp < 0.99 {
            let a = 0.005 + lp * 0.2
            for i in 0..<n {
                lL += a * (L[i] - lL)
                lR += a * (R[i] - lR)
                L[i] = lL
                R[i] = lR
            }
        }
    }
}

// MARK: - Секвенсор

/// 16 шагов × ноты; крутит Chip. Клетка кодируется step * 256 + midi.
final class Sequencer {
    let steps = 16
    weak var chip: ChipSrc?
    var bpm: Double = 128
    var playing = false
    private(set) var grid = Set<Int>()
    private var t: Double = 0
    private var nextStep = 0

    func toggle(_ step: Int, _ midi: Int) {
        let k = step * 256 + midi
        if grid.contains(k) { grid.remove(k) } else { grid.insert(k) }
    }

    func contains(_ step: Int, _ midi: Int) -> Bool {
        grid.contains(step * 256 + midi)
    }

    var currentStep: Int {
        playing ? (nextStep - 1 + steps) % steps : -1
    }

    func reset() {
        nextStep = 0
        t = 0
    }

    func advance(_ n: Int) {
        guard playing else { return }
        let stepDur = 60.0 / bpm / 4
        let tEnd = t + Double(n) / SR
        while Double(nextStep) * stepDur < tEnd {
            let s = nextStep % steps
            for k in grid where k / 256 == s {
                chip?.noteOn(midi: k % 256, dur: Float(stepDur * 2))
            }
            nextStep += 1
        }
        t = tEnd
    }
}

// MARK: - Движок

final class Engine: ObservableObject, @unchecked Sendable {
    let chip = ChipSrc("CHIP")
    let sources: [Source]
    let fx = FX()
    let seq = Sequencer()

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

    /// последний отрендеренный блок для визуализаторов (моно-микс L)
    private(set) var lastL = [Float](repeating: 0, count: 1024)

    private var recorded: [Float] = []   // interleaved L/R
    private let recLock = NSLock()
    private let maxRecord = Int(SR) * 2 * 600   // 10 минут максимум

    private var mixL = [Float](repeating: 0, count: 8192)
    private var mixR = [Float](repeating: 0, count: 8192)
    private var scratch = [Float](repeating: 0, count: 8192)

    private var audioEngine: AVAudioEngine?

    init() {
        sources = [NoiseSrc("NOISE"), BuzzSrc("BUZZ"), GlitchSrc("GLITCH"),
                   TapeSrc("TAPE"), TVSrc("TV"), DriveSrc("DRIVE"),
                   SubSrc("SUB"), chip]
        seq.chip = chip
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

    private func render(frameCount: Int,
                        audioBufferList abl: UnsafeMutablePointer<AudioBufferList>) {
        var n = frameCount
        if n > mixL.count {
            mixL = [Float](repeating: 0, count: n)
            mixR = [Float](repeating: 0, count: n)
            scratch = [Float](repeating: 0, count: n)
        }
        n = min(n, mixL.count)

        mixL.withUnsafeMutableBufferPointer { Lp in
            mixR.withUnsafeMutableBufferPointer { Rp in
                let L = UnsafeMutableBufferPointer(
                    start: Lp.baseAddress!, count: n)
                let R = UnsafeMutableBufferPointer(
                    start: Rp.baseAddress!, count: n)
                for i in 0..<n { L[i] = 0; R[i] = 0 }

                seq.advance(n)

                scratch.withUnsafeMutableBufferPointer { sp in
                    let S = UnsafeMutableBufferPointer(
                        start: sp.baseAddress!, count: n)
                    for src in sources where src.on {
                        for i in 0..<n { S[i] = 0 }
                        src.render(into: S, n: n)
                        let lv = src.level
                        for i in 0..<n {
                            let v = S[i] * lv
                            L[i] += v
                            R[i] += v
                        }
                    }
                }

                fx.process(L, R, n: n)
                let m = master
                for i in 0..<n {
                    L[i] = tanhf(L[i] * m)
                    R[i] = tanhf(R[i] * m)
                }
            }
        }

        // запись
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

        // визуализаторы
        let k = min(n, 1024)
        for i in 0..<k { lastL[i] = mixL[i] }

        // выдача в AVAudioEngine
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

    /// забрать записанное (interleaved) и очистить буфер
    func takeRecording() -> [Float] {
        recLock.lock()
        let out = recorded
        recorded = []
        recLock.unlock()
        return out
    }
}
