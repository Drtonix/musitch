/// musitch — станция чиптюна и глитча: эмуляторы GB/NES/Genesis/SMS,
/// пиано-ролл на 14 каналов, сэмплер, текстуры, FX, запись.
import SwiftUI

@main
struct MusitchApp: App {
    @StateObject private var engine = Engine()

    var body: some Scene {
        WindowGroup("musitch") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 1180, minHeight: 960)
                .background(Color.bg)
        }
    }
}

/// демо-рифф для MUSITCH_DEMO / MUSITCH_RENDER
func loadDemoSong(_ e: Engine) {
    let ch = e.seq.channels
    ch[0].notes = [Note(step: 0, midi: 72, len: 2), Note(step: 4, midi: 76, len: 2),
                   Note(step: 8, midi: 79, len: 2), Note(step: 12, midi: 76, len: 2),
                   Note(step: 14, midi: 74, len: 2)]
    ch[2].notes = [Note(step: 0, midi: 36, len: 4), Note(step: 4, midi: 43, len: 4),
                   Note(step: 8, midi: 41, len: 4), Note(step: 12, midi: 43, len: 4)]
    ch[6].notes = [Note(step: 0, midi: 48, len: 3), Note(step: 8, midi: 45, len: 3)]
    ch[7].notes = [Note(step: 4, midi: 84, len: 1), Note(step: 12, midi: 84, len: 1)]
    ch[8].notes = [Note(step: 2, midi: 69, len: 2), Note(step: 10, midi: 67, len: 2)]
    ch[10].notes = [Note(step: 0, midi: 60, len: 1), Note(step: 2, midi: 64, len: 1),
                    Note(step: 4, midi: 67, len: 1), Note(step: 6, midi: 71, len: 1),
                    Note(step: 8, midi: 72, len: 1)]
}

struct ContentView: View {
    @EnvironmentObject var engine: Engine
    @State private var status = "нажми ▶ PLAY — транспорт всего звука"
    @State private var stutterHeld = false
    @State private var texOpen = false

    private let texParams: [String: (String, String)] = [
        "NOISE": ("TONE", "—"), "BUZZ": ("HUM", "SPARK"),
        "GLITCH": ("DENSITY", "REPEAT"), "TAPE": ("WEAR", "WOW"),
        "TV": ("RATE", "PITCH"), "DRIVE": ("DRIVE", "NOTE"),
        "SUB": ("FREQ", "BEAT"),
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

                HStack(spacing: 10) {
                    GBPanel(e: engine)
                    NESPanel(e: engine)
                }
                HStack(spacing: 10) {
                    GENPanel(e: engine)
                    SMSPanel(e: engine)
                }

                PianoRollView(engine: engine)
                SamplerPanel(sampler: engine.sampler)
                fxPanel

                DisclosureGroup(isExpanded: $texOpen) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(),
                                                                 spacing: 8),
                                             count: 4), spacing: 8) {
                        ForEach(Array(engine.textures.enumerated()),
                                id: \.offset) { _, src in
                            let names = texParams[src.title] ?? ("P1", "P2")
                            TextureView(src: src,
                                        p1name: names.0, p2name: names.1)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("ТЕКСТУРЫ (NOISE · BUZZ · GLITCH · TAPE · TV · DRIVE · SUB)")
                        .font(monoFont(11, .regular))
                        .tracking(3)
                        .foregroundStyle(Color.muted)
                }
                .tint(Color.muted)

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
            let env = ProcessInfo.processInfo.environment
            if let path = env["MUSITCH_RENDER"] {
                loadDemoSong(engine)
                engine.playing = true
                let audio = engine.renderOffline(6)
                try? Exporter.writeWav(audio,
                                       to: URL(fileURLWithPath: path))
                print("rendered:", path)
                exit(0)
            }
            if env["MUSITCH_DEMO"] == "1" {
                loadDemoSong(engine)
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
                Text("GB · NES · GENESIS · SMS · SAMPLER")
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
            HStack(spacing: 14) {
                Text("FX")
                    .font(monoFont(11, .regular))
                    .tracking(3)
                    .foregroundStyle(Color.muted)
                Knob(label: "CRUSH", value: Binding(
                    get: { Double(engine.fx.crush) },
                    set: { engine.fx.crush = Float($0) }))
                Knob(label: "DIST", value: Binding(
                    get: { Double(engine.fx.dist) },
                    set: { engine.fx.dist = Float($0) }))
                Knob(label: "CUTOFF", value: Binding(
                    get: { Double(engine.fx.cutoff) },
                    set: { engine.fx.cutoff = Float($0) }))
                Knob(label: "RESO", value: Binding(
                    get: { Double(engine.fx.reso) },
                    set: { engine.fx.reso = Float($0) }))
                Knob(label: "V·SPEED", value: Binding(
                    get: { Double(engine.fx.varispeed) },
                    set: { engine.fx.varispeed = Float($0) }),
                     range: -1...1, format: "%+.2f")
                Knob(label: "DLY·MIX", value: Binding(
                    get: { Double(engine.fx.delayMix) },
                    set: { engine.fx.delayMix = Float($0) }))
                Knob(label: "DLY·TIME", value: Binding(
                    get: { Double(engine.fx.delayTime) },
                    set: { engine.fx.delayTime = Float($0) }),
                     range: 0.05...1.2, format: "%.2f")
                Knob(label: "DLY·F/B", value: Binding(
                    get: { Double(engine.fx.delayFb) },
                    set: { engine.fx.delayFb = Float($0) }))
                VStack(spacing: 2) {
                    Text("STUTTER")
                        .font(monoFont(9, .regular))
                        .foregroundStyle(Color.muted)
                    Button(action: {}) { Text("◼ ДЕРЖИ") }
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
                }
                Spacer()
                Knob(label: "MASTER", value: Binding(
                    get: { Double(engine.master) },
                    set: { engine.master = Float($0) }), size: 44)
            }
        }
    }
}
