import 'dart:convert';

import 'Location.dart';

class Cell{
  int node;
  int x;
  int y;
  double lat;
  double lng;
  final Function(double angle, {int? currPointer,int? totalCells})? move;
  String? color;
  bool ttsEnabled;
  String? bid;
  int floor;
  int numCols;
  bool imaginedCell;
  int? imaginedIndex;
  Location? position;
  bool masterGraph;
  bool isSource;
  bool isDestination;
  bool isFloorConnection;
  String? connectorType;
  double? destinationLat;
  double? destinationLng;
  String? name;

  Cell(this.node, this.x, this.y, this.move, this.lat, this.lng,this.bid, this.floor, this.numCols, {this.ttsEnabled = true, this.imaginedCell = false, this.imaginedIndex, this.position, this.masterGraph = false, this.isSource = false, this.isDestination = false, this.isFloorConnection = false, this.connectorType, this.color, this.destinationLat, this.destinationLng, this.name});

  Map<String, dynamic> toJson() => {
    'node': node,
    'x': x,
    'y': y,
    'lat': lat,
    'lng': lng,
    'ttsEnabled': ttsEnabled,
    'bid': bid,
    'floor': floor,
    'numCols': numCols,
    'imaginedCell': imaginedCell,
    'imaginedIndex': imaginedIndex,
    'masterGraph': masterGraph,
    'position': position != null
        ? {
      'latitude': position!.latitude,
      'longitude': position!.longitude,
      'accuracy': position!.accuracy,
      'bearing': position!.bearing,
      'timeStamp': position!.timeStamp.toIso8601String(),
    }
        : null,
    'isSource': isSource,
    'isDestination': isDestination,
    'isFloorConnection': isFloorConnection,
    'connectorType': connectorType,
    'color': color,
    'destinationLat':destinationLat,
    'destinationLng':destinationLng,
    'name':name
  };


  factory Cell.fromJson(
      Map<String, dynamic> json) {
    Location? position;

    if (json['position'] != null) {
      position = Location(
        latitude: json['position']['latitude'],
        longitude: json['position']['longitude'],
        accuracy: json['position']['accuracy'],
        bearing: json['position']['bearing'],
        timeStamp: DateTime.parse(json['position']['timeStamp']),
      );
    }

    return Cell(
      json['node'],
      json['x'],
      json['y'],
      null,
      json['lat'],
      json['lng'],
      json['bid'],
      json['floor'],
      json['numCols'],
      ttsEnabled: json['ttsEnabled'] ?? true,
      imaginedCell: json['imaginedCell'] ?? false,
      imaginedIndex: json['imaginedIndex'],
      position: position,
      masterGraph: json['masterGraph'] ?? false,
      isSource: json['isSource'],
      isDestination: json['isDestination'],
      isFloorConnection: json['isFloorConnection'],
        connectorType: json['connectorType'],
      color: json['color'],
      destinationLat: json['destinationLat'],
      destinationLng: json['destinationLng'],
      name: json['name']
    );
  }


  @override
  String toString() => jsonEncode(toJson());
}