import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:path_provider/path_provider.dart';

import '../../config.dart';

class CacheController {
  /// Every bundled asset path, resolved once from the asset manifest.
  ///
  /// Checked for the *exact* file before any `rootBundle.load`, so a miss costs
  /// a set lookup instead of a failing load. Testing the folder is not enough:
  /// `assets/icons/.gitkeep` is bundled as a directory placeholder, so a "does
  /// this folder exist" check passes while every real icon is still absent.
  static Future<Set<String>>? _bundledAssets;

  static Future<Set<String>> _assetIndex() {
    return _bundledAssets ??= () async {
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        return manifest.listAssets().toSet();
      } catch (_) {
        // Manifest unreadable — treat everything as unbundled rather than
        // paying a failing probe per icon.
        return <String>{};
      }
    }();
  }

  static Future<bool> _isBundled(String assetPath) async =>
      (await _assetIndex()).contains(assetPath);

  /// Web has no `dart:io` filesystem and no `path_provider`, so the on-disk
  /// cache used on mobile is unavailable — `getApplicationCacheDirectory()`
  /// throws a MissingPluginException on the very first line and every marker
  /// icon fetched over http fails. The browser's own HTTP cache already gives
  /// the persistence the disk cache provides on mobile, so just read the
  /// bundled asset and otherwise go straight to the network.
  ///
  /// The bundled read is skipped unless the manifest actually lists that exact
  /// file. On web a `rootBundle.load` miss is a real network round trip that
  /// 404s, and no venue icon is bundled — so the probe could never hit, while
  /// costing one 404 per icon. Measured on device: 215 such 404s spread over
  /// 63s of an otherwise idle map, cut to 4.
  Future<Uint8List?> _fetchWithCacheWeb(String url) async {
    final fileName = md5.convert(utf8.encode(url)).toString();
    final assetPath = 'assets/icons/$fileName';
    if (await _isBundled(assetPath)) {
      try {
        final data = await rootBundle.load(assetPath);
        return data.buffer.asUint8List();
      } catch (_) {
        // Listed but unreadable — fall through to the network.
      }
    }
    // Same reasoning as the cache-hit path above: skipping the bundle probe
    // removed this call's only guaranteed yield to the event loop.
    await Future<void>.delayed(Duration.zero);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// NOTE: deliberately NOT memoising the bytes here.
  ///
  /// An in-memory cache keyed by URL was tried and reverted: it hands the SAME
  /// Uint8List instance to every marker sharing a photo, and on web
  /// `ui.instantiateImageCodec` can take ownership of the underlying buffer, so
  /// the second consumer gets a detached one. The failure is silent and total —
  /// the throw escapes the icon rebake inside onStyleLoadedCallback, the
  /// enable*Layers calls at its end never run, and the map sits on the grey
  /// basemap with no error. The bake already caches its *composited output*
  /// (_bakedIconCache / _animalIconCache / _animalSourceCache), which is where
  /// dedup belongs.
  Future<Uint8List?> fetchWithCache(String url) => _fetch(url);

  Future<Uint8List?> _fetch(String url) async {
    if (kIsWeb) return _fetchWithCacheWeb(url);

    final dir = await getApplicationCacheDirectory();
    final fileName = md5.convert(utf8.encode(url)).toString(); // 32 chars
    final file = File('${dir.path}/$fileName');

    // Always serve from disk if available (works offline forever)
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      return bytes;
    }

    final assetPath = 'assets/icons/$fileName'; // 👈 define your folder
    if (await _isBundled(assetPath)) {
      try {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        // Optional: save to cache for next time
        await file.writeAsBytes(bytes);

        return bytes;
      } catch (_) {
        // Listed but unreadable — fall through to the network.
      }
    }

    // if (AppConfig.internetSpeedInMbps < 1) {
    //   return null;
    // }

    // First time — fetch from network AND cache it
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes); // cache for next time
        return response.bodyBytes;
      }
    } catch (_) {}
    return null; // not cached + no internet
  }

  void _refreshCacheInBackground(String url, File file) {
    http.get(Uri.parse(url)).then((response) {
      if (response.statusCode == 200) {
        file.writeAsBytes(response.bodyBytes);
      }
    }).catchError((_) {}); // silently fail if offline
  }
}
