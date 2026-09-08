import '../../unified_map_view.dart';

class MapConfig {
  final UnifiedCameraPosition initialLocation;
  final bool showUserLocation;
  final bool zoomControlsEnabled;
  final bool rotateGesturesEnabled;
  final bool scrollGesturesEnabled;
  final bool tiltGesturesEnabled;
  final bool immersive;

  final void Function(dynamic controller) onMapCreated ;
  final Future<void> Function(dynamic controller) onStyleLoadedCallback ;
  final void Function(UnifiedCameraPosition position) onCameraMove;

  final void Function(UnifiedCameraPosition position)? hostOnCameraMove;

  /// Fired once the venue has actually been drawn — polygons pushed and the
  /// patch's fade opacity applied — not merely when the style or the controller
  /// is ready.
  ///
  /// Exists because "the map is ready" and "the venue is on screen" are far
  /// apart here: on web the style loads and the camera settles seconds before
  /// the venue appears (measured: camera quiet at ~14.8s, venue drawn at
  /// ~23.2s). Anything that wants to move the camera to a specific place at
  /// startup has to wait for THIS, or it aims at a map that has not drawn yet
  /// and lands on empty tiles.
  ///
  /// Fires once per venue render pass; hosts should make their handler
  /// idempotent.
  final void Function()? onVenueRendered;

  final void Function({required MapLocation coordinates, required String markerId})? onMarkerTap;
  final void Function({required List<MapLocation> coordinates, required String polygonId})? onPolygonTap;
  final void Function({required List<MapLocation> coordinates, required String polylineId})? onPolylineTap;

  const MapConfig({
    required this.initialLocation,
    required this.onMapCreated,
    required this.onStyleLoadedCallback,
    required this.onCameraMove,
    this.hostOnCameraMove,
    this.showUserLocation = true,
    this.zoomControlsEnabled = true,
    this.rotateGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.onVenueRendered,
    this.onMarkerTap,
    this.onPolygonTap,
    this.onPolylineTap,
    this.immersive = true

  });

  MapConfig copyWith({
    void Function(dynamic controller)? onMapCreated,
    Future<void> Function(dynamic controller)? onStyleLoadedCallback,
    void Function(UnifiedCameraPosition position)? onCameraMove,
    void Function(UnifiedCameraPosition position)? hostOnCameraMove,
    UnifiedCameraPosition? initialLocation,
    double? initialZoom,
    bool? showUserLocation,
    bool? zoomControlsEnabled,
    bool? rotateGesturesEnabled,
    bool? scrollGesturesEnabled,
    bool? tiltGesturesEnabled,
    bool? immersive,
   void Function()? onVenueRendered,
   void Function({required MapLocation coordinates, required String markerId})? onMarkerTap,
   void Function({required List<MapLocation> coordinates, required String polygonId})? onPolygonTap,
   void Function({required List<MapLocation> coordinates, required String polylineId})? onPolylineTap
  }) {
    return MapConfig(
      onMapCreated: onMapCreated ?? this.onMapCreated,
      onCameraMove: onCameraMove ?? this.onCameraMove,
      hostOnCameraMove: hostOnCameraMove ?? this.hostOnCameraMove,
      initialLocation: initialLocation ?? this.initialLocation,
      showUserLocation: showUserLocation ?? this.showUserLocation,
      zoomControlsEnabled: zoomControlsEnabled ?? this.zoomControlsEnabled,
      rotateGesturesEnabled: rotateGesturesEnabled ?? this.rotateGesturesEnabled,
      scrollGesturesEnabled: scrollGesturesEnabled ?? this.scrollGesturesEnabled,
      tiltGesturesEnabled: tiltGesturesEnabled ?? this.tiltGesturesEnabled,
      onVenueRendered: onVenueRendered ?? this.onVenueRendered,
      onMarkerTap: onMarkerTap ?? this.onMarkerTap,
      onPolygonTap: onPolygonTap ?? this.onPolygonTap,
      onPolylineTap: onPolylineTap ?? this.onPolylineTap, onStyleLoadedCallback:onStyleLoadedCallback??this.onStyleLoadedCallback,
        immersive:immersive??this.immersive
    );
  }
}