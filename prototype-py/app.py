"""musitch — ретровейв-станция для глитча и экспериментального звука.

ЧБ интерфейс с LED-акцентами: модули-источники (NOISE, BUZZ, GLITCH,
TAPE, TV, DRIVE, SUB, CHIP), мастер-эффекты, 8-бит секвенсор с пиано-
роллом, осциллограф и спектр, запись мастера в wav/mp3/ogg.

Запуск из исходников: uv run python app.py
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from PySide6.QtCore import QIODevice, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QFontDatabase, QPainter, QPen
from PySide6.QtMultimedia import QAudioFormat, QAudioSink, QMediaDevices
from PySide6.QtWidgets import (
    QApplication, QComboBox, QDialog, QDialogButtonBox, QFileDialog,
    QFrame, QGridLayout, QHBoxLayout, QLabel, QMainWindow, QPushButton,
    QScrollArea, QSlider, QSpinBox, QVBoxLayout, QWidget,
)

from dsp import Engine
from viz import Scope, Spectrum

# ---------------------------------------------------------------- стиль

BG = "#050505"
PANEL = "#0f0f0f"
LINE = "#262626"
TEXT = "#e8e8e8"
MUTED = "#7a7a7a"
LED_G = "#30d158"
LED_R = "#ff3b30"
LED_B = "#0a84ff"
MONO = "Menlo"


def style() -> str:
    return f"""
* {{ font-family: "{MONO}", "JetBrains Mono", monospace; }}
QWidget {{ background: {BG}; color: {TEXT}; font-size: 12px; }}
QLabel {{ background: transparent; }}
QLabel#logo {{ font-size: 20px; font-weight: 700; letter-spacing: 4px; }}
QLabel#sub {{ color: {MUTED}; font-size: 10px; letter-spacing: 2px; }}
QLabel#h {{ font-size: 11px; color: {MUTED}; letter-spacing: 3px; }}
QLabel#param {{ color: {MUTED}; font-size: 10px; }}

QFrame#panel {{ background: {PANEL}; border: 1px solid {LINE}; border-radius: 6px; }}

QPushButton {{
    background: transparent; border: 1px solid {LINE};
    border-radius: 4px; padding: 7px 14px; letter-spacing: 1px;
}}
QPushButton:hover {{ border-color: {TEXT}; }}
QPushButton:checked {{
    background: {TEXT}; color: {BG}; font-weight: 700;
}}
QPushButton#rec:checked {{ background: {LED_R}; color: #fff; border-color: {LED_R}; }}
QPushButton#play:checked {{ background: {LED_G}; color: #000; border-color: {LED_G}; }}

QSlider::groove:horizontal {{
    height: 2px; background: {LINE};
}}
QSlider::handle:horizontal {{
    width: 12px; height: 12px; margin: -5px 0;
    background: {TEXT}; border-radius: 6px;
}}
QSlider::handle:horizontal:hover {{ background: {LED_B}; }}

QSpinBox {{
    background: {PANEL}; border: 1px solid {LINE}; border-radius: 4px;
    padding: 4px 8px;
}}
QSpinBox::up-button, QSpinBox::down-button {{ width: 14px; border: none; }}

QComboBox {{
    background: {PANEL}; border: 1px solid {LINE}; border-radius: 4px;
    padding: 5px 10px;
}}
QComboBox QAbstractItemView {{
    background: {PANEL}; border: 1px solid {LINE};
    selection-background-color: #1f1f1f;
}}
QScrollArea {{ border: none; }}
"""


# ---------------------------------------------------------------- светодиод

class Led(QWidget):
    def __init__(self, color: str = LED_G, d: int = 8):
        super().__init__()
        self.setFixedSize(d, d)
        self.color = QColor(color)
        self.lit = False

    def set(self, on: bool):
        self.lit = on
        self.update()

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        d = self.width()
        if self.lit:
            glow = QColor(self.color)
            glow.setAlpha(70)
            p.setBrush(glow)
            p.setPen(Qt.PenStyle.NoPen)
            p.drawEllipse(-2, -2, d + 4, d + 4)
        p.setBrush(self.color if self.lit else QColor("#222222"))
        p.setPen(QPen(QColor("#333333"), 1))
        p.drawEllipse(0, 0, d, d)
        p.end()


# ---------------------------------------------------------------- аудио-вывод

class AudioOut(QIODevice):
    def __init__(self, engine: Engine):
        super().__init__()
        self.engine = engine

    def readData(self, maxlen: int) -> bytes:
        n = maxlen // 8
        if n <= 0:
            return b""
        return self.engine.render(n).astype(np.float32).tobytes()

    def writeData(self, _):
        return -1


# ---------------------------------------------------------------- модуль-пэд

PARAM_NAMES = {
    "NOISE": ("TONE", "—"), "BUZZ": ("HUM", "SPARK"),
    "GLITCH": ("DENSITY", "REPEAT"), "TAPE": ("WEAR", "WOW"),
    "TV": ("RATE", "PITCH"), "DRIVE": ("DRIVE", "NOTE"),
    "SUB": ("FREQ", "BEAT"), "CHIP": ("DUTY", "VIB"),
}


class Module(QFrame):
    """Один источник звука: заголовок, LED, кнопка вкл, два параметра."""

    def __init__(self, src, led_color: str):
        super().__init__(objectName="panel")
        self.src = src
        lay = QVBoxLayout(self)
        lay.setContentsMargins(12, 10, 12, 12)
        lay.setSpacing(6)

        top = QHBoxLayout()
        name = QLabel(src.title, objectName="h")
        name.setStyleSheet(f"color: {TEXT}; font-weight: 700;")
        top.addWidget(name)
        top.addStretch()
        self.led = Led(led_color)
        top.addWidget(self.led)
        self.btn = QPushButton("OFF")
        self.btn.setCheckable(True)
        self.btn.setFixedWidth(64)
        self.btn.toggled.connect(self._toggle)
        top.addWidget(self.btn)
        lay.addLayout(top)

        p1, p2 = PARAM_NAMES.get(src.title, ("P1", "P2"))
        self._param_row(lay, p1, "p1")
        if p2 != "—":
            self._param_row(lay, p2, "p2")

    def _param_row(self, lay, label, attr):
        row = QHBoxLayout()
        lab = QLabel(label, objectName="param")
        lab.setFixedWidth(56)
        row.addWidget(lab)
        sl = QSlider(Qt.Orientation.Horizontal, value=50)
        sl.valueChanged.connect(lambda v, a=attr: setattr(self.src, a, v / 100))
        row.addWidget(sl)
        lay.addLayout(row)

    def _toggle(self, on: bool):
        self.src.on = on
        self.btn.setText("ON" if on else "OFF")
        self.led.set(on)


# ---------------------------------------------------------------- пиано-ролл

class SeqGrid(QWidget):
    """16 шагов × 13 нот (C4..C5). Клик — вкл/выкл ноту."""
    NOTE_TOP = 72          # C5
    ROWS = 13

    def __init__(self, engine: Engine):
        super().__init__()
        self.engine = engine
        self.cell = 22
        self.setFixedSize(self.cell * engine.seq.STEPS + 60,
                          self.cell * self.ROWS + 6)
        self._timer = QTimer(self, timeout=self.update)
        self._timer.start(60)

    def mousePressEvent(self, e):
        x = int((e.position().x() - 56) / self.cell)
        row = int((e.position().y() - 3) / self.cell)
        if 0 <= x < self.engine.seq.STEPS and 0 <= row < self.ROWS:
            midi = self.NOTE_TOP - row
            self.engine.seq.toggle(x, midi)
            self.update()

    def paintEvent(self, _):
        p = QPainter(self)
        c = self.cell
        seq = self.engine.seq
        names = ["C5", "B4", "A#4", "A4", "G#4", "G4", "F#4",
                 "F4", "E4", "D#4", "D4", "C#4", "C4"]
        p.setPen(QPen(QColor(MUTED), 1))
        f = p.font()
        f.setPixelSize(9)
        p.setFont(f)
        for row in range(self.ROWS):
            p.drawText(4, row * c + 3 + 14, names[row])
        cur = seq.current_step
        for s in range(seq.STEPS):
            for row in range(self.ROWS):
                x, y = 56 + s * c, 3 + row * c
                on = (s, self.NOTE_TOP - row) in seq.grid
                border = QColor("#333333")
                p.setPen(QPen(border, 1))
                p.setBrush(QColor("#161616"))
                p.drawRect(x, y, c - 2, c - 2)
                if s == cur:
                    p.fillRect(x, y, c - 2, c - 2, QColor(255, 255, 255, 18))
                if on:
                    p.setBrush(QColor(TEXT))
                    p.setPen(Qt.PenStyle.NoPen)
                    p.drawRect(x + 2, y + 2, c - 6, c - 6)
        p.end()


# ---------------------------------------------------------------- главное окно

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("musitch")
        self.engine = Engine()

        # аудио-выход
        fmt = QAudioFormat()
        fmt.setSampleRate(44100)
        fmt.setChannelCount(2)
        fmt.setSampleFormat(QAudioFormat.SampleFormat.Float)
        self.io = AudioOut(self.engine)
        self.io.open(QIODevice.OpenModeFlag.ReadOnly)
        self.sink = QAudioSink(QMediaDevices.defaultAudioOutput(), fmt)
        self.sink.setBufferSize(8192)
        self.sink.start(self.io)

        root = QWidget()
        root_lay = QVBoxLayout(root)
        root_lay.setContentsMargins(16, 12, 16, 12)
        root_lay.setSpacing(10)

        # шапка
        head = QHBoxLayout()
        logo_col = QVBoxLayout()
        logo_col.setSpacing(0)
        logo_col.addWidget(QLabel("MUSITCH", objectName="logo"))
        logo_col.addWidget(QLabel("GLITCH · TAPE · 8BIT · NOISE",
                                  objectName="sub"))
        head.addLayout(logo_col)
        head.addStretch()
        self.led_play = Led(LED_G, 10)
        head.addWidget(self.led_play)
        self.play_btn = QPushButton("▶ PLAY", objectName="play")
        self.play_btn.setCheckable(True)
        self.play_btn.toggled.connect(self._play)
        head.addWidget(self.play_btn)
        head.addSpacing(8)
        self.led_rec = Led(LED_R, 10)
        head.addWidget(self.led_rec)
        self.rec_btn = QPushButton("● REC", objectName="rec")
        self.rec_btn.setCheckable(True)
        self.rec_btn.toggled.connect(self._rec)
        head.addWidget(self.rec_btn)
        head.addSpacing(8)
        head.addWidget(QLabel("BPM", objectName="param"))
        self.bpm = QSpinBox(minimum=40, maximum=300, value=128)
        self.bpm.valueChanged.connect(
            lambda v: setattr(self.engine.seq, "bpm", float(v)))
        head.addWidget(self.bpm)
        save = QPushButton("💾 ЭКСПОРТ")
        save.clicked.connect(self._export)
        head.addWidget(save)
        root_lay.addLayout(head)

        # визуализаторы
        viz_row = QHBoxLayout()
        viz_row.addWidget(Scope(self.engine), stretch=1)
        viz_row.addWidget(Spectrum(self.engine), stretch=1)
        root_lay.addLayout(viz_row)

        # модули
        grid = QGridLayout()
        grid.setSpacing(8)
        led_colors = [LED_G, LED_B, LED_R, LED_G, LED_B, LED_R, LED_G, LED_B]
        for i, src in enumerate(self.engine.sources):
            grid.addWidget(Module(src, led_colors[i % len(led_colors)]),
                           i // 4, i % 4)
        root_lay.addLayout(grid)

        # эффекты
        fx = QFrame(objectName="panel")
        fx_lay = QHBoxLayout(fx)
        fx_lay.setContentsMargins(14, 10, 14, 12)
        fx_lay.setSpacing(16)
        fx_lay.addWidget(QLabel("FX", objectName="h"))
        for label, attr in (("BITCRUSH", "crush"), ("DISTORT", "dist"),
                            ("DELAY", "delay"), ("FILTER", "lp")):
            col = QVBoxLayout()
            lab = QLabel(label, objectName="param")
            lab.setAlignment(Qt.AlignmentFlag.AlignCenter)
            col.addWidget(lab)
            sl = QSlider(Qt.Orientation.Horizontal,
                         value=100 if attr == "lp" else 0)
            sl.setFixedWidth(130)
            sl.valueChanged.connect(
                lambda v, a=attr: setattr(self.engine.fx, a, v / 100))
            col.addWidget(sl)
            fx_lay.addLayout(col)
        fx_lay.addStretch()
        fx_lay.addWidget(QLabel("MASTER", objectName="param"))
        mst = QSlider(Qt.Orientation.Horizontal, value=90)
        mst.setFixedWidth(110)
        mst.valueChanged.connect(
            lambda v: setattr(self.engine, "master", v / 100))
        fx_lay.addWidget(mst)
        root_lay.addWidget(fx)

        # секвенсор
        seqf = QFrame(objectName="panel")
        seq_lay = QVBoxLayout(seqf)
        seq_lay.setContentsMargins(14, 10, 14, 12)
        seq_lay.addWidget(QLabel("8-BIT СЕКВЕНСОР — CHIP", objectName="h"))
        seq_lay.addWidget(SeqGrid(self.engine),
                          alignment=Qt.AlignmentFlag.AlignHCenter)
        root_lay.addWidget(seqf)

        scroll = QScrollArea()
        scroll.setWidget(root)
        scroll.setWidgetResizable(True)
        self.setCentralWidget(scroll)
        self.resize(1120, 860)

    # ------------------------------------------------------------ транспорт

    def _play(self, on: bool):
        self.engine.seq.playing = on
        self.led_play.set(on)
        if not on:
            self.engine.seq._next_step = 0
            self.engine.seq._t = 0.0

    def _rec(self, on: bool):
        self.engine.recording = on
        self.led_rec.set(on)
        self.rec_btn.setText("■ STOP" if on else "● REC")

    def _export(self):
        audio = self.engine.take_recording()
        if self.engine.recording:
            self.rec_btn.setChecked(False)
        if len(audio) < 4410:
            self.statusBar().showMessage("Не записано ни одной секунды — "
                                         "нажмите ● REC, поиграйте, затем экспорт.")
            return
        path, flt = QFileDialog.getSaveFileName(
            self, "Экспорт записи", str(Path.home() / "Music" / "musitch.wav"),
            "WAV (*.wav);;MP3 (*.mp3);;OGG (*.ogg);;FLAC (*.flac)")
        if not path:
            return
        p = Path(path)
        if p.suffix.lower() == ".wav":
            sf.write(str(p), audio, 44100)
        else:
            tmp = Path(tempfile.gettempdir()) / "musitch_export.wav"
            sf.write(str(tmp), audio, 44100)
            codec = {".mp3": "libmp3lame", ".ogg": "libvorbis",
                     ".flac": "flac"}.get(p.suffix.lower(), "libmp3lame")
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(tmp),
                            "-c:a", codec, "-q:a", "3", str(p)], check=True)
        self.statusBar().showMessage(f"Сохранено: {p}")


def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    app.setStyleSheet(style())
    win = MainWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
