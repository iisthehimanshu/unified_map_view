import 'package:unified_map_view/src/models/map_location.dart';

class CameraBound{
  final MapLocation southwest;
  final MapLocation northeast;

  CameraBound({required this.southwest, required this.northeast});

  @override
  String toString() {
    return 'CameraBound{southwest: $southwest, northeast: $northeast}';
  }
}