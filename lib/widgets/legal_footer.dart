import 'dart:async';
import 'dart:math' show pi;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../screens/webview_screen.dart';
import '../services/update_service.dart';
import '../services/logger_service.dart';
import '../services/api_service.dart';
import 'debug_console.dart';
import 'update_dialog.dart';
import 'changelog.dart';
import '../utils/app_farben.dart';

class LegalFooter extends StatefulWidget {
  final bool darkMode;

  const LegalFooter({
    super.key,
    this.darkMode = false,
  });

  @override
  State<LegalFooter> createState() => _LegalFooterState();
}

class _LegalFooterState extends State<LegalFooter> with SingleTickerProviderStateMixin {
  final _log = LoggerService();
  bool _isChecking = false;
  Timer? _autoCheckTimer;
  // Versteckter Zugang zur Debug-Konsole (7 Tipps auf den Copyright-Text).
  int _debugTipps = 0;
  Timer? _debugTippTimer;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    // ⚠️ Zweiter, unabhängiger Update-Prüfer. Das Dashboard hat einen eigenen,
    // und dieser Fußbereich sitzt IN ihm — es liefen also zwei Prüfungen
    // parallel gegen dieselbe Datei bei GitHub, diese hier zusätzlich weiter,
    // während die App im Hintergrund lag (sie hängt an keinem Lebenszyklus).
    //
    // Er wird nicht gestrichen, weil der Fußbereich auch auf dem Anmeldebild
    // steht — dort gibt es kein Dashboard, und gerade dort ist eine veraltete
    // App am lästigsten. Aber eine halbe Stunde reicht für einen zweiten
    // Wächter über etwas, das der erste ohnehin prüft.
    _autoCheckTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (!mounted) return;
      _checkForUpdates(silent: true);
    });
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    _debugTippTimer?.cancel();
    _rotationController.dispose();
    super.dispose();
  }

  /// Versteckter Zugang zur Debug-Konsole: 7 schnelle Tipps auf den
  /// Copyright-Text, und NUR wenn angemeldet. Kein sichtbarer Knopf mehr — der
  /// war in Release sogar vor der Anmeldung erreichbar (der Fußbereich sitzt
  /// auch auf dem Login-Bildschirm). Muster wie Androids Entwickleroptionen
  /// (7× auf die Build-Nummer). Die Konsole selbst zeigt keine Geheimnisse mehr
  /// (siehe Log-Redigierung), aber Gerätekennung/Mitgliedsnummer haben vor der
  /// Anmeldung nichts verloren.
  void _verstecktesDebug() {
    _debugTippTimer?.cancel();
    _debugTippTimer = Timer(const Duration(seconds: 2), () => _debugTipps = 0);
    _debugTipps++;
    if (_debugTipps >= 7) {
      _debugTipps = 0;
      _debugTippTimer?.cancel();
      if (ApiService().isLoggedIn) showDebugConsole(context);
    }
  }

  Future<void> _checkForUpdates({bool silent = false}) async {
    if (_isChecking) return;

    setState(() => _isChecking = true);
    _rotationController.repeat();

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Suche nach Updates...'),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blue.shade700,
        ),
      );
    }

    _log.info('Checking for updates...', tag: 'UPDATE');

    try {
      final updateService = UpdateService();
      final updateInfo = await updateService.checkForUpdate();

      if (!mounted) return;

      _rotationController.stop();
      _rotationController.reset();
      setState(() => _isChecking = false);

      if (updateInfo != null) {
        _log.info('Update available: ${updateInfo.version}', tag: 'UPDATE');
        // Show update dialog
        showDialog(
          context: context,
          barrierDismissible: !updateInfo.forceUpdate,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      } else if (!silent && mounted) {
        _log.info('No updates available', tag: 'UPDATE');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text('Die App ist auf dem neuesten Stand'),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      _log.error('Update check failed: $e', tag: 'UPDATE');
      if (!mounted) return;

      _rotationController.stop();
      _rotationController.reset();
      setState(() => _isChecking = false);

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text('Fehler bei der Update-Prüfung'),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  void _showChangelog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ChangelogDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.darkMode ? F.h(Colors.grey, 400) : F.h(Colors.grey, 600);

    // Die App zeichnet randlos (`SystemUiMode.edgeToEdge`, main.dart), das
    // System schiebt also nichts mehr über die Navigationsleiste. Als
    // `bottomNavigationBar` ist diese Zeile das unterste Bauteil des
    // Bildschirms — ohne den Zuschlag lägen Version, Aktualisierungsknopf und
    // Weblink unter den drei Systemtasten: weder lesbar noch antippbar.
    //
    // Der Zuschlag gehört INNEN an den eingefärbten Container: so reicht die
    // Fläche bis zur Bildschirmkante durch und das System legt seinen Schleier
    // auf unseren Hintergrund statt auf eine Lücke. `MailQuotaBar` erreicht
    // dasselbe mit `SafeArea(top: false)` — hier wäre eine SafeArea nur mit
    // ebendiesem `top: false` richtig, weil `padding.top` an dieser Stelle noch
    // die Statusleiste meldet und oben 48 dp aufrisse.
    //
    // `paddingOf`, nicht `viewPaddingOf`: bei offener Tastatur hebt das
    // Scaffold diese Leiste über die Tastatur, die Systemleiste liegt dann
    // nicht mehr darunter. Im Login-Bildschirm steht der Fuß in einer SafeArea,
    // die den Wert bereits verbraucht hat; beide Male kommt 0 heraus.
    final systemleiste = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + systemleiste),
      decoration: BoxDecoration(
        color: widget.darkMode ? const Color(0xFF1a1a2e) : F.h(Colors.grey, 100),
        border: Border(
          top: BorderSide(
            color: widget.darkMode ? F.h(Colors.grey, 800) : F.h(Colors.grey, 300),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _verstecktesDebug,
                    child: Text('© 2025 - ${DateTime.now().year} ICD360S e.V', style: TextStyle(fontSize: 11, color: textColor)),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => _showChangelog(context),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'v${UpdateService.currentVersion}',
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  decoration: TextDecoration.underline,
                  decorationColor: textColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Update check button
          Tooltip(
            message: 'Nach Updates suchen',
            child: InkWell(
              onTap: _isChecking ? null : () => _checkForUpdates(silent: false),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: AnimatedBuilder(
                  animation: _rotationController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _rotationController.value * 2 * pi,
                      child: Icon(
                        Icons.refresh,
                        size: 16,
                        color: _isChecking ? F.h(Colors.blue, 600) : textColor,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Sichtbarer >_-Knopf NUR in Debug-Builds. In Release öffnet die
          // Konsole ausschließlich der versteckte 7-Tipp auf den Copyright-Text
          // (und nur angemeldet) — kein casual/pre-auth-Zugang mehr.
          if (kDebugMode)
            InkWell(
              onTap: () => showDebugConsole(context),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '>_',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Consolas',
                  ),
                ),
              ),
            ),
          if (kDebugMode) const SizedBox(width: 4),
          // Website link
          Tooltip(
            message: 'icd360s.de',
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WebViewScreen(
                      title: 'ICD360S e.V.',
                      url: 'https://icd360s.de',
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(
                  Icons.language,
                  size: 16,
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
