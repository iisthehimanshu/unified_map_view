/// Landmark type identifiers a host can pass to
/// `UnifiedMapController.showMarkerTypes`.
///
/// These exist because [UnifiedMapController.availableMarkerTypes] can only
/// report what the *loaded* venue contains — it is empty until markers arrive,
/// and useless to a host that must build its filter UI before (or without) that
/// API call. These constants are known at compile time, so a host can offer
/// "show me washrooms and lifts" immediately.
///
/// ## Matching is by substring, not equality
///
/// Venues do not agree on spelling: one writes `Male Washroom`, another
/// `Accessible Washroom`, a third might write `Washroom (M)`. [washroom]
/// matches all three, because a type matches when the marker's own type
/// CONTAINS it. This mirrors `RenderingUtilities.getAssetForLandmark`, which
/// picks icons the same way — so filtering and icon choice group types
/// identically instead of disagreeing.
///
/// Two consequences worth knowing:
///
/// * Broad constants are deliberately broad. [room] also matches `Room Door`
///   and `Meeting Room`. Pass a more specific value, or an exact spelling from
///   [UnifiedMapController.availableMarkerTypes], when you need precision.
/// * An exact spelling still works, because a string contains itself. Mixing
///   the two is fine: `{MarkerTypes.washroom, 'Pharmacy / Dispensary'}`.
///
/// Matching is case- and whitespace-insensitive.
class MarkerTypes {
  const MarkerTypes._();

  // ── Facilities ────────────────────────────────────────────────────────────
  /// Every washroom, including the male/female/accessible/unisex variants.
  static const String washroom = 'washroom';
  static const String maleWashroom = 'male washroom';
  static const String femaleWashroom = 'female washroom';
  static const String accessibleWashroom = 'accessible washroom';
  static const String drinkingWater = 'drinking water';
  static const String waterFountain = 'fountain';
  static const String cafeteria = 'cafeteria';
  static const String pharmacy = 'pharmacy';
  static const String firstAid = 'first aid';
  static const String atm = 'atm';
  static const String parking = 'parking';
  static const String vendingMachine = 'vending';
  static const String smokingArea = 'smoking';
  static const String tuckShop = 'tuckshop';
  static const String stationary = 'stationary';

  // ── Floor connections / circulation ───────────────────────────────────────
  /// Lifts and elevators — the data uses both words.
  static const String lift = 'lift';
  static const String elevator = 'elevator';
  static const String stairs = 'stairs';
  /// Both directions; use [escalatorUp] / [escalatorDown] to separate them.
  static const String escalator = 'escalator';
  static const String escalatorUp = 'escalator-up';
  static const String escalatorDown = 'escalator-down';
  static const String ramp = 'ramp';

  // ── Entries and doors ─────────────────────────────────────────────────────
  static const String mainEntry = 'main entry';
  static const String entrance = 'entrance';
  static const String exit = 'exit';
  static const String exitOnly = 'exit only';
  static const String emergencyExit = 'emergency';
  static const String doorOnly = 'door only';
  static const String roomDoor = 'room door';

  // ── Rooms and service points ──────────────────────────────────────────────
  /// Broad: also matches `Room Door` and `Meeting Room`.
  static const String room = 'room';
  static const String office = 'office';
  static const String meetingRoom = 'meeting';
  static const String conferenceHall = 'hall';
  static const String assemblyArea = 'assembly area';
  static const String reception = 'reception';
  static const String helpDesk = 'help desk';
  static const String registrationDesk = 'registration';
  static const String counter = 'counter';
  static const String booth = 'booth';
  static const String sittingArea = 'sitting';
  static const String waitingArea = 'waiting';
  static const String gallery = 'gallery';

  // ── Transport ─────────────────────────────────────────────────────────────
  /// Pick-up / drop-off points and buggy stops.
  static const String pickupDropoff = 'pick';

  // ── Retail ────────────────────────────────────────────────────────────────
  static const String gadgets = 'gadget';
  static const String garments = 'garment';

  // ── Safety ────────────────────────────────────────────────────────────────
  static const String fireExtinguisher = 'fire';

  // ── Zoo / attraction content ──────────────────────────────────────────────
  static const String mammals = 'mammals';
  static const String birds = 'birds';
  static const String reptiles = 'reptiles';

  // ── Structural ────────────────────────────────────────────────────────────
  /// The venue outline. Rarely something a user filters to.
  static const String boundary = 'boundary';

  /// Every constant above, for building a "pick any" UI without a live venue.
  ///
  /// Prefer [UnifiedMapController.availableMarkerTypes] once markers have
  /// loaded — it reports what THIS venue actually has, with counts, so the UI
  /// shows no dead options.
  static const List<String> all = [
    washroom, maleWashroom, femaleWashroom, accessibleWashroom,
    drinkingWater, waterFountain, cafeteria, pharmacy, firstAid, atm,
    parking, vendingMachine, smokingArea, tuckShop, stationary,
    lift, elevator, stairs, escalator, escalatorUp, escalatorDown, ramp,
    mainEntry, entrance, exit, exitOnly, emergencyExit, doorOnly, roomDoor,
    room, office, meetingRoom, conferenceHall, assemblyArea, reception,
    helpDesk, registrationDesk, counter, booth, sittingArea, waitingArea,
    gallery, pickupDropoff, gadgets, garments, fireExtinguisher,
    mammals, birds, reptiles, boundary,
  ];
}
