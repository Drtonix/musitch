/// musitch — сэмплер: загрузка аудио, выделение фрагмента, реверс,
/// нормализация, питч/скорость/закрутка/перегруз при воспроизведении.
import AVFoundation

final class SamplerSrc: Source {
    @Published private(set) var name = ""
    @Published private(set) var loaded = false
    @Published var loop = false
    var data: [Float] = []
    var selStart = 0
    var selEnd = 0
    var pitchSemis: Int = 0
    var speed: Float = 1
    var twist: Float = 0   // закрутка: воббуляция скорости чтения
    var drive: Float = 0
    private(set) var playPos: Float = -1  // -1 = не играет
    private var wobPh: Float = 0

    var duration: Double { Double(data.count) / SR }

    override init(_ title: String) { super.init(title) }

    // MARK: загрузка (любой формат, который понимает AVAudioFile)

    func load(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(standardFormatWithSampleRate: SR,
                                         channels: 1),
              let conv = AVAudioConverter(from: file.processingFormat,
                                          to: target) else {
            throw NSError(domain: "musitch", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                                     "не могу сконвертировать файл"])
        }
        let ratio = SR / file.processingFormat.sampleRate
        let cap = AVAudioFrameCount(Double(file.length) * ratio + 256)
        guard let out = AVAudioPCMBuffer(pcmFormat: target,
                                         frameCapacity: cap) else {
            throw NSError(domain: "musitch", code: 2, userInfo: nil)
        }
        var error: NSError?
        let block: AVAudioConverterInputBlock = { _, status in
            if file.framePosition >= file.length {
                status.pointee = .endOfStream
                return nil
            }
            let left = min(file.length - file.framePosition, 1 << 20)
            guard let inBuf = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(left)) else {
                status.pointee = .endOfStream
                return nil
            }
            do { try file.read(into: inBuf) } catch {
                status.pointee = .endOfStream
                return nil
            }
            if inBuf.frameLength == 0 {
                status.pointee = .endOfStream
                return nil
            }
            status.pointee = .haveData
            return inBuf
        }
        let st = conv.convert(to: out, error: &error,
                              withInputFrom: block)
        if let error { throw error }
        guard st != .error, let chan = out.floatChannelData else {
            throw NSError(domain: "musitch", code: 3, userInfo: nil)
        }
        let n = Int(out.frameLength)
        data = Array(UnsafeBufferPointer(start: chan[0], count: n))
        selStart = 0
        selEnd = n
        playPos = -1
        name = url.deletingPathExtension().lastPathComponent
        loaded = true
    }

    // MARK: обработка выделенного фрагмента

    private func clampedSel() -> (Int, Int) {
        let a = max(0, min(selStart, data.count))
        let b = max(a + 1, min(selEnd, data.count))
        return (a, b)
    }

    func reverseSelection() {
        guard loaded else { return }
        let (a, b) = clampedSel()
        data[a..<b].reverse()
        objectWillChange.send()
    }

    func normalizeSelection() {
        guard loaded else { return }
        let (a, b) = clampedSel()
        var peak: Float = 0
        for i in a..<b { peak = max(peak, abs(data[i])) }
        guard peak > 1e-6 else { return }
        let g = 0.98 / peak
        for i in a..<b { data[i] *= g }
        objectWillChange.send()
    }

    // MARK: воспроизведение

    func trigger() {
        guard loaded else { return }
        let (a, _) = clampedSel()
        playPos = Float(a)
    }

    override func render(into buf: UnsafeMutableBufferPointer<Float>,
                         n: Int) {
        guard playPos >= 0, !data.isEmpty else {
            for i in 0..<n { buf[i] = 0 }
            return
        }
        let (a, b) = clampedSel()
        let rate0 = speed * powf(2, Float(pitchSemis) / 12)
        let gain = 1 + 9 * drive
        var pos = playPos
        var wp = wobPh
        let sr = Float(SR)
        for i in 0..<n {
            let idx = Int(pos)
            if idx >= b - 1 {
                if loop {
                    pos = Float(a)
                } else {
                    playPos = -1
                    wobPh = wp
                    for j in i..<n { buf[j] = 0 }
                    return
                }
            }
            let i0 = Int(pos)
            let frac = pos - Float(i0)
            let i1 = min(i0 + 1, b - 1)
            let s = data[i0] * (1 - frac) + data[i1] * frac
            buf[i] = tanhf(s * gain) * 0.9
            // закрутка: глубокая воббуляция скорости чтения
            wp += 6.5 / sr
            if wp >= 1 { wp -= 1 }
            let wob = 1 + twist * 0.8 * sinf(2 * .pi * wp)
            pos += max(rate0 * wob, 0.01)
        }
        playPos = pos
        wobPh = wp
    }
}
