import 'package:gp_hudai/core/models/detection.dart';
import 'package:gp_hudai/core/models/scene_detection.dart';

/// Adapter — converts our YOLO Detection objects into SceneDetection
/// objects that the SceneService expects.
///
/// This is the bridge between two parallel architectures:
///   - Our YOLO pipeline produces: Detection (className: String, boundingBox)
///   - Her audio pipeline expects:  SceneDetection (sceneClass: enum)
///
/// Both designs are valid; this adapter lets them work together cleanly
/// without rewriting either side.
class DetectionToSceneAdapter {
  const DetectionToSceneAdapter();

  /// Converts a list of Detection objects into a list of SceneDetection.
  /// Drops any detection whose label cannot be matched to a SceneClass.
  List<SceneDetection> adapt(List<Detection> detections) {
    final result = <SceneDetection>[];

    for (final detection in detections) {
      final sceneClass = sceneClassFromLabel(detection.className);

      // Skip if the label couldn't be matched (returns noDetection by default).
      // We only forward real model classes to SceneService.
      if (sceneClass == SceneClass.noDetection) {
        continue;
      }

      result.add(SceneDetection(
        sceneClass: sceneClass,
        confidence: detection.confidence,
      ));
    }

    return result;
  }
}