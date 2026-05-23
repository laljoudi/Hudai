import 'package:camera/camera.dart' as cam;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:gp_hudai/core/constants/location_constants.dart';
import 'package:gp_hudai/core/models/detection.dart';
import 'package:gp_hudai/core/services/ai/yolo_service.dart';
import 'package:gp_hudai/core/services/ai/frame_preprocessor.dart';
import 'package:gp_hudai/core/services/ai/detection_decoder.dart';
import 'package:gp_hudai/core/services/ai/inference_throttler.dart';
import 'package:gp_hudai/core/services/location/location_guidance_service.dart';
import 'package:gp_hudai/core/services/location/location_service.dart';
import 'package:gp_hudai/core/services/permission_service.dart';
import 'package:gp_hudai/core/storage/prefs.dart';
import 'package:gp_hudai/features/camera/camera_state.dart';
import 'package:gp_hudai/core/services/audio/audio_service.dart';
import 'package:gp_hudai/core/services/audio/scene_service.dart';
import 'package:gp_hudai/core/services/ai/detection_to_scene_adapter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:gp_hudai/core/services/phone_service.dart';

const bool kForceMockCamera = false;

/// Demo coverage mode for quick presentations.
///
/// - `off`: use real GPS.
/// - `forceInsideArafat`: always inside Arafat.
/// - `forceOutsideArafat`: always outside Arafat.
enum DemoCoverageMode { off, forceInsideArafat, forceOutsideArafat }

// Set this to force coverage state during demo.
const DemoCoverageMode kDemoCoverageMode = DemoCoverageMode.off;

/// Audio file paths used by the camera screen.
/// Note: audioplayers uses paths WITHOUT the 'assets/' prefix.
class _CameraAudio {
  static const String intro = 'audio/camera/camera_intro.mp3';
  static const String permissionDenied =
      'audio/camera/camera_permission_denied.mp3';
}

/// The brain of the camera screen.
///
/// Manages: camera lifecycle, audio playback, location queries,
/// AI pipeline (added in Phase C).
///
/// The view (camera_screen.dart) only displays state and forwards
/// user input here. All business logic lives in this file.
class CameraController extends ChangeNotifier {
  // ──────────────────────────────────────────────────────────────────
  // Services
  // ──────────────────────────────────────────────────────────────────
  final YoloService _yoloService = YoloService();
  final FramePreprocessor _preprocessor = const FramePreprocessor();
  final DetectionDecoder _decoder = const DetectionDecoder();
  final InferenceThrottler _throttler = InferenceThrottler();
  final LocationService _locationService = const LocationService();
  final LocationGuidanceService _locationGuidanceService =
      const LocationGuidanceService();
  final PermissionService _permissionService = const PermissionService();
  final AudioService _audioService = AudioService();
  late final SceneService _sceneService;
  final DetectionToSceneAdapter _adapter = const DetectionToSceneAdapter();
  final PhoneService _phoneService = const PhoneService();
  List<List<List<double>>>? _inferenceOutput;
  List<double>? _flatOutput;

  cam.CameraController? _cameraController;
  Future<void>? _initializeFuture;

  // ──────────────────────────────────────────────────────────────────
  // Public state
  // ──────────────────────────────────────────────────────────────────
  CameraState _state = const CameraState();
  CameraState get state => _state;

  cam.CameraController? get cameraController => _cameraController;
  Future<void>? get initializeFuture => _initializeFuture;
  ValueListenable<List<Detection>> get detectionsListenable =>
      _detectionsNotifier;

  final ValueNotifier<List<Detection>> _detectionsNotifier =
      ValueNotifier<List<Detection>>(const []);

  bool _useMockCamera = false;
  String? _cameraError;
  bool _locationBusy = false;
  bool _systemAudioBusy = false;
  bool _cameraStarting = false;
  bool _processingEnabled = true;
  int _blockedFrameStreak = 0;
  Timer? _coverageRefreshTimer;
  bool? _insideArafatZone;
  bool? _lastSceneInferenceAllowedLog;
  bool _hasAnnouncedOutsideArafat = false;
  double? _previousMotionLuma;
  int _motionFastStreak = 0;

  // ============================================================
  // PERFORMANCE TEST [PT-01] — START
  // Purpose: Collect per-inference latency over 30 samples
  // Remove this block after testing is complete
  // ============================================================
  final Stopwatch _pt01Watch = Stopwatch();
  int _pt01WarmUpCount = 0;   // first 10 inferences are skipped
  int _pt01SampleCount = 0;
  final List<double> _pt01Latencies = [];
  // ============================================================
  // PERFORMANCE TEST [PT-01] — END
  // ============================================================

  // ============================================================
  // PERFORMANCE TEST [PT-02] — START
  // Purpose: Count inferences over a 60-second window for FPS
  // Remove this block after testing is complete
  // ============================================================
  int _pt02WarmUpCount = 0;   // first 10 inferences are skipped
  int _pt02FrameCount = 0;
  DateTime? _pt02WindowStart;
  // ============================================================
  // PERFORMANCE TEST [PT-02] — END
  // ============================================================

  bool get useMockCamera => _useMockCamera;
  String? get cameraError => _cameraError;
  bool get locationBusy => _locationBusy;

  // ──────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────

  /// Initialize everything: camera, AI model, audio intro.
  /// Call once when the screen opens.
  Future<void> initialize() async {
    _sceneService = SceneService(audioService: _audioService);
    debugPrint('🎬 CameraController: initialize()');

    // Step 1: Initialize camera (without starting frame stream yet).
    // If this fails (permission denied / no camera), it plays its own
    // audio message explaining the situation.
    await _initCamera();

    if (_useMockCamera) {
      // Camera is unavailable. The permission-denied audio has already
      // played inside _initCamera(). Still play the intro so the user
      // learns about location and emergency features that remain available.
      // Only skip the AI pipeline (model load + frame stream).
      debugPrint(
        '🎬 Camera unavailable → playing intro, skipping model load and frame stream',
      );
      await _playIntroOnce();
      _startCoverageRefreshLoop();
      return;
    }

    // Step 2: Play intro first (per requirement).
    await _playIntroOnce();

    // Step 3: Load model after intro finishes.
    await _loadYoloModel();

    // Step 4: Start frame stream only after intro + model loading.
    debugPrint('🎬 Intro done + model loaded → starting AI pipeline');
    await _startFrameStream();
    _startCoverageRefreshLoop();
  }

  @override
  void dispose() {
    debugPrint('🛑 CameraController: dispose()');

    // Stop receiving frames before disposing the camera
    if (_cameraController?.value.isStreamingImages == true) {
      _cameraController?.stopImageStream();
    }

    _yoloService.dispose();
    _audioService.dispose();
    _detectionsNotifier.dispose();
    _cameraController?.dispose();
    _coverageRefreshTimer?.cancel();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────
  // Camera setup
  // ──────────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    if (kForceMockCamera) {
      _useMockCamera = true;
      notifyListeners();
      return;
    }

    try {
      final cameras = await cam.availableCameras();
      if (cameras.isEmpty) {
        _useMockCamera = true;
        notifyListeners();
        await _announceCameraUnavailable();
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == cam.CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // `medium` makes the live preview visibly soft on iPhone.
      // `high` is the best default here: much sharper preview than medium,
      // while still leaving enough headroom for the 640x640 AI pipeline.
      final preset = cam.ResolutionPreset.high;

      _cameraController = cam.CameraController(
        back,
        preset,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? cam.ImageFormatGroup.bgra8888
            : cam.ImageFormatGroup.yuv420,
      );

      _initializeFuture = _cameraController!.initialize();
      await _initializeFuture;
      try {
        await _cameraController!.lockCaptureOrientation(
          DeviceOrientation.portraitUp,
        );
      } catch (_) {}
      try {
        await _cameraController!.setFocusMode(cam.FocusMode.auto);
      } catch (_) {}
      try {
        await _cameraController!.setExposureMode(cam.ExposureMode.auto);
      } catch (_) {}

      _updateState(_state.copyWith(isCameraReady: true));
    } catch (_) {
      _useMockCamera = true;
      notifyListeners();
      await _announceCameraUnavailable();
    }
  }

  /// Plays the audio message that informs the user the camera is not
  /// available and reminds them which features still work (location and
  /// emergency call). Called from both failure branches of [_initCamera].
  ///
  /// Errors are swallowed: if audio playback fails for any reason, we
  /// still want the rest of [initialize] to proceed so the user keeps
  /// access to the non-camera features.
  Future<void> _announceCameraUnavailable() async {
    debugPrint('🔊 Announcing camera unavailable to user');
    try {
      _systemAudioBusy = true;
      await _audioService.playAssetNow(_CameraAudio.permissionDenied);
    } catch (e) {
      debugPrint('🔊 Failed to play camera-unavailable audio: $e');
    } finally {
      _systemAudioBusy = false;
    }
  }

  /// Subscribe to the camera's frame stream.
  /// Each frame is sent to _onCameraFrame() for processing.
  Future<void> _startFrameStream() async {
    if (_cameraStarting) return;
    _cameraStarting = true;

    if (_cameraController == null) {
      debugPrint('⚠️ _startFrameStream: _cameraController is null');
      _cameraStarting = false;
      return;
    }

    try {
      debugPrint('📹 Attempting to start frame stream...');
      await _cameraController!.startImageStream(_onCameraFrame);
      debugPrint('📹 Camera frame stream started successfully');
    } catch (e) {
      debugPrint('🚨 Failed to start frame stream: $e');
    } finally {
      _cameraStarting = false;
    }
  }

  /// Called for every camera frame (~30 times per second).
  /// Runs the full AI pipeline at ~3 FPS via the throttler.
  Future<void> _onCameraFrame(cam.CameraImage image) async {
    if (!_processingEnabled) return;

    final canRunSceneInference = _canRunSceneInference;
    _logSceneInferenceGate(canRunSceneInference);
    if (!canRunSceneInference) {
      _clearLiveDetections();
      return;
    }

    _updateAdaptiveThrottle(image);

    // 1. Throttle — drop most frames, keep ~3 per second
    if (!_throttler.shouldProcess()) return;

    // 2. Skip if model isn't ready yet
    if (!_yoloService.isReady) {
      _throttler.markDone();
      return;
    }

    final newCount = _state.framesProcessed + 1;

    try {
      // 3. Quick camera-health guard (blocked lens / totally dark frame).
      final blocked = _isLikelyLensBlocked(image);
      if (blocked) {
        _blockedFrameStreak++;
      } else {
        _blockedFrameStreak = 0;
      }
      if (_blockedFrameStreak >= 4) {
        if (!_systemAudioBusy) {
          _sceneService.processCameraIssue();
        }
        _throttler.markDone();
        return;
      }

      // 3. Preprocess: YUV/BGRA → 640×640 RGB float
      final input = _preprocessor.processFrame(image);
      if (input == null) {
        _throttler.markDone();
        return;
      }

      // 4. Reshape input for the model
      final reshapedInput = input.reshape([1, 640, 640, 3]);

      // 5. Reuse preallocated output buffers to reduce GC/jank.
      final output = _inferenceOutput;
      final flat = _flatOutput;
      if (output == null || flat == null) {
        _throttler.markDone();
        return;
      }
      // ============================================================
      // PERFORMANCE TEST [PT-01] — START
      // Purpose: Start stopwatch before inference (warm-up skipped)
      // Remove this block after testing is complete
      // ============================================================
      if (_pt01WarmUpCount >= 10 && _pt01SampleCount < 30) _pt01Watch
        ..reset()
        ..start();
      // ============================================================
      // PERFORMANCE TEST [PT-01] — END
      // ============================================================

      // 6. Run inference
      await _yoloService.run(reshapedInput, output);

      // ============================================================
      // PERFORMANCE TEST [PT-01] — START
      // Purpose: Record sample; log mean once 30 steady-state inferences collected
      // Remove this block after testing is complete
      // ============================================================
      if (_pt01WarmUpCount < 10) {
        _pt01WarmUpCount++;
      } else if (_pt01SampleCount < 30) {
        _pt01Watch.stop();
        _pt01Latencies.add(_pt01Watch.elapsedMicroseconds / 1000.0);
        _pt01SampleCount++;
        if (_pt01SampleCount == 30) {
          final mean =
              _pt01Latencies.reduce((a, b) => a + b) / _pt01Latencies.length;
          debugPrint(
            '[PT-01] Mean latency (steady-state, after 10 warm-up): '
            '${mean.toStringAsFixed(2)} ms '
            '(samples: ${_pt01Latencies.map((v) => v.toStringAsFixed(1)).toList()})',
          );
        }
      }
      // ============================================================
      // PERFORMANCE TEST [PT-01] — END
      // ============================================================

      // ============================================================
      // PERFORMANCE TEST [PT-02] — START
      // Purpose: Count inferences over 60 s and log throughput (FPS)
      // Remove this block after testing is complete
      // ============================================================
      if (_pt02WarmUpCount < 10) {
        _pt02WarmUpCount++;
      } else {
        _pt02WindowStart ??= DateTime.now();
        _pt02FrameCount++;
        final pt02Elapsed =
            DateTime.now().difference(_pt02WindowStart!).inSeconds;
        if (pt02Elapsed >= 60) {
          final fps = _pt02FrameCount / 60.0;
          debugPrint(
            '[PT-02] Throughput (steady-state, after 10 warm-up): '
            '${fps.toStringAsFixed(2)} FPS '
            '(total inferences: $_pt02FrameCount over ${pt02Elapsed}s)',
          );
          _pt02FrameCount = 0;
          _pt02WindowStart = DateTime.now();
        }
      }
      // ============================================================
      // PERFORMANCE TEST [PT-02] — END
      // ============================================================

      // 7. Flatten output for the decoder
      int outIdx = 0;
      for (final dim1 in output[0]) {
        for (final value in dim1) {
          flat[outIdx++] = value;
        }
      }

      // 8. Decode raw output → Detection objects
      final detections = _decoder.decode(flat);

      // 9. Adapter: convert to SceneDetection format
      final sceneDetections = _adapter.adapt(detections);

      // 10. SceneService picks priority + plays audio
      // Skip scene audio while system audio is speaking
      // (intro/location/emergency feedback) to avoid overlap.
      if (!_systemAudioBusy) {
        _sceneService.processDetections(sceneDetections);
      }

      // 11. Update internal state only.
      // We intentionally avoid rebuilding the full camera UI on each
      // detection delta to keep preview smooth.
      _state = _state.copyWith(
        framesProcessed: newCount,
        currentDetections: detections,
        isInferring: false,
      );
      _detectionsNotifier.value = List<Detection>.unmodifiable(detections);

      // Log occasionally so we know it's alive
      if (newCount % 10 == 0) {
        debugPrint('🎯 Frame $newCount → ${detections.length} detection(s)');
      }
    } catch (e) {
      debugPrint('🚨 _onCameraFrame error: $e');
    } finally {
      // ALWAYS mark throttler done, even on error
      _throttler.markDone();
    }
  }

  bool _isLikelyLensBlocked(cam.CameraImage image) {
    final stats = _sampleLumaStats(image);
    if (stats == null) return false;

    final mean = stats.mean;
    final variance = stats.variance;
    final darkRatio = stats.darkRatio;
    final brightRatio = stats.brightRatio;

    final mostlyDark = darkRatio > 0.82 && mean < 55;
    final mostlyBright = brightRatio > 0.85 && mean > 220;
    final flatAndDim = variance < 22 && mean < 80;
    final flatAndBright = variance < 22 && mean > 190;

    return mostlyDark || mostlyBright || flatAndDim || flatAndBright;
  }

  void _updateAdaptiveThrottle(cam.CameraImage image) {
    final stats = _sampleLumaStats(image);
    if (stats == null) return;

    final prev = _previousMotionLuma;
    _previousMotionLuma = stats.mean;
    if (prev == null) return;

    final delta = (stats.mean - prev).abs();
    final isFast = delta >= 9.0;

    if (isFast) {
      _motionFastStreak = (_motionFastStreak + 1).clamp(0, 10);
    } else {
      _motionFastStreak = (_motionFastStreak - 1).clamp(0, 10);
    }

    final keepPreviewFluid = _motionFastStreak >= 2;
    if (Platform.isIOS) {
      _throttler.setOverrideIntervalMs(keepPreviewFluid ? 1000 : 600);
    } else {
      _throttler.setOverrideIntervalMs(keepPreviewFluid ? 700 : 350);
    }
  }

  _LumaStats? _sampleLumaStats(cam.CameraImage image) {
    if (image.planes.isEmpty) return null;
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0) return null;

    final stepY = (height / 18).clamp(4, 26).toInt();
    final stepX = (width / 18).clamp(4, 26).toInt();

    double sum = 0;
    double sumSq = 0;
    int dark = 0;
    int bright = 0;
    int n = 0;

    if (image.format.group == cam.ImageFormatGroup.bgra8888) {
      final p = image.planes[0];
      final bytes = p.bytes;
      final rowStride = p.bytesPerRow;
      for (int y = 0; y < height; y += stepY) {
        final rowBase = y * rowStride;
        for (int x = 0; x < width; x += stepX) {
          final idx = rowBase + (x * 4);
          if (idx + 2 >= bytes.length) continue;
          final b = bytes[idx];
          final g = bytes[idx + 1];
          final r = bytes[idx + 2];
          final luma = (0.299 * r + 0.587 * g + 0.114 * b);

          sum += luma;
          sumSq += luma * luma;
          if (luma < 35) dark++;
          if (luma > 235) bright++;
          n++;
        }
      }
    } else {
      final p = image.planes[0];
      final bytes = p.bytes;
      final rowStride = p.bytesPerRow;
      for (int y = 0; y < height; y += stepY) {
        final rowBase = y * rowStride;
        for (int x = 0; x < width; x += stepX) {
          final idx = rowBase + x;
          if (idx >= bytes.length) continue;
          final luma = bytes[idx].toDouble();

          sum += luma;
          sumSq += luma * luma;
          if (luma < 35) dark++;
          if (luma > 235) bright++;
          n++;
        }
      }
    }

    if (n == 0) return null;
    final mean = sum / n;
    final variance = (sumSq / n) - (mean * mean);
    return _LumaStats(
      mean: mean,
      variance: variance,
      darkRatio: dark / n,
      brightRatio: bright / n,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // YOLO model loading
  // ──────────────────────────────────────────────────────────────────
  Future<void> _loadYoloModel() async {
    try {
      await _yoloService.loadModel();
      final outputShape = _yoloService.interpreter!.getOutputTensor(0).shape;
      _inferenceOutput = List.generate(
        outputShape[0],
        (_) => List.generate(
          outputShape[1],
          (_) => List<double>.filled(outputShape[2], 0.0),
        ),
      );
      _flatOutput = List<double>.filled(outputShape[1] * outputShape[2], 0.0);
      _updateState(_state.copyWith(isAiReady: true));
    } catch (e) {
      debugPrint('🚨 CameraController: YOLO model failed to load: $e');
      _updateState(_state.copyWith(lastError: 'YOLO load failed'));
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Audio
  // ──────────────────────────────────────────────────────────────────
  Future<void> _playAudio(String path) async {
    debugPrint('🔊 Playing: $path');
    try {
      _systemAudioBusy = true;
      await _sceneService.stop();
      await _audioService.playAssetNow(path);
    } catch (e) {
      debugPrint('🔊 Audio error: $e');
    } finally {
      _systemAudioBusy = false;
    }
  }

  Future<void> _playAudioSequence(List<String> paths) async {
    if (paths.isEmpty) return;

    debugPrint('🔊 Playing sequence: ${paths.join(' → ')}');
    try {
      _systemAudioBusy = true;
      await _sceneService.stop();
      for (final path in paths) {
        await _audioService.playAssetNow(path);
      }
    } catch (e) {
      debugPrint('🔊 Audio sequence error: $e');
    } finally {
      _systemAudioBusy = false;
    }
  }

  Future<void> _playIntroOnce() async {
    await Future.delayed(const Duration(milliseconds: 800));

    // Play intro and wait until it finishes.
    await _playAudio(_CameraAudio.intro);
    debugPrint('🔊 Camera intro finished');

    await Prefs.markCameraIntroHeard();
  }

  Future<void> _interruptAllAudio() async {
    await _sceneService.stop();
    await _audioService.stop();
  }

  Future<void> _stopFrameStream() async {
    final controller = _cameraController;
    if (controller == null) return;
    if (!controller.value.isStreamingImages) return;

    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  /// Called before navigating to Settings.
  /// Stops live detection and silences any in-flight camera audio.
  Future<void> suspendForSettings() async {
    _processingEnabled = false;
    _systemAudioBusy = true;
    _coverageRefreshTimer?.cancel();
    await _interruptAllAudio();
    await _stopFrameStream();
    _throttler.reset();
  }

  /// Called after returning from Settings.
  /// Resumes live detection stream again.
  Future<void> resumeFromSettings() async {
    _systemAudioBusy = false;
    _processingEnabled = true;
    await _startFrameStream();
    _startCoverageRefreshLoop();
  }

  // ──────────────────────────────────────────────────────────────────
  // User actions (called by view when a quadrant is tapped)
  // ──────────────────────────────────────────────────────────────────

  // ── Emergency call double-tap state ────────────────────────────
  /// Timestamp of the first tap. Reset to 0 after the call or timeout.
  int _firstEmergencyTapMs = 0;

  /// Window in which the second tap must happen (milliseconds).
  static const int _doubleTapWindowMs = 1500;

  /// Top-right: emergency call (DOUBLE-TAP REQUIRED).
  ///
  /// First tap  → arms confirmation window only
  /// Second tap (within 1.5s) → places the emergency call
  /// If the second tap doesn't come within the window, state resets.
  Future<void> onEmergencyTap() async {
    debugPrint('👆 onEmergencyTap');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsed = nowMs - _firstEmergencyTapMs;

    if (elapsed > _doubleTapWindowMs) {
      // First tap (or window expired) — arm the double-tap
      _firstEmergencyTapMs = nowMs;
      debugPrint('☎️ First tap registered — waiting for confirmation');
      return;
    }

    // Second tap arrived within the window — place the call
    _firstEmergencyTapMs = 0; // reset
    debugPrint('☎️ Double-tap confirmed — calling emergency');

    final success = await _phoneService.callEmergency();
    if (success) {
      debugPrint('☎️ Call placed successfully');
    } else {
      debugPrint('🚨 Call failed — no number set or permission denied');
      await _playAudio(LocationAudioPaths.locationUnavailable);
    }
  }

  /// Bottom-left: replay the last spoken AI instruction.
  /// Falls back to the camera intro if no AI instruction has played yet.
  Future<void> onReplayInstructionsTap() async {
    debugPrint('👆 onReplayInstructionsTap');

    // Replay the LAST actually played clip globally (system or detection).
    final lastPath = _audioService.lastPlayedPath;
    if (lastPath != null && lastPath.isNotEmpty) {
      debugPrint('🔁 Replaying global last audio clip');
      await _playAudio(lastPath);
      return;
    }

    if (_sceneService.hasLastInstruction) {
      debugPrint('🔁 Replaying last AI audio clip');
      await _interruptAllAudio();
      _sceneService.repeatLastInstruction();
    } else {
      debugPrint('🔁 No AI instruction yet — replaying intro');
      await _playAudio(_CameraAudio.intro);
    }
  }

  /// Bottom-right: get current location and announce it.
  Future<void> onLocationTap() async {
    debugPrint('👆 onLocationTap');
    if (_locationBusy) return;

    _locationBusy = true;
    _systemAudioBusy = true;
    notifyListeners();

    try {
      // Stop any current clip immediately on tap.
      await _interruptAllAudio();

      if (_locationGuidanceService.isDemoModeEnabled) {
        final guidance = _locationGuidanceService.buildDemoGuidance();
        _updateCoverageStatus(guidance.insideArafat);

        debugPrint(
          '📍 Demo location mode: $kDemoLocationMode | '
          'insideArafat=${guidance.insideArafat} | '
          'nearNamirah=${guidance.nearNamirah} | '
          'distanceToJabal=${guidance.distanceToJabalMeters.toStringAsFixed(1)}m',
        );

        await _playAudioSequence(guidance.audioSequence);
        return;
      }

      final granted = await _permissionService.ensureLocationPermission();
      if (!granted) {
        await _playAudio(LocationAudioPaths.locationUnavailable);
        return;
      }

      final position = await _locationService.getCurrentPosition();
      final guidance = _locationGuidanceService.buildGuidance(position);
      _updateCoverageStatus(guidance.insideArafat);

      debugPrint(
        '📍 Manual location: ${position.latitude}, ${position.longitude} | '
        'accuracy=${position.accuracy.toStringAsFixed(1)}m | '
        'insideArafat=${guidance.insideArafat} | '
        'nearNamirah=${guidance.nearNamirah} | '
        'distanceToJabal=${guidance.distanceToJabalMeters.toStringAsFixed(1)}m',
      );

      if (guidance.audioSequence.isEmpty) {
        await _playAudio(LocationAudioPaths.locationUnavailable);
        return;
      }
      await _playAudioSequence(guidance.audioSequence);
    } catch (_) {
      await _playAudio(LocationAudioPaths.locationUnavailable);
    } finally {
      _systemAudioBusy = false;
      _locationBusy = false;
      notifyListeners();
    }
  }

  bool get _canRunSceneInference => _insideArafatZone == true;

  void _logSceneInferenceGate(bool allowed) {
    if (_lastSceneInferenceAllowedLog == allowed) return;
    _lastSceneInferenceAllowedLog = allowed;

    final locationText = _insideArafatZone == null
        ? 'location unknown'
        : (_insideArafatZone! ? 'inside Arafat' : 'outside Arafat');
    debugPrint(
      allowed
          ? '✅ Scene inference ENABLED: user is inside Arafat.'
          : '⛔ Scene inference BLOCKED: user is $locationText.',
    );
  }

  void _clearLiveDetections() {
    if (_state.currentDetections.isNotEmpty) {
      _state = _state.copyWith(currentDetections: const []);
    }
    if (_detectionsNotifier.value.isNotEmpty) {
      _detectionsNotifier.value = const [];
    }
  }

  void _startCoverageRefreshLoop() {
    _coverageRefreshTimer?.cancel();
    // Warm up once at startup. If the user is outside Arafat, announce it once
    // so they know why scene detection is not running.
    unawaited(_refreshCoverageStatus(announceOutsideOnce: true));
    _coverageRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshCoverageStatus());
    });
  }

  Future<bool?> _refreshCoverageStatus({
    bool announceOutsideOnce = false,
  }) async {
    try {
      if (_locationGuidanceService.isDemoModeEnabled) {
        final guidance = _locationGuidanceService.buildDemoGuidance();
        _updateCoverageStatus(guidance.insideArafat);
        debugPrint(
          '📍 Coverage (location demo mode): '
          'insideArafat=${guidance.insideArafat} | '
          'mode=$kDemoLocationMode',
        );
        if (announceOutsideOnce && !guidance.insideArafat) {
          await _announceOutsideArafatIfNeeded();
        }
        return guidance.insideArafat;
      }

      if (kDemoCoverageMode != DemoCoverageMode.off) {
        final forcedInside =
            kDemoCoverageMode == DemoCoverageMode.forceInsideArafat;
        _updateCoverageStatus(forcedInside);
        debugPrint(
          '📍 Coverage (demo mode): insideArafat=$forcedInside '
          'mode=$kDemoCoverageMode',
        );
        if (announceOutsideOnce && !forcedInside) {
          await _announceOutsideArafatIfNeeded();
        }
        return forcedInside;
      }

      final granted = await _permissionService.ensureLocationPermission();
      if (!granted) {
        _insideArafatZone = null;
        _clearLiveDetections();
        _sceneService.setCoverageStatus(false);
        return null;
      }

      final position = await _locationService.getCurrentPosition();
      final distance = _locationService.distanceToCircleCenter(
        position,
        LocationConstants.arafatZone,
      );
      final inside = _locationService.isInsideCircle(
        position,
        LocationConstants.arafatZone,
      );
      debugPrint(
        '📍 GPS: ${position.latitude}, ${position.longitude} | '
        'distanceToArafat=${distance.toStringAsFixed(1)}m | inside=$inside',
      );

      if (_insideArafatZone != inside) {
        _updateCoverageStatus(inside);
        debugPrint('📍 Coverage updated: insideArafat=$inside');
      } else if (_insideArafatZone == null) {
        _updateCoverageStatus(inside);
      }

      if (announceOutsideOnce && !inside) {
        await _announceOutsideArafatIfNeeded();
      }
      return inside;
    } catch (_) {
      _insideArafatZone = null;
      _clearLiveDetections();
      _sceneService.setCoverageStatus(false);
      return null;
    }
  }

  void _updateCoverageStatus(bool inside) {
    _insideArafatZone = inside;
    if (!inside) {
      _clearLiveDetections();
    } else {
      _hasAnnouncedOutsideArafat = false;
    }
    _sceneService.setCoverageStatus(inside);
  }

  Future<void> _announceOutsideArafatIfNeeded() async {
    if (_hasAnnouncedOutsideArafat) return;
    _hasAnnouncedOutsideArafat = true;
    await _playAudio(LocationAudioPaths.outsideArafat);
  }

  // ──────────────────────────────────────────────────────────────────
  // State helpers
  // ──────────────────────────────────────────────────────────────────
  void _updateState(CameraState newState) {
    _state = newState;
    notifyListeners();
  }
}

class _LumaStats {
  const _LumaStats({
    required this.mean,
    required this.variance,
    required this.darkRatio,
    required this.brightRatio,
  });

  final double mean;
  final double variance;
  final double darkRatio;
  final double brightRatio;
}