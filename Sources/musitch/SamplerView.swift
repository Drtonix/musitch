/// musitch — панель сэмплера: загрузка своих звуков, волна с выделением
/// фрагмента, реверс/нормализация, питч по полутонам, скорость, закрутка.
import SwiftUI
import UniformTypeIdentifiers

struct SamplerPanel: View {
    @ObservedObject var sampler: SamplerSrc
    @State private var dragFrom: CGFloat? = nil
    @State private var dropHover = false
    @State private var waveTick = 0
    private let waveTimer = Timer.publish(every: 0.1, on: .main,
                                          in: .common).autoconnect()

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                // заголовок + транспорт сэмплера
                HStack(spacing: 10) {
                    Text("СЭМПЛЕР")
                        .font(monoFont(11, .regular))
                        .tracking(3)
                        .foregroundStyle(Color.muted)
                    Text(sampler.name)
                        .font(monoFont(11, .bold))
                        .lineLimit(1)
                    if sampler.loaded {
                        Text(String(format: "%.2f s", sampler.duration))
                            .font(monoFont(10, .regular))
                            .foregroundStyle(Color.muted)
                    }
                    Spacer()
                    StateLed(on: sampler.loaded)
                    Button { openFile() } label: { Text("ЗАГРУЗИТЬ") }
                        .buttonStyle(OptionButton())
                    Button { sampler.reverseSelection() } label: { Text("REV") }
                        .buttonStyle(OptionButton())
                        .disabled(!sampler.loaded)
                    Button { sampler.normalizeSelection() } label: { Text("NORM") }
                        .buttonStyle(OptionButton())
                        .disabled(!sampler.loaded)
                    Button {
                        sampler.loop.toggle()
                    } label: { Text("LOOP") }
                        .buttonStyle(TransportButton(active: sampler.loop,
                                                     color: .ledG))
                        .disabled(!sampler.loaded)
                    Button {
                        sampler.on = true
                        sampler.trigger()
                    } label: { Text("▶ ИГРАТЬ") }
                    .buttonStyle(TransportButton(active: false, color: .ledG))
                    .disabled(!sampler.loaded)
                }

                // волна с выделением
                GeometryReader { geo in
                    Canvas { ctx, size in
                        _ = waveTick
                        drawWave(&ctx, size: size)
                    }
                    .contentShape(Rectangle())
                    .onReceive(waveTimer) { _ in waveTick &+= 1 }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard sampler.loaded else { return }
                            let w = geo.size.width
                            let from = dragFrom ?? v.startLocation.x
                            dragFrom = from
                            let n = sampler.data.count
                            let a = Int(min(max(from / w, 0), 1) * CGFloat(n))
                            let b = Int(min(max(v.location.x / w, 0), 1)
                                * CGFloat(n))
                            sampler.selStart = min(a, b)
                            sampler.selEnd = max(max(a, b),
                                                 sampler.selStart + 256)
                        }
                        .onEnded { _ in dragFrom = nil })
                    .onDrop(of: [.fileURL], isTargeted: $dropHover) { providers in
                        guard let p = providers.first else { return false }
                        _ = p.loadObject(ofClass: URL.self) { url, _ in
                            guard let url else { return }
                            try? sampler.load(url)
                        }
                        return true
                    }
                }
                .frame(height: 76)

                // параметры — ручки, как у остального железа
                HStack(spacing: 18) {
                    Knob(label: "PITCH",
                         value: Binding(
                             get: { Double(sampler.pitchSemis) },
                             set: { sampler.pitchSemis = Int($0) }),
                         range: -24...24, step: 1, format: "%+.0f st")
                    Knob(label: "SPEED",
                         value: Binding(
                             get: { Double(sampler.speed) },
                             set: { sampler.speed = Float($0) }),
                         range: 0.25...4, format: "%.2f×")
                    Knob(label: "TWIST",
                         value: Binding(
                             get: { Double(sampler.twist) },
                             set: { sampler.twist = Float($0) }),
                         range: -1...1, format: "%+.2f")
                    Knob(label: "DRIVE",
                         value: Binding(
                             get: { Double(sampler.drive) },
                             set: { sampler.drive = Float($0) }),
                         range: 0...1, format: "%.2f")
                    Spacer()
                }
            }
        }
    }

    private func drawWave(_ ctx: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .color(Color(white: 0.04)))
        let d = sampler.data
        if d.isEmpty {
            let hint = Text(dropHover
                            ? "ОТПУСКАЙ — ЗАГРУЖУ"
                            : "ПЕРЕТАЩИ АУДИОФАЙЛ ИЛИ НАЖМИ «ЗАГРУЗИТЬ»")
                .font(monoFont(10, .regular))
                .foregroundColor(dropHover ? .ledB : .muted)
            ctx.draw(hint, at: CGPoint(x: size.width / 2,
                                       y: size.height / 2))
        } else {
            // волна: min/max столбики
            let w = Int(size.width)
            let n = d.count
            var path = Path()
            for x in 0..<w {
                let a = x * n / w
                let b = max((x + 1) * n / w, a + 1)
                var lo: Float = 1, hi: Float = -1
                var i = a
                while i < b && i < n {
                    lo = min(lo, d[i])
                    hi = max(hi, d[i])
                    i += 1
                }
                let y0 = size.height / 2 - CGFloat(hi) * size.height * 0.45
                let y1 = size.height / 2 - CGFloat(lo) * size.height * 0.45
                path.move(to: CGPoint(x: CGFloat(x), y: y0))
                path.addLine(to: CGPoint(x: CGFloat(x), y: max(y1, y0 + 0.5)))
            }
            ctx.stroke(path, with: .color(Color.txt.opacity(0.85)),
                       lineWidth: 1)

            // выделение
            let x0 = size.width * CGFloat(sampler.selStart) / CGFloat(n)
            let x1 = size.width * CGFloat(sampler.selEnd) / CGFloat(n)
            let sel = CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)
            ctx.fill(Path(sel), with: .color(.white.opacity(0.12)))
            ctx.stroke(Path(sel), with: .color(Color.ledB.opacity(0.7)),
                       lineWidth: 1)

            // плейхед
            if sampler.playPos >= 0 {
                let px = size.width * CGFloat(sampler.playPos) / CGFloat(n)
                var pl = Path()
                pl.move(to: CGPoint(x: px, y: 0))
                pl.addLine(to: CGPoint(x: px, y: size.height))
                ctx.stroke(pl, with: .color(Color.ledG), lineWidth: 1)
            }
        }
        ctx.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                   with: .color(dropHover ? Color.ledB : Color.line),
                   lineWidth: 1)
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? sampler.load(url)
        }
    }
}

