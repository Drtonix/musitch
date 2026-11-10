/// musitch — пиано-ролл v2: как в нормальном софте.
/// Клик по пустому — поставить ноту (драг вправо — длина), клик по ноте —
/// удалить, драг по ноте — перенести, драг за правый край — растянуть.
/// Каналы чипов переключаются вкладками, октавы — кнопками.
import SwiftUI

private let noteNames = ["C", "C#", "D", "D#", "E", "F",
                         "F#", "G", "G#", "A", "A#", "B"]

struct PianoRollView: View {
    let engine: Engine
    @State private var channel = 0
    @State private var octave = 1        // базовая: C(2+octave)
    @State private var tick = 0
    @State private var gridW: CGFloat = 480
    private let timer = Timer.publish(every: 0.05, on: .main,
                                      in: .common).autoconnect()

    private var cellW: CGFloat { (gridW - labelW) / 16 }
    private let rowH: CGFloat = 17
    private let rows = 24                // две октавы на экране
    private let labelW: CGFloat = 44

    private var ch: Channel { engine.seq.channels[channel] }
    private var topMidi: Int { 36 + 12 * octave + rows - 1 }

    /// подогнать октаву под ноты текущего канала
    private func fitOctave() {
        let ns = ch.notes
        guard !ns.isEmpty else { return }
        let avg = ns.reduce(0) { $0 + $1.midi } / ns.count
        let o = Int((Double(avg) - 47.5) / 12.0)
        octave = max(0, min(3, o))
    }

    /// если все ноты канала вне видимого диапазона — перестроить октаву
    private func autoFit() {
        let ns = ch.notes
        guard !ns.isEmpty else { return }
        let lo = 36 + 12 * octave
        let hi = lo + rows - 1
        if !ns.contains(where: { $0.midi >= lo && $0.midi <= hi }) {
            fitOctave()
        }
    }

    // режим драга
    private enum Mode {
        case none, create(Int), move(Int, CGPoint), resize(Int)
    }
    @State private var mode = Mode.none

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                // вкладки каналов + управление
                HStack(spacing: 4) {
                    Text("ТРЕКИ")
                        .font(monoFont(11, .regular))
                        .tracking(3)
                        .foregroundStyle(Color.muted)
                    Spacer()
                    ForEach(Array(engine.seq.channels.enumerated()),
                            id: \.offset) { i, c in
                        Button { channel = i; fitOctave() } label: {
                            Text(c.name)
                                .font(monoFont(9, i == channel ? .bold
                                              : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(i == channel ? Color.txt
                                            : Color.clear)
                                .foregroundStyle(i == channel ? Color.bg
                                                 : (c.muted ? Color.ledR
                                                    : Color.txt))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 10) {
                    Text("OCT")
                        .font(monoFont(9, .regular))
                        .foregroundStyle(Color.muted)
                    Button { octave = max(0, octave - 1) } label: {
                        Text("◀").font(monoFont(11, .regular))
                    }.buttonStyle(OptionButton())
                    Text("\(noteNames[(36 + 12 * octave) % 12])\((36 + 12 * octave) / 12 - 1) – \(noteNames[(59 + 12 * octave) % 12])\((59 + 12 * octave) / 12 - 1)")
                        .font(monoFont(9, .regular))
                        .foregroundStyle(Color.muted)
                    Button { octave = min(3, octave + 1) } label: {
                        Text("▶").font(monoFont(11, .regular))
                    }.buttonStyle(OptionButton())
                    Spacer()
                    StateLed(on: !ch.muted)
                    Button { ch.muted.toggle() } label: {
                        Text(ch.muted ? "UNMUTE" : "MUTE")
                    }
                    .buttonStyle(TransportButton(active: ch.muted,
                                                 color: .ledR))
                    Button { ch.notes.removeAll() } label: { Text("ОЧИСТИТЬ") }
                        .buttonStyle(OptionButton())
                }

                // сетка на всю ширину
                GeometryReader { geo in
                    Canvas { ctx, size in
                        _ = tick
                        draw(ctx: ctx)
                    }
                    .contentShape(Rectangle())
                    .onReceive(timer) { _ in tick &+= 1; autoFit() }
                    .gesture(dragGesture)
                    .onAppear { gridW = geo.size.width; fitOctave() }
                    .onChange(of: geo.size.width) { w in gridW = w }
                }
                .frame(height: CGFloat(rows) * rowH + 2)
            }
        }
    }

    // ---------------------------------------------------------- рисование

    private func noteColor() -> Color { Color.txt }

    private func draw(ctx: GraphicsContext) {
        var ctx = ctx
        let cur = engine.seq.currentStep
        let w = labelW + 16 * cellW

        // фон строк: «чёрные» клавиши темнее, C — с полосой
        for r in 0..<rows {
            let midi = topMidi - r
            let pc = midi % 12
            let y = CGFloat(r) * rowH
            let rect = CGRect(x: labelW, y: y, width: w - labelW,
                              height: rowH)
            let isBlack = [1, 3, 6, 8, 10].contains(pc)
            ctx.fill(Path(rect),
                     with: .color(Color(white: isBlack ? 0.055 : 0.085)))
            if pc == 0 {
                ctx.fill(Path(rect), with: .color(.white.opacity(0.04)))
            }
            if pc == 0 || rows <= 14 {
                let t = Text("\(noteNames[pc])\(midi / 12 - 1)")
                    .font(monoFont(8, .regular))
                    .foregroundColor(pc == 0 ? .txt : .muted)
                ctx.draw(t, at: CGPoint(x: 22, y: y + rowH / 2))
            }
        }
        // вертикали шагов: доли сильнее
        for s in 0...16 {
            let x = labelW + CGFloat(s) * cellW
            var p = Path()
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: CGFloat(rows) * rowH))
            ctx.stroke(p,
                       with: .color(.white.opacity(s % 4 == 0 ? 0.22 : 0.09)),
                       lineWidth: 1)
        }
        // текущий шаг
        if cur >= 0 {
            let rect = CGRect(x: labelW + CGFloat(cur) * cellW, y: 0,
                              width: cellW, height: CGFloat(rows) * rowH)
            ctx.fill(Path(rect), with: .color(.white.opacity(0.10)))
            ctx.stroke(Path(rect),
                       with: .color(.white.opacity(0.5)), lineWidth: 1)
        }
        // ноты
        for note in ch.notes {
            let row = topMidi - note.midi
            guard (0..<rows).contains(row) else { continue }
            let rect = CGRect(x: labelW + CGFloat(note.step) * cellW + 1,
                              y: CGFloat(row) * rowH + 1,
                              width: CGFloat(note.len) * cellW - 3,
                              height: rowH - 2)
            let path = Path(roundedRect: rect, cornerRadius: 2)
            let onCur = cur >= note.step && cur < note.step + note.len
            ctx.fill(path, with: .color(onCur ? Color.ledG : noteColor()))
            // край для ресайза
            let edge = CGRect(x: rect.maxX - 4, y: rect.minY,
                              width: 3, height: rect.height)
            ctx.fill(Path(edge), with: .color(Color.bg.opacity(0.6)))
        }
        // рамка
        let border = CGRect(x: labelW, y: 0, width: w - labelW,
                            height: CGFloat(rows) * rowH)
        ctx.stroke(Path(border), with: .color(Color.line), lineWidth: 1)
    }

    // ---------------------------------------------------------- жесты

    private func pointToCell(_ p: CGPoint) -> (Int, Int) {
        let s = Int((p.x - labelW) / cellW)
        let r = Int(p.y / rowH)
        return (s, r)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let (s0, r0) = pointToCell(v.startLocation)
                let (s, r) = pointToCell(v.location)
                guard (0..<rows).contains(r0) else { return }
                let midi0 = topMidi - r0
                switch mode {
                case .none:
                    guard (0..<16).contains(s0) else { return }
                    if let idx = ch.covering(step: s0, midi: midi0) {
                        // правый край — ресайз, иначе перенос
                        let note = ch.notes[idx]
                        let edgeX = labelW + CGFloat(note.step + note.len)
                            * cellW
                        if abs(v.startLocation.x - (edgeX - 3)) < 7 {
                            mode = .resize(idx)
                        } else {
                            mode = .move(idx, v.startLocation)
                        }
                    } else {
                        var note = Note(step: s0, midi: midi0, len: 1)
                        note.vel = 100
                        ch.notes.append(note)
                        ch.voice.noteOn(midi: midi0, dur: 0.3, vel: 0.8)
                        mode = .create(ch.notes.count - 1)
                    }
                case .create(let idx):
                    guard ch.notes.indices.contains(idx) else { return }
                    let st = ch.notes[idx].step
                    ch.notes[idx].len = max(1, min(s, 15) - st + 1)
                case .resize(let idx):
                    guard ch.notes.indices.contains(idx) else { return }
                    let st = ch.notes[idx].step
                    ch.notes[idx].len = max(1, min(s, 15) - st + 1)
                case .move(let idx, let start):
                    guard ch.notes.indices.contains(idx) else { return }
                    let dStep = Int((v.location.x - start.x) / cellW)
                    let dRow = Int((v.location.y - start.y) / rowH)
                    let (ss, sr) = pointToCell(start)
                    let baseMidi = topMidi - sr
                    var ns = ss + dStep
                    ns = max(0, min(16 - ch.notes[idx].len, ns))
                    ch.notes[idx].step = ns
                    ch.notes[idx].midi = baseMidi - dRow
                }
            }
            .onEnded { v in
                // чистый клик по существующей ноте — удалить
                if case .move(let idx, _) = mode,
                   abs(v.translation.width) < 3,
                   abs(v.translation.height) < 3 {
                    if ch.notes.indices.contains(idx) {
                        ch.notes.remove(at: idx)
                    }
                }
                mode = .none
            }
    }
}
