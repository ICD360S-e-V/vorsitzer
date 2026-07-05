import 'package:flutter/material.dart';

import '../services/weather_profile_service.dart';

/// Settings dialog for the user's weather-sensitivity profile.
///
/// Grouped in three sections: temperature sensitivity, chronic condition,
/// pollen allergies. Persists immediately on toggle so nothing is lost when
/// the dialog is dismissed with the platform back gesture.
class WeatherProfileDialog extends StatefulWidget {
  const WeatherProfileDialog({super.key});

  @override
  State<WeatherProfileDialog> createState() => _WeatherProfileDialogState();
}

class _WeatherProfileDialogState extends State<WeatherProfileDialog> {
  late WeatherProfile _p;

  @override
  void initState() {
    super.initState();
    _p = WeatherProfileService.instance.current;
  }

  Future<void> _update(WeatherProfile next) async {
    setState(() => _p = next);
    await WeatherProfileService.instance.save(next);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.shade600,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Mein Wetter-Profil',
                      style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Warnungen und Empfehlungen werden auf deine persönliche '
                    'Empfindlichkeit zugeschnitten. Beispiel: markierst du '
                    '„Empfindlich bei Kälte", wird eine Warnung schon ab '
                    '+3 °C statt ab 0 °C ausgelöst.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 14),
                  _section('Temperatur-Empfindlichkeit'),
                  _switchTile(
                    '🥶 Empfindlich bei Kälte',
                    'Frostwarnung bereits ab +3 °C',
                    _p.coldSensitive,
                    (v) => _update(_p.copyWith(coldSensitive: v)),
                  ),
                  _switchTile(
                    '🥵 Empfindlich bei Hitze',
                    'Hitzewarnung bereits ab gefühlt 29 °C',
                    _p.heatSensitive,
                    (v) => _update(_p.copyWith(heatSensitive: v)),
                  ),
                  const SizedBox(height: 8),
                  _section('Chronische Bedingungen'),
                  _switchTile(
                    '😷 Asthma / COPD',
                    'Feinstaub-Warnung bereits ab 35 µg/m³',
                    _p.asthma,
                    (v) => _update(_p.copyWith(asthma: v)),
                  ),
                  _switchTile(
                    '🔆 Foto-sensible Medikamente',
                    'UV-Warnung bereits ab Index 4,5',
                    _p.photoSensitive,
                    (v) => _update(_p.copyWith(photoSensitive: v)),
                  ),
                  const SizedBox(height: 8),
                  _section('Pollen-Allergien'),
                  Text(
                    'Warnungen erscheinen nur für die Pollen, die du hier markierst.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  _switchTile('🌿 Erle', null, _p.allergyErle,
                      (v) => _update(_p.copyWith(allergyErle: v))),
                  _switchTile('🌳 Birke', null, _p.allergyBirke,
                      (v) => _update(_p.copyWith(allergyBirke: v))),
                  _switchTile('🌾 Gräser', null, _p.allergyGraeser,
                      (v) => _update(_p.copyWith(allergyGraeser: v))),
                  _switchTile('🌱 Beifuß', null, _p.allergyBeifuss,
                      (v) => _update(_p.copyWith(allergyBeifuss: v))),
                  _switchTile('🫒 Olive', null, _p.allergyOlive,
                      (v) => _update(_p.copyWith(allergyOlive: v))),
                  _switchTile('🌼 Ambrosia', null, _p.allergyAmbrosia,
                      (v) => _update(_p.copyWith(allergyAmbrosia: v))),
                  const SizedBox(height: 12),
                  Text(
                    'Die Einstellungen bleiben nur auf diesem Gerät — sie '
                    'werden nicht auf den Vereins-Server hochgeladen.',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          title,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.teal.shade900,
              letterSpacing: 0.4),
        ),
      );

  Widget _switchTile(
      String title, String? subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.teal,
    );
  }
}
