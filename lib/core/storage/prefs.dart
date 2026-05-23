import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  Prefs._();

  static const _storage = FlutterSecureStorage();

  // Key used to store the emergency number in secure storage.
  static const String emergencyNumberKey = 'emergency_number';

  static Future<void> saveEmergencyNumber(String number) async {
    await _storage.write(key: emergencyNumberKey, value: number);
  }

  static Future<String?> getEmergencyNumber() async {
    return await _storage.read(key: emergencyNumberKey);
  }

  static Future<bool> hasEmergencyNumber() async {
    final number = await getEmergencyNumber();
    return number != null && number.trim().isNotEmpty;
  }

  /// Saudi mobile format: exactly 10 digits, starts with "05".
  /// Used by the splash screen to decide whether to skip the setup flow.
  static Future<bool> hasValidEmergencyNumber() async {
    final number = await getEmergencyNumber();
    if (number == null) return false;
    return RegExp(r'^05\d{8}$').hasMatch(number.trim());
  }

  // ── Camera intro audio (plays once on first visit) ────────────────────────
  static const String cameraIntroHeardKey = 'camera_intro_heard';

  static Future<bool> hasHeardCameraIntro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(cameraIntroHeardKey) ?? false;
  }

  static Future<void> markCameraIntroHeard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(cameraIntroHeardKey, true);
  }
}
