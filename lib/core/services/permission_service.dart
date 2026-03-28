import 'package:flutter/foundation.dart'; 
import 'package:geolocator/geolocator.dart';

class PermissionService {
  const PermissionService();

  Future<bool> ensureLocationPermission() async {
    var status = await Geolocator.checkPermission();
    debugPrint('PERM status BEFORE: $status');

    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }

    debugPrint('PERM status AFTER: $status');

    return status == LocationPermission.always ||
        status == LocationPermission.whileInUse;
  }
}
