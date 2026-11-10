"""musitch — визуализаторы: осциллограф и спектр, CRT/фосфор стиль."""
from __future__ import annotations

import numpy as np
from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QWidget

PHOS = QColor("#e8e8e8")          # «фосфор» — белый след
DIM = QColor(255, 255, 255, 28)   # сетка


class Scope(QWidget):
    """Осциллограф: след волны с послесвечением."""

    def __init__(self, engine, parent=None):
        super().__init__(parent)
        self.engine = engine
        self._trail: list[np.ndarray] = []
        self.setMinimumHeight(130)
        self._timer = QTimer(self, timeout=self.update)
        self._timer.start(33)

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()
        p.fillRect(self.rect(), QColor("#0a0a0a"))

        # сетка
        p.setPen(QPen(DIM, 1))
        for gy in range(1, 4):
            y = h * gy / 4
            p.drawLine(0, y, w, y)
        for gx in range(1, 8):
            x = w * gx / 8
            p.drawLine(x, 0, x, h)

        block = self.engine.last_block[:, 0]
        if len(block) > 2:
            k = max(1, len(block) // 512)
            sig = block[::k]
            self._trail.append(sig)
            if len(self._trail) > 3:
                self._trail.pop(0)

        # послесвечение
        for i, sig in enumerate(self._trail):
            alpha = int(40 + 190 * (i + 1) / len(self._trail))
            path = QPainterPath()
            n = len(sig)
            for j, v in enumerate(sig):
                x = w * j / max(n - 1, 1)
                y = h / 2 - float(v) * h * 0.45
                if j == 0:
                    path.moveTo(x, y)
                else:
                    path.lineTo(x, y)
            p.setPen(QPen(QColor(255, 255, 255, alpha), 1.4))
            p.drawPath(path)
        p.setPen(QPen(QColor("#262626"), 1))
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawRect(0, 0, w - 1, h - 1)
        p.end()


class Spectrum(QWidget):
    """Спектр: столбики, монохром с редкими цветными пиками."""

    BARS = 32

    def __init__(self, engine, parent=None):
        super().__init__(parent)
        self.engine = engine
        self.setMinimumHeight(130)
        self._smooth = np.zeros(self.BARS)
        self._timer = QTimer(self, timeout=self.update)
        self._timer.start(33)

    def paintEvent(self, _):
        p = QPainter(self)
        w, h = self.width(), self.height()
        p.fillRect(self.rect(), QColor("#0a0a0a"))

        block = self.engine.last_block.mean(axis=1)
        if len(block) >= 256:
            win = np.hanning(1024)
            seg = block[:1024] * win if len(block) >= 1024 else np.pad(
                block, (0, 1024 - len(block))) * win
            sp = np.abs(np.fft.rfft(seg))[1:]
            peak = max(float(sp.max()), 1e-9, float(self._smooth.max()) * 2)
            self._peak = max(getattr(self, "_peak", 1e-9) * 0.98, peak)
            idx = np.geomspace(1, len(sp), self.BARS + 1).astype(int)
            vals = np.array([sp[a:b].mean() if b > a else 0
                             for a, b in zip(idx[:-1], idx[1:])])
            mag = np.log1p(vals / self._peak * 6) / np.log1p(6)
            self._smooth = np.maximum(mag, self._smooth * 0.75)
        bw = w / self.BARS
        for i, v in enumerate(self._smooth):
            if v <= 0.01:
                continue
            bh = max(2.0, float(np.clip(v, 0, 1)) * (h - 8))
            col = PHOS
            if v > 0.9:
                col = QColor("#ff3b30")      # пик — красный
            elif v > 0.75:
                col = QColor("#30d158")      # высокий — зелёный
            p.fillRect(int(i * bw) + 1, int(h - bh),
                       int(bw) - 2, int(bh), col)
        p.setPen(QPen(QColor("#262626"), 1))
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.drawRect(0, 0, w - 1, h - 1)
        p.end()
