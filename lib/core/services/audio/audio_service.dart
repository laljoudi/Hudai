// lib/core/services/audio/audio_service.dart
//
// Responsibilities:
//   1. Map every audio key (from AudioKeys) to its actual file path in assets.
//   2. Play clips via the audioplayers package.
//   3. Expose a stop() method for silencing mid-sequence if needed.
//
// ── How to add a new audio file ─────────────────────────────────
//   1. Drop the .mp3 file into the correct folder under assets/audio/
//   2. Add its key constant in AudioKeys
//   3. Add the corresponding entry in _assetMap below
//   4. Register the folder in pubspec.yaml under flutter > assets
//      (only needed if you are adding a brand-new folder)
//
// ── Asset path convention ────────────────────────────────────────
//   Paths here do NOT include the 'assets/' prefix.
//   audioplayers adds it automatically when using AssetSource.
//
//   Folder structure:
//     audio/detection/safety/               ← Priority 1
//     audio/detection/cameraGuidance/       ← Priority 2
//     audio/detection/mountainStatus/       ← Priority 3
//     audio/detection/mountainLocation/     ← Priority 4
//     audio/detection/movementConfirmation/ ← Priority 5
//     audio/detection/distanceAndArrival/   ← Priority 6
// ─────────────────────────────────────────────────────────────────

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'dart:collection';

import '../../constants/audio_keys.dart';
// ============================================================
// PERFORMANCE TEST [PT-03] [PT-04] — START
// Purpose: Import PerfMarkers for post-splash and audio-response measurement
// Remove this block after testing is complete
// ============================================================
import '../../utils/perf_markers.dart';
// ============================================================
// PERFORMANCE TEST [PT-03] [PT-04] — END
// ============================================================

typedef AssetPlaybackStarted = void Function(String path);

class AudioService {
  AudioService() : _player = AudioPlayer() {
    _configure();
  }

  final AudioPlayer _player;
  final Queue<String> _queue = Queue<String>();
  bool _draining = false;
  int _interruptToken = 0;
  AssetPlaybackStarted? onAssetPlaybackStarted;
  // ============================================================
  // PERFORMANCE TEST [PT-04] — START
  // Purpose: Hold the latency tracker until audio physically starts
  // Remove this block after testing is complete
  // ============================================================
  Stopwatch? _pt04PendingTracker;
  int _pt04WarmUpCount = 0; // first 2 readings are skipped
  // ============================================================
  // PERFORMANCE TEST [PT-04] — END
  // ============================================================

  Future<void> _configure() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
    } catch (e) {
      debugPrint('AudioService: configure error: $e');
    }
  }

  // ── Asset map: key → file path ───────────────────────────────────

  static const Map<String, String> _assetMap = {
    // ── Priority 1 · Safety ──────────────────────────────────────
    AudioKeys.personAhead: 'audio/detection/safety/person_ahead.mp3',
    AudioKeys.peopleAhead: 'audio/detection/safety/people_ahead.mp3',
    AudioKeys.severeCrowdingAhead:
        'audio/detection/safety/severe_crowding_ahead.mp3',
    AudioKeys.moveCarefully: 'audio/detection/safety/move_carefully.mp3',
    AudioKeys.stopTemporarily: 'audio/detection/safety/stop_temporarily.mp3',

    // ── Priority 2 · Camera Guidance ─────────────────────────────
    AudioKeys.lensBlocked: 'audio/detection/camera_guidance/lens_blocked.mp3',
    AudioKeys.pointCameraForward:
        'audio/detection/camera_guidance/point_camera_forward.mp3',

    // ── Priority 3 · Mountain Recognition Status ─────────────────
    AudioKeys.analyzingScene:
        'audio/detection/mountain_recognition_status/analyzing_scene.mp3',
    AudioKeys.arafatRecognized:
        'audio/detection/mountain_recognition_status/arafat_recognized.mp3',

    // ── Priority 4 · Mountain Location ───────────────────────────
    AudioKeys.arafatAhead: 'audio/detection/mountain_location/arafat_ahead.mp3',

    // ── Priority 5 · Movement Confirmation ───────────────────────
    AudioKeys.keepSameDirection:
        'audio/detection/movement_confirmation/keep_same_direction.mp3',

    // ── Priority 6 · Distance and Arrival ────────────────────────
    AudioKeys.reachedArafat:
        'audio/detection/distance_and_arrival/reached_arafat.mp3',

    // ── Other Audio ──────────────────────────────────────────────
    AudioKeys.markerAhead: 'audio/detection/other_audio/marker_ahead.mp3',
    AudioKeys.outOfCoverage: 'audio/detection/other_audio/out_of_coverage.mp3',
  };
  // ── Public API ───────────────────────────────────────────────────

  /// Queues and plays the audio clip mapped to [key].
  ///
  /// Playback is serialized to prevent overlapping voices.
  ///
  /// [perfTracker] is an optional stopwatch started at the detection trigger
  /// point; it is stopped the moment playback physically begins so that
  /// end-to-end audio response latency can be measured (PT-04).
  /// All existing callers omit this parameter — default is null.
  void play(String key, {Stopwatch? perfTracker}) {
    final path = _assetMap[key];

    if (path == null) {
      debugPrint('AudioService: ⚠️ Unknown key "$key" — add it to _assetMap');
      return;
    }

    // Avoid stale long backlogs.
    if (_queue.length >= 6) {
      return;
    }

    // ============================================================
    // PERFORMANCE TEST [PT-04] — START
    // Purpose: Store the tracker so _safePlayAndWait can stop it at playback
    // Remove this block after testing is complete
    // ============================================================
    if (perfTracker != null) _pt04PendingTracker = perfTracker;
    // ============================================================
    // PERFORMANCE TEST [PT-04] — END
    // ============================================================

    _queue.add(path);
    _drainQueue();
    debugPrint('AudioService: 🔊 $key → $path');
  }

  /// Interrupts current playback and plays a raw asset path immediately.
  /// Path should be relative to assets/ (without the assets/ prefix).
  Future<void> playAssetNow(String path) async {
    _interruptToken++;
    _queue.clear();
    // ============================================================
    // PERFORMANCE TEST [PT-04] — START
    // Purpose: Discard any pending tracker so automatic audio (intro,
    //          permission-denied, location) is never measured by PT-04
    // Remove this block after testing is complete
    // ============================================================
    _pt04PendingTracker = null;
    // ============================================================
    // PERFORMANCE TEST [PT-04] — END
    // ============================================================
    await _player.stop();
    await _safePlayAndWait(path, token: _interruptToken);
  }

  Future<void> _drainQueue() async {
    if (_draining) return;
    _draining = true;
    final token = _interruptToken;

    while (_queue.isNotEmpty) {
      if (token != _interruptToken) break;
      final path = _queue.removeFirst();
      await _safePlayAndWait(path, token: token);
    }

    _draining = false;
  }

  Future<void> _safePlayAndWait(String path, {required int token}) async {
    try {
      if (token != _interruptToken) return;
      onAssetPlaybackStarted?.call(path);
      // ============================================================
      // PERFORMANCE TEST [PT-03] — START
      // Purpose: Stop the post-splash stopwatch on the very first audio play
      // Remove this block after testing is complete
      // ============================================================
      if (!PerfMarkers.firstAudioPlayed &&
          PerfMarkers.postSplashWatch.isRunning) {
        PerfMarkers.postSplashWatch.stop();
        PerfMarkers.firstAudioPlayed = true;
        debugPrint(
          '[PT-03] Post-splash init: '
          '${PerfMarkers.postSplashWatch.elapsedMilliseconds} ms',
        );
      }
      // ============================================================
      // PERFORMANCE TEST [PT-03] — END
      // ============================================================
      // ============================================================
      // PERFORMANCE TEST [PT-04] — START
      // Purpose: Log time from detection trigger to audio playback start
      // Remove this block after testing is complete
      // ============================================================
      final pt04 = _pt04PendingTracker;
      if (pt04 != null) {
        pt04.stop();
        _pt04PendingTracker = null;
        if (_pt04WarmUpCount < 2) {
          _pt04WarmUpCount++; // skip first 2 readings (warm-up audio events)
        } else if (pt04.elapsedMilliseconds > 0) {
          debugPrint(
            '[PT-04] Audio response (post-warm-up): ${pt04.elapsedMilliseconds} ms',
          );
        }
      }
      // ============================================================
      // PERFORMANCE TEST [PT-04] — END
      // ============================================================
      await _player.play(AssetSource(path));
      final duration = await _player.getDuration();
      final wait = (duration == null || duration <= Duration.zero)
          ? const Duration(milliseconds: 1400)
          : duration + const Duration(milliseconds: 120);
      await Future.delayed(wait);
    } catch (e) {
      debugPrint('AudioService: 🔊 Error playing "$path": $e');
    }
  }

  /// Stops the current clip immediately.
  Future<void> stop() async {
    _queue.clear();
    await _player.stop();
  }

  /// Releases player resources.
  /// Call this in the camera screen's dispose().
  Future<void> dispose() async {
    onAssetPlaybackStarted = null;
    await _player.dispose();
  }
}
