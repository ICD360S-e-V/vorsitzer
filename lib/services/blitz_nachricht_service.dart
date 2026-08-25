import 'dart:io';

import '../models/blitz_nachricht.dart';
import 'blitz_fenster_steuerung.dart';
import 'logger_service.dart';
import 'notification_service.dart';
import 'platform_service.dart';
import 'rdp_nur_modus.dart';

/// Der Blitz: eine eingehende Nachricht legt sich von selbst mitten auf den
/// Bildschirm, mit Antwortfeld — statt Benachrichtigung ➜ Taskleiste ➜
/// Chat-Symbol ➜ Mitglied anklicken.
///
/// Diese Klasse ist die EINZIGE Stelle, die entscheidet, wie eine eingehende
/// Nachricht auffällt. Sie wird aus [ChatService] gerufen, und zwar genau
/// dort, wo vorher die Benachrichtigung stand — dadurch gelten die dortigen
/// Filter (eigene Nachricht, stummgeschaltete Unterhaltung) unverändert
/// weiter, ohne dass sie hier ein zweites Mal nachgebaut werden müssten.
/// Zwei Abonnenten desselben Stroms hätten sonst zwangsläufig zwei
/// Wahrheiten.
class BlitzNachrichtService {
  BlitzNachrichtService._();
  static final BlitzNachrichtService instanz = BlitzNachrichtService._();

  final _log = LoggerService();

  bool _bereit = false;

  /// Gemerkt, weil [RdpNurModus.istAn] auf die Platte greift und hier
  /// mehrmals pro Minute gefragt würde.
  bool _kiosk = false;

  /// Vom Benutzer abschaltbar (Einstellungen). Standard: an.
  bool aktiv = true;

  /// Die zuletzt gemeldete Nachricht je Unterhaltung.
  ///
  /// ⚠️ Nur im Arbeitsspeicher, und das reicht: die Benachrichtigung kann nur
  /// entstehen, während [ChatService] läuft — also lebt der Prozess, wenn der
  /// Vollbild-Schirm sie wieder abholt. Sie zusätzlich auf die Platte zu
  /// schreiben hiesse, Nachrichtentexte unverschlüsselt liegen zu lassen.
  final Map<int, BlitzNachricht> _letzte = {};

  BlitzNachricht? letzteFuer(int conversationId) => _letzte[conversationId];

  /// Nach dem Lesen wegräumen — sonst zeigt ein späterer Tipper auf eine alte
  /// Benachrichtigung einen Satz von vorgestern.
  void vergessen(int conversationId) => _letzte.remove(conversationId);

  Future<void> starten() async {
    if (_bereit) return;
    _kiosk = await RdpNurModus.istAn();
    if (PlatformService.isDesktop) {
      await BlitzFensterSteuerung.instanz.bereitmachen();
    }
    _bereit = true;
    _log.info('Blitz bereit (kiosk=$_kiosk)', tag: 'BLITZ');
  }

  /// Eine eingehende Nachricht auffällig machen.
  ///
  /// Fällt in jedem Fall auf die gewöhnliche Benachrichtigung zurück, wenn
  /// der Blitz nicht möglich ist — eine Nachricht, die weder als Karte noch
  /// als Streifen erscheint, wäre schlimmer als der Zustand vorher.
  Future<void> melden({
    required int conversationId,
    required String absender,
    required String text,
    String kanal = 'app',
    DateTime? zeit,
  }) async {
    Future<void> gewoehnlich() => NotificationService().showChatMessage(
          senderName: absender,
          message: text,
          conversationId: conversationId,
        );

    final wann = zeit ?? DateTime.now();
    final vorher = _letzte[conversationId];
    _letzte[conversationId] = (vorher != null && vorher.absender == absender)
        ? vorher.ergaenztUm(text, wann)
        : BlitzNachricht(
            conversationId: conversationId,
            absender: absender,
            zeilen: [text],
            kanal: kanal,
            zeit: wann,
          );

    if (!aktiv || !_bereit) return gewoehnlich();

    // ⚠️ Im RDP-Kiosk-Betrieb (das Pixel neben dem Schreibtisch) hat der Blitz
    // nichts zu suchen: das Gerät zeigt ausschliesslich die Fernsitzung, und
    // ein Vollbild-Schirm würde mitten in die Arbeit am Bürorechner springen.
    // Das Gerät bekommt weiterhin die gewöhnliche Benachrichtigung.
    if (_kiosk) return gewoehnlich();

    // Der Chat steht schon offen — dann liest der Vorsitzende die Nachricht
    // ohnehin gerade. Eine Karte davor wäre nur im Weg.
    if (NotificationService.isChatDialogOpen) return gewoehnlich();

    if (PlatformService.isDesktop) {
      // Nur Linux: unter Windows und macOS ist der Rückruf zur
      // Plugin-Registrierung im Runner nicht gesetzt, das zweite Fenster
      // hätte dort kein window_manager und bliebe unsichtbar irgendwo stehen.
      // Lieber ehrlich der Streifen als eine Karte, die keiner sieht.
      if (!Platform.isLinux) return gewoehnlich();

      final gezeigt = await BlitzFensterSteuerung.instanz.zeigen(
        conversationId: conversationId,
        absender: absender,
        text: text,
        kanal: kanal,
        zeit: wann,
      );
      if (!gezeigt) return gewoehnlich();
      return;
    }

    if (Platform.isAndroid) {
      await NotificationService().showBlitzVollbild(
        senderName: absender,
        message: text,
        conversationId: conversationId,
        kanal: kanal,
      );
      return;
    }

    return gewoehnlich();
  }
}
