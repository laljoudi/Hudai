import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:gp_hudai/core/models/landmark_point.dart';

class LocationServiceDisabledException implements Exception {
  const LocationServiceDisabledException();
}

class LocationService {
  const LocationService();

 Future<Position> getCurrentPosition() async {
  final enabled = await Geolocator.isLocationServiceEnabled();
  if (!enabled) throw const LocationServiceDisabledException();

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      timeLimit: Duration(seconds: 8),
    ),
  );
}

  bool isInsideCircle(Position position, GeoCircle circle) {
    final distance = distanceToCircleCenter(position, circle);

    return distance <= circle.radiusMeters;
  }

  double distanceToCircleCenter(Position position, GeoCircle circle) {
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      circle.center.lat,
      circle.center.lng,
    );
  }
}
