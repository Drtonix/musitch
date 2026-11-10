/// musitch — экспорт записи: WAV своими руками, mp3/ogg/flac через ffmpeg.
import AppKit
import UniformTypeIdentifiers

enum Exporter {

    /// Снять запись с движка, спросить путь, сохранить.
    /// Результат (или причина отмены) уходит в completion для статус-строки.
    static func export(engine: Engine, completion: @escaping (String) -> Void) {
        let audio = engine.takeRecording()
        guard audio.count > 4410 * 2 else {
            completion("Пусто: нажми ● REC, поиграй, затем ЭКСПОРТ.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "musitch.wav"
        panel.directoryURL = FileManager.default
            .urls(for: .musicDirectory, in: .userDomainMask).first
        panel.allowedContentTypes = [
            .wav, .mp3,
            UTType(filenameExtension: "ogg") ?? .audio,
            UTType(filenameExtension: "flac") ?? .audio,
        ]
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else {
                completion("Отменено.")
                return
            }
            do {
                try write(audio: audio, to: url)
                completion("Сохранено: \(url.lastPathComponent)")
            } catch {
                completion("Ошибка: \(error.localizedDescription)")
            }
        }
    }

    static func write(audio: [Float], to url: URL) throws {
        let ext = url.pathExtension.lowercased()
        if ext == "wav" {
            try writeWav(audio, to: url)
            return
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("musitch_export.wav")
        try writeWav(audio, to: tmp)
        let codec = ext == "ogg" ? "libvorbis"
            : (ext == "flac" ? "flac" : "libmp3lame")
        let ffmpeg = Bundle.main.url(forResource: "ffmpeg",
                                     withExtension: nil)?.path
            ?? "/opt/homebrew/bin/ffmpeg"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-y", "-v", "error", "-i", tmp.path,
                       "-c:a", codec, "-q:a", "3", url.path]
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "musitch", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                              "ffmpeg завершился с кодом \(p.terminationStatus)"])
        }
    }

    /// 32-бит float WAV, стерео, 44.1 кГц.
    static func writeWav(_ x: [Float], to url: URL) throws {
        let dataSize = UInt32(x.count * 4)
        var d = Data()
        func u32(_ v: UInt32) {
            var v = v.littleEndian
            withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
        }
        func u16(_ v: UInt16) {
            var v = v.littleEndian
            withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
        }
        d.append(contentsOf: "RIFF".utf8)
        u32(36 + dataSize)
        d.append(contentsOf: "WAVE".utf8)
        d.append(contentsOf: "fmt ".utf8)
        u32(16)          // размер fmt
        u16(3)           // IEEE float
        u16(2)           // стерео
        u32(44100)
        u32(44100 * 8)   // байт/сек
        u16(8)           // блок-выравнивание
        u16(32)          // бит на сэмпл
        d.append(contentsOf: "data".utf8)
        u32(dataSize)
        x.withUnsafeBytes { d.append(contentsOf: $0) }
        try d.write(to: url)
    }
}
