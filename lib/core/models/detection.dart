/// Represents a single object detected by the YOLO model in a camera frame.
///
/// The YOLO model outputs raw numbers — this class wraps those numbers
/// into a clean, typed object that the rest of the app can use easily.
class Detection {
  /// Class index from the model (0..4 for our 5 classes).
  final int classId;

  /// Human-readable label (e.g. "person", "jabal_arafah").
  final String className;

  /// How confident the model is, from 0.0 to 1.0.
  /// Example: 0.87 means 87% confident.
  final double confidence;

  /// Bounding box in normalized coordinates (0.0 to 1.0).
  /// Format: [centerX, centerY, width, height]
  /// Multiply by image dimensions to get pixel coordinates.
  final List<double> boundingBox;

  const Detection({
    required this.classId,
    required this.className,
    required this.confidence,
    required this.boundingBox,
  });

  /// Convenience getter for the confidence as a percentage string.
  /// Example: 0.87 → "87%"
  String get confidencePercent =>
      '${(confidence * 100).toStringAsFixed(0)}%';

  @override
  String toString() =>
      'Detection($className, $confidencePercent, box=$boundingBox)';
}