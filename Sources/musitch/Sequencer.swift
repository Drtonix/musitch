/// musitch — многоканальный секвенсор: каналы чипов × паттерн с нотами
/// произвольной длины (как в нормальном пиано-ролле).
import Foundation

struct Note: Equatable {
    var step: Int      // шаг начала (0..<steps)
    var midi: Int      // высота
    var len: Int       // длина в шагах (>=1)
    var vel: Int = 100 // 0..127
}

/// Один канал = один голос чипа + его ноты.
final class Channel {
    let name: String
    let voice: ChipVoiceType
    var notes: [Note] = []
    var muted = false

    init(name: String, voice: ChipVoiceType) {
        self.name = name
        self.voice = voice
    }

    func noteAt(step: Int, midi: Int) -> Int? {
        notes.firstIndex { $0.step == step && $0.midi == midi }
    }

    /// найти ноту, накрывающую шаг (начатую раньше, но длинную)
    func covering(step: Int, midi: Int) -> Int? {
        notes.firstIndex { $0.midi == midi
            && step >= $0.step && step < $0.step + $0.len }
    }
}

final class Seq {
    var steps = 16
    var bpm: Double = 128
    var playing = false
    var channels: [Channel] = []
    private var t: Double = 0
    private var nextStep = 0

    var currentStep: Int {
        playing ? (nextStep - 1 + steps) % steps : -1
    }

    var stepDur: Double { 60.0 / bpm / 4 }

    func reset() {
        nextStep = 0
        t = 0
    }

    func advance(_ n: Int) {
        guard playing else { return }
        let tEnd = t + Double(n) / SR
        while Double(nextStep) * stepDur < tEnd {
            let s = nextStep % steps
            for ch in channels where !ch.muted {
                for note in ch.notes where note.step == s {
                    ch.voice.noteOn(midi: note.midi,
                                    dur: Float(stepDur * Double(note.len)),
                                    vel: Float(note.vel) / 127)
                }
            }
            nextStep += 1
        }
        t = tEnd
    }
}
