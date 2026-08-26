import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Sorgt dafür, dass die App unter Linux nur EINMAL läuft.
///
/// ⚠️ WARUM DAS KEINE FEINHEIT IST.
/// Gemeldet aus dem Betrieb: „wenn ich Nachrichten bekomme, erscheinen vier
/// Benachrichtigungen" und „es erscheinen drei Kästchen mit derselben
/// Nachricht, eines nach dem anderen". Das Protokoll vom 26.08.2026 zeigt es
/// schwarz auf weiss — dieselbe `message_id` 29175 kommt in derselben Sekunde
/// mehrfach an, einmal davon an einer App der Version 6.159.0, während
/// gleichzeitig 6.160.0 lief:
///
///   21:59:07 | linux | 6.160.0 | message_id 29175
///   21:59:07 | linux | 6.160.0 | message_id 29175
///   21:59:07 | linux | 6.159.0 | message_id 29175
///
/// Also mehrere Prozesse gleichzeitig, jeder mit eigenem WebSocket, eigener
/// Benachrichtigung und eigenem Blitz-Fenster. Für Windows gab es diesen
/// Schutz längst ([WindowsSingleInstance] in `main.dart`), für Linux nie —
/// und dort fällt es besonders auf, weil das Fenster in den Systemabschnitt
/// verschwindet statt sich zu schliessen: ein zweiter Start sieht aus wie
/// „die App war zu".
///
/// ⚠️ DIES IST DIE ZWEITE REIHE, NICHT DIE ERSTE.
/// Die Eindeutigkeit besorgt seit dem 26.08.2026 GTK selbst: in
/// `linux/runner/my_application.cc` ist `G_APPLICATION_NON_UNIQUE` entfallen,
/// und `my_application_activate` holt das vorhandene Fenster nach vorn. Das
/// ist der vorgesehene Weg und greift, bevor Flutter überhaupt hochfährt.
///
/// Diese Klasse deckt den Fall ab, in dem GTK das NICHT kann: ohne
/// Sitzungsbus (D-Bus) registriert sich jeder Prozess als der erste, und die
/// Eindeutigkeit fällt still aus — genau die Art von Ausfall, die niemand
/// bemerkt, bis wieder vier Töne gleichzeitig kommen. Kostet im Normalfall
/// nichts: läuft GTKs Sperre, kommt dieser Code im zweiten Prozess gar nicht
/// mehr zur Ausführung.
///
/// ⚠️ Ohne Zusatzpaket. Ein Unix-Socket ist gleichzeitig Schloss UND
/// Nachrichtenweg: wer ihn binden kann, ist der erste; wer nicht, meldet dem
/// Ersten „zeig dich" und beendet sich.
class EinzelneInstanz {
  EinzelneInstanz._();

  static ServerSocket? _lauscher;

  /// Pfad des Sockets. Im Cache-Verzeichnis des Benutzers, nicht in `/tmp` —
  /// dort läge er für alle Konten des Rechners sichtbar, und zwei Benutzer
  /// desselben Rechners dürfen die App sehr wohl gleichzeitig starten.
  static Future<String> _socketPfad() async {
    final cache = await getApplicationCacheDirectory();
    return '${cache.path}/einzelne-instanz.sock';
  }

  /// `true` = weitermachen, wir sind die einzige Instanz.
  /// `false` = eine andere läuft schon, sie wurde nach vorn geholt; dieser
  /// Prozess soll sich sofort beenden.
  ///
  /// Wirft nie. Im Zweifel `true` — lieber zwei Fenster als gar keins.
  static Future<bool> beanspruchen({required void Function() nachVorne}) async {
    if (!Platform.isLinux) return true;
    try {
      final pfad = await _socketPfad();
      final adresse = InternetAddress(pfad, type: InternetAddressType.unix);

      Future<bool> binden() async {
        _lauscher = await ServerSocket.bind(adresse, 0);
        _lauscher!.listen((verbindung) {
          // Inhalt ist gleichgültig — allein die Verbindung heisst „hier ist
          // noch einer, hol dich nach vorn".
          verbindung.destroy();
          nachVorne();
        });
        return true;
      }

      try {
        return await binden();
      } on SocketException {
        // Belegt — entweder läuft wirklich eine, oder es ist eine Leiche.
      }

      try {
        final draht = await Socket.connect(adresse, 0,
            timeout: const Duration(seconds: 2));
        draht.destroy();
        debugPrint('[INSTANZ] Läuft bereits — Fenster wird dort nach vorn geholt');
        return false;
      } on SocketException {
        // Niemand hört zu: der Socket stammt von einem abgestürzten Lauf.
        // ⚠️ Erst JETZT löschen, nie vorher — ein Löschen auf Verdacht würde
        // dem laufenden Prozess das Schloss unter den Füssen wegziehen und
        // genau den Zustand herstellen, den diese Klasse verhindern soll.
        try {
          final datei = File(pfad);
          if (datei.existsSync()) datei.deleteSync();
        } catch (_) {/* dann eben nicht */}
        return await binden();
      }
    } catch (e) {
      debugPrint('[INSTANZ] Prüfung fehlgeschlagen ($e) — Start wird fortgesetzt');
      return true;
    }
  }
}
