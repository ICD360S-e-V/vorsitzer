import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math';

/// Moon phase calculator using verified astronomical data from timeanddate.com/USNO
/// New Moon and Full Moon dates are from official astronomical tables (2025-2027)
class MoonPhaseHelper {
  // Verified New Moon dates (UTC) from timeanddate.com
  static final List<DateTime> _newMoons = [
    // 2025
    DateTime.utc(2025, 1, 29, 13, 35), DateTime.utc(2025, 2, 28, 1, 44),
    DateTime.utc(2025, 3, 29, 11, 57), DateTime.utc(2025, 4, 27, 21, 31),
    DateTime.utc(2025, 5, 27, 5, 2),   DateTime.utc(2025, 6, 25, 12, 31),
    DateTime.utc(2025, 7, 24, 21, 11), DateTime.utc(2025, 8, 23, 8, 6),
    DateTime.utc(2025, 9, 21, 21, 54), DateTime.utc(2025, 10, 21, 14, 25),
    DateTime.utc(2025, 11, 20, 7, 47), DateTime.utc(2025, 12, 20, 2, 43),
    // 2026
    DateTime.utc(2026, 1, 18, 20, 52), DateTime.utc(2026, 2, 17, 13, 1),
    DateTime.utc(2026, 3, 19, 2, 23),  DateTime.utc(2026, 4, 17, 13, 51),
    DateTime.utc(2026, 5, 16, 22, 1),  DateTime.utc(2026, 6, 15, 4, 54),
    DateTime.utc(2026, 7, 14, 11, 43), DateTime.utc(2026, 8, 12, 19, 36),
    DateTime.utc(2026, 9, 11, 5, 27),  DateTime.utc(2026, 10, 10, 17, 50),
    DateTime.utc(2026, 11, 9, 8, 2),   DateTime.utc(2026, 12, 9, 1, 51),
    // 2027
    DateTime.utc(2027, 1, 7, 21, 24),  DateTime.utc(2027, 2, 6, 16, 56),
    DateTime.utc(2027, 3, 8, 10, 29),  DateTime.utc(2027, 4, 7, 1, 51),
    DateTime.utc(2027, 5, 6, 12, 58),  DateTime.utc(2027, 6, 4, 21, 40),
    DateTime.utc(2027, 7, 4, 5, 2),    DateTime.utc(2027, 8, 2, 12, 5),
    DateTime.utc(2027, 8, 31, 19, 41), DateTime.utc(2027, 9, 30, 4, 36),
    DateTime.utc(2027, 10, 29, 15, 36),DateTime.utc(2027, 11, 28, 4, 24),
    DateTime.utc(2027, 12, 27, 21, 12),
  ];

  // Verified Full Moon dates (UTC) from timeanddate.com
  static final List<DateTime> _fullMoons = [
    // 2025
    DateTime.utc(2025, 1, 13, 23, 26), DateTime.utc(2025, 2, 12, 14, 53),
    DateTime.utc(2025, 3, 14, 7, 54),  DateTime.utc(2025, 4, 13, 2, 22),
    DateTime.utc(2025, 5, 12, 18, 55), DateTime.utc(2025, 6, 11, 9, 43),
    DateTime.utc(2025, 7, 10, 22, 36), DateTime.utc(2025, 8, 9, 9, 55),
    DateTime.utc(2025, 9, 7, 20, 8),   DateTime.utc(2025, 10, 7, 5, 47),
    DateTime.utc(2025, 11, 5, 14, 19), DateTime.utc(2025, 12, 5, 0, 14),
    // 2026
    DateTime.utc(2026, 1, 3, 11, 2),   DateTime.utc(2026, 2, 1, 23, 9),
    DateTime.utc(2026, 3, 3, 12, 37),  DateTime.utc(2026, 4, 2, 4, 11),
    DateTime.utc(2026, 5, 1, 19, 23),  DateTime.utc(2026, 5, 31, 10, 45),
    DateTime.utc(2026, 6, 30, 1, 56),  DateTime.utc(2026, 7, 29, 16, 35),
    DateTime.utc(2026, 8, 28, 6, 18),  DateTime.utc(2026, 9, 26, 18, 49),
    DateTime.utc(2026, 10, 26, 5, 11), DateTime.utc(2026, 11, 24, 15, 53),
    DateTime.utc(2026, 12, 24, 2, 28),
    // 2027
    DateTime.utc(2027, 1, 22, 13, 17), DateTime.utc(2027, 2, 21, 0, 23),
    DateTime.utc(2027, 3, 22, 11, 43), DateTime.utc(2027, 4, 21, 0, 27),
    DateTime.utc(2027, 5, 20, 12, 59), DateTime.utc(2027, 6, 19, 2, 44),
    DateTime.utc(2027, 7, 18, 17, 44), DateTime.utc(2027, 8, 17, 9, 28),
    DateTime.utc(2027, 9, 16, 1, 3),   DateTime.utc(2027, 10, 15, 15, 47),
    DateTime.utc(2027, 11, 14, 4, 25), DateTime.utc(2027, 12, 13, 17, 8),
  ];

  /// Find the previous new moon before a given date
  static DateTime findPreviousNewMoon(DateTime date) {
    final utc = date.toUtc();
    for (int i = _newMoons.length - 1; i >= 0; i--) {
      if (_newMoons[i].isBefore(utc)) return _newMoons[i];
    }
    return _newMoons.first;
  }

  /// Find the next new moon after a given date
  static DateTime findNextNewMoon(DateTime date) {
    final utc = date.toUtc();
    for (final nm in _newMoons) {
      if (nm.isAfter(utc)) return nm;
    }
    return _newMoons.last;
  }

  /// Find the next full moon after a given date
  static DateTime findNextFullMoon(DateTime date) {
    final utc = date.toUtc();
    for (final fm in _fullMoons) {
      if (fm.isAfter(utc)) return fm;
    }
    return _fullMoons.last;
  }

  /// Find the previous full moon before a given date
  static DateTime findPreviousFullMoon(DateTime date) {
    final utc = date.toUtc();
    for (int i = _fullMoons.length - 1; i >= 0; i--) {
      if (_fullMoons[i].isBefore(utc)) return _fullMoons[i];
    }
    return _fullMoons.first;
  }

  /// Get moon phase (0.0 to 1.0) for a given date
  /// 0.0 = New Moon, ~0.5 = Full Moon
  static double getMoonPhase(DateTime date) {
    final utc = date.toUtc();
    final prevNew = findPreviousNewMoon(utc);
    final nextNew = findNextNewMoon(utc);
    final cycleLen = nextNew.difference(prevNew).inSeconds.toDouble();
    final daysSince = utc.difference(prevNew).inSeconds.toDouble();
    if (cycleLen <= 0) return 0;
    return daysSince / cycleLen;
  }

  /// Get moon phase name in German
  static String getPhaseName(double phase) {
    if (phase < 0.0125 || phase >= 0.9875) return 'Neumond';
    if (phase < 0.235) return 'Zunehmende Sichel';
    if (phase < 0.265) return 'Erstes Viertel';
    if (phase < 0.485) return 'Zunehmender Mond';
    if (phase < 0.515) return 'Vollmond';
    if (phase < 0.735) return 'Abnehmender Mond';
    if (phase < 0.765) return 'Letztes Viertel';
    return 'Abnehmende Sichel';
  }

  /// Get moon emoji
  static String getPhaseEmoji(double phase) {
    if (phase < 0.0625 || phase >= 0.9375) return '\u{1F311}';
    if (phase < 0.1875) return '\u{1F312}';
    if (phase < 0.3125) return '\u{1F313}';
    if (phase < 0.4375) return '\u{1F314}';
    if (phase < 0.5625) return '\u{1F315}';
    if (phase < 0.6875) return '\u{1F316}';
    if (phase < 0.8125) return '\u{1F317}';
    return '\u{1F318}';
  }

  /// Get illumination percentage
  static int getIllumination(double phase) {
    return ((1 - cos(phase * 2 * pi)) / 2 * 100).round();
  }

  /// Is the moon waxing?
  static bool isWaxing(double phase) => phase > 0.0 && phase < 0.5;

  /// Decision quality info based on moon phase
  static MoonDecisionInfo getDecisionInfo(double phase) {
    if (phase < 0.034 || phase >= 0.966) {
      return MoonDecisionInfo(
        quality: DecisionQuality.neutral, title: 'Neumond',
        shortAdvice: 'Ruhe & Planung',
        advice: 'Der Neumond ist eine Zeit der Ruhe und des Neubeginns. '
            'Planen Sie neue Projekte, aber vermeiden Sie große Entscheidungen '
            'direkt am Neumond. Warten Sie 1-2 Tage.',
        color: Colors.blueGrey, icon: Icons.nightlight_round,
        doList: [
          'Ziele setzen & To-Do-Listen schreiben',
          'Neue Projekte planen (aber noch nicht starten)',
          'Entgiftung & Fasten beginnen',
          'Wohnung aufräumen & entrümpeln',
          'Meditieren & zur Ruhe kommen',
          'Tagebuch schreiben & reflektieren',
        ],
        dontList: [
          'Wichtige Verträge unterschreiben',
          'Große Entscheidungen treffen',
          'Neue Projekte starten (1-2 Tage warten)',
          'Vorstellungsgespräche führen',
          'Wichtige Verhandlungen',
        ],
      );
    }
    if (phase >= 0.034 && phase < 0.25) {
      return MoonDecisionInfo(
        quality: DecisionQuality.good, title: 'Zunehmende Phase',
        shortAdvice: 'Gute Zeit für Entscheidungen',
        advice: 'Die zunehmende Mondphase ist ideal für neue Anfänge, '
            'Vertragsabschlüsse, Bewerbungen und wichtige Entscheidungen. '
            'Die Energie wächst - nutzen Sie diese Phase!',
        color: Colors.green, icon: Icons.trending_up,
        doList: [
          'Neue Projekte starten & lancieren',
          'Bewerbungen abschicken',
          'Neue Kontakte knüpfen & Netzwerken',
          'Geschäftsideen umsetzen',
          'Sport & Muskelaufbau (Körper nimmt besser auf)',
          'Haare schneiden (wachsen kräftiger nach)',
          'Geld anlegen & investieren',
          'Umzug planen & durchführen',
        ],
        dontList: [
          'Operationen (höherer Blutverlust)',
          'Strenge Diäten (Körper speichert mehr)',
          'Trennungen & Kündigungen',
        ],
      );
    }
    if (phase >= 0.25 && phase < 0.466) {
      return MoonDecisionInfo(
        quality: DecisionQuality.best, title: 'Stark zunehmend',
        shortAdvice: 'Beste Zeit für Entscheidungen!',
        advice: 'Dies ist die beste Phase für wichtige Entscheidungen! '
            'Verträge unterschreiben, Projekte starten, Vorstellungsgespräche. '
            'Die Energie ist auf dem Höhepunkt. Nutzen Sie diese Tage!',
        color: Colors.green.shade800, icon: Icons.star,
        doList: [
          'Verträge unterschreiben',
          'Vorstellungsgespräche & Bewerbungen',
          'Geschäftseröffnung & Produktstart',
          'Gehaltsverhandlungen führen',
          'Immobilien kaufen/mieten',
          'Hochzeit & Verlobung',
          'Prüfungen & Weiterbildungen',
          'Wichtige Präsentationen halten',
          'Finanzielle Investitionen tätigen',
        ],
        dontList: [
          'Operationen (wenn verschiebbar)',
          'Diäten beginnen',
          'Haare entfernen (wachsen schneller nach)',
        ],
      );
    }
    if (phase >= 0.466 && phase < 0.534) {
      return MoonDecisionInfo(
        quality: DecisionQuality.avoid, title: 'Vollmond',
        shortAdvice: 'Entscheidungen vermeiden!',
        advice: 'Rund um den Vollmond (ca. 18 Stunden davor und danach) '
            'sind Emotionen verstärkt und das Urteilsvermögen eingeschränkt. '
            'Verschieben Sie wichtige Entscheidungen um 1-2 Tage!',
        color: Colors.red, icon: Icons.warning_amber,
        doList: [
          'Erfolge feiern & dankbar sein',
          'Kreative Arbeit & Kunst',
          'Hautpflege (Haut nimmt Nährstoffe besser auf)',
          'Heilkräuter sammeln (stärkste Wirkung)',
          'Nachdenken über das Erreichte',
        ],
        dontList: [
          'Verträge unterschreiben',
          'Wichtige Entscheidungen treffen',
          'Vorstellungsgespräche führen',
          'Operationen & medizinische Eingriffe',
          'Streitgespräche & Konfrontationen',
          'Impulsive Käufe & Investitionen',
          'Haare bleichen oder chemisch behandeln',
          'Alkohol (stärkere Wirkung)',
        ],
      );
    }
    if (phase >= 0.534 && phase < 0.75) {
      return MoonDecisionInfo(
        quality: DecisionQuality.poor, title: 'Abnehmende Phase',
        shortAdvice: 'Nicht ideal für neue Entscheidungen',
        advice: 'Die abnehmende Phase eignet sich für Reflexion, '
            'Abschluss laufender Projekte und Loslassen von Altem. '
            'Vermeiden Sie es, neue Verträge zu unterzeichnen oder '
            'große Investitionen zu tätigen.',
        color: Colors.orange, icon: Icons.trending_down,
        doList: [
          'Laufende Projekte abschließen',
          'Operationen (weniger Blutverlust, bessere Heilung)',
          'Diäten & Entgiftungskuren starten',
          'Haare entfernen / Waxing (wachsen langsamer nach)',
          'Altlasten loslassen & aufräumen',
          'Beziehungen beenden die nicht funktionieren',
          'Schulden abzahlen & Finanzen ordnen',
          'Reinigungsarbeiten im Haushalt',
        ],
        dontList: [
          'Neue Verträge abschließen',
          'Neue Projekte starten',
          'Bewerbungen abschicken',
          'Große Investitionen tätigen',
          'Geschäftseröffnungen',
        ],
      );
    }
    return MoonDecisionInfo(
      quality: DecisionQuality.poor, title: 'Stark abnehmend',
      shortAdvice: 'Zeit für Reflexion & Abschluss',
      advice: 'Die letzte Phase vor dem Neumond ist für Introspektion, '
          'Aufräumen, Kündigen und Loslassen geeignet. '
          'Keine neuen Projekte starten. Warten Sie auf den nächsten '
          'zunehmenden Mond für neue Initiativen.',
      color: Colors.orange.shade800, icon: Icons.self_improvement,
      doList: [
        'Meditieren & Introspektion',
        'Kündigungen aussprechen',
        'Toxische Gewohnheiten ablegen',
        'Wohnung entrümpeln & Altes wegwerfen',
        'Offene Rechnungen begleichen',
        'Operationen planen (idealer Zeitpunkt)',
        'Fasten & Körper reinigen',
        'Lose Enden aus dem Monat abschließen',
      ],
      dontList: [
        'Neue Projekte oder Geschäfte starten',
        'Verträge unterschreiben',
        'Vorstellungsgespräche / Bewerbungen',
        'Große Einkäufe oder Investitionen',
        'Neue Beziehungen beginnen',
      ],
    );
  }
}

enum DecisionQuality { best, good, neutral, poor, avoid }

class MoonDecisionInfo {
  final DecisionQuality quality;
  final String title;
  final String shortAdvice;
  final String advice;
  final Color color;
  final IconData icon;
  final List<String> doList;
  final List<String> dontList;

  MoonDecisionInfo({
    required this.quality, required this.title, required this.shortAdvice,
    required this.advice, required this.color, required this.icon,
    this.doList = const [], this.dontList = const [],
  });
}

/// Shows the moon phase dialog
void showMoonPhaseDialog(BuildContext context) {
  final now = DateTime.now();
  final phase = MoonPhaseHelper.getMoonPhase(now);
  final info = MoonPhaseHelper.getDecisionInfo(phase);
  final illumination = MoonPhaseHelper.getIllumination(phase);
  final phaseName = MoonPhaseHelper.getPhaseName(phase);
  final emoji = MoonPhaseHelper.getPhaseEmoji(phase);

  final nextNewMoon = MoonPhaseHelper.findNextNewMoon(now);
  final nextFullMoon = MoonPhaseHelper.findNextFullMoon(now);

  final forecast = <_DayForecast>[];
  for (var i = 0; i < 14; i++) {
    final day = now.add(Duration(days: i));
    final dayPhase = MoonPhaseHelper.getMoonPhase(day);
    final dayInfo = MoonPhaseHelper.getDecisionInfo(dayPhase);
    final dayEmoji = MoonPhaseHelper.getPhaseEmoji(dayPhase);
    forecast.add(_DayForecast(date: day, phase: dayPhase, info: dayInfo, emoji: dayEmoji));
  }

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 620),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.indigo.shade900, Colors.indigo.shade700]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mondphase & Entscheidungen',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('$phaseName  •  $illumination% beleuchtet',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                      Text('Quelle: timeanddate.com (USNO verifiziert)',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                    ],
                  )),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Decision quality card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: info.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: info.color.withValues(alpha: 0.3)),
                      ),
                      child: Column(children: [
                        Row(children: [
                          Icon(info.icon, color: info.color, size: 28),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(info.shortAdvice, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: info.color)),
                              const SizedBox(height: 2),
                              Text('Heute: ${info.title}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          )),
                          _buildQualityBadge(info.quality),
                        ]),
                        const SizedBox(height: 12),
                        Text(info.advice, style: const TextStyle(fontSize: 13, height: 1.4)),
                        if (info.doList.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
                            const SizedBox(width: 6),
                            Text('Empfohlen:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                          ]),
                          const SizedBox(height: 4),
                          ...info.doList.map((item) => Padding(
                            padding: const EdgeInsets.only(left: 20, bottom: 2),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('• ', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                              Expanded(child: Text(item, style: const TextStyle(fontSize: 12))),
                            ]),
                          )),
                        ],
                        if (info.dontList.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            Icon(Icons.cancel, size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 6),
                            Text('Vermeiden:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                          ]),
                          const SizedBox(height: 4),
                          ...info.dontList.map((item) => Padding(
                            padding: const EdgeInsets.only(left: 20, bottom: 2),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('• ', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                              Expanded(child: Text(item, style: const TextStyle(fontSize: 12))),
                            ]),
                          )),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // Next dates
                    Row(children: [
                      Expanded(child: _buildNextDateCard('\u{1F315} Nächster Vollmond', nextFullMoon, Colors.amber.shade800)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildNextDateCard('\u{1F311} Nächster Neumond', nextNewMoon, Colors.blueGrey)),
                    ]),
                    const SizedBox(height: 20),

                    const Text('14-Tage-Vorschau', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Planen Sie Ihre Entscheidungen nach der Mondphase',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 12),

                    ...forecast.map((f) => _buildForecastRow(f, now)),

                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Legende', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),
                          _buildLegendItem(Colors.green.shade800, 'Beste Zeit', 'Verträge, Bewerbungen, neue Projekte'),
                          _buildLegendItem(Colors.green, 'Gute Zeit', 'Entscheidungen, Initiativen'),
                          _buildLegendItem(Colors.blueGrey, 'Neutral', 'Planung, aber keine großen Entscheidungen'),
                          _buildLegendItem(Colors.orange, 'Nicht ideal', 'Reflexion, Abschluss, Loslassen'),
                          _buildLegendItem(Colors.red, 'Vermeiden', 'Keine wichtigen Entscheidungen!'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildQualityBadge(DecisionQuality quality) {
  String label; Color color;
  switch (quality) {
    case DecisionQuality.best: label = 'OPTIMAL'; color = Colors.green.shade800;
    case DecisionQuality.good: label = 'GUT'; color = Colors.green;
    case DecisionQuality.neutral: label = 'NEUTRAL'; color = Colors.blueGrey;
    case DecisionQuality.poor: label = 'MEIDEN'; color = Colors.orange;
    case DecisionQuality.avoid: label = 'STOPP'; color = Colors.red;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

Widget _buildNextDateCard(String title, DateTime date, Color color) {
  final daysUntil = date.difference(DateTime.now()).inDays;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      const SizedBox(height: 4),
      Text(DateFormat('dd.MM.yyyy').format(date), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      Text(daysUntil <= 0 ? 'Heute' : 'in $daysUntil ${daysUntil == 1 ? 'Tag' : 'Tagen'}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ]),
  );
}

Widget _buildForecastRow(_DayForecast f, DateTime today) {
  final isToday = f.date.year == today.year && f.date.month == today.month && f.date.day == today.day;
  final dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  final dayName = dayNames[f.date.weekday - 1];

  return Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: isToday ? f.info.color.withValues(alpha: 0.1) : null,
      borderRadius: BorderRadius.circular(6),
      border: isToday ? Border.all(color: f.info.color.withValues(alpha: 0.3)) : null,
    ),
    child: Row(children: [
      Text(f.emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      SizedBox(width: 30, child: Text(dayName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
      SizedBox(width: 60, child: Text(
        '${f.date.day.toString().padLeft(2, '0')}.${f.date.month.toString().padLeft(2, '0')}.',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      )),
      Container(width: 8, height: 8, decoration: BoxDecoration(color: f.info.color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(f.info.shortAdvice,
          style: TextStyle(fontSize: 12, fontWeight: isToday ? FontWeight.bold : FontWeight.normal, color: f.info.color))),
      if (isToday)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(4)),
          child: const Text('HEUTE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
    ]),
  );
}

Widget _buildLegendItem(Color color, String label, String desc) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      const SizedBox(width: 8),
      Expanded(child: Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
    ]),
  );
}

class _DayForecast {
  final DateTime date;
  final double phase;
  final MoonDecisionInfo info;
  final String emoji;
  _DayForecast({required this.date, required this.phase, required this.info, required this.emoji});
}
