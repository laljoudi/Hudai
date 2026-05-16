import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:gp_hudai/core/storage/prefs.dart';

/// Audio file paths used by the setup screen.
/// Note: audioplayers uses paths WITHOUT the 'assets/' prefix.
class _SetupAudio {
  static const String intro = 'audio/setup/setup_intro.mp3';
  static const String startListening = 'audio/setup/start_listening.mp3';
  static const String confirmNumber = 'audio/setup/confirm_number.mp3';
  static const String processing = 'audio/setup/processing_number.mp3';
  static const String invalidVoice = 'audio/setup/invalid_voice_input.mp3';
  static const String manualIntro = 'audio/setup/manual_input_intro.mp3';
  static const String tapToSave = 'audio/setup/tap_to_save.mp3';

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
///   confirming      — confirm_number → digits → tap_to_save
///   awaitingSave    — tap_to_save finished; waiting for user gesture
///                       (single tap → retry voice; long press → save + go)
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
  awaitingSave,
  saving,
  manual,
}

/// Brain of the setup screen. The view only renders state and forwards taps.
class SetupController extends ChangeNotifier {
  // Services
  final AudioPlayer _audioPlayer = AudioPlayer();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechAvailable = false;
  bool _disposed = false;
  bool _processed = false;
  bool _userStopRequested = false;
  int _restartFailures = 0;
  String _accumulatedText = '';

  // State
  SetupStage _stage = SetupStage.intro;
  String _recognizedNumber = '';
  String _heardText = '';
  String _lastParsedDigits = '';
  bool _shouldNavigate = false;

  SetupStage get stage => _stage;
  String get recognizedNumber => _recognizedNumber;
  String get heardText => _heardText;
  String get lastParsedDigits => _lastParsedDigits;
  bool get shouldNavigate => _shouldNavigate;

  bool get isManual => _stage == SetupStage.manual;
  bool get isListening => _stage == SetupStage.listening;
  bool get inputLocked =>
      _stage == SetupStage.intro || _stage == SetupStage.saving;


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

    // طلب إذن الميكروفون + التعرف على الكلام عند فتح شاشة التسجيل
    // حتى لا يتفاجأ المستخدم لاحقًا وقت بدء الإدخال الصوتي.
    await _ensureVoicePermissions();
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

  /// Single tap behaviour:
  ///   - listening                              → stop the mic and process what was heard
  ///   - awaitingSave (post tap_to_save) → retry voice input from scratch
  ///   - otherwise                              → start the voice flow (start_listening → mic → STT)
  /// Ignored during intro & saving.
  Future<void> onSingleTap() async {
    if (inputLocked) return;
    if (_stage == SetupStage.manual) return;
    debugPrint('👆 onSingleTap (stage=$_stage)');

    // Toggle: tap while listening means "I'm done — process now".
    if (_stage == SetupStage.listening) {
      debugPrint('🛑 user requested stop');
      _userStopRequested = true;
      try {
        await _speech.stop();
      } catch (_) {}
      return;
    }

    // After tap_to_save: a single tap means "retry voice from scratch".
    if (_stage == SetupStage.awaitingSave) {
      debugPrint('🔄 awaitingSave → retry voice');
      await _cancelEverything();
      await _runVoiceFlow();
      return;
    }

    // Any other stage → start a fresh voice flow.
    await _cancelEverything();
    await _runVoiceFlow();
  }

  /// Long-press behaviour:
  ///   - awaitingSave (post tap_to_save) → save the number and navigate
  ///   - otherwise                              → ignored
  ///
  /// Long-press is intentionally scoped to the save confirmation only, so it
  /// never collides with manual-mode entry (which stays on double-tap).
  Future<void> onLongPress() async {
    if (_stage != SetupStage.awaitingSave) {
      debugPrint('👆⏱ onLongPress ignored (stage=$_stage)');
      return;
    }
    debugPrint('💾 awaitingSave → save + navigate (long press)');
    await _saveAndNavigate(_recognizedNumber);
  }

  /// Double-tap behaviour:
  ///   - Anywhere except intro → switch to manual (silent) keyboard mode
  ///
  /// Manual mode is a separate accessibility fallback. Double-tap is kept
  /// here so users can reach it without affecting the save gesture.
  Future<void> onDoubleTap() async {
    if (_stage == SetupStage.intro) return;
    debugPrint('👆👆 onDoubleTap → manual (stage=$_stage)');

    await _cancelEverything();
    _setStage(SetupStage.manual);

    await _playAndWait(_SetupAudio.manualIntro);
  }

  // ──────────────────────────────────────────────────────────────────
  // Voice flow
  // ──────────────────────────────────────────────────────────────────
  Future<bool> _ensureVoicePermissions() async {
    final micStatus = await ph.Permission.microphone.status;
    final speechStatus = await ph.Permission.speech.status;

    var mic = micStatus;
    var speech = speechStatus;

    if (mic.isDenied) {
      mic = await ph.Permission.microphone.request();
    }
    if (speech.isDenied) {
      speech = await ph.Permission.speech.request();
    }

    final granted = mic.isGranted && speech.isGranted;
    if (!granted) {
      debugPrint('🎙️ mic/speech permission denied: mic=$mic speech=$speech');
    }
    return granted;
  }

  Future<void> _runVoiceFlow() async {
    // 1. Play start_listening
    _setStage(SetupStage.startingListen);
    await _playAndWait(_SetupAudio.startListening);
    if (_disposed || _stage != SetupStage.startingListen) return;

    // 2. Request microphone + speech permissions
    final granted = await _ensureVoicePermissions();
    if (!granted) {
      _setStage(SetupStage.idle);
      return;
    }

    // 3. Initialize STT lazily
    if (!_speechAvailable) {
      _speechAvailable = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
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
    _heardText = '';
    _accumulatedText = '';
    _processed = false;
    _userStopRequested = false;
    _restartFailures = 0;

    await _speech.listen(
      localeId: 'ar_SA',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
      // Don't auto-stop on silence — user explicitly taps again to stop.
      // listenFor is just a safety upper bound.
      pauseFor: const Duration(minutes: 10),
      listenFor: const Duration(minutes: 5),
      onResult: _onSpeechResult,
    );
  }

  void _onSpeechStatus(String status) {
    debugPrint('🎙️ STT status: $status');
    // The native Android engine will auto-stop after ~10–15s even with our
    // huge pauseFor — we counter that by restarting the listen session
    // until the user actually taps to stop.
    if ((status == 'notListening' || status == 'done') &&
        _stage == SetupStage.listening &&
        !_processed) {
      if (_userStopRequested) {
        _process(_accumulatedText);
      } else {
        _restartListening();
      }
    }
  }

  void _onSpeechError(dynamic error) {
    debugPrint('🎙️ STT error: $error');
    if (_stage != SetupStage.listening || _processed) return;
    if (_userStopRequested) {
      _processed = true;
      _handleInvalid();
      return;
    }
    // Engine error mid-listen — try a few restarts before giving up.
    _restartFailures++;
    if (_restartFailures >= 4) {
      _processed = true;
      _handleInvalid();
      return;
    }
    _restartListening();
  }

  void _onSpeechResult(dynamic result) {
    final words = (result.recognizedWords as String?) ?? '';
    final isFinal = (result.finalResult as bool?) ?? false;
    debugPrint('🎙️ heard: "$words" final=$isFinal');

    // Live preview = previously-banked text + the current partial.
    final live = ('$_accumulatedText $words').trim();
    _heardText = live;

    // Bank only when the engine reports a final for this session.
    if (isFinal && words.isNotEmpty) {
      _accumulatedText = live;
    }
    notifyListeners();
  }

  /// Restart the underlying speech session without resetting the UI state.
  /// Used when the native engine stops on its own but the user hasn't
  /// tapped to end yet.
  Future<void> _restartListening() async {
    if (_disposed) return;
    if (_stage != SetupStage.listening) return;
    if (_processed) return;
    if (_userStopRequested) return;

    debugPrint('🔄 restart listen (failures=$_restartFailures)');
    // Brief pause so the previous session can fully tear down.
    await Future.delayed(const Duration(milliseconds: 250));
    if (_disposed ||
        _userStopRequested ||
        _stage != SetupStage.listening ||
        _processed)
      return;

    try {
      await _speech.listen(
        localeId: 'ar_SA',
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
        pauseFor: const Duration(minutes: 10),
        listenFor: const Duration(minutes: 5),
        onResult: _onSpeechResult,
      );
    } catch (e) {
      debugPrint('🔄 restart failed: $e');
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
    if (_stage != SetupStage.listening) return;

    // 5. Processing audio + parse digits
    _setStage(SetupStage.processing);
    final digits = _arabicSpeechToDigits(words);
    _lastParsedDigits = digits;
    debugPrint('🎙️ parsed: "$digits" (len=${digits.length})');

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

    // (No "after confirm options" clip — the tap_to_save audio below
    // already tells the user what to do next: long-press to save, or
    // single-tap to retry.)

    // Final cue once the digits are recognized + confirmed on screen.
    await _playAndWait(_SetupAudio.tapToSave);
    if (_disposed || _stage != SetupStage.confirming) return;

    // 8. Wait for the user's final gesture.
    //    Single tap → retry voice  (handled in onSingleTap)
    //    Long press → save + navigate (handled in onLongPress → _saveAndNavigate)
    _setStage(SetupStage.awaitingSave);
  }

  /// Persist the recognized number and signal navigation. Triggered by a
  /// long-press while in [SetupStage.awaitingSave].
  Future<void> _saveAndNavigate(String digits) async {
    if (_stage == SetupStage.saving) return;
    if (!_isValidNumber(digits)) {
      debugPrint('🚨 _saveAndNavigate: invalid number "$digits"');
      await _handleInvalid();
      return;
    }
    _setStage(SetupStage.saving);
    try {
      debugPrint('💾 Prefs.saveEmergencyNumber("$digits") …');
      await Prefs.saveEmergencyNumber(digits);
      debugPrint('💾   → saved OK');
      if (_disposed) {
        debugPrint('💾   → controller disposed mid-save, no notify');
        return;
      }
      _shouldNavigate = true;
      debugPrint('💾   → _shouldNavigate=true, notifying listeners');
      notifyListeners();
    } catch (e) {
      debugPrint('🚨 save failed: $e');
      _setStage(SetupStage.awaitingSave);
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
    _processed = true; // prevent stray late callbacks from triggering process
    _userStopRequested = true; // prevent stray restart attempts
    _heardText = '';
    _accumulatedText = '';
    _restartFailures = 0;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    if (_speech.isListening) {
      try {
        await _speech.cancel();
      } catch (_) {}
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
    // 0
    'صفر': '0', 'سفر': '0', 'صفرا': '0', 'صفرة': '0',
    // 1
    'واحد': '1', 'وحد': '1', 'وحدة': '1', 'واحدة': '1',
    // 2
    'اثنان': '2', 'اثنين': '2', 'إثنان': '2', 'إثنين': '2',
    'تنين': '2', 'اتنين': '2', 'إتنين': '2', 'ثنين': '2',
    // 3
    'ثلاثة': '3', 'ثلاث': '3', 'تلاتة': '3', 'تلاثة': '3', 'ثلاثه': '3',
    // 4
    'أربعة': '4', 'اربعة': '4', 'أربع': '4', 'اربع': '4', 'اربعه': '4',
    // 5
    'خمسة': '5', 'خمس': '5', 'خمسه': '5',
    // 6
    'ستة': '6', 'ست': '6', 'سته': '6', 'ستا': '6',
    // 7
    'سبعة': '7', 'سبع': '7', 'سبعه': '7',
    // 8
    'ثمانية': '8', 'ثماني': '8', 'تمانية': '8', 'تماني': '8', 'ثمانيه': '8',
    // 9
    'تسعة': '9', 'تسع': '9', 'تسعه': '9',
  };

  final buf = StringBuffer();
  final arab = RegExp(r'[؀-ۿ]');
  int i = 0;
  while (i < text.length) {
    final ch = text[i];

    // ASCII digit
    if (RegExp(r'[0-9]').hasMatch(ch)) {
      buf.write(ch);
      i++;
      continue;
    }

    // Eastern Arabic numeral (٠–٩)
    final ei = eastern.indexOf(ch);
    if (ei >= 0) {
      buf.write(ei);
      i++;
      continue;
    }

    // Arabic word — accumulate consecutive Arabic letters and look up
    if (arab.hasMatch(ch)) {
      var j = i;
      while (j < text.length && arab.hasMatch(text[j])) {
        j++;
      }
      final word = text.substring(i, j);
      final mapped = arabicWordToDigit[word];
      if (mapped != null) buf.write(mapped);
      i = j;
      continue;
    }

    i++;
  }

  return _normalizeSaudiNumber(buf.toString());
}

/// Normalize common variations of Saudi mobile numbers to the canonical
/// `05xxxxxxxx` form so validation accepts what the user actually said.
///   "+966512345678" / "00966512345678" / "966512345678"   → "0512345678"
///   "5xxxxxxxx"   (no leading 0)                           → "05xxxxxxxx"
///   "...0512345678..."  (extra noise digits around it)      → "0512345678"
String _normalizeSaudiNumber(String d) {
  // 1. Strip Saudi country code prefixes
  if (d.startsWith('00966'))
    d = '0${d.substring(5)}';
  else if (d.startsWith('966'))
    d = '0${d.substring(3)}';

  // 2. Add a leading 0 if the user dropped it ("5xxxxxxxx" → "05xxxxxxxx")
  if (d.length == 9 && d.startsWith('5')) d = '0$d';

  // 3. If we still have extra digits (from noise / repeats / etc.),
  //    try to pull a valid 05xxxxxxxx pattern out of the string.
  if (d.length != 10) {
    final m = RegExp(r'05\d{8}').firstMatch(d);
    if (m != null) return m.group(0)!;
  }

  return d;
}

