/// Configuration constants for the YOLO Hajj model.
///
/// All "magic numbers" related to YOLO live here, in one place.
/// If the model is retrained with different settings, only this file
/// needs to be updated.
class YoloConfig {
  YoloConfig._();

  // ── Model file ───────────────────────────────────────────────────────
  /// Path to the TFLite model file (relative to assets/).
  static const String modelPath = 'assets/models/yolo_hajj.tflite';

  /// Path to the labels file (relative to assets/).
  static const String labelsPath = 'assets/models/labels.txt';

  // ── Input format ─────────────────────────────────────────────────────
  /// Model expects square 640×640 input images.
  static const int inputSize = 640;

  /// Number of color channels (3 = RGB).
  static const int inputChannels = 3;

  // ── Output format ────────────────────────────────────────────────────
  /// Number of classes the model can detect.
  /// Order matters! Must match labels.txt exactly:
  ///   0: jabal_arafah
  ///   1: ar_marker
  ///   2: person
  ///   3: other_mountains
  ///   4: crowd
  static const int numClasses = 5;

  /// Hardcoded class labels (also loaded from labels.txt at runtime).
  static const List<String> labels = [
    'jabal_arafah',
    'ar_marker',
    'person',
    'other_mountains',
    'crowd',
  ];

  // ── Detection thresholds ─────────────────────────────────────────────
  /// Minimum confidence to keep a detection.
  /// Detections below this are discarded.
  /// 0.5 = 50% confident.
  static const double confidenceThreshold = 0.35;

  /// IoU (Intersection over Union) threshold for NMS.
  /// When two boxes overlap by more than this, the lower-confidence
  /// one is removed. 0.5 = 50% overlap.
  static const double nmsThreshold = 0.5;

  /// Maximum number of detections to keep per frame.
  /// Prevents UI / audio flooding if many objects are detected.
  static const int maxDetections = 10;

  // ── Performance ──────────────────────────────────────────────────────
  /// Target inference rate (frames per second).
  /// 3 FPS = inference every ~333ms.
  /// Higher = more responsive but more battery / heat.
  static const int targetFps = 2;

  /// Calculated milliseconds between inferences.
  static int get throttleMs => (1000 / targetFps).round();
}
