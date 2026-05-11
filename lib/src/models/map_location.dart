import 'package:maplibre_gl/maplibre_gl.dart';

class MapLocation {
  final double latitude;
  final double longitude;
  final String? id;

  const MapLocation({
    required this.latitude,
    required this.longitude,
    this.id,
  });

  MapLocation copyWith({
    double? latitude,
    double? longitude,
    String? id,
  }) {
    return MapLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      id: id ?? this.id,
    );
  }

  MapLocation.fromLatLng(LatLng position)
      : latitude = position.latitude,
        longitude = position.longitude,
        id = null;

  factory MapLocation.fromJson(Map<String, dynamic> json) {
    return MapLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      id: json['id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      if (id != null) 'id': id,
    };
  }

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
