import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// A compass heading relayed in by the host application, for the platforms
/// where the map cannot read one itself.
///
/// On native the map reads the device compass directly and nothing here is
/// consulted. In a browser there is no compass to read: `flutter_compass`
/// declares no web platform, so `FlutterCompass.events` resolves to an
/// unregistered EventChannel and every listener gets a
/// `MissingPluginException`.
///
/// A host that *can* see the device's compass hands the stream in here —
/// navigation_sdk does, inside a native shell, where the phone's compass
/// arrives over the scanner bridge. That is the same sensor the native build
/// uses, so the puck behaves identically in both.
///
/// While this is null on web nothing can point the puck, so it is drawn as a
/// non-directional disc rather than an arrow frozen at north.
class HostHeading {
  HostHeading._();

  /// The relayed heading, or null when nothing relays one in.
  static Stream<CompassEvent>? get stream => _stream.value;

  /// Fires when [stream] changes.
  ///
  /// The arrow-versus-disc choice is made when the puck marker is built, and a
  /// host generally cannot answer "is a heading available?" until after the
  /// first frame — it is an async handshake with the bridge. So a map already
  /// on screen listens to this and rebuilds its puck.
  static Listenable get changes => _stream;

  static final ValueNotifier<Stream<CompassEvent>?> _stream =
      ValueNotifier<Stream<CompassEvent>?>(null);

  /// Supplies (or with null, withdraws) the relayed heading.
  ///
  /// Broadcast-wrapped if it is not already: each provider subscribes on its
  /// own, and a provider swap or a puck rebuild resubscribes, which a
  /// single-subscription stream would reject.
  static void provide(Stream<CompassEvent>? heading) {
    print('PUCK-DIAG host: provide(${heading != null})');  // TEMP
    _stream.value = heading == null || heading.isBroadcast
        ? heading
        : heading.asBroadcastStream();
  }
}
