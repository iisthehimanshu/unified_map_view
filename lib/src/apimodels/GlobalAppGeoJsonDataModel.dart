

import 'dart:convert';

class GlobalAppGeoJsonDataModel {
  String? message;
  List<GlobalAppGeoData>? data;
  List<FloorConfigs>? floorConfigs;

  GlobalAppGeoJsonDataModel({this.message, this.data});

  GlobalAppGeoJsonDataModel.fromJson(Map<dynamic, dynamic> json) {
    message = json['message'];
    if (json['data'] != null) {
      data = <GlobalAppGeoData>[];
      json['data'].forEach((v) { data!.add(new GlobalAppGeoData.fromJson(v)); });
    }
    if (json['floorConfigs'] != null) {
      floorConfigs = <FloorConfigs>[];
      json['floorConfigs'].forEach((v) {
        floorConfigs!.add(new FloorConfigs.fromJson(v));
      });
    }
  }

  Map<dynamic, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['message'] = this.message;
    if (this.data != null) {
      data['data'] = this.data!.map((v) => v.toJson()).toList();
    }
    if (this.floorConfigs != null) {
      data['floorConfigs'] = this.floorConfigs!.map((v) => v.toJson()).toList();
    }
    return data;
  }
}

class FloorConfigs {
  String? sId;
  int? floorNumber;
  String? floorName;
  double? initialOrientation;

  FloorConfigs(
      {this.sId, this.floorNumber, this.floorName, this.initialOrientation});

  FloorConfigs.fromJson(Map<dynamic, dynamic> json) {
    sId = json['_id'];
    floorNumber = json['floorNumber'];
    floorName = json['floorName'];
    initialOrientation = json['initialOrientation'];
  }

  Map<dynamic, dynamic> toJson() {
    final Map<dynamic, dynamic> data = new Map<dynamic, dynamic>();
    data['_id'] = this.sId;
    data['floorNumber'] = this.floorNumber;
    data['floorName'] = this.floorName;
    data['initialOrientation'] = this.initialOrientation;
    return data;
  }
}

class GlobalAppGeoData {
  Map<String, dynamic>? properties;
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
      properties = Map<String, dynamic>.from(jsonDecode(jsonEncode(json['properties'])));
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
      data['properties'] = this.properties!;
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
