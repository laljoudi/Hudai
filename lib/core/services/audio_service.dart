// lib/core/services/audio_service.dart
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

import '../constants/audio_keys.dart';

class AudioService {
  AudioService() : _player = AudioPlayer() {
    _configure();
  }

  final AudioPlayer _player;
  final Queue<String> _queue = Queue<String>();
  bool _draining = false;
  int _interruptToken = 0;
  String? _lastPlayedPath;
  int _lastPlayedAtMs = 0;

  String? get lastPlayedPath => _lastPlayedPath;
  int get lastPlayedAtMs => _lastPlayedAtMs;

  Future<void> _configure() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
    } catch (e) {
      debugPrint('AudioService: configure error: $e');
    }
  }

  // ── Asset map: key → file path ───────────────────────────────────
  //
  // 👇 THIS IS WHERE YOU SET YOUR AUDIO FILE PATHS.
  //
  // Change the right-hand side of each entry to match the actual
  // filename of your audio clip inside assets/.
  //
  // Example:
  //   AudioKeys.personAhead: 'audio/detection/safety/person_ahead.mp3',
  //                                                   ^^^^^^^^^^^^^^^^
  //                                              ← change this part only

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
  void play(String key) {
    final path = _assetMap[key];

    if (path == null) {
      debugPrint('AudioService: ⚠️ Unknown key "$key" — add it to _assetMap');
      return;
    }

    // Avoid stale long backlogs.
    if (_queue.length >= 6) {
      return;
    }

    _queue.add(path);
    _drainQueue();
    debugPrint('AudioService: 🔊 $key → $path');
  }

  /// Interrupts current playback and plays a raw asset path immediately.
  /// Path should be relative to assets/ (without the assets/ prefix).
  Future<void> playAssetNow(String path) async {
    _interruptToken++;
    _queue.clear();
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
      _lastPlayedPath = path;
      _lastPlayedAtMs = DateTime.now().millisecondsSinceEpoch;
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
    await _player.dispose();
  }
}
