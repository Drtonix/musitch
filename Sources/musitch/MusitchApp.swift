/// musitch — ретровейв-станция для глитча и экспериментального звука.
/// Точка входа + главный экран.
import SwiftUI

@main
struct MusitchApp: App {
    @StateObject private var engine = Engine()

    var body: some Scene {
        WindowGroup("musitch") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 1120, minHeight: 940)
                .background(Color.bg)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var engine: Engine
    @State private var status = "нажми ▶ PLAY — это общий транспорт всего звука"
    @State private var stutterHeld = false

    private let paramNames: [String: (String, String)] = [
        "NOISE": ("TONE", "—"), "BUZZ": ("HUM", "SPARK"),
        "GLITCH": ("DENSITY", "REPEAT"), "TAPE": ("WEAR", "WOW"),
        "TV": ("RATE", "PITCH"), "DRIVE": ("DRIVE", "NOTE"),
        "SUB": ("FREQ", "BEAT"), "CHIP": ("DUTY", "VIB"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header

                HStack(spacing: 10) {
                    ScopeView(engine: engine)
                    SpectrumView(engine: engine)
                }
                .frame(height: 140)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(),
                                                             spacing: 8),
                                         count: 4), spacing: 8) {
                    ForEach(Array(engine.sources.enumerated()),
                            id: \.offset) { _, src in
                        let names = paramNames[src.title] ?? ("P1", "P2")
                        ModuleView(src: src,
                                   p1name: names.0, p2name: names.1)
                    }
                }

                SamplerPanel(sampler: engine.sampler)

                fxPanel
                seqPanel

                HStack {
                    Text(status)
                        .font(monoFont(10, .regular))
                        .foregroundStyle(Color.muted)
                    Spacer()
                }
            }
            .padding(14)
        }
        .background(Color.bg)
        .task {
            // скрытый демо-режим для автопроверки: MUSITCH_DEMO=1
            if ProcessInfo.processInfo.environment["MUSITCH_DEMO"] == "1" {
                engine.sources.first { $0.title == "NOISE" }?.on = true
                engine.sources.first { $0.title == "DRIVE" }?.on = true
                engine.seq.toggle(0, 72)
                engine.seq.toggle(4, 67)
                engine.seq.toggle(8, 64)
                engine.seq.toggle(12, 60)
                engine.playing = true
            }
        }
    }

    // ---------------------------------------------------------- шапка

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("MUSITCH")
                    .font(monoFont(20, .bold))
                    .tracking(4)
                Text("GLITCH · TAPE · 8BIT · NOISE")
                    .font(monoFont(10, .regular))
                    .tracking(2)
                    .foregroundStyle(Color.muted)
            }
            Spacer()
            StateLed(on: engine.playing, size: 10)
            Button { engine.playing.toggle() } label: {
                Text(engine.playing ? "■ STOP" : "▶ PLAY")
            }
            .buttonStyle(TransportButton(active: engine.playing,
                                         color: .ledG))
            Led(color: .ledR, lit: engine.recording, size: 10)
            Button { engine.recording.toggle() } label: {
                Text(engine.recording ? "■ STOP" : "● REC")
            }
            .buttonStyle(TransportButton(active: engine.recording,
                                         color: .ledR))
            Text("BPM")
                .font(monoFont(10, .regular))
                .foregroundStyle(Color.muted)
            Stepper(value: $engine.bpm, in: 40...300, step: 1) {
                Text("\(Int(engine.bpm))")
                    .font(monoFont(12, .regular))
                    .frame(width: 34, alignment: .trailing)
            }
            Button {
                Exporter.export(engine: engine) { status = $0 }
            } label: {
                Text("⤓ ЭКСПОРТ")
            }
            .buttonStyle(OptionButton())
        }
    }

    // ---------------------------------------------------------- FX

    private var fxPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text("FX")
                        .font(monoFont(11, .regular))
                        .tracking(3)
                        .foregroundStyle(Color.muted)
                    FXSlider(label: "BITCRUSH", value: Binding(
                        get: { Double(engine.fx.crush) },
                        set: { engine.fx.crush = Float($0) }))
                    FXSlider(label: "DISTORT", value: Binding(
                        get: { Double(engine.fx.dist) },
                        set: { engine.fx.dist = Float($0) }))
                    FXSlider(label: "CUTOFF", value: Binding(
                        get: { Double(engine.fx.cutoff) },
                        set: { engine.fx.cutoff = Float($0) }))
                    FXSlider(label: "RESO", value: Binding(
                        get: { Double(engine.fx.reso) },
                        set: { engine.fx.reso = Float($0) }))
                    FXSlider(label: "VARISPEED", value: Binding(
                        get: { Double(engine.fx.varispeed) },
                        set: { engine.fx.varispeed = Float($0) }),
                             range: -1...1, format: "%+.2f")
                    Spacer()
                    Text("MASTER")
                        .font(monoFont(10, .regular))
                        .foregroundStyle(Color.muted)
                    Slider(value: Binding(
                        get: { Double(engine.master) },
                        set: { engine.master = Float($0) }))
                    .tint(Color.txt)
                    .controlSize(.small)
                    .frame(width: 110)
                }
                HStack(spacing: 16) {
                    FXSlider(label: "DELAY MIX", value: Binding(
                        get: { Double(engine.fx.delayMix) },
                        set: { engine.fx.delayMix = Float($0) }))
                    FXSlider(label: "DELAY TIME", value: Binding(
                        get: { Double(engine.fx.delayTime) },
                        set: { engine.fx.delayTime = Float($0) }),
                             range: 0.05...1.2, format: "%.2f s")
                    FXSlider(label: "DELAY F/B", value: Binding(
                        get: { Double(engine.fx.delayFb) },
                        set: { engine.fx.delayFb = Float($0) }))
                    VStack(spacing: 3) {
                        Text("STUTTER")
                            .font(monoFont(10, .regular))
                            .foregroundStyle(Color.muted)
                        Button(action: {}) {
                            Text("◼ ДЕРЖИ")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(TransportButton(active: stutterHeld,
                                                     color: .ledB))
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    stutterHeld = true
                                    engine.fx.stutter = true
                                }
                                .onEnded { _ in
                                    stutterHeld = false
                                    engine.fx.stutter = false
                                })
                        Text("холд")
                            .font(monoFont(9, .regular))
                            .foregroundStyle(Color.muted)
                    }
                    Spacer()
                }
            }
        }
    }

    // ---------------------------------------------------------- секвенсор

    private var seqPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("8-BIT СЕКВЕНСОР — CHIP")
                    .font(monoFont(11, .regular))
                    .tracking(3)
                    .foregroundStyle(Color.muted)
                HStack {
                    Spacer()
                    SeqGridView(engine: engine)
                    Spacer()
                }
            }
        }
    }
}

struct FXSlider: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var format: String = "%.2f"

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(monoFont(10, .regular))
                .foregroundStyle(Color.muted)
            Slider(value: $value, in: range)
                .tint(Color.txt)
                .controlSize(.small)
                .frame(width: 130)
            Text(String(format: format, value))
                .font(monoFont(9, .regular))
                .foregroundStyle(Color.muted)
        }
    }
}
