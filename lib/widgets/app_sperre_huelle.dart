import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/device_key_service.dart';
import '../services/app_sperre_service.dart';
import '../utils/sperre_passwort.dart';

/// Legt die Bildschirmsperre über die gesamte App.
///
/// Sitzt im `builder:` von `MaterialApp`, also **über** dem Navigator: damit
/// deckt sie auch offene Dialoge und Vollbildseiten ab. Läge sie darunter,
/// bliebe ein geöffneter Dialog beim Sperren sichtbar und bedienbar.
///
/// ⚠️ Im Normalfall reicht sie das Kind unverändert durch — kein Stack, keine
/// Überlagerung, kein Lauscher. Der Kommentar in `main.dart` hält fest, dass
/// ein dauerhaft eingehängtes Overlay dort einmal die App auf Android hat
/// einfrieren lassen; die Sperrfläche entsteht deshalb erst, wenn wirklich
/// gesperrt ist.
///
/// ⚠️ Bis zum 02.09.2026 hingen hier ein `Listener` über dem gesamten Baum und
/// ein Haken in `HardwareKeyboard`, um jede Berührung und jeden Tastendruck zu
/// vermerken — Futter für die Leerlaufsperre. Die gibt es nicht mehr
/// (Entscheidung des Users, siehe `AppSperreService`), also sind sie weg. Ein
/// Lauscher, der über jedem Zeigerereignis der App liegt und nichts mehr
/// bewirkt, ist keine tote Zeile, sondern laufende Arbeit bei jeder Wischgeste.
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
    _anmeldungBeobachten();
  }

  @override
  void dispose() {
    _anmeldeWache?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _sperre.removeListener(_neu);
    super.dispose();
  }

  void _neu() {
    if (mounted) setState(() {});
  }

  bool _laedt = false;

  /// Zuletzt gesehener Anmeldezustand.
  bool _warAngemeldet = false;
  Timer? _anmeldeWache;

  /// ⚠️ Der Grund, warum die Sperre in der ersten Fassung NIE griff.
  ///
  /// Diese Hülle sitzt im `builder:` der `MaterialApp` und wurde nur neu
  /// gebaut, wenn der Sperrdienst etwas meldete. Beim Start ist niemand
  /// angemeldet — sie stieg also sofort aus, stiess das Laden nie an, und der
  /// Dienst hatte folglich nie etwas zu melden. Ein Henne-und-Ei-Problem.
  ///
  /// Dass danach die Anmeldung durchlief und der Navigator auf das
  /// Armaturenbrett wechselte, half nicht: der Navigator verwaltet seine Routen
  /// selbst, `builder` läuft dabei NICHT erneut. Im Betrieb hiess das: keine
  /// Sperre, und nach dem Update fragte auch niemand nach einem Passwort.
  ///
  /// `ApiService` meldet Anmeldungen nicht, also wird nachgesehen. Eine
  /// Sekunde, und verglichen wird ein `bool` — das kostet nichts.
  void _anmeldungBeobachten() {
    _anmeldeWache?.cancel();
    _anmeldeWache = Timer.periodic(const Duration(seconds: 1), (_) {
      final jetzt = ApiService().isLoggedIn;
      if (jetzt == _warAngemeldet) return;
      _warAngemeldet = jetzt;
      if (jetzt) {
        _ladenAnstossen();
      } else {
        // Abgemeldet: beim naechsten Anmelden muss frisch geladen werden.
        _laedt = false;
      }
      if (mounted) setState(() {});
    });
  }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ⚠️ In den Hintergrund zu gehen sperrt NICHT. Das ist der ganze Punkt der
    // Änderung vom 02.09.2026: wer kurz in den Kalender schaut oder einen
    // Anruf annimmt, soll danach weiterarbeiten können. Gesperrt wird beim
    // Neustart der App und über den Schloss-Knopf.
    if (state == AppLifecycleState.resumed) {
      // Einzige Ausnahme: kommt die App über dem gesperrten GERÄT nach vorn
      // (Anruf-Vollbild, Tipp auf eine Benachrichtigung am Sperrbildschirm),
      // wären die Akten ohne Geräte-PIN sichtbar. Dann sofort sperren.
      unawaited(_sperre.ueberLockschirmPruefen());
    }
  }

  /// Legt [flaeche] ÜBER den laufenden Baum, statt ihn zu ersetzen.
  ///
  /// ⚠️ Zuerst gab die Hülle die Sperrfläche einfach anstelle des Kindes
  /// zurück. Damit fiel der Navigator aus dem Baum — und mit ihm das
  /// `Overlay`, das jedes `EditableText` braucht. Das Passwortfeld hat
  /// `autofocus`, also flog beim Sperren sofort „No Overlay widget found".
  /// Die Sperre wäre schon beim Erscheinen kaputt gewesen.
  ///
  /// Der Hintergrund bleibt deshalb im Baum, wird aber unbedienbar
  /// ([AbsorbPointer]), für Vorlesehilfen unsichtbar ([ExcludeSemantics]) und
  /// von der deckenden Fläche verdeckt. Aufgefallen erst im Test.
  Widget _darueberlegen(Widget kind, Widget flaeche) {
    return Stack(
      children: [
        ExcludeSemantics(child: AbsorbPointer(child: kind)),
        Positioned.fill(child: flaeche),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.child;

    // Vor der Anmeldung gibt es nichts zu sperren — der Anmeldebildschirm ist
    // sein eigener Riegel.
    if (!ApiService().isLoggedIn) return kind;
    if (!_sperre.istGeladen) {
      _ladenAnstossen();
      return kind;
    }
    // Ab hier ist der Zustand bekannt: entweder gesperrt, oder es fehlt noch
    // ein Passwort, oder es laeuft alles normal weiter.

    if (_sperre.istGesperrt) {
      return _darueberlegen(kind, _SperrFlaeche(sperre: _sperre));
    }
    if (!_sperre.istEingerichtet) {
      return _darueberlegen(kind, _EinrichtFlaeche(sperre: _sperre));
    }
    return kind;
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

  /// ⚠️ Zählt die Wartestaffel nach zu vielen Fehlversuchen herunter.
  ///
  /// Bis zum 02.09.2026 kam dieser Sekundentakt aus `AppSperreService` — er
  /// diente der Leerlaufsperre und hat die Anzeige nebenbei mitgezogen. Mit
  /// der Leerlaufsperre fiel er weg, und ohne Ersatz stünde hier „noch 300
  /// Sekunden", bis jemand etwas tippt. Deshalb hier, wo er hingehört: er
  /// lebt nur, solange die Sperrfläche da ist.
  Timer? _takt;

  @override
  void initState() {
    super.initState();
    _takt = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.sperre.wartezeitRest > Duration.zero) setState(() {});
    });
  }

  @override
  void dispose() {
    _takt?.cancel();
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

  bool _zeigeWiederherstellung = false;

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
                if (!_zeigeWiederherstellung)
                  TextButton(
                    onPressed: () =>
                        setState(() => _zeigeWiederherstellung = true),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.white60),
                    child: const Text('Passwort vergessen?'),
                  )
                else
                  _Wiederherstellung(sperre: widget.sperre),
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
    final problem = sperrePasswortProblem(p);
    if (problem != null) {
      setState(() => _fehler = problem);
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
                  'Danach gefragt wird beim Start der App und immer dann, wenn '
                  'Sie in der Kopfzeile auf das Schloss tippen — nicht '
                  'zwischendurch.\n\n'
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
                      helperText: feld == _a
                          ? 'Mindestens $sperreMindestlaenge Zeichen'
                          : null,
                      helperStyle: const TextStyle(color: Colors.white54),
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

/// Der einzige Weg an der Sperre vorbei: ein Aktivierungscode vom Server.
///
/// ⚠️ Hier stand zuerst ein Knopf „neu anmelden", der einfach abgemeldet hat.
/// Das war eine **Hintertür**: wer das Gerät in die Hand bekam, konnte sie
/// antippen. Zwar kam er an keine Daten, aber ein Bildschirm, der eine Sperre
/// zeigt und daneben einen Ausgang, ist keine Sperre. Entscheidung des Users.
///
/// ⚠️ Ganz weglassen ging aber auch nicht, und der Grund ist nachgemessen:
/// „einfach neu installieren" hilft NUR auf Android. Dort werden die
/// Keystore-Schlüssel beim Deinstallieren gelöscht; selbst wenn Auto-Backup
/// den Chiffretext zurückholt, ist er unlesbar und gilt hier als „kein
/// Passwort gesetzt". Unter Linux bleibt der Schlüsselbund des Flatpaks
/// (`~/.var/app/<id>/data/keyrings`) beim Deinstallieren **stehen** — nur
/// `flatpak uninstall --delete-data` räumt ihn weg. Ohne diesen Weg hier wäre
/// der Vorsitzende auf seinem Linux-Rechner tatsächlich ausgesperrt.
///
/// Der Code ist keine Hintertür, weil ihn nur der Server ausstellt: 16 Zeichen,
/// einmalig, und `activate_code.php` begrenzt auf fünf Fehlversuche je
/// Viertelstunde. Wer das Gerät findet, hat keinen.
class _Wiederherstellung extends StatefulWidget {
  const _Wiederherstellung({required this.sperre});
  final AppSperreService sperre;

  @override
  State<_Wiederherstellung> createState() => _WiederherstellungState();
}

class _WiederherstellungState extends State<_Wiederherstellung> {
  final _nummer = TextEditingController();
  final _code = TextEditingController();
  String? _fehler;
  bool _laeuft = false;

  @override
  void dispose() {
    _nummer.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _einloesen() async {
    setState(() {
      _fehler = null;
      _laeuft = true;
    });
    try {
      final geraeteId = await DeviceKeyService().getOrGenerateDeviceId();
      final antwort = await ApiService().activateDeviceCode(
        mitgliedernummer: _nummer.text.trim().toUpperCase(),
        code: _code.text.trim(),
        deviceId: geraeteId,
      );
      if (antwort['success'] != true) {
        setState(() {
          _fehler = (antwort['message'] ??
                  antwort['data']?['message'] ??
                  'Code nicht angenommen.')
              .toString();
          _laeuft = false;
        });
        return;
      }
      final daten = (antwort['data'] as Map?) ?? {};
      final token = daten['token']?.toString();
      final refresh = daten['refresh_token']?.toString();
      final geraeteSchluessel = daten['device_key']?.toString();
      if (token == null || refresh == null || geraeteSchluessel == null) {
        setState(() {
          _fehler = 'Unvollständige Antwort des Servers.';
          _laeuft = false;
        });
        return;
      }
      await DeviceKeyService()
          .setActivatedCredentials(geraeteSchluessel, geraeteId);
      await ApiService().saveTokens(token, refresh);
      // Erst wenn alles steht, das alte Passwort wegräumen — sonst stünde man
      // nach einem Abbruch ohne Passwort UND ohne gültige Anmeldung da.
      await widget.sperre.zuruecksetzen();
    } catch (e) {
      if (mounted) {
        setState(() {
          _fehler = 'Fehlgeschlagen: $e';
          _laeuft = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Divider(color: Colors.white24, height: 26),
      Text(
        'Ein neues App-Passwort lässt sich nur mit einem Aktivierungscode '
        'setzen. Den stellt der Vorstand über den Server aus — 16 Zeichen, '
        'einmalig gültig.',
        textAlign: TextAlign.center,
        style: TextStyle(
            color: Colors.white.withValues(alpha: .7), fontSize: 12),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _nummer,
        enabled: !_laeuft,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(color: Colors.white),
        decoration: _feldStil('Mitgliedernummer'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _code,
        enabled: !_laeuft,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(color: Colors.white, letterSpacing: 1.2),
        decoration: _feldStil('Aktivierungscode (16 Zeichen)'),
      ),
      if (_fehler != null) ...[
        const SizedBox(height: 10),
        Text(_fehler!, style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
      ],
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _laeuft ? null : _einloesen,
          child: _laeuft
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Gerät neu freischalten'),
        ),
      ),
    ]);
  }

  InputDecoration _feldStil(String beschriftung) => InputDecoration(
        labelText: beschriftung,
        labelStyle: const TextStyle(color: Colors.white70),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: .08),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );
}
