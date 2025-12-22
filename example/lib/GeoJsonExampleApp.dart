// example/lib/geojson_example.dart

import 'package:flutter/material.dart';
import 'package:unified_map_view/unified_map_view.dart';
import 'package:mappls_gl/mappls_gl.dart';

void main(){
  WidgetsFlutterBinding.ensureInitialized();
  MapplsAccountManager.setMapSDKKey("6889110931e58e2b999fb9131f78cc2e");
  MapplsAccountManager.setRestAPIKey("6889110931e58e2b999fb9131f78cc2e");
  MapplsAccountManager.setAtlasClientId("96dHZVzsAuuuN3sEWtPRTabth0A-fz0ZseWHjAq-2lqZV1-b6Tus_MG1v2j-R_o60cIYwVrzPH9ns6LmM1VKvQ==");
  MapplsAccountManager.setAtlasClientSecret("lrFxI-iSEg9he_iO5iRlieP4vy0VnS26w3KGnCTD8jVPei5dJTFX7EDYjrQN1xR-8nvS-qGOIN8DiuvdoAXe4FjMN6Sg_Nsi");
  runApp(const GeoJsonExampleApp());
}

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
      initialProvider: MapProvider.mappls,
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
                        onPressed: () => _controller.switchProvider(MapProvider.mappls),
                        icon: const Icon(Icons.layers, size: 16),
                        label: const Text('Mappls'),
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
              ],
            ),
          ),

          // Map
          Expanded(
            child: Stack(
              children: [
                UnifiedMapWidget(controller: _controller),

                // 🔹 TOP Floating Action Button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  right: 16,
                  child: _floorSelector(),
                ),

                // ✅ Floor FAB at top-right (below indicator)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16 + 230,
                  right: 16,
                  child: _floorFab(),
                ),
              ],
            ),
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

  int? _currentFloor = 0;
  List<int> _availableFloors = [];


  Future<void> _loadFloor(int floor) async {
    setState(() => _isLoading = true);
    try {
      // if(_controller.returnBuildingFloors() != null){
      //   _availableFloors = _controller.returnBuildingFloors()!;
      //   print("_availableFloors $_availableFloors");
      // }
      await _controller.changeBuildingFloor(floor);
    } catch (e) {
      _showMessage('Error loading floor: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _showFloors = false;

  final List<int> _floors = [0, 1, 2, 3, 4];
  Widget _floorSelector() {
    if (!_showFloors) return const SizedBox.shrink();

    return Card(
      elevation: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _floors.map((floor) {
          final isSelected = floor == _currentFloor;

          return InkWell(
            onTap: () {
              setState(() {
                _currentFloor = floor;
                _showFloors = false;
              });

              // 👉 load floor here
              _loadFloor(floor);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.layers,
                    size: 18,
                    color: isSelected ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Floor $floor',
                    style: TextStyle(
                      fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }


  Widget _floorFab() {
    return FloatingActionButton(
      onPressed: () {
        setState(() => _showFloors = !_showFloors);
      },
      child: Icon(_showFloors ? Icons.close : Icons.layers),
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