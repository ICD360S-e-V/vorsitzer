import 'package:flutter/material.dart';

import '../services/rdp_nur_modus.dart';
import 'dashboard_screen.dart';
import 'rdp_only_screen.dart';

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
  bool? _nurRdp;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final an = _nurRdp;
    if (an == null) {
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
    return DashboardScreen(
      userName: widget.userName,
      currentMitgliedernummer: widget.currentMitgliedernummer,
      currentEmail: widget.currentEmail,
      currentRole: widget.currentRole,
    );
  }
}
