import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:unified_map_view/src/models/geojson_models.dart';
import 'package:unified_map_view/src/models/map_location.dart';
import 'package:unified_map_view/src/utils/renderingUtilities.dart';

const _logo =
    'https://maps.iwayplus.in/uploads/1787810584643-195383018-cdac logo.webp';

/// A global Booth landmark, shaped like the IITDelhi venue response once
/// `GlobalAppGeoGeometry` has wrapped the point's coordinates in a list.
Map<String, dynamic> _boothJson({Object? exhibitorRef, bool? textLive = true}) =>
    {
      'id': 'booth-g1',
      'building_ID': 'b1',
      'geometry': {
        'type': 'Point',
        'coordinates': [
          [77.1932, 28.5429],
        ],
      },
      'properties': {
        'name': 'G1',
        'type': 'Booth',
        'global': true,
        'imageLive': true,
        if (textLive != null) 'textLive': textLive,
        if (exhibitorRef != null) 'exhibitorRef': exhibitorRef,
      },
    };

GeoJsonMarker _marker(Map<String, dynamic> json) =>
    GeoJsonMarker.fromFeature(GeoJsonFeature.fromJson(json))!;

void main() {
  group('exhibitor logo markers', () {
    test('a booth with an exhibitor logo draws the logo, not its name', () {
      final marker = _marker(_boothJson(exhibitorRef: {
        'organizationDetails': {'organizationName': 'CDAC Mumbai'},
        'brandingDetails': {'companyLogo': _logo},
        '_id': '6a8fc0c8943ba9769d77ece4',
      }));

      expect(marker.assetPath, _logo);
      expect(marker.textVisibility, isFalse);
      expect(marker.customRendering, isTrue);
      expect(marker.imageSize, GeoJsonMarker.exhibitorLogoSize);
      expect(marker.isExhibitorLogo, isTrue);
      // Kept for the renderer's fallback when the logo cannot be loaded.
      expect(marker.title, 'CDAC Mumbai');
    });

    test('the organisation name is trimmed', () {
      final marker = _marker(_boothJson(exhibitorRef: {
        'organizationDetails': {'organizationName': 'NCPEDP '},
        'brandingDetails': {'companyLogo': _logo},
      }));

      expect(marker.title, 'NCPEDP');
    });

    test('an unnamed exhibitor falls back to the landmark name', () {
      final marker = _marker(_boothJson(
        textLive: null,
        exhibitorRef: {
          'brandingDetails': {'companyLogo': _logo},
        },
      ));

      expect(marker.isExhibitorLogo, isTrue);
      expect(marker.title, 'G1');
    });

    test('a booth without an exhibitor stays a plain name marker', () {
      final marker = _marker(_boothJson());

      expect(marker.assetPath, isNull);
      expect(marker.textVisibility, isTrue);
      expect(marker.customRendering, isFalse);
      expect(marker.isExhibitorLogo, isFalse);
      expect(marker.title, 'G1');
    });

    test('an exhibitor with no usable logo stays a plain name marker', () {
      for (final exhibitorRef in <Object>[
        {'organizationDetails': {'organizationName': '  '}},
        {'brandingDetails': <String, dynamic>{}},
        {'brandingDetails': {'companyLogo': ''}},
        {'brandingDetails': {'companyLogo': null}},
      ]) {
        final marker = _marker(_boothJson(exhibitorRef: exhibitorRef));

        expect(marker.assetPath, isNull, reason: '$exhibitorRef');
        expect(marker.textVisibility, isTrue, reason: '$exhibitorRef');
        expect(marker.isExhibitorLogo, isFalse, reason: '$exhibitorRef');
        expect(marker.title, 'G1', reason: '$exhibitorRef');
      }
    });

    test('an exhibitor without a logo is labelled with its organisation', () {
      final marker = _marker(_boothJson(exhibitorRef: {
        'organizationDetails': {'organizationName': 'CDAC Mumbai'},
      }));

      expect(marker.isExhibitorLogo, isFalse);
      expect(marker.textVisibility, isTrue);
      expect(marker.title, 'CDAC Mumbai');
    });
  });

  group('booth polygon shortest side', () {
    // A 4m x 2m booth rotated 30 degrees, built in local meters around the
    // IITDelhi venue and converted with the same factors the utility uses.
    List<MapLocation> booth({double w = 4, double h = 2, double deg = 30}) {
      const lat0 = 28.5429, lng0 = 77.1932;
      final a = deg * pi / 180;
      return [
        for (final c in [[0.0, 0.0], [w, 0.0], [w, h], [0.0, h], [0.0, 0.0]])
          MapLocation(
            latitude:
                lat0 + (c[0] * sin(a) + c[1] * cos(a)) / 110540.0,
            longitude: lng0 +
                (c[0] * cos(a) - c[1] * sin(a)) /
                    (111320.0 * cos(lat0 * pi / 180)),
          ),
      ];
    }

    test('is the short side of a rotated rectangle', () {
      expect(RenderingUtilities().shortestSideMeters(booth()),
          closeTo(2.0, 0.02));
      expect(RenderingUtilities().shortestSideMeters(booth(w: 2, h: 3)),
          closeTo(2.0, 0.02));
    });

    test('is null for a degenerate polygon', () {
      expect(RenderingUtilities().shortestSideMeters(booth().take(2).toList()),
          isNull);
    });
  });
}
