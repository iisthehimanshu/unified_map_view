import 'dart:convert';

import 'Location.dart';

class Cell{
  int node;
  int x;
  int y;
  double lat;
  double lng;
  final Function(double angle, {int? currPointer,int? totalCells})? move;
  bool ttsEnabled;
  String? bid;
  int floor;
  int numCols;
  bool imaginedCell;
  int? imaginedIndex;
  Location? position;
  bool masterGraph;

  Cell(this.node, this.x, this.y, this.move, this.lat, this.lng,this.bid, this.floor, this.numCols, {this.ttsEnabled = true, this.imaginedCell = false, this.imaginedIndex, this.position, this.masterGraph = false});

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
    );
  }


  @override
  String toString() => jsonEncode(toJson());
}