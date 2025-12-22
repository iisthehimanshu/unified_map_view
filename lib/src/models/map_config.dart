import '../../unified_map_view.dart';

class MapConfig {
  final MapLocation initialLocation;
  final double initialZoom;
  final bool showUserLocation;
  final bool zoomControlsEnabled;
  final bool rotateGesturesEnabled;
  final bool scrollGesturesEnabled;
  final bool tiltGesturesEnabled;

  const MapConfig({
    required this.initialLocation,
    this.initialZoom = 15.0,
    this.showUserLocation = true,
    this.zoomControlsEnabled = true,
    this.rotateGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
  });

  MapConfig copyWith({
    MapLocation? initialLocation,
    double? initialZoom,
    bool? showUserLocation,
    bool? zoomControlsEnabled,
    bool? rotateGesturesEnabled,
    bool? scrollGesturesEnabled,
    bool? tiltGesturesEnabled,
  }) {
    return MapConfig(
      initialLocation: initialLocation ?? this.initialLocation,
      initialZoom: initialZoom ?? this.initialZoom,
      showUserLocation: showUserLocation ?? this.showUserLocation,
      zoomControlsEnabled: zoomControlsEnabled ?? this.zoomControlsEnabled,
      rotateGesturesEnabled: rotateGesturesEnabled ?? this.rotateGesturesEnabled,
      scrollGesturesEnabled: scrollGesturesEnabled ?? this.scrollGesturesEnabled,
      tiltGesturesEnabled: tiltGesturesEnabled ?? this.tiltGesturesEnabled,
    );
  }
}