import 'package:flutter_compass/flutter_compass.dart';

import 'heading_source_native.dart'
    if (dart.library.js_interop) 'heading_source_web.dart' as impl;

/// Where the user puck's rotation comes from.
///
/// Native reads `flutter_compass` directly; web has no compass of its own and
/// uses whatever the host relays in through [HostHeading]. Use this in place of
/// `FlutterCompass.events` at call sites — on native it *is*
/// `FlutterCompass.events`.
class HeadingSource {
  /// Null when no heading is available on this platform, mirroring
  /// `FlutterCompass.events`.
  static Stream<CompassEvent>? get events => impl.headingEvents;

  /// Whether the puck should be drawn as a directional arrow.
  ///
  /// False only in a plain browser, where no heading reaches the map and an
  /// arrow would point somewhere it cannot justify. The puck is a plain disc
  /// there instead.
  static bool get isDirectional => impl.headingIsDirectional;
}
