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

  /// Web has no `dart:io` filesystem and no `path_provider`, so the on-disk
  /// cache used on mobile is unavailable — `getApplicationCacheDirectory()`
  /// throws a MissingPluginException on the very first line and every marker
  /// icon fetched over http fails. The browser's own HTTP cache already gives
  /// the persistence the disk cache provides on mobile, so just read the
  /// bundled asset and otherwise go straight to the network.
  Future<Uint8List?> _fetchWithCacheWeb(String url) async {
    final fileName = md5.convert(utf8.encode(url)).toString();
    try {
      final data = await rootBundle.load('assets/icons/$fileName');
      return data.buffer.asUint8List();
    } catch (_) {
      // Not bundled — fall through to the network.
    }
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> fetchWithCache(String url) async {
    if (kIsWeb) return _fetchWithCacheWeb(url);

    final dir = await getApplicationCacheDirectory();
    final fileName = md5.convert(utf8.encode(url)).toString(); // 32 chars
    final file = File('${dir.path}/$fileName');

    // Always serve from disk if available (works offline forever)
    if (await file.exists()) {
      final bytes=await file.readAsBytes();
      return bytes;
    }

    try {
      final assetPath = 'assets/icons/$fileName'; // 👈 define your folder
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      print("$fileName found in assets");
      // Optional: save to cache for next time
      await file.writeAsBytes(bytes);

      return bytes;
    } catch (_) {
      print("$fileName not found in assets");
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