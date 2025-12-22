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
  }

  // Load GeoJSON from assets
  Future<void> _loadGeoJsonFromAssets() async {
    setState(() => _isLoading = true);

    try {
      // Load your GeoJSON file from assets
      await _controller.loadGeoJsonFromAsset('assets/response.json');

      // Fit map to show all features
      await _controller.fitBoundsToGeoJson();

      _showMessage('GeoJSON loaded successfully!');
    } catch (e) {
      _showMessage('Error loading GeoJSON: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Load sample GeoJSON string
  Future<void> _loadSampleGeoJson() async {
    setState(() => _isLoading = true);

    try {
      const sampleGeoJson = '''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "building_ID": "65d887a5db333f89457145f6",
            "id": "6889bb72fe0f245a59f34d6a",
            "type": "Feature",
            "geometry": {
                "coordinates": [
                    [
                        [
                            77.18743341981822,
                            28.54354478970558
                        ],
                        [
                            77.18732890047193,
                            28.543587605499436
                        ],
                        [
                            77.18738949561822,
                            28.543701755275144
                        ],
                        [
                            77.18749401496453,
                            28.54365893948129
                        ],
                        [
                            77.18743341981822,
                            28.54354478970558
                        ]
                    ]
                ],
                "type": "Polygon"
            },
            "properties": {
                "name": "GA3-NCAHT",
                "buildingName": "Research and Innovation Park",
                "nodeId": "0472b85-8a15-d3-fa41-2f66ea72a34",
                "polygonType": "Room",
                "type": "Room",
                "walkableType": "non-walkable",
                "visibilityType": "visible",
                "directionType": "bidirectional",
                "tactileAvailibity": "not available",
                "fillColor": "undefined",
                "height": "undefined",
                "global": false,
                "floor": 0
            }
        }
        ]
      }
      ''';

      await _controller.loadGeoJsonFromString(sampleGeoJson);
      await _controller.fitBoundsToGeoJson();

      _showMessage('Sample GeoJSON loaded!');
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
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
                const SizedBox(height: 16),
                const Text(
                  'Load GeoJSON:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _loadSampleGeoJson,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Load Sample GeoJSON'),
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
              ],
            ),
          ),

          // Map
          Expanded(
            child: UnifiedMapWidget(controller: _controller),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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