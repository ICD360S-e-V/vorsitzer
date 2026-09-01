import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/rdp_nur_modus.dart';
import 'dashboard_screen.dart';
import 'rdp_only_screen.dart';
import 'vorstand_kompakt_screen.dart';

/// Entscheidet nach dem Login, welcher Bildschirm die App ist: das vollständige
/// Vorsitzer-Panel oder der Kiosk „Nur Remote Desktop".
///
/// Steht bewusst zwischen Login und Dashboard, statt die Weiche in jeden der
/// fünf Anmeldewege zu kopieren — und statt sie in [DashboardScreen] selbst zu
/// legen, denn dann liefe dessen `initState` mit all seinen Abfragetakten
/// trotzdem an, und genau die soll der Kiosk-Modus ja loswerden.
class StartWeiche extends StatefulWidget {
  final String userName;
  final String currentMitgliedernummer;
  final String currentEmail;
  final String currentRole;

  const StartWeiche({
    super.key,
    required this.userName,
    required this.currentMitgliedernummer,
    required this.currentEmail,
    required this.currentRole,
  });

  @override
  State<StartWeiche> createState() => _StartWeicheState();
}

class _StartWeicheState extends State<StartWeiche> {
  /// Gemerkter letzter Serverbescheid. Damit bleibt die richtige Oberfläche
  /// auch dann stehen, wenn die App gerade kein Netz hat — sonst bekäme ein
  /// eingeschränktes Konto beim Start ohne Empfang das volle Dashboard und
  /// darin lauter 403.
  static const _schluesselEingeschraenkt = 'zugriff_eingeschraenkt';

  bool? _nurRdp;
  bool? _eingeschraenkt;

  @override
  void initState() {
    super.initState();
    _zugriffKlaeren();
    // Der Zustand liegt in den SharedPreferences, das Lesen ist also
    // asynchron — aber gepuffert, und damit nach dem ersten Mal sofort da.
    RdpNurModus.istAn().then((an) {
      if (mounted) setState(() => _nurRdp = an);
    }).catchError((_) {
      // Im Zweifel die vollständige App: ein Gerät ohne Oberfläche wäre der
      // schlechtere Ausgang als ein Kiosk, der einmal nicht angeht.
      if (mounted) setState(() => _nurRdp = false);
    });
  }

  /// Fragt den Server, ob dieses Konto eingeschränkt ist.
  ///
  /// ⚠️ Hier und nicht in der Login-Antwort: die App kommt über FÜNF Wege
  /// hierher (Passwort, Anmeldecode, Freigabe durch ein zweites Gerät,
  /// Auto-Login, Wiederaufnahme). Ein Feld in einer davon hätte in den anderen
  /// vier gefehlt — und der Fehler sähe aus wie „zeigt manchmal zu viel", also
  /// wie gar nichts.
  ///
  /// ⚠️ Rückfall ist die VOLLE Oberfläche, nicht die eingeschränkte. Das ist
  /// kein Loch: der Server weist ein eingeschränktes Konto überall ab
  /// (`requireAdminRole`, `requireRollen`, `ticketZugriff`, `chatIstAdmin`).
  /// Umgekehrt — bei Netzfehler sperren — stünde der Vorsitzende ohne Grund
  /// vor einer leeren App. Der gemerkte Wert federt den Normalfall ab.
  Future<void> _zugriffKlaeren() async {
    final prefs = await SharedPreferences.getInstance();
    final gemerkt = prefs.getBool(_schluesselEingeschraenkt);
    if (mounted && gemerkt != null) setState(() => _eingeschraenkt = gemerkt);

    final r = await ApiService().meinZugriff();
    if (r['success'] == true) {
      final wert = r['eingeschraenkt'] == true;
      await prefs.setBool(_schluesselEingeschraenkt, wert);
      if (mounted) setState(() => _eingeschraenkt = wert);
    } else if (mounted && gemerkt == null) {
      setState(() => _eingeschraenkt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final an = _nurRdp;
    if (an == null || _eingeschraenkt == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1a1a2e),
        body: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }
    if (an) {
      return RdpOnlyScreen(
        userName: widget.userName,
        currentMitgliedernummer: widget.currentMitgliedernummer,
        currentEmail: widget.currentEmail,
        currentRole: widget.currentRole,
      );
    }
    // ⚠️ Der Kiosk hat Vorrang: er ist eine Eigenschaft des GERÄTS, die
    // Einschränkung eine des KONTOS. Ein Kiosk-Tablet bleibt ein Kiosk-Tablet,
    // egal wer sich anmeldet.
    if (_eingeschraenkt == true) {
      return VorstandKompaktScreen(
        userName: widget.userName,
        currentMitgliedernummer: widget.currentMitgliedernummer,
        currentEmail: widget.currentEmail,
        currentRole: widget.currentRole,
      );
    }

    return DashboardScreen(
      userName: widget.userName,
      currentMitgliedernummer: widget.currentMitgliedernummer,
      currentEmail: widget.currentEmail,
      currentRole: widget.currentRole,
    );
  }
}
