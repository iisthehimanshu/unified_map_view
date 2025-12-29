// lib/src/providers/mappls_map_provider.dart

import 'package:flutter/material.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:unified_map_view/src/models/camera_position.dart';
import '../utils/renderingUtilities.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';

/// Mappls GL implementation of BaseMapProvider
/// Supports Mappls (MapmyIndia) maps - India's own mapping platform
class MapplsMapProvider extends BaseMapProvider {
  MapplsMapController? _controller;
  final Map<String, Symbol> _symbols = {};
  final Map<String, Line> _lines = {};
  final Map<String, Fill> _fills = {};

  List<GeoJsonMarker> geoJsonFeatureList = [];

  String _clusterSourceId = 'markers-source';

  @override
  Widget buildMap({
    required MapConfig config,
    required Function(dynamic controller) onMapCreated,
    required void Function(UnifiedCameraPosition position) onCameraMove,

  }) {
    return MapplsMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(
          config.initialLocation.mapLocation.latitude,
          config.initialLocation.mapLocation.longitude,
        ),
        zoom: config.initialLocation.zoom,
      ),
      onMapCreated: (MapplsMapController controller) async {
        _controller = controller;
        onMapCreated(controller);
      },
      onStyleLoadedCallback: () {
        // Style loaded, map is ready
      },
      onCameraIdle: ()async{
        if (_controller != null) {
          try {
            final bounds = await _controller!.getVisibleRegion();
              final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
              final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

              final cameraPos = _controller!.cameraPosition;

              onCameraMove(UnifiedCameraPosition(
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
      minMaxZoomPreference: const MinMaxZoomPreference(0, 24),
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
  Future<void> animateCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is MapplsMapController) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
      );
    }
  }

  @override
  Future<MapLocation?> getCurrentLocation(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        final cameraPosition = await controller.cameraPosition;
        if(cameraPosition == null) return null;
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
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker) async {
    if (controller is MapplsMapController) {
      try {
        geoJsonFeatureList.add(marker);
        // _symbols[marker.id] = Symbol(marker.id, SymbolOptions(
        //   geometry: LatLng(marker.position.latitude, marker.position.longitude),
        // ));
      } catch (e) {
        print('Error adding marker: $e');
      }
    }
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    if (controller is MapplsMapController && _symbols.containsKey(markerId)) {
      try {
        await controller.removeSymbol(_symbols[markerId]!);
        _symbols.remove(markerId);
      } catch (e) {
        print('Error removing marker: $e');
      }
    }
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        for (var symbol in _symbols.values) {
          await controller.removeSymbol(symbol);
        }
        _symbols.clear();
      } catch (e) {
        print('Error clearing markers: $e');
      }
    }
  }

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    if (controller is MapplsMapController) {
      try {
        final String? rawType = polygon.properties?["type"];
        final String? type = rawType?.toLowerCase();

        final String? fillColorHex = polygon.properties?["fillColor"];
        final String? strokeColorHex = polygon.properties?["strokeColor"];

        final Color fillColor = (fillColorHex != null && fillColorHex != "undefined" && fillColorHex.isNotEmpty)
            ? RenderingUtilities.hexToColor(fillColorHex, opacity: 1.0)
            : RenderingUtilities.polygonColorMap[type]?["fillColor"]
            ?? Colors.blue.withOpacity(0.1);

        final Color strokeColor = (strokeColorHex != null && strokeColorHex != "undefined" && strokeColorHex.isNotEmpty)
            ? RenderingUtilities.hexToColor(strokeColorHex)
            : RenderingUtilities.polygonColorMap[type]?["strokeColor"]
            ?? Colors.blue.withOpacity(0.1);

        final coordinates = polygon.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        String fillHex = RenderingUtilities.colorToMapplsHex(fillColor);
        String strokeHex = RenderingUtilities.colorToMapplsHex(strokeColor);

        final fill = await controller.addFill(
          FillOptions(
            geometry: [coordinates],
            fillColor: '#$fillHex',
            fillOpacity: fillColor.opacity,
            fillOutlineColor: '#$strokeHex',
          ),
        );

        _fills[polygon.id] = fill;
      } catch (e) {
        print('Error adding polygon: $e');
      }
    }
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId) async {
    if (controller is! MapplsMapController) return;

    final matchingEntries = _fills.entries
        .where((entry) => entry.key.contains(polygonId))
        .toList();
    print("matchingEntries $matchingEntries");
    for (final entry in matchingEntries) {
      await controller.removeFill(entry.value);
      _fills.remove(entry.key);
    }
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is MapplsMapController) {
      final fills = List<Fill>.from(_fills.values);

      for (final fill in fills) {
        try {
          await controller.removeFill(fill);
        } catch (_) {}
      }

      _fills.clear();
    }
  }

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    if (controller is MapplsMapController) {
      bool isWaypoint = false;
      if(polyline.properties?["lineCategory"] != null){
        isWaypoint = polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
      }

      if(isWaypoint) return;
      try {
        final coordinates = polyline.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();

        final line = await controller.addLine(
          LineOptions(
            geometry: coordinates,
            lineColor: '#fa9b9c9',
            lineWidth: 1.0,
            lineOpacity: 0.8,
          ),
        );

        _lines[polyline.id] = line;
      } catch (e) {
        print('Error adding polyline: $e');
      }
    }
  }

  @override
  Future<void> removePolyline(dynamic controller, String polylineId) async {
    if (controller is! MapplsMapController) return;

    final matchingEntries = _lines.entries
        .where((entry) => entry.key.contains(polylineId))
        .toList();

    for (final entry in matchingEntries) {
      try {
        await controller.removeLine(entry.value);
      } catch (_) {}

      _lines.remove(entry.key);
    }
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        for (var line in _lines.values) {
          await controller.removeLine(line);
        }
        _lines.clear();
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

  Future<void> enableClustering(dynamic controller, List<GeoJsonMarker> markers) async {
    if (controller is! MapplsMapController) return;

    try {
      // Create GeoJSON feature collection
      final features = markers.map((marker) => {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [marker.position.longitude, marker.position.latitude],
        },
        'properties': {
          'title': marker.title,
          'id': marker.id,
        }
      }).toList();

      await controller.addGeoJsonSource(_clusterSourceId, {
        'type': 'FeatureCollection',
        'features': features,
      });

      await controller.addSymbolLayer(
        _clusterSourceId,
        'cluster-count',
        SymbolLayerProperties(
          iconImage: ["get", "icon"],
          iconSize: 1.5,
          textField: ["get", "title"],
          textSize: 10,
          textColor: "#000000",
          textHaloColor: "#FFFFFF",
          textHaloWidth: 2,
          textAnchor: "top",
          textOffset: [0, 1.2],
          iconAllowOverlap: false,
          textAllowOverlap: false,
        ),
        enableInteraction: true,
      );

    } catch (e) {
      print('Error enabling clustering: $e');
    }
  }
}