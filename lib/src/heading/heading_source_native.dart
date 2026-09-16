import 'package:flutter_compass/flutter_compass.dart';

/// Native heading: unchanged `flutter_compass` behaviour.
Stream<CompassEvent>? get headingEvents => FlutterCompass.events;

/// Always directional on native — the device compass is right there.
bool get headingIsDirectional => true;
