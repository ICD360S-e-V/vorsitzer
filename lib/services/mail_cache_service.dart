import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey;
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
  bool _geladen = false;
  Future<void>? _laufendesSchreiben;

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

  Future<Map<String, dynamic>> _lesen() async {
    if (_geladen && _daten != null) return _daten!;
    _geladen = true;
    _daten = <String, dynamic>{'ordner': {}, 'texte': {}};
    try {
      final f = await _datei();
      if (!await f.exists()) return _daten!;
      final key = await _schluessel();
      if (key == null) return _daten!;
      final roh = await CloudCrypto.decryptBytes(
          Uint8List.fromList(await f.readAsBytes()), key);
      final j = jsonDecode(utf8.decode(roh));
      if (j is Map) {
        _daten = {
          'ordner': Map<String, dynamic>.from(j['ordner'] ?? {}),
          'texte': Map<String, dynamic>.from(j['texte'] ?? {}),
        };
      }
    } catch (e) {
      // Unlesbar (Schlüssel weg, Datei angerissen) = behandeln wie leer. Ein
      // Zwischenspeicher darf das Postfach niemals blockieren.
      _log.warning('Mail-Zwischenspeicher unlesbar, wird verworfen: $e',
          tag: 'MAILCACHE');
      _daten = <String, dynamic>{'ordner': {}, 'texte': {}};
    }
    return _daten!;
  }

  /// Schreibt im Hintergrund und immer nur einmal gleichzeitig.
  Future<void> _schreiben() async {
    final vorher = _laufendesSchreiben;
    if (vorher != null) await vorher;
    _laufendesSchreiben = _schreibenJetzt();
    await _laufendesSchreiben;
    _laufendesSchreiben = null;
  }

  Future<void> _schreibenJetzt() async {
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
    _daten = <String, dynamic>{'ordner': {}, 'texte': {}};
    _geladen = true;
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
