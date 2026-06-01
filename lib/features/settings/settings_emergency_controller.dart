import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:gp_hudai/core/constants/setup_audio_envelopes.dart';
import 'package:gp_hudai/core/storage/prefs.dart';
import 'package:gp_hudai/core/utils/saudi_number_parser.dart'
    show arabicSpeechToDigits, extractEmergencyDigits, isValidEmergencyNumber;

/// Audio assets — same physical MP3 files as the first-launch Setup flow.
class _Audio {
  static const String intro          = 'audio/setup/setup_intro.mp3';
  static const String startListening = 'audio/setup/start_listening.mp3';
  static const String confirmNumber  = 'audio/setup/confirm_number.mp3';
  static const String processing     = 'audio/setup/processing_number.mp3';
  static const String invalidVoice   = 'audio/setup/invalid_voice_input.mp3';
  static const String manualIntro    = 'audio/setup/manual_input_intro.mp3';
  static const String tapToSave      = 'audio/setup/tap_to_save.mp3';

  static const List<String> digits = [
    'audio/setup/0.mp3',
    'audio/setup/1.mp3',
    'audio/setup/2.mp3',
    'audio/setup/3.mp3',
    'audio/setup/4.mp3',
    'audio/setup/5.mp3',
    'audio/setup/6.mp3',
    'audio/setup/7.mp3',
    'audio/setup/8.mp3',
    'audio/setup/9.mp3',
  ];

  static String digit(int d) => digits[d];
}

/// Stages — identical semantics to SetupStage, kept separate so the two
/// controllers never share an enum value.
enum SettingsEmergencyStage {
  intro,
  idle,
  startingListen,
  listening,
  processing,
  invalid,
  confirming,
  awaitingSave,
  saving,
  manual,
}

/// Brain of the Settings → Edit-emergency-number screen.
///
/// Dedicated, standalone clone of SetupController's working voice-flow
/// logic. Owns its own AudioPlayer + STT session so there is zero shared
/// mutable state with the first-launch Setup flow.
class SettingsEmergencyController extends ChangeNotifier {
  final AudioPlayer      _audioPlayer = AudioPlayer();
  final stt.SpeechToText _speech      = stt.SpeechToText();

  bool   _speechAvailable    = false;
  bool   _disposed           = false;
  bool   _processed          = false;
  bool   _userStopRequested  = false;
  int    _restartFailures    = 0;
  String _accumulatedText    = '';

  SettingsEmergencyStage _stage = SettingsEmergencyStage.intro;
  String _recognizedNumber  = '';
  String _heardText         = '';
  String _lastParsedDigits  = '';
  bool   _shouldNavigate    = false;

  SettingsEmergencyStage get stage => _stage;
  String get recognizedNumber       => _recognizedNumber;
  String get heardText              => _heardText;
  String get lastParsedDigits       => _lastParsedDigits;
  bool   get shouldNavigate         => _shouldNavigate;

  /// Live amplitude (0..1) for the currently playing setup clip. Driven
  /// by the pre-baked envelope in SetupAudioEnvelopes plus attack/release
  /// smoothing so the orb equaliser visually tracks the spoken audio.
  double get speakingAmplitude => _speakingAmplitude;
  double _speakingAmplitude = 0.0;
  List<double>? _currentEnvelope;
  Timer? _amplitudeTicker;

  bool get isManual    => _stage == SettingsEmergencyStage.manual;
  bool get isListening => _stage == SettingsEmergencyStage.listening;
  bool get inputLocked =>
      _stage == SettingsEmergencyStage.intro ||
      _stage == SettingsEmergencyStage.saving;

  // ──────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    debugPrint('SettingsEmergencyController: initialize()');

    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);
    } catch (e) {
      debugPrint('🔊 SE player config error: $e');
    }

    _setStage(SettingsEmergencyStage.intro);
    await _playAndWait(_Audio.intro);
    if (_disposed) return;

    await _ensureVoicePermissions();
    if (_disposed) return;

    _setStage(SettingsEmergencyStage.idle);
  }

  @override
  void dispose() {
    debugPrint('SettingsEmergencyController: dispose()');
    _disposed = true;
    _amplitudeTicker?.cancel();
    try { _speech.cancel(); } catch (_) {}
    try { _audioPlayer.dispose(); } catch (_) {}
    super.dispose();
  }

  void clearNavigationFlag() => _shouldNavigate = false;

  // ──────────────────────────────────────────────────────────────────
  // Public taps
  // ──────────────────────────────────────────────────────────────────

  Future<void> onSingleTap() async {
    if (inputLocked) return;
    if (_stage == SettingsEmergencyStage.manual) return;
    debugPrint('👆 SE onSingleTap (stage=$_stage)');

    if (_stage == SettingsEmergencyStage.listening) {
      debugPrint('🛑 SE user requested stop');
      _userStopRequested = true;
      try { await _speech.stop(); } catch (_) {}

      // ⚠️ DO NOT rely on the onStatus callback to trigger _process.
      // The speech_to_text plugin uses a singleton native engine, and
      // onStatus/onError callbacks are bound on the FIRST initialize().
      // If a Setup-flow controller ran earlier and got disposed, its
      // (now-dead) callback receives the `done` event instead of ours.
      // To survive that, we process directly here.
      //
      // Wait briefly for the final partial result to bank, then process.
      await Future.delayed(const Duration(milliseconds: 400));
      if (!_processed &&
          !_disposed &&
          _stage == SettingsEmergencyStage.listening) {
        debugPrint('🛑 SE forcing _process directly (callback bypass)');
        await _process(_accumulatedText);
      }
      return;
    }

    if (_stage == SettingsEmergencyStage.awaitingSave) {
      debugPrint('🔄 SE awaitingSave → retry voice');
      await _cancelEverything();
      await _runVoiceFlow();
      return;
    }

    await _cancelEverything();
    await _runVoiceFlow();
  }

  /// Long-press: save the recognised number.
  ///
  /// Accepts ANY stage as long as we have a valid 10-digit Saudi number
  /// available (either freshly recognised or last-parsed). This means
  /// the user can save:
  ///   - in `awaitingSave` (normal, after the tap_to_save cue),
  ///   - or earlier — during `confirming` / `processing` — if they
  ///     don't want to wait for the audio playback to finish,
  ///   - or even if an audio clip hangs and the stage gets stuck.
  ///
  /// The ONLY thing that blocks a save is "we don't have a valid number
  /// yet" (still listening, or recognition produced garbage).
  Future<void> onLongPress() async {
    debugPrint(
      '👆⏱ SE onLongPress (stage=$_stage, '
      'recognized="$_recognizedNumber", '
      'lastParsed="$_lastParsedDigits")',
    );

    // Pick the best valid number we have.
    String? digits;
    if (_isValidNumber(_recognizedNumber)) {
      digits = _recognizedNumber;
    } else if (_isValidNumber(_lastParsedDigits)) {
      digits = _lastParsedDigits;
    }

    if (digits == null) {
      debugPrint('👆⏱ SE onLongPress ignored — no valid digits yet');
      return;
    }

    debugPrint('💾 SE long-press → save + navigate (digits="$digits")');
    await _cancelEverything();
    await _saveAndNavigate(digits);
  }

  Future<void> onDoubleTap() async {
    if (_stage == SettingsEmergencyStage.intro) return;
    debugPrint('👆👆 SE onDoubleTap → manual (stage=$_stage)');

    await _cancelEverything();
    _setStage(SettingsEmergencyStage.manual);
    await _playAndWait(_Audio.manualIntro);
  }

  // ──────────────────────────────────────────────────────────────────
  // Voice flow
  // ──────────────────────────────────────────────────────────────────

  Future<bool> _ensureVoicePermissions() async {
    var mic    = await ph.Permission.microphone.status;
    var speech = await ph.Permission.speech.status;

    if (mic.isDenied)    mic    = await ph.Permission.microphone.request();
    if (speech.isDenied) speech = await ph.Permission.speech.request();

    final granted = mic.isGranted && speech.isGranted;
    if (!granted) {
      debugPrint('🎙️ SE permission denied: mic=$mic speech=$speech');
    }
    return granted;
  }

  Future<void> _runVoiceFlow() async {
    _setStage(SettingsEmergencyStage.startingListen);
    await _playAndWait(_Audio.startListening);
    if (_disposed || _stage != SettingsEmergencyStage.startingListen) return;

    final granted = await _ensureVoicePermissions();
    if (!granted) {
      _setStage(SettingsEmergencyStage.idle);
      return;
    }

    if (!_speechAvailable) {
      _speechAvailable = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError:  _onSpeechError,
      );
    }
    if (!_speechAvailable) {
      debugPrint('🎙️ SE STT unavailable');
      await _handleInvalid();
      return;
    }

    _setStage(SettingsEmergencyStage.listening);
    _recognizedNumber  = '';
    _heardText         = '';
    _accumulatedText   = '';
    _processed         = false;
    _userStopRequested = false;
    _restartFailures   = 0;

    await _speech.listen(
      localeId: 'ar_SA',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
      pauseFor:  const Duration(minutes: 10),
      listenFor: const Duration(minutes: 5),
      onResult:  _onSpeechResult,
    );
  }

  void _onSpeechStatus(String status) {
    debugPrint('🎙️ SE STT status: $status');
    if ((status == 'notListening' || status == 'done') &&
        _stage == SettingsEmergencyStage.listening &&
        !_processed) {
      if (_userStopRequested) {
        _process(_accumulatedText);
      } else {
        _restartListening();
      }
    }
  }

  void _onSpeechError(dynamic error) {
    debugPrint('🎙️ SE STT error: $error');
    if (_stage != SettingsEmergencyStage.listening || _processed) return;
    if (_userStopRequested) {
      _processed = true;
      _handleInvalid();
      return;
    }
    _restartFailures++;
    if (_restartFailures >= 4) {
      _processed = true;
      _handleInvalid();
      return;
    }
    _restartListening();
  }

  void _onSpeechResult(dynamic result) {
    final words   = (result.recognizedWords as String?) ?? '';
    final isFinal = (result.finalResult as bool?) ?? false;
    debugPrint('🎙️ SE heard: "$words" final=$isFinal');

    final live = ('$_accumulatedText $words').trim();
    _heardText = live;
    if (isFinal && words.isNotEmpty) {
      _accumulatedText = live;
    }
    notifyListeners();
  }

  Future<void> _restartListening() async {
    if (_disposed) return;
    if (_stage != SettingsEmergencyStage.listening) return;
    if (_processed) return;
    if (_userStopRequested) return;

    debugPrint('🔄 SE restart listen (failures=$_restartFailures)');
    await Future.delayed(const Duration(milliseconds: 250));
    if (_disposed ||
        _userStopRequested ||
        _stage != SettingsEmergencyStage.listening ||
        _processed) {
      return;
    }

    try {
      await _speech.listen(
        localeId: 'ar_SA',
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
        pauseFor:  const Duration(minutes: 10),
        listenFor: const Duration(minutes: 5),
        onResult:  _onSpeechResult,
      );
    } catch (e) {
      debugPrint('🔄 SE restart failed: $e');
      _restartFailures++;
      if (_restartFailures < 4) {
        _restartListening();
      } else {
        _processed = true;
        _handleInvalid();
      }
    }
  }

  Future<void> _process(String words) async {
    if (_processed) return;
    _processed = true;
    if (_stage != SettingsEmergencyStage.listening) return;

    _setStage(SettingsEmergencyStage.processing);
    final digits = arabicSpeechToDigits(words);
    _lastParsedDigits = digits;
    debugPrint('🎙️ SE parsed: "$digits" (len=${digits.length})');

    // Validate FIRST and expose the recognised number BEFORE playing any
    // audio. This way, onLongPress can save the number even if a later
    // audio clip hangs (audio focus, missing asset, etc.) and the stage
    // gets stuck in processing/confirming.
    final valid = _isValidNumber(digits);
    if (valid) {
      _recognizedNumber = digits;
      notifyListeners();
    }

    await _playAndWait(_Audio.processing);
    if (_disposed || _stage != SettingsEmergencyStage.processing) return;

    if (!valid) {
      _recognizedNumber = '';
      await _handleInvalid();
      return;
    }

    _setStage(SettingsEmergencyStage.confirming);

    await _playAndWait(_Audio.confirmNumber);
    if (_disposed || _stage != SettingsEmergencyStage.confirming) return;

    for (final ch in digits.split('')) {
      final d = int.tryParse(ch);
      if (d == null) continue;
      await _playAndWait(_Audio.digit(d));
      if (_disposed || _stage != SettingsEmergencyStage.confirming) return;
    }

    await _playAndWait(_Audio.tapToSave);
    if (_disposed || _stage != SettingsEmergencyStage.confirming) return;

    _setStage(SettingsEmergencyStage.awaitingSave);
  }

  Future<void> _saveAndNavigate(String digits) async {
    debugPrint('💾 SE _saveAndNavigate("$digits") [stage=$_stage]');

    if (!_isValidNumber(digits)) {
      debugPrint('🚨 SE _saveAndNavigate: invalid number, aborting');
      return;
    }

    // Force into the saving stage even if onLongPress came in early
    // (during processing/confirming). This guarantees the UI shows the
    // saving state and that we don't double-save.
    if (_stage == SettingsEmergencyStage.saving) {
      debugPrint('💾 SE already saving, ignoring duplicate trigger');
      return;
    }
    _setStage(SettingsEmergencyStage.saving);

    try {
      debugPrint('💾 SE Prefs.saveEmergencyNumber("$digits") …');
      await Prefs.saveEmergencyNumber(digits);
      debugPrint('💾 SE   → saved OK');
    } catch (e) {
      debugPrint('🚨 SE Prefs.saveEmergencyNumber failed: $e');
      // Still proceed to navigate — the user will see the old number on
      // the next emergency call. Better than getting stranded on this
      // screen with no save.
    }

    if (_disposed) {
      debugPrint('💾 SE controller disposed mid-save, not notifying');
      return;
    }

    _shouldNavigate = true;
    debugPrint('💾 SE _shouldNavigate=true → notifying listeners');
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────
  // Manual mode (silent)
  // ──────────────────────────────────────────────────────────────────

  String? validateManualNumber(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) return 'الرجاء إدخال رقم الطوارئ';
    // Normalise Arabic numerals first so a number typed on an Arabic
    // keyboard (٠٥٠…) is accepted, not silently stripped to empty.
    if (!isValidEmergencyNumber(input)) {
      return 'يجب أن يبدأ الرقم بـ 05 ويتكون من 10 أرقام';
    }
    return null;
  }

  Future<bool> saveManualNumber(String rawNumber) async {
    if (_stage == SettingsEmergencyStage.saving) return false;
    // Normalise Arabic numerals before stripping non-digits + validating.
    final digits = extractEmergencyDigits(rawNumber);
    if (!_isValidNumber(digits)) return false;
    _setStage(SettingsEmergencyStage.saving);
    try {
      await Prefs.saveEmergencyNumber(digits);
      return true;
    } catch (e) {
      debugPrint('🚨 SE manual save failed: $e');
      _setStage(SettingsEmergencyStage.manual);
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────

  bool _isValidNumber(String digits) => RegExp(r'^05\d{8}$').hasMatch(digits);

  Future<void> _handleInvalid() async {
    if (_disposed) return;
    _setStage(SettingsEmergencyStage.invalid);
    await _playAndWait(_Audio.invalidVoice);
    if (_disposed) return;
    _setStage(SettingsEmergencyStage.idle);
  }

  Future<void> _cancelEverything() async {
    _processed         = true;
    _userStopRequested = true;
    _heardText         = '';
    _accumulatedText   = '';
    _restartFailures   = 0;
    try { await _audioPlayer.stop(); } catch (_) {}
    if (_speech.isListening) {
      try { await _speech.cancel(); } catch (_) {}
    }
  }

  void _setStage(SettingsEmergencyStage s) {
    if (_disposed) return;
    _stage = s;
    notifyListeners();
  }

  Future<void> _playAndWait(String path) async {
    debugPrint('🔊 SE play: $path');
    final completer = Completer<void>();
    final sub = _audioPlayer.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(path));
      _startEnvelopeTicker(path);
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => debugPrint('🔊 SE audio timeout: $path'),
      );
    } catch (e) {
      debugPrint('🔊 SE audio error ($path): $e');
    } finally {
      _stopEnvelopeTicker();
      await sub.cancel();
    }
  }

  /// Starts polling the audio player position at ~30 Hz and writes the
  /// matching envelope value (with attack/release smoothing) into
  /// `_speakingAmplitude` so the screen's orb equaliser tracks the
  /// currently playing clip.
  void _startEnvelopeTicker(String path) {
    _amplitudeTicker?.cancel();
    _currentEnvelope = SetupAudioEnvelopes.forPath(path);
    _speakingAmplitude = 0.0;

    if (_currentEnvelope == null) return;

    const attack = 0.45;
    const release = 0.10;

    _amplitudeTicker = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) async {
        if (_disposed) return;
        final envelope = _currentEnvelope;
        if (envelope == null) return;
        final pos = await _audioPlayer.getCurrentPosition();
        if (pos == null) return;
        final ms = pos.inMilliseconds;
        final idx = ms ~/ SetupAudioEnvelopes.binMs;
        double raw;
        if (idx < 0 || idx >= envelope.length) {
          raw = 0.0;
        } else {
          final t = (ms % SetupAudioEnvelopes.binMs) /
              SetupAudioEnvelopes.binMs;
          final a = envelope[idx];
          final b = idx + 1 < envelope.length ? envelope[idx + 1] : a;
          raw = a + (b - a) * t;
        }
        final coeff = raw > _speakingAmplitude ? attack : release;
        _speakingAmplitude = (_speakingAmplitude +
                (raw - _speakingAmplitude) * coeff)
            .clamp(0.0, 1.0);
        if (!_disposed) notifyListeners();
      },
    );
  }

  void _stopEnvelopeTicker() {
    _amplitudeTicker?.cancel();
    _amplitudeTicker = null;
    _currentEnvelope = null;
    if (_speakingAmplitude != 0.0) {
      _speakingAmplitude = 0.0;
      if (!_disposed) notifyListeners();
    }
  }
}
