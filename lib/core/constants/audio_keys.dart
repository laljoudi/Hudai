// lib/core/constants/audio_keys.dart
//
// Single source of truth for every audio asset key used in the app.
// Each key maps 1-to-1 with an audio file via AudioService._assetMap.
// Keys are grouped by category and ordered by descending priority.
// ─────────────────────────────────────────────────────────────────

class AudioKeys {
  AudioKeys._();

  // ── Priority 1 · Safety / Danger ────────────────────────────────
  // Triggered by: person, crowd
  static const String personAhead         = 'personAhead';
  static const String peopleAhead         = 'peopleAhead';
  static const String severeCrowdingAhead = 'severeCrowdingAhead';
  static const String moveCarefully       = 'moveCarefully';
  static const String stopTemporarily     = 'stopTemporarily';

  // ── Priority 2 · Camera Guidance ────────────────────────────────
  // Triggered by: cameraIssue (virtual)
  static const String lensBlocked        = 'lensBlocked';
  static const String pointCameraForward = 'pointCameraForward';

  // ── Priority 3 · Mountain Recognition Status ────────────────────
  // Triggered by: noDetection (virtual), otherMountains, jabalArafah (first sight)
  static const String analyzingScene   = 'analyzingScene';
  static const String arafatRecognized = 'arafatRecognized';
  static const String outOfCoverage    = 'outOfCoverage';

  // ── Priority 4 · Mountain Location ──────────────────────────────
  // Triggered by: jabalArafah (ongoing), arMarker
  static const String arafatAhead = 'arafatAhead';
  static const String markerAhead = 'markerAhead';

  // ── Priority 5 · Movement Confirmation ──────────────────────────
  // Triggered by: jabalArafah (user confirmed walking toward it)
  static const String keepSameDirection = 'keepSameDirection';

  // ── Priority 6 · Distance and Arrival ───────────────────────────
  // Triggered by: location service (GPS) confirming the user entered Arafat zone
  static const String reachedArafat = 'reachedArafat';
}