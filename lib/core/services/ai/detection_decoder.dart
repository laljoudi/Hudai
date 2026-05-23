import 'dart:math' as math;

import 'package:gp_hudai/core/constants/yolo_config.dart';
import 'package:gp_hudai/core/models/detection.dart';

/// Decodes raw YOLOv8 model output into clean Detection objects.
///
/// YOLOv8 output format: [1, 4 + numClasses, 8400]
///   - 8400 candidate detections per image
///   - For each candidate: 4 box coordinates + class probabilities
///
/// Pipeline:
///   raw output → parse 8400 candidates → filter by confidence → NMS → final list
class DetectionDecoder {
  const DetectionDecoder();

  /// Decodes a raw YOLOv8 output tensor into a list of Detection objects.
  ///
  /// [rawOutput] should be the flattened 1D output from the interpreter.
  /// Expected length: (4 + numClasses) * 8400 = 9 * 8400 = 75,600 numbers
  List<Detection> decode(List<double> rawOutput) {
    // 1. Parse the raw output into candidate detections
    final candidates = _parseCandidates(rawOutput);

    // 2. Filter by confidence threshold
    final filtered = candidates
        .where((c) => c.confidence >= YoloConfig.confidenceThreshold)
        .toList();

    // 3. Apply Non-Maximum Suppression (remove overlapping duplicates)
    final finalDetections = _applyNms(filtered);

    // 4. Cap at maxDetections to prevent overload
    if (finalDetections.length > YoloConfig.maxDetections) {
      finalDetections.sort((a, b) => b.confidence.compareTo(a.confidence));
      return finalDetections.take(YoloConfig.maxDetections).toList();
    }

    return finalDetections;
  }

  /// Parses raw output into Detection objects (no filtering yet).
  ///
  /// YOLOv8 output layout: [4 box coords + N class scores] per anchor
  /// Total anchors: 8400
  List<Detection> _parseCandidates(List<double> rawOutput) {
    const numAnchors = 8400;
    final numClasses = YoloConfig.numClasses;
    

    final candidates = <Detection>[];

    // YOLOv8 output is transposed: stored column-major
    // Layout in memory: [all_x][all_y][all_w][all_h][all_c0][all_c1]...
    for (int i = 0; i < numAnchors; i++) {
      // Read box coordinates (normalized 0..1)
      final cx = rawOutput[0 * numAnchors + i];
      final cy = rawOutput[1 * numAnchors + i];
      final w  = rawOutput[2 * numAnchors + i];
      final h  = rawOutput[3 * numAnchors + i];

      // Find the class with highest score
      double bestScore = 0.0;
      int    bestClass = 0;

      for (int c = 0; c < numClasses; c++) {
        final rawScore = rawOutput[(4 + c) * numAnchors + i];
        // Some TFLite exports return logits instead of probabilities.
        // If score is outside [0,1], convert using sigmoid.
        final score = (rawScore < 0.0 || rawScore > 1.0)
            ? _sigmoid(rawScore)
            : rawScore;
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }

      // Skip if confidence is too low (early filter for performance)
      if (bestScore < YoloConfig.confidenceThreshold) continue;

      candidates.add(Detection(
        classId:     bestClass,
        className:   YoloConfig.labels[bestClass],
        confidence:  bestScore,
        boundingBox: [cx, cy, w, h],
      ));
    }

    return candidates;
  }

  /// Non-Maximum Suppression — removes overlapping boxes of the same class.
  ///
  /// Algorithm:
  ///   1. Sort detections by confidence (highest first)
  ///   2. Take the highest-confidence detection
  ///   3. Remove any other detection that overlaps it by > nmsThreshold
  ///   4. Repeat until no detections remain
  List<Detection> _applyNms(List<Detection> detections) {
    if (detections.isEmpty) return [];

    // Sort by confidence (highest first)
    final sorted = List<Detection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final kept = <Detection>[];

    while (sorted.isNotEmpty) {
      // Take the highest-confidence detection
      final best = sorted.removeAt(0);
      kept.add(best);

      // Remove any remaining detection that overlaps it (same class)
      sorted.removeWhere((other) {
        if (other.classId != best.classId) return false;
        final iou = _calculateIou(best.boundingBox, other.boundingBox);
        return iou > YoloConfig.nmsThreshold;
      });
    }

    return kept;
  }

  /// Calculates Intersection over Union for two boxes.
  ///
  /// Boxes are in [centerX, centerY, width, height] format.
  /// Returns a value 0.0 to 1.0:
  ///   0.0 = no overlap
  ///   1.0 = perfectly identical boxes
  double _calculateIou(List<double> box1, List<double> box2) {
    // Convert from center-format to corner-format
    final x1Min = box1[0] - box1[2] / 2;
    final y1Min = box1[1] - box1[3] / 2;
    final x1Max = box1[0] + box1[2] / 2;
    final y1Max = box1[1] + box1[3] / 2;

    final x2Min = box2[0] - box2[2] / 2;
    final y2Min = box2[1] - box2[3] / 2;
    final x2Max = box2[0] + box2[2] / 2;
    final y2Max = box2[1] + box2[3] / 2;

    // Calculate intersection rectangle
    final interLeft   = math.max(x1Min, x2Min);
    final interTop    = math.max(y1Min, y2Min);
    final interRight  = math.min(x1Max, x2Max);
    final interBottom = math.min(y1Max, y2Max);

    final interWidth  = math.max(0.0, interRight  - interLeft);
    final interHeight = math.max(0.0, interBottom - interTop);
    final interArea   = interWidth * interHeight;

    // Calculate union area
    final box1Area = box1[2] * box1[3];
    final box2Area = box2[2] * box2[3];
    final unionArea = box1Area + box2Area - interArea;

    // Avoid division by zero
    if (unionArea <= 0) return 0.0;

    return interArea / unionArea;
  }

  double _sigmoid(double x) {
    return 1.0 / (1.0 + math.exp(-x));
  }
}
