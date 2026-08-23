import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Unangesehene verpasste Anrufe aus der Antwort von `sipgate_manage.php`.
///
/// `null`, wenn die Antwort die Zahl gar nicht nennt — das ist etwas anderes
/// als „null verpasst" und darf ein bestehendes Abzeichen nicht löschen.
///
/// ⚠️ Nimmt `num`, nicht `int` — aus demselben Grund wie beim Fax: PHP schickt
/// eine Zahl, aber ob sie als `3` oder `3.0` durch `json_encode` kommt, hängt
/// davon ab, wie sie entstanden ist, und ein `as int` auf einem `double` wirft
/// erst im Release-Build beim Benutzer.
int? anrufVerpassteAusAntwort(Map<String, dynamic> antwort) {
  final n = antwort['verpasst_ungesehen'];
  if (n is num) return n < 0 ? 0 : n.toInt();
  return null;
}

/// Verpasste eingehende Anrufe, die noch niemand abgehakt hat — die Zahl am
/// Telefonsymbol in der Kopfleiste.
///
/// ⚠️ WARUM ES DAS BRAUCHT
/// Gemessen am 23.08.2026: **58 verpasste eingehende Anrufe in zehn Tagen**,
/// jeden Tag zwischen einem und zwanzig. Zu sehen waren sie ausschliesslich
/// im Verlauf innerhalb des sipgate-Bildschirms — kein Abzeichen, keine
/// Meldung im Nachhinein. Wer nicht neben dem Tablet stand, erfuhr nichts.
/// Dieselbe Lücke wie beim Fax, nur dass ein Anruf zurückgerufen werden will.
///
/// ⚠️ DER BLINDE FLECK, UND WARUM ER NICHT ZU SCHLIESSEN IST
/// Beim Fax holt ein Cron die Liste bei sipgate ab. Für Anrufe geht das nicht:
/// am 23.08.2026 gemessen liefert `GET /history?types=CALL` auf diesem Konto
/// **null** Positionen (`types=VOICEMAIL` ebenfalls), während `/history` ohne
/// Filter acht FAX-Positionen zurückgibt — auf sipgate neo ist der
/// Gesprächsverlauf zu den Channel Events gewandert.
///
/// Gezählt wird deshalb, was **dieses Gerät mitbekommen hat**. Ein Anruf, der
/// eintrifft während das Tablet aus oder nicht angemeldet ist, steht nirgends
/// bei uns. Der sipgate-Bildschirm schreibt das hin; ein Abzeichen, das sich
/// für vollständig ausgibt, wäre schlimmer als eines, das seine Grenze nennt.
///
/// ⚠️ Gezählt wird **allein der Eingang**, und `abgelehnt` zählt nicht: einen
/// Anruf wegzudrücken ist eine Entscheidung, kein Versäumnis.
class AnrufBadgeService {
  static final AnrufBadgeService _instance = AnrufBadgeService._internal();
  factory AnrufBadgeService() => _instance;
  AnrufBadgeService._internal();

  final ApiService _api = ApiService();

  /// 0 heisst „nichts offen", nicht „unbekannt" — bei einem Fehler bleibt der
  /// letzte bekannte Stand stehen.
  final ValueNotifier<int> verpasst = ValueNotifier<int>(0);

  bool _laeuft = false;
  Timer? _takt;

  /// ⚠️ Fünf Minuten, derselbe Takt wie Fax und Postfach — und aus demselben
  /// gemessenen Grund kein kürzerer: die App hat sich schon einmal über Nacht
  /// am Dauertakt leergezogen (5.176 Anfragen/h im nginx-Log). Zwölf Anfragen
  /// je Stunde sind kein Dauertakt, und die Gegenseite ist ein `COUNT(*)` auf
  /// einem Index.
  ///
  /// Hier gibt es zusätzlich keinen abholenden Cron, hinter dem man
  /// zurückbleiben könnte: die Zeile entsteht auf diesem Gerät. Der wirkliche
  /// Sofortweg ist ohnehin die ntfy-Meldung, die der Server beim Übergang nach
  /// `verpasst` verschickt — dieses Abzeichen ist das, was danach stehen
  /// bleibt.
  static const Duration taktweite = Duration(minutes: 5);

  void start() {
    _takt ??= Timer.periodic(taktweite, (_) => aktualisieren());
  }

  void stop() {
    _takt?.cancel();
    _takt = null;
  }

  /// ⚠️ Eigene Aktion `verpasst_zaehler`, nicht `list_anrufe`. Die Liste
  /// entschlüsselt vier Felder je Zeile und schlägt für jede namenlose Nummer
  /// im Rückwärtsverzeichnis nach; für eine Zahl, die zwölfmal in der Stunde
  /// geholt wird, wäre das Arbeit für nichts.
  Future<void> aktualisieren() async {
    if (_laeuft) return;
    _laeuft = true;
    try {
      final res = await _api.sipgateAction({'action': 'verpasst_zaehler'});
      if (res['success'] != true) {
        _log.warning('Anruf-Abzeichen nicht lesbar: ${res['message'] ?? ''}',
            tag: 'SIPGATE');
        return;
      }
      uebernehmen(res);
    } catch (e) {
      _log.warning('Anruf-Abzeichen fehlgeschlagen: $e', tag: 'SIPGATE');
    } finally {
      _laeuft = false;
    }
  }

  /// Übernimmt einen Stand, den ein anderer Aufruf ohnehin gerade mitgebracht
  /// hat — `list_anrufe` und `anruf_gesehen` liefern die Zahl mit. Spart eine
  /// zweite Anfrage und lässt das Abzeichen sofort stimmen, statt erst beim
  /// nächsten Takt.
  void uebernehmen(Map<String, dynamic> antwort) {
    final n = anrufVerpassteAusAntwort(antwort);
    // null heisst „die Antwort nennt die Zahl nicht" — dann ist der letzte
    // bekannte Stand ehrlicher als eine erfundene 0.
    if (n != null) verpasst.value = n;
  }
}
