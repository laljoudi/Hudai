import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  Prefs._();

  // اسم المفتاح الذي نخزن تحته رقم الطوارئ.
  static const String emergencyNumberKey = 'emergency_number';

  static Future<void> saveEmergencyNumber(String number) async {
    // فتح التخزين المحلي.
    final prefs = await SharedPreferences.getInstance();
    // حفظ الرقم كنص.
    await prefs.setString(emergencyNumberKey, number);
  }

  static Future<String?> getEmergencyNumber() async {
    // فتح التخزين المحلي.
    final prefs = await SharedPreferences.getInstance();
    // قراءة الرقم إذا كان موجودًا.
    return prefs.getString(emergencyNumberKey);
  }

  static Future<bool> hasEmergencyNumber() async {
    // جلب الرقم ثم التأكد أنه غير فارغ.
    final number = await getEmergencyNumber();
    return number != null && number.trim().isNotEmpty;
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

