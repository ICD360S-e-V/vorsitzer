import 'package:flutter/material.dart';

/// A single clothing/gear suggestion, e.g. "🧥 Warme Jacke — Wind 25 km/h".
class ClothingItem {
  final String emoji;
  final String label;
  final String? detail;
  const ClothingItem(this.emoji, this.label, [this.detail]);
}

/// Result of [computeClothingAdvice] — the list of items to bring/wear plus
/// optional travel hint (extra time to allow) and a warning flag when the
/// forecast suggests staying inside entirely.
class ClothingAdvice {
  final List<ClothingItem> items;
  final String? travelNote;
  final String? warning; // "Bei Gewitter besser drinnen bleiben"

  const ClothingAdvice({
    required this.items,
    this.travelNote,
    this.warning,
  });

  bool get isEmpty => items.isEmpty && warning == null;
}

/// Derive a concrete clothing/gear recommendation from a forecast slice.
///
/// [apparentTemp] and [temp] in °C, [wind] in km/h, [precipProb] as 0..100 %,
/// [precip] in mm/h, [uvIndex] 0..12 optional, [humidity] % optional,
/// [weatherCode] WMO code, [durationMinutes] how long the person is outside
/// (defaults to 60 min if unknown — a typical Termin length).
///
/// Chosen thresholds match roughly what a German mother would tell you before
/// walking to the Jobcenter — pragmatic, not a fashion column.
ClothingAdvice computeClothingAdvice({
  required double apparentTemp,
  required double temp,
  required int weatherCode,
  required double wind,
  required int precipProb,
  required double precip,
  double? uvIndex,
  int? humidity,
  int durationMinutes = 60,
}) {
  final items = <ClothingItem>[];
  String? travelNote;
  String? warning;

  final isThunder = weatherCode >= 95 && weatherCode <= 99;
  final isSnow = (weatherCode >= 71 && weatherCode <= 77) ||
      (weatherCode >= 85 && weatherCode <= 86);
  final isSleet = weatherCode == 56 || weatherCode == 57 ||
      weatherCode == 66 || weatherCode == 67;
  final isRain = ((weatherCode >= 51 && weatherCode <= 67) ||
          (weatherCode >= 80 && weatherCode <= 82)) &&
      !isSleet;

  // ── Kleidung nach gefühlter Temperatur ──
  if (apparentTemp <= -5) {
    items.add(ClothingItem('🧥', 'Winter-Jacke',
        'gefühlt ${apparentTemp.toStringAsFixed(0)}°C — dick anziehen'));
    items.add(const ClothingItem('🧣', 'Schal & Mütze'));
    items.add(const ClothingItem('🧤', 'Handschuhe'));
    items.add(const ClothingItem('🥾', 'Winter- oder Trekkingschuhe',
        'Rutschgefahr, Frost'));
  } else if (apparentTemp <= 5) {
    items.add(ClothingItem('🧥', 'Warme Jacke',
        'gefühlt ${apparentTemp.toStringAsFixed(0)}°C'));
    items.add(const ClothingItem('🧣', 'Schal'));
    if (apparentTemp <= 0) {
      items.add(const ClothingItem('🧤', 'Handschuhe'));
    }
  } else if (apparentTemp <= 12) {
    items.add(ClothingItem('🧥', 'Leichte Jacke oder Pullover',
        'gefühlt ${apparentTemp.toStringAsFixed(0)}°C'));
  } else if (apparentTemp <= 18) {
    items.add(const ClothingItem('👕', 'Langarmshirt',
        'evtl. mit Weste oder Cardigan'));
  } else if (apparentTemp <= 25) {
    items.add(ClothingItem('👕', 'T-Shirt',
        'angenehme ${apparentTemp.toStringAsFixed(0)}°C'));
  } else if (apparentTemp <= 30) {
    items.add(ClothingItem('👕', 'Leichte Sommerkleidung',
        'gefühlt ${apparentTemp.toStringAsFixed(0)}°C — dünner Stoff'));
    items.add(const ClothingItem('💧', 'Wasserflasche mitnehmen'));
  } else {
    items.add(ClothingItem('👕', 'Sehr leichte Kleidung',
        'gefühlt ${apparentTemp.toStringAsFixed(0)}°C — Hitze!'));
    items.add(const ClothingItem('💧', 'Viel Wasser (0,5 L+)'));
    items.add(const ClothingItem('🧢', 'Kopfbedeckung'));
  }

  // ── Regen / Schnee / Sleet ──
  final rainish = isRain || precip >= 1 || precipProb >= 60;
  if (rainish) {
    items.add(ClothingItem('☔', 'Regenschirm',
        precipProb > 0 ? '$precipProb % Regenwahrsch.' : null));
    if (precip >= 3 || precipProb >= 80) {
      items.add(const ClothingItem('🥾', 'Wasserdichte Schuhe'));
    }
  } else if (isSleet) {
    items.add(const ClothingItem('☔', 'Regenschirm', 'Schneeregen'));
    items.add(const ClothingItem('🥾', 'Wasserdichte Schuhe'));
  } else if (isSnow) {
    items.add(const ClothingItem('🥾', 'Winterschuhe mit Profil',
        'Schneefall — Rutschgefahr'));
  }

  // ── Wind ──
  if (wind >= 40) {
    items.add(ClothingItem('💨', 'Sturmfest anziehen',
        'Wind ${wind.toStringAsFixed(0)} km/h — Schal fixieren, Kapuze zu'));
  } else if (wind >= 20) {
    items.add(ClothingItem('🧥', 'Windjacke',
        'Wind ${wind.toStringAsFixed(0)} km/h'));
  }

  // ── UV / Sonne ──
  if (uvIndex != null) {
    if (uvIndex >= 8) {
      items.add(ClothingItem('🧴', 'Sonnencreme LSF 50+',
          'UV-Index ${uvIndex.toStringAsFixed(1)} — sehr hoch'));
      items.add(const ClothingItem('🕶️', 'Sonnenbrille'));
      if (!items.any((i) => i.emoji == '🧢')) {
        items.add(const ClothingItem('🧢', 'Kopfbedeckung'));
      }
    } else if (uvIndex >= 6) {
      items.add(ClothingItem('🧴', 'Sonnencreme LSF 30+',
          'UV-Index ${uvIndex.toStringAsFixed(1)}'));
    } else if (uvIndex >= 3 && apparentTemp >= 22) {
      items.add(const ClothingItem('🧴', 'Sonnencreme'));
    }
  }

  // ── Feuchtigkeit (schwül) ──
  if (humidity != null && humidity >= 80 && apparentTemp >= 24 && !isRain) {
    items.add(const ClothingItem('👕', 'Atmungsaktive Kleidung',
        'Baumwolle statt Synthetik — es ist schwül'));
  }

  // ── Reise-Hinweis ──
  if (rainish || isSnow) {
    travelNote = '⏱ 15 Min früher losfahren — Verkehr bei Niederschlag';
  } else if (wind >= 40) {
    travelNote = '⏱ Extra Zeit einplanen bei Sturm';
  } else if (durationMinutes >= 120) {
    travelNote = '⏱ Lange draußen (${durationMinutes ~/ 60} h) — Snack + Wasser';
  }

  // ── Warnung: nicht rausgehen ──
  if (isThunder) {
    warning = 'Bei Gewitter Termin möglichst verschieben. '
        'Wenn nicht möglich: Regenschirm mit Metallstab MEIDEN, '
        'schnellstmöglich ins Gebäude.';
  }

  return ClothingAdvice(items: items, travelNote: travelNote, warning: warning);
}

/// Compact card rendering a [ClothingAdvice]. Reused in the WeatherDialog
/// (Aktuell tab) and inside the Termin edit dialog beneath the weather hint.
class ClothingAdviceCard extends StatelessWidget {
  final ClothingAdvice advice;
  final String? headline; // e.g. "Für heute" or "Für 09:00 Jobcenter"

  const ClothingAdviceCard({super.key, required this.advice, this.headline});

  @override
  Widget build(BuildContext context) {
    if (advice.isEmpty) return const SizedBox.shrink();
    const emojiFonts = ['Segoe UI Emoji', 'Apple Color Emoji', 'Noto Color Emoji'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.brown.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.brown.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('🧥', style: TextStyle(fontSize: 18, fontFamilyFallback: emojiFonts)),
              const SizedBox(width: 8),
              Text(
                headline == null ? 'Anziehtipp' : 'Anziehtipp — $headline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...advice.items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(it.emoji,
                          style: const TextStyle(
                              fontSize: 15, fontFamilyFallback: emojiFonts)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(it.label,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          if (it.detail != null)
                            Text(it.detail!,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade700)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          if (advice.travelNote != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                advice.travelNote!,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.amber.shade900,
                    fontFamilyFallback: emojiFonts),
              ),
            ),
          ],
          if (advice.warning != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, color: Colors.red.shade700, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      advice.warning!,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade900,
                          height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
