// Unit tests for DetectionDecoder.decode().
//
// Test cases covered in this file (matching the testing report):
//   UN-1: Empty input returns no detections
//   UN-2: Single strong detection is returned correctly
//   UN-3: Confidence threshold filtering
//   UN-4: Multiple detections of different classes
//   UN-5: NMS removes duplicate detections of the same class
//
// How the YOLOv8 output tensor is laid out (flat List<double>, 75,600 values):
//
//   tensor[row * 8400 + anchor] gives one value.
//   Each "row" stores one piece of info for all 8400 anchors:
//
//     row 0 → x center of the box
//     row 1 → y center of the box
//     row 2 → width of the box
//     row 3 → height of the box
//     row 4 → score for class 0 (jabal_arafah)
//     row 5 → score for class 1 (ar_marker)
//     row 6 → score for class 2 (person)
//     row 7 → score for class 3 (other_mountains)
//     row 8 → score for class 4 (crowd)
//
// Built-in settings used by the decoder:
//   - Confidence threshold: 0.15 (scores below this are dropped)
//   - NMS threshold: same-class boxes with overlap above 0.5 are merged
//   - Max detections returned: 10

import 'package:flutter_test/flutter_test.dart';

import 'package:gp_hudai/core/constants/yolo_config.dart';
import 'package:gp_hudai/core/services/ai/detection_decoder.dart';

// ── Tensor constants ──────────────────────────────────────────────────────────

const int _numAnchors = 8400;
const int _numClasses = YoloConfig.numClasses; // 5
const int _tensorSize = (4 + _numClasses) * _numAnchors; // 75,600

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Creates an empty tensor of the right size, filled with 0.0.
List<double> _emptyTensor() => List<double>.filled(_tensorSize, 0.0);

/// Writes one detection into the tensor at the given anchor position.
///
/// Sets the box coordinates and the score for one class. All other class
/// scores for this anchor stay at 0.0.
void _writeAnchor(
  List<double> tensor,
  int anchorIdx, {
  double cx = 0.5,
  double cy = 0.5,
  double w = 0.1,
  double h = 0.1,
  required int classId,
  required double score,
}) {
  tensor[0 * _numAnchors + anchorIdx] = cx;
  tensor[1 * _numAnchors + anchorIdx] = cy;
  tensor[2 * _numAnchors + anchorIdx] = w;
  tensor[3 * _numAnchors + anchorIdx] = h;
  tensor[(4 + classId) * _numAnchors + anchorIdx] = score;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('DetectionDecoder', () {
    const decoder = DetectionDecoder();

    // ── Case 1: Empty input returns no detections ────────────────────────────
    test('Case 1: empty input returns no detections', () {
      // The tensor is all zeros, so every score is 0.0.
      // Nothing should pass the 0.15 threshold.
      final results = decoder.decode(_emptyTensor());

      expect(results, isEmpty);
    });

    // ── Case 2: Single strong detection is returned correctly ────────────────
    test('Case 2: single strong detection is returned correctly', () {
      // Put one detection (class 0, score 0.92) at anchor 0.
      // Everything else stays at 0.0 and gets filtered out.
      final tensor = _emptyTensor();
      _writeAnchor(tensor, 0, classId: 0, score: 0.92);

      final results = decoder.decode(tensor);

      expect(results.length, equals(1));
      expect(results.first.classId, equals(0));
      expect(results.first.className, equals('jabal_arafah'));
      expect(results.first.confidence, closeTo(0.92, 0.001));
    });

    // ── Case 3: Confidence threshold filtering ───────────────────────────────
    test('Case 3: confidence threshold filtering', () {
      // Three detections with different scores:
      //   0.90 → kept (above threshold)
      //   0.05 → dropped (below threshold)
      //   0.15 → kept (exactly at threshold, should pass)
      //
      // Different classes are used so NMS does not interfere.
      final tensor = _emptyTensor();
      _writeAnchor(tensor, 0, classId: 0, score: 0.90);
      _writeAnchor(tensor, 1, classId: 1, score: 0.05);
      _writeAnchor(tensor, 2, classId: 2, score: 0.15);

      final results = decoder.decode(tensor);

      expect(results.length, equals(2));

      final confidences = results.map((d) => d.confidence).toList()..sort();
      expect(confidences[0], closeTo(0.15, 0.001));
      expect(confidences[1], closeTo(0.90, 0.001));
    });

    // ── Case 4: Multiple detections of different classes ─────────────────────
    test('Case 4: multiple detections of different classes', () {
      // Three strong detections, each from a different class.
      // NMS only removes overlapping boxes of the same class,
      // so all three should survive.
      final tensor = _emptyTensor();
      _writeAnchor(tensor, 0, classId: 0, score: 0.90); // jabal_arafah
      _writeAnchor(tensor, 1, classId: 1, score: 0.80); // ar_marker
      _writeAnchor(tensor, 2, classId: 2, score: 0.70); // person

      final results = decoder.decode(tensor);

      expect(results.length, equals(3));
      final classIds = results.map((d) => d.classId).toSet();
      expect(classIds, containsAll(<int>[0, 1, 2]));
    });

    // ── Case 5: NMS removes duplicate detections of the same class ───────────
    test('Case 5: NMS removes duplicate detections of the same class', () {
      // Two detections of the same class with identical boxes.
      // Their overlap is 100%, which is above the NMS threshold (0.5),
      // so NMS should keep only the one with the higher score (0.90).
      final tensor = _emptyTensor();
      _writeAnchor(tensor, 0, cx: 0.5, cy: 0.5, w: 0.2, h: 0.2, classId: 0, score: 0.90);
      _writeAnchor(tensor, 1, cx: 0.5, cy: 0.5, w: 0.2, h: 0.2, classId: 0, score: 0.60);

      final results = decoder.decode(tensor);

      expect(results.length, equals(1));
      expect(results.first.confidence, closeTo(0.90, 0.001));
    });
  });
}