import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart' as cam;
import 'package:flutter/foundation.dart';

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
  static const String intro                = 'audio/camera/camera_intro.mp3';
  static const String insideArafat         = 'audio/location/inside_arafat.mp3';
  static const String outsideArafat        = 'audio/location/outside_arafat.mp3';
  static const String locationUnavailable  = 'audio/location/location_unavailable.mp3';
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
  final YoloService          _yoloService       = YoloService();
  final FramePreprocessor    _preprocessor      = const FramePreprocessor();
  final DetectionDecoder     _decoder           = const DetectionDecoder();
  final InferenceThrottler   _throttler         = InferenceThrottler();
  final LocationService      _locationService   = const LocationService();
  final PermissionService    _permissionService = const PermissionService();
  final AudioPlayer          _audioPlayer       = AudioPlayer();
  final AudioService             _audioService = AudioService();
  late final SceneService        _sceneService;
  final DetectionToSceneAdapter  _adapter      = const DetectionToSceneAdapter();
  final PhoneService             _phoneService = const PhoneService();

  cam.CameraController? _cameraController;
  Future<void>?         _initializeFuture;

  // ──────────────────────────────────────────────────────────────────
  // Public state
  // ──────────────────────────────────────────────────────────────────
  CameraState _state = const CameraState();
  CameraState get state => _state;

  cam.CameraController? get cameraController => _cameraController;
  Future<void>?         get initializeFuture => _initializeFuture;

  bool   _useMockCamera = false;
  String? _cameraError;
  bool    _locationBusy = false;
   bool   _introPlaying  = false;

  bool   get useMockCamera => _useMockCamera;
  String? get cameraError  => _cameraError;
  bool   get locationBusy  => _locationBusy;

  // ──────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────

  /// Initialize everything: camera, AI model, audio intro.
  /// Call once when the screen opens.
  Future<void> initialize() async {
     _sceneService = SceneService(audioService: _audioService);
    debugPrint('🎬 CameraController: initialize()');

    // Run all three in parallel — they don't depend on each other
    await Future.wait([
      _initCamera(),
      _loadYoloModel(),
      _playIntroOnce(),
    ]);
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
    _audioPlayer.dispose();
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
        _cameraError   = 'لا توجد كاميرا متاحة، تم تفعيل الوضع التجريبي.';
        notifyListeners();
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == cam.CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = cam.CameraController(
        back,
        cam.ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: cam.ImageFormatGroup.yuv420,
      );

  _initializeFuture = _cameraController!.initialize();
      await _initializeFuture;

      _updateState(_state.copyWith(isCameraReady: true));

      // Start receiving camera frames for AI processing
      await _startFrameStream();
    } catch (_) {
      _useMockCamera = true;
      _cameraError   = 'تعذر تشغيل الكاميرا، تم تفعيل الوضع التجريبي.';
      notifyListeners();
    }
  }
/// Subscribe to the camera's frame stream.
  /// Each frame is sent to _onCameraFrame() for processing.
  Future<void> _startFrameStream() async {
    if (_cameraController == null) {
      debugPrint('⚠️ _startFrameStream: _cameraController is null');
      return;
    }

    try {
      debugPrint('📹 Attempting to start frame stream...');
      await _cameraController!.startImageStream(_onCameraFrame);
      debugPrint('📹 Camera frame stream started successfully');
    } catch (e) {
      debugPrint('🚨 Failed to start frame stream: $e');
    }
  }

  /// Called for every camera frame (~30 times per second).
  /// Runs the full AI pipeline at ~3 FPS via the throttler.
  Future<void> _onCameraFrame(cam.CameraImage image) async {
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

      // 5. Prepare output buffer matching the model's output shape
      final outputShape = _yoloService.interpreter!.getOutputTensor(0).shape;
      final output = List.generate(
        outputShape[0],
        (_) => List.generate(
          outputShape[1],
          (_) => List<double>.filled(outputShape[2], 0.0),
        ),
      );
            // Give the UI thread a chance to render before heavy inference
      await Future.delayed(Duration.zero);

      // 6. Run inference
      _yoloService.interpreter!.run(reshapedInput, output);

      // 7. Flatten output for the decoder
      final flat = <double>[];
      for (final dim1 in output[0]) {
        flat.addAll(dim1);
      }

      // 8. Decode raw output → Detection objects
      final detections = _decoder.decode(flat);

      // 9. Adapter: convert to SceneDetection format
      final sceneDetections = _adapter.adapt(detections);

      // 10. SceneService picks priority + plays audio
      _sceneService.processDetections(sceneDetections);

      // 11. Update state — only notify when detections actually change
      final oldDetectionCount = _state.currentDetections.length;
      _state = _state.copyWith(
        framesProcessed:   newCount,
        currentDetections: detections,
        isInferring:       false,
      );

      // Only trigger UI rebuild when detection count changes
      // (not on every frame — prevents lag)
      if (detections.length != oldDetectionCount) {
        notifyListeners();
      }

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
      await _audioPlayer.play(AssetSource(path));
    } catch (e) {
      debugPrint('🔊 Audio error: $e');
    }
  }

Future<void> _playIntroOnce() async {
    _introPlaying = true;

    await Future.delayed(const Duration(milliseconds: 800));
    await _playAudio(_CameraAudio.intro);

    // Wait for the intro to finish playing before allowing AI audio.
    // Camera intro is roughly 15 seconds — we listen for completion.
    _audioPlayer.onPlayerComplete.listen((_) {
      _introPlaying = false;
      debugPrint('🔊 Camera intro finished — AI audio enabled');
    });

    // Safety timeout: if onPlayerComplete never fires, unlock after 20s.
    Future.delayed(const Duration(seconds: 20), () {
      if (_introPlaying) {
        _introPlaying = false;
        debugPrint('🔊 Camera intro timeout — AI audio enabled');
      }
    });

    await Prefs.markCameraIntroHeard();
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
  /// First tap  → plays "double tap to confirm" audio
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
      // Play a confirmation audio prompt
      // (Using camera intro as a placeholder; your colleague can add a dedicated audio)
      await _playAudio(_CameraAudio.intro);
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

    // Check if SceneService has a previous instruction to replay
    if (_sceneService.hasLastInstruction) {
      debugPrint('🔁 Replaying last AI instruction');
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
    notifyListeners();

    try {
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
