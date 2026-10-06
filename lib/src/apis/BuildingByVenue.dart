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
  /// leaves exactly one live fetch per session (see [_fetchResponse]).
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

    // Seed from the bundled asset (if any) so a first run has something to
    // serve below.
    if (!buildingByVenueBox.containsKey(id)) {
      await _seedFromAssetIfNeeded(id, buildingByVenueBox);
    }

    // Cached: serve it now and refresh the cache behind it, for the next
    // launch. Waiting on the live fetch here held the whole venue off screen
    // for as long as the network took, on every launch, for a response that
    // rarely differs from the cached one.
    if (buildingByVenueBox.containsKey(id)) {
      final responseBody = buildingByVenueBox.get(id)!.responseBody;
      print("UNIFIED MAP BUILDINGBYVENUE DATA FROM DATABASE");
      _refresh(id, buildingByVenueBox);
      return Map<String, dynamic>.from(responseBody);
    }

    if (await checkInternetConnectivity()) {
      return await _fetchFromApi(id, buildingByVenueBox);
    }

    throw("no preload & no DB data & no internet");
  }

  /// Fetches the venue live and stores it for the next launch.
  Future<void> _refresh(String id, dynamic box) async {
    try {
      if (!await checkInternetConnectivity()) return;
      await _fetchFromApi(id, box);
    } catch (e) {
      print("UNIFIED MAP BUILDINGBYVENUE background refresh failed: $e");
    }
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