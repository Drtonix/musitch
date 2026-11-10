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
                .frame(minWidth: 1120, minHeight: 880)
                .background(Color.bg)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @EnvironmentObject var engine: Engine
    @State private var status = ""

    private let ledColors: [Color] = [.ledG, .ledB, .ledR, .ledG,
                                      .ledB, .ledR, .ledG, .ledB]
    private let paramNames: [String: (String, String)] = [
        "NOISE": ("TONE", "—"), "BUZZ": ("HUM", "SPARK"),
        "GLITCH": ("DENSITY", "REPEAT"), "TAPE": ("WEAR", "WOW"),
        "TV": ("RATE", "PITCH"), "DRIVE": ("DRIVE", "NOTE"),
        "SUB": ("FREQ", "BEAT"), "CHIP": ("DUTY", "VIB"),
    ]

    var body: some View {
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
                        id: \.offset) { i, src in
                    let names = paramNames[src.title] ?? ("P1", "P2")
                    ModuleView(src: src, ledColor: ledColors[i],
                               p1name: names.0, p2name: names.1)
                }
            }

            fxPanel
            seqPanel

            if !status.isEmpty {
                HStack {
                    Text(status)
                        .font(monoFont(10, .regular))
                        .foregroundStyle(Color.muted)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Color.bg)
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
            Led(color: .ledG, lit: engine.playing, size: 10)
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
            .buttonStyle(TransportButton(active: false, color: .txt))
        }
    }

    // ---------------------------------------------------------- FX

    private var fxPanel: some View {
        Panel {
            HStack(spacing: 18) {
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
                FXSlider(label: "DELAY", value: Binding(
                    get: { Double(engine.fx.delay) },
                    set: { engine.fx.delay = Float($0) }))
                FXSlider(label: "FILTER", value: Binding(
                    get: { Double(engine.fx.lp) },
                    set: { engine.fx.lp = Float($0) }))
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

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(monoFont(10, .regular))
                .foregroundStyle(Color.muted)
            Slider(value: $value)
                .tint(Color.txt)
                .controlSize(.small)
                .frame(width: 130)
        }
    }
}
