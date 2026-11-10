/// musitch — общие UI-элементы: палитра, LED, кнопки, модуль, пиано-ролл.
import SwiftUI

// MARK: - Палитра (ЧБ + LED-акценты)

extension Color {
    static let bg = Color(red: 5 / 255, green: 5 / 255, blue: 5 / 255)
    static let panel = Color(red: 15 / 255, green: 15 / 255, blue: 15 / 255)
    static let line = Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
    static let txt = Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255)
    static let muted = Color(red: 122 / 255, green: 122 / 255, blue: 122 / 255)
    static let ledG = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let ledR = Color(red: 255 / 255, green: 59 / 255, blue: 48 / 255)
    static let ledB = Color(red: 10 / 255, green: 132 / 255, blue: 1)
}

let monoFont: (CGFloat, Font.Weight) -> Font = { size, weight in
    .system(size: size, weight: weight, design: .monospaced)
}

// MARK: - Светодиод

struct Led: View {
    var color: Color
    var lit: Bool
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(lit ? color : Color(white: 0.13))
            .frame(width: size, height: size)
            .shadow(color: lit ? color.opacity(0.9) : .clear, radius: 4)
            .overlay(Circle().stroke(Color(white: 0.2), lineWidth: 0.5))
    }
}

// MARK: - Кнопка-переключатель

struct TransportButton: ButtonStyle {
    var active: Bool
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(monoFont(12, active ? .bold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(active ? color : Color.clear)
            .foregroundStyle(active ? Color.black : Color.txt)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(active ? color : Color.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Панель-модификатор

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(10)
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.line, lineWidth: 1))
    }
}

// MARK: - Строка параметра со слайдером

struct ParamRow: View {
    let name: String
    @Binding var value: Double
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(monoFont(10, .regular))
                .foregroundStyle(Color.muted)
                .frame(width: 56, alignment: .leading)
            Slider(value: $value)
                .tint(Color.txt)
                .controlSize(.small)
                .frame(maxWidth: width)
        }
    }
}

// MARK: - Модуль-источник

struct ModuleView: View {
    @ObservedObject var src: Source
    var ledColor: Color
    var p1name: String
    var p2name: String

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(src.title)
                        .font(monoFont(11, .bold))
                        .tracking(2)
                    Spacer()
                    Led(color: ledColor, lit: src.on)
                    Button { src.on.toggle() } label: {
                        Text(src.on ? "ON" : "OFF")
                            .frame(width: 34)
                    }
                    .buttonStyle(TransportButton(active: src.on,
                                                 color: .txt))
                }
                ParamRow(name: p1name, value: Binding(
                    get: { Double(src.p1) }, set: { src.p1 = Float($0) }))
                if p2name != "—" {
                    ParamRow(name: p2name, value: Binding(
                        get: { Double(src.p2) }, set: { src.p2 = Float($0) }))
                }
            }
        }
    }
}

// MARK: - Пиано-ролл (16 шагов × 13 нот C4..C5)

private let seqNames = ["C5", "B4", "A#4", "A4", "G#4", "G4", "F#4",
                        "F4", "E4", "D#4", "D4", "C#4", "C4"]

private func drawSeqGrid(_ ctx: inout GraphicsContext, size: CGSize,
                         engine: Engine, cell: CGFloat, rows: Int) {
    let cur = engine.seq.currentStep
    let labelFont = monoFont(9, .regular)
    for row in 0..<rows {
        let label = Text(seqNames[row]).font(labelFont)
            .foregroundColor(Color.muted)
        ctx.draw(label, at: CGPoint(x: 20,
                                    y: 3 + CGFloat(row) * cell + cell / 2))
    }
    for s in 0..<engine.seq.steps {
        for row in 0..<rows {
            let x = 56 + CGFloat(s) * cell
            let y = 3 + CGFloat(row) * cell
            let rect = CGRect(x: x, y: y, width: cell - 2, height: cell - 2)
            let path = Path(rect)
            ctx.fill(path, with: .color(Color(white: 0.09)))
            ctx.stroke(path, with: .color(Color(white: 0.2)), lineWidth: 1)
            if s == cur {
                ctx.fill(path, with: .color(.white.opacity(0.07)))
            }
            if engine.seq.contains(s, 72 - row) {
                ctx.fill(Path(rect.insetBy(dx: 2, dy: 2)),
                         with: .color(Color.txt))
            }
        }
    }
}

struct SeqGridView: View {
    let engine: Engine
    let cell: CGFloat = 22
    let rows = 13

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.06)) { _ in
            Canvas { ctx, size in
                var c = ctx
                drawSeqGrid(&c, size: size, engine: engine,
                            cell: cell, rows: rows)
            }
        }
        .frame(width: 56 + 16 * cell, height: 3 + 13 * cell + 3)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { v in
            let s = Int((v.location.x - 56) / cell)
            let row = Int((v.location.y - 3) / cell)
            if (0..<16).contains(s), (0..<13).contains(row) {
                engine.seq.toggle(s, 72 - row)
            }
        })
    }
}
