// lib/src/providers/mapbox_map_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../models/camera_position.dart';
import '../utils/LandmarkAssetType.dart';
import '../utils/renderingUtilities.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';

/// Mapbox implementation of BaseMapProvider
class MapboxMapProvider extends BaseMapProvider {
  late MapboxMap _mapboxMap;
  static const String _markerSourceId = 'marker-source';
  static const String _markerLayerId = 'marker-symbol-layer';
  final Map<String, GeoJsonMarker> _markers = {};

  static const String _polygonSourceId = 'polygon-source';
  static const String _polygonLayerId  = 'polygon-extrusion-layer';
  final Map<String, GeoJsonPolygon> _polygons = {};


  @override
  Widget buildMap({
    required MapConfig config}) {
    return MapWidget(       
      onMapCreated: (mapboxMap) async {
        config.onMapCreated(mapboxMap);
        _mapboxMap = mapboxMap;
         await _initMarkerLayer(mapboxMap);
         mapboxMap.setOnMapTapListener((value) async {
           print("🟢 Map tapped at: ${value.point.coordinates.lat}, ${value.point.coordinates.lng}");
           final screenCoordinate = await mapboxMap.pixelForCoordinate(value.point);

           final features = await mapboxMap.queryRenderedFeatures(
             RenderedQueryGeometry.fromScreenCoordinate(screenCoordinate),
             RenderedQueryOptions(
               layerIds: [
                 'marker-symbol-layer',
                 'polygon-extrusion-layer',
               ],
             ),
           );
           features.forEach((value){
             if(value?.layers[0] == _polygonLayerId && value?.layers[0] != null && !value!.layers[0]!.contains('boundary')){
               dynamic geometry = value.queriedFeature.feature['geometry']!;
               final coordinates = geometry['coordinates'] as List<dynamic>;
               final List<MapLocation> polygonPoints = (coordinates.first as List<dynamic>).map((point) {
                 final lng = point[0] as double;
                 final lat = point[1] as double;
                 return MapLocation(latitude: lat, longitude: lng,);
               }).toList();
               if(coordinates.length == 1){
                 config.onPolygonTap!(coordinates: polygonPoints, polygonId: value.queriedFeature.feature['id']!.toString());
               }
             }
           });
         });
      },
      styleUri: MapboxStyles.MAPBOX_STREETS,
      cameraOptions: CameraOptions(
        center: Point(
          coordinates: Position(
            config.initialLocation.mapLocation.longitude,
            config.initialLocation.mapLocation.latitude,
          ),
        ),
        zoom: config.initialLocation.zoom,
      ),
      onMapIdleListener: (MapIdleEventData mapIdleEventData) async {
        try {
          final cameraState = await _mapboxMap.getCameraState();
          config.onCameraMove(
            UnifiedCameraPosition(
              mapLocation: MapLocation(
                latitude: cameraState.center.coordinates.lat.toDouble(),
                longitude: cameraState.center.coordinates.lng.toDouble(),
              ),
              zoom: cameraState.zoom ?? 0.0,
              bearing: cameraState.bearing ?? 0.0,
            ),
          );
        } catch (e) {
          print("Error getting camera state: $e");
        }
      },
      textureView: true,
    );
  }

  @override
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is MapboxMap) {
      await controller.setCamera(
        CameraOptions(
          center: Point(
            coordinates: Position(location.longitude, location.latitude),
          ),
          zoom: zoom,
        ),
      );
    }
  }

  @override
  Future<void> animateCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is MapboxMap) {
      await controller.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(location.longitude, location.latitude),
          ),
          zoom: zoom,
        ),
        MapAnimationOptions(duration: 2000, startDelay: 0),
      );
    }
  }


  Future<void> _initMarkerLayer(MapboxMap mapboxMap) async {
    final style = mapboxMap.style;

    Future<void> addIcon(String id, String path) async {
      if (await style.styleLayerExists(id)) return;

      final bytes = await rootBundle.load(path);
      final list = bytes.buffer.asUint8List();
      final image = await decodeImageFromList(list);

      await style.addStyleImage(
        id,
        1.0,
        MbxImage(
          width: image.width,
          height: image.height,
          data: list,
        ),
        false,
        [],
        [],
        null,
      );
    }

    await addIcon(LandmarkAssetType.entrance.iconImageId, LandmarkAssetType.entrance.assetPath);
    await addIcon(LandmarkAssetType.femaleWashroom.iconImageId, LandmarkAssetType.femaleWashroom.assetPath);
    await addIcon(LandmarkAssetType.maleWashroom.iconImageId, LandmarkAssetType.maleWashroom.assetPath);


    final exists = await style.styleSourceExists(_markerSourceId);
    if (!exists) {
      await style.addSource(
        GeoJsonSource(
          id: _markerSourceId,
          data: jsonEncode({
            'type': 'FeatureCollection',
            'features': [],
          }),
        ),
      );
    }

    final layerExists = await style.styleLayerExists(_markerLayerId);
    if (!layerExists) {
      await style.addLayer(
        SymbolLayer(
          id: _markerLayerId,
          sourceId: _markerSourceId,
          iconImageExpression: ['get', 'icon'],
          iconSizeExpression: ['get','iconSize'],
          textFieldExpression: ['get', 'title'],
          textFont: ["Roboto Medium", "Arial Unicode MS Regular"],
          textSize: 12,
          textColor: 0xFF000000,
          textHaloColor: 0xFFFFFFFF,
          textHaloWidth: 1,
          textHaloBlur: 0.5,
          iconAllowOverlap: false,
          textAllowOverlap: false,
          textMaxWidth: 5,
          textAnchor: TextAnchor.CENTER,
          symbolZOffset: 3.0,
          textJustify: TextJustify.LEFT,
        ),
      );
    }
  }

  @override
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker) async {
    if (controller is! MapboxMap) return;
    if(marker.properties == null || marker.properties!["polyId"] == null) return;

    _markers[marker.id] = marker;

    try {
      await _updateMarkerSource(controller);
    } catch(e) {
      print("error adding marker $e");
    }
  }

  Future<void> _updateMarkerSource(MapboxMap mapboxMap) async {
    final features = _markers.values.map((marker) {
      final result = RenderingUtilities.getIconIdByType(marker.title??"");
      return {
        'type': 'Feature',
        'id': marker.id,
        'geometry': {
          'type': 'Point',
          'coordinates': [
            marker.position.longitude,
            marker.position.latitude,
          ],
        },
        'properties': {
          'title': (marker.title != null && marker.title!.toLowerCase().contains("washroom"))? "" : marker.title,
          'icon': result.$1,
          'iconSize': result.$2,
          'isPriority': marker.priority ?? false,
        },
      };
    }).toList();

    await mapboxMap.style.setStyleSourceProperty(
      _markerSourceId,
      'data',
      {
        'type': 'FeatureCollection',
        'features': features,
      },
    );
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId,{String? exclude}) async {
    if (controller is! MapboxMap) return;

    final markersToRemove = _markers.entries.where((entry){
      final id = entry.key;
      if(exclude != null && id.contains(exclude)){
        return false;
      }
      if(id.contains(markerId)){
        return true;
      }
      return false;
    }).toList();

    for(final entry in markersToRemove) {
      _markers.remove(entry.key);
    }

    await _updateMarkerSource(controller);
  }
  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is! MapboxMap) return;

    _markers.clear();
    await _updateMarkerSource(controller);
  }

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    if (controller is! MapboxMap) return;

    try {
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

      _polygons[polygon.id] = polygon;
      await _updatePolygonSource(controller);
    } catch (e) {
      print('Error adding polygon: $e');
    }
  }

  @override
  Future<void> addPolygons(dynamic controller, List<GeoJsonPolygon> polygons) async {
    if (controller is! MapboxMap) return;

    // Add all polygons to the map
    for (var polygon in polygons) {
      _polygons[polygon.id] = polygon;
    }

    // Update source only once
    await _updatePolygonSource(controller);
  }

  Future<void> _updatePolygonSource(MapboxMap mapboxMap) async {
    final style = mapboxMap.style;

    final features = _polygons.values
        .map((polygon) {

      final String? rawType =
          polygon.properties?["type"] ?? polygon.properties?["polygonType"];
      final String? type = rawType?.toLowerCase();

      final String? fillColorHex = polygon.properties?["fillColor"];


      String color = (fillColorHex != null &&
          fillColorHex != "undefined" &&
          fillColorHex.isNotEmpty)
          ? fillColorHex
          : RenderingUtilities.colorToHex(
        RenderingUtilities.polygonColorMap[type]?["fillColor"]
            ?? RenderingUtilities.polygonColorMap['default']!["fillColor"]!,
      );
      if(polygon.properties?["type"] != null){
        color = RenderingUtilities.getColorByType(polygon.properties?["type"]);
      }

      final height = (polygon.properties?["name"] !=null && polygon.properties!["name"].toString().toLowerCase().contains("boundary"))? 0 : 3;
      double opacity = (polygon.properties?["polygonType"]?.toString().toLowerCase() == "wall") ? 0.5 : 1.0;

      return {
        'type': 'Feature',
        'id': polygon.id,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            polygon.points
                .map((p) => [p.longitude, p.latitude])
                .toList()
          ],
        },
        'properties': {
          'height': height,
          'fillColor': color, // Pass the color value directly
          'opacity': opacity
        },
      };
    }).toList();

    // ---- Create source once ----
    if (!await style.styleSourceExists(_polygonSourceId)) {
      await style.addSource(
        GeoJsonSource(
          id: _polygonSourceId,
          data: jsonEncode({
            'type': 'FeatureCollection',
            'features': features,
          }),
        ),
      );
    } else {
      // ---- Update source data ----
      await style.setStyleSourceProperty(
        _polygonSourceId,
        'data',
        jsonEncode({
          'type': 'FeatureCollection',
          'features': features,
        }),
      );
    }

    // ---- Create ONE extrusion layer ----
    if (!await style.styleLayerExists(_polygonLayerId)) {

      await style.addLayerAt(
        FillExtrusionLayer(
          id: _polygonLayerId,
          sourceId: _polygonSourceId,
          fillExtrusionColorExpression: ['get', 'fillColor'],
          fillExtrusionHeightExpression: ['get', 'height'],
        ),
        LayerPosition(below: _markerLayerId)
      );
    }
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId,{String? exclude}) async {
    print("removePolygon ${StackTrace.current}");
    if (controller is! MapboxMap) return;

    final entriesToRemove = _polygons.entries.where((entry) {
      final id = entry.key;
      if (exclude != null && id.contains(exclude)) {
        return false;
      }
      if (id.contains(polygonId)) {
        return true;
      }
      return false;
    }).toList();

    for (final entry in entriesToRemove) {
      _polygons.remove(entry.key);
    }
    await _updatePolygonSource(controller);
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is! MapboxMap) return;

    _polygons.clear();
    await _updatePolygonSource(controller);
  }


  @override
  Future<MapLocation?> getCurrentLocation(dynamic controller) async {
    if (controller is MapboxMap) {
      final cameraState = await controller.getCameraState();
      final center = cameraState.center;
      return MapLocation(
        latitude: center.coordinates.lat.toDouble(),
        longitude: center.coordinates.lng.toDouble(),
      );
    }
    return null;
  }

  @override
  Future<void> setMapStyle(dynamic controller, String? styleJson) async {
    if (controller is MapboxMap && styleJson != null) {
      await controller.loadStyleURI(styleJson);
    }
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    // Mapbox polylines require style layer implementation
    if (controller is MapboxMap) {
      // TODO: Implement polyline rendering using Mapbox style layers
    }
  }

  @override
  Future<void> removePolyline(dynamic controller, String polylineId) async {
    // Mapbox polyline removal
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    // Clear all Mapbox polylines
  }

  @override
  Future<void> selectLocation(controller, String polyID) {
    // TODO: implement selectLocation
    throw UnimplementedError();
  }

  @override
  Future<void> deSelectLocation(controller) {
    // TODO: implement deSelectLocation
    throw UnimplementedError();
  }

}