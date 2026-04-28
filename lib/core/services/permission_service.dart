import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class PermissionService {
  const PermissionService();

  bool get _isIosSimulator {
    if (!Platform.isIOS) return false;
    return Platform.environment.containsKey('SIMULATOR_DEVICE_NAME') ||
        Platform.environment.containsKey('SIMULATOR_UDID');
  }

  Future<bool> ensureLocationPermission({
    bool openSettingsIfDeniedForever = false,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('PERM Location: service disabled');
      return false;
    }

    var status = await Geolocator.checkPermission();
    debugPrint('PERM Location BEFORE: $status');

    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }

    debugPrint('PERM Location AFTER: $status');

    final granted = status == LocationPermission.always ||
        status == LocationPermission.whileInUse;

    if (!granted &&
        status == LocationPermission.deniedForever &&
        openSettingsIfDeniedForever) {
      await openAppSettings();
    }

    return granted;
  }

  Future<bool> ensureCameraPermission({
    bool openSettingsIfDeniedForever = true,
  }) async {
    // في محاكي iOS لا تعمل صلاحية الكاميرا كسلوك جهاز حقيقي.
    // نعتبرها مسموحة لتكملة التدفق أثناء التطوير.
    if (_isIosSimulator) {
      debugPrint('PERM Camera: iOS Simulator detected, skipping prompt.');
      return true;
    }

    var status = await ph.Permission.camera.status;
    debugPrint('PERM Camera BEFORE: $status');

    if (status.isDenied) {
      status = await ph.Permission.camera.request();
    }

    debugPrint('PERM Camera AFTER: $status');

    if (status.isPermanentlyDenied && openSettingsIfDeniedForever) {
      await openAppSettings();
    }

    return status.isGranted;
  }

  Future<bool> ensurePhonePermission({
    bool openSettingsIfDeniedForever = true,
  }) async {
    if (!Platform.isAndroid) return true;

    var status = await ph.Permission.phone.status;
    debugPrint('PERM Phone BEFORE: $status');

    if (status.isDenied) {
      status = await ph.Permission.phone.request();
    }

    debugPrint('PERM Phone AFTER: $status');

    if (status.isPermanentlyDenied && openSettingsIfDeniedForever) {
      await openAppSettings();
    }

    return status.isGranted;
  }

  Future<bool> ensureAllPermissions({
    bool openSettingsIfDeniedForever = true,
  }) async {
    final location = await ensureLocationPermission(
      openSettingsIfDeniedForever: openSettingsIfDeniedForever,
    );
    final camera = await ensureCameraPermission(
      openSettingsIfDeniedForever: openSettingsIfDeniedForever,
    );
    final phone = await ensurePhonePermission(
      openSettingsIfDeniedForever: openSettingsIfDeniedForever,
    );

    return location && camera && phone;
  }

  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}