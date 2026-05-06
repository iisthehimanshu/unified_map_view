import 'package:hive/hive.dart';
import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';

class GlobalGeoJSONVenueStorageService {
  static const String _boxName = 'GlobalGeoJSONVenueAPIModelFile';

  /// Singleton instance
  static final GlobalGeoJSONVenueStorageService _instance =
      GlobalGeoJSONVenueStorageService._internal();

  factory GlobalGeoJSONVenueStorageService() {
    return _instance;
  }

  GlobalGeoJSONVenueStorageService._internal();

  Box<GlobalGeoJSONVenueAPIModel>? _globalGeoJsonBox;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized &&
        _globalGeoJsonBox != null &&
        _globalGeoJsonBox!.isOpen) {
      return;
    }

    _globalGeoJsonBox = await Hive.openBox<GlobalGeoJSONVenueAPIModel>(
      _boxName,

      /// helps reclaim old stale data
      compactionStrategy: (
        entries,
        deletedEntries,
      ) {
        return deletedEntries > 0;
      },
    );

    _initialized = true;

    print(
      "GlobalGeoJSON box initialized once",
    );
  }

  Box<GlobalGeoJSONVenueAPIModel> get _getGlobalGeoJsonBox {
    if (_globalGeoJsonBox == null || !_globalGeoJsonBox!.isOpen) {
      throw Exception(
        'StorageService not initialized',
      );
    }

    return _globalGeoJsonBox!;
  }

  Future<void> saveGeoData(
      GlobalGeoJSONVenueAPIModel user,
      String uniqueId,
      ) async {

    final box =
        _getGlobalGeoJsonBox;

    if (box.containsKey(
      uniqueId,
    )) {

      await box.delete(
        uniqueId,
      );
    }

    await box.put(
      uniqueId,
      user,
    );

    await box.compact();

    print(
      "GeoJSON saved + compacted",
    );
  }

  bool containsID(
    String uniqueId,
  ) {
    return _getGlobalGeoJsonBox.containsKey(
      uniqueId,
    );
  }

  GlobalGeoJSONVenueAPIModel? getGeoData(
    String id,
  ) {
    return _getGlobalGeoJsonBox.get(
      id,
    );
  }

  Future<void> deleteGeoData(
    String id,
  ) async {
    await _getGlobalGeoJsonBox.delete(
      id,
    );
  }

  Future<void> clearAll() async {
    await _getGlobalGeoJsonBox.clear();
  }

  Future<void> close() async {
    await _globalGeoJsonBox?.close();

    _initialized = false;
  }
}
