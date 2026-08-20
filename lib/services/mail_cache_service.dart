import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'cloud_crypto_service.dart';
import 'logger_service.dart';
import 'secure_store.dart';

/// Das Postfach bleibt lesbar, wenn die Leitung wegbricht.
///
/// Bisher ging jeder Aufruf ins Netz; fiel es aus, stand da „Keine Verbindung
/// zum Server" und ein leerer Bildschirm. Die eigenen Speedtest-Reihen sagen,
/// wie oft das vorkommt: an einem von drei Tagen ein Totalausfall unter
/// 2 Mbit/s, Latenz unter Last bis 7402 ms. Ein Postfach, das genau dann nichts
/// mehr zeigt, ist genau dann nutzlos, wenn man unterwegs ist.
///
/// ⚠️ **Verschlüsselt, und ohne Anhänge.** Die Leseansicht schreibt Anhänge
/// bewusst nie auf die Platte — durch dieses Postfach gehen Arzt-, Jobcenter-
/// und Behördenunterlagen. Ein Zwischenspeicher, der sie doch ablegt, würde
/// diese Entscheidung stillschweigend aufheben. Gespeichert werden deshalb nur
/// Kopfzeilen und der **Text** schon geöffneter Nachrichten, und auch die nur
/// AES-256-GCM-verschlüsselt unter einem Schlüssel aus [SecureStore].
class MailCacheService {
  MailCacheService._();

  static final MailCacheService instance = MailCacheService._();

  /// Eine frische, unabhängige Instanz — nur für Tests.
  ///
  /// ⚠️ Der Zwischenspeicher ist absichtlich eine einzige Instanz: zwei davon
  /// schrieben auf dieselbe Datei. Für einen Test über das NEBENEINANDER
  /// mehrerer Aufrufer braucht es aber einen unberührten Anfangszustand
  /// (`_ladevorgang == null`), und den kann `leeren()` nicht herstellen —
  /// es setzt bewusst einen bereits erledigten Ladevorgang.
  @visibleForTesting
  MailCacheService.zumTesten();

  static const _keyName = 'mail_cache_key_v1';
  static const _fileName = 'mail_cache_v1.bin';

  /// So viele Kopfzeilen je Ordner. 200 sind rund vier Bildschirmseiten und
  /// decken jeden Zeitraum ab, in dem eine Leitung ausfällt.
  static const int maxKopfProOrdner = 200;

  /// So viele Nachrichtentexte insgesamt, älteste fliegen zuerst.
  static const int maxTexte = 80;

  /// Ab hier gilt der Bestand als alt und wird als solcher angezeigt.
  static const Duration altAb = Duration(hours: 12);

  final _log = LoggerService();
  final _store = SecureStore();

  Map<String, dynamic>? _daten;

  /// Der laufende (oder erledigte) Ladevorgang. Merkt sich das FUTURE, nicht
  /// ein „schon geladen" — siehe [_lesen].
  Future<Map<String, dynamic>>? _ladevorgang;

  /// Das Ende der Schreibkette.
  Future<void>? _laufendesSchreiben;

  /// Wie viele Schreibvorgänge GERADE gleichzeitig laufen.
  ///
  /// ⚠️ Nur zum Prüfen. Ein Test, der auf eine beschädigte Datei wartet, prüft
  /// den Zufall: zwei überlappende Schreibvorgänge auf dieselbe `.tmp` gehen
  /// meistens gut aus und manchmal nicht. Die Zusage lautet aber nicht „selten
  /// kaputt", sondern „immer nur einer" — und genau das ist hier zählbar.
  @visibleForTesting
  int gleichzeitigeSchreibvorgaenge = 0;

  /// Der höchste je gleichzeitig erreichte Stand. Muss 1 bleiben.
  @visibleForTesting
  int hoechststandSchreiben = 0;

  // ── Schlüssel ─────────────────────────────────────────────────────────────

  Future<SecretKey?> _schluessel() async {
    try {
      var b64 = await _store.read(key: _keyName);
      if (b64 == null || b64.isEmpty) {
        final rnd = Random.secure();
        final bytes =
            Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
        b64 = base64Encode(bytes);
        await _store.write(key: _keyName, value: b64);
      }
      return SecretKey(base64Decode(b64));
    } catch (e) {
      // Kein Schlüssel = kein Zwischenspeicher. Das ist ein Verlust an Komfort,
      // niemals ein Grund, unverschlüsselt zu schreiben.
      _log.warning('Mail-Zwischenspeicher ohne Schlüssel: $e', tag: 'MAILCACHE');
      return null;
    }
  }

  Future<File> _datei() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  // ── Laden / Schreiben ─────────────────────────────────────────────────────

  /// Lädt den Bestand — und zwar genau EINMAL, auch bei mehreren Aufrufern.
  ///
  /// ⚠️ Der Ladevorgang wird als Future gemerkt, nicht über ein `bool`. Die
  /// erste Fassung setzte `_geladen = true` VOR dem Entschlüsseln: ein zweiter
  /// Aufrufer bekam dann die noch leere Karte, schrieb hinein — und der erste
  /// ersetzte `_daten` anschliessend komplett durch das Geladene. Der Eintrag
  /// des zweiten war weg, ohne Fehler und ohne Spur.
  ///
  /// Und das ist kein seltener Fall: `_load()` stösst das Ablegen der
  /// Ordnerliste an, die Leseansicht daneben das Ablegen der Nachricht — beide
  /// unbeaufsichtigt, beide beim ersten Öffnen des Postfachs.
  Future<Map<String, dynamic>> _lesen() {
    return _ladevorgang ??= _lesenJetzt();
  }

  Future<Map<String, dynamic>> _lesenJetzt() async {
    var daten = <String, dynamic>{'ordner': {}, 'texte': {}};
    try {
      final f = await _datei();
      if (await f.exists()) {
        final key = await _schluessel();
        if (key != null) {
          final roh = await CloudCrypto.decryptBytes(
              Uint8List.fromList(await f.readAsBytes()), key);
          final j = jsonDecode(utf8.decode(roh));
          if (j is Map) {
            daten = {
              'ordner': Map<String, dynamic>.from(j['ordner'] ?? {}),
              'texte': Map<String, dynamic>.from(j['texte'] ?? {}),
            };
          }
        }
      }
    } catch (e) {
      // Unlesbar (Schlüssel weg, Datei angerissen) = behandeln wie leer. Ein
      // Zwischenspeicher darf das Postfach niemals blockieren.
      _log.warning('Mail-Zwischenspeicher unlesbar, wird verworfen: $e',
          tag: 'MAILCACHE');
      daten = <String, dynamic>{'ordner': {}, 'texte': {}};
    }
    // ⚠️ Erst hier zuweisen, nach allen `await`. Solange nichts gesetzt ist,
    // kann auch niemand in eine halbe Karte schreiben.
    _daten = daten;
    return daten;
  }

  /// Schreibt — und immer nur einmal gleichzeitig.
  ///
  /// ⚠️ Die erste Fassung reichte dafür nicht: zwischen dem Lesen von
  /// `_laufendesSchreiben` und dem Setzen lag ein `await`, also konnte ein
  /// dritter Aufrufer den bereits erledigten Vorgang sehen und parallel
  /// loslaufen. Zwei Läufe schreiben dieselbe `.tmp` und benennen sie um —
  /// im ungünstigen Fall wird eine halb geschriebene Datei zum Bestand.
  ///
  /// Jetzt hängt jeder Schreibvorgang an der Kette des vorherigen, ohne dass
  /// dazwischen jemand einsteigen könnte.
  Future<void> _schreiben() {
    final naechster = (_laufendesSchreiben ?? Future<void>.value())
        .then((_) => _schreibenJetzt(), onError: (_) => _schreibenJetzt());
    _laufendesSchreiben = naechster;
    return naechster;
  }

  Future<void> _schreibenJetzt() async {
    gleichzeitigeSchreibvorgaenge++;
    if (gleichzeitigeSchreibvorgaenge > hoechststandSchreiben) {
      hoechststandSchreiben = gleichzeitigeSchreibvorgaenge;
    }
    try {
      final key = await _schluessel();
      if (key == null) return;
      final f = await _datei();
      final container = await CloudCrypto.encryptBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(_daten ?? {}))), key);
      // Erst daneben schreiben, dann umbenennen — ein abgebrochener Schreibvorgang
      // darf keinen halben Bestand hinterlassen.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(container, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      _log.warning('Mail-Zwischenspeicher nicht geschrieben: $e', tag: 'MAILCACHE');
    } finally {
      gleichzeitigeSchreibvorgaenge--;
    }
  }

  // ── Kopfzeilen ────────────────────────────────────────────────────────────

  /// Legt die Liste eines Ordners ab.
  ///
  /// ⚠️ Nur die **erste** Seite. Wer weiterblättert, hängt Ältere an, die beim
  /// nächsten Start ohnehin nachgeladen würden; sie zu behalten hieße, den
  /// Bestand ohne Nutzen wachsen zu lassen.
  Future<void> ordnerAblegen(String box, List<Map<String, dynamic>> nachrichten,
      {required int gesamt}) async {
    if (nachrichten.isEmpty) return;
    final d = await _lesen();
    final schlank = nachrichten
        .take(maxKopfProOrdner)
        .map(mailKopfFuerBestand)
        .toList(growable: false);
    (d['ordner'] as Map)[box] = {
      'stand': DateTime.now().toIso8601String(),
      'gesamt': gesamt,
      'nachrichten': schlank,
    };
    await _schreiben();
  }

  /// Der abgelegte Bestand eines Ordners, oder null.
  Future<({List<Map<String, dynamic>> nachrichten, int gesamt, DateTime stand})?>
      ordnerHolen(String box) async {
    final d = await _lesen();
    final e = (d['ordner'] as Map)[box];
    if (e is! Map) return null;
    final liste = (e['nachrichten'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    if (liste.isEmpty) return null;
    return (
      nachrichten: liste,
      gesamt: (e['gesamt'] as num?)?.toInt() ?? liste.length,
      stand: DateTime.tryParse('${e['stand'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  // ── Nachrichtentexte ──────────────────────────────────────────────────────

  static String _textSchluessel(String box, int uid) => '$box/$uid';

  /// Legt eine geöffnete Nachricht ab — ohne Anhangsinhalte.
  Future<void> nachrichtAblegen(
      String box, int uid, Map<String, dynamic> daten) async {
    if (uid <= 0) return;
    final d = await _lesen();
    final texte = d['texte'] as Map;

    // Die Anhangsliste bleibt (Name, Größe, Typ) — die BYTES nie. So sieht man
    // offline, dass etwas dranhängt, und bekommt beim Antippen ehrlich gesagt,
    // dass es dafür eine Leitung braucht.
    final anhaenge = (daten['attachments'] as List? ?? const [])
        .whereType<Map>()
        .map((a) => {
              'index': a['index'],
              'name': a['name'],
              'type': a['type'],
              'size': a['size'],
              'inline': a['inline'],
              'content_id': a['content_id'],
            })
        .toList();

    texte[_textSchluessel(box, uid)] = {
      'stand': DateTime.now().toIso8601String(),
      'daten': {
        for (final k in const [
          'uid', 'box', 'from', 'to', 'cc', 'subject', 'date', 'message_id',
          'in_reply_to', 'references', 'text', 'html', 'keywords', 'archived',
          'mdn_requested_by', 'mdn_original_id', 'mdn_disposition',
          'authentication_results',
        ])
          if (daten.containsKey(k)) k: daten[k],
        'attachments': anhaenge,
      },
    };

    // Ältestes zuerst hinaus, bis die Obergrenze wieder stimmt.
    if (texte.length > maxTexte) {
      final nachAlter = texte.entries.toList()
        ..sort((a, b) => '${(a.value as Map)['stand']}'
            .compareTo('${(b.value as Map)['stand']}'));
      for (var i = 0; i < nachAlter.length - maxTexte; i++) {
        texte.remove(nachAlter[i].key);
      }
    }
    await _schreiben();
  }

  /// Die abgelegte Nachricht, oder null.
  Future<({Map<String, dynamic> daten, DateTime stand})?> nachrichtHolen(
      String box, int uid) async {
    final d = await _lesen();
    final e = (d['texte'] as Map)[_textSchluessel(box, uid)];
    if (e is! Map || e['daten'] is! Map) return null;
    return (
      daten: Map<String, dynamic>.from(e['daten'] as Map),
      stand: DateTime.tryParse('${e['stand'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Beim Abmelden. Der Bestand gehört zum Konto, nicht zum Gerät.
  Future<void> leeren() async {
    // ⚠️ Auf einen ERLEDIGTEN Ladevorgang setzen, nicht auf null: sonst läse
    // der nächste Aufrufer die eben gelöschte Datei wieder ein, und das
    // Abmelden hätte den Bestand nicht entfernt, sondern nur kurz versteckt.
    final leer = <String, dynamic>{'ordner': {}, 'texte': {}};
    _daten = leer;
    _ladevorgang = Future.value(leer);
    try {
      final f = await _datei();
      if (await f.exists()) await f.delete();
      await _store.delete(key: _keyName);
    } catch (_) {/* weg ist weg, auch wenn das Löschen scheitert */}
  }
}

/// Die Felder, die eine Listenzeile im Zwischenspeicher behalten darf.
///
/// ⚠️ Es ist eine **Positivliste**. `delivery` und `korrespondenz` stehen
/// bewusst NICHT darin: beide sind Momentaufnahmen des Servers. Abgelegt würden
/// sie beim nächsten Start als gesicherter Zustand gelesen — die Anzeige „liegt
/// in der Korrespondenz" wäre dann eine Behauptung über etwas, das nie geprüft
/// wurde. Und `box` fehlt ebenfalls: der Bestand ist je Ordner abgelegt, ein
/// mitgeschleppter zweiter Ordnername könnte ihm nur widersprechen.
const List<String> kMailBestandFelder = [
  'uid', 'from', 'to', 'cc', 'subject', 'message_id', 'date', 'size',
  'seen', 'flagged', 'answered', 'draft', 'has_attachment',
  'is_report', 'mdn_requested_by', 'archived',
];

/// Wirft aus einer Listenzeile alles weg, was nicht in den Bestand gehört.
Map<String, dynamic> mailKopfFuerBestand(Map<String, dynamic> m) => {
      for (final k in kMailBestandFelder)
        if (m.containsKey(k)) k: m[k],
    };

/// Wie alt darf ein Bestand sein, bevor man es dazusagt.
String mailStandText(DateTime stand) {
  final alter = DateTime.now().difference(stand);
  if (alter.inMinutes < 2) return 'gerade eben';
  if (alter.inMinutes < 60) return 'vor ${alter.inMinutes} Minuten';
  if (alter.inHours < 24) {
    return 'vor ${alter.inHours} Stunde${alter.inHours == 1 ? '' : 'n'}';
  }
  return 'vor ${alter.inDays} Tag${alter.inDays == 1 ? '' : 'en'}';
}
