import 'package:unified_map_view/src/apimodels/BuildingData.dart';
import 'package:unified_map_view/src/apimodels/GlobalAppGeoJsonDataModel.dart';

import '../../unified_map_view.dart';
import '../utils/renderingUtilities.dart';

class VenueData{
  VenueData._internal(this.venueName, this.json, this.buildingData) {
    venueLatLng = MapLocation(latitude: buildingData.buildings!.first.coordinates.first, longitude: buildingData.buildings!.first.coordinates.last);
    // The venue response is parsed exactly once. Re-parsing it per call was
    // walking every feature of every floor (and doing a jsonEncode/jsonDecode
    // round-trip per feature's properties), which froze the UI thread when a
    // lookup happened inside a widget build — see [getFloorRenderLevel].
    _model = GlobalAppGeoJsonDataModel.fromJson(json);
    _buildFloorConfigIndex();
    extractBuildingWiseData(json);
    findBuildingCenters();
  }

  // Singleton instance
  static VenueData? _instance;

  // Public factory constructor
  factory VenueData(String venueName, Map<String, dynamic> json, BuildingData buildingData) {
    _instance = VenueData._internal(venueName, json, buildingData);
    return _instance!;
  }
  static VenueData? get instance => _instance;

  String venueName;
  MapLocation venueLatLng = MapLocation(latitude: 21.7679, longitude: 78.8718);
  Map<String, dynamic> json;

  Map<String,int> _selectedFloor = {};
  Map<String,List<int>> _availableFloors = {};
  BuildingData buildingData;
  Map<String, MapLocation> buildingCenters = {};

  /// The venue response parsed once, at construction. Every lookup below reads
  /// from this instead of calling [GlobalAppGeoJsonDataModel.fromJson] again.
  late final GlobalAppGeoJsonDataModel _model;

  /// buildingId -> (floorRenderLevel -> floorNumber), from `floorConfigs`.
  /// The value stays nullable so a config with a null `floorNumber` still
  /// occupies its slot and falls back to the requested floor, exactly as the
  /// previous first-match linear scan did.
  final Map<String, Map<int, int?>> _renderLevelToFloorNumber = {};

  /// floorNumber -> initialOrientation, from `floorConfigs`.
  final Map<int, double> _floorOrientations = {};

  /// Flattens `floorConfigs` into the two lookup maps above. Both keep the
  /// first matching config for a key, preserving the first-match-wins
  /// behaviour of the linear scans these replace.
  void _buildFloorConfigIndex() {
    final configs = _model.floorConfigs;
    if (configs == null) return;
    for (final f in configs) {
      final buildingId = f.buildingId;
      final renderLevel = f.floorRenderLevel;
      if (buildingId != null && renderLevel != null) {
        _renderLevelToFloorNumber
            .putIfAbsent(buildingId, () => {})
            .putIfAbsent(renderLevel, () => f.floorNumber);
      }

      final floorNumber = f.floorNumber;
      if (floorNumber != null) {
        _floorOrientations.putIfAbsent(
            floorNumber, () => f.initialOrientation ?? 0.0);
      }
    }
  }

  Map<String, List<int>> get availableFloors => _availableFloors;
  Map<String, int> get selectedFloor => _selectedFloor;

  String? buildingNameForId(String? buildingId) {
    if (buildingId == null) return null;
    final buildings = buildingData.buildings;
    if (buildings == null) return null;
    for (final building in buildings) {
      if (building.id == buildingId) return building.buildingName;
    }
    return null;
  }

  /// [json] is kept for API compatibility but is no longer re-parsed here —
  /// it is the same response already parsed into [_model] at construction.
  void extractBuildingWiseData(Map<String, dynamic> json){
    GlobalAppGeoJsonDataModel globalAppGeoJsonDataModel = _model;
    _availableFloors.clear();
    _selectedFloor.clear();

    // Temporary map to track unique floors per building
    Map<String, Set<int>> buildingFloorsMap = {};

    // Iterate through all features
    for (var feature in globalAppGeoJsonDataModel.data!) {
      // Get building ID
      String? buildingId = feature.buildingID;

      // Get floor from properties
      int? floor = feature.properties?["floor"];

      // Skip if building ID or floor is null
      if (buildingId == null || floor == null) {
        continue;
      }

      // Add floor to the building's set (automatically handles duplicates)
      if (!buildingFloorsMap.containsKey(buildingId)) {
        buildingFloorsMap[buildingId] = <int>{};
      }
      buildingFloorsMap[buildingId]!.add(floor);
    }

    // Convert sets to sorted lists and populate availableFloors
    buildingFloorsMap.forEach((buildingId, floorsSet) {
      List<int> sortedFloors = floorsSet.toList()..sort();
      _availableFloors[buildingId] = sortedFloors;

      // Set default selected floor (lowest floor or 0 if available)
      if (sortedFloors.isNotEmpty) {
        // Prefer ground floor (0) if available, otherwise use the lowest floor
        _selectedFloor[buildingId] = sortedFloors.contains(0)
            ? 0
            : sortedFloors.first;
      }
    });
  }

  int? getSelectedFloor(String buildingId) {
    return _selectedFloor[buildingId];
  }

  // Helper method to set selected floor for a building
  void setSelectedFloor(String buildingId, int floor) {
    if (availableFloors[buildingId]?.contains(floor) ?? false) {
      _selectedFloor[buildingId] = floor;
    }
  }

  List<GeoJsonFeature> _getFeaturesForBuildingAndFloor(
      String buildingId,
      int floor,
      ) {
    if (_model.data == null) return [];

    final filteredData = _model.data!.where((feature) {
      final name = feature.properties?["name"];
      final lowerName = name?.toLowerCase() ?? '';

      if (feature.buildingID != buildingId ||
          feature.properties?["floor"] != floor) {
        return false;
      }

      // Features carrying a "3dRef" part list (rendered as extruded 3D
      // furniture) often have no name — e.g. waypoint points hosting a 3d
      // object — so they bypass the name-based filtering below.
      if (feature.properties?['3dRef'] != null) return true;

      return name != null &&
          !lowerName.contains('non walkable') &&
          !lowerName.contains('iw');
    }).toList();

    for (var data in filteredData) {
      if(data.geometry?.type == "Point"){
        String? polyId = data.properties?["polyId"];
        final associatedPolygons = data.properties?['associatedPolygons'];
        if (associatedPolygons is List && associatedPolygons.isNotEmpty) {
          polyId = associatedPolygons.first;
        }
        if(polyId != null){
          var polygons = filteredData.where((element)=>element.id == polyId).toList();
          if(polygons.isNotEmpty){
            GlobalAppGeoData polygon = polygons.first;
            List<MapLocation>? polygonPoints = polygon.geometry?.coordinates?.first.map((point)=>MapLocation(latitude: point[1], longitude: point[1])).toList();
            if(polygonPoints != null){
              // data.properties?['bearing'] = RenderingUtilities().findBestFitRectangleBearing(polygonPoints).bearing - 108;
            }
          }
        }
      }
    }

    return filteredData.map((f) {
      final featureJson = f.toJson();
      // toJson() hands back the cached model's own properties map, and the
      // render pipeline mutates properties (it clears 'bearing'). Copy it so a
      // floor render can't write into the venue data — re-parsing per call used
      // to give each caller a fresh map.
      final props = featureJson['properties'];
      if (props is Map<String, dynamic>) {
        featureJson['properties'] = Map<String, dynamic>.from(props);
      }
      return GeoJsonFeature.fromJson(featureJson);
    }).toList();
  }

  double getFloorOrientation(int floor) {
    return _floorOrientations[floor] ?? 0.0;
  }

  /// Maps an actual [floor] level to the level number that should be shown to
  /// the user, using `floorRenderLevel` from the matching floor config. Falls
  /// back to [floor] itself when there is no config or no render level.
  ///
  /// Called from widget builds (the floor speed dial rebuilds on every
  /// controller notification), so this must stay a plain map lookup.
  int getFloorRenderLevel(int floor, String bid) {
    return _renderLevelToFloorNumber[bid]?[floor] ?? floor;
  }

  List<GeoJsonFeature> setBuildingFloor({required String buildingId, required int floor}){
    _selectedFloor[buildingId] = floor;
    return _getFeaturesForBuildingAndFloor(buildingId, floor);
  }

  /// The id of the campus "building" from the building-by-venue data. The
  /// campus carries the base map (roads, greenery, overall outline) and must
  /// never be floor-swapped, so callers skip it.
  String? get campusBuildingId {
    final campus = buildingData.campus;
    return campus is Campus ? campus.id : null;
  }

  /// Returns the boundary outline feature(s) to show for [buildingId] when its
  /// tapped floor has no walkable content, so the building's footprint stays
  /// visible. Prefers GeoJSON `Boundary` polygons on the highest floor; if the
  /// venue has none, falls back to the building footprint from the
  /// building-by-venue data.
  List<GeoJsonFeature> highestFloorBoundaryFeatures(String buildingId) {
    final model = GlobalAppGeoJsonDataModel.fromJson(json);

    final boundaries = (model.data ?? []).where((feature) =>
        feature.buildingID == buildingId &&
        feature.properties?["type"] == "Boundary" &&
        feature.properties?["floor"] is int).toList();

    if (boundaries.isNotEmpty) {
      final int maxFloor = boundaries
          .map((feature) => feature.properties!["floor"] as int)
          .reduce((a, b) => a > b ? a : b);

      return boundaries
          .where((feature) => feature.properties!["floor"] == maxFloor)
          .map((feature) => GeoJsonFeature.fromJson(feature.toJson()))
          .toList();
    }

    final footprint = _buildingFootprintFeature(buildingId);
    return footprint == null ? [] : [footprint];
  }

  /// Builds a `Boundary`-typed polygon from the building-by-venue footprint
  /// coordinates for [buildingId]. Boundary coords come as [lat, lng]; GeoJSON
  /// geometry needs [lng, lat] with a closed ring.
  GeoJsonFeature? _buildingFootprintFeature(String buildingId) {
    final buildings = buildingData.buildings;
    if (buildings == null) return null;

    List<List<double>>? boundary;
    for (final building in buildings) {
      if (building.id == buildingId) {
        boundary = building.boundary;
        break;
      }
    }
    if (boundary == null || boundary.length < 3) return null;

    final ring = boundary.map((point) => [point[1], point[0]]).toList();
    if (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
      ring.add(ring.first);
    }

    final floors = _availableFloors[buildingId];
    final int? highestFloor =
        (floors != null && floors.isNotEmpty) ? floors.last : null;

    return GeoJsonFeature(
      buildingId: buildingId,
      id: 'footprint_$buildingId',
      geometry: GeoJsonGeometry(
        type: GeoJsonGeometryType.polygon,
        coordinates: [ring],
      ),
      properties: {
        'type': 'Boundary',
        if (highestFloor != null) 'floor': highestFloor,
      },
    );
  }

  GeoJsonFeature? findLocation(String polyId){
    GlobalAppGeoJsonDataModel model = GlobalAppGeoJsonDataModel.fromJson(json);
    if (model.data == null) return null;
    print("model.data $polyId ${model.data}");
    final feature = model.data!.firstWhere((feature)=>(feature.id == polyId || feature.properties?["polyId"] == polyId));

    return GeoJsonFeature.fromJson(feature.toJson());
  }

  void findBuildingCenters() {
    buildingCenters.clear();

    final List<Building>? buildings = buildingData.buildings;
    if (buildings == null || buildings.isEmpty) return;

    for (final building in buildings) {
      // coordinates = [lat, lng]
      if (building.coordinates.length < 2) continue;

      final double lat = building.coordinates[0];
      final double lng = building.coordinates[1];

      // Use building ID as key (recommended)
      buildingCenters[building.id] = MapLocation(latitude: lat, longitude: lng);
    }
  }

}