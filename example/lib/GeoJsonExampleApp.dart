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
  late UnifiedMapController _unifiedMapController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _unifiedMapController = UnifiedMapController(
        initialProvider: MapProvider.mappls,
        venueName: 'Mapmyindia',
        initialLocation: UnifiedCameraPosition(
          mapLocation: MapLocation(latitude: 28.6139, longitude: 77.2090), // Delhi
          zoom: 12.0,
          bearing: 0.0,
        )
    );
    
    _unifiedMapController.setMapStyle("assets/mapstyle.json");
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
                        onPressed: () => _unifiedMapController.switchProvider(MapProvider.google),
                        icon: const Icon(Icons.map, size: 16),
                        label: const Text('Google'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _unifiedMapController.switchProvider(MapProvider.mappls),
                        icon: const Icon(Icons.layers, size: 16),
                        label: const Text('Mappls'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () => _unifiedMapController.deSelectLocation(),
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
                UnifiedMapWidget(controller: _unifiedMapController),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _unifiedMapController.dispose();
    super.dispose();
  }
}

/*
============================================
USAGE NOTES
============================================

1. INITIALIZATION:
   UnifiedMapController(
     initialProvider: MapProvider.mappls,  // Choose your map provider
     config: MapConfig(...),                // Set initial camera position
     venueName: 'IITDelhi',                // Your venue name
   );

2. LOADING GEOJSON:
   - From Assets:
     await controller.loadGeoJsonFromAsset('assets/data.geojson');

   - From String:
     await controller.loadGeoJsonFromString(jsonString);

3. MARKER MANAGEMENT:
   - Add individual marker:
     await controller.addMarker(MapMarker(
       id: 'marker-1',
       position: MapLocation(lat: 28.6139, lng: 77.2090),
       title: 'My Location',
     ));

   - Remove marker:
     await controller.removeMarker('marker-1');

   - Clear all markers:
     await controller.clearMarkers();

4. POLYGON MANAGEMENT:
   - Polygons are automatically created from GeoJSON
   - Remove by ID:
     await controller.removePolygon('polygon-id');

   - Clear all:
     await controller.clearPolygons();

5. CAMERA CONTROL:
   - Move camera:
     await controller.moveCamera(
       MapLocation(lat: 28.6139, lng: 77.2090),
       zoom: 15.0,
     );

   - Animate camera:
     await controller.animateCamera(location, zoom: 15.0);

   - Fit to all features:
     await controller.fitBoundsToGeoJson();

6. FLOOR MANAGEMENT (for venue maps):
   - Get focused building:
     String? building = controller.focusedBuilding;

   - Get available floors:
     List<int>? floors = controller.focusedBuildingAvailableFloors;

   - Change floor:
     await controller.changeBuildingFloor(
       buildingID: 'building-123',
       floor: 2,
     );

7. PROVIDER SWITCHING:
   controller.switchProvider(MapProvider.google);
   controller.switchProvider(MapProvider.mappls);

8. MARKER RENDERING:
   - Markers always render on TOP of polygons and polylines
   - Each marker shows its unique title
   - Default icon is 'marker-15' from Mappls
   - Text appears below the marker icon

9. GEOJSON FEATURES SUPPORTED:
   - Point → Markers
   - Polygon → Filled shapes
   - LineString → Polylines
   - Properties are preserved and can be accessed

10. LISTENING TO CHANGES:
    controller.addListener(() {
      // React to map changes
      print('Camera: ${controller.cameraPosition}');
      print('Markers: ${controller.markers.length}');
    });
*/