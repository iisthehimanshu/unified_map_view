// lib/src/enums/map_provider.dart

/// Enum representing different map providers
enum MapProvider {
  /// Google Maps provider
  google,

  /// Mapbox provider
  mapbox,

  /// Mappls Maps provider
  mappls,
}

extension MapProviderExtension on MapProvider {
  String get name {
    switch (this) {
      case MapProvider.google:
        return 'Google Maps';
      case MapProvider.mapbox:
        return 'Mapbox';
      case MapProvider.mappls:
        return 'Mappls';
    }
  }
}