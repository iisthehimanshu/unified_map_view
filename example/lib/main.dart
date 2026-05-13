// example/lib/geojson_example.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:unified_map_view/maplibre.dart';
import 'package:unified_map_view/mappls.dart';
import 'package:unified_map_view/unified_map_view.dart';
// import 'package:mappls_gl/mappls_gl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MapplsAccountManager.setMapSDKKey("6889110931e58e2b999fb9131f78cc2e");
  MapplsAccountManager.setRestAPIKey("6889110931e58e2b999fb9131f78cc2e");
  MapplsAccountManager.setAtlasClientId("96dHZVzsAuuuN3sEWtPRTabth0A-fz0ZseWHjAq-2lqZV1-b6Tus_MG1v2j-R_o60cIYwVrzPH9ns6LmM1VKvQ==");
  MapplsAccountManager.setAtlasClientSecret("lrFxI-iSEg9he_iO5iRlieP4vy0VnS26w3KGnCTD8jVPei5dJTFX7EDYjrQN1xR-8nvS-qGOIN8DiuvdoAXe4FjMN6Sg_Nsi");
  await UnifiedMapViewPackage.initialize(venueName: 'NationalZoologicalPark');
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

  Timer? _moveUserTimer;

  // Demo user marker ID
  static const String _userMarkerId = 'demo-user-marker';

  // Demo route points for animation
  final List<MapLocation> _demoRoute = [
    MapLocation(latitude: 77.18750616904389, longitude: 28.54368402795895), // Delhi start
    MapLocation(latitude: 28.54368677, longitude: 77.2100),
    MapLocation(latitude: 28.6159, longitude: 77.2110),
    MapLocation(latitude: 28.6169, longitude: 77.2120),
    MapLocation(latitude: 28.6179, longitude: 77.2130),
  ];

  int _currentRouteIndex = 0;

  @override
  void initState() {
    super.initState();
    _unifiedMapController = UnifiedMapController(
        initialProvider: MapProvider.mapLibre,
        venueName: 'AIGHospital',
        initialLocation: UnifiedCameraPosition(
          mapLocation: MapLocation(latitude: 21.7679, longitude: 78.8718), // Delhi
          zoom: 3.0,
          bearing: 0.0,
          tilt: 0.0
        ),
      url: "https://dev.iwayplus.in",
      languageCode: "hi",
        providers: {MapProvider.mapLibre: MaplibreMapProvider(),
          MapProvider.mappls: MapplsMapProvider()}
    );
    
    _unifiedMapController.setMapStyle("assets/mapstyle.json");
    // Future.delayed(const Duration(seconds: 2), () {
    //   _addUserMarker();
    // });
  }

  // Future<void> _addUserMarker() async {
  //   final userMarker = GeoJsonMarker(
  //       id: "user",
  //       position: MapLocation(latitude: 77.18750616904389, longitude: 28.54368402795895),
  //       title: "",
  //       snippet: "",
  //       assetPath: 'packages/unified_map_view/assets/markers/user.png',
  //       iconName: "User",
  //       priority: true,
  //       imageSize: Size(35, 35),
  //       anchor: Offset(0.51, 0.785),
  //       compassBasedRotation: true
  //   );
  //
  //   await _unifiedMapController.addUserMarker(userMarker);
  // }

  void localizeUser(){
    _unifiedMapController.localizeUser(User(MapLocation(latitude: 17.443003846371283, longitude: 78.36624414341532), "69e88519412aec622fc75536", 0));
  }

  void _stopMovingUser() {
    _moveUserTimer?.cancel();
  }

  var path = [
    {"node": 3897251, "x": 1187, "y": 1068, "lat": 17.443003846371283, "lng": 78.36624414341532, "ttsEnabled": true, "bid": "69e88519412aec622fc75536", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": true, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3780534, "x": 1206, "y": 1036, "lat": 17.44313680329257, "lng": 78.36623342162618, "ttsEnabled": false, "bid": "69e88519412aec622fc75536", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3780534, "x": 1206, "y": 1036, "lat": 17.443180266500633, "lng": 78.36628798157611, "ttsEnabled": false, "bid": "69e88519412aec622fc75536", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3036008, "x": 872, "y": 832, "lat": 17.44309958389197 ,"lng": 78.36628466337953, "ttsEnabled": true, "bid": "69e88519412aec622fc75536", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": true, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat":17.44298967296045, "destinationLng": 78.36628052448958, "name":"Destination"}
  ];

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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (){
                          localizeUser();
                        },
                        icon: const Icon(Icons.my_location, size: 16),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        label: const Text('Localize User'),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (){
                          _unifiedMapController.addPath(path: path);
                          _unifiedMapController.annotatePath(bids: ["6998011da89f89231fabc59f"], sourceFloor: 0);
                        },
                        icon: const Icon(Icons.play_arrow, size: 16),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        label: const Text('Add Path'),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () async {
                        await _unifiedMapController.clearPath();
                        await _unifiedMapController.deSelectLocation();
                      },
                      icon: const Icon(Icons.refresh),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Map
          Expanded(
            child: Stack(
              children: [
                UnifiedMapWidget(controller: _unifiedMapController),
                Positioned(bottom: 150,
                right: 16,
                child: Column(
                  children: [
                    FloorSpeedDial(controller: _unifiedMapController),
                    SizedBox(height: 12,),
                    ExtrusionToggleButton(controller: _unifiedMapController)
                  ],
                ),)
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _moveUserTimer?.cancel();
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