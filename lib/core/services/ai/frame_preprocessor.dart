import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'package:gp_hudai/core/constants/yolo_config.dart';

/// Converts raw camera frames into the format the YOLO model expects.
///
/// Pipeline:
///   CameraImage (YUV420 from iOS / Android)
///   → RGB image
///   → resize to 640×640
///   → normalize pixels to 0.0-1.0
///   → flatten into Float32List
///
/// Output: Float32List of length 640 × 640 × 3 = 1,228,800 numbers
/// This matches the model's expected input shape [1, 640, 640, 3].
class FramePreprocessor {
  const FramePreprocessor();

  /// Main entry point: takes a camera frame, returns model-ready input.
  ///
  /// Returns null if the frame cannot be processed (rare, defensive).
  Float32List? processFrame(CameraImage cameraImage) {
    try {
      // Fast path:
      // sample directly from camera planes into a 640×640 Float32 tensor
      // (without creating a full intermediate image object).
      if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        return _bgraToModelInput(cameraImage);
      }
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        return _yuvToModelInput(cameraImage);
      }
      // ignore: avoid_print
      print('⚠️ Unsupported camera format: ${cameraImage.format.group}');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('🚨 FramePreprocessor: failed to process frame: $e');
      return null;
    }
  }

  Float32List _bgraToModelInput(CameraImage image) {
    const dstSize = YoloConfig.inputSize;
    final output = Float32List(dstSize * dstSize * 3);

    final plane = image.planes[0];
    final src = plane.bytes;
    final srcW = image.width;
    final srcH = image.height;
    final rowStride = plane.bytesPerRow;

    int outIdx = 0;
    for (int y = 0; y < dstSize; y++) {
      final srcY = (y * srcH) ~/ dstSize;
      final rowBase = srcY * rowStride;
      for (int x = 0; x < dstSize; x++) {
        final srcX = (x * srcW) ~/ dstSize;
        final idx = rowBase + srcX * 4;
        if (idx + 2 >= src.length) {
          output[outIdx++] = 0;
          output[outIdx++] = 0;
          output[outIdx++] = 0;
          continue;
        }
        final b = src[idx];
        final g = src[idx + 1];
        final r = src[idx + 2];

        output[outIdx++] = r / 255.0;
        output[outIdx++] = g / 255.0;
        output[outIdx++] = b / 255.0;
      }
    }

    return output;
  }

  Float32List _yuvToModelInput(CameraImage image) {
    const dstSize = YoloConfig.inputSize;
    final output = Float32List(dstSize * dstSize * 3);

    final srcW = image.width;
    final srcH = image.height;
    final planes = image.planes;
    final yPlane = planes[0];
    final yBytes = yPlane.bytes;
    final yRowStride = yPlane.bytesPerRow;

    int outIdx = 0;

    for (int y = 0; y < dstSize; y++) {
      final srcY = (y * srcH) ~/ dstSize;
      for (int x = 0; x < dstSize; x++) {
        final srcX = (x * srcW) ~/ dstSize;

        final yIdx = srcY * yRowStride + srcX;
        final yValue = yIdx < yBytes.length ? yBytes[yIdx] : 0;

        int uValue = 128;
        int vValue = 128;

        if (planes.length >= 3) {
          // Android YUV420
          final uPlane = planes[1];
          final vPlane = planes[2];
          final uvRowStride = uPlane.bytesPerRow;
          final uvPixelStride = uPlane.bytesPerPixel ?? 1;
          final uvIdx =
              (srcY ~/ 2) * uvRowStride + (srcX ~/ 2) * uvPixelStride;

          if (uvIdx < uPlane.bytes.length) {
            uValue = uPlane.bytes[uvIdx];
          }
          if (uvIdx < vPlane.bytes.length) {
            vValue = vPlane.bytes[uvIdx];
          }
        } else if (planes.length == 2) {
          // iOS NV12
          final uvPlane = planes[1];
          final uvIdx = (srcY ~/ 2) * uvPlane.bytesPerRow + (srcX ~/ 2) * 2;
          if (uvIdx + 1 < uvPlane.bytes.length) {
            uValue = uvPlane.bytes[uvIdx];
            vValue = uvPlane.bytes[uvIdx + 1];
          }
        }

        final r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
        final g =
            (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
                .clamp(0, 255)
                .toInt();
        final b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();

        output[outIdx++] = r / 255.0;
        output[outIdx++] = g / 255.0;
        output[outIdx++] = b / 255.0;
      }
    }

    return output;
  }
}
