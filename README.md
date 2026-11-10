# musitch

Ретровейв-станция для глитча и экспериментального звука. Нативное macOS-приложение (Swift 6, SwiftUI, AVAudioEngine). Чёрно-белый интерфейс с редкими красными/зелёными/синими LED-акцентами.

A retro-styled glitch & experimental-sound workstation for macOS. Native app (Swift 6, SwiftUI, AVAudioEngine). Black-and-white UI with sparse red/green/blue LED accents.

## Что внутри / Features

- **8 источников звука** — NOISE (белый шум с тоном), BUZZ (50 Гц + гармоники + треск), GLITCH (грейн-статтер), TAPE (wow/flutter + crackle), TV (кнопки старого телевизора), DRIVE (чистый перегруз пил), SUB (саб-дрон с биением), CHIP (8-бит квадрат).
- **Сэмплер** — свой аудиофайл (drag&drop или кнопка), выделение фрагмента на волне, реверс, нормализация, питч по полутонам (±24 st), скорость 0.25–4×, закрутка (питч-рамп), драйв, луп.
- **Мастер-FX** — bitcrush, distortion, резонансный фильтр (cutoff/reso), вариспид (±1 октава на весь микс), статтер-холд (зацикливает последний шаг), delay с временем/фидбэком/миксом.
- **8-бит секвенсор** — 16 шагов × 13 нот (C4–C5), клик по клетке ставит ноту, канал CHIP играет паттерн.
- **Визуализаторы** — осциллограф с послесвечением и логарифмический спектр (Accelerate/vDSP FFT).
- **Транспорт** — ▶ PLAY/■ STOP глушит всё; LED-семантика: зелёный = вкл, красный = выкл, синий = опции.
- **Запись и экспорт** — ● REC пишет мастер-шину, ЭКСПОРТ сохраняет WAV (32-bit float), MP3, OGG или FLAC (через встроенный ffmpeg).

## Сборка / Build

Требуется Xcode.app (Command Line Tools недостаточно — нужны SwiftUI-макросы).

```bash
./build_app.sh
```

Скрипт собирает release-бинарь через SwiftPM, упаковывает `musitch.app` (иконка, Info.plist, ffmpeg), adhoc-подписывает и копирует в `/Applications`.

## Прототип / Prototype

`prototype-py/` — исходный Python+PySide6-прототип, по которому написан DSP. Не нужен для работы приложения.

## License

MIT
