class MapLocation {
  final double latitude;
  final double longitude;

  const MapLocation({
    required this.latitude,
    required this.longitude,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is MapLocation &&
              runtimeType == other.runtimeType &&
              latitude == other.latitude &&
              longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}