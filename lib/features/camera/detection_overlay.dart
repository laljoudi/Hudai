import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:gp_hudai/core/constants/yolo_config.dart';
import 'package:gp_hudai/core/models/detection.dart';

class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.cameraAspectRatio,
  });

  final List<Detection> detections;
  final double cameraAspectRatio;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _DetectionPainter(
          detections: detections,
          cameraAspectRatio: cameraAspectRatio,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  const _DetectionPainter({
    required this.detections,
    required this.cameraAspectRatio,
  });

  final List<Detection> detections;
  final double cameraAspectRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || size.isEmpty) return;

    final previewRect = _previewRect(size);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF40E0FF);
    final labelBackgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xCC030A20);

    for (final detection in detections) {
      final rect = _boxToRect(detection.boundingBox, previewRect);
      final visibleRect = rect.intersect(Offset.zero & size);
      if (visibleRect.isEmpty) continue;

      canvas.drawRect(visibleRect, borderPaint);
      _paintLabel(
        canvas,
        visibleRect,
        '${detection.className} ${detection.confidencePercent}',
        labelBackgroundPaint,
      );
    }
  }

  Rect _previewRect(Size size) {
    final screenAspectRatio = size.width / size.height;
    final rawCameraAspectRatio = cameraAspectRatio <= 0
        ? screenAspectRatio
        : cameraAspectRatio;
    final portraitCameraAspectRatio = rawCameraAspectRatio > 1
        ? 1 / rawCameraAspectRatio
        : rawCameraAspectRatio;

    if (portraitCameraAspectRatio > screenAspectRatio) {
      final width = size.height * portraitCameraAspectRatio;
      return Rect.fromLTWH((size.width - width) / 2, 0, width, size.height);
    }

    final height = size.width / portraitCameraAspectRatio;
    return Rect.fromLTWH(0, (size.height - height) / 2, size.width, height);
  }

  Rect _boxToRect(List<double> box, Rect previewRect) {
    if (box.length < 4) return Rect.zero;

    final cx = _normalizeCoordinate(box[0]);
    final cy = _normalizeCoordinate(box[1]);
    final w = _normalizeCoordinate(box[2]);
    final h = _normalizeCoordinate(box[3]);

    final left = previewRect.left + (cx - w / 2) * previewRect.width;
    final top = previewRect.top + (cy - h / 2) * previewRect.height;
    final right = previewRect.left + (cx + w / 2) * previewRect.width;
    final bottom = previewRect.top + (cy + h / 2) * previewRect.height;

    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _normalizeCoordinate(double value) {
    if (!value.isFinite) return 0;

    // YOLO exports commonly emit either normalized 0..1 coordinates or
    // input-space coordinates in 0..640. Support both so the overlay does not
    // disappear off-screen if the export format changes.
    final normalized = value > 1.5 ? value / YoloConfig.inputSize : value;
    return normalized.clamp(-1.0, 2.0).toDouble();
  }

  void _paintLabel(
    Canvas canvas,
    Rect box,
    String text,
    Paint backgroundPaint,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, box.width - 8));

    if (textPainter.width <= 0 || textPainter.height <= 0) return;

    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 4);
    final labelWidth = textPainter.width + padding.horizontal;
    final labelHeight = textPainter.height + padding.vertical;
    final labelLeft = box.left;
    final labelTop = math.max(0.0, box.top - labelHeight);
    final labelRect = Rect.fromLTWH(
      labelLeft,
      labelTop,
      labelWidth,
      labelHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      backgroundPaint,
    );
    textPainter.paint(
      canvas,
      Offset(labelLeft + padding.left, labelTop + padding.top),
    );
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.cameraAspectRatio != cameraAspectRatio;
  }
}
