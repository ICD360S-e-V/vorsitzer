/// Kanal-Definition für den ferngesteuerten Anruf.
///
/// Die Fachlogik (Warteschlange, Auftragsablauf, Rufnummernprüfung) liegt in
/// `lib/services/anruf_gateway_service.dart` der App — dieses Paket existiert
/// nur, damit der Kanal über `GeneratedPluginRegistrant` in **jeder** Engine
/// registriert wird, auch in der, die der Vordergrunddienst startet. Genau
/// dort kommt der Auftrag an; ein Kanal aus MainActivity existiert dort nicht.
library;

import 'package:flutter/services.dart';

/// Name des MethodChannels. Muss zu `IcdAnrufPlugin.CHANNEL` passen.
const String icdAnrufChannelName = 'de.icd360sev.vorsitzer/fernanruf';

/// Fertig gebundener Kanal für Aufrufer, die nichts weiter brauchen.
const MethodChannel icdAnrufChannel = MethodChannel(icdAnrufChannelName);

/// Ergebnis eines ferngesteuerten Wählversuchs.
///
/// Die Zeichenketten sind der Vertrag mit der nativen Seite **und** mit dem
/// Server (`anruf_auftraege.ergebnis`). Wer hier etwas umbenennt, muss beide
/// Enden anfassen.
class IcdAnrufErgebnis {
  /// Der Anruf läuft — nachgeprüft am Telefoniezustand, nicht angenommen.
  static const gewaehlt = 'gewaehlt';

  /// Android hat den Start aus dem Hintergrund verweigert. Es liegt eine
  /// Benachrichtigung bereit: ein Tipp darauf wählt.
  static const bestaetigungNoetig = 'bestaetigung_noetig';

  /// `CALL_PHONE` fehlt.
  static const keineBerechtigung = 'keine_berechtigung';

  /// Gerät kann nicht telefonieren (WLAN-Tablet, Desktop).
  static const keinTelefon = 'kein_telefon';

  /// Notruf — wird ferngesteuert grundsätzlich nicht gewählt.
  static const notruf = 'notruf';

  /// Aus dem Auftrag ließ sich keine Rufnummer lesen.
  static const ungueltig = 'ungueltig';

  /// Unerwarteter Fehler; Text steht in `meldung`.
  static const fehler = 'fehler';
}
