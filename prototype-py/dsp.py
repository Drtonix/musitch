"""musitch — DSP-движок: генераторы глитча, эффекты, секвенсор, микшер.

Всё считает numpy-блоками (стерео, 44.1 кГц). Модель вызовов — pull:
аудио-выход дёргает Engine.render(nframes), UI только крутит параметры.
"""
from __future__ import annotations

import numpy as np

SR = 44100


# ---------------------------------------------------------------- источники

class Source:
    """Базовый источник: вкл/выкл, громкость, два параметра."""
    title = "SRC"

    def __init__(self):
        self.on = False
        self.level = 0.8
        self.p1 = 0.5      # назначение у каждого своё
        self.p2 = 0.5
        self._phase = 0.0

    def render(self, n: int) -> np.ndarray:
        return np.zeros((n, 2), np.float32)


class Noise(Source):
    """Белый шум с тоном (p1: white→pink-ish через однополюсный фильтр)."""
    title = "NOISE"

    def __init__(self):
        super().__init__()
        self._mem = 0.0

    def render(self, n):
        if not self.on:
            return super().render(n)
        w = np.random.uniform(-1, 1, n).astype(np.float32)
        a = 0.02 + self.p1 * 0.25
        out = np.empty(n, np.float32)
        mem = self._mem
        for i in range(n):
            mem = mem + a * (w[i] - mem)
            out[i] = mem
        self._mem = mem
        out = out * (1.0 + 6.0 * self.p1)     # компенсация спада
        return np.stack([out, out], 1) * self.level


class Buzz(Source):
    """Электричество: 50 Гц + гармоники, p2 — треск/искры."""
    title = "BUZZ"

    def __init__(self):
        super().__init__()
        self._ph = 0.0

    def render(self, n):
        if not self.on:
            return super().render(n)
        t = (np.arange(n) + self._ph) / SR
        self._ph += n
        f0 = 50.0
        sig = np.zeros(n, np.float32)
        for h, g in ((1, 1.0), (2, 0.45), (3, 0.3), (5, 0.12), (7, 0.07)):
            sig += g * np.sign(np.sin(2 * np.pi * f0 * h * t))
        # треск: случайные короткие всплески
        if self.p2 > 0.05:
            mask = np.random.rand(n) < (self.p2 * 0.002)
            sig = sig * 0.6 + mask.astype(np.float32) * np.random.uniform(-1, 1, n)
        sig *= 0.25
        return np.stack([sig, sig], 1) * self.level


class Glitch(Source):
    """Статтер: дробит несущую (синтетический шум-импульс) на куски.
    p1 — плотность, p2 — скорость повторов."""
    title = "GLITCH"

    def __init__(self):
        super().__init__()
        self._buf = np.zeros(1, np.float32)
        self._pos = 0
        self._cnt = 0

    def render(self, n):
        if not self.on:
            return super().render(n)
        out = np.zeros(n, np.float32)
        grain = max(32, int((1.0 - self.p1) * 2200))
        rep = max(1, int(self.p2 * 8))
        i = 0
        while i < n:
            if self._pos >= len(self._buf):
                # новый грейн: шип/щелчок/тона в случайном диапазоне
                kind = np.random.randint(3)
                if kind == 0:
                    self._buf = np.random.uniform(-1, 1, grain).astype(np.float32)
                elif kind == 1:
                    f = np.random.uniform(200, 4000)
                    tt = np.arange(grain) / SR
                    self._buf = (np.sin(2 * np.pi * f * tt)
                                 * np.hanning(grain)).astype(np.float32)
                else:
                    self._buf = np.zeros(grain, np.float32)
                    self._buf[:64] = np.random.uniform(-1, 1, 64)
                self._pos = 0
                self._cnt = rep
            take = min(n - i, len(self._buf) - self._pos)
            out[i:i + take] = self._buf[self._pos:self._pos + take]
            self._pos += take
            i += take
            if self._pos >= len(self._buf):
                self._cnt -= 1
                if self._cnt > 0:
                    self._pos = 0
        env = np.hanning(len(out)).astype(np.float32) ** 0.15
        return np.stack([out * env, out * env], 1) * self.level * 0.7


class Tape(Source):
    """Кассета: шипение + wow/flutter-дрон + треск.
    p1 — износ (crackle), p2 — глубина расстройки."""
    title = "TAPE"

    def __init__(self):
        super().__init__()
        self._ph = 0.0

    def render(self, n):
        if not self.on:
            return super().render(n)
        t = (np.arange(n) + self._ph) / SR
        self._ph += n
        wow = np.sin(2 * np.pi * 0.6 * t) * self.p2 * 6.0
        f = 110.0 + wow
        ph = np.cumsum(2 * np.pi * f / SR)
        drone = np.sin(ph) * 0.4 + np.sin(2 * ph) * 0.15
        hiss = np.random.uniform(-1, 1, n).astype(np.float32) * 0.06
        crk = (np.random.rand(n) < self.p1 * 0.0008).astype(np.float32) \
            * np.random.uniform(-1, 1, n) * 0.8
        sig = drone * 0.5 + hiss + crk
        return np.stack([sig, sig], 1) * self.level


class TV(Source):
    """Кнопки старого телевизора: щелчки + короткие писки.
    p1 — частота событий, p2 — высота писка."""
    title = "TV"

    def __init__(self):
        super().__init__()
        self._env = np.zeros(1, np.float32)
        self._tone = np.zeros(1, np.float32)
        self._pos = 0

    def render(self, n):
        if not self.on:
            return super().render(n)
        out = np.zeros(n, np.float32)
        i = 0
        while i < n:
            if self._pos >= len(self._env):
                if np.random.rand() < self.p1 * 0.0009:
                    ln = int(0.02 * SR + np.random.rand() * 0.08 * SR)
                    f = 300 + self.p2 * 2000 + np.random.rand() * 800
                    tt = np.arange(ln) / SR
                    self._tone = np.sin(2 * np.pi * f * tt).astype(np.float32)
                    self._env = np.exp(-tt * 60).astype(np.float32)
                    click = np.zeros(12, np.float32)
                    click[:] = np.random.uniform(-1, 1, 12)  # сам щелчок
                    self._tone = np.concatenate([click, self._tone])
                    self._env = np.concatenate([np.ones(12, np.float32), self._env])
                    self._pos = 0
                else:
                    i = n
                    break
            take = min(n - i, len(self._env) - self._pos)
            out[i:i + take] = (self._tone[self._pos:self._pos + take]
                               * self._env[self._pos:self._pos + take])
            self._pos += take
            i += take
        return np.stack([out, out], 1) * self.level


class Drive(Source):
    """Чистый перегруз: стек пил через жёсткий waveshaper.
    p1 — драйв, p2 — нота (дрон)."""
    title = "DRIVE"

    def __init__(self):
        super().__init__()
        self._ph = np.zeros(3)

    def render(self, n):
        if not self.on:
            return super().render(n)
        base = 27.5 * 2 ** (self.p2 * 4)          # A0 .. A4
        t = (np.arange(n))[:, None] / SR
        ph = (self._ph + 2 * np.pi * base * np.array([1.0, 1.005, 0.5]) * t)
        self._ph = ph[-1] % (2 * np.pi)
        saw = 2 * ((ph / (2 * np.pi)) % 1.0) - 1.0
        sig = saw.sum(1) / 3
        d = 1 + self.p1 * 24
        sig = np.tanh(sig * d)
        return np.stack([sig, sig], 1) * self.level * 0.5


class SubDrone(Source):
    """Саб-дрон: глубокий синус с биением.
    p1 — частота, p2 — биение."""
    title = "SUB"

    def __init__(self):
        super().__init__()
        self._ph = 0.0

    def render(self, n):
        if not self.on:
            return super().render(n)
        f = 30.0 + self.p1 * 40.0
        t = (np.arange(n) + self._ph) / SR
        self._ph += n
        beat = 0.5 + self.p2 * 6.0
        lfo = 0.75 + 0.25 * np.sin(2 * np.pi * beat * t)
        sig = np.sin(2 * np.pi * f * t) * lfo
        return np.stack([sig, sig], 1) * self.level * 0.8


# ---------------------------------------------------------------- чип-синт

class ChipVoice:
    __slots__ = ("freq", "t", "dur", "duty", "amp")

    def __init__(self, freq, dur, duty, amp=0.5):
        self.freq, self.t, self.dur, self.duty, self.amp = freq, 0.0, dur, duty, amp


class Chip(Source):
    """8-бит канал: квадрат с регулируемой скважностью, играет секвенсор.
    p1 — duty (10%..50%), p2 — арпеджио-вибрато."""
    title = "CHIP"

    def __init__(self):
        super().__init__()
        self.on = True
        self.voices: list[ChipVoice] = []
        self._ph = 0.0

    def note_on(self, midi: int, dur_s: float):
        f = 440.0 * 2 ** ((midi - 69) / 12)
        self.voices.append(ChipVoice(f, dur_s, 0.1 + self.p1 * 0.4))

    def render(self, n):
        out = np.zeros(n, np.float32)
        alive = []
        for v in self.voices:
            left = v.dur - v.t
            if left <= 0:
                continue
            m = min(n, int(left * SR))
            tt = (np.arange(m) + v.t * SR) / SR
            duty = v.duty
            if self.p2 > 0.55:                    # вибрато
                fmod = v.freq * (1 + 0.02 * np.sin(2 * np.pi * 8 * tt))
            else:
                fmod = v.freq
                f = fmod
            ph = np.cumsum(2 * np.pi * (v.freq if self.p2 <= 0.55 else fmod) / SR)
            sq = ((ph % (2 * np.pi)) < 2 * np.pi * duty).astype(np.float32) * 2 - 1
            env = np.minimum(1.0, np.linspace(1.0, 0.0, m) ** 0.3 + 0.15)
            out[:m] += sq * env * v.amp * 0.4
            v.t += m / SR
            alive.append(v)
        self.voices = alive
        return np.stack([out, out], 1) * self.level


# ---------------------------------------------------------------- эффекты

class FX:
    """Мастер-цепочка: bitcrush → distortion → delay → lowpass."""

    def __init__(self):
        self.crush = 0.0       # 0..1
        self.dist = 0.0
        self.delay = 0.0
        self.lp = 1.0          # 1 = открыт
        self._dl = np.zeros(2, np.float32)
        self._buf_l = np.zeros(SR, np.float32)   # 1 с на канал
        self._buf_r = np.zeros(SR, np.float32)
        self._w = 0

    def process(self, x: np.ndarray) -> np.ndarray:
        n = len(x)
        if self.crush > 0.01:
            bits = 16 - int(self.crush * 12)
            q = 2.0 ** (bits - 1)
            x = np.round(x * q) / q
        if self.dist > 0.01:
            x = np.tanh(x * (1 + self.dist * 20))
        if self.delay > 0.01:
            d = int(0.35 * SR)
            fb, mix = 0.45, 0.4 * self.delay
            y = x.copy()
            for i in range(n):
                rpos = (self._w - d) % SR
                dl = self._buf_l[rpos] * fb
                dr = self._buf_r[rpos] * fb
                self._buf_l[self._w] = x[i, 0] + dl
                self._buf_r[self._w] = x[i, 1] + dr
                y[i, 0] += self._buf_l[rpos] * mix
                y[i, 1] += self._buf_r[rpos] * mix
                self._w = (self._w + 1) % SR
            x = y
        if self.lp < 0.99:
            a = 0.005 + self.lp * 0.2
            l = np.empty(n, np.float32)
            r = np.empty(n, np.float32)
            l0, r0 = self._dl
            for i in range(n):
                l0 += a * (x[i, 0] - l0)
                r0 += a * (x[i, 1] - r0)
                l[i], r[i] = l0, r0
            self._dl = np.array([l0, r0], np.float32)
            x = np.stack([l, r], 1)
        return x


# ---------------------------------------------------------------- секвенсор

class Sequencer:
    """16 шагов × ноты; BPM; крутит Chip."""
    STEPS = 16

    def __init__(self, chip: Chip):
        self.chip = chip
        self.bpm = 128.0
        self.playing = False
        self.grid: set[tuple[int, int]] = set()   # (step, midi)
        self._t = 0.0
        self._next_step = 0

    def toggle(self, step: int, midi: int):
        key = (step, midi)
        self.grid ^= {key}

    def advance(self, n: int):
        if not self.playing:
            return
        step_dur = 60.0 / self.bpm / 4
        t_end = self._t + n / SR
        while self._next_step * step_dur < t_end:
            s = self._next_step % self.STEPS
            for (st, midi) in list(self.grid):
                if st == s:
                    self.chip.note_on(midi, step_dur * 2)
            self._next_step += 1
        self._t = t_end

    @property
    def current_step(self) -> int:
        return (self._next_step - 1) % self.STEPS if self.playing else -1


# ---------------------------------------------------------------- движок

class Engine:
    """Микшер: источники → секвенсор → FX → мягкий лимитер."""

    def __init__(self):
        self.chip = Chip()
        self.sources: list[Source] = [
            Noise(), Buzz(), Glitch(), Tape(), TV(), Drive(), SubDrone(),
            self.chip,
        ]
        self.fx = FX()
        self.seq = Sequencer(self.chip)
        self.master = 0.9
        self.recording = False
        self.recorded: list[np.ndarray] = []
        self.last_block = np.zeros((1024, 2), np.float32)  # для визуализаторов

    def render(self, n: int) -> np.ndarray:
        self.seq.advance(n)
        out = np.zeros((n, 2), np.float32)
        for s in self.sources:
            if s.on:
                out += s.render(n)
        out = self.fx.process(out)
        out = np.tanh(out * self.master).astype(np.float32)
        if self.recording:
            self.recorded.append(out.copy())
        self.last_block = out
        return out

    def take_recording(self) -> np.ndarray:
        audio = (np.concatenate(self.recorded) if self.recorded
                 else np.zeros((1, 2), np.float32))
        self.recorded = []
        return audio
