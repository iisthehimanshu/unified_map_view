import 'package:hive/hive.dart';
import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';

class GlobalGeoJSONVenueStorageService{
  static const String _boxName = 'GlobalGeoJSONVenueAPIModelFile';
  Box<GlobalGeoJSONVenueAPIModel>? _globalGeoJsonBox;

  GlobalGeoJSONVenueStorageService._(); // private constructor

  static Future<GlobalGeoJSONVenueStorageService> create() async {
    final service = GlobalGeoJSONVenueStorageService._();
    await service.init();
    return service;
  }

  Future<void> init() async {
    _globalGeoJsonBox =
    await Hive.openBox<GlobalGeoJSONVenueAPIModel>(_boxName);
  }

  Box<GlobalGeoJSONVenueAPIModel> get _getGlobalGeoJsonBox {
    if (_globalGeoJsonBox == null || !_globalGeoJsonBox!.isOpen) {
      throw Exception('UserStorageService not initialized. Call init() first.');
    }
    return _globalGeoJsonBox!;
  }

  Future<void> saveGeoData(GlobalGeoJSONVenueAPIModel user,String uniqueId) async {
    print("saveGeoData ${getGeoData(uniqueId)}");
    await _globalGeoJsonBox?.put(uniqueId, user);

  }

  bool? contiansID(String uniqueId){
    return _globalGeoJsonBox?.containsKey(uniqueId);
  }

  GlobalGeoJSONVenueAPIModel? getGeoData(String id) {
    return _globalGeoJsonBox?.get(id);
  }

  Future<void> deleteGeoData(String id) async {
    await _globalGeoJsonBox?.delete(id);
  }

  Future<void> clearAll() async {
    await _globalGeoJsonBox?.clear();
  }

  /// Close the box
  Future<void> close() async {
    await _globalGeoJsonBox?.close();
  }
}