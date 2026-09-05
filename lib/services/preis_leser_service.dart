import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'device_key_service.dart';
import '../utils/preis_link.dart';

/// Liest die überwachten Produktseiten — auf dem Linux-Rechner, mit dem
/// Chromium, der dort ohnehin installiert ist.
///
/// ⚠️ WARUM NICHT AUF DEM SERVER
/// Der Server kann diese Seiten nicht lesen (gemessen am 05.09.2026):
/// dm liefert 11 kB JS-Gerüst ohne Preis, Rossmann eine Seite „Client
/// Challenge". Ein echter Browser sieht bei allen dreien dasselbe saubere
/// schema.org/Product. Auf dem Server müsste dafür Chromium installiert
/// werden — auf der Maschine, die Mail, API und die Mitgliederdaten trägt.
/// Hier ist er schon da.
///
/// ⚠️ Dieselbe Bauart wie TerminSmsGatewayService und AnrufGatewayService,
/// und aus demselben Grund: der Server hat kein Gerät, das die Arbeit tun
/// kann, also holt sich das Gerät die Arbeit ab.
class PreisLeserService {
  PreisLeserService._();
  static final PreisLeserService _i = PreisLeserService._();
  factory PreisLeserService() => _i;

  static const _letzterLaufKey = 'preise_letzter_lauf';

  /// Wie lange eine einzelne Seite dauern darf.
  ///
  /// Gemessen 18–29 s je Seite (dm 29, Rossmann 27, Müller 18). 90 s lässt
  /// Luft für eine langsame Leitung, ohne dass ein hängender Browser den
  /// ganzen Lauf blockiert.
  static const _seiteTimeout = Duration(seconds: 90);

  /// Wie lange der Browser auf nachgeladene Inhalte wartet.
  ///
  /// ⚠️ Ohne das steht bei dm gar nichts auf der Seite — der Preis wird per
  /// JavaScript nachgeholt. 15 s war in allen Messungen ausreichend.
  static const _virtualTimeMs = 15000;

  bool _laeuft = false;

  /// Der Fortschritt für den Bildschirm. Niemand muss zusehen; wer zusieht,
  /// soll aber nicht raten müssen, ob noch etwas passiert.
  final ValueNotifier<String?> fortschritt = ValueNotifier<String?>(null);

  /// Nur dort, wo es einen Browser gibt.
  ///
  /// ⚠️ Bewusst KEIN Rückfall auf einen einfachen Abruf, wenn Chromium fehlt:
  /// der käme bei zwei von drei Märkten mit einer Seite ohne Preis zurück,
  /// und das sähe wie ein defektes Produkt aus statt wie ein fehlendes
  /// Werkzeug.
  static String? chromiumPfad() {
    if (!Platform.isLinux) return null;
    const kandidaten = [
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/snap/bin/chromium',
      '/var/lib/flatpak/exports/bin/org.chromium.Chromium',
    ];
    for (final p in kandidaten) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  static bool get verfuegbar => chromiumPfad() != null;

  /// Höchstens einmal am Tag von selbst — angestoßen beim Start und aus dem
  /// Bildschirm. Kein eigener Zeitgeber: der Rechner läuft nicht durch, und
  /// ein Wecker, der nur bei laufender App tickt, verspricht mehr als er hält.
  Future<void> laufWennFaellig() async {
    if (!verfuegbar) return;
    final prefs = await SharedPreferences.getInstance();
    final heute = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString(_letzterLaufKey) == heute) return;
    final n = await lauf();
    // ⚠️ Der Merker wird nur bei einem Lauf gesetzt, der auch etwas erreicht
    // hat. Sonst würde ein Start ohne Netz den Tag verbrauchen, und der
    // Wächter meldete abends zu Recht Schweigen — verursacht von uns.
    if (n >= 0) await prefs.setString(_letzterLaufKey, heute);
  }

  /// Ein Durchgang. Gibt die Zahl gelesener Produkte zurück, -1 bei einem
  /// Fehlschlag, der den ganzen Lauf betrifft (kein Netz, keine Berechtigung).
  Future<int> lauf() async {
    final chrom = chromiumPfad();
    if (chrom == null) return -1;
    if (_laeuft) return 0;
    _laeuft = true;
    var gelesen = 0;

    try {
      final geraet = DeviceKeyService().deviceId;
      if (geraet == null || geraet.isEmpty) return -1;

      final api = ApiService();
      final antwort = await api.preiseAction({'action': 'queue', 'geraet': geraet});
      if (antwort['success'] != true) return -1;

      final jobs = (antwort['jobs'] as List?) ?? const [];
      if (jobs.isEmpty) {
        fortschritt.value = null;
        return 0;
      }

      for (var i = 0; i < jobs.length; i++) {
        final job = jobs[i] as Map<String, dynamic>;
        final id = job['id'] as int;
        final url = job['url'] as String;
        fortschritt.value = '${i + 1}/${jobs.length} · ${job['haendler_name'] ?? ''}';

        try {
          final html = await _rendern(chrom, url);
          final lesung = preisAusDom(html);
          if (lesung == null || !lesung.brauchbar) {
            // ⚠️ Der Grund gehört in den Bericht. „nicht gelesen" allein
            // lässt später niemanden unterscheiden, ob der Link tot ist oder
            // der Browser klemmte.
            await api.preiseAction({
              'action': 'report',
              'id': id,
              'geraet': geraet,
              'fehler': html.toLowerCase().contains('client challenge')
                  ? 'Seite zeigt eine Bot-Abfrage'
                  : 'Kein Preis auf der Seite gefunden',
            });
            continue;
          }
          final r = await api.preiseAction({
            'action': 'report',
            'id': id,
            'geraet': geraet,
            ...lesung.alsBericht(),
          });
          if (r['success'] == true) gelesen++;
        } catch (e) {
          await api.preiseAction({
            'action': 'report',
            'id': id,
            'geraet': geraet,
            'fehler': e.toString().substring(0, e.toString().length.clamp(0, 200)),
          });
        }
      }
      return gelesen;
    } catch (e) {
      debugPrint('[Preise] Lauf fehlgeschlagen: $e');
      return -1;
    } finally {
      _laeuft = false;
      fortschritt.value = null;
    }
  }

  /// Liest EINEN Link sofort — für „Produkt hinzufügen", damit der Nutzer
  /// sieht, was gefunden wurde, bevor er speichert.
  Future<PreisLesung?> einmalLesen(String url) async {
    final chrom = chromiumPfad();
    if (chrom == null) return null;
    try {
      return preisAusDom(await _rendern(chrom, url));
    } catch (_) {
      return null;
    }
  }

  Future<String> _rendern(String chromium, String url) async {
    // ⚠️ Ein FRISCHES Profil je Seite. Ein wiederverwendetes hat den
    // Plattencache, und ab der zweiten Runde käme der Preis von gestern
    // zurück — als „unverändert", ohne dass irgendetwas fehlschlägt.
    final profil = await Directory.systemTemp.createTemp('icd_preis_');
    try {
      final p = await Process.run(
        chromium,
        [
          '--headless',
          '--disable-gpu',
          // ⚠️ KEIN --no-sandbox. Hier wird eine fremde Seite gerendert;
          // der Sandkasten ist genau dafür da. Als gewöhnlicher Benutzer
          // läuft Chromium damit einwandfrei (gemessen).
          '--user-data-dir=${profil.path}',
          '--disable-extensions',
          '--disable-background-networking',
          '--virtual-time-budget=$_virtualTimeMs',
          '--dump-dom',
          url,
        ],
        stdoutEncoding: const SystemEncoding(),
      ).timeout(_seiteTimeout);
      return p.stdout as String? ?? '';
    } finally {
      try {
        await profil.delete(recursive: true);
      } catch (_) {}
    }
  }
}
