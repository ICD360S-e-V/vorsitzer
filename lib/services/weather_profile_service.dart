import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-configurable weather-sensitivity profile.
///
/// Persisted per-device in SharedPreferences (JSON via individual bool keys —
/// small and future-proof). Used by [WeatherService._evaluateHealthAlerts] to
/// tighten thresholds and by the Umwelt-Tab's pollen row to highlight only
/// the specific allergies the user marked.
class WeatherProfile {
  final bool coldSensitive;
  final bool heatSensitive;
  final bool asthma;
  final bool photoSensitive; // photo-sensitive medication → tighter UV threshold
  final bool allergyErle;    // Alder
  final bool allergyBirke;
  final bool allergyGraeser;
  final bool allergyBeifuss;
  final bool allergyOlive;
  final bool allergyAmbrosia;

  const WeatherProfile({
    this.coldSensitive = false,
    this.heatSensitive = false,
    this.asthma = false,
    this.photoSensitive = false,
    this.allergyErle = false,
    this.allergyBirke = false,
    this.allergyGraeser = false,
    this.allergyBeifuss = false,
    this.allergyOlive = false,
    this.allergyAmbrosia = false,
  });

  bool get anyAllergy =>
      allergyErle || allergyBirke || allergyGraeser ||
      allergyBeifuss || allergyOlive || allergyAmbrosia;

  WeatherProfile copyWith({
    bool? coldSensitive, bool? heatSensitive, bool? asthma, bool? photoSensitive,
    bool? allergyErle, bool? allergyBirke, bool? allergyGraeser,
    bool? allergyBeifuss, bool? allergyOlive, bool? allergyAmbrosia,
  }) =>
      WeatherProfile(
        coldSensitive: coldSensitive ?? this.coldSensitive,
        heatSensitive: heatSensitive ?? this.heatSensitive,
        asthma: asthma ?? this.asthma,
        photoSensitive: photoSensitive ?? this.photoSensitive,
        allergyErle: allergyErle ?? this.allergyErle,
        allergyBirke: allergyBirke ?? this.allergyBirke,
        allergyGraeser: allergyGraeser ?? this.allergyGraeser,
        allergyBeifuss: allergyBeifuss ?? this.allergyBeifuss,
        allergyOlive: allergyOlive ?? this.allergyOlive,
        allergyAmbrosia: allergyAmbrosia ?? this.allergyAmbrosia,
      );
}

/// Singleton store — the WeatherService reads from it during health-alert
/// evaluation, and settings-UI writes back via [save]. Both listen to
/// [notifier] so hot-reload of the profile refreshes any open Aktuell tab.
class WeatherProfileService {
  static const _keyPrefix = 'weather_profile_';

  static final WeatherProfileService instance = WeatherProfileService._();
  WeatherProfileService._();

  final ValueNotifier<WeatherProfile> notifier =
      ValueNotifier<WeatherProfile>(const WeatherProfile());

  WeatherProfile get current => notifier.value;

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      bool r(String k) => sp.getBool('$_keyPrefix$k') ?? false;
      notifier.value = WeatherProfile(
        coldSensitive: r('cold'),
        heatSensitive: r('heat'),
        asthma: r('asthma'),
        photoSensitive: r('photo'),
        allergyErle: r('a_erle'),
        allergyBirke: r('a_birke'),
        allergyGraeser: r('a_graeser'),
        allergyBeifuss: r('a_beifuss'),
        allergyOlive: r('a_olive'),
        allergyAmbrosia: r('a_ambrosia'),
      );
    } catch (_) {/* fall back to default profile */}
  }

  Future<void> save(WeatherProfile p) async {
    notifier.value = p;
    try {
      final sp = await SharedPreferences.getInstance();
      Future<void> w(String k, bool v) => sp.setBool('$_keyPrefix$k', v);
      await Future.wait([
        w('cold', p.coldSensitive),
        w('heat', p.heatSensitive),
        w('asthma', p.asthma),
        w('photo', p.photoSensitive),
        w('a_erle', p.allergyErle),
        w('a_birke', p.allergyBirke),
        w('a_graeser', p.allergyGraeser),
        w('a_beifuss', p.allergyBeifuss),
        w('a_olive', p.allergyOlive),
        w('a_ambrosia', p.allergyAmbrosia),
      ]);
    } catch (_) {/* not fatal */}
  }
}
