"""Иконка musitch: чёрный квадрат, белая осциллограмма, красный LED."""
import math
import sys

from PySide6.QtCore import Qt
from PySide6.QtGui import (QBrush, QColor, QImage, QPainter, QPainterPath,
                           QPen)
from PySide6.QtWidgets import QApplication

app = QApplication(sys.argv)
S = 1024
img = QImage(S, S, QImage.Format.Format_ARGB32)
img.fill(Qt.GlobalColor.transparent)

p = QPainter(img)
p.setRenderHint(QPainter.RenderHint.Antialiasing)

# фон: почти чёрный скруглённый квадрат с тонкой обводкой
r = 230
p.setBrush(QColor("#0a0a0a"))
p.setPen(QPen(QColor("#2a2a2a"), 6))
p.drawRoundedRect(3, 3, S - 6, S - 6, r, r)

# клип по иконке, чтобы ничего не вылезало
clip = QPainterPath()
clip.addRoundedRect(3, 3, S - 6, S - 6, r, r)
p.setClipPath(clip)

# сетка-паутина (очень тусклая)
p.setPen(QPen(QColor(255, 255, 255, 16), 3))
for i in range(1, 4):
    y = S * i / 4
    p.drawLine(0, y, S, y)
for i in range(1, 8):
    x = S * i / 8
    p.drawLine(x, 0, x, S)

# осциллограмма: «глитч»-волна с обрывами
path = QPainterPath()
mid = S * 0.52
amp = S * 0.20
n = 96
prev = mid
for i in range(n + 1):
    x = S * i / n
    t = i / n * math.pi * 6
    y = mid + math.sin(t) * amp * (0.55 + 0.45 * math.sin(t * 0.37))
    if i in (30, 31, 62):          # глитч-скачки
        y = mid + (amp * 1.25 if i == 31 else -amp * 1.15)
    if i in (46, 47, 48):          # обрыв — прямая
        y = mid
    if i == 0:
        path.moveTo(x, y)
    else:
        path.lineTo(x, y)
    prev = y

# мягкое свечение вокруг следа
p.setPen(QPen(QColor(255, 255, 255, 40), 26, Qt.PenStyle.SolidLine,
              Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
p.drawPath(path)
p.setPen(QPen(QColor("#f2f2f2"), 11, Qt.PenStyle.SolidLine,
              Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
p.drawPath(path)

# красный LED справа сверху
led_x, led_y, led_r = S * 0.80, S * 0.185, 34
p.setPen(Qt.PenStyle.NoPen)
p.setBrush(QColor(255, 59, 48, 60))
p.drawEllipse(int(led_x - led_r * 2), int(led_y - led_r * 2),
              led_r * 4, led_r * 4)
p.setBrush(QColor("#ff3b30"))
p.drawEllipse(int(led_x - led_r), int(led_y - led_r), led_r * 2, led_r * 2)

p.end()
img.save("/Users/tonix/Documents/Kimi/Workspaces/AIsoft/musitch/icon/icon_1024.png")

# превью для проверки глазами
for s in (128, 64):
    img.scaled(s, s, Qt.AspectRatioMode.KeepAspectRatio,
               Qt.TransformationMode.SmoothTransformation).save(
        f"/Users/tonix/Documents/Kimi/Workspaces/AIsoft/musitch/icon/preview_{s}.png")
print("ok")
