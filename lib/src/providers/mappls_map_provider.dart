// lib/src/providers/mappls_map_provider.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:unified_map_view/src/models/CameraBound.dart';
import 'package:unified_map_view/src/models/camera_position.dart';
import 'package:unified_map_view/src/models/selectedLocation.dart';
import '../utils/UnifiedMarkerCreator.dart';
import '../utils/geoJson/geoJsonUtils.dart';
import '../utils/geoJson/predefined_markers.dart';
import '../utils/renderingUtilities.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

/// Mappls GL implementation of BaseMapProvider
/// Supports Mappls (MapmyIndia) maps - India's own mapping platform
class MapplsMapProvider extends BaseMapProvider {
  MapplsMapController? _controller;
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
  final String _normalFixedMarkerLayerId = 'normalFixed-markers-layer';
  final String _priorityMarkerLayerId = 'priority-marker-layer';
  final String _sectionMarkerLayerId = 'section-markers-layer';
  final String _subSectionMarkerLayerId = 'subSection-markers-layer';

  final String _rotationSourceId = 'rotation-markers-source';
  final String _rotationMarkerLayerId = 'rotation-marker-layer';

  final String _circleSourceId = 'circle-source';
  final String _normalCircleLayerId = 'normal-circle-layer';

  final String _polygonSourceId = 'polygons-source';
  final String _normalPolygonLayerId = 'normal-polygons-layer';
  final String _selectedPolygonLayerId = 'selected-polygon-layer';
  final String _patchPolygonLayerId = 'patch-polygon-layer';
  final String _sectionPolygonLayerId = 'section-polygon-layer';
  final String _subSectionPolygonLayerId = 'subSection-polygon-layer';
  final String _extrudedPolygonLayerId = 'extruded-polygon-layer';

  final String _polylineSourceId = 'polylines-source';
  final String _pathLayerId = 'path-polyline-layer';
  final String _polylineLayerId = 'normal-polyline-layer';

  bool _isClusteringEnabled = false;
  bool _isPolygonLayersEnabled = false;
  bool _isPolylineLayersEnabled = false;
  bool _isCircleLayersEnabled = false;

  @override
  Widget buildMap({required MapConfig config, required BuildContext context}) {
    var width=MediaQuery.of(context).size.width;
    return Stack(
      children:[
        MapplsMap(
          trackCameraPosition: true,
          initialCameraPosition: CameraPosition(
            target: LatLng(
              config.initialLocation.mapLocation.latitude,
              config.initialLocation.mapLocation.longitude,
            ),
            zoom: config.initialLocation.zoom,
          ),
          onMapCreated: (MapplsMapController controller) async {
            _config = config;
            _controller = controller;

            config.onMapCreated(controller);

            // Handle polygon taps
            controller.onFeatureTapped.add((id, point, coordinates) async {
              print("Mappls onFeatureTapped id $id $point $coordinates");
              if(_symbols.where((symbol)=>symbol.id.toLowerCase().contains("path")).isNotEmpty) return;
              try {
                // Query rendered features at the tap point for marker layers
                final markerFeatures = await controller.queryRenderedFeatures(
                    point, [_normalTextMarkerLayerId, _normalIconMarkerLayerId, _normalFixedMarkerLayerId, _priorityMarkerLayerId, _rotationMarkerLayerId],null
                );

                if (markerFeatures.isNotEmpty) {
                  // Marker was tapped
                  final feature = markerFeatures.first;
                  print("feature $feature ${feature['properties']?['id']}");
                  final id = _extractPolygonIdFromTap(feature['properties']?['id']);
                  print("Marker tapped with ID: $id");

                  // Handle marker tap
                  if (id != null) {
                    selectLocation(controller, id);
                    return; // Exit early, don't process as polygon
                  }
                }

                // If no marker was found, check for polygon tap
                if (id.isNotEmpty) {
                  final polygonId = _extractPolygonIdFromTap(id);
                  if (polygonId != null && !polygonId.toLowerCase().contains("boundary")) {
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

              // Now initialize layers after style is loaded
              await enablePolygonLayers(_controller!);
              await enablePolylineLayers(_controller!);
              await enableCircleLayers(_controller!);
              await enableMarkerLayers(_controller!);

            }
          },
          onCameraIdle: () async {
            if (_controller != null) {
              try {
                final bounds = await _controller!.getVisibleRegion();

                final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
                final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;
                final cameraPos = _controller!.cameraPosition;
                // print("cameraPos tilt ${cameraPos?.tilt}");
                // print("cameraPos bearing ${cameraPos?.bearing}");
                // print("cameraPos zoom ${cameraPos?.zoom}");
                // print("cameraPos target ${cameraPos?.target}");
                config.onCameraMove(UnifiedCameraPosition(
                  mapLocation: MapLocation(
                    latitude: centerLat,
                    longitude: centerLng,
                  ),
                  zoom: cameraPos?.zoom ?? 0.0,
                  bearing: cameraPos?.bearing ?? 0.0,
                ));
              } catch (e) {
                print("Error getting camera position: $e");
              }
            }
          },
          myLocationEnabled: config.showUserLocation,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          compassEnabled: true,
          rotateGesturesEnabled: config.rotateGesturesEnabled,
          scrollGesturesEnabled: config.scrollGesturesEnabled,
          tiltGesturesEnabled: config.tiltGesturesEnabled,
          zoomGesturesEnabled: config.zoomControlsEnabled,
          minMaxZoomPreference: const MinMaxZoomPreference(0.0, 23.0),
          logoViewMargins:Point(50, 5),
        ),
        Positioned(bottom:-11,right: width*0.19,child: Row(
          children: [
            InkWell(
              onTap: () async {
                try {
                  var url = "https://www.iwayplus.com/";
                  if (await canLaunch(url)) {
                    await launch(url);
                  } else {
                    throw 'Could not launch $url';
                  }
                }catch(e){}
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3.0),
                child: Text("| ",style: TextStyle(fontSize: 21,fontWeight: FontWeight.w700,color: Colors.grey[800]),),
              ),
            ),
            Image.asset("packages/unified_map_view/assets/logos/iwayplus_logo.png",height: 52,width: 52,),
          ],
        )),
      ]
    );
  }

  @override
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is MapplsMapController) {
      await controller.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
      );
    }
  }

  @override
  Future<void> animateCamera(dynamic controller, MapLocation location, double zoom, {double? bearing, double? tilt}) async {
    if (controller is MapplsMapController) {
      if(bearing != null && tilt != null){
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(location.latitude, location.longitude), zoom: zoom, bearing: bearing, tilt: tilt)
          ),
        );
      }else{
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(location.latitude, location.longitude),
            zoom,
          ),
        );
        if (bearing != null && tilt == null){
          await controller.animateCamera(CameraUpdate.bearingTo(bearing));
        }else if (tilt != null && bearing == null){
          await controller.animateCamera(CameraUpdate.tiltTo(tilt));
        }
      }
    }
  }

  @override
  Future<MapLocation?> getCurrentLocation(dynamic controller) async {
    if (controller is MapplsMapController) {
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
    if (controller is MapplsMapController && styleJson != null) {
      // Mappls supports different style URLs
      // Default styles: MapmyIndiaStyle.STREET, HYBRID, SATELLITE, etc.
      // Custom style would need to be a valid Mappls style URL
    }
  }

  @override
  Future<void> addCircle(controller, GeoJsonCircle circle) async {
    if (controller is MapplsMapController) {
      _circles.removeWhere((circles)=>circles.id == circle.id);
      _circles.add(circle);
      try{
        await _setGeoJsonCircle(controller);
        if(circle.animated){
          _startCircleAnimation(controller, circle);
        }
      }catch(e){
        print("error adding marker $e");
      }
    }
  }

  @override
  Future<void> removeCircle(controller, String id) async {
    if (controller is MapplsMapController) {
      _circles.removeWhere((circles)=>circles.id.toLowerCase().contains(id));
      try{
        await _setGeoJsonCircle(controller);
      }catch(e){
        print("error adding marker $e");
      }
    }
  }

  Future<void> _setGeoJsonCircle(MapplsMapController controller) async {
    try {
      final features = _circles.map((circle){
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [circle.position.longitude, circle.position.latitude],
          },
          'properties': {
            if(circle.properties?['radius'] != null)'radius': circle.properties?['radius'],
          }
        };
      }).toList();

      await controller.setGeoJsonSource(_circleSourceId, {
        "type": "FeatureCollection",
        "features": features
      });
    } catch (e) {
      print('Error adding animated circle: $e');
    }
  }

  Timer? _circleAnimationTimer;
  bool _circleExpanding = true;
  void _startCircleAnimation(MapplsMapController controller, GeoJsonCircle circle) {
    _circleAnimationTimer?.cancel();
    var circleRadius = circle.properties?['radius']??5.0;
    _circleAnimationTimer = Timer.periodic(Duration(milliseconds: 50), (timer) async {
      // Animate radius between 5 and 20
      if (_circleExpanding) {
        circleRadius += 0.5;
        if (circleRadius >= 20.0) {
          _circleExpanding = false;
        }
      } else {
        circleRadius -= 0.5;
        if (circleRadius <= 5.0) {
          _circleExpanding = true;
        }
      }

      // Calculate opacity based on radius (fade out as it expands)
      double opacity = 1.0 - ((circleRadius - 5.0) / 15.0) * 0.7;

      try {
        // Update circle with new radius
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
        // Ignore errors during animation
      }
    });
  }

  void stopCircleAnimation() {
    _circleAnimationTimer?.cancel();
    _circleAnimationTimer = null;
  }

  @override
  Future<void> localizeUser(controller, GeoJsonMarker marker) async {
    if (controller is MapplsMapController) {
      if(_rotatingSymbols.where((element)=>element.id.toLowerCase().contains("user")).isNotEmpty){
        return;
      }
      print("localizeUser ${StackTrace.current}");
      _rotatingSymbols.add(marker);
      await _loadMarkerIcon(controller, marker);
      try{
        await setGeoJsonSource(controller, _rotatingSymbols, _rotationSourceId);
        _startCompassListening(controller, _rotationSourceId);
      }catch(e){
        print("error adding marker $e");
      }

    }
  }

  @override
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker) async {
    if (controller is MapplsMapController) {

      await _loadMarkerIcon(controller, marker);
      _symbols.add(marker);
      try{
        setGeoJsonSource(controller, _symbols, _clusterSourceId);
      }catch(e){
        print("error adding marker $e");
      }

    }
  }

  @override
  Future<void> addMarkers(controller, List<GeoJsonMarker> markers) async {
    if (controller is MapplsMapController) {
      for (var marker in markers) {
        await _loadMarkerIcon(controller, marker);
        _symbols.add(marker);
      }
      try{
        setGeoJsonSource(controller, _symbols, _clusterSourceId);
      }catch(e){
        print("error adding marker $e");
      }
    }
  }

  @override
  Future<void> moveUser(controller, String id, MapLocation location) async {
    if(controller is MapplsMapController){
      await _animateMarkerToPosition(controller, id, location);
    }
  }


  Future<void> _updateUserLocation(MapplsMapController controller) async {
    final features = _rotatingSymbols.map((marker) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [marker.position.longitude, marker.position.latitude],
      },
      'properties': {
        'title': '',
        'id': marker.id,
        if(marker.iconName != null || true) 'icon': marker.id,
        'isPriority': marker.priority ?? false,
        'intractable': marker.properties?["polyId"] != null,
        if(_currentHeading != null) "bearing": _currentHeading!
      }
    }).toList();

    await controller.setGeoJsonSource(_rotationSourceId, {
      "type": "FeatureCollection",
      "features": features
    });
  }

  Future<void> _animateMarkerToPosition(
      MapplsMapController controller,
      String id,
      MapLocation targetLocation,
      ) async {
    const duration = Duration(milliseconds: 300);
    const fps = 60;
    final steps = (duration.inMilliseconds / (1000 / fps)).round();

    var markers = _rotatingSymbols.where((symbol)=>symbol.id.toLowerCase().contains(id));
    var circles = _circles.where((circle)=>circle.id.toLowerCase().contains(id));

    if(markers.isEmpty) return;

    var marker = markers.first;
    GeoJsonCircle? circle;
    if(circles.isNotEmpty){
      circle = circles.first;
    }

    final startLat = marker.position.latitude;
    final startLng = marker.position.longitude;
    final endLat = targetLocation.latitude;
    final endLng = targetLocation.longitude;

    for (int i = 1; i <= steps; i++) {
      final progress = i / steps;
      final currentLat = startLat + (endLat - startLat) * progress;
      final currentLng = startLng + (endLng - startLng) * progress;

      marker.position = MapLocation(latitude: currentLat, longitude: currentLng);
      if(circle != null){
        circle.position = MapLocation(latitude: currentLat, longitude: currentLng);
      }
      await _updateUserLocation(controller);
      await _setGeoJsonCircle(controller);
      await Future.delayed(Duration(milliseconds: 1000 ~/ fps));
    }

    marker.position = targetLocation;
    if(circle != null){
      circle.position = targetLocation;
    }
    await _updateUserLocation(controller);
    await _setGeoJsonCircle(controller);
  }

  Future<void> setGeoJsonSource(dynamic controller, List<GeoJsonMarker> symbols, String sourceID) async {
    if (controller is MapplsMapController) {

      if (!_isClusteringEnabled) {
        print("Clustering not enabled yet");
        return;
      }

      final features = symbols.map((marker) {
        final anchor = (marker.anchor?.dx == 0.5 && marker.anchor?.dy == 0.5)?"center":"bottom";
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [marker.position.longitude, marker.position.latitude],
          },
          'properties': {
            // ✅ Always include ALL properties with defaults
            'title': marker.textVisibility ? creator.formatText(marker.title ?? "", TextFormat.smartWrap) : '',
            'id': marker.id,
            if (marker.assetPath != null) 'icon': marker.id,
            'isPriority': marker.priority ?? false,
            'intractable': marker.properties?["polyId"] != null,
            'bearing': marker.compassBasedRotation ? 0.0 : (marker.properties?["bearing"] ?? 0.0), // ✅ Always set with default
            'iconAnchor': anchor,
            'section': marker.properties?['type'] == "Section",
            'subSection': marker.properties?['type'] == "Sub Section",
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
  void _startCompassListening(MapplsMapController controller, String sourceID) {
    if(_compassSub != null) return;
    _compassSub = FlutterCompass.events?.listen((event) async {
      if (event.heading == null) return;
      _currentHeading = event.heading;
      final cameraPos = controller.cameraPosition;
      if (cameraPos == null) return;

      final features = _rotatingSymbols.map((marker)=>
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [marker.position.longitude, marker.position.latitude],
        },
        'properties': {
          'title': '',
          'id': marker.id,
          if(marker.iconName != null || true) 'icon': marker.id,
          'isPriority': marker.priority ?? false,
          'intractable': marker.properties?["polyId"] != null,
          if(marker.compassBasedRotation) "bearing": event.heading!
        }
      }).toList();

      await controller.setGeoJsonSource(sourceID, {
        "type": "FeatureCollection",
        "features": features
      });
    });
  }


  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    if (controller is MapplsMapController) {
      try {
        // Remove marker from the list
        _symbols.removeWhere((marker) => marker.id.toLowerCase().contains(markerId));
        _rotatingSymbols.forEach((symbol){
          print("_rotatingSymbols ${symbol.id}");
        });
        if(_rotatingSymbols.where((marker)=>marker.id.toLowerCase().contains(markerId)).isNotEmpty){
          _compassSub?.cancel();
          _compassSub = null;
        }
        _rotatingSymbols.removeWhere((marker) => marker.id.toLowerCase().contains(markerId));

        setGeoJsonSource(controller, _symbols, _clusterSourceId);
        setGeoJsonSource(controller, _rotatingSymbols, _rotationSourceId);
      } catch (e) {
        print('Error removing marker: $e');
      }
    }
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        // Clear the marker list
        _symbols.clear();

        // Update the GeoJSON source with empty features
        setGeoJsonSource(controller, [], _clusterSourceId);
        setGeoJsonSource(controller, [], _rotationSourceId);
      } catch (e) {
        print('Error clearing markers: $e');
      }
    }
  }

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    if (controller is MapplsMapController) {
      try {
        _polygons.add(polygon);
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding polygon: $e');
      }
    }
  }

  @override
  Future<void> addSection(controller, GeoJsonPolygon polygon) async {
    if (controller is MapplsMapController) {
      try {
        _polygons.add(polygon);
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding polygon: $e');
      }
    }
  }

  @override
  Future<void> addPolygons(dynamic controller, List<GeoJsonPolygon> polygons) async {
    if (controller is MapplsMapController) {
      try {
        _polygons.addAll(polygons);
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding polygons: $e');
      }
    }
  }

  Future<void> _updatePolygonSource(MapplsMapController controller, {String? selectPolygonId}) async {
    if (!_isPolygonLayersEnabled) {
      print("Polygon layers not enabled yet");
      return;
    }

    final features = _polygons.map((polygon) {
      final String? rawType = polygon.properties?["type"] ?? polygon.properties?["polygonType"];
      final String? type = rawType?.toLowerCase();

      final String? fillColorHex = polygon.properties?["fillColor"];
      final String? strokeColorHex = polygon.properties?["strokeColor"];

      final Color fillColor = (fillColorHex != null && fillColorHex != "undefined" && fillColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(fillColorHex)
          : RenderingUtilities.polygonColorMap[type]?["fillColor"] ?? Colors.white;

      final Color strokeColor = (strokeColorHex != null && strokeColorHex != "undefined" && strokeColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(strokeColorHex)
          : RenderingUtilities.polygonColorMap[type]?["strokeColor"] ?? Color(0xffD3D3D3);

      final coordinates = polygon.points
          .map((p) => [p.longitude, p.latitude])
          .toList();

      // Parse height and baseHeight
      double? baseHeight;
      double? height;

      // if (polygon.properties?['baseHeight'] != null && polygon.properties?['baseHeight'].isNotEmpty && polygon.properties?['baseHeight'].toLowerCase() != "undefined") {
      //   baseHeight = double.tryParse(polygon.properties?['baseHeight']);
      // }
      //
      // if (polygon.properties?['height'] != null && polygon.properties?['height'].isNotEmpty && polygon.properties?['height'].toLowerCase() != "undefined") {
      //   height = double.tryParse(polygon.properties?['height']);
      //   // If baseHeight exists, add it to height
      //   if (baseHeight != null && height != null) {
      //     height = height + baseHeight;
      //   }
      // }

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
          'fillColor': '#${RenderingUtilities.colorToMapplsHex(fillColor)}',
          'strokeColor': '#${RenderingUtilities.colorToMapplsHex(strokeColor)}',
          'fillOpacity': fillColor.a,
          'isSelected': polygon.id == selectPolygonId,
          'boundary' : polygon.properties?['type'] == "Boundary",
          'section' : polygon.properties?['type'] == "Section",
          'subsection' : polygon.properties?['type'] == "Sub Section",
          if(baseHeight != null) 'base_height': baseHeight,
          if(height != null) 'height': height
        }
      };
    }).toList();

    await controller.setGeoJsonSource(
      _polygonSourceId,
      {
        "type": "FeatureCollection",
        "features": features,
      },
    );
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId, {String? exclude}) async {
    if (controller is! MapplsMapController) return;

    _polygons.removeWhere((polygon) {
      final id = polygon.id;

      if (exclude != null && id.contains(exclude)) {
        return false;
      }

      return id.contains(polygonId);
    });

    await _updatePolygonSource(controller);
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        _polygons.clear();
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error clearing polygons: $e');
      }
    }
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    if (controller is MapplsMapController) {
      bool isWaypoint = false;
      if (polyline.properties?["lineCategory"] != null) {
        isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
      }
      if (polyline.properties?["polygonType"] != null) {
        isWaypoint = polyline.properties!["polygonType"].toLowerCase() == "waypoints";
      }

      if (isWaypoint) return;

      try {
        _lines.add(polyline);
        await _updatePolylineSource(controller);
      } catch (e) {
        print('Error adding polyline: $e');
      }
    }
  }

  @override
  Future<void> addPolylines(controller, List<GeoJsonPolyline> polylines) async {
    if (controller is MapplsMapController) {
      for (var polyline in polylines) {
        bool isWaypoint = false;
        if (polyline.properties?["lineCategory"] != null) {
          isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
        }
        if (polyline.properties?["polygonType"] != null) {
          isWaypoint = polyline.properties!["polygonType"].toLowerCase() == "waypoints";
        }

        if (isWaypoint) continue;

        try {
          _lines.add(polyline);
        } catch (e) {
          print('Error adding polyline: $e');
        }
      }
      try{
        await _updatePolylineSource(controller);
      }catch (e) {
        print('Error adding polyline: $e');
      }
    }
  }

  Future<void> _updatePolylineSource(MapplsMapController controller) async {
    if (!_isPolylineLayersEnabled) {
      print("Polyline layers not enabled yet");
      return;
    }

    final features = _lines.map((line) {
      return {
        'type': 'Feature',
        'id': line.id,
        'geometry': {
          'type': 'LineString',
          'coordinates': line.points.map((point) => [point.longitude, point.latitude]).toList(),
        },
        'properties': {
          // ✅ Always include ALL properties with defaults
          'id': line.id,
          'type': 'default',
          'isSelected': false,
          'lineColor': line.properties?['fillColor'] ?? '#000000', // ✅ Always set with default
          'lineOpacity': line.properties?['fillOpacity'] ?? 1.0,  // ✅ Always set
          'lineWidth': line.properties?['width']?.toDouble() ?? 4.0, // ✅ Always set, ensure double
          'path': line.properties?['path'] ?? line.id.toLowerCase().contains("path")
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
    if (controller is! MapplsMapController) return;

    _lines.removeWhere((line) {
      final id = line.id;
      return id.contains(polylineId);
    });

    await _updatePolylineSource(controller);
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    if (controller is MapplsMapController) {
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

  final creator = UnifiedMarkerCreator();

  Future<bool> _loadMarkerIcon(MapplsMapController controller, GeoJsonMarker marker) async {
    if(marker.assetPath == null) return false;
    try {
      if(marker.customRendering){
        MarkerIconWithAnchor markerIconWithAnchor = await creator.createUnifiedMarker(
            imageSize: marker.imageSize??const Size(25, 25),
            fontSize: 8.5,
            text: "",
            imageSource: marker.assetPath,
            layout: MarkerLayout.horizontal,
            textFormat: TextFormat.smartWrap,
            textColor: const Color(0xff000000),
            customAnchor: marker.renderAnchor??marker.anchor??Offset(0.5, 0.5),
            expandCanvasForRotation: true
        );
        print("markerIconWithAnchor $markerIconWithAnchor");
        final Uint8List iconBytes = markerIconWithAnchor.icon;
        await controller.addImage(marker.id, iconBytes);
        marker.anchor = markerIconWithAnchor.anchor;
        return true;
      }else{
        Uint8List? iconBytes;
        if (marker.assetPath!.startsWith('http')) {
          final response = await http.get(Uri.parse(marker.assetPath!));
          if (response.statusCode == 200) iconBytes = response.bodyBytes;
        } else {
          final bd = await rootBundle.load(marker.assetPath!);
          iconBytes = bd.buffer.asUint8List();
        }
        if(iconBytes != null){
          await controller.addImage(marker.id, iconBytes);
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Icon ${marker.iconName}.png not found in ${marker.assetPath!}');
      return false;
    }
  }

  Future<void> enableCircleLayers(MapplsMapController controller) async {
    try {
      await controller.addGeoJsonSource(_circleSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      await controller.addCircleLayer(
        _circleSourceId,
        _normalCircleLayerId,
        CircleLayerProperties(
          circleRadius: 10.0,
          circleColor: '#448AFF',
          circleOpacity: 0.3,
          circleStrokeWidth: 2.0,
          circleStrokeColor: '#4CAF50',
          circleStrokeOpacity: 0.8,
        ),
        enableInteraction: false,
        belowLayerId: _rotationMarkerLayerId, // Below the rotating marker
      );

      _isCircleLayersEnabled = true;

    } catch (e) {
      print('Error enabling circle layers: $e');
    }
  }

  Future<void> enableMarkerLayers(dynamic controller) async {
    if (controller is! MapplsMapController) return;

    try {
      await controller.addGeoJsonSource(_clusterSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      await controller.addGeoJsonSource(_rotationSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      // Layer 1: Normal text markers (no icon, no bearing) - lowest priority
      await controller.addSymbolLayer(
          _clusterSourceId,
          _normalTextMarkerLayerId,
          SymbolLayerProperties(
            textField: ["get", "title"], // ✅ Just get, no case/has
            textSize: 14,
            textColor: "#000000",
            textHaloColor: "#f8f9fa",
            textHaloWidth: 1.5,
            textAnchor: "center",
            textAllowOverlap: false,
          ),
          filter: [
            "all",
            ["!", ["to-boolean", ["get", "isPriority"]]],
            ["!", ["to-boolean", ["get", "section"]]],
            ["!", ["to-boolean", ["get", "subSection"]]],
            ["!", ["to-boolean", ["get", "bearing"]]],
            ["!", ["to-boolean", ["get", "icon"]]],
          ],
          enableInteraction: true,
          belowLayerId: null,
          minzoom: 18.0
      );

      // Layer 2: Normal icon markers (has icon, no bearing)
      await controller.addSymbolLayer(
        _clusterSourceId,
        _normalIconMarkerLayerId,
        SymbolLayerProperties(
          iconImage: ["get", "icon"],
          iconSize: 0.8,
          iconAnchor: "center",

          textField: ["get", "title"],
          textSize: 14,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,
          textAnchor: "top",
          textOffset: ["literal", [0, 1.5]],
          textAllowOverlap: false,
          iconAllowOverlap: false,
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "bearing"]]],
          ["to-boolean", ["get", "icon"]],
        ],
        enableInteraction: true,
        belowLayerId: _normalTextMarkerLayerId,
        minzoom: 18.0,
      );


      // Layer 3: Normal fixed/rotated markers (has bearing) - show at zoom 17+
      await controller.addSymbolLayer(
          _clusterSourceId,
          _normalFixedMarkerLayerId,
          SymbolLayerProperties(
            textRotate: ["get", "bearing"],
            textRotationAlignment: "map",
            textField: ["get", "title"],
            textSize: 12,
            textColor: "#000000",
            textHaloColor: "#f8f9fa",
            textHaloWidth: 2,
            textAnchor: "left",
            textAllowOverlap: false,
          ),
          filter: [
            "all",
            ["!", ["to-boolean", ["get", "isPriority"]]],
            ["!", ["to-boolean", ["get", "section"]]],
            ["!", ["to-boolean", ["get", "subSection"]]],
            ["to-boolean", ["get", "bearing"]],
          ],
          enableInteraction: true,
          belowLayerId: _normalIconMarkerLayerId,
          minzoom: 18.0
      );

      // Layer 4: Section markers (zoom < 17)
      await controller.addSymbolLayer(
        _clusterSourceId,
        _sectionMarkerLayerId,
        SymbolLayerProperties(
          iconImage: ["get", "icon"],
          iconSize: 0.8,
          iconAnchor: "center",

          textField: ["get", "title"],
          textSize: 14,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,

          // 👇 Conditional anchor
          textAnchor: [
            "case",
            ["has", "icon"],     // if icon exists
            "top",               // place text above icon
            "center"             // else center text
          ],

          textOffset: [
            "case",
            ["has", "icon"],
            ["literal", [0, 1.5]],   // offset only if icon exists
            ["literal", [0, 0]]      // no offset if no icon
          ],

          textAllowOverlap: false,
          iconAllowOverlap: false,
        ),
        filter: ["to-boolean", ["get", "section"]],
        enableInteraction: true,
        belowLayerId: _normalFixedMarkerLayerId,
        maxzoom: 17.0,
      );

      // Layer 4b: SubSection markers
      await controller.addSymbolLayer(
          _clusterSourceId,
          _subSectionMarkerLayerId,
          SymbolLayerProperties(
            iconImage: ["get", "icon"],
            iconSize: 1.5,
            textField: ["get", "title"],
            textSize: 12,
            textColor: "#000000",
            textHaloColor: "#f8f9fa",
            textHaloWidth: 2,
            textAnchor: "center",
            iconAllowOverlap: true,
            textAllowOverlap: true,
          ),
          filter: ["to-boolean", ["get", "subSection"]],
          enableInteraction: true,
          belowLayerId: _normalFixedMarkerLayerId,
          maxzoom: 18.0,
          minzoom: 17.0
      );

      // Layer 5: Rotation markers (separate source)
      await controller.addSymbolLayer(
        _rotationSourceId,
        _rotationMarkerLayerId,
        SymbolLayerProperties(
          iconImage: ["get", "icon"],
          iconSize: 1.5,
          iconRotate: ["get", "bearing"],
          iconRotationAlignment: "map",
          iconAllowOverlap: true,
        ),
        enableInteraction: true,
        belowLayerId: _sectionMarkerLayerId,
      );

      // Layer 6: Priority markers (rendered on top - always visible)
      await controller.addSymbolLayer(
          _clusterSourceId,
          _priorityMarkerLayerId,
          SymbolLayerProperties(
            iconImage: ["get", "icon"],
            iconSize: 1.5,
            iconAllowOverlap: true,
            textAllowOverlap: true,
          ),
          filter: ["to-boolean", ["get", "isPriority"]],
          enableInteraction: true,
          belowLayerId: null
      );

      _isClusteringEnabled = true;

      if (_symbols.isNotEmpty) {
        List<GeoJsonMarker> symbols = [..._symbols];
        setGeoJsonSource(controller, symbols, _clusterSourceId);
      }
    } catch (e, stack) {
      print('Error enabling clustering: $e');
      print('Stack trace: $stack');
    }
  }

  /// Enable polygon layers with GeoJSON source
  Future<void> enablePolygonLayers(MapplsMapController controller) async {
    try {
      await controller.addGeoJsonSource(_polygonSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      /// =========================
      /// 1️⃣ SECTION (TOP-MOST)
      /// =========================
      await controller.addFillLayer(
        _polygonSourceId,
        _sectionPolygonLayerId,
        FillLayerProperties(
          fillColor: ["get", "fillColor"],
          fillOpacity: ["get", "fillOpacity"],
          fillOutlineColor: ["get", "strokeColor"],
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "section"]],
          ["!", ["to-boolean", ["get", "subsection"]]],
          ["!", ["has", "height"]],
        ],
        enableInteraction: false,
        maxzoom: 17.0,
        belowLayerId: _polylineLayerId,
      );

      /// =========================
      /// 2️⃣ SUBSECTION
      /// =========================
      await controller.addFillLayer(
        _polygonSourceId,
        _subSectionPolygonLayerId,
        FillLayerProperties(
          fillColor: ["get", "fillColor"],
          fillOpacity: ["get", "fillOpacity"],
          fillOutlineColor: ["get", "strokeColor"],
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "section"]]],
          ["to-boolean", ["get", "subsection"]],
          ["!", ["has", "height"]],
        ],
        enableInteraction: false,
        minzoom: 17.0,
        maxzoom: 18.0,
        belowLayerId: _sectionPolygonLayerId,
      );

      /// =========================
      /// 3️⃣ SELECTED
      /// =========================
      await controller.addFillLayer(
        _polygonSourceId,
        _selectedPolygonLayerId,
        FillLayerProperties(
          fillColor: "#4CAF50",
          fillOpacity: 0.6,
          fillOutlineColor: "#2E7D32",
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "isSelected"]],
          ["!", ["has", "height"]],
        ],
        enableInteraction: true,
        belowLayerId: _subSectionPolygonLayerId,
      );

      /// =========================
      /// 4️⃣ EXTRUDED
      /// =========================
      await controller.addFillExtrusionLayer(
        _polygonSourceId,
        _extrudedPolygonLayerId,
        FillExtrusionLayerProperties(
          fillExtrusionColor: ["get", "fillColor"],
          fillExtrusionHeight: ["get", "height"],
          fillExtrusionBase: ["get", "base_height"],
          fillExtrusionOpacity: 1.0,
        ),
        filter: ['has', 'height'],
        belowLayerId: _selectedPolygonLayerId,
      );

      /// =========================
      /// 5️⃣ NORMAL
      /// =========================
      await controller.addFillLayer(
        _polygonSourceId,
        _normalPolygonLayerId,
        FillLayerProperties(
          fillColor: ["get", "fillColor"],
          fillOpacity: ["get", "fillOpacity"],
          fillOutlineColor: ["get", "strokeColor"],
        ),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "isSelected"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subsection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["!", ["has", "height"]],
        ],
        enableInteraction: true,
        belowLayerId: _extrudedPolygonLayerId,
      );

      /// =========================
      /// 6️⃣ PATCH (BOTTOM-MOST)
      /// =========================
      await controller.addFillLayer(
        _polygonSourceId,
        _patchPolygonLayerId,
        FillLayerProperties(
          fillColor: ["get", "fillColor"],
          fillOpacity: ["get", "fillOpacity"],
          fillOutlineColor: ["get", "strokeColor"],
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "boundary"]],
          ["!", ["has", "height"]],
        ],
        enableInteraction: true,
        belowLayerId: _normalPolygonLayerId,
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


  Future<void> enablePolylineLayers(MapplsMapController controller) async {
    try {
      await controller.addGeoJsonSource(_polylineSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      /// 🔹 Normal polylines (NOT path)
      await controller.addLineLayer(
        _polylineSourceId,
        _polylineLayerId,
        LineLayerProperties(
          lineColor: ["get", "lineColor"], // ✅ Direct get (ensure property exists in GeoJSON)
          lineWidth: ["get", "lineWidth"],
          lineOpacity: ["get", "lineOpacity"],
        ),
        filter: ["!", ["to-boolean", ["get", "path"]]],
        enableInteraction: true,
        belowLayerId: _normalIconMarkerLayerId,
      );

      /// 🔹 Path polylines (highlighted route)
      await controller.addLineLayer(
        _polylineSourceId,
        _pathLayerId,
        LineLayerProperties(
          lineColor: ["get", "lineColor"],
          lineWidth: ["get", "lineWidth"],
          lineOpacity: ["get", "lineOpacity"],
        ),
        filter: ["to-boolean", ["get", "path"]],
        enableInteraction: true,
        belowLayerId: _normalIconMarkerLayerId,
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

  /// Extract polygon ID from tap coordinates
  String? _extractPolygonIdFromTap(String key) {
    var keyMap = GeoJsonUtils.extractKeyValueMap(key);
    if(keyMap["polyId"] != null) return keyMap["polyId"];
    if(keyMap["id"] != null) return keyMap["id"];
    return null;
  }

  CameraBound? calculateBounds(controller, List<MapLocation> allPoints){
    // Calculate bounds
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

    // Move to center
    try {
      // Add padding to the bounds (adjust these values as needed)
      final latPadding = (maxLat - minLat) * 0.5; // % padding
      final lngPadding = (maxLng - minLng) * 0.5;

      // Create bounds with padding
      final bounds = CameraBound(
        southwest: MapLocation(
            latitude: minLat - latPadding, longitude: minLng - lngPadding),
        northeast: MapLocation(
            latitude: maxLat + latPadding, longitude: maxLng + lngPadding),
      );
      return bounds;
    }catch(e){
      print("calculateBounds error $e");
    }
    return null;
  }

  @override
  Future<void> selectLocation(controller, String polyID) async {
    if(selectedLocation?.polyID == polyID) return;
    if (controller is! MapplsMapController) {
      print('Error: Invalid controller type');
      return;
    }
    if (polyID.isEmpty) {
      print('Error: polyID cannot be empty');
      return;
    }

    try {
      GeoJsonPolygon? polygon;
      GeoJsonMarker? marker;
      // Try to find marker
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

      if(marker != null){
        // Deselect previous location if exists
        if (selectedLocation != null) {
          print("selectedLocation is ${selectedLocation.toString()}");
          await deSelectLocation(controller);
        }
      }

      String polyIDInsideMarker = polyID;
      print("markerid ${marker?.id}");
      if(marker?.id != null){
        polyIDInsideMarker = _extractPolygonIdFromTap(marker!.id)??polyID;
      }
      print("polyIDInsideMarker ${polyIDInsideMarker}");

      // Try to find polygon
      try {
        if (_polygons.isNotEmpty) {
          polygon = _polygons.firstWhere(
                (p) => (p.id.contains(polyID) || p.id.contains(polyIDInsideMarker)),
            orElse: () => throw Exception('Polygon not found'),
          );

          // Validate polygon coordinates
          if (polygon.points.isEmpty) {
            print('Warning: No coordinates found for polygon: ${polygon.id}');
            polygon = null;
          } else if (polygon.points.length < 3) {
            print('Warning: Polygon must have at least 3 points: ${polygon.id}');
            polygon = null;
          }
        }
      } catch (e) {
        print('No polygon found for polyID: $polyID - $e');
      }

      // Check if we found at least one
      if (polygon == null && marker == null) {
        print('Error: Neither polygon nor marker found for polyID: $polyID');
        return;
      }

      // Calculate bounds and center
      MapLocation? center;
      double? targetZoom;

      if (polygon != null && polygon.points.isNotEmpty) {
        // Calculate from polygon bounds
        double minLat = polygon.points.first.latitude;
        double maxLat = polygon.points.first.latitude;
        double minLng = polygon.points.first.longitude;
        double maxLng = polygon.points.first.longitude;

        for (final point in polygon.points) {
          if (point.latitude < -90 || point.latitude > 90) {
            print('Warning: Invalid latitude ${point.latitude}');
            continue;
          }
          if (point.longitude < -180 || point.longitude > 180) {
            print('Warning: Invalid longitude ${point.longitude}');
            continue;
          }

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

          // Calculate zoom based on polygon size
          final latSpan = maxLat - minLat;
          final lngSpan = maxLng - minLng;
          final maxSpan = max(latSpan, lngSpan);

          targetZoom = 20.0;
          if (maxSpan > 0.01) targetZoom = 15.0;
          if (maxSpan > 0.1) targetZoom = 12.0;
          if (maxSpan > 1.0) targetZoom = 8.0;
        }
      } else if (marker != null) {
        // Use marker position if polygon not available
        center = marker.position;
        targetZoom = 19; // Default zoom for marker-only view
      }

      // Update polygon selection state if polygon exists
      if (polygon != null) {
        await _updatePolygonSelectionState(controller, polygon.id, true);
      }

      print("marker $marker");
      // Handle marker styling if marker exists
      if (marker != null) {
        if(marker.assetPath == null){
          try {
            final genericMarker = PredefinedMarkers.getGenericMarker(marker);
            print("genericMarker id ${genericMarker.id}");
            await removeMarker(controller, polyID);
            await addMarker(controller, genericMarker);
          } catch (e) {
            print('Warning: Failed to update marker styling: $e');
          }
        }else{
          var copyMarker = marker?.copyWith(imageSize: Size(50, 50), textVisibility: true, priority: true);
          print("copyMarker ${copyMarker?.assetPath}");
          await removeMarker(controller, polyID);
          await addMarker(controller, copyMarker!);
        }
      }


      // Store selected location
      selectedLocation = SelectedLocation(
        polyID: polyIDInsideMarker??polyID,
        polygon: polygon,
        marker: marker,
      );

      CameraBound? bounds;
      if(polygon != null && polygon.points.isNotEmpty){
        bounds = calculateBounds(controller, polygon.points);
      }

      // Animate camera if we have a valid center
      if (bounds != null || (center != null && targetZoom != null)) {
        try {
          if(bounds != null){
            fitCameraToBounds(controller, bounds);
          }else if(center != null && targetZoom != null){
            animateCamera(controller, center, targetZoom);
          }
        } catch (e) {
          print('Warning: Failed to animate camera: $e');
        }
      }

      // Trigger callback if polygon exists
      if (polygon != null) {
        _config.onPolygonTap?.call(
          coordinates: polygon.points,
          polygonId: polyID,
        );
      }else if(marker != null){
        _config.onMarkerTap?.call(
          coordinates: marker.position,
          markerId: polyID,
        );
      }
    } catch (e, stackTrace) {
      print('Error selecting location: $e');
      print('Stack trace: $stackTrace');
      selectedLocation = null;
    }
  }

  /// Update polygon selection state in GeoJSON source
  Future<void> _updatePolygonSelectionState(
      MapplsMapController controller,
      String selectPolygonId,
      bool isSelected,
      ) async {
    _updatePolygonSource(controller, selectPolygonId: selectPolygonId);
  }

  /// Deselect a polygon and restore its original colors
  @override
  Future<void> deSelectLocation(dynamic controller) async {
    if (controller is! MapplsMapController) {
      print('Error: Invalid controller type in deSelectLocation');
      return;
    }

    print("selectedLocation $selectedLocation");
    if (selectedLocation == null) {
      return;
    }

    final polyID = selectedLocation!.polyID;

    if (polyID.isEmpty) {
      print('Error: polyID is empty in selectedLocation');
      selectedLocation = null;
      return;
    }

    try {
      // Update polygon selection state
      await _updatePolygonSelectionState(controller, polyID, false);

      // Handle marker
      try {
        final marker = selectedLocation?.marker as GeoJsonMarker?;
        print("marker in deselect ${polyID} ${_symbols.where((marker)=>marker.id.toLowerCase().contains(polyID))}");

        if (marker != null) {
          await removeMarker(controller, polyID);
          await addMarker(controller, marker);
        }
      } catch (e) {
        print('Error handling marker during deselection: $e');
      }

      selectedLocation = null;
    } catch (e, stackTrace) {
      print('Error deselecting location: $e');
      print('Stack trace: $stackTrace');
      selectedLocation = null;
    }
  }

  @override
  Future<void> zoom(dynamic controller, {double zoom = 0.0}) async {
    try {
      final bounds = await _controller!.getVisibleRegion();
      final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

      final cameraPos = _controller!.cameraPosition;

      await animateCamera(
        controller,
        MapLocation(
          latitude: centerLat,
          longitude: centerLng,
        ),
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
      final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

      await animateCamera(
        controller,
        MapLocation(
          latitude: centerLat,
          longitude: centerLng,
        ),
        zoom,
      );
    } catch (e) {
      print("Error zoomTo: $e");
    }
  }

  @override
  Future<void> fitCameraToLine(controller, GeoJsonPolyline polyline) async {
    if (polyline.points.isEmpty) return;

    // Calculate bounds from all points in the line
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

    // Add padding to the bounds (adjust these values as needed)
    final latPadding = (maxLat - minLat) * 0.1; // 10% padding
    final lngPadding = (maxLng - minLng) * 0.1;

    // Create bounds with padding
    final bounds = LatLngBounds(
      southwest: LatLng(minLat - latPadding, minLng - lngPadding),
      northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
    );

    // Animate camera to fit bounds
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 50,    // Edge padding in pixels
        top: 50,
        right: 50,
        bottom: 50,
      ),
    );
  }

  @override
  Future<void> fitCameraToBounds(controller, CameraBound bound) async {
    final bounds = LatLngBounds(
      southwest: LatLng(bound.southwest.latitude, bound.southwest.longitude),
      northeast: LatLng(bound.northeast.latitude, bound.northeast.longitude),
    );

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 50,    // Edge padding in pixels
        top: 50,
        right: 50,
        bottom: 50,
      ),
    );

  }

}