import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

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
      // 1. Convert camera frame → RGB image
      final rgbImage = _convertCameraImageToRgb(cameraImage);
      if (rgbImage == null) return null;

      // 2. Resize to 640×640
      final resized = img.copyResize(
        rgbImage,
        width:  YoloConfig.inputSize,
        height: YoloConfig.inputSize,
        interpolation: img.Interpolation.linear,
      );

      // 3. Normalize pixels (0-255 → 0.0-1.0) and flatten to Float32List
      return _normalizeAndFlatten(resized);
    } catch (e) {
      // ignore: avoid_print
      print('🚨 FramePreprocessor: failed to process frame: $e');
      return null;
    }
  }

  /// Converts a CameraImage (YUV420 or BGRA8888) to an RGB image.
  ///
  /// iOS cameras typically use BGRA8888 format.
  /// Android cameras typically use YUV420.
  /// We handle both.
  img.Image? _convertCameraImageToRgb(CameraImage cameraImage) {
    if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
      return _convertBgra8888(cameraImage);
    } else if (cameraImage.format.group == ImageFormatGroup.yuv420) {
      return _convertYuv420(cameraImage);
    } else {
      // ignore: avoid_print
      print('⚠️ Unsupported camera format: ${cameraImage.format.group}');
      return null;
    }
  }

  /// Converts BGRA8888 (iOS default) to an RGB image.
  /// BGRA8888 is straightforward: 4 bytes per pixel (B, G, R, A).
  img.Image _convertBgra8888(CameraImage cameraImage) {
    final plane = cameraImage.planes[0];
    final width  = cameraImage.width;
    final height = cameraImage.height;

    final rgbImage = img.Image(width: width, height: height);

    final bytes = plane.bytes;
    int byteIdx = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final b = bytes[byteIdx];
        final g = bytes[byteIdx + 1];
        final r = bytes[byteIdx + 2];
        // Skip alpha (byteIdx + 3) — model doesn't need transparency
        byteIdx += 4;

        rgbImage.setPixelRgb(x, y, r, g, b);
      }
    }

    return rgbImage;
  }

  /// Converts YUV420 (Android default) to an RGB image.
  /// YUV420 has 3 separate planes: Y (luminance), U + V (chrominance).
  /// This is more complex than BGRA — requires per-pixel math.
/// Converts YUV420 (Android default) or NV12 (iOS) to an RGB image.
  ///
  /// Handles both:
  ///   - 3-plane YUV420 (Android — separate Y, U, V planes)
  ///   - 2-plane NV12   (iOS — Y plane + interleaved UV plane)
  img.Image _convertYuv420(CameraImage cameraImage) {
    final width  = cameraImage.width;
    final height = cameraImage.height;
    final planes = cameraImage.planes;

    final rgbImage = img.Image(width: width, height: height);

    final yPlane = planes[0];
    final yBytes = yPlane.bytes;
    final yRowStride = yPlane.bytesPerRow;

    // ── 3-plane YUV420 (Android) ──────────────────────────────────
    if (planes.length >= 3) {
      final uPlane = planes[1];
      final vPlane = planes[2];

      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex  = y * yRowStride + x;
          final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

          if (yIndex >= yBytes.length || uvIndex >= uPlane.bytes.length) {
            continue;
          }

          final yValue = yBytes[yIndex];
          final uValue = uPlane.bytes[uvIndex];
          final vValue = vPlane.bytes[uvIndex];

          int r = (yValue + 1.402 * (vValue - 128)).round();
          int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
          int b = (yValue + 1.772 * (uValue - 128)).round();

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          rgbImage.setPixelRgb(x, y, r, g, b);
        }
      }
      return rgbImage;
    }

    // ── 2-plane NV12 (iOS) ───────────────────────────────────────
    // Y plane is plane[0], UV interleaved in plane[1]
    if (planes.length == 2) {
      final uvPlane = planes[1];
      final uvBytes = uvPlane.bytes;
      final uvRowStride = uvPlane.bytesPerRow;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIndex  = y * yRowStride + x;
          final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * 2;

          if (yIndex >= yBytes.length || uvIndex + 1 >= uvBytes.length) {
            continue;
          }

          final yValue = yBytes[yIndex];
          final uValue = uvBytes[uvIndex];
          final vValue = uvBytes[uvIndex + 1];

          int r = (yValue + 1.402 * (vValue - 128)).round();
          int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
          int b = (yValue + 1.772 * (uValue - 128)).round();

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          rgbImage.setPixelRgb(x, y, r, g, b);
        }
      }
      return rgbImage;
    }

    // ── Fallback — single plane (grayscale) ──────────────────────
    // Just convert luminance to RGB equally
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * yRowStride + x;
        if (yIndex >= yBytes.length) continue;
        final yValue = yBytes[yIndex];
        rgbImage.setPixelRgb(x, y, yValue, yValue, yValue);
      }
    }
    return rgbImage;
  }

  /// Converts a 640×640 RGB image into a normalized Float32List.
  ///
  /// Pixel range: 0-255 (integers)  →  0.0-1.0 (floats)
  /// Layout: [R0,G0,B0, R1,G1,B1, R2,G2,B2, ...]
  /// Length: 640 × 640 × 3 = 1,228,800 numbers
  Float32List _normalizeAndFlatten(img.Image image) {
    const size = YoloConfig.inputSize;
    const channels = YoloConfig.inputChannels;
    final output = Float32List(size * size * channels);

    int outIdx = 0;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final pixel = image.getPixel(x, y);

        output[outIdx++] = pixel.r / 255.0;
        output[outIdx++] = pixel.g / 255.0;
        output[outIdx++] = pixel.b / 255.0;
      }
    }

    return output;
  }
}