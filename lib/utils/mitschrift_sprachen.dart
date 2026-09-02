/// Welche Sprachen die Live-Mitschrift kann — und wie die eine je Gespräch
/// gewählt wird.
///
/// 🔴 EINE FALSCHE SPRACHE IST SCHLIMMER ALS KEINE MITSCHRIFT.
/// Auf dem Server gemessen: rumänische Rede durch das deutsche Modell ergibt
/// 99,3 % Wortfehler — aber als flüssige deutsche Wörter, die nie gesagt
/// wurden („wohne seo ab was so nen libretto der programmierer"). Wer den Text
/// liest, um das Gespräch zu verstehen, merkt daran nichts. Deshalb wird eine
/// Sprache ohne Modell nicht heimlich durch Deutsch ersetzt, sondern
/// abgewiesen.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Sprachen, für die auf dem Server ein Modell liegt.
///
/// ⚠️ Diese Menge ist an den Server gekoppelt (`ASR_MODELLE` in
/// `vosk-asr.service` plus `ASR_RO_MODELL`). Steht hier eine Sprache, die
/// dort fehlt, weist der Server die Verbindung mit „Sprache nicht verfügbar"
/// ab — sichtbar, nicht still. Umgekehrt bliebe ein Modell auf dem Server
/// ungenutzt.
///
/// Am Telefonband gemessene Wortfehler: de 0,0 % · en 0,0 % · ro 22,6 %.
const Set<String> kMitschriftSprachen = {'de', 'en', 'ro'};

/// Womit begonnen wird, wenn über den Anschluss nichts bekannt ist.
///
/// ⚠️ Deutsch, weil die grosse Mehrheit der Gespräche mit Ämtern, Kassen und
/// Praxen geführt wird — nicht, weil es die „Hauptsprache" wäre.
const String kMitschriftStandard = 'de';

/// Bringt eine Sprachangabe auf die Menge oben — oder gibt `null`.
///
/// Nimmt auch `de-DE`, `RO`, `ro_RO` an; alles andere ist `null`, und `null`
/// heisst „dafür haben wir kein Modell", nicht „Deutsch".
String? mitschriftSprache(String? roh) {
  final s = (roh ?? '').trim().toLowerCase();
  if (s.isEmpty) return null;
  final kurz = s.split(RegExp(r'[-_]')).first;
  return kMitschriftSprachen.contains(kurz) ? kurz : null;
}

/// Was für dieses Gespräch benutzt wird.
///
/// ⚠️ Die REIHENFOLGE ist die eigentliche Aussage:
/// 1. was der Vorsitzende bei dieser Nummer zuletzt selbst gewählt hat,
/// 2. der Vorschlag des Servers aus `users.preferred_language`,
/// 3. Deutsch.
///
/// Der Vorschlag steht bewusst NICHT an erster Stelle: `preferred_language`
/// ist die Sprache der Anwendung, nicht nachweislich die des Telefonats. Ein
/// Mitglied mit rumänischer Oberfläche kann am Telefon Deutsch sprechen.
/// Deshalb schlägt eine einmal getroffene Wahl den Vorschlag dauerhaft — so
/// korrigiert sich eine falsche Vermutung nach genau einem Griff.
String mitschriftSpracheWaehlen({String? gemerkt, String? vorschlag}) =>
    mitschriftSprache(gemerkt) ??
    mitschriftSprache(vorschlag) ??
    kMitschriftStandard;

/// Merkt sich je Anschluss, welche Sprache zuletzt benutzt wurde.
///
/// ⚠️ Gespeichert wird der HASH der Nummer, nicht die Nummer. In den
/// Einstellungen liegt sonst mit der Zeit eine offene Liste aller Anschlüsse,
/// mit denen der Verein telefoniert hat — unverschlüsselt, und für eine
/// Einstellung, die den Klartext gar nicht braucht.
class MitschriftSprachwahl {
  static const _praefix = 'mitschrift_sprache_';

  /// Nur die Ziffern zählen: `+49 731 …`, `0731…` und `0049731…` sind
  /// derselbe Anschluss, und drei Einträge dafür wären drei Vermutungen.
  static String schluessel(String nummer) {
    var z = nummer.replaceAll(RegExp(r'\D'), '');
    if (z.isEmpty) return '';
    if (z.startsWith('0049')) {
      z = '49${z.substring(4)}';
    } else if (z.startsWith('0')) {
      z = '49${z.substring(1)}';
    }
    return _praefix + sha256.convert(utf8.encode(z)).toString().substring(0, 24);
  }

  static Future<String?> gemerkt(String nummer) async {
    final k = schluessel(nummer);
    if (k.isEmpty) return null;
    try {
      return (await SharedPreferences.getInstance()).getString(k);
    } catch (_) {
      // Eine Einstellung, die sich nicht lesen lässt, darf die Mitschrift
      // nicht verhindern — dann gilt eben der Vorschlag.
      return null;
    }
  }

  static Future<void> merken(String nummer, String sprache) async {
    final k = schluessel(nummer);
    final s = mitschriftSprache(sprache);
    if (k.isEmpty || s == null) return;
    try {
      await (await SharedPreferences.getInstance()).setString(k, s);
    } catch (_) {
      // Nicht schlimm: dann wird beim nächsten Mal wieder vorgeschlagen.
    }
  }
}

/// Der Name der Sprache, wie er auf dem Schirm steht.
String mitschriftSpracheName(String s) => switch (s) {
      'de' => 'Deutsch',
      'en' => 'Englisch',
      'ro' => 'Rumänisch',
      _ => s.toUpperCase(),
    };
