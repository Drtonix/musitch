/// musitch — общие UI-элементы: палитра, LED, кнопки, ручки (knob).
/// Семантика цвета: зелёный = вкл, красный = выкл/запись, синий = опции.
/// Все регуляторы — ручки с вертикальным драгом (ползунки убраны: глючили).
import SwiftUI

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

// MARK: - Светодиоды

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

struct StateLed: View {
    var on: Bool
    var size: CGFloat = 8

    var body: some View {
        Led(color: on ? .ledG : .ledR, lit: true, size: size)
    }
}

// MARK: - Кнопки

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

struct OptionButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(monoFont(12, .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Color.ledB)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(Color.ledB.opacity(0.55), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Панель

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

// MARK: - Ручка (вертикальный драг, всегда работает)

struct Knob: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil
    var format: String = "%.2f"
    var size: CGFloat = 34
    var showValue = true
    @State private var dragBase: Double? = nil

    private var norm: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(monoFont(9, .regular))
                .foregroundStyle(Color.muted)
            Canvas { ctx, canvasSize in
                let d = min(canvasSize.width, canvasSize.height) - 4
                let c = CGPoint(x: canvasSize.width / 2,
                                y: canvasSize.height / 2)
                let r = d / 2
                var arc = Path()
                arc.addArc(center: c, radius: r,
                           startAngle: .degrees(135),
                           endAngle: .degrees(405), clockwise: false)
                ctx.stroke(arc, with: .color(Color(white: 0.22)),
                           lineWidth: 2.5)
                var act = Path()
                act.addArc(center: c, radius: r,
                           startAngle: .degrees(135),
                           endAngle: .degrees(135 + 270 * norm),
                           clockwise: false)
                ctx.stroke(act, with: .color(Color.txt), lineWidth: 2.5)
                let ang = (135 + 270 * norm) * .pi / 180
                var tickMark = Path()
                tickMark.move(to: CGPoint(x: c.x + cos(ang) * r * 0.45,
                                          y: c.y + sin(ang) * r * 0.45))
                tickMark.addLine(to: CGPoint(x: c.x + cos(ang) * r * 0.92,
                                             y: c.y + sin(ang) * r * 0.92))
                ctx.stroke(tickMark, with: .color(Color.txt), lineWidth: 2)
            }
            .frame(width: size, height: size)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let base = dragBase ?? value
                    if dragBase == nil { dragBase = value }
                    let span = range.upperBound - range.lowerBound
                    var nv = base + Double(-v.translation.height) / 120 * span
                    nv = min(max(nv, range.lowerBound), range.upperBound)
                    if let step {
                        nv = (nv / step).rounded() * step
                        nv = min(max(nv, range.lowerBound),
                                 range.upperBound)
                    }
                    value = nv
                }
                .onEnded { _ in dragBase = nil })
            if showValue {
                Text(String(format: format, value))
                    .font(monoFont(8, .regular))
                    .foregroundStyle(Color.muted)
            }
        }
    }
}

// MARK: - Модуль текстуры (ручки вместо слайдеров)

struct TextureView: View {
    @ObservedObject var src: Source
    var p1name: String
    var p2name: String

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(src.title)
                        .font(monoFont(11, .bold))
                        .tracking(2)
                    Spacer()
                    StateLed(on: src.on)
                    Button { src.on.toggle() } label: {
                        Text(src.on ? "ON" : "OFF").frame(width: 34)
                    }
                    .buttonStyle(TransportButton(active: src.on,
                                                 color: .ledG))
                }
                HStack(spacing: 14) {
                    Knob(label: p1name, value: Binding(
                        get: { Double(src.p1) },
                        set: { src.p1 = Float($0) }), showValue: false)
                    if p2name != "—" {
                        Knob(label: p2name, value: Binding(
                            get: { Double(src.p2) },
                            set: { src.p2 = Float($0) }), showValue: false)
                    }
                    Spacer()
                }
            }
        }
    }
}
