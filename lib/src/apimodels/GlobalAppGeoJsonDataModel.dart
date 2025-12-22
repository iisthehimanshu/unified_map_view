

class GlobalAppGeoJsonDataModel {
  String? message;
  List<GlobalAppGeoData>? data;

  GlobalAppGeoJsonDataModel({this.message, this.data});

  GlobalAppGeoJsonDataModel.fromJson(Map<dynamic, dynamic> json) {
    message = json['message'];
    if (json['data'] != null) {
      data = <GlobalAppGeoData>[];
      json['data'].forEach((v) { data!.add(new GlobalAppGeoData.fromJson(v)); });
    }
  }

  Map<dynamic, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['message'] = this.message;
    if (this.data != null) {
      data['data'] = this.data!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

class GlobalAppGeoData {
  GLobalAppGeoProperties? properties;
  String? sId;
  String? id;
  String? buildingID;
  GlobalAppGeoGeometry? geometry;
  List<String>? associatedPolygons;
  List<String>? associatedPoints;
  String? type;
  String? createdBy;
  String? updatedBy;
  int? iV;

  GlobalAppGeoData({this.properties, this.sId, this.id, this.buildingID, this.geometry, this.associatedPolygons, this.associatedPoints, this.type, this.createdBy, this.updatedBy, this.iV});

  GlobalAppGeoData.fromJson(Map<dynamic, dynamic> json) {
    if(json['properties'] != null){
      properties = new GLobalAppGeoProperties.fromJson(json['properties']);
    }else{
      print("json['properties'] is null");
    }
    sId = json['_id'];
    id = json['id'];
    buildingID = json['building_ID'];
    geometry = json['geometry'] != null ? new GlobalAppGeoGeometry.fromJson(json['geometry']) : null;
    associatedPolygons = (json['associatedPolygons'] as List?)?.map((e) => e.toString()).toList();
    associatedPoints = (json['associatedPoints'] as List?)?.map((e) => e.toString()).toList();
    type = json['type'];
    createdBy = json['createdBy'];
    updatedBy = json['updatedBy'];
    iV = json['__v'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    if (this.properties != null) {
      data['properties'] = this.properties!.toJson();
    }
    data['_id'] = this.sId;
    data['id'] = this.id;
    data['building_ID'] = this.buildingID;
    if (this.geometry != null) {
      data['geometry'] = this.geometry!.toJson();
    }
    data['associatedPolygons'] = this.associatedPolygons;
    data['associatedPoints'] = this.associatedPoints;
    data['type'] = this.type;
    data['createdBy'] = this.createdBy;
    data['updatedBy'] = this.updatedBy;
    data['__v'] = this.iV;
    return data;
  }
}

class GLobalAppGeoProperties {
  String? number;
  String? lineCategory;
  List<double>? centroid;
  bool? visible;
  int? level;
  String? name;
  String? type;
  String? fillColor;
  String? strokeColor;
  String? direction;
  String? pathNature;
  String? pathType;
  String? accessibility;
  String? gpsAvailibility;
  List<String>? associatedPoints;
  String? buildingName;
  int? floor;
  String? landmarkId;
  bool? global;
  String? polygonType;
  List<String>? associatedPolygons;
  String? objectFile;
  String? fillOpacity;
  String? height;
  String? strokeOpacity;
  String? strokeWidth;
  String? imageFile;
  String? noJuctionId;
  String? nodeId;
  String? visibilityType;
  double? angle;
  double? elevation;
  double? scale;

  GLobalAppGeoProperties({this.number, this.lineCategory, this.centroid, this.visible, this.level, this.name, this.type, this.fillColor, this.strokeColor, this.direction, this.pathNature, this.pathType, this.accessibility, this.gpsAvailibility, this.associatedPoints, this.buildingName, this.floor, this.landmarkId, this.global, this.polygonType, this.associatedPolygons, this.objectFile, this.fillOpacity, this.height, this.strokeOpacity, this.strokeWidth, this.imageFile, this.noJuctionId, this.nodeId, this.visibilityType});

  GLobalAppGeoProperties.fromJson(Map<dynamic, dynamic> json) {
    number = json['number'];
    lineCategory = json['lineCategory'];
    centroid = (json['centroid'] is List) ? (json['centroid'] as List).map((e) => (e as num).toDouble()).toList() : null;
    visible = json['visible'];
    level = json['level'];
    name = json['name'];
    type = json['type'];
    fillColor = json['fillColor'];
    strokeColor = json['strokeColor'];
    direction = json['direction'];
    pathNature = json['pathNature'];
    pathType = json['pathType'];
    accessibility = json['accessibility'];
    gpsAvailibility = json['gpsAvailibility'];
    buildingName = json['buildingName'];
    floor = json['floor'];
    landmarkId = json['landmarkId'];
    global = json['global'];
    polygonType = json['polygonType'];
    associatedPolygons = (json['associatedPolygons'] as List?)?.map((e) => e.toString()).toList();
    associatedPoints = (json['associatedPoints'] as List?)?.map((e) => e.toString()).toList();
    objectFile = json['objectFile'];
    fillOpacity = json['fillOpacity'];
    if(json['height'].runtimeType == double){
      height = json['height'].toString();
    }else{
      height = json['height'];
    }
    strokeOpacity = json['strokeOpacity'];
    strokeWidth = json['strokeWidth'];
    imageFile = json['imageFile'];
    noJuctionId = json['noJuctionId'];
    nodeId = json['nodeId'];
    visibilityType = json['visibilityType'];
    if(json['angle'].runtimeType == int){ //Mishor issue
      angle = double.parse(json['angle'].toString());
    }else{
      angle = json['angle'];
    }

    if(json['elevation'] != null){
      elevation = double.parse(json['elevation'].toString());
    }else{
      elevation = json['elevation'];
    }
    if(json['scale'] != null){
      scale = double.parse(json['scale'].toString());
    }else {
      scale = json['scale'];
    }
  }

  Map<dynamic, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['number'] = this.number;
    data['lineCategory'] = this.lineCategory;
    data['centroid'] = this.centroid;
    data['visible'] = this.visible;
    data['level'] = this.level;
    data['name'] = this.name;
    data['type'] = this.type;
    data['fillColor'] = this.fillColor;
    data['strokeColor'] = this.strokeColor;
    data['direction'] = this.direction;
    data['pathNature'] = this.pathNature;
    data['pathType'] = this.pathType;
    data['accessibility'] = this.accessibility;
    data['gpsAvailibility'] = this.gpsAvailibility;
    data['associatedPoints'] = this.associatedPoints;
    data['buildingName'] = this.buildingName;
    data['floor'] = this.floor;
    data['landmarkId'] = this.landmarkId;
    data['global'] = this.global;
    data['polygonType'] = this.polygonType;
    data['associatedPolygons'] = this.associatedPolygons;
    data['objectFile'] = this.objectFile;
    data['fillOpacity'] = this.fillOpacity;
    data['height'] = this.height;
    data['strokeOpacity'] = this.strokeOpacity;
    data['strokeWidth'] = this.strokeWidth;
    data['imageFile'] = this.imageFile;
    data['noJuctionId'] = this.noJuctionId;
    data['nodeId'] = this.nodeId;
    data['visibilityType'] = this.visibilityType;
    data['angle'] = this.angle;
    data['elevation'] = this.angle;
    data['scale'] = this.angle;
    return data;
  }
}

class GlobalAppGeoGeometry {
  List<List<dynamic>>? coordinates;
  String? type;
  List<List<dynamic>>? coordinatesLocal;

  GlobalAppGeoGeometry({
    this.coordinates,
    this.type,
    this.coordinatesLocal,
  });

  GlobalAppGeoGeometry.fromJson(Map<dynamic, dynamic> json) {
    type = json['type'];

    if (json['coordinates'] != null) {
      final coords = json['coordinates'];

      if (coords is List) {
        if (coords.isNotEmpty && coords.first is List) {
          // e.g. [[lon, lat], [lon, lat]]
          coordinates = coords
              .map((v) => v is List ? v.map((e) => e).toList() : [v])
              .toList();
        } else {
          // e.g. [lon, lat] (Point)
          coordinates = [coords.map((e) => e).toList()];
        }
      }
    }

    if (json['coordinatesLocal'] != null) {
      final coordsLocal = json['coordinatesLocal'];

      if (coordsLocal is List) {
        if (coordsLocal.isNotEmpty && coordsLocal.first is List) {
          coordinatesLocal = coordsLocal
              .map((v) => v is List ? v.map((e) => e).toList() : [v])
              .toList();
        } else {
          coordinatesLocal = [coordsLocal.map((e) => e).toList()];
        }
      }
    }
  }

  Map<dynamic, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (coordinates != null) {
      data['coordinates'] = coordinates;
    }
    data['type'] = type;
    if (coordinatesLocal != null) {
      data['coordinatesLocal'] = coordinatesLocal;
    }
    return data;
  }
}


// Method to convert QueriedFeature to GlobalAppGeoData
GlobalAppGeoData? convertQueriedFeatureToGeoData(dynamic queriedFeature) {
  try {
    if (queriedFeature == null) return null;

    // Get the feature map
    Map<dynamic, dynamic>? featureMap;

    if (queriedFeature is Map) {
      featureMap = queriedFeature;
    } else if (queriedFeature.feature is Map) {
      featureMap = queriedFeature.feature as Map<dynamic, dynamic>;
    } else {
      return null;
    }

    // Create GlobalAppGeoData from the feature map
    return GlobalAppGeoData.fromJson(featureMap);

  } catch (e) {
    print("Error converting QueriedFeature: $e");
    return null;
  }
}

// Method to extract just the properties
GLobalAppGeoProperties? convertQueriedFeatureToProperties(dynamic queriedFeature) {
  try {
    if (queriedFeature == null) return null;

    Map<dynamic, dynamic>? featureMap;

    if (queriedFeature is Map) {
      featureMap = queriedFeature;
    } else if (queriedFeature.feature is Map) {
      featureMap = queriedFeature.feature as Map<dynamic, dynamic>;
    } else {
      return null;
    }

    // Extract the properties field
    final propertiesMap = featureMap['properties'];
    if (propertiesMap == null) return null;

    // For the stairs example, properties is nested inside properties
    // Check if there's a nested 'properties' field
    if (propertiesMap is Map && propertiesMap.containsKey('properties')) {
      return GLobalAppGeoProperties.fromJson(propertiesMap['properties']);
    }

    // Otherwise use the properties directly
    return GLobalAppGeoProperties.fromJson(propertiesMap);

  } catch (e) {
    print("Error converting properties: $e");
    return null;
  }
}
GlobalAppGeoGeometry? convertQueriedFeatureToGeometry(dynamic queriedFeature) {
  try {
    if (queriedFeature == null) return null;

    Map<dynamic, dynamic>? featureMap;

    if (queriedFeature is Map) {
      featureMap = queriedFeature;
    } else if (queriedFeature.feature is Map) {
      featureMap = queriedFeature.feature as Map<dynamic, dynamic>;
    } else {
      return null;
    }

    // Extract geometry
    final geometryMap = featureMap['geometry'];
    if (geometryMap == null || geometryMap is! Map) return null;

    // Convert to model
    return GlobalAppGeoGeometry.fromJson(
      Map<String, dynamic>.from(geometryMap),
    );

  } catch (e) {
    print("Error converting geometry: $e");
    return null;
  }
}
