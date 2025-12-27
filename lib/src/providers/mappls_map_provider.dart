// lib/src/providers/mappls_map_provider.dart

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mappls_gl/mappls_gl.dart';
import '../models/camera_position.dart';
import '../utils/renderingUtilities.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/map_marker.dart';
import '../models/geojson_models.dart';

/// Mappls GL implementation of BaseMapProvider
/// Supports Mappls (MapmyIndia) maps - India's own mapping platform
class MapplsMapProvider extends BaseMapProvider {
  final Map<String, Symbol> _symbols = {};
  final Map<String, Line> _lines = {};
  final Map<String, Fill> _fills = {};
  MapplsMapController? _controller;

  // Clustering configuration
  bool _clusteringEnabled = true;
  int _clusterMaxZoom = 14;
  double _clusterRadiusInMeters = 100;
  bool _layersInitialized = false;

  // Track markers for clustering
  final List<MapMarker> _allMarkers = [];

  @override
  Widget buildMap({
    required MapConfig config,
    required Function(dynamic controller) onMapCreated,
    Set<MapMarker>? markers,
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
        controller.onSymbolTapped.add(_onSymbolTapped);
        controller.onFillTapped.add(_onFillTapped);
        await _addMarkerImage();
        // Add initial markers if provided
        if (markers != null) {
          for (var marker in markers) {
            await addMarker(controller, marker);
          }
        }
      },
      onStyleLoadedCallback: () async {
        print("Style loaded, initializing clustering layers");
        if (_clusteringEnabled && _controller != null) {
          // await _initializeClusteringLayers();
          // Update markers if any were added before style loaded
          if (_allMarkers.isNotEmpty) {
            await _addPendingMarkers();
          }
        }
      },
      onMapClick: (Point<double> point, LatLng latlng) async {
        print("onMapClick");
        final features = await _controller!.queryRenderedFeatures(
          point,
          ['marker-layer-'], // OR all your marker layer IDs
          null,
        );

        if (features.isNotEmpty) {
          final feature = features.first;
          final props = feature['properties'];

          debugPrint("🟢 SymbolLayer tapped");
          debugPrint("Feature id: ${feature['id']}");
          debugPrint("Properties: $props");

          final tappedMarkerId = props?['id'];
          if (tappedMarkerId != null) {
            debugPrint("Tapped marker id: $tappedMarkerId");
          }
        }else{
          print("features.isEmpty");
        }
        print(point);
        print(latlng);
      },
      onAttributionClick: (){
        print("onAttributionClick");
      },
      myLocationEnabled: config.showUserLocation,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      compassEnabled: true,
      rotateGesturesEnabled: config.rotateGesturesEnabled,
      scrollGesturesEnabled: config.scrollGesturesEnabled,
      tiltGesturesEnabled: config.tiltGesturesEnabled,
      zoomGesturesEnabled: config.zoomControlsEnabled,
      minMaxZoomPreference: const MinMaxZoomPreference(4, 18),

      onCameraIdle: () async {
        print("onCameraIdle called");

        if (_controller != null) {
          try {
            final bounds = await _controller!.getVisibleRegion();
            if (bounds != null) {
              final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
              final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

              final cameraPos = await _controller!.cameraPosition;

              onCameraMove(UnifiedCameraPosition(
                mapLocation: MapLocation(
                  latitude: centerLat,
                  longitude: centerLng,
                ),
                zoom: cameraPos?.zoom ?? 0.0,
                bearing: cameraPos?.bearing ?? 0.0,
              ));
            }
          } catch (e) {
            print("Error getting camera position: $e");
          }
        }
      },

    );
  }
  void _onFillTapped(Fill fill) {
    debugPrint("🔵 Polygon tapped: ${fill.id}");

    final entry = _fills.entries.firstWhere(
          (e) => e.value.id == fill.id,
      orElse: () => MapEntry('', fill),
    );

    if (entry.key.isNotEmpty) {
      debugPrint("Polygon ID tapped: ${entry.key}");
      // TODO: highlight polygon / show details
    }
  }

  void _onSymbolTapped(Symbol symbol) {
    debugPrint("🟢 Symbol tapped: ${symbol.id}");

    final entry = _symbols.entries.firstWhere(
          (e) => e.value.id == symbol.id,
      orElse: () => MapEntry('', symbol),
    );

    if (entry.key.isNotEmpty) {
      debugPrint("Marker ID tapped: ${entry.key}");
      // 👉 open bottom sheet / show details / highlight marker
    }
  }


  Future<void> _addMarkerImage() async {
    final ByteData bytes = await rootBundle.load('assets/MapLift.png');

    final Uint8List list = bytes.buffer.asUint8List();

    await _controller!.addImage(
      'custom-lift-marker', // 👈 image ID
      list,
    );
    final ByteData maleWashroombytes = await rootBundle.load('assets/MapMaleWashroom.png');

    final Uint8List maleWashroomlist = maleWashroombytes.buffer.asUint8List();

    await _controller!.addImage(
      'custom-male-marker', // 👈 image ID
      maleWashroomlist,
    );

    final ByteData femaleWashroombytes = await rootBundle.load('assets/MapFemaleWashroom.png');

    final Uint8List femaleWashroomlist = femaleWashroombytes.buffer.asUint8List();

    await _controller!.addImage(
      'custom-female-marker', // 👈 image ID
      femaleWashroomlist,
    );
  }

  /// Initialize clustering layers using GeoJSON source and symbol layers
  Future<void> _initializeClusteringLayers() async {
    if (_layersInitialized || _controller == null) {
      print("Skipping layer init - already initialized: $_layersInitialized");
      return;
    }

    try {
      print("Adding GeoJSON source for markers");

      // Add GeoJSON source for markers
      await _controller!.addGeoJsonSource(
        'markers-source',
        {
          'type': 'FeatureCollection',
          'features': [],
        },
      );
      print("GeoJSON source added successfully");

      // Add symbol layer for individual markers (unclustered)
      await _controller!.addSymbolLayer(
        'markers-source',
        'markers-layer',
        const SymbolLayerProperties(
          iconImage: 'marker-15',
          iconSize: 1.5,
          textField: '{title}',
          textSize: 10.0,
          textColor: '#000000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.0,
        ),
        enableInteraction: true,
      );
      print("Symbol layer added successfully");

      _layersInitialized = true;
      print("Clustering layers initialized successfully");
    } catch (e) {
      print('Error initializing clustering layers: $e');
      print('Stack trace: ${StackTrace.current}');
      _layersInitialized = false;
    }
  }

  /// Add all pending markers that were added before style loaded
  Future<void> _addPendingMarkers() async {
    if (_controller == null || !_layersInitialized) return;

    try {
      final features = _allMarkers.map((marker) {
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
            'id': marker.id,
            'title': marker.title ?? '',
          },
        };
      }).toList();

      final geojson = {
        'type': 'FeatureCollection',
        'features': features,
      };

      // Use setGeoJsonSource to update existing source
      await _controller!.setGeoJsonSource('markers-source', geojson);
      print("Added ${features.length} pending markers to map");
    } catch (e) {
      print('Error adding pending markers: $e');
    }
  }

  /// Add a single marker's GeoJSON feature and update the source
  Future<void> _addMarkerToSource(MapMarker marker) async {
    if (_controller == null) return;

    String finalMarkerId = "${marker.position.longitude} ${marker.position.longitude}";

    final sourceId = 'marker-source-${finalMarkerId}';
    final layerId = 'marker-layer-${finalMarkerId}';

    await _controller!.removeLayer(layerId);
    await _controller!.removeSource(sourceId);
    final geojson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'id': finalMarkerId,
          'geometry': {
            'type': 'Point',
            'coordinates': [
              marker.position.longitude,
              marker.position.latitude,
            ],
          },
        },
      ],
    };

    try {

      // 🔵 First time marker
      await _controller!.addGeoJsonSource(sourceId, geojson);

      await _controller!.addSymbolLayer(
        sourceId,
        layerId,
        SymbolLayerProperties(
          iconImage: RenderingUtilities.getMarkerIconId(marker.title),
          iconSize: 1.5,
          textField: marker.title ?? '',
          textSize: 10.0,
          textColor: '#000000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.0,
          textAnchor: 'top',
          textOffset: [0, 1.2],
          textAllowOverlap: false,
          iconAllowOverlap: false,
        ),
        enableInteraction: true,
      );


      print('✅ Marker ${finalMarkerId} added');
    } catch (e) {
      print('❌ Error adding marker ${finalMarkerId}: $e');
    }
  }



  /// Enable or disable clustering
  void setClusteringEnabled(bool enabled) {
    _clusteringEnabled = enabled;
  }

  /// Configure clustering parameters
  void setClusteringConfig({
    int? maxZoom,
    double? radiusInMeters,
  }) {
    if (maxZoom != null) _clusterMaxZoom = maxZoom;
    if (radiusInMeters != null) _clusterRadiusInMeters = radiusInMeters;
  }

  @override
  Future<void> moveCamera(dynamic controller, MapLocation location, double zoom) async {
    if (controller is MapplsMapController) {
      print("current location ${location.latitude} ${location.longitude}");
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
  Future<void> addMarker(dynamic controller, MapMarker marker) async {
    if (controller is MapplsMapController) {
      try {
        _allMarkers.add(marker);
        print("Adding marker: ${marker.id} at ${marker.position.latitude}, ${marker.position.longitude}");
        print("Clustering enabled: $_clusteringEnabled, Layers initialized: $_layersInitialized");
        await _addMarkerToSource(marker);
        // if (_clusteringEnabled && _layersInitialized) {
        //   // Add marker to GeoJSON source immediately - symbol will be added automatically
        //   await _addMarkerToSource(marker);
        // } else if (_clusteringEnabled && !_layersInitialized) {
        //   // Wait for layers to be initialized
        //   print("Markers will be added once style loads (${_allMarkers.length} markers pending)");
        // } else {
        //   // Add as regular symbol (non-clustered)
        //   print("Adding marker as regular symbol");
        //   final symbol = await controller.addSymbol(
        //     SymbolOptions(
        //       geometry: LatLng(
        //         marker.position.latitude,
        //         marker.position.longitude,
        //       ),
        //       iconImage: 'marker-15',
        //       iconSize: 1.5,
        //       textField: marker.title,
        //       textSize: 10.0,
        //       textOffset: const Offset(0, 1.5),
        //       textColor: '#000000',
        //       textHaloColor: '#FFFFFF',
        //       textHaloWidth: 2.0,
        //
        //     ),
        //   );
        //   _symbols[marker.id] = symbol;
        // }
      } catch (e) {
        print('Error adding marker: $e');
      }
    }
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    if (controller is! MapplsMapController) return;

    _allMarkers.removeWhere((m) => m.id == markerId);

    if (_clusteringEnabled && _layersInitialized) {
      // Update GeoJSON source with remaining markers
      final features = _allMarkers.map((m) {
        return {
          'type': 'Feature',
          'id': m.id,
          'geometry': {
            'type': 'Point',
            'coordinates': [
              m.position.longitude,
              m.position.latitude,
            ],
          },
          'properties': {
            'id': m.id,
            'title': m.title ?? '',
          },
        };
      }).toList();

      final geojson = {
        'type': 'FeatureCollection',
        'features': features,
      };

      await _controller!.setGeoJsonSource('markers-source', geojson);
    } else {
      final matchingEntries = _symbols.entries
          .where((entry) => entry.key.contains(markerId))
          .toList();

      for (final entry in matchingEntries) {
        try {
          await controller.removeSymbol(entry.value);
        } catch (_) {}
        _symbols.remove(entry.key);
      }
    }
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is MapplsMapController) {
      try {
        _allMarkers.clear();

        if (_clusteringEnabled && _layersInitialized) {
          // Clear GeoJSON source using setGeoJsonSource
          await _controller!.setGeoJsonSource(
            'markers-source',
            {
              'type': 'FeatureCollection',
              'features': [],
            },
          );
          print("Cleared all markers from GeoJSON source");
        } else {
          for (var symbol in _symbols.values) {
            try {
              await controller.removeSymbol(symbol);
            } catch (_) {}
          }
          _symbols.clear();
        }
      } catch (e) {
        print('Error clearing markers: $e');
      }
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
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    print("polgonid ${polygon.id}");
    if (controller is MapplsMapController) {
      try {
        final String? rawType = polygon.properties?["type"];
        final String? type = rawType?.toLowerCase();

        final String? fillColorHex = polygon.properties?["fillColor"];
        final String? strokeColorHex = polygon.properties?["strokeColor"];

        final Color fillColor =
        (fillColorHex != null && fillColorHex != "undefined" && fillColorHex.isNotEmpty)
            ? RenderingUtilities.hexToColor(fillColorHex, opacity: 1.0)
            : RenderingUtilities.polygonColorMap[type]?["fillColor"]
            ?? Colors.blue.withOpacity(0.0);

        final Color strokeColor =
        (strokeColorHex != null && strokeColorHex != "undefined" && strokeColorHex.isNotEmpty)
            ? RenderingUtilities.hexToColor(strokeColorHex)
            : RenderingUtilities.polygonColorMap[type]?["strokeColor"]
            ?? Colors.blue.withOpacity(0.0);

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

  /// Add custom symbol with custom icon
  Future<void> addCustomMarker(
      MapplsMapController controller,
      MapMarker marker, {
        String? customIconImage,
        double? iconSize,
      }) async {
    try {
      final symbol = await controller.addSymbol(
        SymbolOptions(
          geometry: LatLng(
            marker.position.latitude,
            marker.position.longitude,
          ),
          iconImage: customIconImage ?? 'marker-15',
          iconSize: iconSize ?? 1.5,
          textField: marker.title ?? '',
          textSize: 12.0,
          textOffset: const Offset(0, 1.5),
        ),
      );

      _symbols[marker.id] = symbol;
    } catch (e) {
      print('Error adding custom marker: $e');
    }
  }

  /// Update polygon style
  Future<void> updatePolygonStyle(
      MapplsMapController controller,
      String polygonId, {
        String? fillColor,
        double? fillOpacity,
        String? outlineColor,
      }) async {
    if (_fills.containsKey(polygonId)) {
      try {
        await controller.updateFill(
          _fills[polygonId]!,
          FillOptions(
            fillColor: fillColor,
            fillOpacity: fillOpacity,
            fillOutlineColor: outlineColor,
          ),
        );
      } catch (e) {
        print('Error updating polygon: $e');
      }
    }
  }

  /// Update polyline style
  Future<void> updatePolylineStyle(
      MapplsMapController controller,
      String polylineId, {
        String? lineColor,
        double? lineWidth,
        double? lineOpacity,
      }) async {
    if (_lines.containsKey("polygonId")) {
      try {
        await controller.updateLine(
          _lines[polylineId]!,
          LineOptions(
            lineColor: lineColor,
            lineWidth: lineWidth,
            lineOpacity: lineOpacity,
          ),
        );
      } catch (e) {
        print('Error updating polyline: $e');
      }
    }
  }

  /// Clear all map elements
  Future<void> clearAll(dynamic controller) async {
    await clearMarkers(controller);
    await clearPolygons(controller);
    await clearPolylines(controller);
  }
}