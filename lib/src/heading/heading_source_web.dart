import 'package:flutter_compass/flutter_compass.dart';

import 'host_heading.dart';

/// Web heading: only what the host relays in.
///
/// Deliberately no DeviceOrientation fallback. Inside a WebView those events
/// are unreliable, and in a plain browser they cost a permission prompt for a
/// heading the map would rather show honestly as "unknown" — see [HostHeading].
Stream<CompassEvent>? get headingEvents => HostHeading.stream;

/// Directional only when a heading is actually arriving.
bool get headingIsDirectional => HostHeading.stream != null;
