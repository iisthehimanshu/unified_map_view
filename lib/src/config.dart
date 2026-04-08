import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:unified_map_view/src/enums/language.dart';

class AppConfig {
  static String? url;

  static Language _language = Language.english;
  static double _internetSpeedInMbps = 0.0;
  static Timer? _speedCheckTimer;

  AppConfig._() {
    _startSpeedMonitor();
  }

  static final AppConfig _instance = AppConfig._();

  static AppConfig get instance => _instance;

  // A small public test file (~200KB) from a reliable CDN
  static const String _speedTestUrl =
      'https://speed.cloudflare.com/__down?bytes=1000000';

  // Auto-starts when the class is first loaded
  static final _init = _startSpeedMonitor();

  static void _startSpeedMonitor() {
    print("_measureSpeed");
    // Run immediately on startup, then every 30 seconds
    _measureSpeed();
    _speedCheckTimer = Timer.periodic(
      const Duration(minutes: 2),
          (_) => _measureSpeed(),
    );
  }

  static Future<void> _measureSpeed() async {
    try {
      print("_measureSpeed1");
      final stopwatch = Stopwatch()..start();

      final response = await http
          .get(Uri.parse(_speedTestUrl))
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();
      print("_measureSpeed2 ${response.statusCode}");
      if (response.statusCode == 200) {
        print("_measureSpeed3");
        final int actualBytes = response.bodyBytes.length;
        final double elapsedSeconds =
            stopwatch.elapsedMilliseconds / 1000.0;

        // Convert bytes to megabits: bytes * 8 / 1,000,000
        final double megabits = (actualBytes * 8) / 1000000.0;

        _internetSpeedInMbps =
        elapsedSeconds > 0 ? megabits / elapsedSeconds : 0.0;

        if (kDebugMode) {
          print(
            '[AppConfig] Internet speed: '
                '${_internetSpeedInMbps.toStringAsFixed(2)} Mbps',
          );
        }
      }
    } catch (e) {
      // On timeout or network error, set speed to 0
      _internetSpeedInMbps = 0.0;
      if (kDebugMode) {
        print('[AppConfig] Speed check failed: $e');
      }
    }
  }

  /// Call this when the app is closing to clean up the timer
  static void dispose() {
    _speedCheckTimer?.cancel();
    _speedCheckTimer = null;
  }

  static double get internetSpeedInMbps => _internetSpeedInMbps;

  static String get baseUrl {
    if (url != null) return url!;
    if (kDebugMode) {
      return 'https://dev.iwayplus.in';
    } else {
      return 'https://dev.iwayplus.in';
    }
  }

  static String get apiKey {
    if (baseUrl == 'https://dev.iwayplus.in') {
      return '7cc62870-d67e-11f0-91ed-2f0eb903e7db';
    } else {
      return '63a0a740-cc23-11f0-b58c-17043284b6b2';
    }
  }

  static setLanguage({required String value}) {
    _language = Language.fromString(value);
  }

  static String get languageCode => _language.code;
}