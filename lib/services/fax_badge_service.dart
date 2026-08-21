import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Ungelesene Faxe im Eingang aus der Antwort von `sipgate_fax.php`.
///
/// `null`, wenn die Antwort die Zahl gar nicht nennt — das ist etwas anderes
/// als „null ungelesen" und darf ein bestehendes Abzeichen nicht löschen.
///
/// ⚠️ Nimmt `num`, nicht `int`. PHP schickt eine Zahl, aber ob sie als `12`
/// oder `12.0` durch `json_encode` kommt, hängt davon ab, wie sie entstanden
/// ist — ein `as int` auf einem `double` wirft, und zwar erst im
/// Release-Build beim Benutzer.
int? faxUngeleseneAusAntwort(Map<String, dynamic> antwort) {
  final n = antwort['ungelesen'];
  if (n is num) return n < 0 ? 0 : n.toInt();
  return null;
}

/// Eingegangene, noch nicht angesehene Faxe — die Zahl am Faxsymbol im Kopf.
///
/// ⚠️ WARUM ES DAS BRAUCHT
/// Eingehende Faxe holt ein Cron alle fünf Minuten von sipgate ab und meldet
/// sie per ntfy. Wer die Meldung wegwischt oder das Telefon stummgeschaltet
/// hat, erfährt vom Fax **gar nichts** — in der App selbst gab es kein
/// einziges Zeichen dafür. Und sipgate löscht seinen Verlauf nach 30 Tagen.
///
/// ⚠️ Gezählt wird **allein der Eingang**. Ein gesendetes Fax hat der Mensch
/// selbst abgeschickt; es „ungelesen" zu nennen ergäbe kein Bild, sondern ein
/// Abzeichen, das nie erlischt — und dann fällt das echte auch nicht mehr auf.
/// Dieselbe Überlegung wie beim Postfach, wo Junk und Entwürfe draußen bleiben.
class FaxBadgeService {
  static final FaxBadgeService _instance = FaxBadgeService._internal();
  factory FaxBadgeService() => _instance;
  FaxBadgeService._internal();

  final ApiService _api = ApiService();

  /// Ungelesene Faxe im Eingang. 0 heißt „nichts Ungelesenes", nicht
  /// „unbekannt" — bei einem Fehler bleibt der letzte bekannte Stand stehen.
  final ValueNotifier<int> ungelesen = ValueNotifier<int>(0);

  bool _laeuft = false;
  Timer? _takt;

  /// ⚠️ Bewusst groß, und aus einem gemessenen Grund: die App hat sich schon
  /// einmal über Nacht am Dauertakt leergezogen (5.176 Anfragen/h im
  /// nginx-Log). Zehn Minuten sind sechs Anfragen in der Stunde, und die
  /// Gegenseite ist ein `COUNT(*)` auf einem Index.
  ///
  /// ⚠️ Länger als beim Postfach (fünf Minuten), weil der abholende Cron
  /// selbst nur alle fünf Minuten läuft — schneller zu fragen könnte gar
  /// nichts Neues finden.
  static const Duration taktweite = Duration(minutes: 10);

  /// Läuft, solange das Dashboard steht.
  void start() {
    _takt ??= Timer.periodic(taktweite, (_) => aktualisieren());
  }

  void stop() {
    _takt?.cancel();
    _takt = null;
  }

  /// Eine Anfrage, absichtlich kein Dauer-Polling. Aufgerufen beim Start, beim
  /// Aufwecken und nach dem Verlassen des Faxbildschirms — also immer dann,
  /// wenn sich der Stand überhaupt geändert haben kann.
  ///
  /// ⚠️ Eigene Aktion `ungelesen`, nicht `list`. `list` entschlüsselt vier
  /// Felder je Zeile und fragt zweimal das Dateisystem; für eine Zahl, die
  /// sechsmal in der Stunde geholt wird, wäre das Arbeit für nichts.
  Future<void> aktualisieren() async {
    if (_laeuft) return;
    _laeuft = true;
    try {
      final res = await _api.sipgateFaxAction({'action': 'ungelesen'});
      if (res['success'] != true) {
        // ⚠️ Kein Fehler im Log, wenn schlicht kein Fax-Zugang eingerichtet
        // ist: das ist der Normalzustand vor der Einrichtung und würde sonst
        // sechsmal je Stunde eine Warnung schreiben.
        final grund = '${res['message'] ?? ''}';
        if (!grund.contains('Zugang')) {
          _log.warning('Fax-Abzeichen nicht lesbar: $grund', tag: 'FAX');
        }
        return;
      }
      final n = faxUngeleseneAusAntwort(res);
      // null heißt „die Antwort nennt die Zahl nicht" — dann ist der letzte
      // bekannte Stand ehrlicher als eine erfundene 0.
      if (n != null) ungelesen.value = n;
    } catch (e) {
      _log.warning('Fax-Abzeichen fehlgeschlagen: $e', tag: 'FAX');
    } finally {
      _laeuft = false;
    }
  }

  /// Übernimmt einen Stand, den der Faxbildschirm ohnehin gerade geladen hat.
  /// Spart die zweite Anfrage und hält das Abzeichen synchron, während jemand
  /// im Verlauf Faxe öffnet.
  void setzen(int wert) {
    ungelesen.value = wert < 0 ? 0 : wert;
  }
}
