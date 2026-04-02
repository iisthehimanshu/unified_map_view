// example/lib/geojson_example.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unified_map_view/unified_map_view.dart';
import 'package:mappls_gl/mappls_gl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MapplsAccountManager.setMapSDKKey("6889110931e58e2b999fb9131f78cc2e");
  MapplsAccountManager.setRestAPIKey("6889110931e58e2b999fb9131f78cc2e");
  MapplsAccountManager.setAtlasClientId("96dHZVzsAuuuN3sEWtPRTabth0A-fz0ZseWHjAq-2lqZV1-b6Tus_MG1v2j-R_o60cIYwVrzPH9ns6LmM1VKvQ==");
  MapplsAccountManager.setAtlasClientSecret("lrFxI-iSEg9he_iO5iRlieP4vy0VnS26w3KGnCTD8jVPei5dJTFX7EDYjrQN1xR-8nvS-qGOIN8DiuvdoAXe4FjMN6Sg_Nsi");
  await UnifiedMapViewPackage.initialize();
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
        venueName: 'NationalZoologicalPark',
        initialLocation: UnifiedCameraPosition(
          mapLocation: MapLocation(latitude: 21.7679, longitude: 78.8718), // Delhi
          zoom: 3.0,
          bearing: 0.0,
          tilt: 0.0
        ),
      url: "https://dev.iwayplus.in",
      languageCode: "hi"
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
    _unifiedMapController.localizeUser(User(MapLocation(latitude: 28.544238796241345, longitude: 77.20697074957559), "696f514c1caa6fd666e58a74", -1));
  }

  void _stopMovingUser() {
    _moveUserTimer?.cancel();
  }

  var path = [
    {"node": 3897251, "x": 1187, "y": 1068, "lat": 28.605888170592493, "lng": 77.24386953260642, "ttsEnabled": true, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": true, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3780534, "x": 1206, "y": 1036, "lat": 28.605980230123173, "lng": 77.24392508778026, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3660122, "x": 1178, "y": 1003, "lat": 28.606064001791694, "lng": 77.24383147096121, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3568899, "x": 1155, "y": 978, "lat": 28.606131526628268, "lng": 77.24375601036077, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3561602, "x": 1154, "y": 976, "lat": 28.606134750510574, "lng": 77.24375240759612, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3401058, "x": 1122, "y": 932, "lat": 28.606252523193668, "lng": 77.24364657443407, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3386464, "x": 1120, "y": 928, "lat": 28.606261654031556, "lng": 77.24363836925932, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3324435, "x": 1107, "y": 911, "lat": 28.60630798798481, "lng": 77.24359598411456, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3222271, "x": 1087, "y": 883, "lat": 28.606381770268804, "lng": 77.2435296822523, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3076323, "x": 1059, "y": 843, "lat": 28.60648615805889, "lng": 77.24343587782425, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3047133, "x": 1053, "y": 835, "lat": 28.606507569381545, "lng": 77.24341591341782, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3036187, "x": 1051, "y": 832, "lat": 28.606515305681285, "lng": 77.2434086999152, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 2996051, "x": 1043, "y": 821, "lat": 28.606544453303684, "lng": 77.24338152200615, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 2963213, "x": 1037, "y": 812, "lat": 28.60656739974462, "lng": 77.24336012622037, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 2981445, "x": 1029, "y": 817, "lat": 28.60655256183624, "lng": 77.2433371048761, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3017903, "x": 1007, "y": 827, "lat": 28.60652270001188, "lng": 77.24327014187645, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3032472, "x": 984, "y": 831, "lat": 28.606507421621885, "lng": 77.24319768786177, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3028798, "x": 958, "y": 830, "lat": 28.60650576680044, "lng": 77.24311811460171, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3014177, "x": 929, "y": 826, "lat": 28.60651329211713, "lng": 77.24302568647795, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3017796, "x": 900, "y": 827, "lat": 28.606507093917813, "lng": 77.24293672552818, "ttsEnabled": false, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3036008, "x": 872, "y": 832, "lat": 28.606490411898534, "lng": 77.24284912080952, "ttsEnabled": true, "bid": "6998011da89f89231fabc59f", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": true, "isFloorConnection": false, "connectorType": null, "color": null}
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
                child: FloorSpeedDial(controller: _unifiedMapController),)
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