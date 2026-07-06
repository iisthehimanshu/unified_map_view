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
        venueName: 'RGCI',
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
    _unifiedMapController.localizeUser(User(MapLocation(latitude: 28.716439358009897, longitude: 77.1109546329173), "65d88662db333f894570bad3", 0));
  }

  void moveUser() {
    // Restart any in-progress animation.
    _moveUserTimer?.cancel();
    if (path.length < 2) return;

    // Build a smooth trail by interpolating extra points between each pair of
    // consecutive path nodes, so the user glides along the route (and the grey
    // traversed overlay gets frequent projection updates) instead of jumping.
    const stepsPerSegment = 10;
    final trail = <User>[];
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i];
      final b = path[i + 1];
      final aLat = (a['lat'] as num).toDouble();
      final aLng = (a['lng'] as num).toDouble();
      final bLat = (b['lat'] as num).toDouble();
      final bLng = (b['lng'] as num).toDouble();
      final bid = a['bid'] as String;
      final floor = (a['floor'] as num).toInt();

      for (var s = 0; s < stepsPerSegment; s++) {
        final t = s / stepsPerSegment;
        trail.add(
          User(
            MapLocation(
              latitude: aLat + (bLat - aLat) * t,
              longitude: aLng + (bLng - aLng) * t,
            ),
            bid,
            floor,
          ),
        );
      }
    }
    // Include the final node exactly.
    final last = path.last;
    trail.add(
      User(
        MapLocation(
          latitude: (last['lat'] as num).toDouble(),
          longitude: (last['lng'] as num).toDouble(),
        ),
        last['bid'] as String,
        (last['floor'] as num).toInt(),
      ),
    );

    var index = 0;
    _moveUserTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (index >= trail.length) {
        timer.cancel();
        return;
      }
      // Use localizeUser (not moveUser): the first call creates the user
      // marker, and later calls with the same bid/floor route to moveUser
      // internally, which is what draws the grey traversed path.
      _unifiedMapController.localizeUser(trail[index]);
      index++;
    });
  }

  void _stopMovingUser() {
    _moveUserTimer?.cancel();
  }

  var path = [
    {"node": 3897251, "x": 112, "y": 82, "lat": 28.716439358009897, "lng": 77.1109546329173, "ttsEnabled": true, "bid": "65d88662db333f894570bad3", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": true, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3780534, "x": 115, "y": 82, "lat": 28.71644644755438, "lng": 77.11096073708924, "ttsEnabled": false, "bid": "65d88662db333f894570bad3", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3780534, "x": 115, "y": 92, "lat": 28.716429974372552, "lng": 77.11098567502565, "ttsEnabled": false, "bid": "65d88662db333f894570bad3", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
    {"node": 3036008, "x": 113, "y": 104, "lat": 28.716406312087642 ,"lng": 77.11101218917014, "ttsEnabled": true, "bid": "65d88662db333f894570bad3", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": true, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat":28.716406312087642, "destinationLng": 77.11101218917014, "name":"Destination"}
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
                          _unifiedMapController.annotatePath(bids: ["65d88662db333f894570bad3"], sourceFloor: 0);
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: moveUser,
                        icon: const Icon(Icons.directions_walk, size: 16),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                        label: const Text('Move User'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _stopMovingUser,
                        icon: const Icon(Icons.stop, size: 16),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        label: const Text('Stop'),
                      ),
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