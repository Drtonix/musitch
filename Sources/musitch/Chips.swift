/// musitch — эмуляторы звуковых чипов: Game Boy (DMG APU), NES (2A03),
/// Sega Genesis (YM2612-lite FM), Sega Master System (SN76489 PSG).
/// Не cycle-accurate, а характерные: те же волны, огибающие, LFSR, алгоритмы FM.
import Foundation

let SR: Double = 44100

/// протокол канала чипа: секвенсор дёргает noteOn, движок — render
protocol ChipVoiceType: AnyObject {
    var on: Bool { get set }
    func noteOn(midi: Int, dur: Float, vel: Float)
    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int)
}

@inline(__always)
func polyBLEP(_ t: Double, _ dt: Double) -> Double {
    if t < dt { let x = t / dt; return 2 * x - x * x - 1 }
    if t > 1 - dt { let x = (t - 1) / dt; return x * x + 2 * x + 1 }
    return 0
}

@inline(__always)
func mtof(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

// MARK: - Game Boy APU

/// GB Pulse 1/2: duty 12.5/25/50/75%, огибающая громкости, свип (ch1).
final class GBPulse: ChipVoiceType {
    var on = true
    let hasSweep: Bool
    var duty = 2                 // 0..3
    var envVol: Float = 13       // 0..15
    var envDecay: Float = 0      // сек до тишины; 0 = sustain до конца ноты
    var sweep: Float = 0         // -1..1 (октавы/сек)
    private var phase = 0.0
    private var freq = 440.0
    private var baseFreq = 440.0
    private var t = 0.0
    private var dur = 0.0
    private var vel: Float = 1
    private var sounding = false

    init(sweep: Bool) { hasSweep = sweep }

    func noteOn(midi: Int, dur: Float, vel: Float) {
        baseFreq = mtof(midi)
        freq = baseFreq
        self.dur = Double(dur)
        self.vel = vel
        t = 0
        phase = 0
        sounding = true
    }

    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard on, sounding else { return }
        let dutyF = [0.125, 0.25, 0.5, 0.75][duty]
        for i in 0..<n {
            if hasSweep && sweep != 0 {
                freq = baseFreq * pow(2, Double(sweep) * t)
            }
            let dt = freq / SR
            phase += dt
            if phase >= 1 { phase -= 1 }
            var s = phase < dutyF ? 1.0 : -1.0
            s += polyBLEP(phase, dt)
            var t2 = phase - dutyF
            if t2 < 0 { t2 += 1 }
            s -= polyBLEP(t2, dt)
            var env = envVol / 15 * vel
            if envDecay > 0 {
                env *= max(0, 1 - Float(t / Double(envDecay)))
                if t > Double(envDecay) { sounding = false; break }
            } else if t > dur {
                sounding = false
                break
            }
            buf[i] += Float(s) * env * 0.22
            t += 1 / SR
        }
    }
}

/// GB Wave: 32×4-бит волновая таблица (без интерполяции — как в железе).
final class GBWave: ChipVoiceType {
    var on = true
    var preset = 0               // 0 sine, 1 saw, 2 square, 3 bell, 4 bass
    var vol: Float = 1           // GB: 0/25/50/100%
    private(set) var table = [Float](repeating: 0, count: 32)
    private var phase = 0.0
    private var t = 0.0
    private var dur = 0.0
    private var vel: Float = 1
    private var sounding = false

    init() { applyPreset() }

    func applyPreset() {
        switch preset {
        case 0: for i in 0..<32 { table[i] = sin(2 * .pi * Float(i) / 32) }
        case 1: for i in 0..<32 { table[i] = Float(i) / 16 - 1 }
        case 2: for i in 0..<32 { table[i] = i < 8 ? 1 : -1 }
        case 3: // «колокол» — спадающие пики
            for i in 0..<32 {
                table[i] = sin(2 * .pi * Float(i) / 32)
                    * exp(-Float(i % 8) * 0.35) * 1.8
            }
        default: // «бас» — треугольник с подъёмом
            for i in 0..<32 {
                let x = Float(i) / 32
                table[i] = (x < 0.5 ? x * 4 - 1 : 3 - x * 4)
                    * (0.7 + 0.3 * sin(2 * .pi * x * 3))
            }
        }
    }

    func noteOn(midi: Int, dur: Float, vel: Float) {
        phase = 0
        t = 0
        self.dur = Double(dur)
        self.vel = vel
        sounding = true
        _freq = mtof(midi)
    }
    private var _freq = 440.0

    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard on, sounding else { return }
        let v = vol * 0.2
        for i in 0..<n {
            if t > dur { sounding = false; break }
            phase += _freq / SR
            if phase >= 1 { phase -= 1 }
            let idx = Int(phase * 32) & 31
            buf[i] += table[idx] * v * vel
            t += 1 / SR
        }
    }
}

/// GB Noise: LFSR 15/7 бит, высота через сдвиг, огибающая для хэта.
final class GBNoise: ChipVoiceType {
    var on = true
    var mode7 = false            // 7-бит «металлический» режим
    var envDecay: Float = 0.12   // короткий хэт по умолчанию
    var envVol: Float = 13
    private var lfsr: UInt16 = 0x7FFF
    private var clk = 0.0
    private var clkRate = 4410.0
    private var held: Float = 0
    private var t = 0.0
    private var dur = 0.0
    private var vel: Float = 1
    private var sounding = false

    func noteOn(midi: Int, dur: Float, vel: Float) {
        // midi → частота клока LFSR (лог-шкала 300 Гц..~60 кГц)
        clkRate = 300 * pow(2, Double(midi - 36) / 18)
        lfsr = 0x7FFF
        t = 0
        self.dur = Double(dur)
        self.vel = vel
        sounding = true
    }

    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard on, sounding else { return }
        let step = clkRate / SR
        for i in 0..<n {
            clk += step
            if clk >= 1 {
                clk -= 1
                let bit = (lfsr ^ (lfsr >> 1)) & 1
                lfsr = (lfsr >> 1) | (bit << 14)
                if mode7 { lfsr = (lfsr & ~(1 << 6)) | (bit << 6) }
                held = (lfsr & 1) == 0 ? 1 : -1
            }
            let env = max(0, 1 - Float(t / Double(envDecay)))
            if env <= 0 || t > dur { sounding = false; break }
            buf[i] += held * env * (envVol / 15) * vel * 0.22
            t += 1 / SR
        }
    }
}

// MARK: - NES 2A03

/// NES Pulse: duty, свип, без огибающей громкости (в 2A03 — fixed/loop).
final class NESPulse: ChipVoiceType {
    var on = true
    var duty = 2
    var sweep: Float = 0
    var vol: Float = 12
    private var phase = 0.0
    private var freq = 440.0
    private var baseFreq = 440.0
    private var t = 0.0
    private var dur = 0.0
    private var vel: Float = 1
    private var sounding = false

    func noteOn(midi: Int, dur: Float, vel: Float) {
        baseFreq = mtof(midi)
        freq = baseFreq
        self.dur = Double(dur)
        self.vel = vel
        t = 0
        phase = 0
        sounding = true
    }

    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard on, sounding else { return }
        let dutyF = [0.125, 0.25, 0.5, 0.75][duty]
        for i in 0..<n {
            if t > dur { sounding = false; break }
            if sweep != 0 { freq = baseFreq * pow(2, Double(sweep) * t) }
            let dt = freq / SR
            phase += dt
            if phase >= 1 { phase -= 1 }
            var s = phase < dutyF ? 1.0 : -1.0
            s += polyBLEP(phase, dt)
            var t2 = phase - dutyF
            if t2 < 0 { t2 += 1 }
            s -= polyBLEP(t2, dt)
            buf[i] += Float(s) * (vol / 15) * vel * 0.22
            t += 1 / SR
        }
    }
}

/// NES Triangle: 16-ступенчатая пила-треугольник, без огибающей.
final class NESTri: ChipVoiceType {
    var on = true
    var vol: Float = 13
    private let stepsTable: [Float] = (0..<16).map {
        Float($0 < 8 ? 15 - $0 : $0 - 8) / 15 * 2 - 1
    }
    private var phase = 0.0
    private var freq = 440.0
    private var t = 0.0
    private var dur = 0.0
    private var vel: Float = 1
    private var sounding = false

    func noteOn(midi: Int, dur: Float, vel: Float) {
        freq = mtof(midi)
        self.dur = Double(dur)
        self.vel = vel
        t = 0
        phase = 0
        sounding = true
    }

    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard on, sounding else { return }
        for i in 0..<n {
            if t > dur { sounding = false; break }
            phase += freq / SR
            if phase >= 1 { phase -= 1 }
            buf[i] += stepsTable[Int(phase * 16) & 15] * (vol / 15) * vel * 0.25
            t += 1 / SR
        }
    }
}

/// NES Noise: LFSR с 16 периодами из таблицы 2A03 + «тональный» режим.
final class NESNoise: ChipVoiceType {
    var on = true
    var tonal = false            // короткая петля LFSR
    var envDecay: Float = 0.15
    var vol: Float = 12
    /// периоды 2A03 в отсчётах APU (переведены в Гц при render)
    private let periods = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254,
                           380, 508, 762, 1016, 2034, 4068]
    private var lfsr: UInt16 = 1
    private var clk = 0.0
    private var clkRate = 1000.0
    private var held: Float = 0
    private var t = 0.0
    private var dur = 0.0
    private var vel: Float = 1
    private var sounding = false

    func noteOn(midi: Int, dur: Float, vel: Float) {
        let idx = max(0, min(15, (midi - 24) / 3))
        clkRate = 1789773.0 / Double(periods[idx])
        lfsr = 1
        t = 0
        self.dur = Double(dur)
        self.vel = vel
        sounding = true
    }

    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard on, sounding else { return }
        let step = clkRate / SR
        for i in 0..<n {
            clk += step
            if clk >= 1 {
                clk -= 1
                let tap = tonal ? (lfsr >> 6) : (lfsr >> 1)
                let bit = (lfsr ^ tap) & 1
                lfsr = (lfsr >> 1) | (bit << 14)
                held = (lfsr & 1) == 0 ? 1 : -1
            }
            let env = max(0, 1 - Float(t / Double(envDecay)))
            if env <= 0 || t > dur { sounding = false; break }
            buf[i] += held * env * (vol / 15) * vel * 0.2
            t += 1 / SR
        }
    }
}

// MARK: - Sega Genesis YM2612 (lite 4-op FM)

struct FMOp {
    var mul: Float = 1
    var tl: Float = 0.5          // 0 = громко, 1 = тихо
    var ar: Float = 30           // 1/сек до пика
    var dr: Float = 4            // 1/сек спад к sustain
    var sl: Float = 0.4          // sustain level
    var rr: Float = 6            // 1/сек отпускание
    var phase = 0.0
    var env: Float = 0
    var released = false
    var t: Float = 0
}

/// Один FM-канал: 4 оператора, 8 алгоритмов, feedback на op1.
final class YMChannel: ChipVoiceType {
    var on = true
    var algo = 4                 // 0..7
    var fb: Float = 0.3          // 0..1
    var modRatio: Float = 2      // множитель модуляторов
    var modLevel: Float = 0.6    // глубина FM (яркость)
    var decay: Float = 3         // общий спад
    var vol: Float = 0.85

    private var ops = (0..<4).map { _ in FMOp() }
    private var freq = 440.0
    private var dur: Float = 0
    private var t: Float = 0
    private var vel: Float = 1
    private var sounding = false
    private var fbMem: Float = 0

    func noteOn(midi: Int, dur: Float, vel: Float) {
        freq = mtof(midi)
        self.dur = dur
        self.vel = vel
        t = 0
        sounding = true
        fbMem = 0
        for i in 0..<4 {
            ops[i].phase = 0
            ops[i].env = 0
            ops[i].released = false
            ops[i].t = 0
        }
    }

    @inline(__always)
    private func envStep(_ op: inout FMOp) -> Float {
        op.t += Float(1 / SR)
        if t > dur { op.released = true }
        if op.released {
            op.env = max(0, op.env - op.rr * Float(1 / SR))
        } else if op.env < 1 && op.t * op.ar < 1 {
            op.env = min(1, op.t * op.ar)                    // attack
        } else {
            let target = op.sl
            if op.env > target {
                op.env = max(target, op.env - op.dr * Float(1 / SR))
            }
        }
        return op.env
    }

    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard on, sounding else { return }
        let muls: [Float] = [1, modRatio, modRatio * 2, 1]   // op1,2,3 модуляторы, op4 несущая
        let tls: [Float] = [modLevel, modLevel, modLevel * 0.7, 0.05]
        for i in 0..<4 {
            ops[i].mul = muls[i]
            ops[i].tl = tls[i]
            ops[i].dr = decay
            ops[i].rr = decay * 2
        }
        var alive = false
        for i in 0..<n {
            var o = [Float](repeating: 0, count: 4)
            for j in 0..<4 {
                let env = envStep(&ops[j])
                if env > 0.001 { alive = true }
                ops[j].phase += freq * Double(ops[j].mul) / SR
                if ops[j].phase >= 1 { ops[j].phase -= 1 }
                o[j] = env * (1 - ops[j].tl)
            }
            // алгоритмы YM2612 (упрощённо, индексы op1..4 → o[0..3])
            var out: Float = 0
            switch algo {
            case 0: // 1→2→3→4
                let m1 = sin(2 * .pi * Float(ops[0].phase)
                    + fb * fbMem * 3) * o[0]
                fbMem = m1
                let m2 = sin(2 * .pi * Float(ops[1].phase) + m1 * 4) * o[1]
                let m3 = sin(2 * .pi * Float(ops[2].phase) + m2 * 4) * o[2]
                out = sin(2 * .pi * Float(ops[3].phase) + m3 * 4) * o[3]
            case 1: // (1+2)→3→4
                let m1 = sin(2 * .pi * Float(ops[0].phase)
                    + fb * fbMem * 3) * o[0]
                fbMem = m1
                let m2 = sin(2 * .pi * Float(ops[1].phase)) * o[1]
                let m3 = sin(2 * .pi * Float(ops[2].phase) + (m1 + m2) * 4) * o[2]
                out = sin(2 * .pi * Float(ops[3].phase) + m3 * 4) * o[3]
            case 2: // (1+(2→3))→4
                let m1 = sin(2 * .pi * Float(ops[0].phase)
                    + fb * fbMem * 3) * o[0]
                fbMem = m1
                let m2 = sin(2 * .pi * Float(ops[1].phase)) * o[1]
                let m3 = sin(2 * .pi * Float(ops[2].phase) + m2 * 4) * o[2]
                out = sin(2 * .pi * Float(ops[3].phase) + (m1 + m3) * 4) * o[3]
            case 3: // (1→3)+(2→4)... параллельные пары
                let m1 = sin(2 * .pi * Float(ops[0].phase)
                    + fb * fbMem * 3) * o[0]
                fbMem = m1
                let m3 = sin(2 * .pi * Float(ops[2].phase) + m1 * 4) * o[2]
                let m2 = sin(2 * .pi * Float(ops[1].phase)) * o[1]
                let o4 = sin(2 * .pi * Float(ops[3].phase) + m2 * 4) * o[3]
                out = (m3 + o4) * 0.7
            case 4: // (1→2)+(3→4)
                let m1 = sin(2 * .pi * Float(ops[0].phase)
                    + fb * fbMem * 3) * o[0]
                fbMem = m1
                let m2 = sin(2 * .pi * Float(ops[1].phase) + m1 * 4) * o[1]
                let m3 = sin(2 * .pi * Float(ops[2].phase)) * o[2]
                let o4 = sin(2 * .pi * Float(ops[3].phase) + m3 * 4) * o[3]
                out = (m2 + o4) * 0.7
            case 5: // 1→(2,3,4)
                let m1 = sin(2 * .pi * Float(ops[0].phase)
                    + fb * fbMem * 3) * o[0]
                fbMem = m1
                let m2 = sin(2 * .pi * Float(ops[1].phase) + m1 * 4) * o[1]
                let m3 = sin(2 * .pi * Float(ops[2].phase) + m1 * 4) * o[2]
                let o4 = sin(2 * .pi * Float(ops[3].phase) + m1 * 4) * o[3]
                out = (m2 + m3 + o4) / 3
            case 6: // 1→2 + 3 + 4
                let m1 = sin(2 * .pi * Float(ops[0].phase)
                    + fb * fbMem * 3) * o[0]
                fbMem = m1
                let m2 = sin(2 * .pi * Float(ops[1].phase) + m1 * 4) * o[1]
                let m3 = sin(2 * .pi * Float(ops[2].phase)) * o[2]
                let o4 = sin(2 * .pi * Float(ops[3].phase)) * o[3]
                out = (m2 + m3 + o4) / 3
            default: // 7: все параллельно (4 пилы-синусы)
                out = (o[0] * sin(2 * .pi * Float(ops[0].phase))
                    + o[1] * sin(2 * .pi * Float(ops[1].phase))
                    + o[2] * sin(2 * .pi * Float(ops[2].phase))
                    + o[3] * sin(2 * .pi * Float(ops[3].phase))) * 0.4
            }
            buf[i] += out * vol * vel * 0.35
            t += Float(1 / SR)
            if t > dur + 1 && !alive { sounding = false; break }
        }
    }
}

// MARK: - Sega Master System SN76489

/// PSG-канал: чистый квадрат 50% + громкость.
final class PSGSquare: ChipVoiceType {
    var on = true
    var vol: Float = 12
    var vibrato: Float = 0
    private var phase = 0.0
    private var freq = 440.0
    private var t = 0.0
    private var dur = 0.0
    private var vel: Float = 1
    private var sounding = false

    func noteOn(midi: Int, dur: Float, vel: Float) {
        freq = mtof(midi)
        self.dur = Double(dur)
        self.vel = vel
        t = 0
        phase = 0
        sounding = true
    }

    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard on, sounding else { return }
        for i in 0..<n {
            if t > dur { sounding = false; break }
            var f = freq
            if vibrato > 0 {
                f *= 1 + Double(vibrato) * 0.02 * sin(2 * .pi * 7 * t)
            }
            phase += f / SR
            if phase >= 1 { phase -= 1 }
            buf[i] += (phase < 0.5 ? 1 : -1) * (vol / 15) * vel * 0.2
            t += 1 / SR
        }
    }
}

/// PSG-шум: LFSR 15-бит, 3 скорости + привязка к каналу 3.
final class PSGNoise: ChipVoiceType {
    var on = true
    var vol: Float = 12
    private var lfsr: UInt16 = 0x4000
    private var clk = 0.0
    private var clkRate = 3000.0
    private var held: Float = 0
    private var t = 0.0
    private var dur = 0.0
    private var vel: Float = 1
    private var sounding = false

    func noteOn(midi: Int, dur: Float, vel: Float) {
        clkRate = 400 * pow(2, Double(midi - 36) / 15)
        lfsr = 0x4000
        t = 0
        self.dur = Double(dur)
        self.vel = vel
        sounding = true
    }

    func render(into buf: UnsafeMutableBufferPointer<Float>, n: Int) {
        guard on, sounding else { return }
        let step = clkRate / SR
        for i in 0..<n {
            if t > dur { sounding = false; break }
            clk += step
            if clk >= 1 {
                clk -= 1
                let bit = (lfsr ^ (lfsr >> 3)) & 1
                lfsr = (lfsr >> 1) | (bit << 14)
                held = (lfsr & 1) == 0 ? 1 : -1
            }
            buf[i] += held * (vol / 15) * vel * 0.18
            t += 1 / SR
        }
    }
}
