// lib/core/constants/scene_audio_map.dart
//
// Maps every SceneClass to a [SceneAudioProfile] that carries:
//   • An [AudioCategory]  — drives priority comparison (lower index = higher priority)
//   • An [audioSequence]  — ordered list of keys played when this scene wins
//
// ── Design rules ────────────────────────────────────────────────
//
// 1. ONE RESPONSIBILITY PER PROFILE
//    Each profile's audioSequence must only contain keys that belong
//    to its own AudioCategory. Mixing categories inside one sequence
//    was the root cause of the previous "dump everything at once" bug.
//
// 2. JABAL ARAFAH IS A MULTI-STAGE JOURNEY
//    Detecting jabalArafah is not one event — it unfolds over time:
//      Stage A · First sight  → mountainStatus  (arafatRecognized)
//      Stage B · Navigating   → mountainLocation (arafatAhead)
//      Stage C · Walking      → movementConfirmation (keepSameDirection)
//      Stage D · Arrival      → distanceAndArrival — fired by the location
//                               service (GPS), not the model, because GPS
//                               is more reliable for "you arrived".
//    SceneService advances through these stages using [JabalArafahStage].
//    Each stage maps to its own profile in [jabalArafahStageMap].
//
// 3. AR MARKER IS INDEPENDENT
//    arMarker has its own mountainLocation profile. When jabalArafah AND
//    arMarker are detected simultaneously, SceneService's priority resolver
//    picks jabalArafah (same category, earlier enum index).
//
// 4. COOLDOWN IS THE SERVICE'S JOB
//    This file is pure data. SceneService decides *when* to play;
//    this file only decides *what* to play.
//
// Priority table (AudioCategory.index):
//   0 · safety               → person, crowd
//   1 · cameraGuidance       → cameraIssue
//   2 · mountainStatus       → noDetection, otherMountains, jabalArafah stage A
//   3 · mountainLocation     → jabalArafah stage B, arMarker
//   4 · movementConfirmation → jabalArafah stage C
//   5 · distanceAndArrival   → fired externally by the location service
// ─────────────────────────────────────────────────────────────────

import '../models/scene_detection.dart';
import 'audio_keys.dart';

// ── Category enum (index = priority rank) ───────────────────────

enum AudioCategory {
  safety,                // 0 — highest priority
  cameraGuidance,        // 1
  mountainStatus,        // 2
  mountainLocation,      // 3
  movementConfirmation,  // 4
  distanceAndArrival,    // 5 — lowest priority
}

// ── Profile ──────────────────────────────────────────────────────

class SceneAudioProfile {
  final AudioCategory category;

  /// Audio keys played in this exact order when this profile wins.
  /// All keys must belong to [category].
  final List<String> audioSequence;

  const SceneAudioProfile({
    required this.category,
    required this.audioSequence,
  });
}

// ── Main scene map (model detections → profiles) ────────────────

const Map<SceneClass, SceneAudioProfile> sceneAudioMap = {

  // ── person → Safety ───────────────────────────────────────────
  // A single person is ahead. Warn and advise caution.
  SceneClass.person: SceneAudioProfile(
    category: AudioCategory.safety,
    audioSequence: [
      AudioKeys.personAhead,
      AudioKeys.moveCarefully,
    ],
  ),

  // ── crowd → Safety ────────────────────────────────────────────
  // Dense crowd detected. Higher urgency than a single person.
  SceneClass.crowd: SceneAudioProfile(
    category: AudioCategory.safety,
    audioSequence: [
      AudioKeys.peopleAhead,
      AudioKeys.severeCrowdingAhead,
      AudioKeys.moveCarefully,
      AudioKeys.stopTemporarily,
    ],
  ),

  // ── cameraIssue → Camera Guidance ─────────────────────────────
  // Feed is blocked or unusable. Tell the user to reposition.
  SceneClass.cameraIssue: SceneAudioProfile(
    category: AudioCategory.cameraGuidance,
    audioSequence: [
      AudioKeys.lensBlocked,
      AudioKeys.pointCameraForward,
    ],
  ),

  // ── noDetection → Mountain Status ─────────────────────────────
  // Model returned nothing. Scene is unclear.
  // Note: pointCameraForward is NOT played here to avoid repeating
  // it every frame. It is reserved for cameraIssue only.
  // SceneService throttles this profile with a 15 s cooldown.
  SceneClass.noDetection: SceneAudioProfile(
    category: AudioCategory.mountainStatus,
    audioSequence: [
      AudioKeys.analyzingScene,
    ],
  ),

  // ── otherMountains → Mountain Status ──────────────────────────
  // A mountain was detected but it is not Jabal Arafah.
  SceneClass.otherMountains: SceneAudioProfile(
    category: AudioCategory.mountainStatus,
    audioSequence: [
      AudioKeys.outOfCoverage,
    ],
  ),

// ── jabalArafah → scene recognition ─────────────────────────────
// Jabal Arafah is handled like the other scene classes.
// When the model detects this scene, the related audio sequence is played.
// No navigation stages, GPS, or location-based arrival logic are used.
  SceneClass.jabalArafah: SceneAudioProfile(
    category: AudioCategory.mountainStatus,
    audioSequence: [
      AudioKeys.arafatRecognized,
      AudioKeys.arafatAhead,
      AudioKeys.keepSameDirection,
      AudioKeys.reachedArafat,
      AudioKeys.markerAhead,
    ],
  ),

  // ── arMarker → Mountain Location ──────────────────────────────
  // An AR navigation marker is visible. Confirm its presence.
  SceneClass.arMarker: SceneAudioProfile(
    category: AudioCategory.mountainLocation,
    audioSequence: [
      AudioKeys.markerAhead,
    ],
  ),
};