import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:unified_map_view/src/config.dart';
import 'package:unified_map_view/src/database/cache/cache_controller.dart';
import 'package:unified_map_view/src/models/CameraBound.dart';
import 'package:unified_map_view/src/models/camera_position.dart';
import 'package:unified_map_view/src/models/selectedLocation.dart';
import '../utils/UnifiedMarkerCreator.dart';
import '../utils/geoJson/geoJsonUtils.dart';
import '../utils/geoJson/predefined_markers.dart';
import '../utils/renderingUtilities.dart';
import '../enums/Theme.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:http/http.dart' as http;

/// MapLibre GL implementation of BaseMapProvider
/// Supports MapLibre — an open-source vector map rendering engine
class MaplibreMapProvider extends BaseMapProvider {
  MaplibreMapController? _controller;
  final List<GeoJsonMarker> _symbols = [];
  final List<GeoJsonCircle> _circles = [];
  final List<GeoJsonMarker> _rotatingSymbols = [];
  final List<GeoJsonPolygon> _polygons = [];
  final List<GeoJsonPolyline> _lines = [];

  late MapConfig _config;

  SelectedLocation? selectedLocation;

  final String _clusterSourceId = 'markers-source';
  final String _normalTextMarkerLayerId = 'normalText-markers-layer';
  final String _normalIconMarkerLayerId = 'normalIcon-markers-layer';
  final String _customRenderingMarkerLayerId = 'customRendering-markers-layer';
  final String _fixedMarkerLayerId = 'fixed-markers-layer';
  final String _priorityMarkerLayerId = 'priority-marker-layer';
  final String _selectedMarkerLayerId = 'selected-marker-layer';
  final String _sectionMarkerLayerId = 'section-markers-layer';
  final String _patchAboveMarkerLayerId = 'patch-above-markers-layer';
  final String _subSectionMarkerLayerId = 'subSection-markers-layer';
  final String _overlapOverrideMarkerLayerId = 'overlap-override-markers-layer';

  /// Collision-fallback "dot" layer. When a normal marker loses a collision it
  /// would normally be hidden; instead we render a small dot at its location.
  /// See [_collisionBase] / [enableMarkerLayers] for the ordering that makes a
  /// loser fall back to a dot, and a dot-vs-dot loser hide entirely.
  final String _dotMarkerLayerId = 'collision-dot-markers-layer';

  /// Map image id + asset for the collision-fallback dot.
  static const String _kDotImageId = '__collision_dot__';
  static const String _kDotAssetPath =
      'packages/unified_map_view/assets/markers/room_dot.png';

  /// Marker ids for which icon/text overlap is temporarily forced on. These
  /// markers are routed into a dedicated always-visible layer (and excluded
  /// from the collision-subject normal layers) so they are never hidden by
  /// collision, until cleared.
  final Set<String> _overlapOverrideIds = {};

  final String _rotationSourceId = 'rotation-markers-source';
  final String _rotationMarkerLayerId = 'rotation-marker-layer';

  final String _circleSourceId = 'circle-source';
  final String _normalCircleLayerId = 'normal-circle-layer';

  final String _polygonSourceId = 'polygons-source';
  final String _normalPolygonLayerId = 'normal-polygons-layer';
  final String _patternPolygonLayerId = 'pattern-polygons-layer';
  final String _selectedPlainPolygonLayerId = 'selected-plain-polygon-layer';
  final String _selectedExtrudedPolygonLayerId = 'selected-extruded-polygon-layer';
  final String _patchBelowPolygonLayerId = 'patch-below-polygon-layer';
  final String _patchAbovePolygonLayerId = 'patch-above-polygon-layer';
  final String _sectionPolygonLayerId = 'section-polygon-layer';
  final String _subSectionPolygonLayerId = 'subSection-polygon-layer';
  final String _extrudedPolygonLayerId = 'extruded-polygon-layer';

  final String _polylineSourceId = 'polylines-source';
  final String _pathSolidLayerId = 'path-solid-polyline-layer';
  final String _pathOutlineLayerId = 'path-solid-outline-polyline-layer';
  final String _pathDashedLayerId = 'path-dashed-polyline-layer';
  final String _polylineLayerId = 'normal-polyline-layer';
  final String _greyOverlayLayerId = 'grey-overlay-polyline-layer';

  bool _isClusteringEnabled = false;
  bool _isPolygonLayersEnabled = false;
  bool _isPolylineLayersEnabled = false;
  bool _isCircleLayersEnabled = false;

  Size? _screenSize;
  double? _fadeOutZoom;

  // ---------------------------------------------------------------------------
  // Priority collision key
  //
  // MapLibre's symbol-sort-key: lower value = rendered first = wins collision.
  // We negate the marker priority so that a higher priority number wins.
  // All layers that participate in collision detection must declare this key.
  // ---------------------------------------------------------------------------

  /// GeoJSON property name that carries the numeric priority value.
  static const String _kPriorityKey = 'markerPriority';

  /// MapLibre expression: negate priority so higher number → lower sort key → wins.
  static const List<dynamic> _kSortKeyExpression = [
    "*",
    ["get", _kPriorityKey],
    -1,
  ];

  /// Markers whose full marker only appears from zoom 18 (text markers with
  /// collisionBase 0 and icon-with-sectionId markers with collisionBase 3000).
  /// Used to pick the dot's opacity ramp; see [enableMarkerLayers].
  static const List<dynamic> _kDotStepGroupExpression = [
    "any",
    ["==", ["get", "collisionBase"], 0],
    ["==", ["get", "collisionBase"], 3000],
  ];

  // ---------------------------------------------------------------------------
  // Styles
  // ---------------------------------------------------------------------------

  @override
  Widget buildMap({required MapConfig config, required BuildContext context, Function(UnifiedCameraPosition position)? onCameraMove}) {
    return Stack(
      children: [
        MaplibreMap(
          trackCameraPosition: true,
          initialCameraPosition: CameraPosition(
              target: LatLng(
                config.initialLocation.mapLocation.latitude,
                config.initialLocation.mapLocation.longitude,
              ),
              zoom: config.initialLocation.zoom,
              tilt: config.initialLocation.tilt,
              bearing: config.initialLocation.bearing
          ),
          styleString: osmRasterStyle,
          onMapCreated: (MaplibreMapController controller) async {
            _config = config;
            _controller = controller;

            config.onMapCreated(controller);

            // Handle feature taps (polygons & markers)
            // MapLibre signature: (Point<double> point, LatLng coordinates, String id, String layerId, Annotation? annotation)
            controller.onFeatureTapped.add((dynamic id, Point<double> point, LatLng coordinates, String layerId) async {
              print("MapLibre onFeatureTapped id $id $point $coordinates layerId $layerId");
              // if (_symbols
              //     .where((s) => s.id.toLowerCase().contains("path"))
              //     .isNotEmpty) return;
              try {
                // Query rendered features at the tap point for marker layers
                final markerFeatures = await controller.queryRenderedFeatures(
                  point,
                  [
                    _normalTextMarkerLayerId,
                    "$_normalIconMarkerLayerId-withSectionId",
                    "$_normalIconMarkerLayerId-withoutSectionId",
                    _fixedMarkerLayerId,
                    _customRenderingMarkerLayerId,
                    _priorityMarkerLayerId,
                    _rotationMarkerLayerId,
                    _dotMarkerLayerId,
                  ],
                  null,
                );

                print("queryRenderedFeatures count: ${markerFeatures.length}");

                if (markerFeatures.isNotEmpty) {
                  final feature = markerFeatures.first;
                  print(
                      "feature $feature ${feature['properties']?['id']}");
                  final markerId =
                  _extractPolygonIdFromTap(feature['properties']?['id']);
                  print("Marker tapped with ID: $markerId");

                  if (markerId != null) {
                    selectLocation(controller, markerId);
                    return;
                  }
                }

                final tappedPolygon = _hitTestPolygons(
                  coordinates.latitude,
                  coordinates.longitude,
                );

                print("tappedPolygon.id ${tappedPolygon?.id}");

                if (tappedPolygon != null &&
                    !tappedPolygon.id.toLowerCase().contains("boundary")) {
                  final polygonId = _extractPolygonIdFromTap(tappedPolygon.id);
                  if (polygonId != null &&
                      !polygonId.toLowerCase().contains("boundary")) {
                    selectLocation(controller, polygonId);
                  }
                  return;
                }

                // Fall through to polygon tap
                if (id.isNotEmpty) {
                  final polygonId = _extractPolygonIdFromTap(id);
                  if (polygonId != null &&
                      !polygonId.toLowerCase().contains("boundary")) {
                    selectLocation(controller, polygonId);
                  }
                }
              } catch (e) {
                print("Error handling feature tap: $e");
              }
            });
          },
          onStyleLoadedCallback: () async {
            if (_controller != null) {
              await config.onStyleLoadedCallback(_controller);
              // Style reload wipes ALL sources, layers, and addImage() calls —
              // reset flags so enableXxxLayers() re-creates everything cleanly.
              _isClusteringEnabled = false;
              _isPolygonLayersEnabled = false;
              _isPolylineLayersEnabled = false;
              // Registered dot images are wiped too; allow re-registration.
              _registeredDotImageIds.clear();
              _isCircleLayersEnabled = false;

              // Re-register all marker icons — style reload wipes addImage() calls
              for (final marker in [..._symbols, ..._rotatingSymbols]) {
                try {
                  await _loadMarkerIcon(_controller!, marker);
                } catch (e) {
                  print('Warning: failed to reload icon for ${marker.id}: $e');
                }
              }

              await enablePolygonLayers(_controller!);
              await enablePolylineLayers(_controller!);
              await enableCircleLayers(_controller!);
              await enableMarkerLayers(_controller!);

              // enableMarkerLayers re-pushes _symbols, but not _rotatingSymbols
              if (_rotatingSymbols.isNotEmpty) {
                await setGeoJsonSource(_controller!, _rotatingSymbols, _rotationSourceId);
              }
              // Re-push polygons, polylines, and circles that existed before reload.
              // Style reload wipes addImage() pattern bitmaps too, so re-register
              // them BEFORE re-pushing the source — otherwise fill-pattern resolves
              // to a missing image and the polygon renders grey.
              if (_polygons.isNotEmpty) {
                await Future.wait(
                  _polygons.map((polygon) async {
                    try {
                      await RenderingUtilities.registerLandmarkPattern(_controller!, polygon);
                    } catch (e) {
                      print('Warning: failed to re-register pattern for ${polygon.id}: $e');
                    }
                  }),
                );
                await _updatePolygonSource(_controller!);
              }
              if (_lines.isNotEmpty) {
                await _updatePolylineSource(_controller!);
              }
              if (_circles.isNotEmpty) {
                await _setGeoJsonCircle(_controller!);
              }
              _screenSize = MediaQuery.of(context).size;
              await _refreshPatchAboveOpacity(_controller!, screenSize: _screenSize);
            }
          },
          onCameraIdle: () async {
            if (_controller != null) {
              try {
                final cameraPos = _controller!.cameraPosition;
                if(cameraPos == null) return;
                final target = cameraPos.target;
                final bearing = cameraPos.bearing;
                final tilt = cameraPos.tilt;
                final zoom = cameraPos.zoom;
                print("tilt $tilt");
                print("zoom $zoom");
                print("bearing $bearing");
                var unifiedCameraPosition = UnifiedCameraPosition(
                    mapLocation: MapLocation(
                      latitude: target.latitude,
                      longitude: target.longitude,
                    ),
                    zoom: zoom,
                    bearing: bearing,
                    tilt: tilt
                );
                config.onCameraMove(unifiedCameraPosition);

                if(onCameraMove != null){
                  onCameraMove(unifiedCameraPosition);
                }
              } catch (e) {
                print("Error getting camera position: $e");
              }
            }
          },
          myLocationEnabled: config.showUserLocation,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          compassEnabled: false,
          rotateGesturesEnabled: config.rotateGesturesEnabled,
          scrollGesturesEnabled: config.scrollGesturesEnabled,
          tiltGesturesEnabled: config.tiltGesturesEnabled,
          zoomGesturesEnabled: config.zoomControlsEnabled,
          minMaxZoomPreference: const MinMaxZoomPreference(12.0, 23.0),
          logoViewMargins: const Point(50, 5),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  @override
  Future<void> moveCamera(
      dynamic controller, MapLocation location, double zoom) async {
    if (controller is MaplibreMapController) {
      await controller.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
      );
    }
  }

  @override
  Future<void> animateCamera(
      dynamic controller,
      MapLocation location,
      double zoom, {
        double? bearing,
        double? tilt,
        Duration? duration
      }) async {
    if (controller is MaplibreMapController) {
      if (bearing != null && tilt != null) {
        await controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(location.latitude, location.longitude),
                zoom: zoom,
                bearing: bearing,
                tilt: tilt,
              ),
            ),
            duration: duration
        );
      } else {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(location.latitude, location.longitude),
            zoom,
          ),
        );
        if (bearing != null && tilt == null) {
          await controller.animateCamera(CameraUpdate.bearingTo(bearing));
        } else if (tilt != null && bearing == null) {
          await controller.animateCamera(CameraUpdate.tiltTo(tilt));
        }
      }
    }
  }

  @override
  Future<void> setContentInsets(dynamic controller, EdgeInsets insets, {bool animated = true}) async {
    if (controller is MaplibreMapController) {
      await controller.updateContentInsets(insets, animated);
    }
  }

  Future<void> set3DViewEnabled(
      dynamic controller, {
        required bool isEnabled,
        double? tiltWhen3D,
      }) async {
    if (controller is! MaplibreMapController) return;
    if (_config.immersive == isEnabled) return;

    _config = _config.copyWith(immersive: isEnabled);

    // Keep map perspective in sync with 2D/3D state.
    final targetTilt = isEnabled ? (tiltWhen3D ?? (_config.initialLocation.tilt > 0 ? _config.initialLocation.tilt : 45.0)) : 0.0;
    await controller.animateCamera(CameraUpdate.tiltTo(targetTilt));

    // Explicitly disable extrusion rendering in 2D to avoid any residual shading.
    try {
      await controller.setLayerProperties(
        _selectedExtrudedPolygonLayerId,
        FillExtrusionLayerProperties(
          fillExtrusionColor: "#4CAF50",
          fillExtrusionHeight: ["get", "height"],
          fillExtrusionBase: ["get", "base_height"],
          fillExtrusionOpacity: isEnabled ? 1.0 : 0.0,
        ),
      );
    } catch (_) {}
    try {
      await controller.setLayerProperties(
        _extrudedPolygonLayerId,
        FillExtrusionLayerProperties(
          fillExtrusionColor: ["get", "fillColor"],
          fillExtrusionHeight: ["get", "height"],
          fillExtrusionBase: ["get", "base_height"],
          fillExtrusionOpacity: isEnabled ? 1.0 : 0.0,
        ),
      );
    } catch (_) {}
    try {
      await controller.setLayerProperties(
        _fixedMarkerLayerId,
        SymbolLayerProperties(
          visibility: isEnabled ? "none" : "visible",
        ),
      );
    } catch (_) {}

    // Rebuild polygon source so height/base_height are removed in 2D.
    await _updatePolygonSource(
      controller,
      selectPolygonId: selectedLocation?.polygon?.id,
    );
  }

  Future<void> toggle3DView(dynamic controller, {double? tiltWhen3D}) async {
    await set3DViewEnabled(
      controller,
      isEnabled: !_config.immersive,
      tiltWhen3D: tiltWhen3D,
    );
  }

  @override
  Future<MapLocation?> getCurrentLocation(dynamic controller) async {
    if (controller is MaplibreMapController) {
      try {
        final cameraPosition = controller.cameraPosition;
        if (cameraPosition == null) return null;
        return MapLocation(
          latitude: cameraPosition.target.latitude,
          longitude: cameraPosition.target.longitude,
        );
      } catch (e) {
        print('Error getting current location: $e');
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> setMapStyle(dynamic controller, String? styleJson) async {
    if (controller is MaplibreMapController && styleJson != null) {
      // await controller.setStyleString(styleJson);
    }
  }

  // ---------------------------------------------------------------------------
  // Circles
  // ---------------------------------------------------------------------------

  @override
  Future<void> addCircle(controller, GeoJsonCircle circle) async {
    if (controller is MaplibreMapController) {
      _circles.removeWhere((c) => c.id == circle.id);
      _circles.add(circle);
      try {
        await _setGeoJsonCircle(controller);
        if (circle.animated) {
          _startCircleAnimation(controller, circle);
        }
      } catch (e) {
        print("error adding circle $e");
      }
    }
  }

  @override
  Future<void> removeCircle(controller, String id) async {
    if (controller is MaplibreMapController) {
      _circles.removeWhere((c) => c.id.toLowerCase().contains(id));
      try {
        await _setGeoJsonCircle(controller);
      } catch (e) {
        print("error removing circle $e");
      }
    }
  }

  Future<void> _setGeoJsonCircle(MaplibreMapController controller) async {
    try {
      final features = _circles.map((circle) {
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [
              circle.position.longitude,
              circle.position.latitude
            ],
          },
          'properties': {
            if (circle.properties?['radius'] != null)
              'radius': circle.properties?['radius'],
          }
        };
      }).toList();

      await controller.setGeoJsonSource(_circleSourceId, {
        "type": "FeatureCollection",
        "features": features,
      });
    } catch (e) {
      print('Error updating circle source: $e');
    }
  }

  Timer? _circleAnimationTimer;
  bool _circleExpanding = true;

  void _startCircleAnimation(
      MaplibreMapController controller, GeoJsonCircle circle) {
    _circleAnimationTimer?.cancel();
    var circleRadius = circle.properties?['radius'] ?? 5.0;
    _circleAnimationTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) async {
          if (_circleExpanding) {
            circleRadius += 0.5;
            if (circleRadius >= 20.0) _circleExpanding = false;
          } else {
            circleRadius -= 0.5;
            if (circleRadius <= 5.0) _circleExpanding = true;
          }

          final double opacity = 1.0 - ((circleRadius - 5.0) / 15.0) * 0.7;

          try {
            await controller.setLayerProperties(
              _normalCircleLayerId,
              CircleLayerProperties(
                circleRadius: circleRadius,
                circleColor: '#4CAF50',
                circleOpacity: opacity * 0.3,
                circleStrokeWidth: 2.0,
                circleStrokeColor: '#4CAF50',
                circleStrokeOpacity: opacity * 0.8,
              ),
            );
          } catch (e) {
            // Ignore animation errors
          }
        });
  }

  void stopCircleAnimation() {
    _circleAnimationTimer?.cancel();
    _circleAnimationTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Markers
  // ---------------------------------------------------------------------------

  @override
  Future<void> localizeUser(controller, GeoJsonMarker marker) async {
    if (controller is MaplibreMapController) {
      if (_rotatingSymbols
          .where((e) => e.id.toLowerCase().contains("user"))
          .isNotEmpty) {
        return;
      }
      print("localizeUser ${StackTrace.current}");
      _rotatingSymbols.add(marker);
      await _loadMarkerIcon(controller, marker);
      try {
        await setGeoJsonSource(controller, _rotatingSymbols, _rotationSourceId);
        _startCompassListening(controller, _rotationSourceId);
      } catch (e) {
        print("error localizing user $e");
      }
    }
  }

  @override
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker, {String? selectedMarkerId}) async {
    if (controller is MaplibreMapController) {
      await _loadMarkerIcon(controller, marker);
      _symbols.add(marker);
      try {
        setGeoJsonSource(controller, _symbols, _clusterSourceId, selectedMarkerId: selectedMarkerId);
      } catch (e) {
        print("error adding marker $e");
      }
    }
  }

  @override
  Future<void> addMarkers(controller, List<GeoJsonMarker> markers) async {
    print("markers $markers");
    if (controller is MaplibreMapController) {
      for (var marker in markers) {
        try{
          Uint8List? iconBytes;
          if(marker.assetPath != null){
            if (marker.assetPath!.startsWith('http')) {
              final response = await CacheController().fetchWithCache(marker.assetPath!);
              iconBytes = response;
            } else {
              final bd = await rootBundle.load(marker.assetPath!);
              iconBytes = bd.buffer.asUint8List();
            }
            if (iconBytes != null) {
              await controller.addImage(marker.id, iconBytes);
            }
          }
        }catch(e){
          print("error in addMarkers $e");
        }
        _loadMarkerIcon(controller, marker);
        _symbols.add(marker);
      }
      try {
        setGeoJsonSource(controller, _symbols, _clusterSourceId);
      } catch (e) {
        print("error adding markers $e");
      }
    }
  }

  @override
  Future<void> moveUser(controller, String id, MapLocation location, Duration duration) async {
    if (controller is MaplibreMapController) {
      await _animateMarkerToPosition(controller, id, location, duration);
    }
  }

  Future<void> _updateUserLocation(MaplibreMapController controller) async {
    final features = _rotatingSymbols
        .map((marker) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [
          marker.position.longitude,
          marker.position.latitude
        ],
      },
      'properties': {
        'title': '',
        'id': marker.id,
        if (marker.iconName != null || true) 'icon': marker.id,
        'isPriority': marker.priority ?? false,
        'intractable': marker.properties?["polyId"] != null,
        if (_currentHeading != null) "bearing": _currentHeading!,
      }
    })
        .toList();

    await controller.setGeoJsonSource(_rotationSourceId, {
      "type": "FeatureCollection",
      "features": features,
    });
  }

  Future<void> _animateMarkerToPosition(
      MaplibreMapController controller,
      String id,
      MapLocation targetLocation,
      Duration duration
      ) async {
    const fps = 60;
    final steps = (duration.inMilliseconds / (1000 / fps)).round();

    final markers =
    _rotatingSymbols.where((s) => s.id.toLowerCase().contains(id));
    final circles =
    _circles.where((c) => c.id.toLowerCase().contains(id));

    if (markers.isEmpty) return;

    final marker = markers.first;
    GeoJsonCircle? circle;
    if (circles.isNotEmpty) circle = circles.first;

    final startLat = marker.position.latitude;
    final startLng = marker.position.longitude;
    final endLat = targetLocation.latitude;
    final endLng = targetLocation.longitude;

    for (int i = 1; i <= steps; i++) {
      final progress = i / steps;
      final currentLat = startLat + (endLat - startLat) * progress;
      final currentLng = startLng + (endLng - startLng) * progress;

      marker.position = MapLocation(latitude: currentLat, longitude: currentLng);
      if (circle != null) {
        circle.position =
            MapLocation(latitude: currentLat, longitude: currentLng);
      }
      await _updateUserLocation(controller);
      await _setGeoJsonCircle(controller);
      await Future.delayed(Duration(milliseconds: 1000 ~/ fps));
    }

    marker.position = targetLocation;
    if (circle != null) circle.position = targetLocation;
    await _updateUserLocation(controller);
    await _setGeoJsonCircle(controller);
  }

  /// Reads the numeric priority from a marker's properties.
  /// Returns 0 if the property is absent or not a number.
  int _markerPriority(GeoJsonMarker marker) {
    final raw = marker.properties?['priority'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  /// The per-layer base offset of the full marker's [symbolSortKey] for a
  /// collision-participating marker. Mirrors the layer filters/bases in
  /// [enableMarkerLayers] (text=0, fixed/bearing=1000, icon-withoutSectionId=
  /// 2000, icon-withSectionId=3000, customRendering=4000). Used by the dot layer
  /// so a feature's dot sorts right after its own full marker.
  int _collisionBase({
    required bool hasIcon,
    required double bearing,
    required bool customRendering,
    required bool sectionId,
  }) {
    if (bearing != 0.0) return 1000; // Layer 4: fixed/bearing
    if (!hasIcon) return 0; // Layer 1: text-only
    if (customRendering) return 4000; // Layer 3: custom rendering
    return sectionId ? 3000 : 2000; // Layer 2 / 2b: icon markers
  }

  Future<void> setGeoJsonSource(
      dynamic controller,
      List<GeoJsonMarker> symbols,
      String sourceID,
      {String? selectedMarkerId}
      ) async {
    if (controller is MaplibreMapController) {
      if (!_isClusteringEnabled) {
        print("Clustering not enabled yet");
        return;
      }

      final features = symbols.map((marker) {
        final anchor = (marker.anchor?.dx == 0.5 && marker.anchor?.dy == 0.5)
            ? "center"
            : "bottom";
        bool hasSectionId = (marker.properties?['sectionId'] != null && marker.properties?['sectionId'].isNotEmpty);
        double? entryDirection;
        if(marker.id.contains("_entryDirection") && marker.properties?['entryDirection'] != null){
          entryDirection = (marker.properties?['entryDirection'] as num).toDouble();
        }

        // Effective bearing matches the 'bearing' property written below, after
        // the entryDirection override. A truthy (non-zero) bearing routes a
        // marker into the fixed/bearing layer.
        final double effectiveBearing = entryDirection ??
            (marker.compassBasedRotation
                ? 0.0
                : ((marker.properties?["bearing"] ?? 0.0) as num).toDouble());

        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [
              marker.position.longitude,
              marker.position.latitude
            ],
          },
          'properties': {
            'title': marker.textVisibility
                ? creator.formatText(
                marker.title ?? "", TextFormat.smartWrap)
                : '',
            'id': marker.id,
            if (marker.assetPath != null) 'icon': marker.id,
            'isPriority': marker.priority ?? false,
            'intractable': marker.properties?["polyId"] != null,
            'bearing': marker.compassBasedRotation
                ? 0.0
                : (marker.properties?["bearing"] ?? 0.0),
            'iconAnchor': anchor,
            'section': marker.properties?['type'] == "Section",
            'subSection': marker.properties?['type'] == "Sub Section",
            'sectionId': hasSectionId,
            'boundary':marker.properties?["type"]=="Boundary",
            'isSelected': marker.id == selectedMarkerId,
            'customRendering':marker.customRendering,
            // POI markers bake a separate '<id>-selected' highlight image; this
            // flag tells the selected-marker layer to use it.
            'hasSelectedIcon': RenderingTheme.current.isMuseum &&
                marker.properties?['poiRef'] != null,
            'overlapOverride': _overlapOverrideIds.any((id) => marker.id.contains(id)),
            // Numeric priority used by symbolSortKey: higher value → higher sort
            // precedence (wins collision). Negated inside the layer expression.
            _kPriorityKey: _markerPriority(marker),
            // Per-feature base of the full marker's symbolSortKey. The dot layer
            // reuses this (+ a fractional offset) so each feature's dot is
            // placed right after its own full marker in the global collision
            // pass, yielding the marker → dot → hidden fallback cascade.
            'collisionBase': _collisionBase(
              hasIcon: marker.assetPath != null,
              bearing: effectiveBearing,
              customRendering: marker.customRendering,
              sectionId: hasSectionId,
            ),
            // Image id for this marker's collision-fallback dot. Per-marker dots
            // are registered under their asset path; null falls back to the
            // shared default room dot.
            'dotIcon': marker.dotAssetPath ?? _kDotImageId,
            if(entryDirection != null)'bearing':entryDirection
          }
        };
      }).toList();


      await controller.setGeoJsonSource(
        sourceID,
        {
          "type": "FeatureCollection",
          "features": features,
        },
      );
    }
  }

  StreamSubscription<CompassEvent>? _compassSub;
  double? _currentHeading;

  void _startCompassListening(
      MaplibreMapController controller, String sourceID) {
    if (_compassSub != null) return;
    _compassSub = FlutterCompass.events?.listen((event) async {
      if (event.heading == null) return;
      _currentHeading = event.heading;
      final cameraPos = controller.cameraPosition;
      if (cameraPos == null) return;

      final features = _rotatingSymbols
          .map((marker) => {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [
            marker.position.longitude,
            marker.position.latitude
          ],
        },
        'properties': {
          'title': '',
          'id': marker.id,
          if (marker.iconName != null || true) 'icon': marker.id,
          'isPriority': marker.priority ?? false,
          'intractable': marker.properties?["polyId"] != null,
          if (marker.compassBasedRotation) "bearing": event.heading!,
        }
      })
          .toList();

      await controller.setGeoJsonSource(sourceID, {
        "type": "FeatureCollection",
        "features": features,
      });
    });
  }

  /// Temporarily force icon/text overlap ON for the given marker ids so they
  /// are never hidden by collision. Reverse with [clearMarkersAllowOverlap] or
  /// [clearAllMarkersAllowOverlap].
  @override
  Future<void> setMarkersAllowOverlap(dynamic controller, List<String> markerIds) async {
    if (controller is! MaplibreMapController) return;
    if (markerIds.isEmpty) return;
    _overlapOverrideIds.addAll(markerIds);
    await setGeoJsonSource(controller, _symbols, _clusterSourceId);
  }

  /// Turn the temporary overlap override back OFF for the given marker ids.
  @override
  Future<void> clearMarkersAllowOverlap(dynamic controller, List<String> markerIds) async {
    if (controller is! MaplibreMapController) return;
    if (markerIds.isEmpty) return;
    _overlapOverrideIds.removeAll(markerIds);
    await setGeoJsonSource(controller, _symbols, _clusterSourceId);
  }

  /// Turn the temporary overlap override OFF for every marker it was set on.
  @override
  Future<void> clearAllMarkersAllowOverlap(dynamic controller) async {
    if (controller is! MaplibreMapController) return;
    if (_overlapOverrideIds.isEmpty) return;
    _overlapOverrideIds.clear();
    await setGeoJsonSource(controller, _symbols, _clusterSourceId);
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    if (controller is MaplibreMapController) {
      try {
        _symbols.removeWhere(
                (marker) => marker.id.toLowerCase().contains(markerId));
        _rotatingSymbols.forEach((symbol) {
          print("_rotatingSymbols ${symbol.id}");
        });
        if (_rotatingSymbols
            .where((m) => m.id.toLowerCase().contains(markerId))
            .isNotEmpty) {
          _compassSub?.cancel();
          _compassSub = null;
        }
        _rotatingSymbols.removeWhere(
                (marker) => marker.id.toLowerCase().contains(markerId));

        setGeoJsonSource(controller, _symbols, _clusterSourceId);
        setGeoJsonSource(controller, _rotatingSymbols, _rotationSourceId);
      } catch (e) {
        print('Error removing marker: $e');
      }
    }
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is MaplibreMapController) {
      try {
        _symbols.clear();
        setGeoJsonSource(controller, [], _clusterSourceId);
        setGeoJsonSource(controller, [], _rotationSourceId);
      } catch (e) {
        print('Error clearing markers: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Polygons
  // ---------------------------------------------------------------------------

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    if (controller is MaplibreMapController) {
      try {
        _polygons.add(polygon);
        await RenderingUtilities.registerLandmarkPattern(controller, polygon);
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding polygon: $e');
      }
    }
  }

  @override
  Future<void> addSection(controller, GeoJsonPolygon polygon) async {
    if (controller is MaplibreMapController) {
      try {
        _polygons.add(polygon);
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding section polygon: $e');
      }
    }
  }

  @override
  Future<void> addPolygons(
      dynamic controller, List<GeoJsonPolygon> polygons) async {
    if (controller is MaplibreMapController) {
      try {
        _polygons.addAll(polygons);
        await Future.wait(
          polygons.map((polygon) =>
              RenderingUtilities.registerLandmarkPattern(controller, polygon)
          ),
        );
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding polygons: $e');
      }
    }
  }

  Future<void> _updatePolygonSource(
      MaplibreMapController controller, {
        String? selectPolygonId,
      }) async {
    if (!_isPolygonLayersEnabled) {
      return;
    }

    final features = _polygons.map((polygon) {
      final String? rawType =
          polygon.properties?["type"] ?? polygon.properties?["polygonType"];
      final String? type = rawType?.toLowerCase();

      final String? fillColorHex = polygon.properties?["fillColor"];
      final String? strokeColorHex = polygon.properties?["strokeColor"];
      final String? fillColorSecondaryHex=polygon.properties?["fillColorSecondary"];

      final Color fillColor = (fillColorHex != null &&
          fillColorHex != "undefined" &&
          fillColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(fillColorHex)
          : RenderingUtilities.polygonColorMap[type]?["fillColor"] ??
          Colors.white;

      final Color strokeColor = (strokeColorHex != null &&
          strokeColorHex != "undefined" &&
          strokeColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(strokeColorHex)
          : RenderingUtilities.polygonColorMap[type]?["strokeColor"] ??
          fillColor;


      final Color fillColorSecondary = (fillColorSecondaryHex != null &&
          fillColorSecondaryHex != "undefined" &&
          fillColorSecondaryHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(fillColorSecondaryHex)
          : RenderingUtilities.polygonColorMap[type]?["fillColorSecondary"] ??
          const Color(0xffD3D3D3);

      final coordinates =
      polygon.points.map((p) => [p.longitude, p.latitude]).toList();

      double? baseHeight;
      double? height;
      bool pattern=false;

      if (polygon.properties?['baseHeight'] != null && polygon.properties?['baseHeight'].isNotEmpty && polygon.properties?['baseHeight'].toLowerCase() != "undefined") {
        baseHeight = double.tryParse(polygon.properties?['baseHeight']);
      }

      if (polygon.properties?['height'] != null && polygon.properties?['height'].isNotEmpty && polygon.properties?['height'].toLowerCase() != "undefined") {
        height = double.tryParse(polygon.properties?['height']);
        // If baseHeight exists, add it to height
        if (baseHeight != null && height != null) {
          height = height + baseHeight;
        }
      }

      if(polygon.properties?['pattern']!=null && polygon.properties?['pattern'].isNotEmpty && polygon.properties?['patternSize']!=null && polygon.properties?['patternSpacing']!=null && polygon.properties?['patternRotation']!=null){
        pattern=true;
      }

      return {
        'type': 'Feature',
        'id': polygon.id,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [coordinates],
        },
        'properties': {
          'id': polygon.id,
          'type': type ?? 'default',
          'fillColor':
          '#${RenderingUtilities.colorToMapplsHex(fillColor)}',
          'strokeColor':
          '#${RenderingUtilities.colorToMapplsHex(strokeColor)}',
          'fillColorSecondary':'#${RenderingUtilities.colorToMapplsHex(fillColorSecondary)}',
          'fillOpacity': fillColor.a,
          'isSelected': polygon.id == selectPolygonId,
          'boundary': polygon.properties?['type'] == "Boundary",
          'section': polygon.properties?['type'] == "Section",
          'subsection': polygon.properties?['type'] == "Sub Section",
          if (_config.immersive && baseHeight != null) 'base_height': baseHeight,
          if (_config.immersive && height != null) 'height': height,
          'hasPattern':pattern,
          'pattern':GeoJsonUtils.buildPatternKey(name:polygon.properties?['pattern'],size:polygon.properties?['patternSize'] ,gap: polygon.properties?['patternSpacing'],rotation:polygon.properties?['patternRotation'] ,color: polygon.properties?['patternColor']),
        }
      };
    }).toList();

    final patternKeys = features
        .where((f) => (f['properties'] as Map)['hasPattern'] == true)
        .map((f) => (f['properties'] as Map)['pattern'])
        .toList();

    await controller.setGeoJsonSource(
      _polygonSourceId,
      {
        "type": "FeatureCollection",
        "features": features,
      },
    );
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId,
      {String? exclude}) async {
    if (controller is! MaplibreMapController) return;

    _polygons.removeWhere((polygon) {
      final id = polygon.id;
      if (exclude != null && id.contains(exclude)) return false;
      return id.contains(polygonId);
    });

    await _updatePolygonSource(controller);
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is MaplibreMapController) {
      try {
        _polygons.clear();
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error clearing polygons: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Polylines
  // ---------------------------------------------------------------------------

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    if (controller is MaplibreMapController) {
      bool isWaypoint = false;
      if (polyline.properties?["lineCategory"] != null) {
        isWaypoint =
            polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
      }
      if (polyline.properties?["polygonType"] != null) {
        isWaypoint =
            polyline.properties!["polygonType"].toLowerCase() == "waypoints";
      }
      if (isWaypoint) return;
      try {
        _lines.removeWhere((line) => line.id == polyline.id);
        _lines.add(polyline);
        await _updatePolylineSource(controller);
      } catch (e) {
        print('Error adding polyline: $e');
      }
    }
  }

  @override
  Future<void> addPolylines(
      controller, List<GeoJsonPolyline> polylines) async {
    if (controller is MaplibreMapController) {
      for (var polyline in polylines) {
        bool isWaypoint = false;
        if (polyline.properties?["lineCategory"] != null) {
          isWaypoint =
              polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
        }
        if (polyline.properties?["polygonType"] != null) {
          isWaypoint = polyline.properties!["polygonType"].toLowerCase() ==
              "waypoints";
        }
        if (isWaypoint) continue;
        try {
          _lines.add(polyline);
        } catch (e) {
          print('Error adding polyline: $e');
        }
      }
      try {
        await _updatePolylineSource(controller);
      } catch (e) {
        print('Error updating polyline source: $e');
      }
    }
  }

  Future<void> _updatePolylineSource(MaplibreMapController controller) async {
    if (!_isPolylineLayersEnabled) {
      print("Polyline layers not enabled yet");
      return;
    }

    print("poyline going to add");

    final features = _lines.map((line) {
      return {
        'type': 'Feature',
        'id': line.id,
        'geometry': {
          'type': 'LineString',
          'coordinates': line.points
              .map((point) => [point.longitude, point.latitude])
              .toList(),
        },
        'properties': {
          'id': line.id,
          'type': 'default',
          'isSelected': false,
          'lineColor': line.properties?['fillColor'] ?? '#000000',
          'lineOpacity': line.properties?['fillOpacity'] ?? 1.0,
          'lineWidth': line.properties?['width']?.toDouble() ?? 4.0,
          'path': line.properties?['path'] ??
              line.id.toLowerCase().contains("path"),
          'style':line.properties?['style'],
          'isGreyOverlay': line.properties?['isGreyOverlay'] ?? false,
        }
      };
    }).toList();
    await controller.setGeoJsonSource(
      _polylineSourceId,
      {
        "type": "FeatureCollection",
        "features": features,
      },
    );
  }

  @override
  Future<void> removePolyline(dynamic controller, String polylineId) async {
    if (controller is! MaplibreMapController) return;

    _lines.removeWhere((line) => line.id.contains(polylineId));
    await _updatePolylineSource(controller);
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    if (controller is MaplibreMapController) {
      try {
        _lines.clear();
        await _updatePolylineSource(controller);
      } catch (e) {
        print('Error clearing polylines: $e');
      }
    }
  }

  /// Clear all map elements
  Future<void> clearAll(dynamic controller) async {
    await clearMarkers(controller);
    await clearPolygons(controller);
    await clearPolylines(controller);
  }

  // ---------------------------------------------------------------------------
  // Icon loading
  // ---------------------------------------------------------------------------

  final creator = UnifiedMarkerCreator();

  /// Dot image ids already registered with the current style (cleared on style
  /// reload, which wipes addImage()). Avoids re-decoding shared dot assets.
  final Set<String> _registeredDotImageIds = {};

  /// Registers the default collision-fallback dot image. A style reload wipes
  /// addImage() calls, so this is invoked again from [enableMarkerLayers].
  Future<void> _loadDotImage(MapLibreMapController controller) async {
    try {
      final bd = await rootBundle.load(_kDotAssetPath);
      await controller.addImage(_kDotImageId, bd.buffer.asUint8List());
      _registeredDotImageIds.add(_kDotImageId);
    } catch (e) {
      print("_loadDotImage $e");
    }
  }

  /// Registers a marker's custom dot image (under its asset path as the image
  /// id) so the dot layer can reference it via the feature's `dotIcon` property.
  Future<void> _loadMarkerDotIcon(
      MapLibreMapController controller, GeoJsonMarker marker) async {
    final path = marker.dotAssetPath;
    if (path == null || _registeredDotImageIds.contains(path)) return;
    try {
      Uint8List? bytes;
      if (path.startsWith('http')) {
        bytes = await CacheController().fetchWithCache(path);
      } else {
        final bd = await rootBundle.load(path);
        bytes = bd.buffer.asUint8List();
      }
      if (bytes != null) {
        await controller.addImage(path, bytes);
        _registeredDotImageIds.add(path);
      }
    } catch (e) {
      print("_loadMarkerDotIcon $e");
    }
  }

  Future<bool> _loadMarkerIcon(MapLibreMapController controller, GeoJsonMarker marker) async {
    await _loadMarkerDotIcon(controller, marker);
    if (marker.assetPath == null) return false;
    try {
      if (marker.customRendering) {
        // Museum POI marker: photo card + tail + dot + title, baked into one PNG.
        // Anchor is (0.5, 0.5) so the "center" keyword anchor lands the dot on
        // the coordinate. Same image is used for the zoomed-out "-small" variant
        // so the anchor stays consistent across the custom-render layer's zoom
        // icon swap.
        if(RenderingTheme.current.isMuseum && marker.properties?['poiRef'] != null){
          final poiMarker = await creator.createMuseumPoiMarker(
            text: marker.textVisibility ? marker.title ?? "" : "",
            imageSource: marker.assetPath,
          );
          await controller.addImage(marker.id, poiMarker.icon);
          await controller.addImage("${marker.id}-small", poiMarker.icon);
          // Highlighted (#CD084A) variant used by the selected-marker layer when
          // this POI is tapped.
          final poiSelected = await creator.createMuseumPoiMarker(
            text: marker.textVisibility ? marker.title ?? "" : "",
            imageSource: marker.assetPath,
            selected: true,
          );
          await controller.addImage("${marker.id}-selected", poiSelected.icon);
          marker.anchor = poiMarker.anchor;
          return true;
        }
        if(marker.properties?['pathStop']??false){
          final Uint8List iconBytes = await creator.createStopMarkerIcon(
            marker.title??"",
            museum: RenderingTheme.current.isMuseum,
            stopName: marker.properties?['stopName'] ?? "",
          );
          await controller.addImage(marker.id, iconBytes);
          return true;
        }else{
          double fontSize = marker.properties?["fontSize"]??14.5;
          Offset customAnchor = marker.renderAnchor ?? marker.anchor ?? const Offset(0.5, 0.5);
          // Gallery landmarks use a bold, shadowed, border-less translucent card
          // on a slightly smaller icon.
          final bool isGallery =
              marker.assetPath?.contains('Gallery.png') ?? false;
          final FontWeight pillWeight =
              isGallery ? FontWeight.w700 : FontWeight.w500;
          final double pillFontSize = isGallery ? 14.0 : fontSize;
          final Size markerImageSize = isGallery
              ? const Size(62, 62)
              : (marker.imageSize ?? const Size(85, 85));
          final Color pillColor =
              isGallery ? Colors.white.withOpacity(0.82) : Colors.white;
          MarkerIconWithAnchor markerIconWithAnchorWithText =
          await creator.createUnifiedMarker(
            imageSize: markerImageSize,
            fontSize: pillFontSize,
            text: marker.textVisibility? marker.title??"":"",
            imageSource: marker.assetPath,
            layout: MarkerLayout.vertical,
            textFormat: TextFormat.smartWrap,
            textColor: const Color(0xff000000),
            customAnchor: customAnchor,
            fontWeight: pillWeight,
            showPillBorder: !isGallery,
            pillShadow: isGallery,
            pillColor: pillColor,
            pillCornerRadius: isGallery ? 10.0 : null,
            expandCanvasForRotation: (customAnchor.dx == 0.5 && customAnchor.dy == 0.5)?false:true,
          );
          MarkerIconWithAnchor markerIconWithAnchorWithoutText =
          await creator.createUnifiedMarker(
            imageSize: markerImageSize,
            fontSize: pillFontSize,
            text: "",
            imageSource: marker.assetPath,
            layout: MarkerLayout.vertical,
            textFormat: TextFormat.smartWrap,
            textColor: const Color(0xff000000),
            customAnchor: customAnchor,
            fontWeight: pillWeight,
            showPillBorder: !isGallery,
            pillShadow: isGallery,
            pillColor: pillColor,
            pillCornerRadius: isGallery ? 10.0 : null,
          );
          final Uint8List iconBytes = markerIconWithAnchorWithText.icon;
          final Uint8List iconBytes2 = markerIconWithAnchorWithoutText.icon;
          await controller.addImage(marker.id, iconBytes);
          await controller.addImage("${marker.id}-small", iconBytes2);
          marker.anchor = markerIconWithAnchorWithText.anchor;
          return true; 
        }
      } else {
        Uint8List? iconBytes;
        if (marker.assetPath!.startsWith('http')) {
          final response = await CacheController().fetchWithCache(marker.assetPath!);
          iconBytes = response;
        } else {
          final bd = await rootBundle.load(marker.assetPath!);
          iconBytes = bd.buffer.asUint8List();
        }
        if (iconBytes != null) {
          await controller.addImage(marker.id, iconBytes);
          return true;
        }
      }
      return false;
    } catch (e) {
      print("_loadMarkerIcon $e");
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Layer initialisation
  // ---------------------------------------------------------------------------

  Future<void> enableCircleLayers(MaplibreMapController controller) async {
    try {
      await controller.addGeoJsonSource(_circleSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      await controller.addCircleLayer(
        _circleSourceId,
        _normalCircleLayerId,
        const CircleLayerProperties(
          circleRadius: 10.0,
          circleColor: '#448AFF',
          circleOpacity: 0.3,
          circleStrokeWidth: 2.0,
          circleStrokeColor: '#4CAF50',
          circleStrokeOpacity: 0.8,
        ),
        enableInteraction: false,
        belowLayerId: _rotationMarkerLayerId,
      );

      _isCircleLayersEnabled = true;
    } catch (e) {
      print('Error enabling circle layers: $e');
    }
  }

  Future<void> enableMarkerLayers(dynamic controller) async  {
    if (controller is! MapLibreMapController) return;

    try {
      await controller.addGeoJsonSource(_clusterSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      await controller.addGeoJsonSource(_rotationSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      // Register the collision-fallback dot image (style reload wipes images).
      await _loadDotImage(controller);

      // Layer 0: Collision-fallback dots.
      // One dot per collision-participating marker, drawn beneath the full
      // markers. Its symbolSortKey places each dot immediately after its own
      // full marker in MapLibre's single global collision pass:
      //   full = collisionBase + (-priority);  dot = collisionBase + 0.6 + (-priority)
      // Resulting cascade (all via native iconAllowOverlap:false placement):
      //   • 2 markers collide → winner shows full; loser's full is hidden and
      //     its small dot places in the gap (marker → dot).
      //   • marker vs existing dot → the marker's full collides with the dot and
      //     is hidden, so the marker also falls back to its dot.
      //   • 2 dots collide → the lower-priority dot is hidden.
      // The winner never shows a dot: its own dot collides with its own full.
      await controller.addSymbolLayer(
        _clusterSourceId,
        _dotMarkerLayerId,
        SymbolLayerProperties(
          symbolSortKey: ["+", ["get", "collisionBase"], 0.6, _kSortKeyExpression],
          iconImage: ["get", "dotIcon"],
          iconSize: 1.0,
          iconAnchor: "center",
          iconAllowOverlap: false,
          textAllowOverlap: false,
          // Mirror the per-type zoom visibility of the full markers: text (base
          // 0) and icon-with-sectionId (base 3000) only appear from zoom 18;
          // everything else fades in 12→14 like the normal icon markers.
          // MapLibre only allows a `zoom` expression at the very top level, so
          // we cannot nest `step`/`interpolate` over zoom inside a `case` (doing
          // so makes NSExpression(mglJSONObject:) throw an uncaught NSException
          // on iOS and aborts the app). Instead keep `interpolate` over zoom at
          // the top and move the per-feature branch into the stop outputs:
          //   • collisionBase 0/3000 → stays 0 until ~z18, then jumps to 1
          //     (near-instant step, matching the previous `step` behaviour).
          //   • everything else → fades in linearly 12→14, matching the
          //     previous `interpolate`.
          iconOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            12.0,
            ["case", _kDotStepGroupExpression, 0.0, 0.0],
            14.0,
            ["case", _kDotStepGroupExpression, 0.0, 1.0],
            17.999,
            ["case", _kDotStepGroupExpression, 0.0, 1.0],
            18.0,
            ["case", _kDotStepGroupExpression, 1.0, 1.0],
          ],
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
        ],
        enableInteraction: true,
        belowLayerId: null,
      );

      // Layer 1: Normal text markers (no icon, no bearing)
      await controller.addSymbolLayer(
          _clusterSourceId,
          _normalTextMarkerLayerId,
          SymbolLayerProperties(
            symbolSortKey: ["+", 0, _kSortKeyExpression],
            textField: ["get", "title"],
            textSize: 14,
            textColor: "#000000",
            textHaloColor: "#f8f9fa",
            textHaloWidth: 1.5,
            textAnchor: "center",
            textAllowOverlap: false,
            textOpacity: [
              "interpolate",
              ["linear"],
              ["zoom"],
              12.0, 0.0,
              14.0, 1.0
            ],
          ),
          filter: [
            "all",
            ["!", ["to-boolean", ["get", "overlapOverride"]]],
            ["!", ["to-boolean", ["get", "isPriority"]]],
            ["!", ["to-boolean", ["get", "section"]]],
            ["!", ["to-boolean", ["get", "subSection"]]],
            ["!", ["to-boolean", ["get", "boundary"]]],
            ["!", ["to-boolean", ["get", "bearing"]]],
            ["!", ["to-boolean", ["get", "icon"]]],
          ],
          enableInteraction: true,
          belowLayerId: null,
          minzoom: 18.0
      );

      // Layer 2: Normal icon markers (has icon, no bearing) — with sectionId
      await controller.addSymbolLayer(
        _clusterSourceId,
        "$_normalIconMarkerLayerId-withSectionId",
        SymbolLayerProperties(
          symbolSortKey: ["+", 3000, _kSortKeyExpression],
          iconImage: ["get", "icon"],
          iconSize: 0.8,
          iconAnchor: ["get", "iconAnchor"],
          textField: ["get", "title"],
          textSize: 14,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,
          textAnchor: "top",
          textOffset: [
            "case",
            ["==", ["get", "iconAnchor"], "bottom"],
            ["literal", [0, 0.0]],
            ["==", ["get", "iconAnchor"], "center"],
            ["literal", [0, 1.2]],
            ["literal", [0, 1.2]]
          ],
          textAllowOverlap: false,
          iconAllowOverlap: false,
          iconOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            12.0, 0.0,
            14.0, 1.0
          ],
          textOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            12.0, 0.0,
            14.0, 1.0
          ],
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["!", ["to-boolean", ["get", "bearing"]]],
          ["to-boolean", ["get", "sectionId"]],
          ["!", ["to-boolean", ["get", "customRendering"]]],
          ["to-boolean", ["get", "icon"]],
        ],
        enableInteraction: true,
        belowLayerId: _normalTextMarkerLayerId,
        minzoom: 18.0,
      );

      // Layer 2b: Normal icon markers — without sectionId
      await controller.addSymbolLayer(
        _clusterSourceId,
        "$_normalIconMarkerLayerId-withoutSectionId",
        SymbolLayerProperties(
          symbolSortKey: ["+", 2000, _kSortKeyExpression],
          iconImage: ["get", "icon"],
          iconSize: 0.8,
          iconAnchor: ["get", "iconAnchor"],
          textField: ["get", "title"],
          textSize: 14,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,
          textAnchor: "top",
          textOffset: [
            "case",
            ["==", ["get", "iconAnchor"], "bottom"],
            ["literal", [0, 0.0]],
            ["==", ["get", "iconAnchor"], "center"],
            ["literal", [0, 1.2]],
            ["literal", [0, 1.2]]
          ],
          textAllowOverlap: false,
          iconAllowOverlap: false,
          iconOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            12.0, 0.0,
            14.0, 1.0
          ],
          textOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            12.0, 0.0,
            14.0, 1.0
          ],
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["!", ["to-boolean", ["get", "bearing"]]],
          ["!", ["to-boolean", ["get", "sectionId"]]],
          ["!", ["to-boolean", ["get", "customRendering"]]],
          ["to-boolean", ["get", "icon"]],
        ],
        enableInteraction: true,
        belowLayerId: _normalTextMarkerLayerId,
      );

      // Layer 3: Custom rendering markers
      await controller.addSymbolLayer(
        _clusterSourceId,
        _customRenderingMarkerLayerId,
        SymbolLayerProperties(
          symbolSortKey: ["+", 4000, _kSortKeyExpression],
          iconImage: [
            "step",
            ["zoom"],
            ["concat", ["get", "icon"], "-small"],
            16,
            ["get", "icon"],
          ],
          // Museum POI markers (hasSelectedIcon) use a dedicated zoom curve:
          // 0.3 at z18 growing linearly to 1.0 at z22 (clamped below/above).
          // All other custom-rendering markers keep the original 14→0.2,
          // 18.3→1.0 curve. Per the iOS rule above, the zoom `interpolate`
          // stays at the top level and the per-feature branch lives in the
          // stop outputs (nesting zoom inside a `case` throws on iOS).
          iconSize: [
            "interpolate",
            ["linear"],
            ["zoom"],
            14.0,  ["case", ["to-boolean", ["get", "hasSelectedIcon"]], 0.3, 0.2],
            18.0,  ["case", ["to-boolean", ["get", "hasSelectedIcon"]], 0.3, 0.9442],
            18.3,  ["case", ["to-boolean", ["get", "hasSelectedIcon"]], 0.3525, 1.0],
            22.0,  ["case", ["to-boolean", ["get", "hasSelectedIcon"]], 1.0, 1.0],
          ],
          iconAnchor: ["get", "iconAnchor"],
          iconAllowOverlap: false,
          iconOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            12.0, 0.0,
            14.0, 1.0
          ],
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["!", ["to-boolean", ["get", "bearing"]]],
          // When selected, the marker is drawn (and highlighted) by the selected
          // layer instead; excluding it here avoids the base image colliding with
          // or peeking out from behind the highlighted one.
          ["!", ["to-boolean", ["get", "isSelected"]]],
          ["to-boolean", ["get", "customRendering"]],
          ["to-boolean", ["get", "icon"]],
        ],
        enableInteraction: true,
      );

      // Layer 4: Normal fixed/rotated markers (has bearing)
      await controller.addSymbolLayer(
        _clusterSourceId,
        _fixedMarkerLayerId,
        SymbolLayerProperties(
          symbolSortKey: ["+", 1000, _kSortKeyExpression],
          textRotate: ["get", "bearing"],
          textRotationAlignment: "map",
          textField: ["get", "title"],
          textSize: 12,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 2,
          textAnchor: "center",
          textAllowOverlap: false,
          iconImage: ["get", "icon"],
          iconSize: [
            "interpolate",
            ["linear"],
            ["zoom"],
            18, 0.0,
            22.0, 1.0,
          ],
          iconAnchor: ["get", "iconAnchor"],
          iconOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            12.0, 0.0,
            14.0, 1.0
          ],
          iconRotate: ["get", "bearing"],
          iconRotationAlignment: "map",
          iconAllowOverlap: false,
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["to-boolean", ["get", "bearing"]],
        ],
        enableInteraction: true,
        belowLayerId: _normalIconMarkerLayerId,
      );

      // Layer 5: Boundary / patch-above markers
      await controller.addSymbolLayer(
        _clusterSourceId,
        _patchAboveMarkerLayerId,
        SymbolLayerProperties(
          symbolSortKey: ["+", 10000, _kSortKeyExpression],
          iconImage: ["get", "icon"],
          iconAnchor: [
            "case",
            [
              "all",
              ["has", "title"],
              ["!=", ["get", "title"], ""]
            ],
            "bottom",
            "center"
          ],
          textField: ["get", "title"],
          textSize: 14,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,
          textAnchor: [
            "case",
            ["has", "icon"],
            "top",
            "center"
          ],
          textOffset: [
            "case",
            ["has", "icon"],
            ["literal", [0, 0.2]],
            ["literal", [0, 0]]
          ],
          textAllowOverlap: false,
          iconAllowOverlap: false,
          iconOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            12, 1.0,
            14, 0.0
          ],
          textOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            12, 1.0,
            14, 0.0
          ],
        ),
        filter: ["to-boolean", ["get", "boundary"]],
        enableInteraction: true,
        belowLayerId: _fixedMarkerLayerId,
      );

      // Layer 6: Section markers
      await controller.addSymbolLayer(
        _clusterSourceId,
        _sectionMarkerLayerId,
        SymbolLayerProperties(
          symbolSortKey: ["+", 7000, _kSortKeyExpression],
          iconImage: ["get", "icon"],
          iconSize: 0.8,
          iconAnchor: ["get", "iconAnchor"],
          textField: ["get", "title"],
          textSize: 14,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,
          textAnchor: [
            "case",
            ["has", "icon"],
            "top",
            "center"
          ],
          textOffset: [
            "case",
            ["has", "icon"],
            ["literal", [0, 0.2]],
            ["literal", [0, 0]]
          ],
          textAllowOverlap: false,
          iconAllowOverlap: false,
          iconOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            17, 1.0,
            18, 0.0
          ],
          textOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            17, 1.0,
            18, 0.0
          ],
        ),
        filter: ["to-boolean", ["get", "section"]],
        enableInteraction: true,
        belowLayerId: _fixedMarkerLayerId,
      );

      // Layer 7: SubSection markers
      await controller.addSymbolLayer(
          _clusterSourceId,
          _subSectionMarkerLayerId,
          SymbolLayerProperties(
            symbolSortKey: ["+", 6000, _kSortKeyExpression],
            iconImage: ["get", "icon"],
            iconSize: 1.5,
            textField: ["get", "title"],
            textSize: 12,
            textColor: "#000000",
            textHaloColor: "#f8f9fa",
            textHaloWidth: 2,
            textAnchor: "center",
            iconAllowOverlap: false,
            textAllowOverlap: false,
            iconOpacity: [
              "interpolate",
              ["linear"],
              ["zoom"],
              12.0, 0.0,
              14.0, 1.0
            ],
            textOpacity: [
              "interpolate",
              ["linear"],
              ["zoom"],
              12.0, 0.0,
              14.0, 1.0
            ],
          ),
          filter: ["to-boolean", ["get", "subSection"]],
          enableInteraction: true,
          belowLayerId: _fixedMarkerLayerId,
          maxzoom: 18.0,
          minzoom: 17.0
      );

      // Layer 8: Rotation markers (separate source)
      await controller.addSymbolLayer(
        _rotationSourceId,
        _rotationMarkerLayerId,
        SymbolLayerProperties(
          symbolSortKey: ["+", 9000, _kSortKeyExpression],
          iconImage: ["get", "icon"],
          iconSize: 1.5,
          iconRotate: ["get", "bearing"],
          iconRotationAlignment: "map",
          iconAllowOverlap: true,
        ),
        enableInteraction: true,
        belowLayerId: _sectionMarkerLayerId,
      );

      // Layer 9: isPriority markers
      await controller.addSymbolLayer(
        _clusterSourceId,
        _priorityMarkerLayerId,
        SymbolLayerProperties(
          symbolSortKey: ["+", 5000, _kSortKeyExpression],
          iconImage: ["get", "icon"],
          iconSize: 1.5,
          iconAllowOverlap: true,
          textAllowOverlap: false,
        ),
        filter: ["to-boolean", ["get", "isPriority"]],
        enableInteraction: true,
        belowLayerId: null,
      );

      // Layer 9b: Temporary allow-overlap override markers.
      // Mirrors the normal icon-marker styling but with icon/text overlap forced
      // on, so toggled markers stay visible regardless of collision. Excludes
      // priority/structural markers (they are handled by their own layers).
      await controller.addSymbolLayer(
        _clusterSourceId,
        _overlapOverrideMarkerLayerId,
        SymbolLayerProperties(
          symbolSortKey: ["+", 15000, _kSortKeyExpression],
          iconImage: ["get", "icon"],
          iconSize: 0.8,
          iconAnchor: ["get", "iconAnchor"],
          textField: ["get", "title"],
          textSize: 14,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,
          textAnchor: "top",
          textOffset: [
            "case",
            ["==", ["get", "iconAnchor"], "bottom"],
            ["literal", [0, 0.0]],
            ["==", ["get", "iconAnchor"], "center"],
            ["literal", [0, 1.2]],
            ["literal", [0, 1.2]]
          ],
          iconAllowOverlap: false,
          textAllowOverlap: false,
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "overlapOverride"]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
        ],
        enableInteraction: true,
        belowLayerId: null,
      );

      // Layer 10: Selected marker
      await controller.addSymbolLayer(
        _clusterSourceId,
        _selectedMarkerLayerId,
        SymbolLayerProperties(
          symbolSortKey: ["+", 8000, _kSortKeyExpression],
          iconImage: [
            "case",
            ["to-boolean", ["get", "hasSelectedIcon"]],
            ["concat", ["get", "icon"], "-selected"],
            ["get", "icon"],
          ],
          iconSize: [
            "interpolate",
            ["linear"],
            ["zoom"],
            13,  0.2,
            18,  1.5,
          ],
          iconAllowOverlap: false,
          textAllowOverlap: false,
        ),
        filter: ["to-boolean", ["get", "isSelected"]],
        enableInteraction: true,
        belowLayerId: null,
      );

      _isClusteringEnabled = true;

      if (_symbols.isNotEmpty) {
        final symbols = [..._symbols];
        setGeoJsonSource(controller, symbols, _clusterSourceId);
      }
    } catch (e, stack) {
      print('Error enabling marker layers: $e');
      print('Stack trace: $stack');
    }
  }

  Future<void> enablePolygonLayers(MaplibreMapController controller) async {
    try {
      await controller.addGeoJsonSource(_polygonSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      /// 1️⃣ SECTION (TOP-MOST among polygon layers)
      await controller.addFillLayer(
        _polygonSourceId,
        _sectionPolygonLayerId,
        const FillLayerProperties(
          fillColor: ["get", "fillColor"],
          fillOpacity: [
            "interpolate", ["linear"], ["zoom"],
            16, 0.0,
            17, 1.0,
            17.5, 0.0
          ],
          fillOutlineColor: ["get", "strokeColor"],
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "section"]],
          ["!", ["to-boolean", ["get", "subsection"]]],
          ["!", ["has", "height"]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        enableInteraction: false,
        belowLayerId: _polylineLayerId,
      );

      /// 2️⃣ SUBSECTION
      await controller.addFillLayer(
        _polygonSourceId,
        _subSectionPolygonLayerId,
        const FillLayerProperties(
          fillColor: ["get", "fillColor"],
          fillOpacity: ["get", "fillOpacity"],
          fillOutlineColor: ["get", "strokeColor"],
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "section"]]],
          ["to-boolean", ["get", "subsection"]],
          ["!", ["has", "height"]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        enableInteraction: false,
        minzoom: 17.0,
        maxzoom: 18.0,
        belowLayerId: _sectionPolygonLayerId,
      );

      /// 3️⃣ SELECTED
      await controller.addFillLayer(
        _polygonSourceId,
        _selectedPlainPolygonLayerId,
        const FillLayerProperties(
          fillColor: "#4CAF50",
          fillOpacity: 0.6,
          fillOutlineColor: "#2E7D32",
        ),
        filter: [
          "all",
          ["!", ["has", "height"]],
          ["to-boolean", ["get", "isSelected"]],
        ],
        enableInteraction: true,
        belowLayerId: _subSectionPolygonLayerId,
      );

      await controller.addFillExtrusionLayer(
        _polygonSourceId,
        _selectedExtrudedPolygonLayerId,
        const FillExtrusionLayerProperties(
          fillExtrusionColor: "#4CAF50",
          fillExtrusionHeight: ["get", "height"],
          fillExtrusionBase: ["get", "base_height"],
          fillExtrusionOpacity: 1.0,
        ),
        filter: [
          "all",
          ['has', 'height'],
          ["to-boolean", ["get", "isSelected"]],
        ],
        enableInteraction: true,
        belowLayerId: _subSectionPolygonLayerId,
      );

      /// 4️⃣ EXTRUDED
      await controller.addFillExtrusionLayer(
        _polygonSourceId,
        _extrudedPolygonLayerId,
        const FillExtrusionLayerProperties(
          fillExtrusionColor: ["get", "fillColor"],
          fillExtrusionHeight: ["get", "height"],
          fillExtrusionBase: ["get", "base_height"],
          fillExtrusionOpacity: 1.0,
        ),
        filter: [
          "all",
          ['has', 'height'],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        belowLayerId: _selectedPlainPolygonLayerId,
      );

      /// 5️⃣ NORMAL
      await controller.addFillLayer(
        _polygonSourceId,
        _normalPolygonLayerId,
        const FillLayerProperties(
          fillColor: ["get", "fillColor"],
          fillOpacity: ["get", "fillOpacity"],
          fillOutlineColor: ["get", "strokeColor"],
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subsection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
          ["!", ["has", "height"]],
        ],
        enableInteraction: true,
        belowLayerId: _extrudedPolygonLayerId,
      );

      /// 6️⃣ NORMAL with texture
      await controller.addFillLayer(
        _polygonSourceId,
        _patternPolygonLayerId,
        const FillLayerProperties(
          fillColor: ["get", "fillColor"],
          fillOpacity: ["get", "fillOpacity"],
          fillOutlineColor: ["get", "strokeColor"],
          fillPattern: ["get", "pattern"],
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subsection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["to-boolean", ["get", "hasPattern"]],
        ],
        enableInteraction: true,
        belowLayerId: _extrudedPolygonLayerId,
      );

      /// 7️⃣ PATCH BELOW (zoom >= 14 → bottom-most)
      await controller.addFillLayer(
        _polygonSourceId,
        _patchBelowPolygonLayerId,
        const FillLayerProperties(
          fillColor: ["get", "fillColor"],
          fillOpacity: ["get", "fillOpacity"],
          fillOutlineColor: ["get", "strokeColor"],
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "boundary"]],
          ["!", ["has", "height"]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        enableInteraction: false,
        minzoom: 13.5,
        belowLayerId: _normalPolygonLayerId,
      );

      /// 8️⃣ PATCH ABOVE (zoom < 14 → top-most)
      await controller.addFillLayer(
        _polygonSourceId,
        _patchAbovePolygonLayerId,
        const FillLayerProperties(
          fillColor: ["get", "fillColorSecondary"],
          fillOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            13, 1.0,
            14, 0.0
          ],
          fillOutlineColor: ["get", "strokeColor"],
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "boundary"]],
          ["!", ["has", "height"]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        enableInteraction: false,
        belowLayerId: _polylineLayerId,
      );

      _isPolygonLayersEnabled = true;

      if (_polygons.isNotEmpty) {
        await _updatePolygonSource(controller);
      }
    } catch (e, stack) {
      print('Error enabling polygon layers: $e');
      print('Stack trace: $stack');
    }
  }

  Future<void> _refreshPatchAboveOpacity(
      MaplibreMapController controller, {
        Size? screenSize,
      }) async {
    final boundaryPolygons = _polygons.where((p) =>
    p.properties?['type']?.toString().toLowerCase() == 'boundary'
    ).toList();

    final fitZoom = _calculateFitZoom(
      boundaryPolygons.isNotEmpty ? boundaryPolygons : _polygons,
      screenSize: screenSize,
    ) - 2.0;

    final fadeOutZoom = fitZoom;
    final fadeInZoom  = fitZoom - 0.5;

    _fadeOutZoom = fadeOutZoom;

    // 1. Boundary polygon fade layer
    await controller.setLayerProperties(
      _patchAbovePolygonLayerId,
      FillLayerProperties(
        fillColor: ["get", "fillColorSecondary"],
        fillOpacity: [
          "interpolate", ["linear"], ["zoom"],
          fadeInZoom, 1.0,
          fadeOutZoom, 0.0,
        ],
      ),
    );

    // 2. Boundary marker fade layer — remove and re-add to update maxzoom
    await controller.removeLayer(_patchAboveMarkerLayerId);
    await controller.addSymbolLayer(
      _clusterSourceId,
      _patchAboveMarkerLayerId,
      SymbolLayerProperties(
        symbolSortKey: ["+", 10000, _kSortKeyExpression],
        iconImage: ["get", "icon"],
        iconAnchor: [
          "case",
          ["all", ["has", "title"], ["!=", ["get", "title"], ""]],
          "bottom",
          "center"
        ],
        textField: ["get", "title"],
        textSize: 14,
        textColor: "#000000",
        textHaloColor: "#f8f9fa",
        textHaloWidth: 1.5,
        textAnchor: ["case", ["has", "icon"], "top", "center"],
        textOffset: [
          "case",
          ["has", "icon"],
          ["literal", [0, 0.2]],
          ["literal", [0, 0]]
        ],
        textAllowOverlap: true,
        iconAllowOverlap: true,
        iconOpacity: [
          "interpolate", ["linear"], ["zoom"],
          fadeInZoom, 1.0,
          fadeOutZoom, 0.0,
        ],
        textOpacity: [
          "interpolate", ["linear"], ["zoom"],
          fadeInZoom, 1.0,
          fadeOutZoom, 0.0,
        ],
      ),
      filter: ["to-boolean", ["get", "boundary"]],
      enableInteraction: true,
      belowLayerId: _fixedMarkerLayerId,
      maxzoom: fadeOutZoom,
    );

    print("fadeOutZoom $fadeOutZoom");

    await controller.setLayerProperties(
      _sectionPolygonLayerId,
      FillLayerProperties(
        fillOpacity: [
          "interpolate", ["linear"], ["zoom"],
          fadeOutZoom + 1.5, 1.0,
          fadeOutZoom + 2.0, 0.0,
        ],
      ),
    );
    await controller.removeLayer(_sectionMarkerLayerId);
    await controller.addSymbolLayer(
      _clusterSourceId,
      _sectionMarkerLayerId,
      SymbolLayerProperties(
        symbolSortKey: ["+", 7000, _kSortKeyExpression],
        iconImage: ["get", "icon"],
        iconSize: 0.8,
        iconAnchor: ["get", "iconAnchor"],
        textField: ["get", "title"],
        textSize: 14,
        textColor: "#000000",
        textHaloColor: "#f8f9fa",
        textHaloWidth: 1.5,
        textAnchor: [
          "case",
          ["has", "icon"],
          "top",
          "center"
        ],
        textOffset: [
          "case",
          ["has", "icon"],
          ["literal", [0, 0.2]],
          ["literal", [0, 0]]
        ],
        textAllowOverlap: false,
        iconAllowOverlap: false,
        iconOpacity: [
          "interpolate",
          ["linear"],
          ["zoom"],
          fadeOutZoom+1.5, 1.0,
          fadeOutZoom+2.0, 0.0
        ],
        textOpacity: [
          "interpolate",
          ["linear"],
          ["zoom"],
          fadeOutZoom+1.5, 1.0,
          fadeOutZoom+2.0, 0.0
        ],
      ),
      filter: ["to-boolean", ["get", "section"]],
      enableInteraction: true,
      belowLayerId: _fixedMarkerLayerId,
    );

    await _refreshMarkerLayerMinZooms(controller, fadeOutZoom);
  }

  Future<void> _refreshMarkerLayerMinZooms(
      MaplibreMapController controller,
      double fadeOutZoom,
      ) async {
    final fadeInEnd = fadeOutZoom;
    fadeOutZoom --;

    final opacityExpression = [
      "interpolate", ["linear"], ["zoom"],
      fadeOutZoom, 0.0,
      fadeInEnd,   1.0,
    ];

    await controller.setLayerProperties(
      _normalTextMarkerLayerId,
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        textOpacity: opacityExpression,
      ),
    );

    await controller.setLayerProperties(
      "$_normalIconMarkerLayerId-withSectionId",
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        iconOpacity: opacityExpression,
        textOpacity: opacityExpression,
      ),
    );

    await controller.setLayerProperties(
      "$_normalIconMarkerLayerId-withoutSectionId",
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        iconOpacity: opacityExpression,
        textOpacity: opacityExpression,
      ),
    );

    await controller.setLayerProperties(
      _customRenderingMarkerLayerId,
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        iconOpacity: opacityExpression,
      ),
    );

    await controller.setLayerProperties(
      _fixedMarkerLayerId,
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        textOpacity: opacityExpression,
      ),
    );
  }

  double _calculateFitZoom(List<GeoJsonPolygon> polygons, {Size? screenSize}) {
    if (polygons.isEmpty) return 13.0;

    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;

    for (final polygon in polygons) {
      for (final point in polygon.points) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }
    }

    const double tileSize = 256.0;

    final double mapWidthPx  = screenSize?.width  ?? 400.0;
    final double mapHeightPx = screenSize?.height ?? 800.0;

    double _latToMercatorFraction(double latDeg) {
      final sinLat = sin(latDeg * pi / 180.0);
      return (0.5 - log((1 + sinLat) / (1 - sinLat)) / (4 * pi));
    }

    final double lngFraction = (maxLng - minLng) / 360.0;
    final double latFraction = (_latToMercatorFraction(minLat) - _latToMercatorFraction(maxLat)).abs();

    double zoomForLng = double.infinity;
    double zoomForLat = double.infinity;

    if (lngFraction > 0) {
      zoomForLng = log(mapWidthPx  / tileSize / lngFraction) / ln2;
    }
    if (latFraction > 0) {
      zoomForLat = log(mapHeightPx / tileSize / latFraction) / ln2;
    }

    final double fitZoom = min(zoomForLng, zoomForLat);
    return fitZoom.clamp(1.0, 22.0);
  }

  Future<void> enablePolylineLayers(MaplibreMapController controller) async {
    try {
      await controller.addGeoJsonSource(_polylineSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      // Normal polylines (NOT path) — bottom-most
      await controller.addLineLayer(
        _polylineSourceId,
        _polylineLayerId,
        const LineLayerProperties(
          lineColor: ["get", "lineColor"],
          lineWidth: ["get", "lineWidth"],
          lineOpacity: ["get", "lineOpacity"],
        ),
        filter: ["!", ["to-boolean", ["get", "path"]]],
        enableInteraction: true,
        belowLayerId: _normalIconMarkerLayerId,
      );

      await controller.addLineLayer(
        _polylineSourceId,
        _pathOutlineLayerId,          // new layer id, e.g. 'path-solid-outline'
        const LineLayerProperties(
          lineColor: "#FFFFFF",        // white outline
          lineWidth: 14,  // will be wider via lineGapWidth trick
          lineOpacity: ["get", "lineOpacity"],
          // lineGapWidth: ["get", "lineWidth"], // ← key: pushes the outline outward
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "path"]],
          ["==", ["get", "style"], "solid"],
          ["!", ["to-boolean", ["get", "isGreyOverlay"]]],
        ],
        enableInteraction: false,       // outline doesn't need to be tappable
        belowLayerId: _pathSolidLayerId, // render BELOW the solid line
      );

      // Solid path lines
      await controller.addLineLayer(
        _polylineSourceId,
        _pathSolidLayerId,
        const LineLayerProperties(
          lineColor: ["get", "lineColor"],
          lineWidth: ["get", "lineWidth"],
          lineOpacity: ["get", "lineOpacity"],
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "path"]],
          ["==", ["get", "style"], "solid"],
          ["!", ["to-boolean", ["get", "isGreyOverlay"]]],
        ],
        enableInteraction: true,
        belowLayerId: _normalIconMarkerLayerId,
      );

      // Dashed path lines
      await controller.addLineLayer(
        _polylineSourceId,
        _pathDashedLayerId,
        LineLayerProperties(
          lineColor: ["get", "lineColor"],
          lineWidth: ["get", "lineWidth"],
          lineOpacity: ["get", "lineOpacity"],
          lineDasharray: Platform.isAndroid
              ? ["literal", [0.1, 2.0]]
              : null,
          lineCap: "round",
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "path"]],
          ["==", ["get", "style"], "dashed"],
        ],
        enableInteraction: true,
        belowLayerId: _normalIconMarkerLayerId,
      );

      // Grey overlay — above all path layers, below user marker
      await controller.addLineLayer(
        _polylineSourceId,
        _greyOverlayLayerId,
        const LineLayerProperties(
          lineColor: ["get", "lineColor"],
          lineWidth: ["get", "lineWidth"],
          lineOpacity: ["get", "lineOpacity"],
          lineCap: "round",
          lineJoin: "round",
        ),
        filter: ["to-boolean", ["get", "isGreyOverlay"]],
        enableInteraction: false,
        belowLayerId: _rotationMarkerLayerId,
      );

      _isPolylineLayersEnabled = true;

      if (_lines.isNotEmpty) {
        await _updatePolylineSource(controller);
      }
    } catch (e, stack) {
      print('Error enabling polyline layers: $e');
      print('Stack trace: $stack');
    }
  }

  // ---------------------------------------------------------------------------
  // Selection helpers
  // ---------------------------------------------------------------------------

  String? _extractPolygonIdFromTap(String key) {
    var keyMap = GeoJsonUtils.extractKeyValueMap(key);
    if (keyMap["polyId"] != null) return keyMap["polyId"];
    if (keyMap["id"] != null) return keyMap["id"];
    return null;
  }

  bool _pointInPolygon(double lat, double lng, List<MapLocation> points) {
    if (points.length < 3) return false;
    bool inside = false;
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      final xi = points[i].longitude, yi = points[i].latitude;
      final xj = points[j].longitude, yj = points[j].latitude;
      final intersects =
          ((yi > lat) != (yj > lat)) &&
              (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (intersects) inside = !inside;
      j = i;
    }
    return inside;
  }

  GeoJsonPolygon? _hitTestPolygons(double lat, double lng) {
    final hits = _polygons.where((p) =>
    !p.id.toLowerCase().contains("boundary") &&
        !p.properties?['type'].toLowerCase().contains("boundary") &&
        !p.properties?['type'].toLowerCase().contains("section") &&
        _pointInPolygon(lat, lng, p.points),
    ).toList();

    if (hits.isEmpty) return null;

    final flat = hits.where((p) {
      final h = p.properties?['height'];
      return h == null || h.toString().isEmpty || h.toString().toLowerCase() == 'undefined';
    }).toList();

    return flat.isNotEmpty ? flat.first : hits.first;
  }

  CameraBound? calculateBounds(
      controller, List<MapLocation> allPoints) {
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (var point in allPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    try {
      final latPadding = (maxLat - minLat) * 0.5;
      final lngPadding = (maxLng - minLng) * 0.5;
      return CameraBound(
        southwest: MapLocation(
            latitude: minLat - latPadding, longitude: minLng - lngPadding),
        northeast: MapLocation(
            latitude: maxLat + latPadding, longitude: maxLng + lngPadding),
      );
    } catch (e) {
      print("calculateBounds error $e");
    }
    return null;
  }

  @override
  Future<void> selectLocation(controller, String polyID) async {
    if (selectedLocation?.polyID == polyID) return;
    if (controller is! MaplibreMapController) {
      print('Error: Invalid controller type');
      return;
    }
    if (polyID.isEmpty) {
      print('Error: polyID cannot be empty');
      return;
    }

    try {
      if (selectedLocation != null) {
        await deSelectLocation(controller);
      }

      GeoJsonPolygon? polygon;
      GeoJsonMarker? marker;

      try {
        if (_symbols.isNotEmpty) {
          marker = _symbols.firstWhere(
                (m) => m.id.contains(polyID),
            orElse: () => throw Exception('Marker not found'),
          );
        }
      } catch (e) {
        print('No marker found for polyID: $polyID - $e');
        return;
      }

      String polyIDInsideMarker = polyID;
      if (marker?.id != null) {
        polyIDInsideMarker = _extractPolygonIdFromTap(marker!.id) ?? polyID;
      }
      print("polyIDInsideMarker $polyIDInsideMarker");

      try {
        if (_polygons.isNotEmpty) {
          polygon = _polygons.firstWhere(
                (p) => p.id.contains(polyID) || p.id.contains(polyIDInsideMarker),
            orElse: () => throw Exception('Polygon not found'),
          );
          if (polygon.points.length < 3) {
            print('Warning: Polygon has fewer than 3 points: ${polygon.id}');
            polygon = null;
          }
        }
      } catch (e) {
        print('No polygon found for polyID: $polyID - $e');
      }

      if (polygon == null && marker == null) {
        print('Error: Neither polygon nor marker found for polyID: $polyID');
        return;
      }

      if (polygon != null) {
        await _updatePolygonSource(controller, selectPolygonId: polygon.id);
      }

      if (marker != null) {
        await setGeoJsonSource(
          controller,
          _symbols,
          _clusterSourceId,
          selectedMarkerId: marker.id,
        );
      }

      selectedLocation = SelectedLocation(
        polyID: polyIDInsideMarker,
        polygon: polygon,
        marker: marker,
      );

      MapLocation? center;
      double? targetZoom;
      CameraBound? bounds;

      if (polygon != null && polygon.points.isNotEmpty) {
        double minLat = polygon.points.first.latitude;
        double maxLat = polygon.points.first.latitude;
        double minLng = polygon.points.first.longitude;
        double maxLng = polygon.points.first.longitude;

        for (final point in polygon.points) {
          if (point.latitude < -90 || point.latitude > 90) continue;
          if (point.longitude < -180 || point.longitude > 180) continue;
          minLat = min(minLat, point.latitude);
          maxLat = max(maxLat, point.latitude);
          minLng = min(minLng, point.longitude);
          maxLng = max(maxLng, point.longitude);
        }

        final centerLat = (minLat + maxLat) / 2;
        final centerLng = (minLng + maxLng) / 2;

        if (!centerLat.isNaN && !centerLng.isNaN &&
            !centerLat.isInfinite && !centerLng.isInfinite) {
          center = MapLocation(latitude: centerLat, longitude: centerLng);
          final maxSpan = max(maxLat - minLat, maxLng - minLng);
          targetZoom = maxSpan > 1.0 ? 8.0
              : maxSpan > 0.1 ? 12.0
              : maxSpan > 0.01 ? 15.0
              : 20.0;
          bounds = calculateBounds(controller, polygon.points);
        }
      } else if (marker != null) {
        center = marker.position;
        targetZoom = 19;
      }

      try {
        if (bounds != null) {
          fitCameraToBounds(controller, bounds);
        } else if (center != null && targetZoom != null) {
          animateCamera(controller, center, targetZoom);
        }
      } catch (e) {
        print('Warning: Failed to animate camera: $e');
      }

      if (polygon != null) {
        _config.onPolygonTap?.call(
          coordinates: polygon.points,
          polygonId: polyID,
        );
      } else if (marker != null) {
        _config.onMarkerTap?.call(
          coordinates: marker.position,
          markerId: polyID,
        );
      }
    } catch (e, stackTrace) {
      print('Error selecting location: $e\n$stackTrace');
      selectedLocation = null;
    }
  }

  Future<void> _updatePolygonSelectionState(
      MaplibreMapController controller,
      String selectPolygonId,
      bool isSelected,
      ) async {
    _updatePolygonSource(controller, selectPolygonId: isSelected ? selectPolygonId : null);
  }

  @override
  Future<void> deSelectLocation(dynamic controller) async {
    if (controller is! MaplibreMapController) {
      print('Error: Invalid controller type in deSelectLocation');
      return;
    }

    if (selectedLocation == null) return;

    final polyID = selectedLocation!.polyID;
    if (polyID.isEmpty) {
      selectedLocation = null;
      return;
    }

    try {
      await _updatePolygonSource(controller, selectPolygonId: null);

      await setGeoJsonSource(
        controller,
        _symbols,
        _clusterSourceId,
        selectedMarkerId: null,
      );

      selectedLocation = null;
    } catch (e, stackTrace) {
      print('Error deselecting location: $e\n$stackTrace');
      selectedLocation = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Zoom helpers
  // ---------------------------------------------------------------------------

  @override
  Future<void> zoom(dynamic controller, {double zoom = 0.0}) async {
    try {
      final bounds = await _controller!.getVisibleRegion();
      final centerLat =
          (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng =
          (bounds.northeast.longitude + bounds.southwest.longitude) / 2;
      final cameraPos = _controller!.cameraPosition;

      await animateCamera(
        controller,
        MapLocation(latitude: centerLat, longitude: centerLng),
        (cameraPos?.zoom ?? 0.0) + zoom,
      );
    } catch (e) {
      print("Error zoom: $e");
    }
  }

  @override
  Future<void> zoomTo(controller, double zoom) async {
    try {
      final bounds = await _controller!.getVisibleRegion();
      final centerLat =
          (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng =
          (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

      await animateCamera(
        controller,
        MapLocation(latitude: centerLat, longitude: centerLng),
        zoom,
      );
    } catch (e) {
      print("Error zoomTo: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Camera bounds
  // ---------------------------------------------------------------------------

  @override
  Future<void> fitCameraToLine(controller, GeoJsonPolyline polyline) async {
    if (polyline.points.isEmpty) return;

    double minLat = polyline.points.first.latitude;
    double maxLat = polyline.points.first.latitude;
    double minLng = polyline.points.first.longitude;
    double maxLng = polyline.points.first.longitude;

    for (final point in polyline.points) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    final latPadding = (maxLat - minLat) * 0.1;
    final lngPadding = (maxLng - minLng) * 0.1;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat - latPadding, minLng - lngPadding),
      northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
    );

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 50,
        top: 50,
        right: 50,
        bottom: 50,
      ),
    );
  }

  @override
  Future<void> fitCameraToBounds(controller, CameraBound bound) async {
    final bounds = LatLngBounds(
      southwest:
      LatLng(bound.southwest.latitude, bound.southwest.longitude),
      northeast:
      LatLng(bound.northeast.latitude, bound.northeast.longitude),
    );

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 50,
        top: 50,
        right: 50,
        bottom: 50,
      ),
      duration: const Duration(milliseconds: 2000),
    );
  }

  Future<void> addMapFade(controller) async {
    await controller.setLayerProperties(
      _patchAbovePolygonLayerId,
      FillLayerProperties(
        fillOpacity: 0.5,
        fillColor: "#FFFFFF",
      ),
    );
  }

  Future<void> removeMapFade(controller) async {
    print("removeMapFade");
    await _refreshPatchAboveOpacity(controller, screenSize: _screenSize);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _compassSub?.cancel();
    _compassSub = null;
    _circleAnimationTimer?.cancel();
    _circleAnimationTimer = null;
  }

  static const String osmRasterStyle = '''
{
  "version": 8,
  "name": "CARTO Dark No Labels",
  "glyphs": "https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf",
  "sources": {
    "osm-tiles": {
      "type": "raster",
      "tiles": [
        "https://a.basemaps.cartocdn.com/rastertiles/dark_nolabels/{z}/{x}/{y}.png",
        "https://b.basemaps.cartocdn.com/rastertiles/dark_nolabels/{z}/{x}/{y}.png",
        "https://c.basemaps.cartocdn.com/rastertiles/dark_nolabels/{z}/{x}/{y}.png",
        "https://d.basemaps.cartocdn.com/rastertiles/dark_nolabels/{z}/{x}/{y}.png"
      ],
      "tileSize": 256,
      "attribution": "© OpenStreetMap contributors © CARTO",
      "maxzoom": 20
    },
    "empty": {
      "type": "geojson",
      "data": { "type": "FeatureCollection", "features": [] }
    }
  },
  "layers": [
    {
      "id": "osm-tiles-layer",
      "type": "raster",
      "source": "osm-tiles",
      "minzoom": 0,
      "maxzoom": 23,
      "paint": {
        "raster-brightness-min": 0.18,
        "raster-brightness-max": 1.0
      }
    },
    {
      "id": "font-anchor",
      "type": "symbol",
      "source": "empty",
      "layout": {
        "text-field": "",
        "text-font": ["Open Sans Regular", "Arial Unicode MS Regular"]
      }
    }
  ]
}
''';
}