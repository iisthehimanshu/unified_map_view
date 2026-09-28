
import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/furniture_model.dart';

class FurnitureAPI {
  /// Hive box holding each venue's last `get-all-threed-models` response,
  /// keyed by venue name, as `{version, body}` with the raw JSON body.
  static const boxName = 'UnifiedFurnitureBox';

  /// Each venue's data version as handed in by the host, pending until the
  /// host's own versions request answers. Null means the version is unknown.
  static final Map<String, Future<String?>> _versions = {};

  /// Supplies the data version the cached 3D models for [venueName] are
  /// checked against. The host already fetches the venue's versions, so this
  /// package makes no versions request of its own.
  static void provideVersion(String venueName, Future<String?> version) {
    _versions[venueName] = version;
  }

  /// The version for [venueName], or null when none was supplied, the host's
  /// request failed, or it has not answered in time.
  static Future<String?> _versionFor(String venueName) async {
    final version = _versions[venueName];
    if (version == null) return null;
    try {
      return await version.timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  static Box? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  /// The venue's 3D models. Served from the cache when the host's version
  /// matches the one the cache was stored with; fetched otherwise, and on a
  /// failed fetch the cache is used anyway so the models still show offline.
  Future<List<FurnitureModel>> fetchFurniture(String venueName) async {
    final box = _box;
    final cached = box?.get(venueName) as Map?;
    final versionFuture = _versionFor(venueName);

    if (cached != null) {
      final version = await versionFuture;
      if (version != null && cached['version'] == version) {
        print('3D models: version unchanged ($version) — served from cache');
        return _parse(cached['body'] as String);
      }
      print('3D models: version ${cached['version']} -> $version — fetching');
    }

    final body = await _request(venueName);
    if (body == null) {
      return cached != null ? _parse(cached['body'] as String) : [];
    }
    final version = await versionFuture;
    await box?.put(venueName, {'version': version, 'body': body});
    return _parse(body);
  }

  /// The raw response body, or null when the request failed.
  Future<String?> _request(String venueName) async {
    final url = Uri.parse(
      '${AppConfig.baseUrl}/secured/get-all-threed-models?venueName=$venueName&api_key=${AppConfig.apiKey}',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return response.body;
      } else {
        print('Error fetching furniture: ${response.statusCode}');
        return null;
      }
    } catch (e, st) {
      print('Exception fetching furniture: $e\n$st');
      return null;
    }
  }

  List<FurnitureModel> _parse(String responseBody) {
    try {
      final Map<String, dynamic> body = jsonDecode(responseBody);
      final List<dynamic> data = (body['data'] as List?) ?? const [];

      // Parse per-model so a single malformed model can't throw out the
      // whole list — one bad field would otherwise leave furnitureData
      // empty and every placement unresolved.
      final models = <FurnitureModel>[];
      for (final item in data) {
        try {
          models.add(FurnitureModel.fromJson(item as Map<String, dynamic>));
        } catch (e) {
          print('Skipping malformed furniture model '
              '(${item is Map ? item['_id'] : '?'}): $e');
        }
      }
      return models;
    } catch (e) {
      print('Exception parsing furniture: $e');
      return [];
    }
  }
}
