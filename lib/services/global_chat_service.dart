import 'package:flutter/foundation.dart';

/// Wer ist gerade angemeldet — Mitgliedernummer und Benutzer-ID des
/// Vorsitzenden.
///
/// ⚠️ DER NAME IST GESCHICHTE, NICHT BESCHREIBUNG.
/// Bis zum 26.08.2026 hing hier die Messenger-artige Blasen-Oberfläche
/// (`GlobalChatOverlay` + `ChatMiniPanel`): Blasen, aufklappbare Panels,
/// Zählstände, Ankerpunkte. Die Oberfläche war seit dem 11.07.2026 in
/// `main.dart` auskommentiert („TEMPORARY DIAGNOSTIC") und damit sechs Wochen
/// lang wirkungslos; an ihre Stelle ist der [BlitzNachrichtService] getreten.
///
/// Übrig geblieben ist genau das, was 25 andere Dateien wirklich von hier
/// lesen: die beiden Kennungen des angemeldeten Benutzers. Umbenannt wurde
/// die Klasse nicht — das hätte 25 Dateien angefasst, ohne irgendetwas
/// besser zu machen.
class GlobalChatService extends ChangeNotifier {
  static final GlobalChatService _instance = GlobalChatService._internal();
  factory GlobalChatService() => _instance;
  GlobalChatService._internal();

  /// Numerische ID des angemeldeten Admins.
  ///
  /// Bewusst getrennt von der Chat-Sitzung: jene steht erst bei `auth_success`
  /// des WebSockets und ist null, solange der Socket nicht steht. Diese hier
  /// setzt das Dashboard beim Laden der Mitgliederliste und taugt damit für
  /// Entscheidungen, die nicht vom Chat abhängen dürfen (z. B. welche Cloud
  /// beim Hochladen gemeint ist).
  int? currentAdminUserId;

  /// Mitgliedernummer des angemeldeten Vorsitzenden. Wird beim Anmelden
  /// gesetzt und beim Abmelden geleert.
  String? _currentMitgliedernummer;
  String? get currentMitgliedernummer => _currentMitgliedernummer;
  set currentMitgliedernummer(String? v) {
    if (_currentMitgliedernummer == v) return;
    _currentMitgliedernummer = v;
    notifyListeners();
  }
}
