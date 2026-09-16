import 'package:flutter_test/flutter_test.dart';
import 'package:unified_map_view/unified_map_view.dart';

/// Mirrors the matcher in MaplibreMapProvider._passesMarkerTypeFilter.
bool matches(String wanted, String rawType) => RegExp(
      '(?<![a-z0-9])${RegExp.escape(wanted)}(?![a-z0-9])',
    ).hasMatch(rawType.toLowerCase().trim());

/// Every type observed in the two venues used for development.
const _delhiZoo = [
  'Mammals', 'Birds', 'Sitting Area', 'Reptiles', 'Drinking Water',
  'Pick up / Drop Off Point', 'Female Washroom', 'Male Washroom', 'Cafeteria',
  'First Aid', 'Counter', 'Main Entry', 'Assembly Area', 'ATM', 'Booth',
  'Boundary', 'Parking', 'Room Door',
];
const _aigHospital = [
  'Sitting Area', 'Room Door', 'Lift', 'Door Only', 'Pharmacy / Dispensary',
  'Accessible Washroom', 'Cafeteria', 'Female Washroom', 'Male Washroom',
  'Boundary', 'Counter', 'Escalator-down', 'Escalator-up', 'Exit Only',
  'Help Desk', 'Main Entry', 'Reception', 'Stairs',
];

void main() {
  group('MarkerTypes reachability', () {
    test('every observed venue type is reachable by some constant', () {
      for (final raw in {..._delhiZoo, ..._aigHospital}) {
        expect(MarkerTypes.all.any((c) => matches(c, raw)), isTrue,
            reason: 'no MarkerTypes constant matches "$raw"');
      }
    });

    test('an exact spelling matches itself', () {
      for (final raw in _aigHospital) {
        expect(matches(raw.toLowerCase(), raw), isTrue);
      }
    });
  });

  group('whole-word matching', () {
    // The bug this guards: plain `contains` made 'male washroom' match
    // "FEmale washroom", so filtering to male washrooms returned female ones.
    test('male washroom does not match female washroom', () {
      expect(matches(MarkerTypes.maleWashroom, 'Female Washroom'), isFalse);
      expect(matches(MarkerTypes.maleWashroom, 'Male Washroom'), isTrue);
    });

    test('room does not match washroom', () {
      expect(matches(MarkerTypes.room, 'Accessible Washroom'), isFalse);
      expect(matches(MarkerTypes.room, 'Room Door'), isTrue);
    });

    test('broad washroom still catches every variant', () {
      for (final v in ['Male Washroom', 'Female Washroom', 'Accessible Washroom']) {
        expect(matches(MarkerTypes.washroom, v), isTrue, reason: v);
      }
    });

    test('escalator catches both directions, each direction only itself', () {
      expect(matches(MarkerTypes.escalator, 'Escalator-up'), isTrue);
      expect(matches(MarkerTypes.escalator, 'Escalator-down'), isTrue);
      expect(matches(MarkerTypes.escalatorUp, 'Escalator-down'), isFalse);
      expect(matches(MarkerTypes.escalatorDown, 'Escalator-up'), isFalse);
    });

    test('partial words do not match', () {
      expect(matches(MarkerTypes.lift, 'Shoplifting Desk'), isFalse);
      expect(matches(MarkerTypes.exit, 'Exitless Room'), isFalse);
    });
  });
}
