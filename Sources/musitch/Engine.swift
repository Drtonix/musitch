/// musitch — DSP-движок: генераторы глитча, сэмплер, эффекты, секвенсор.
/// Источники пишут моно-блок, движок суммирует в стерео → FX → лимитер →
/// транспортный гейт (STOP = тишина).
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
    var midi: Int
    var t: Int
    var dur: Int
    var duty: Float
    var amp: Float = 0.5
}

/// 8-бит канал: квадрат с регулируемой скважностью, играет секвенсор.
/// Потокобезопасный запуск нот (pending-очередь), битовая маска звучащих нот
/// для подсветки пиано-ролла.
final class ChipSrc: Source {
    private var voices: [ChipVoice] = []
    private var pending: [ChipVoice] = []
    private let lock = NSLock()
    /// бит (midi - 60) = нота звучит прямо сейчас
    private(set) var activeMask: UInt64 = 0

    override init(_ title: String) {
        super.init(title)
        on = true
    }

    func noteOn(midi: Int, dur: Float) {
        let f = 440 * powf(2, Float(midi - 69) / 12)
        let v = ChipVoice(freq: f, midi: midi, t: 0,
                          dur: Int(dur * Float(SR)),
                          duty: 0.1 + p1 * 0.4)
        lock.lock()
        pending.append(v)
        lock.unlock()
    }

    override func render(into out: UnsafeMutableBufferPointer<Float>, n: Int) {
        lock.lock()
        if !pending.isEmpty {
            voices.append(contentsOf: pending)
            pending.removeAll()
        }
        lock.unlock()

        var mask: UInt64 = 0
        defer { activeMask = mask }
        guard !voices.isEmpty else { return }

        let sr = Float(SR)
        var alive = 0
        for vi in voices.indices {
            var v = voices[vi]
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
            voices[alive] = v
            alive += 1
            if (60...124).contains(v.midi) {
                mask |= UInt64(1) << UInt64(v.midi - 60)
            }
        }
        if alive < voices.count {
            voices.removeLast(voices.count - alive)
        }
    }
}

// MARK: - Сэмплер

struct SamplerVoice {
    var pos: Double
    var rate0: Double
    var t: Int
}

/// Свой звук: файл → выделенный фрагмент → питч/скорость/закрутка/драйв.
/// Управление потоками: data заменяется целиком (snapshot), триггеры — через
/// pending под замком, playPos — одно слово для визуализации.
final class SamplerSrc: Source {
    @Published var name = "—"
    private(set) var data: [Float] = []
    var selStart = 0
    var selEnd = 0
    var loop = false
    var pitchSemis: Int = 0        // -24..+24, округлённые полутоны
    var speed: Float = 1           // 0.25..4
    var twist: Float = 0           // -1..+1 закрутка (питч-рамп по фрагменту)
    var drive: Float = 0
    private(set) var playPos = -1  // для плейхеда в waveform

    private var voices: [SamplerVoice] = []
    private var pending = 0
    private let lock = NSLock()

    var loaded: Bool { !data.isEmpty }
    var duration: Double { Double(data.count) / SR }

    // ------------------------------------------------ загрузка

    func load(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let srcFmt = file.processingFormat
        let maxFrames = AVAudioFramePosition(SR) * 60   // не более минуты
        let frames = AVAudioFrameCount(min(file.length, maxFrames))
        guard frames > 0 else {
            throw NSError(domain: "musitch", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "пустой файл"])
        }
        let dstFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: SR,
                                   channels: srcFmt.channelCount,
                                   interleaved: false)!
        guard let conv = AVAudioConverter(from: srcFmt, to: dstFmt) else {
            throw NSError(domain: "musitch", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "не могу сконвертировать"])
        }
        guard let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFmt,
                                            frameCapacity: frames) else { return }
        try file.read(into: srcBuf, frameCount: frames)
        let ratio = SR / srcFmt.sampleRate
        let outCap = AVAudioFrameCount(Double(srcBuf.frameLength) * ratio) + 1024
        guard let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFmt,
                                            frameCapacity: outCap) else { return }
        var err: NSError?
        var consumed = false
        conv.convert(to: dstBuf, error: &err) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return srcBuf
        }
        if let err { throw err }
        let ch = Int(dstFmt.channelCount)
        let count = Int(dstBuf.frameLength)
        var mono = [Float](repeating: 0, count: count)
        if let channels = dstBuf.floatChannelData {
            for c in 0..<ch {
                let p = channels[c]
                for i in 0..<count { mono[i] += p[i] / Float(ch) }
            }
        }
        data = mono
        selStart = 0
        selEnd = count
        voices = []
        playPos = -1
        DispatchQueue.main.async {
            self.name = url.deletingPathExtension().lastPathComponent
        }
    }

    // ------------------------------------------------ обработка фрагмента

    func reverseSelection() {
        guard loaded else { return }
        var d = data
        let s0 = selStart, s1 = max(selEnd, selStart + 1)
        d[s0..<s1].reverse()
        data = d
    }

    func normalizeSelection() {
        guard loaded else { return }
        var d = data
        let s0 = selStart, s1 = max(selEnd, selStart + 1)
        var peak: Float = 0
        for i in s0..<s1 { peak = max(peak, abs(d[i])) }
        guard peak > 1e-6 else { return }
        let g = 0.95 / peak
        for i in s0..<s1 { d[i] *= g }
        data = d
    }

    // ------------------------------------------------ запуск

    func trigger() {
        guard loaded else { return }
        lock.lock()
        pending += 1
        lock.unlock()
    }

    // ------------------------------------------------ рендер

    override func render(into out: UnsafeMutableBufferPointer<Float>, n: Int) {
        lock.lock()
        if pending > 0 {
            let rate = Double(powf(2, Float(pitchSemis) / 12) * speed)
            for _ in 0..<pending {
                voices.append(SamplerVoice(pos: Double(selStart),
                                           rate0: rate, t: 0))
            }
            pending = 0
        }
        lock.unlock()

        let d = data
        if voices.isEmpty || d.isEmpty {
            playPos = -1
            return
        }
        let s0 = selStart
        let s1 = max(selEnd, selStart + 256)
        let total = Double(s1 - s0)

        var alive = 0
        for vi in voices.indices {
            var v = voices[vi]
            var dead = false
            for i in 0..<n {
                if v.pos >= Double(s1) || Int(v.pos) + 1 >= d.count {
                    if loop {
                        v.pos = Double(s0)
                            + (v.pos - Double(s0)).truncatingRemainder(dividingBy: total)
                    } else {
                        dead = true
                        break
                    }
                }
                let prog = (v.pos - Double(s0)) / total
                // закрутка: twist>0 раскручивает вверх к концу, <0 — вниз
                let rate = v.rate0 * pow(2.0, Double(twist) * 2.0 * (prog * 2 - 1))
                let p0 = Int(v.pos)
                let fr = Float(v.pos - Double(p0))
                var s = d[p0] * (1 - fr) + d[p0 + 1] * fr
                let fade = min(1, Float(v.t) / 128)   // защита от щелчка
                if drive > 0.01 { s = tanhf(s * (1 + drive * 10)) }
                out[i] += s * fade
                v.pos += max(rate, 0.01)
                v.t += 1
            }
            if !dead {
                voices[alive] = v
                alive += 1
            }
        }
        if alive < voices.count {
            voices.removeLast(voices.count - alive)
        }
        playPos = voices.first.map { Int($0.pos) } ?? -1
    }
}

// MARK: - Эффекты

/// Мастер-цепочка: bitcrush → distortion → delay → фильтр (biquad LP
/// с резонансом) → вариспид → статтер-холд.
final class FX {
    var crush: Float = 0          // 0..1 → битность 16..4
    var dist: Float = 0
    var delayMix: Float = 0
    var delayTime: Float = 0.35   // секунды
    var delayFb: Float = 0.45
    var cutoff: Float = 1         // 1 = открыт
    var reso: Float = 0
    var varispeed: Float = 0      // -1..+1 октавы
    var stutter = false           // держать — зацикливает последний шаг
    var stepSamples: Double = Double(SR) * 60 / 128 / 4

    // delay
    private var dlL = [Float](repeating: 0, count: Int(SR * 2))
    private var dlR = [Float](repeating: 0, count: Int(SR * 2))
    private var dlW = 0

    // biquad LP (RBJ)
    private var bq: (b0: Float, b1: Float, b2: Float,
                     a1: Float, a2: Float) = (1, 0, 0, 0, 0)
    private var bqKey: Float = -1
    private var x1L: Float = 0, x2L: Float = 0, y1L: Float = 0, y2L: Float = 0
    private var x1R: Float = 0, x2R: Float = 0, y1R: Float = 0, y2R: Float = 0

    // varispeed ring
    private var vsL = [Float](repeating: 0, count: 131072)
    private var vsR = [Float](repeating: 0, count: 131072)
    private var vsW = 0
    private var vsRead = 0.0
    private var vsActive = false

    // stutter
    private var stL = [Float](repeating: 0, count: 65536)
    private var stR = [Float](repeating: 0, count: 65536)
    private var stW = 0
    private var stActive = false
    private var stSegStart = 0
    private var stSegLen = 0

    func process(_ L: UnsafeMutableBufferPointer<Float>,
                 _ R: UnsafeMutableBufferPointer<Float>, n: Int) {
        // --- bitcrush
        if crush > 0.01 {
            let bits = 16 - Int(crush * 12)
            let q = powf(2, Float(bits - 1))
            for i in 0..<n {
                L[i] = (L[i] * q).rounded() / q
                R[i] = (R[i] * q).rounded() / q
            }
        }
        // --- distortion
        if dist > 0.01 {
            let d = 1 + dist * 20
            for i in 0..<n {
                L[i] = tanhf(L[i] * d)
                R[i] = tanhf(R[i] * d)
            }
        }
        // --- delay
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
        // --- фильтр с резонансом
        if cutoff < 0.995 || reso > 0.01 {
            let key = cutoff * 1000 + reso
            if key != bqKey {
                bqKey = key
                let fc = 200 * powf(100, cutoff)          // 200 Гц..20 кГц
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
        // --- вариспид (ускорить/замедлить весь микс, октава в обе стороны)
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
        // --- статтер-холд: зацикливает последний шаг секвенсора
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
    let sampler = SamplerSrc("SAMPLER")
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
    private var gate: Float = 0   // транспортный гейт (STOP → 0)

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
                    // сэмплер идёт тем же маршрутом
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

                // транспортный гейт: STOP = тишина (сглажено от щелчков)
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

    /// забрать записанное (interleaved) и очистить буфер
    func takeRecording() -> [Float] {
        recLock.lock()
        let out = recorded
        recorded = []
        recLock.unlock()
        return out
    }
}
