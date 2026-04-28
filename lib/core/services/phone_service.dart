import 'dart:io';

import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:gp_hudai/core/services/permission_service.dart';
import 'package:gp_hudai/core/storage/prefs.dart';
import 'package:url_launcher/url_launcher.dart';

class PhoneService {
  const PhoneService();

  static const String defaultEmergencyNumber = '911';
  static const PermissionService _permissionService = PermissionService();

  Future<bool> callEmergency([String number = defaultEmergencyNumber]) async {
    final savedNumber = await Prefs.getEmergencyNumber();
    final targetNumber = savedNumber != null && savedNumber.trim().isNotEmpty
        ? savedNumber
        : number;
    return callNumber(targetNumber);
  }

  Future<bool> callNumber(String number) async {
    final normalized = _normalizeNumber(number);
    if (normalized.isEmpty) {
      return false;
    }

    if (Platform.isAndroid) {
      final hasPermission = await _permissionService.ensurePhonePermission();
      if (!hasPermission) {
        return false;
      }

      final placed = await FlutterPhoneDirectCaller.callNumber(normalized);
      if (placed ?? false) {
        return true;
      }
    }

    final uri = Uri(scheme: 'tel', path: normalized);
    if (!await canLaunchUrl(uri)) {
      return false;
    }

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _normalizeNumber(String number) {
    final normalized = number.replaceAll(RegExp(r'[^\d]'), '');

    // لازم يبدأ بـ 05
    if (!normalized.startsWith('05')) {
      return '';
    }

    // لازم 10 أرقام
    if (normalized.length != 10) {
      return '';
    }

    return normalized;
  }
}