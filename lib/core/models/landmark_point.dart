class GeoPoint {
  final double lat;
  final double lng;

  const GeoPoint(this.lat, this.lng);
}

class GeoCircle {
  final String name;
  final GeoPoint center;
  final double radiusMeters;

  const GeoCircle({
    required this.name,
    required this.center,
    required this.radiusMeters,
  });
}
