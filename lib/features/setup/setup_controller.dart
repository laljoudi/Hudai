import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:gp_hudai/core/storage/prefs.dart';

/// Audio file paths used by the setup screen.
/// Note: audioplayers uses paths WITHOUT the 'assets/' prefix.
class _SetupAudio {
  static const String intro          = 'audio/setup/setup_intro..mp3';
  static const String startListening = 'audio/setup/start_listening.mp3';
  static const String confirmNumber  = 'audio/setup/confirm_number.mp3';
  static const String afterConfirm   = 'audio/setup/after_confirm_options.mp3';
  static const String processing     = 'audio/setup/processing_number.mp3';
  static const String invalidVoice   = 'audio/setup/invalid_voice_input.mp3';

  // Digit files 0–9, played one-by-one when reading back the number.
  static const String d0 = 'audio/setup/0.mp3';
  static const String d1 = 'audio/setup/1.mp3';
  static const String d2 = 'audio/setup/2.mp3';
  static const String d3 = 'audio/setup/3.mp3';
  static const String d4 = 'audio/setup/4.mp3';
  static const String d5 = 'audio/setup/5.mp3';
  static const String d6 = 'audio/setup/6.mp3';
  static const String d7 = 'audio/setup/7.mp3';
  static const String d8 = 'audio/setup/8.mp3';
  static const String d9 = 'audio/setup/9.mp3';

  static const List<String> digits = [d0, d1, d2, d3, d4, d5, d6, d7, d8, d9];

  static String digit(int d) => digits[d];
}

/// Stages the setup screen can be in.
///   intro           — setup_intro is playing, all input ignored
///   idle            — waiting for first user tap
///   startingListen  — start_listening audio is playing
///   listening       — microphone is open, capturing speech
///   processing      — processing_number is playing + parsing digits
///   invalid         — invalid_voice_input is playing
///   confirming      — confirm_number → digits → after_confirm_options
///   saving          — persisting to Prefs (after a valid voice input)
///   manual          — silent manual mode (text field)
enum SetupStage {
  intro,
  idle,
  startingListen,
  listening,
  processing,
  invalid,
  confirming,
  saving,
  manual,
}

/// Brain of the setup screen. The view only renders state and forwards taps.
class SetupController extends ChangeNotifier {
  // Services
  final AudioPlayer      _audioPlayer = AudioPlayer();
  final stt.SpeechToText _speech      = stt.SpeechToText();

  bool _speechAvailable = false;
  bool _disposed        = false;
  bool _processed       = false;

  // State
  SetupStage _stage             = SetupStage.intro;
  String     _recognizedNumber  = '';
  String     _heardText         = '';
  bool       _shouldNavigate    = false;

  SetupStage get stage            => _stage;
  String     get recognizedNumber => _recognizedNumber;
  String     get heardText        => _heardText;
  bool       get shouldNavigate   => _shouldNavigate;

  bool get isManual    => _stage == SetupStage.manual;
  bool get isListening => _stage == SetupStage.listening;
  bool get inputLocked =>
      _stage == SetupStage.intro ||
      _stage == SetupStage.saving;

  String get statusText {
    switch (_stage) {
      case SetupStage.intro:           return '...';
      case SetupStage.idle:            return 'اضغط للتحدث';
      case SetupStage.startingListen:  return 'استعد للتحدث...';
      case SetupStage.listening:       return 'جارٍ الاستماع...';
      case SetupStage.processing:      return 'جارٍ المعالجة...';
      case SetupStage.invalid:         return 'لم يتم التعرف على الرقم';
      case SetupStage.confirming:      return 'تأكيد الرقم...';
      case SetupStage.saving:          return 'جارٍ الحفظ...';
      case SetupStage.manual:          return '';
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────

  /// On screen open: play setup_intro, then unlock to idle.
  /// No mic permission requested here.
  Future<void> initialize() async {
    debugPrint('SetupController: initialize()');

    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);
    } catch (e) {
      debugPrint('🔊 player config error: $e');
    }

    _setStage(SetupStage.intro);
    await _playAndWait(_SetupAudio.intro);
    if (_disposed) return;

    _setStage(SetupStage.idle);
  }

  @override
  void dispose() {
    debugPrint('SetupController: dispose()');
    _disposed = true;
    _speech.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Called by the view after it has navigated, so the flag doesn't fire twice.
  void clearNavigationFlag() => _shouldNavigate = false;

  // ──────────────────────────────────────────────────────────────────
  // Public taps
  // ──────────────────────────────────────────────────────────────────

  /// Single tap → start the voice flow. Ignored during intro & saving.
  Future<void> onSingleTap() async {
    if (inputLocked) return;
    if (_stage == SetupStage.manual) return; // tap doesn't fire in manual UI
    debugPrint('👆 onSingleTap (stage=$_stage)');

    await _cancelEverything();
    await _runVoiceFlow();
  }

  /// Double tap → manual mode. Ignored during intro.
  Future<void> onDoubleTap() async {
    if (_stage == SetupStage.intro) return;
    debugPrint('👆👆 onDoubleTap → manual');

    await _cancelEverything();
    _setStage(SetupStage.manual);
  }

  // ──────────────────────────────────────────────────────────────────
  // Voice flow
  // ──────────────────────────────────────────────────────────────────
  Future<void> _runVoiceFlow() async {
    // 1. Play start_listening
    _setStage(SetupStage.startingListen);
    await _playAndWait(_SetupAudio.startListening);
    if (_disposed || _stage != SetupStage.startingListen) return;

    // 2. Request microphone permission
    final mic = await ph.Permission.microphone.request();
    if (!mic.isGranted) {
      debugPrint('🎙️ mic permission denied');
      _setStage(SetupStage.idle);
      return;
    }

    // 3. Initialize STT lazily
    if (!_speechAvailable) {
      _speechAvailable = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError:  _onSpeechError,
      );
    }
    if (!_speechAvailable) {
      debugPrint('🎙️ STT unavailable');
      await _handleInvalid();
      return;
    }

    // 4. Start listening
    _setStage(SetupStage.listening);
    _recognizedNumber = '';
    _heardText        = '';
    _processed        = false;

    await _speech.listen(
      localeId: 'ar_SA',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
      pauseFor:  const Duration(seconds: 6),
      listenFor: const Duration(seconds: 30),
      onResult:  _onSpeechResult,
    );
  }

  void _onSpeechStatus(String status) {
    debugPrint('🎙️ STT status: $status');
    // When listening ends naturally without a final result event firing,
    // process whatever partial we last heard so we never get stuck.
    if ((status == 'notListening' || status == 'done') &&
        _stage == SetupStage.listening &&
        !_processed) {
      _process(_heardText);
    }
  }

  void _onSpeechError(dynamic error) {
    debugPrint('🎙️ STT error: $error');
    if (_stage == SetupStage.listening && !_processed) {
      _processed = true;
      _handleInvalid();
    }
  }

  void _onSpeechResult(dynamic result) async {
    final words   = (result.recognizedWords as String?) ?? '';
    final isFinal = (result.finalResult as bool?) ?? false;
    debugPrint('🎙️ heard: "$words" final=$isFinal');

    // Live update so the user sees what's being heard.
    _heardText = words;
    notifyListeners();

    if (!isFinal) return;
    if (_processed) return;
    _process(words);
  }

  Future<void> _process(String words) async {
    if (_processed) return;
    _processed = true;
    if (_stage != SetupStage.listening) return;

    // 5. Processing audio + parse digits
    _setStage(SetupStage.processing);
    final digits = _arabicSpeechToDigits(words);
    debugPrint('🎙️ parsed: "$digits"');

    await _playAndWait(_SetupAudio.processing);
    if (_disposed || _stage != SetupStage.processing) return;

    // 6. Validate
    if (!_isValidNumber(digits)) {
      await _handleInvalid();
      return;
    }

    // 7. Confirm sequence
    _recognizedNumber = digits;
    _setStage(SetupStage.confirming);

    await _playAndWait(_SetupAudio.confirmNumber);
    if (_disposed || _stage != SetupStage.confirming) return;

    for (final ch in digits.split('')) {
      final d = int.tryParse(ch);
      if (d == null) continue;
      await _playAndWait(_SetupAudio.digit(d));
      if (_disposed || _stage != SetupStage.confirming) return;
    }

    await _playAndWait(_SetupAudio.afterConfirm);
    if (_disposed || _stage != SetupStage.confirming) return;

    // 8. Save and signal navigation
    _setStage(SetupStage.saving);
    try {
      await Prefs.saveEmergencyNumber(digits);
      _shouldNavigate = true;
      notifyListeners();
    } catch (e) {
      debugPrint('🚨 save failed: $e');
      _setStage(SetupStage.idle);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Manual mode (silent)
  // ──────────────────────────────────────────────────────────────────

  String? validateManualNumber(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) return 'الرجاء إدخال رقم الطوارئ';
    final digits = input.replaceAll(RegExp(r'[^\d]'), '');
    if (!_isValidNumber(digits)) {
      return 'يجب أن يبدأ الرقم بـ 05 ويتكون من 10 أرقام';
    }
    return null;
  }

  /// Manual save — fully silent.
  Future<bool> saveManualNumber(String rawNumber) async {
    if (_stage == SetupStage.saving) return false;
    final digits = rawNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (!_isValidNumber(digits)) return false;
    _setStage(SetupStage.saving);
    try {
      await Prefs.saveEmergencyNumber(digits);
      return true;
    } catch (e) {
      debugPrint('🚨 manual save failed: $e');
      _setStage(SetupStage.manual);
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────

  /// A valid Saudi mobile number:
  ///   - is exactly 10 digits long
  ///   - starts with "05"
  ///   - contains only digits 0–9
  bool _isValidNumber(String digits) {
    return RegExp(r'^05\d{8}$').hasMatch(digits);
  }

  /// Single source of truth for the invalid path.
  /// Plays invalid_voice_input ONLY (no further audio, per spec) and returns
  /// to idle so the user can try again.
  Future<void> _handleInvalid() async {
    if (_disposed) return;
    _setStage(SetupStage.invalid);
    await _playAndWait(_SetupAudio.invalidVoice);
    if (_disposed) return;
    _setStage(SetupStage.idle);
  }

  Future<void> _cancelEverything() async {
    _processed  = true; // prevent stray late callbacks from triggering process
    _heardText  = '';
    try { await _audioPlayer.stop(); } catch (_) {}
    if (_speech.isListening) {
      try { await _speech.cancel(); } catch (_) {}
    }
  }

  void _setStage(SetupStage s) {
    if (_disposed) return;
    _stage = s;
    notifyListeners();
  }

  Future<void> _playAndWait(String path) async {
    debugPrint('🔊 play: $path');
    final completer = Completer<void>();
    final sub = _audioPlayer.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(path));
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => debugPrint('🔊 audio timeout: $path'),
      );
    } catch (e) {
      debugPrint('🔊 audio error ($path): $e');
    } finally {
      await sub.cancel();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Arabic speech → digits (0-9)
// ─────────────────────────────────────────────────────────────────────────────

String _arabicSpeechToDigits(String text) {
  if (text.isEmpty) return '';

  const eastern = '٠١٢٣٤٥٦٧٨٩';
  const arabicWordToDigit = <String, String>{
    'صفر': '0', 'سفر': '0',
    'واحد': '1', 'وحد': '1',
    'اثنان': '2', 'اثنين': '2', 'إثنان': '2', 'إثنين': '2', 'تنين': '2',
    'ثلاثة': '3', 'ثلاث': '3',
    'أربعة': '4', 'اربعة': '4', 'أربع': '4', 'اربع': '4',
    'خمسة': '5', 'خمس': '5',
    'ستة': '6', 'ست': '6',
    'سبعة': '7', 'سبع': '7',
    'ثمانية': '8', 'ثماني': '8', 'تمانية': '8',
    'تسعة': '9', 'تسع': '9',
  };

  final buf = StringBuffer();

  // ASCII digits & Eastern Arabic numerals embedded in the text
  for (final ch in text.split('')) {
    if (RegExp(r'[0-9]').hasMatch(ch)) { buf.write(ch); continue; }
    final i = eastern.indexOf(ch);
    if (i >= 0) buf.write(i);
  }

  // Spelled-out Arabic words
  for (final raw in text.split(RegExp(r'\s+'))) {
    final w = raw.replaceAll(RegExp(r'[^؀-ۿ]'), '');
    final mapped = arabicWordToDigit[w];
    if (mapped != null) buf.write(mapped);
  }

  return buf.toString();
}
