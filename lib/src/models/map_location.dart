import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapLocation {
  final double latitude;
  final double longitude;

  final String? id;

  const MapLocation({
    required this.latitude,
    required this.longitude,
    this.id
  });


  MapLocation.fromLatLng(LatLng position):latitude = position.latitude, longitude = position.longitude, id = null;


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
    return 'MapLocation{latitude: $latitude, longitude: $longitude}'
        '${id != null ? ', id: $id' : ''}';

  }
}