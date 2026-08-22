import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/app_sperre_service.dart';
import '../utils/sperre_passwort.dart';

/// Legt die Bildschirmsperre über die gesamte App.
///
/// Sitzt im `builder:` von `MaterialApp`, also **über** dem Navigator: damit
/// deckt sie auch offene Dialoge und Vollbildseiten ab. Läge sie darunter,
/// bliebe ein geöffneter Dialog beim Sperren sichtbar und bedienbar.
///
/// ⚠️ Im Normalfall ist das hier nur ein [Listener] um das Kind — kein Stack,
/// keine Überlagerung. Der Kommentar in `main.dart` hält fest, dass ein
/// dauerhaft eingehängtes Overlay dort einmal die App auf Android hat
/// einfrieren lassen; die Sperrfläche entsteht deshalb erst, wenn wirklich
/// gesperrt ist.
class AppSperreHuelle extends StatefulWidget {
  const AppSperreHuelle({super.key, required this.child});

  final Widget child;

  @override
  State<AppSperreHuelle> createState() => _AppSperreHuelleState();
}

class _AppSperreHuelleState extends State<AppSperreHuelle>
    with WidgetsBindingObserver {
  final AppSperreService _sperre = AppSperreService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sperre.addListener(_neu);
    _sperre.taktStarten();
    // Tastatur zählt auch als Bedienung — auf dem Rechner tippt man lange,
    // ohne den Zeiger zu bewegen, und würde sonst mitten im Satz gesperrt.
    HardwareKeyboard.instance.addHandler(_taste);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_taste);
    WidgetsBinding.instance.removeObserver(this);
    _sperre.removeListener(_neu);
    _sperre.taktStoppen();
    super.dispose();
  }

  void _neu() {
    if (mounted) setState(() {});
  }

  bool _laedt = false;

  /// Liest den Sperrzustand — erst, wenn jemand angemeldet ist.
  ///
  /// ⚠️ Bewusst NICHT in `initState`. Vor der Anmeldung gibt es nichts zu
  /// sperren, und der Zugriff auf den Schlüsselbund kostet beim Start Zeit;
  /// unter Linux wartet er im ungünstigen Fall sekundenlang auf D-Bus
  /// (siehe `secure_store.dart`). Nebenbei blieb der Startbildschirm-Test
  /// dadurch grün: dessen Umgebung kennt weder Schlüsselbund noch
  /// `path_provider`, und ein Zeitgeber daraus stört die Testuhr.
  void _ladenAnstossen() {
    if (_laedt || _sperre.istGeladen) return;
    _laedt = true;
    _sperre.laden();
  }

  /// Gibt immer `false` zurück: wir hören nur mit, wir verbrauchen nichts.
  bool _taste(KeyEvent _) {
    _sperre.vermerkeBedienung();
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ⚠️ Hier steckt der Sinn der Uhrzeit-Rechnung: war die App zwei Stunden
      // im Hintergrund, lief kein Takt — die Zeit ist trotzdem vergangen.
      _sperre.pruefen();
      _sperre.taktStarten();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Den Takt anhalten spart Strom; gemerkt wird ohnehin der Zeitpunkt.
      _sperre.taktStoppen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = Listener(
      // `translucent`: mithören, ohne einem Knopf darunter etwas wegzunehmen.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _sperre.vermerkeBedienung(),
      onPointerMove: (_) => _sperre.vermerkeBedienung(),
      onPointerSignal: (_) => _sperre.vermerkeBedienung(),
      child: widget.child,
    );

    // Vor der Anmeldung gibt es nichts zu sperren — der Anmeldebildschirm ist
    // sein eigener Riegel.
    if (!ApiService().isLoggedIn) return kind;
    if (!_sperre.istGeladen) {
      _ladenAnstossen();
      return kind;
    }

    if (_sperre.istGesperrt) {
      return _SperrFlaeche(sperre: _sperre);
    }
    if (!_sperre.istEingerichtet) {
      return _EinrichtFlaeche(sperre: _sperre);
    }
    if (_sperre.warntGleich) {
      return Stack(
        children: [
          kind,
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: _Hinweisstreifen(
              verbleibend: _sperre.verbleibend,
              onBleiben: () => _sperre.vermerkeBedienung(erzwingen: true),
            ),
          ),
        ],
      );
    }
    return kind;
  }
}

/// Der Streifen in der letzten Minute.
class _Hinweisstreifen extends StatelessWidget {
  const _Hinweisstreifen({required this.verbleibend, required this.onBleiben});

  final Duration verbleibend;
  final VoidCallback onBleiben;

  @override
  Widget build(BuildContext context) {
    final s = verbleibend.inSeconds;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.shade800,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: Row(children: [
          const Icon(Icons.lock_clock, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          // ⚠️ Kurz halten. Die erste Fassung nannte auch noch den Grund
          // („keine Eingaben seit 15 Minuten") — auf einem 412-px-Telefon
          // brach das auf vier Zeilen um, und der Streifen verdeckte ein
          // Drittel des Bildschirms. Erst am gerenderten Bild aufgefallen.
          Expanded(
            child: Text(
              'Sperre in $s\u00a0s',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onBleiben,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Bleiben'),
          ),
        ]),
      ),
    );
  }
}

/// Die Sperrfläche selbst.
class _SperrFlaeche extends StatefulWidget {
  const _SperrFlaeche({required this.sperre});
  final AppSperreService sperre;

  @override
  State<_SperrFlaeche> createState() => _SperrFlaecheState();
}

class _SperrFlaecheState extends State<_SperrFlaeche> {
  final _feld = TextEditingController();
  bool _laeuft = false;
  bool _falsch = false;

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  Future<void> _versuchen() async {
    if (_laeuft || _feld.text.isEmpty) return;
    setState(() {
      _laeuft = true;
      _falsch = false;
    });
    final ok = await widget.sperre.entsperren(_feld.text);
    if (!mounted) return;
    setState(() {
      _laeuft = false;
      _falsch = !ok;
    });
    if (ok) _feld.clear();
  }

  Future<void> _abmelden() async {
    // Der Weg heraus, wenn das Passwort vergessen ist. Kein Datenverlust: die
    // Daten liegen auf dem Server, die Anmeldung stellt alles wieder her.
    await ApiService().logout();
    await widget.sperre.zuruecksetzen();
  }

  @override
  Widget build(BuildContext context) {
    final warten = widget.sperre.wartezeitRest;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFF1a2a3a),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline, size: 56, color: Colors.white70),
                const SizedBox(height: 18),
                const Text('Gesperrt',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Bitte geben Sie Ihr App-Passwort ein.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: .75)),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _feld,
                  obscureText: true,
                  autofocus: true,
                  enabled: !_laeuft && warten == Duration.zero,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _versuchen(),
                  decoration: InputDecoration(
                    labelText: 'App-Passwort',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .08),
                    errorText: _falsch ? 'Passwort stimmt nicht.' : null,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (warten > Duration.zero) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Zu viele Fehlversuche — noch ${warten.inSeconds} Sekunden.',
                    style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        _laeuft || warten > Duration.zero ? null : _versuchen,
                    child: _laeuft
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Entsperren'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _abmelden,
                  style: TextButton.styleFrom(foregroundColor: Colors.white60),
                  child: const Text('Passwort vergessen — neu anmelden'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Einmalige Einrichtung, wenn noch kein Passwort gesetzt ist.
class _EinrichtFlaeche extends StatefulWidget {
  const _EinrichtFlaeche({required this.sperre});
  final AppSperreService sperre;

  @override
  State<_EinrichtFlaeche> createState() => _EinrichtFlaecheState();
}

class _EinrichtFlaecheState extends State<_EinrichtFlaeche> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _fehler;
  bool _laeuft = false;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _setzen() async {
    final p = _a.text;
    if (p.length < sperreMindestlaenge) {
      setState(() => _fehler =
          'Mindestens $sperreMindestlaenge Zeichen.');
      return;
    }
    if (p != _b.text) {
      setState(() => _fehler = 'Die beiden Eingaben stimmen nicht überein.');
      return;
    }
    setState(() {
      _fehler = null;
      _laeuft = true;
    });
    await widget.sperre.passwortSetzen(p);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFF1a2a3a),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.key, size: 52, color: Colors.white70),
                const SizedBox(height: 16),
                const Text('App-Passwort festlegen',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(
                  'Die App enthält Mitglieder-, Gesundheits- und Behördendaten. '
                  'Sie wird nach ${AppSperreService.leerlauf.inMinutes} Minuten '
                  'ohne Bedienung gesperrt und beim Öffnen danach gefragt.\n\n'
                  'Das ist NICHT die PIN des Geräts — wer die kennt, soll damit '
                  'nicht auch in die Akten kommen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .75), fontSize: 13),
                ),
                const SizedBox(height: 20),
                for (final (feld, beschriftung) in [
                  (_a, 'Neues App-Passwort'),
                  (_b, 'Wiederholen'),
                ]) ...[
                  TextField(
                    controller: feld,
                    obscureText: true,
                    enabled: !_laeuft,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: beschriftung,
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: .08),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_fehler != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_fehler!,
                        style: TextStyle(color: Colors.red.shade300)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _laeuft ? null : _setzen,
                    child: _laeuft
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Festlegen'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
