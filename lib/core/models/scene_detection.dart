// lib/core/models/scene_detection.dart
//
// Defines all detectable scene classes (real model output + virtual
// edge-case classes) and the SceneDetection result wrapper.
// ─────────────────────────────────────────────────────────────────

enum SceneClass {
  // ── Real model classes ───────────────────────────────────────
  person,
  crowd,
  jabalArafah,
  arMarker,
  otherMountains,

  // ── Virtual classes (set by SceneService, not the model) ─────
  noDetection,  // model returned an empty list
  cameraIssue,  // feed is blocked / unusable
}

/// Converts a raw label string from the model into a [SceneClass].
SceneClass sceneClassFromLabel(String label) {
  switch (label.toLowerCase()) {
    case 'person':
      return SceneClass.person;
    case 'crowd':
      return SceneClass.crowd;
    case 'jabal_arafah':
      return SceneClass.jabalArafah;
    case 'ar_marker':
      return SceneClass.arMarker;
    case 'other_mountains':
      return SceneClass.otherMountains;
    default:
      return SceneClass.noDetection;
  }
}

/// A single detection result for one inference frame.
class SceneDetection {
  final SceneClass sceneClass;

  /// Confidence score in [0.0 – 1.0].
  final double confidence;

  const SceneDetection({
    required this.sceneClass,
    required this.confidence,
  });

  @override
  String toString() =>
      'SceneDetection(class: $sceneClass, '
      'confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
}