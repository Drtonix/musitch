/// musitch — панели чипов: Game Boy, NES, Genesis (YM2612 FM), SMS (PSG).
import SwiftUI

private func chipToggle(_ on: Bool, _ voices: [ChipVoiceType]) {
    for v in voices { v.on = on }
}

struct ChipHeader: View {
    let title: String
    let voices: [ChipVoiceType]
    @State private var on = true

    var body: some View {
        HStack {
            Text(title)
                .font(monoFont(11, .bold))
                .tracking(2)
            Spacer()
            StateLed(on: on)
            Button {
                on.toggle()
                chipToggle(on, voices)
            } label: {
                Text(on ? "ON" : "OFF").frame(width: 34)
            }
            .buttonStyle(TransportButton(active: on, color: .ledG))
        }
    }
}

// MARK: - Game Boy

struct GBPanel: View {
    let e: Engine

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                ChipHeader(title: "GAME BOY",
                           voices: [e.gbP1, e.gbP2, e.gbW, e.gbN])
                Text("PULSE 1·2").font(monoFont(9, .regular))
                    .foregroundStyle(Color.muted)
                HStack(spacing: 12) {
                    Knob(label: "DUTY", value: Binding(
                        get: { Double(e.gbP1.duty) },
                        set: { e.gbP1.duty = Int($0); e.gbP2.duty = Int($0) }),
                         range: 0...3, step: 1, format: "%.0f")
                    Knob(label: "VOL", value: Binding(
                        get: { Double(e.gbP1.envVol) },
                        set: { e.gbP1.envVol = Float($0)
                            e.gbP2.envVol = Float($0) }),
                         range: 0...15, step: 1, format: "%.0f")
                    Knob(label: "DECAY", value: Binding(
                        get: { Double(e.gbP1.envDecay) },
                        set: { e.gbP1.envDecay = Float($0)
                            e.gbP2.envDecay = Float($0) }),
                         range: 0...1, format: "%.2f")
                    Knob(label: "SWEEP", value: Binding(
                        get: { Double(e.gbP1.sweep) },
                        set: { e.gbP1.sweep = Float($0) }),
                         range: -1...1, format: "%+.1f")
                }
                Text("WAVE / NOISE").font(monoFont(9, .regular))
                    .foregroundStyle(Color.muted)
                HStack(spacing: 12) {
                    Knob(label: "WAVE", value: Binding(
                        get: { Double(e.gbW.preset) },
                        set: { e.gbW.preset = Int($0); e.gbW.applyPreset() }),
                         range: 0...4, step: 1, format: "%.0f")
                    Knob(label: "W·VOL", value: Binding(
                        get: { Double(e.gbW.vol) },
                        set: { e.gbW.vol = Float($0) }))
                    Knob(label: "N·DECAY", value: Binding(
                        get: { Double(e.gbN.envDecay) },
                        set: { e.gbN.envDecay = Float($0) }),
                         range: 0.02...1)
                    VStack(spacing: 2) {
                        Text("N·MODE").font(monoFont(9, .regular))
                            .foregroundStyle(Color.muted)
                        Button { e.gbN.mode7.toggle() } label: {
                            Text(e.gbN.mode7 ? "7bit" : "15bit")
                                .font(monoFont(9, .regular))
                        }
                        .buttonStyle(TransportButton(active: e.gbN.mode7,
                                                     color: .ledB))
                    }
                }
            }
        }
    }
}

// MARK: - NES

struct NESPanel: View {
    let e: Engine

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                ChipHeader(title: "NES",
                           voices: [e.nesP1, e.nesP2, e.nesT, e.nesN])
                Text("PULSE 1·2").font(monoFont(9, .regular))
                    .foregroundStyle(Color.muted)
                HStack(spacing: 12) {
                    Knob(label: "DUTY", value: Binding(
                        get: { Double(e.nesP1.duty) },
                        set: { e.nesP1.duty = Int($0)
                            e.nesP2.duty = Int($0) }),
                         range: 0...3, step: 1, format: "%.0f")
                    Knob(label: "VOL", value: Binding(
                        get: { Double(e.nesP1.vol) },
                        set: { e.nesP1.vol = Float($0)
                            e.nesP2.vol = Float($0) }),
                         range: 0...15, step: 1, format: "%.0f")
                    Knob(label: "SWEEP", value: Binding(
                        get: { Double(e.nesP1.sweep) },
                        set: { e.nesP1.sweep = Float($0)
                            e.nesP2.sweep = Float($0) }),
                         range: -1...1, format: "%+.1f")
                }
                Text("TRI / NOISE").font(monoFont(9, .regular))
                    .foregroundStyle(Color.muted)
                HStack(spacing: 12) {
                    Knob(label: "T·VOL", value: Binding(
                        get: { Double(e.nesT.vol) },
                        set: { e.nesT.vol = Float($0) }),
                         range: 0...15, step: 1, format: "%.0f")
                    Knob(label: "N·VOL", value: Binding(
                        get: { Double(e.nesN.vol) },
                        set: { e.nesN.vol = Float($0) }),
                         range: 0...15, step: 1, format: "%.0f")
                    Knob(label: "N·DECAY", value: Binding(
                        get: { Double(e.nesN.envDecay) },
                        set: { e.nesN.envDecay = Float($0) }),
                         range: 0.02...1)
                    VStack(spacing: 2) {
                        Text("N·MODE").font(monoFont(9, .regular))
                            .foregroundStyle(Color.muted)
                        Button { e.nesN.tonal.toggle() } label: {
                            Text(e.nesN.tonal ? "TONE" : "WHITE")
                                .font(monoFont(9, .regular))
                        }
                        .buttonStyle(TransportButton(active: e.nesN.tonal,
                                                     color: .ledB))
                    }
                }
            }
        }
    }
}

// MARK: - Genesis YM2612

struct FMRow: View {
    let label: String
    let ch: YMChannel

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(monoFont(9, .regular))
                .foregroundStyle(Color.muted).frame(width: 30,
                                                    alignment: .leading)
            Knob(label: "ALGO", value: Binding(
                get: { Double(ch.algo) },
                set: { ch.algo = Int($0) }),
                 range: 0...7, step: 1, format: "%.0f")
            Knob(label: "FB", value: Binding(
                get: { Double(ch.fb) }, set: { ch.fb = Float($0) }))
            Knob(label: "RATIO", value: Binding(
                get: { Double(ch.modRatio) },
                set: { ch.modRatio = Float($0) }),
                 range: 0.5...8, step: 0.5, format: "%.1f")
            Knob(label: "MOD", value: Binding(
                get: { Double(ch.modLevel) },
                set: { ch.modLevel = Float($0) }))
            Knob(label: "DECAY", value: Binding(
                get: { Double(ch.decay) },
                set: { ch.decay = Float($0) }),
                 range: 0.5...12, step: 0.5, format: "%.1f")
        }
    }
}

struct GENPanel: View {
    let e: Engine

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                ChipHeader(title: "GENESIS FM", voices: [e.fm1, e.fm2])
                FMRow(label: "FM1", ch: e.fm1)
                FMRow(label: "FM2", ch: e.fm2)
            }
        }
    }
}

// MARK: - SMS PSG

struct SMSPanel: View {
    let e: Engine

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                ChipHeader(title: "SMS PSG",
                           voices: [e.psg1, e.psg2, e.psg3, e.psgN])
                Text("SQUARE 1·2·3").font(monoFont(9, .regular))
                    .foregroundStyle(Color.muted)
                HStack(spacing: 12) {
                    Knob(label: "VOL", value: Binding(
                        get: { Double(e.psg1.vol) },
                        set: { e.psg1.vol = Float($0)
                            e.psg2.vol = Float($0)
                            e.psg3.vol = Float($0) }),
                         range: 0...15, step: 1, format: "%.0f")
                    Knob(label: "VIB", value: Binding(
                        get: { Double(e.psg1.vibrato) },
                        set: { e.psg1.vibrato = Float($0)
                            e.psg2.vibrato = Float($0)
                            e.psg3.vibrato = Float($0) }))
                }
                Text("NOISE").font(monoFont(9, .regular))
                    .foregroundStyle(Color.muted)
                HStack(spacing: 12) {
                    Knob(label: "N·VOL", value: Binding(
                        get: { Double(e.psgN.vol) },
                        set: { e.psgN.vol = Float($0) }),
                         range: 0...15, step: 1, format: "%.0f")
                }
            }
        }
    }
}
