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
        venueName: 'NationalZoologicalPark',
        initialLocation: UnifiedCameraPosition(
          mapLocation: MapLocation(latitude: 21.7679, longitude: 78.8718), // Delhi
          zoom: 3.0,
          bearing: 0.0,
          tilt: 0.0
        ),
      url: "https://maps.iwayplus.in",
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

  // var path = [
  //   {"node": 3897251, "x": 1187, "y": 1068, "lat": 17.443003846371283, "lng": 78.36624414341532, "ttsEnabled": true, "bid": "69e88519412aec622fc75536", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": true, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
  //   {"node": 3780534, "x": 1206, "y": 1036, "lat": 17.44313680329257, "lng": 78.36623342162618, "ttsEnabled": false, "bid": "69e88519412aec622fc75536", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
  //   {"node": 3780534, "x": 1206, "y": 1036, "lat": 17.443180266500633, "lng": 78.36628798157611, "ttsEnabled": false, "bid": "69e88519412aec622fc75536", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null},
  //   {"node": 3036008, "x": 872, "y": 832, "lat": 17.44309958389197 ,"lng": 78.36628466337953, "ttsEnabled": true, "bid": "69e88519412aec622fc75536", "floor": 0, "numCols": 3648, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": true, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat":17.44298967296045, "destinationLng": 78.36628052448958}
  // ];


  var path = [
    {"node": 6451550, "x": 865, "y": 1669, "lat": 28.606400436674008, "lng": 77.2429690795206, "ttsEnabled": true, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": true, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6397454, "x": 879, "y": 1655, "lat": 28.60643761045843, "lng": 77.24301210916002, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6370477, "x": 957, "y": 1648, "lat": 28.606451292201996, "lng": 77.24325471297695, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6351192, "x": 997, "y": 1643, "lat": 28.606464300509913, "lng": 77.24338055908487, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6347342, "x": 1012, "y": 1642, "lat": 28.60646523238822, "lng": 77.24342884550143, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6347357, "x": 1027, "y": 1642, "lat": 28.606466114151512, "lng": 77.24347453514714, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6370568, "x": 1048, "y": 1648, "lat": 28.606447375621116, "lng": 77.24353913054938, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6378305, "x": 1055, "y": 1650, "lat": 28.606441134089245, "lng": 77.24356036266899, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6529070, "x": 1085, "y": 1689, "lat": 28.606334695609785, "lng": 77.24365280861275, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6679836, "x": 1116, "y": 1728, "lat": 28.606226250942754, "lng": 77.24374699700815, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 6934975, "x": 1165, "y": 1794, "lat": 28.606043450412372, "lng": 77.24389697401546, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7043222, "x": 1192, "y": 1822, "lat": 28.60596339020038, "lng": 77.24397981708034, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7093479, "x": 1204, "y": 1835, "lat": 28.605927210487348, "lng": 77.24401725438209, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7101211, "x": 1206, "y": 1837, "lat": 28.605923360094383, "lng": 77.24402123861279, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7155334, "x": 1219, "y": 1851, "lat": 28.605883329988387, "lng": 77.24406266014523, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7267452, "x": 1252, "y": 1880, "lat": 28.605804047000543, "lng": 77.2441631954649, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7340901, "x": 1266, "y": 1899, "lat": 28.60574998892491, "lng": 77.24420440903877, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7510991, "x": 1296, "y": 1943, "lat": 28.605629466995612, "lng": 77.24429629428212, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7638594, "x": 1354, "y": 1976, "lat": 28.60553493030835, "lng": 77.24447575479937, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7684993, "x": 1373, "y": 1988, "lat": 28.605502610906104, "lng": 77.24453550583397, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7708195, "x": 1385, "y": 1994, "lat": 28.60548373547701, "lng": 77.2445704020987, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7820292, "x": 1397, "y": 2023, "lat": 28.6054032319564, "lng": 77.24460891379624, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 7943989, "x": 1414, "y": 2055, "lat": 28.605315259816223, "lng": 77.24465949061738, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 8117934, "x": 1434, "y": 2100, "lat": 28.605191946463833, "lng": 77.24471878886993, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 8187510, "x": 1440, "y": 2118, "lat": 28.605141068388857, "lng": 77.24473772885699, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 8264817, "x": 1447, "y": 2138, "lat": 28.605088451787026, "lng": 77.24475731603198, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 8365312, "x": 1452, "y": 2164, "lat": 28.605015190904602, "lng": 77.24477177116616, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 8504459, "x": 1459, "y": 2200, "lat": 28.604917532531317, "lng": 77.24479104017908, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 8670660, "x": 1465, "y": 2243, "lat": 28.6047985323882, "lng": 77.24480844079744, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 8867777, "x": 1467, "y": 2294, "lat": 28.604658898333895, "lng": 77.24481161091762, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9099680, "x": 1470, "y": 2354, "lat": 28.604493796778627, "lng": 77.24481619764398, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9146060, "x": 1470, "y": 2366, "lat": 28.60446148831438, "lng": 77.24481528601386, "ttsEnabled": true, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9273605, "x": 1470, "y": 2399, "lat": 28.604370508844223, "lng": 77.24481271889633, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9327714, "x": 1469, "y": 2413, "lat": 28.604333791650898, "lng": 77.24481091095205, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9327714, "x": 1469, "y": 2413, "lat": 28.60433349022019, "lng": 77.2448108961097, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9331579, "x": 1469, "y": 2414, "lat": 28.604329280677888, "lng": 77.24481068883301, "ttsEnabled": true, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9397284, "x": 1469, "y": 2431, "lat": 28.604284053184628, "lng": 77.2448099462173, "ttsEnabled": true, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9420474, "x": 1469, "y": 2437, "lat": 28.604268283685492, "lng": 77.244809687289, "ttsEnabled": true, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9486179, "x": 1469, "y": 2454, "lat": 28.604221581510785, "lng": 77.24480892045966, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9567345, "x": 1470, "y": 2475, "lat": 28.604163278795532, "lng": 77.24480946713581, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9768326, "x": 1471, "y": 2527, "lat": 28.604021104423566, "lng": 77.24481080023563, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9768326, "x": 1471, "y": 2527, "lat": 28.6040206654612, "lng": 77.24481080573798, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 9996363, "x": 1473, "y": 2586, "lat": 28.603858786314493, "lng": 77.24481283487961, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10038878, "x": 1473, "y": 2597, "lat": 28.603830619245812, "lng": 77.24481318795148, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10189616, "x": 1476, "y": 2636, "lat": 28.603723716969895, "lng": 77.24482020329262, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10235997, "x": 1477, "y": 2648, "lat": 28.603690456855517, "lng": 77.24482238595007, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10290111, "x": 1481, "y": 2662, "lat": 28.60365228130072, "lng": 77.24483295828335, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10367416, "x": 1486, "y": 2682, "lat": 28.603597307910416, "lng": 77.24484818260707, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10371281, "x": 1486, "y": 2683, "lat": 28.603594534626712, "lng": 77.2448489506399, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10436991, "x": 1491, "y": 2700, "lat": 28.603546410943977, "lng": 77.24486227800648, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10514299, "x": 1499, "y": 2720, "lat": 28.60349248533927, "lng": 77.24488547222867, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10750088, "x": 1523, "y": 2781, "lat": 28.60332229073161, "lng": 77.24495867551619, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 10974286, "x": 1551, "y": 2839, "lat": 28.603164308598508, "lng": 77.24504265036984, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11074790, "x": 1565, "y": 2865, "lat": 28.603090588623225, "lng": 77.24508485902143, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11155966, "x": 1576, "y": 2886, "lat": 28.60303176805627, "lng": 77.24511853696026, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11314451, "x": 1596, "y": 2927, "lat": 28.602919692422066, "lng": 77.24517858957694, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11322182, "x": 1597, "y": 2929, "lat": 28.602913515399408, "lng": 77.24518189936302, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11465208, "x": 1618, "y": 2966, "lat": 28.602812830123852, "lng": 77.24524484091964, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11623696, "x": 1641, "y": 3007, "lat": 28.60269743885391, "lng": 77.24531477374694, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11639159, "x": 1644, "y": 3011, "lat": 28.60268703815275, "lng": 77.24532191819434, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11735799, "x": 1659, "y": 3036, "lat": 28.602617471998766, "lng": 77.24536970456184, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11739665, "x": 1660, "y": 3037, "lat": 28.602616815533423, "lng": 77.24537015550086, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11809272, "x": 1697, "y": 3055, "lat": 28.60256453030351, "lng": 77.24548553238529, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11844068, "x": 1708, "y": 3064, "lat": 28.602540516096866, "lng": 77.24551879808917, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11882725, "x": 1715, "y": 3074, "lat": 28.602510985438187, "lng": 77.24554222243327, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11905918, "x": 1718, "y": 3080, "lat": 28.602494672514396, "lng": 77.2455493169567, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11917528, "x": 1733, "y": 3083, "lat": 28.60248653401206, "lng": 77.24559760838991, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11921409, "x": 1749, "y": 3084, "lat": 28.602482194449138, "lng": 77.24564597984693, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11929156, "x": 1766, "y": 3086, "lat": 28.60247646132551, "lng": 77.24570056202072, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11936906, "x": 1786, "y": 3088, "lat": 28.602470959658604, "lng": 77.24576202081619, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11952386, "x": 1806, "y": 3092, "lat": 28.60245912692831, "lng": 77.24582248781496, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11960142, "x": 1832, "y": 3094, "lat": 28.60245239033584, "lng": 77.24590316068821, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11967895, "x": 1855, "y": 3096, "lat": 28.602443768265672, "lng": 77.24597542854991, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11991103, "x": 1873, "y": 3102, "lat": 28.602428454544864, "lng": 77.24603062265561, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11994986, "x": 1891, "y": 3103, "lat": 28.602424656866873, "lng": 77.24608931796399, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11991135, "x": 1905, "y": 3102, "lat": 28.602425131701125, "lng": 77.2461302890353, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11983419, "x": 1919, "y": 3100, "lat": 28.60243033108388, "lng": 77.2461756359479, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11971846, "x": 1941, "y": 3097, "lat": 28.602438921272977, "lng": 77.24624568010876, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11956397, "x": 1952, "y": 3093, "lat": 28.602448769493446, "lng": 77.24627815384258, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11937086, "x": 1966, "y": 3088, "lat": 28.602461786710435, "lng": 77.24632107709363, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11894597, "x": 1992, "y": 3077, "lat": 28.602490681985785, "lng": 77.24640489408381, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 11983508, "x": 2008, "y": 3100, "lat": 28.602425777140468, "lng": 77.2464519290634, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 12010564, "x": 2009, "y": 3107, "lat": 28.602406977524623, "lng": 77.24645700169677, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 12041486, "x": 2011, "y": 3115, "lat": 28.60238488155629, "lng": 77.24646277806383, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 12068545, "x": 2015, "y": 3122, "lat": 28.60236533524295, "lng": 77.24647374784385, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 12095604, "x": 2019, "y": 3129, "lat": 28.602347285290023, "lng": 77.24648699320167, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 12130401, "x": 2031, "y": 3138, "lat": 28.60232042562734, "lng": 77.24652212095143, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 12192269, "x": 2059, "y": 3154, "lat": 28.602274837046313, "lng": 77.24661014355684, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 12188438, "x": 2093, "y": 3153, "lat": 28.602278228438223, "lng": 77.24671542068359, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 12258039, "x": 2124, "y": 3171, "lat": 28.602227152664128, "lng": 77.24681139494231, "ttsEnabled": false, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": false, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": null, "destinationLng": null},
    {"node": 12281241, "x": 2136, "y": 3177, "lat": 28.60221003546249, "lng": 77.24684726208898, "ttsEnabled": true, "bid": "685bcd44a640e4b04f5b9d1e", "floor": 0, "numCols": 3865, "imaginedCell": false, "imaginedIndex": null, "masterGraph": true, "position": null, "isSource": false, "isDestination": true, "isFloorConnection": false, "connectorType": null, "color": null, "destinationLat": 28.60248946742729, "destinationLng": 77.24701493139764}
  ];

  List<List<Map<String, dynamic>>> createMultiPointPath() {
    return [
      path.sublist(0, 31),
      path.sublist(30, 88),
      path.sublist(87, path.length),
    ];
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
                          _unifiedMapController.addMultiPointPath(paths: createMultiPointPath());
                          _unifiedMapController.annotateMultiPointPath(bids: ["685bcd44a640e4b04f5b9d1e"], sourceFloor: 0);
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