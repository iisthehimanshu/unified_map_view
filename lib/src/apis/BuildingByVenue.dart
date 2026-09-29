import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../apimodels/BuildingData.dart';
import '../config.dart';
import 'package:http/http.dart' as http;
import '../database/box/BuildingByVenueAPIBOX.dart';
import '../database/model/BuildingByVenueAPIModel.dart';

class BuildingByVenue {
  final String baseUrl = "${AppConfig.baseUrl}/secured/building/get/venue?api_key=${AppConfig.apiKey}";

  /// One load per venue per session, shared by every caller — the same shape
  /// [GlobalGeoJSONVenueAPI] already uses.
  ///
  /// `initialize` and each map's annotation controller (`renderVenue`) both ask
  /// for the venue, and each used to start its own live fetch, so
  /// `building/get/venue` went out twice on a single launch. Sharing the load
  /// keeps the "prefer a live fetch when online" behaviour below intact — there
  /// is still exactly one live fetch per session, so a server-side data fix is
  /// still picked up on the next launch — it just stops the second caller
  /// duplicating the first.
  ///
  /// Holds the raw response, so a host can reuse the very same load through
  /// [fetchResponse] instead of posting the identical request itself.
  static final Map<String, Future<Map<String, dynamic>>> _loads = {};

  /// Hands the package a venue response the host already has, so no request is
  /// made for it. It is not written to the cache — the host owns that.
  static void provide(String venueName, Map<String, dynamic> data) {
    _loads[venueName] = Future.value(data);
  }

  /// Drops the shared load, so the next call fetches again. Null clears all.
  static void invalidate([String? venueName]) {
    if (venueName == null) {
      _loads.clear();
    } else {
      _loads.remove(venueName);
    }
  }

  Future<BuildingData> fetchBuildingIDS(String id) {
    // An empty venue answers `200 {"buildings":[],"campus":{...}}` — a wasted
    // round-trip whose only effect is to look like a venue with no buildings.
    // Callers reach here before the venue is known, so bail. Deliberately not
    // recorded in [_loads]: the next call with a real venue must still fetch.
    if (id.trim().isEmpty) {
      print("fetchBuildingIDS: empty venue name — skipping request");
      return Future.value(BuildingData(buildings: [], campus: null));
    }
    return fetchResponse(id).then(BuildingData.fromJson);
  }

  /// The venue's raw `building/get/venue` response, from the load shared by
  /// every caller this session.
  Future<Map<String, dynamic>> fetchResponse(String id) {
    final existing = _loads[id];
    if (existing != null) return existing;
    final load = _fetchResponse(id);
    _loads[id] = load;
    // A failed load must not be remembered — the next caller retries.
    load.catchError((Object error) {
      if (identical(_loads[id], load)) _loads.remove(id);
      throw error;
    });
    return load;
  }

  Future<Map<String, dynamic>> _fetchResponse(String id) async {
    final buildingByVenueBox = BuildingByVenueAPIBOX.getData();

    // Seed from the bundled asset (if any) so there's something to fall
    // back to below even if the live fetch fails or there's no internet.
    if (!buildingByVenueBox.containsKey(id)) {
      await _seedFromAssetIfNeeded(id, buildingByVenueBox);
    }

    // Prefer a live fetch whenever we're online, and use its result for
    // THIS render — not just save it for next launch. The previous
    // fire-and-forget "_backgroundSync" always rendered from whatever was
    // cached (a bundled asset, or a prior session's fetch) and only
    // updated the cache for the *next* launch, so a server-side data fix
    // stayed invisible until the app was uninstalled and reinstalled,
    // which is the only path that starts with an empty cache.
    if (await checkInternetConnectivity()) {
      try {
        return await _fetchFromApi(id, buildingByVenueBox);
      } catch (_) {
        // fall through to cache below
      }
    }

    if (buildingByVenueBox.containsKey(id)) {
      final responseBody = buildingByVenueBox.get(id)!.responseBody;
      print("UNIFIED MAP BUILDINGBYVENUE DATA FROM DATABASE");
      return Map<String, dynamic>.from(responseBody);
    }

    throw("no preload & no DB data & no internet");
  }

  /// Seeds DB from bundled asset. Returns true if successful.
  Future<bool> _seedFromAssetIfNeeded(String id, dynamic box) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/api_data/BuildingByVenue${id}.json',
      );
      final Map<String, dynamic> responseBody = json.decode(raw);
      final model = BuildingByVenueAPIModel(responseBody: responseBody);
      box.put(id, model);
      await model.save();
      print("UNIFIED MAP BUILDINGBYVENUE seeded from asset.");
      return true;
    } catch (_) {
      print("No bundled BuildingByVenue asset found.");
      return false;
    }
  }

  Future<Map<String, dynamic>> _fetchFromApi(String id, dynamic box) async {
    final data = {"venueName": id, "campusIncludes": true};
    final response = await http.post(
      Uri.parse(baseUrl),
      body: json.encode(data),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseBody = json.decode(response.body);
      // Stringifies the whole decoded payload on the main thread; `print` is not
      // stripped from Flutter web release builds. Native keeps the original log.
      if (!kIsWeb) print("UNIFIED MAP BUILDINGBYVENUE DATA FROM API $responseBody");
      final model = BuildingByVenueAPIModel(responseBody: responseBody);
      box.put(id, model);
      await model.save();
      return responseBody;
    } else if (response.statusCode == 403) {
      // Rejected key. Retrying cannot fix that, and retrying with no delay or
      // limit (as this used to) floods the server until the page is closed.
      // Thrown, so the caller falls back to the cache like any other failure.
      throw Exception('building/get/venue: api key rejected (403)');
    } else {
      throw Exception('Failed to load building data');
    }
  }

  static Future<bool> checkInternetConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();

    if (!connectivityResult.contains(ConnectivityResult.mobile) &&
        !connectivityResult.contains(ConnectivityResult.wifi) &&
        !(kIsWeb && connectivityResult.contains(ConnectivityResult.ethernet))) {
      return false;
    }

    // The reachability probe is a cross-origin request the browser blocks
    // (clients3.google.com sends no CORS headers), so it always reports
    // offline on web. Trust the connectivity result there instead.
    if (kIsWeb) return true;

    try {
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 3));

      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}