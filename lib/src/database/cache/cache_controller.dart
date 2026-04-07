import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:path_provider/path_provider.dart';

import '../../config.dart';

class CacheController {

  Future<Uint8List?> fetchWithCache(String url) async {
    final dir = await getApplicationCacheDirectory();
    final fileName = md5.convert(utf8.encode(url)).toString(); // 32 chars
    final file = File('${dir.path}/$fileName');

    // Always serve from disk if available (works offline forever)
    if (await file.exists()) {
      final bytes=await file.readAsBytes();
      if (AppConfig.internetSpeedInMbps >= 1) {
        _refreshCacheInBackground(url, file);
      }
      return bytes;
    }


    if (AppConfig.internetSpeedInMbps < 1) {
      return null;
    }

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