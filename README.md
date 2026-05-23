# Hudai — هُداي
### AI-Powered Hajj Navigation for Visually Impaired Pilgrims

Hudai is a Flutter mobile application that guides visually impaired pilgrims through the Hajj journey using real-time AI scene detection, spoken Arabic audio instructions, and GPS-based arrival confirmation  with no screen interaction required during use.

---

## Overview

Pilgrims point their phone camera forward. Hudai continuously analyzes the scene, speaks guidance in Arabic, and alerts the user to crowds, the direction of Jabal Arafah, AR navigation markers, and arrival at the Arafat zone all through audio alone.

The app is designed to be operated entirely by touch zones (four corner buttons, no labels needed) so it remains accessible when vision is limited or unavailable.

---

## Features

| Category | What it does |
|---|---|
| **Crowd & Safety Alerts** | Detects a single person or a dense crowd ahead; speaks urgency-scaled warnings |
| **Jabal Arafah Recognition** | Identifies Jabal Arafah in the camera feed and guides the pilgrim toward it |
| **AR Marker Detection** | Recognizes physical navigation markers placed along the route |
| **GPS Arrival Confirmation** | Confirms entry into the Arafat zone via GPS, independent of the camera |
| **Camera Self-Check** | Detects a blocked or misaligned lens and asks the user to reposition |
| **Replay Last Instruction** | Bottom-left tap replays the most recent spoken instruction |
| **Emergency Call** | Top-right tap dials a pre-configured emergency number instantly |
| **Voice Setup** | First-run flow uses Arabic speech recognition to capture the emergency number |
| **Always-On Screen** | Wakelock keeps the screen active during navigation |

---

## Detection Classes

The on-device YOLO model (`yolo_hajj.tflite`) detects five classes:

| Class | Description |
|---|---|
| `jabal_arafah` | Jabal Arafah (Mount Arafat) |
| `ar_marker` | Physical AR navigation markers |
| `person` | Single person in the path |
| `other_mountains` | Mountains other than Jabal Arafah |
| `crowd` | Dense crowd |

Input: 640 × 640 RGB — Inference rate: 2 FPS (configurable via `YoloConfig.targetFps`)

---

## Audio Guidance System

Audio instructions are prioritized so the most urgent message always plays first:

| Priority | Category | Example triggers |
|---|---|---|
| 1 (highest) | Safety | Crowd or person detected ahead |
| 2 | Camera Guidance | Lens blocked, camera misaligned |
| 3 | Mountain Recognition | Jabal Arafah recognized, scene unclear |
| 4 | Mountain Location | Arafah is ahead, marker visible |
| 5 | Movement Confirmation | Keep walking in the same direction |
| 6 (lowest) | Distance & Arrival | Entered Arafat zone (GPS-confirmed) |

Per-category cooldowns (5s - 20s) prevent audio flooding between frames.

---

## Tech Stack

| Layer | Library / Tool |
|---|---|
| Framework | Flutter (Dart) |
| AI Inference | `tflite_flutter` YOLO TFLite model |
| Audio Playback | `audioplayers` |
| Location / GPS | `geolocator`, `geocoding` |
| Voice Input | `speech_to_text` (Arabic `ar_SA`) |
| Camera | `camera` |
| Secure Storage | `flutter_secure_storage` |
| Screen Wake | `wakelock_plus` |
| Permissions | `permission_handler` |
| Fonts | IBM Plex Sans Arabic |

---

## Project Structure

```
lib/
├── app/                    # Routes, theme, app root
├── core/
│   ├── constants/          # Audio keys, YOLO config, colors, scene map
│   ├── models/             # Detection, SceneDetection, LandmarkPoint
│   ├── services/
│   │   ├── ai/             # YoloService, DetectionDecoder, Adapter, Preprocessor, Throttler
│   │   ├── audio/          # AudioService, SceneService
│   │   └── location/       # LocationService, LocationGuidanceService
│   ├── storage/            # Prefs (secure storage wrapper)
│   └── utils/              # PerfMarkers (performance instrumentation)
├── features/
│   ├── camera/             # CameraScreen, CameraController, DetectionOverlay
│   ├── debug/              # YoloDebugScreen (static-image pipeline tester)
│   ├── onboarding/         # Voice instructions screen
│   ├── settings/           # Settings screen + emergency number editor
│   ├── setup/              # First-run voice setup flow
│   └── splash/             # Splash screen
└── main.dart
```

---

## Getting Started

### Prerequisites

- Flutter SDK `^3.8.1`
- Android SDK (minSdkVersion 21) or Xcode for iOS
- A physical device is recommended camera and audio do not work reliably on simulators

### Setup

```bash
git clone <repo-url>
cd gp_hudai
flutter pub get
flutter run
```

> **Note:** The YOLO model file (`assets/models/yolo_hajj.tflite`) and audio assets must be present before building. They are not committed to the repository due to file size — contact the team for the asset bundle.

### Platforms

| Platform | Status |
|---|---|
| Android | Supported (minSdk 21) |
| iOS | Supported |

---

## Permissions Required

| Permission | Why |
|---|---|
| Camera | Real-time scene detection |
| Microphone | Arabic voice input during setup |
| Location (fine) | GPS-based Arafat zone confirmation |
| Phone | Emergency direct dial |

---

## Team

**Institution:** <!-- University name -->  
**Department:** <!-- Department name -->

| Name | Role |
|---|---|
| <!-- Layan Aljoudi --> | <!-- Role --> |
| <!-- Name --> | <!-- Role --> |
| <!-- Name --> | <!-- Role --> |

---

## License

This project is currently unlicensed. All rights reserved by the authors.
