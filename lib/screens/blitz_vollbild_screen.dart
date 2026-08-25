import 'package:flutter/material.dart';

import '../models/blitz_nachricht.dart';
import '../services/api_service.dart';
import '../services/blitz_nachricht_service.dart';
import '../services/global_chat_service.dart';
import '../services/logger_service.dart';
import '../utils/app_farben.dart';
import '../widgets/blitz_karte.dart';

/// Der Blitz auf dem Tablet: die Nachricht auf dem ganzen Schirm, mit
/// Antwortfeld — wie ein Anrufbildschirm, nur zum Schreiben.
///
/// ⚠️ NICHT auf dem Pixel. Das Gerät läuft im RDP-Kiosk-Betrieb und zeigt
/// ausschliesslich die Fernsitzung; ein Vollbild-Schirm würde mitten in die
/// Arbeit am Bürorechner springen. Die Weiche steht in
/// [BlitzNachrichtService.melden] und fragt [RdpNurModus] — also den
/// Schalter, nicht das Gerätemodell: ein Tablet, das jemand später auf
/// Kiosk stellt, ist damit automatisch ebenfalls aussen vor.
class BlitzVollbildScreen extends StatelessWidget {
  final BlitzNachricht nachricht;

  /// „Im Chat öffnen" — bekommt die Unterhaltung, nachdem der Schirm zu ist.
  final void Function(int conversationId)? onImChatOeffnen;

  const BlitzVollbildScreen({
    super.key,
    required this.nachricht,
    this.onImChatOeffnen,
  });

  static final _log = LoggerService();

  Future<String?> _senden(String text) async {
    final mnr = GlobalChatService().currentMitgliedernummer;
    if (mnr == null || mnr.isEmpty) return 'Nicht angemeldet';
    try {
      final r = await ApiService().sendChatMessage(
        nachricht.conversationId,
        mnr,
        text,
        // Auf demselben Weg zurück, auf dem es hereinkam — sonst sieht das
        // Mitglied die Antwort nie.
        channel: nachricht.kanal == 'sms' ? 'sms' : 'app',
      );
      if (r['success'] == true) {
        BlitzNachrichtService.instanz.vergessen(nachricht.conversationId);
        return null;
      }
      return '${r['message'] ?? 'Senden fehlgeschlagen'}';
    } catch (e) {
      _log.error('Blitz-Antwort (Vollbild) fehlgeschlagen: $e', tag: 'BLITZ');
      return 'Netzwerkfehler';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) BlitzNachrichtService.instanz.vergessen(nachricht.conversationId);
      },
      child: Scaffold(
        backgroundColor: F.hintergrund,
        body: SafeArea(
          child: BlitzKarte(
            nachricht: nachricht,
            gross: true,
            onSenden: _senden,
            onSchliessen: () {
              BlitzNachrichtService.instanz.vergessen(nachricht.conversationId);
              Navigator.of(context).maybePop();
            },
            onImChatOeffnen: onImChatOeffnen == null
                ? null
                : () {
                    final id = nachricht.conversationId;
                    BlitzNachrichtService.instanz.vergessen(id);
                    Navigator.of(context).maybePop();
                    onImChatOeffnen!(id);
                  },
          ),
        ),
      ),
    );
  }
}
