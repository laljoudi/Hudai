import 'package:flutter_test/flutter_test.dart';
import 'package:gp_hudai/core/services/detection_decoder.dart';

void main() {
  group('DetectionDecoder', () {

    // Helper: creates a fake YOLO output with one strong detection
    // YOLO output shape: [1, 9, 8400] flattened to length 75600
    // Layout: [all_x][all_y][all_w][all_h][all_class0][all_class1]...[all_class4]
    List<double> createFakeOutput({
      required int    detectionIndex,   // which anchor (0-8399)
      required int    classId,          // which class (0-4)
      required double confidence,       // confidence score (0.0-1.0)
      required double centerX,          // box center X (normalized 0-1)
      required double centerY,          // box center Y (normalized 0-1)
      required double width,            // box width (normalized 0-1)
      required double height,           // box height (normalized 0-1)
    }) {
      const numAnchors = 8400;
      const numChannels = 9;
      final output = List<double>.filled(numAnchors * numChannels, 0.0);

      // Set box coordinates at the chosen anchor
      output[0 * numAnchors + detectionIndex] = centerX;
      output[1 * numAnchors + detectionIndex] = centerY;
      output[2 * numAnchors + detectionIndex] = width;
      output[3 * numAnchors + detectionIndex] = height;

      // Set the chosen class confidence
      output[(4 + classId) * numAnchors + detectionIndex] = confidence;

      return output;
    }

    test('detects a single high-confidence object', () {
      final decoder = const DetectionDecoder();

      // Fake: a "person" (class 2) at 90% confidence in the center of the image
      final fakeOutput = createFakeOutput(
        detectionIndex: 100,
        classId:        2,
        confidence:     0.90,
        centerX:        0.5,
        centerY:        0.5,
        width:          0.3,
        height:         0.4,
      );

      final detections = decoder.decode(fakeOutput);

      expect(detections.length,          1,           reason: 'Should detect 1 object');
      expect(detections[0].classId,      2,           reason: 'Should be class 2');
      expect(detections[0].className,    'person',    reason: 'Should be labeled "person"');
      expect(detections[0].confidence,   0.90,        reason: 'Confidence should match');
      expect(detections[0].boundingBox, [0.5, 0.5, 0.3, 0.4]);
    });

    test('ignores low-confidence detections', () {
      final decoder = const DetectionDecoder();

      // Fake: a low-confidence detection (below 0.5 threshold)
      final fakeOutput = createFakeOutput(
        detectionIndex: 200,
        classId:        0,
        confidence:     0.30,  // below threshold
        centerX:        0.5,
        centerY:        0.5,
        width:          0.2,
        height:         0.2,
      );

      final detections = decoder.decode(fakeOutput);

      expect(detections, isEmpty, reason: 'Low-confidence should be filtered out');
    });

    test('returns empty list when nothing is detected', () {
      final decoder = const DetectionDecoder();

      // All zeros — model sees nothing
      final fakeOutput = List<double>.filled(8400 * 9, 0.0);

      final detections = decoder.decode(fakeOutput);

      expect(detections, isEmpty, reason: 'No detections expected');
    });

    test('detects multiple different-class objects', () {
      final decoder = const DetectionDecoder();

      // Combine two fake detections in one output
      final output1 = createFakeOutput(
        detectionIndex: 100,
        classId:        0,         // jabal_arafah
        confidence:     0.85,
        centerX:        0.3,
        centerY:        0.3,
        width:          0.2,
        height:         0.2,
      );
      final output2 = createFakeOutput(
        detectionIndex: 5000,
        classId:        4,         // crowd
        confidence:     0.75,
        centerX:        0.7,
        centerY:        0.7,
        width:          0.4,
        height:         0.3,
      );

      // Merge them
      final combined = List<double>.from(output1);
      for (int i = 0; i < combined.length; i++) {
        if (combined[i] == 0.0 && output2[i] != 0.0) {
          combined[i] = output2[i];
        }
      }

      final detections = decoder.decode(combined);

      expect(detections.length, 2, reason: 'Should detect 2 objects');

      final classNames = detections.map((d) => d.className).toSet();
      expect(classNames, containsAll(['jabal_arafah', 'crowd']));
    });

    test('NMS removes overlapping boxes of the same class', () {
      final decoder = const DetectionDecoder();

      // Two near-identical detections of the same class (person)
      final output1 = createFakeOutput(
        detectionIndex: 100,
        classId:        2,        // person
        confidence:     0.90,
        centerX:        0.5,
        centerY:        0.5,
        width:          0.3,
        height:         0.4,
      );
      final output2 = createFakeOutput(
        detectionIndex: 200,
        classId:        2,        // person (same class, overlapping box)
        confidence:     0.85,
        centerX:        0.51,     // very close
        centerY:        0.51,
        width:          0.29,
        height:         0.39,
      );

      final combined = List<double>.from(output1);
      for (int i = 0; i < combined.length; i++) {
        if (combined[i] == 0.0 && output2[i] != 0.0) {
          combined[i] = output2[i];
        }
      }

      final detections = decoder.decode(combined);

      expect(detections.length, 1, reason: 'NMS should remove the lower-confidence duplicate');
      expect(detections[0].confidence, 0.90, reason: 'Should keep the higher-confidence one');
    });
  });
}