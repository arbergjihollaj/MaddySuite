# MaddySuite

MaddySuite kombiniert:

- **MaddyV2 (macOS App)**: Haupt-App mit Fokus, Aufgaben, Gewohnheiten, Musik, Stats, Settings und ESP-Integration.
- **MaddyMobile (iPhone App)**: Companion-App (offline-first, lokal gespeichert, ohne ESP/AI-Steuerung).
- **ESP32 Firmware**: ST7789-Display-Firmware für das externe Status-Display.

## Projektstruktur

```text
MaddySuite/
├── ESP32-Firmware/
├── MaddyV2-App/
├── MaddyMobile-App/
└── Icloud-Sync/
```

## Voraussetzungen

- **macOS + Xcode** (für Mac- und iPhone-App)
- **Arduino IDE** oder PlatformIO (für ESP32-Firmware)
- **ESP32 Board Package** installiert
- Optional für private Repos/CI: GitHub CLI (`gh`)

## Schnellstart

### 1) macOS App (MaddyV2)

1. Öffnen:
   - `MaddyV2-App/MaddyV2/MaddyV2.xcodeproj`
2. Signing/Team in Xcode prüfen.
3. Build & Run starten.

### 2) iPhone App (MaddyMobile)

1. Öffnen:
   - `MaddyMobile-App/MaddyMobile.xcodeproj`
2. Signing/Bundle Identifier prüfen.
3. Simulator oder echtes iPhone auswählen.
4. Build & Run starten.

### 3) ESP32 Firmware

1. Öffnen:
   - `ESP32-Firmware/MaddyDisplayFirmware/MaddyDisplayFirmware.ino`
2. Board/Port in Arduino IDE auswählen.
3. Hochladen.
4. Parser-/Stabilitätstests:
   - `ESP32-Firmware/TESTING.md`

## ESP Display Eckdaten

- Controller: **ST7789**
- Panel: **1.47\" IPS**
- Rotation: `setRotation(3)`
- Effektive Auflösung: **320 x 172** (Landscape)

## Serielle Kommunikation (Kurzüberblick)

Line-based, newline-terminated bei 115200 Baud.

Beispiele:

- `hello:esp|proto=2|fw=1.0|screen=idle`
- `ping` / `pong`
- `view:idle|music|focus|tasks|habits|coach|game|stats|settings|debug`
- `time:HH:MM`
- `date:YYYY-MM-DD`
- `pomo:phase|remaining|total|running`
- `music:state|artist|title|posSec|durSec`
- `gamify:level|v1|v2|v3|v4|v5|v6`

## Hinweis zu iCloud Capability

Für echte iCloud/CloudKit-Features auf iOS/macOS ist in der Regel ein **bezahltes Apple Developer Program Team** nötig.  
Mit Personal Team funktioniert Signierung lokal, aber bestimmte Capabilities (z. B. iCloud) sind eingeschränkt.
