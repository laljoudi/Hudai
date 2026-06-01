# Tap Feedback Overlay — Implementation Report

A demo-only visual press feedback (ripple + glow) was added on top of every tap
zone in the app. It is purely visual: no tap behaviour, callback, or audio logic
was changed.

## New widget

- **`lib/core/widgets/tap_feedback_overlay.dart`** — `TapFeedbackOverlay`, a
  `StatefulWidget` that wraps any tap zone. On pointer-down it spawns a brief
  ripple + glow at the touch point using an `AnimationController` +
  `CustomPainter`. Effects use the project cyan accent (`#70F0FF`) at 60–70%
  opacity and complete in 280 ms.
  - The effect is driven by a **`Listener` (`onPointerDown`)**, which never joins
    the gesture arena. The wrapped child's own `GestureDetector`
    (onTap / onDoubleTap / onLongPress) keeps receiving every event exactly as
    before — behaviour is untouched.
  - Multiple simultaneous taps are supported (each tap gets its own animation;
    controllers are disposed on completion and in `dispose()`).

## Configuration / toggle

- **`lib/core/constants/tap_feedback_config.dart`** — new config file following
  the project's existing top-level `k`-prefixed global convention (e.g.
  `kDemoLocationMode`):
  - `bool kShowTapFeedback = true;` — master on/off switch.
  - `kTapFeedbackColorValue` (`0xFF70F0FF`) — accent colour.
  - `kTapFeedbackDuration` (`280 ms`) — total effect duration (< 300 ms).

### How to toggle on/off

Open `lib/core/constants/tap_feedback_config.dart` and set:

```dart
bool kShowTapFeedback = true;   // demo: show ripple + glow
bool kShowTapFeedback = false;  // production: pass straight through, no visuals
```

When `false`, `TapFeedbackOverlay.build` returns its `child` unchanged — zero
visual effect and zero overhead. No code needs to be removed.

## Tap zones wrapped

| File | Line (approx) | Tap zone |
|------|------|----------|
| `lib/features/camera/camera_screen.dart` | ~245 | Middle dead-zone (demo-switcher long-press) |
| `lib/features/camera/camera_screen.dart` | ~280 | `_tapZone` helper → Settings, Emergency, Replay, Location quadrants (4 zones) |
| `lib/features/settings/settings_screen.dart` | ~100 | Full-screen "edit emergency" tap zone |
| `lib/features/settings/settings_screen.dart` | ~138 | Top-right back tap zone |
| `lib/features/settings/settings_screen.dart` | ~216 | `_SettingsTile` option card |
| `lib/features/settings/settings_emergency_screen.dart` | ~128 | Voice-mode tap zone (single / double / long press) |
| `lib/features/settings/settings_emergency_screen.dart` | ~525 | `_GlowingSaveButton` (manual save) |
| `lib/features/setup/setup_screen.dart` | ~144 | Voice-mode tap zone (single / double / long press) |
| `lib/features/setup/setup_screen.dart` | ~618 | `_GlowingSaveButton` (manual save) |
| `lib/features/onboarding/voice_instructions_screen.dart` | ~215 | Full-screen "tap to proceed" zone |

On the camera screen the four quadrants (Settings top-left, Emergency call
double-tap target top-right, Replay bottom-left, Location bottom-right) all go
through the single `_tapZone` helper, so wrapping it covers all four.

## Caveats / limitations

- **Voice-mode keys moved to the wrapper.** In `setup_screen.dart` and
  `settings_emergency_screen.dart` the voice-mode `GestureDetector` carried a
  `ValueKey('voice')` used by an `AnimatedSwitcher`. The key was moved onto the
  `TapFeedbackOverlay` wrapper so the switcher's voice↔manual transition still
  works. No test references these keys (tests are unit-only), and the suite
  still passes.
- **Debug demo switcher not wrapped.** `lib/features/debug/demo_switcher.dart`
  uses a Material `ListTile` (not a `GestureDetector`) inside a bottom-sheet.
  `ListTile` already shows a Material ink ripple, and it is a debug-only sheet
  not part of the demo flow, so it was intentionally left as-is.
- **Effect renders on top of the wrapped subtree only.** Because the overlay is
  a `Positioned.fill` painter inside the wrapper's `Stack`, the ripple is
  clipped to the wrapped zone's bounds. For the full-screen zones this is the
  whole screen; for smaller buttons it is the button's box.
- **Toggle is compile-time-ish.** `kShowTapFeedback` is a mutable global; flip
  it and hot-restart (or rebuild). There is no runtime UI switch.
- **Not covered by automated tests** per the task constraint (no test files were
  changed). Verify visually by running the app with `kShowTapFeedback = true`.
- All existing unit tests (17) still pass; `flutter analyze` reports only the
  pre-existing `withOpacity` deprecation infos shared with the rest of the
  codebase — no new errors or warnings.
