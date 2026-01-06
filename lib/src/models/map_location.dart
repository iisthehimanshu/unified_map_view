import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapLocation {
  final double latitude;
  final double longitude;

  const MapLocation({
    required this.latitude,
    required this.longitude,
  });


  MapLocation.fromLatLng(LatLng position):latitude = position.latitude, longitude = position.longitude;


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is MapLocation &&
              runtimeType == other.runtimeType &&
              latitude == other.latitude &&
              longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;

  @override
  String toString() {
    return 'MapLocation{latitude: $latitude, longitude: $longitude}';
  }
}