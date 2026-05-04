import 'package:gp_hudai/core/models/detection.dart';

/// Snapshot of the camera screen's current state.
///
/// The controller updates instances of this class.
/// The view (camera_screen.dart) reads it and redraws when it changes.
///
/// This is an IMMUTABLE class — every state change creates a new instance.
/// This pattern prevents subtle bugs and makes the state changes explicit.
class CameraState {
  /// True when the camera is initialized and showing the preview.
  final bool isCameraReady;

  /// True when the AI model has been loaded.
  final bool isAiReady;

  /// True while AI is currently processing a frame.
  final bool isInferring;

  /// The most recent detections from the AI (empty if nothing detected).
  final List<Detection> currentDetections;

  /// Total number of frames the AI has successfully processed.
  /// Useful for debugging — shows the pipeline is alive.
  final int framesProcessed;

  /// The last error message, or null if no error.
  /// Display in debug mode only.
  final String? lastError;

  const CameraState({
    this.isCameraReady     = false,
    this.isAiReady         = false,
    this.isInferring       = false,
    this.currentDetections = const [],
    this.framesProcessed   = 0,
    this.lastError,
  });

  /// Creates a copy of this state with some fields changed.
  /// Used by the controller to update specific properties.
  ///
  /// Example:
  ///   final newState = oldState.copyWith(isInferring: true);
  CameraState copyWith({
    bool?            isCameraReady,
    bool?            isAiReady,
    bool?            isInferring,
    List<Detection>? currentDetections,
    int?             framesProcessed,
    String?          lastError,
    bool             clearError = false,
  }) {
    return CameraState(
      isCameraReady:     isCameraReady     ?? this.isCameraReady,
      isAiReady:         isAiReady         ?? this.isAiReady,
      isInferring:       isInferring       ?? this.isInferring,
      currentDetections: currentDetections ?? this.currentDetections,
      framesProcessed:   framesProcessed   ?? this.framesProcessed,
      lastError:         clearError ? null : (lastError ?? this.lastError),
    );
  }

  /// Convenience: returns true if the system is fully ready to detect.
  bool get isReadyForInference => isCameraReady && isAiReady;

  @override
  String toString() =>
      'CameraState(camera=$isCameraReady, ai=$isAiReady, '
      'inferring=$isInferring, detections=${currentDetections.length}, '
      'frames=$framesProcessed)';
}