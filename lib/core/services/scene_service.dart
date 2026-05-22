// lib/core/services/scene_service.dart
//
// Responsibilities:
//   1. Receives per-frame detections → resolves the highest-priority profile.
//   2. Enforces a per-category cooldown to prevent audio flooding.
//   3. Plays audio sequences via AudioService.
//   4. Stores the last played sequence for repeatLastInstruction().
//
// ── Cooldown strategy ───────────────────────────────────────────
//   Safety alerts       →  5 s
//   Camera guidance     → 10 s
//   Mountain status     → 15 s
//   Mountain location   → 12 s
//   Movement confirm    → 20 s
//   Distance / arrival  → 15 s
//
// Note:
//   This service only depends on scene analysis from the camera.
//   It does not use GPS, location service, or Jabal Arafah stages.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../constants/audio_keys.dart';
import '../constants/scene_audio_map.dart';
import '../models/scene_detection.dart';
import 'audio_service.dart';

class SceneService {
  SceneService({required AudioService audioService})
      : _audioService = audioService;

  final AudioService _audioService;

  // ── Confidence filtering ─────────────────────────────────────────

  /// Minimum confidence required to trust a detection.
  static const double _confidenceThreshold = 0.55;

  // ── Cooldown table (milliseconds per category) ───────────────────

  static const Map<AudioCategory, int> _cooldownMs = {
    AudioCategory.safety: 5000,
    AudioCategory.cameraGuidance: 10000,
    AudioCategory.mountainStatus: 15000,
    AudioCategory.mountainLocation: 12000,
    AudioCategory.movementConfirmation: 20000,
    AudioCategory.distanceAndArrival: 15000,
  };

  /// Timestamp (ms since epoch) of the last play per category.
  final Map<AudioCategory, int> _lastPlayedAt = {};

  // ── Repeat feature ───────────────────────────────────────────────

  /// The full sequence that was last sent to AudioService.
  /// Null until at least one sequence has been played.
  List<String>? _lastPlayedSequence;
  String? _lastPlayedKey;
  bool? _insideCoverage;
  /// True if there's a previous instruction available to replay.
  bool get hasLastInstruction =>
      _lastPlayedSequence != null && _lastPlayedSequence!.isNotEmpty;

  /// Injects the latest GPS coverage context (inside/outside Arafat zone).
  ///
  /// When outside coverage, location-only "arrival" lines are filtered out
  /// from model-driven sequences to avoid contradictory guidance.
  void setCoverageStatus(bool inside) {
    _insideCoverage = inside;
  }

  // ── Public API ───────────────────────────────────────────────────

  /// Process a list of [SceneDetection]s from one inference frame.
  ///
  /// - Filters out low-confidence detections.
  /// - If no reliable detections remain, defers to [processNoDetection].
  /// - Resolves the highest-priority scene profile.
  /// - Plays the related audio sequence if cooldown allows it.
  void processDetections(List<SceneDetection> detections) {
    final reliableDetections = detections
        .where((d) => d.confidence >= _confidenceThreshold)
        .toList();

    if (reliableDetections.isEmpty) {
      processNoDetection();
      return;
    }

    final profile = _resolveHighestPriority(reliableDetections);
    if (profile != null) {
      _tryPlay(profile);
    }
  }

  /// Call when the model returns no detections for a frame.
  void processNoDetection() {
    final profile = sceneAudioMap[SceneClass.noDetection];
    if (profile != null) {
      _tryPlay(profile);
    }
  }

  /// Call when the camera feed is confirmed blocked or unusable.
  void processCameraIssue() {
    final profile = sceneAudioMap[SceneClass.cameraIssue];
    if (profile != null) {
      _tryPlay(profile);
    }
  }

  /// Replays only the last played clip.
  /// Does nothing if no clip has been played yet.
  void repeatLastInstruction() {
    final last = _lastPlayedKey;
    if (last != null && last.isNotEmpty) {
      _audioService.play(last);
    }
  }

  /// Stops any currently playing scene audio.
  Future<void> stop() async {
    await _audioService.stop();
  }

  // ── Priority resolution (private) ────────────────────────────────

  SceneAudioProfile? _resolveHighestPriority(List<SceneDetection> detections) {
    SceneAudioProfile? winner;

    for (final detection in detections) {
      final profile = sceneAudioMap[detection.sceneClass];
      if (profile == null) continue;

      // Lower enum index = higher priority.
      if (winner == null || profile.category.index < winner.category.index) {
        winner = profile;
      }
    }

    return winner;
  }

  // ── Cooldown-gated playback (private) ────────────────────────────

  /// Attempts to play [profile].
  /// Returns true if played, false if throttled by cooldown.
  bool _tryPlay(SceneAudioProfile profile) {
    final cooldown = _cooldownMs[profile.category] ?? 10000;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastPlayed = _lastPlayedAt[profile.category] ?? 0;

    if (now - lastPlayed < cooldown) {
      return false;
    }

    final played = _playSequence(profile.audioSequence);
    if (played) {
      _lastPlayedAt[profile.category] = now;
    }
    return played;
  }

  // ── Playback (private) ───────────────────────────────────────────

  bool _playSequence(List<String> audioKeys) {
    if (audioKeys.isEmpty) return false;

    final effectiveSequence = _filterByCoverage(audioKeys);
    if (effectiveSequence.isEmpty) return false;

    for (final key in effectiveSequence) {
      _audioService.play(key);
    }

    // Store an immutable copy for the repeat feature.
    _lastPlayedSequence = List.unmodifiable(effectiveSequence);
    _lastPlayedKey = effectiveSequence.last;

    debugPrint('SceneService: playing ${effectiveSequence.join(' → ')}');
    return true;
  }

  List<String> _filterByCoverage(List<String> audioKeys) {
    // If coverage isn't confirmed yet OR user is outside, do not play the
    // "reached Arafat" line from model detections.
    if (_insideCoverage != true) {
      return audioKeys
          .where((k) => k != AudioKeys.reachedArafat)
          .toList(growable: false);
    }
    return audioKeys;
  }
}
