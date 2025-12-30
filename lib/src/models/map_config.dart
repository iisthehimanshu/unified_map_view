import '../../unified_map_view.dart';

class MapConfig {
  final UnifiedCameraPosition initialLocation;
  final bool showUserLocation;
  final bool zoomControlsEnabled;
  final bool rotateGesturesEnabled;
  final bool scrollGesturesEnabled;
  final bool tiltGesturesEnabled;

  final void Function(dynamic controller) onMapCreated ;
  final void Function(UnifiedCameraPosition position) onCameraMove;

  final void Function({required MapLocation coordinates, required String polygonId})? onMarkerTap;
  final void Function({required List<MapLocation> coordinates, required String polygonId})? onPolygonTap;
  final void Function({required List<MapLocation> coordinates, required String polylineId})? onPolylineTap;

  const MapConfig({
    required this.initialLocation,
    required this.onMapCreated,
    required this.onCameraMove,
    this.showUserLocation = true,
    this.zoomControlsEnabled = true,
    this.rotateGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.onMarkerTap,
    this.onPolygonTap,
    this.onPolylineTap,
  });

  MapConfig copyWith({
    void Function(dynamic controller)? onMapCreated,
    void Function(UnifiedCameraPosition position)? onCameraMove,
    UnifiedCameraPosition? initialLocation,
    double? initialZoom,
    bool? showUserLocation,
    bool? zoomControlsEnabled,
    bool? rotateGesturesEnabled,
    bool? scrollGesturesEnabled,
    bool? tiltGesturesEnabled,
   void Function({required MapLocation coordinates, required String polygonId})? onMarkerTap,
   void Function({required List<MapLocation> coordinates, required String polygonId})? onPolygonTap,
   void Function({required List<MapLocation> coordinates, required String polylineId})? onPolylineTap
  }) {
    return MapConfig(
      onMapCreated: onMapCreated ?? this.onMapCreated,
      onCameraMove: onCameraMove ?? this.onCameraMove,
      initialLocation: initialLocation ?? this.initialLocation,
      showUserLocation: showUserLocation ?? this.showUserLocation,
      zoomControlsEnabled: zoomControlsEnabled ?? this.zoomControlsEnabled,
      rotateGesturesEnabled: rotateGesturesEnabled ?? this.rotateGesturesEnabled,
      scrollGesturesEnabled: scrollGesturesEnabled ?? this.scrollGesturesEnabled,
      tiltGesturesEnabled: tiltGesturesEnabled ?? this.tiltGesturesEnabled,
      onMarkerTap: onMarkerTap ?? this.onMarkerTap,
      onPolygonTap: onPolygonTap ?? this.onPolygonTap,
      onPolylineTap: onPolylineTap ?? this.onPolylineTap,
    );
  }
}