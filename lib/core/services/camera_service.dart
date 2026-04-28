import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// CameraService owns the [CameraController] lifecycle.
///
/// Responsibilities:
///   - Find the back camera.
///   - Initialize and dispose the controller safely.
///   - Start / stop the YUV420 image stream for YOLO.
///   - Throttle frames to [targetFps] so the model is not flooded.
///
/// The screen (camera_screen.dart) creates one instance, calls [init()],
/// listens to [onFrameReady], and calls [dispose()] when done.
/// It never touches CameraController directly.
class CameraService {
  CameraService({this.targetFps = 3});

  /// Frames per second forwarded to [onFrameReady].
  /// 3 is a safe default. Raise to 5–8 once the model is confirmed fast enough.
  final int targetFps;

  CameraController? _controller;
  Timer?            _throttleTimer;
  bool              _frameProcessing = false;

  /// Fires with a raw YUV420 [CameraImage] every (1000/targetFps) ms.
  /// Wire this to your TFLite / HTTP detection adapter.
  ///
  /// Example in camera_screen.dart:
  ///   _cameraService.onFrameReady = (frame) async {
  ///     final results = await _detectionAdapter.detect(frame);
  ///     decisionEngine.evaluate(results);
  ///   };
  Future<void> Function(CameraImage frame)? onFrameReady;

  // ── Public getters ─────────────────────────────────────────────────────────

  /// True once [init] completes successfully.
  bool get isReady =>
      _controller != null && (_controller?.value.isInitialized ?? false);

  /// The initialized controller — pass to [CameraPreview] in the screen.
  /// Returns null if not yet ready.
  CameraController? get controller => isReady ? _controller : null;

  /// The camera's native aspect ratio — used to size [CameraPreview] correctly.
  double get aspectRatio => _controller?.value.aspectRatio ?? (9 / 16);

  // ── Init ───────────────────────────────────────────────────────────────────

  /// Finds the back camera, creates and initializes the controller.
  ///
  /// Returns true on success, false if no camera is available.
  /// Throws [CameraException] if the camera fails to initialize — the caller
  /// (camera_screen.dart) should catch it and show the mock view.
  Future<bool> init() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return false;

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    // medium = 720p — good for YOLO, half the RAM of high (1080p).
    // yuv420 is mandatory for startImageStream() on both iOS and Android.
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize(); // throws CameraException on failure
    return true;
  }

  // ── Frame stream ───────────────────────────────────────────────────────────

  /// Starts sending frames to [onFrameReady] at [targetFps].
  /// Safe to call multiple times — does nothing if already streaming.
  void startStream() {
    if (!isReady) return;
    if (_controller!.value.isStreamingImages) return;
    if (onFrameReady == null) {
      debugPrint('CameraService: startStream() called but onFrameReady is null');
      return;
    }

    final interval = Duration(milliseconds: (1000 / targetFps).round());

    _controller!.startImageStream((CameraImage frame) {
      // Drop frame if the previous one is still being processed.
      if (_frameProcessing) return;
      // Drop frame if we are within the throttle window.
      if (_throttleTimer?.isActive ?? false) return;

      _throttleTimer   = Timer(interval, () {});
      _frameProcessing = true;

      onFrameReady!(frame).whenComplete(() => _frameProcessing = false);
    });

    debugPrint('CameraService: stream started at $targetFps fps');
  }

  /// Stops the frame stream. Safe to call when not streaming.
  void stopStream() {
    _throttleTimer?.cancel();
    try {
      if (_controller?.value.isStreamingImages ?? false) {
        _controller?.stopImageStream();
      }
    } catch (e) {
      debugPrint('CameraService: stopStream error — $e');
    }
    debugPrint('CameraService: stream stopped');
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  /// Stops the stream and releases the camera.
  /// Always call this in the screen's dispose() and on app lifecycle pause.
  Future<void> dispose() async {
    stopStream();
    final old = _controller;
    _controller = null;
    await old?.dispose();
    debugPrint('CameraService: disposed');
  }
}
