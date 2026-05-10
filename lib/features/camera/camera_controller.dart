import 'package:camera/camera.dart' as cam;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

import 'package:gp_hudai/core/constants/location_constants.dart';
import 'package:gp_hudai/core/services/yolo_service.dart';
import 'package:gp_hudai/core/services/frame_preprocessor.dart';
import 'package:gp_hudai/core/services/detection_decoder.dart';
import 'package:gp_hudai/core/services/inference_throttler.dart';
import 'package:gp_hudai/core/services/location_service.dart';
import 'package:gp_hudai/core/services/permission_service.dart';
import 'package:gp_hudai/core/storage/prefs.dart';
import 'package:gp_hudai/features/camera/camera_state.dart';
import 'package:gp_hudai/core/services/audio_service.dart';
import 'package:gp_hudai/core/services/scene_service.dart';
import 'package:gp_hudai/core/services/detection_to_scene_adapter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:gp_hudai/core/services/phone_service.dart';

const bool kForceMockCamera = false;

/// Audio file paths used by the camera screen.
/// Note: audioplayers uses paths WITHOUT the 'assets/' prefix.
class _CameraAudio {
  static const String intro = 'audio/camera/camera_intro.mp3';
  static const String insideArafat = 'audio/location/inside_arafat.mp3';
  static const String outsideArafat = 'audio/location/outside_arafat.mp3';
  static const String locationUnavailable =
      'audio/location/location_unavailable.mp3';
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

  bool _useMockCamera = false;
  String? _cameraError;
  bool _locationBusy = false;
  bool _systemAudioBusy = false;
  String? _lastSystemAudioPath;
  bool _cameraStarting = false;
  bool _processingEnabled = true;

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

    // Step 1: Initialize camera (without starting frame stream yet)
    await _initCamera();

    // Step 2: Play intro first (per requirement).
    await _playIntroOnce();

    // Step 3: Load model after intro finishes.
    await _loadYoloModel();

    // Step 4: Start frame stream only after intro + model loading.
    debugPrint('🎬 Intro done + model loaded → starting AI pipeline');
    await _startFrameStream();
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
    _cameraController?.dispose();
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
        _cameraError = 'لا توجد كاميرا متاحة، تم تفعيل الوضع التجريبي.';
        notifyListeners();
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
      _cameraError = 'تعذر تشغيل الكاميرا، تم تفعيل الوضع التجريبي.';
      notifyListeners();
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

    // 1. Throttle — drop most frames, keep ~3 per second
    if (!_throttler.shouldProcess()) return;

    // 2. Skip if model isn't ready yet
    if (!_yoloService.isReady) {
      _throttler.markDone();
      return;
    }

    final newCount = _state.framesProcessed + 1;

    try {
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
      // 6. Run inference
      _yoloService.interpreter!.run(reshapedInput, output);

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

      // Log occasionally so we know it's alive
      if (newCount % 3 == 0) {
        debugPrint('🎯 Frame $newCount → ${detections.length} detection(s)');
      }
    } catch (e) {
      debugPrint('🚨 _onCameraFrame error: $e');
    } finally {
      // ALWAYS mark throttler done, even on error
      _throttler.markDone();
    }
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
      _lastSystemAudioPath = path;
      await _audioService.playAssetNow(path);
    } catch (e) {
      debugPrint('🔊 Audio error: $e');
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
      await _playAudio(_CameraAudio.locationUnavailable); // reuse error audio
    }
  }

  /// Bottom-left: replay the last spoken instruction.
  /// If no AI instruction has been spoken yet, falls back to camera intro.
  /// Bottom-left: replay the last spoken AI instruction.
  /// If no AI instruction has been played yet, falls back to camera intro.
  Future<void> onReplayInstructionsTap() async {
    debugPrint('👆 onReplayInstructionsTap');

    // Replays ONE last clip only.
    if (_lastSystemAudioPath != null) {
      debugPrint('🔁 Replaying last system audio clip');
      await _playAudio(_lastSystemAudioPath!);
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

      final granted = await _permissionService.ensureLocationPermission();
      if (!granted) {
        await _playAudio(_CameraAudio.locationUnavailable);
        return;
      }

      final position = await _locationService.getCurrentPosition();
      debugPrint('GPS: ${position.latitude}, ${position.longitude}');

      final inside = _locationService.isInsideCircle(
        position,
        LocationConstants.arafatZone,
      );

      await _playAudio(
        inside ? _CameraAudio.insideArafat : _CameraAudio.outsideArafat,
      );
    } catch (_) {
      await _playAudio(_CameraAudio.locationUnavailable);
    } finally {
      _systemAudioBusy = false;
      _locationBusy = false;
      notifyListeners();
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // State helpers
  // ──────────────────────────────────────────────────────────────────
  void _updateState(CameraState newState) {
    _state = newState;
    notifyListeners();
  }
}
