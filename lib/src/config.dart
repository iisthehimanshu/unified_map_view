import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unified_map_view/src/enums/language.dart';

class AppConfig {

  static String? url;

  static Language _language = Language.english;

  static String get baseUrl {
    if(url != null){
      return url!;
    }

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
      //this api key is for udit soni
      return '63a0a740-cc23-11f0-b58c-17043284b6b2';
    }
  }

  static setLanguage({required String value}) {
    _language = Language.fromString(value);
  }

  static String get languageCode => _language.code;

}



