import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:gp_hudai/core/models/landmark_point.dart';

class LocationServiceDisabledException implements Exception {
  const LocationServiceDisabledException();
}

class LocationService {
  const LocationService();

  static Position? _cachedPosition;
  static int _cachedAtMs = 0;

  Future<Position> getCurrentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const LocationServiceDisabledException();
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Fast path: recent cached GPS (keeps button response smooth).
    final cached = _cachedPosition;
    if (cached != null && (now - _cachedAtMs) <= 15000) {
      return cached;
    }

    // Fast path: last known position from OS cache.
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      _cachedPosition = lastKnown;
      _cachedAtMs = now;
      return lastKnown;
    }

    // Active GPS request with timeout to avoid long UI stalls.
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
      _cachedPosition = position;
      _cachedAtMs = now;
      return position;
    } on TimeoutException {
      // Fallback with lower accuracy if first attempt times out.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 6),
        ),
      );
      _cachedPosition = position;
      _cachedAtMs = now;
      return position;
    }
  }

  bool isInsideCircle(Position position, GeoCircle circle) {
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      circle.center.lat,
      circle.center.lng,
    );

    return distance <= circle.radiusMeters;
  }
}
