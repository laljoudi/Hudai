# GP Hudai - Project Guide

A complete reference to every file in the codebase: what it does and how it
connects to the rest. Read this before touching any file you have not seen before.

---

## What the app does

Hudai is an Arabic-language assistive app for Hajj pilgrims. It uses an
on-device YOLOv8 model to recognize scenes (people, crowds, Jabal Arafah,
AR markers, other mountains), combines that with GPS coverage, and gives
spoken Arabic guidance to help blind and low-vision users navigate safely
toward Jabal Arafah during Arafat day.

The UI is camera-first and tap-driven. Four corner buttons cover Settings,
Emergency Call, Replay, and Location. No reading or fine motor control is
required during use.

---

## User flow

```
Splash (6 s animation)
  |
  +-- no saved number --> Voice Instructions --> Setup --> Camera
  |
  +-- has saved number ---------------------------------> Camera
                                                           |
                              +----------------------------+
                              |
                    Settings (top-left tap)
                    Emergency Call (top-right tap)
                    Replay (bottom-left tap)
                    Location (bottom-right tap)
```

---

## File-by-file reference

### `lib/main.dart`
Entry point. Calls `WidgetsFlutterBinding.ensureInitialized()`, sets portrait
orientation, then runs `HudaiApp`.

---

### `lib/app/`

| File | Purpose |
|---|---|
| `hudai_app.dart` | Root `MaterialApp`. Wires theme and named routes. |
| `app_routes.dart` | All route name constants (splash, camera, settings, etc.). |
| `app_theme.dart` | Global `ThemeData` with IBM Plex Sans Arabic as default font. |

---

### `lib/core/constants/`

| File | Purpose |
|---|---|
| `colors.dart` | `AppColors` - all brand colors used across every screen. |
| `yolo_config.dart` | `YoloConfig` - model input size (640), confidence threshold, target FPS (2), class count. |
| `audio_keys.dart` | String constants for every audio file key used by SceneService. |
| `scene_audio_map.dart` | Maps each detected scene label to its ordered audio sequence and priority. |
| `location_constants.dart` | GPS coordinates and radii for Arafat zone, Namirah mosque, and Jabal Arafah. |

---

### `lib/core/models/`

| File | Purpose |
|---|---|
| `detection.dart` | `Detection` - a single YOLO bounding box (label, confidence, rect). |
| `scene_detection.dart` | `SceneDetection` - wraps a list of `Detection` objects with a timestamp. |
| `landmark_point.dart` | `LandmarkPoint` and `LandmarkCircle` - lat/lng + radius used by location logic. |

---

### `lib/core/services/ai/`

| File | Purpose |
|---|---|
| `yolo_service.dart` | Loads the TFLite model, runs inference on a raw image buffer, returns raw output tensor. |
| `frame_preprocessor.dart` | Converts a `CameraImage` to the 640x640 RGB float buffer the model expects. |
| `detection_decoder.dart` | Parses the raw model output tensor into a list of `Detection` objects. |
| `inference_throttler.dart` | Rate-limits inference calls to `YoloConfig.targetFps` to prevent overheating. |
| `detection_to_scene_adapter.dart` | Converts `Detection` list to a `SceneDetection` and maps it to an audio sequence via `scene_audio_map`. |

**Pipeline order:**
```
CameraImage
  --> FramePreprocessor  (resize + normalize)
  --> YoloService        (TFLite inference)
  --> DetectionDecoder   (parse tensor)
  --> InferenceThrottler (rate limit)
  --> DetectionToSceneAdapter (scene label + audio key)
  --> SceneService       (play audio)
```

---

### `lib/core/services/audio/`

| File | Purpose |
|---|---|
| `audio_service.dart` | Queued audio player. Supports interrupt (high-priority) and queued playback. Owns the `audioplayers` instance. |
| `scene_service.dart` | Sits above `AudioService`. Applies per-category cooldowns and priority rules before deciding whether to play a scene audio clip. |

**Priority levels (1 = highest):**

| Level | Category |
|---|---|
| 1 | Safety (crowd / person) |
| 2 | Camera guidance (blocked lens) |
| 3 | Mountain recognition status |
| 4 | Mountain location |
| 5 | Movement confirmation |
| 6 | Distance and arrival |

---

### `lib/core/services/location/`

| File | Purpose |
|---|---|
| `location_service.dart` | Thin wrapper around `geolocator`. Provides `getCurrentPosition`, `isInsideCircle`, `distanceToPoint`. |
| `location_guidance_service.dart` | Takes a GPS position (or demo override) and builds a `LocationGuidanceResult` with the correct audio sequence. Also owns `kDemoLocationMode` - a mutable global that `DemoSwitcher` writes to at runtime. |

---

### `lib/core/services/`

| File | Purpose |
|---|---|
| `permission_service.dart` | Requests and checks camera, microphone, location, and phone permissions. |
| `phone_service.dart` | Wraps `flutter_phone_direct_caller` to place an emergency call. |

---

### `lib/core/storage/`

| File | Purpose |
|---|---|
| `prefs.dart` | `Prefs` class - reads/writes the emergency number (via `flutter_secure_storage`) and the camera-intro-heard flag (via `shared_preferences`). |

---

### `lib/core/utils/`

| File | Purpose |
|---|---|
| `perf_markers.dart` | Stopwatch instances for performance tests PT-01 through PT-04. Do not remove or rename these markers - they are referenced in the project report. |
| `saudi_number_parser.dart` | Validates Saudi mobile numbers (10 digits, starts with 05). Used by Setup and Prefs. |

---

### `lib/features/splash/`

| File | Purpose |
|---|---|
| `splash_screen.dart` | 6-second animated intro (logo + waves). Checks `Prefs.hasValidEmergencyNumber()` and routes to Voice Instructions or Camera. |

---

### `lib/features/onboarding/`

| File | Purpose |
|---|---|
| `voice_instructions_screen.dart` | Plays the Arabic onboarding audio sequence. Advances to Setup when done. |

---

### `lib/features/setup/`

| File | Purpose |
|---|---|
| `setup_screen.dart` | UI for first-run emergency number entry. |
| `setup_controller.dart` | Drives the voice-entry flow: plays prompts, listens via `speech_to_text`, validates and saves the number, then navigates to Camera. |

---

### `lib/features/camera/`

| File | Purpose |
|---|---|
| `camera_screen.dart` | UI only. Displays the live camera feed, detection overlay, and four glassy corner buttons. Forwards taps to `CameraController`. Long-pressing the middle of the screen opens the demo location switcher. |
| `camera_controller.dart` | The brain of the app. Owns the camera lifecycle, AI pipeline, GPS coverage, audio playback, and emergency-call double-tap logic. |
| `camera_state.dart` | Immutable state snapshot used by `CameraController` to notify the view. |
| `detection_overlay.dart` | Draws bounding boxes over the camera preview using a `CustomPainter`. |
| `yolo_debug_screen.dart` | Developer tool. Runs the full AI pipeline on a static test image so the model can be verified without a live camera. |

**Key constants in `camera_controller.dart`:**

| Constant | Effect |
|---|---|
| `kForceMockCamera` | Set to `true` to skip real camera init (useful on simulators). Compile-time only. |
| `kDemoCoverageMode` | Forces the GPS coverage state (off / inside Arafat / outside Arafat). Compile-time only. |

**Performance test blocks (do not remove):**

| Marker | What it measures |
|---|---|
| PT-01 | YOLOv8 inference latency (mean over 30 samples after 10 warm-up frames) |
| PT-02 | Inference throughput in FPS over a 60-second window |
| PT-03 | Post-splash to first-audio latency |
| PT-04 | Audio queue drain time |

---

### `lib/features/settings/`

| File | Purpose |
|---|---|
| `settings_screen.dart` | Displays the current emergency number. Tapping anywhere opens the emergency edit screen. Top-right corner goes back. |
| `settings_controller.dart` | Plays the settings audio sequence and manages the `audioplayers` instance for this screen. |
| `settings_emergency_screen.dart` | UI for editing the emergency number after first-run setup. |
| `settings_emergency_controller.dart` | Voice-entry flow for changing the emergency number (mirrors setup flow). |

---

### `lib/features/debug/`

| File | Purpose |
|---|---|
| `demo_switcher.dart` | `showDemoSwitcherModal(context)` - opens a bottom sheet listing all `DemoLocationMode` values. Selecting one immediately updates `kDemoLocationMode` in memory so the next location tap uses it. Triggered by long-pressing the middle of the camera screen. |

---

## Important constraints

- **PT markers** - do not rename or remove `PT-01` through `PT-04` comment blocks. They are cited in the project report.
- **CameraController public API** - do not change the public method signatures (`initialize`, `onEmergencyTap`, `onLocationTap`, `onReplayInstructionsTap`, `suspendForSettings`, `resumeFromSettings`). The view depends on all of them.
- **Comment style** - no em dashes in code comments. Use commas or parentheses instead.
- **No session history in comments** - describe files as if they always existed.
