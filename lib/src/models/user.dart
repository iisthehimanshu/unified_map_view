import 'package:unified_map_view/src/models/map_location.dart';

class User{
  MapLocation _location;
  final String _bid;
  final int _floor;

  MapLocation get location => _location;

  set location(MapLocation value) {
    _location = value;
  }

  User(this._location, this._bid, this._floor);

  String get bid => _bid;

  int get floor => _floor;

  @override
  String toString() {
    return 'User{_location: ${_location.toString()}, _bid: $_bid, _floor: $_floor}';
  }


}