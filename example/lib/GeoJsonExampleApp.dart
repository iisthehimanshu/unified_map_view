// example/lib/geojson_example.dart

import 'package:flutter/material.dart';
import 'package:unified_map_view/unified_map_view.dart';

void main() => runApp(const GeoJsonExampleApp());

class GeoJsonExampleApp extends StatelessWidget {
  const GeoJsonExampleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoJSON Map Example',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const GeoJsonMapScreen(),
    );
  }
}

class GeoJsonMapScreen extends StatefulWidget {
  const GeoJsonMapScreen({Key? key}) : super(key: key);

  @override
  State<GeoJsonMapScreen> createState() => _GeoJsonMapScreenState();
}

class _GeoJsonMapScreenState extends State<GeoJsonMapScreen> {
  late UnifiedMapController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _controller = UnifiedMapController(
      initialProvider: MapProvider.google,
      config: const MapConfig(
        initialLocation: MapLocation(latitude: 0, longitude: 0),
        initialZoom: 2.0,
      ),
    );
    _controller.setMapStyle("assets/mapstyle.json");
  }

  // Load GeoJSON from assets
  Future<void> _loadGeoJsonFromAssets() async {
    setState(() => _isLoading = true);

    // try {
      // Load your GeoJSON file from assets
      // await _controller.loadGeoJsonFromAsset('assets/response.json');
      await _controller.setVenue("IITDelhi");

      // Fit map to show all features
      await _controller.fitBoundsToGeoJson();

      _showMessage('GeoJSON loaded successfully!');
    // } catch (e) {
    //   _showMessage('Error loading GeoJSON: $e');
    // } finally {
    //   setState(() => _isLoading = false);
    // }
  }


  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoJSON Map Example'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Controls
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Map Provider:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _controller.switchProvider(MapProvider.google),
                        icon: const Icon(Icons.map, size: 16),
                        label: const Text('Google'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _controller.switchProvider(MapProvider.mapbox),
                        icon: const Icon(Icons.layers, size: 16),
                        label: const Text('Mapbox'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _loadGeoJsonFromAssets,
                  icon: const Icon(Icons.folder),
                  label: const Text('Load from Assets'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () => _controller.clearAllGeoJsonFeatures(),
                  icon: const Icon(Icons.clear),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  label: const Text('Clear All'),
                ),
                _buildFloorIndicator(),
              ],
            ),
          ),

          // Map
          Expanded(
            child: Stack(
              children: [
                UnifiedMapWidget(controller: _controller),

                // Floor indicator badge

              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloorSpeedDial(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  String? _currentBuildingId;

  bool _isSpeedDialOpen = false;
  int? _currentFloor = 0;
  List<int> _availableFloors = [];


  Future<void> _loadFloor(int floor) async {
    if (_currentBuildingId == null) return;

    setState(() => _isLoading = true);

    try {
      // Clear current features
      await _controller.clearAllGeoJsonFeatures();

      // Get features for the selected floor
      // final venueData = _controller..instance;
      // if (venueData != null) {
      //   // final features = venueData.getFeaturesForBuildingAndFloor(
      //   //   _currentBuildingId!,
      //   //   floor,
      //   // );
      //   //
      //   // // Add features to map
      //   // for (var feature in features) {
      //   //   await _controller.addGeoJsonFeature(feature);
      //   // }
      //   //
      //   // venueData.setSelectedFloor(_currentBuildingId!, floor);
      //
      //   setState(() {
      //     _currentFloor = floor;
      //   });
      //
      //   await _controller.fitBoundsToGeoJson();
      //   _showMessage('Loaded Floor $floor');
      // }
    } catch (e) {
      _showMessage('Error loading floor: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Build speed dial for floor selection
  Widget _buildFloorSpeedDial() {
    if (_availableFloors.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Floor options (shown when speed dial is open)
        if (_isSpeedDialOpen) ...[
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Card(
              elevation: 8,
              margin: const EdgeInsets.only(bottom: 8),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _availableFloors.map((floor) {
                    final isSelected = floor == _currentFloor;
                    return Material(
                      color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                      child: InkWell(
                        onTap: _isLoading
                            ? null
                            : () {
                          _loadFloor(floor);
                          setState(() => _isSpeedDialOpen = false);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.layers,
                                size: 20,
                                color: isSelected ? Colors.blue : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Floor $floor',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.blue : Colors.black87,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],

        // Main FAB button
        FloatingActionButton(
          heroTag: 'floor_switcher',
          onPressed: () {
            setState(() => _isSpeedDialOpen = !_isSpeedDialOpen);
          },
          backgroundColor: _isSpeedDialOpen ? Colors.red : Colors.blue,
          child: AnimatedRotation(
            turns: _isSpeedDialOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(_isSpeedDialOpen ? Icons.close : Icons.layers),
          ),
        ),
      ],
    );
  }

  // Build current floor indicator
  Widget _buildFloorIndicator() {
    if (_currentFloor == null) return const SizedBox.shrink();

    return Positioned(
      top: 50,
      right: 16,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.layers, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Floor $_currentFloor',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// SAMPLE GEOJSON FILES FOR TESTING
// ============================================

/*
Create these files in your assets folder:

1. assets/data.geojson - Points
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "name": "Location 1",
        "description": "First marker"
      },
      "geometry": {
        "type": "Point",
        "coordinates": [-122.4194, 37.7749]
      }
    }
  ]
}

2. assets/routes.geojson - LineStrings
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "name": "Route 1"
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [-122.4194, 37.7749],
          [-122.4084, 37.7849],
          [-122.3974, 37.7949]
        ]
      }
    }
  ]
}

3. assets/zones.geojson - Polygons
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "properties": {
        "name": "Zone 1",
        "type": "restricted"
      },
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [
            [-122.4194, 37.7749],
            [-122.4084, 37.7749],
            [-122.4084, 37.7849],
            [-122.4194, 37.7849],
            [-122.4194, 37.7749]
          ]
        ]
      }
    }
  ]
}

Don't forget to add to pubspec.yaml:
assets:
  - assets/data.geojson
  - assets/routes.geojson
  - assets/zones.geojson
*/