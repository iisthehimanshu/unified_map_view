import 'map_viewport.dart';

/// Native map views are sized by the platform; there is nothing to wait for.
MapViewportState mapViewportState() => MapViewportState.ready;
