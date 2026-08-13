import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'phone_link.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../utils/person_name.dart';
import '../utils/flaggen.dart';
import '../utils/sprach_flaggen.dart';
import '../utils/visitenkarte_daten.dart';
import '../utils/visitenkarte_farben.dart';
import '../utils/visitenkarte_pdf.dart';

/// Die Visitenkarte im Profil-Dialog: Vorderseite mit den Kontaktdaten,
/// Rückseite mit dem, was der Verein tut.
///
/// ⚠️ Die Karte hat ein **festes Seitenverhältnis** (85 × 55 mm, also 1,545).
/// Vorher war sie `double.infinity × 280` — im 950 dp breiten Dialog ergab das
/// 902 × 280, ein Verhältnis von 3,2 : 1. Das ist kein Kartenformat, sondern
/// ein Banner, und es hat die Karte als Karte unkenntlich gemacht.
///
/// Die Höhe darf trotzdem wachsen ([BoxConstraints.minHeight] statt fester
/// Höhe): bei stark vergrößerter Systemschrift braucht der Inhalt mehr Platz,
/// und eine Karte, die dann unten abschneidet, wäre für genau die Mitglieder
/// unlesbar, für die dieser Verein da ist. Bei normaler Schriftgröße stimmt
/// das Verhältnis exakt.
class Visitenkarte extends StatefulWidget {
  final String mitgliedernummer;
  final ApiService apiService;

  const Visitenkarte({
    super.key,
    required this.mitgliedernummer,
    required this.apiService,
  });

  @override
  State<Visitenkarte> createState() => _VisitenkarteState();
}

/// Rückfall für den Slogan, wenn `vereineinstellungen.slogan` nicht zu
/// erreichen ist.
///
/// ⚠️ Die **Datenbank ist die Quelle**, nicht diese Konstante. Die Spalte gibt
/// es seit dem 13.08.2026, und die Karte liest sie über `getVereineinstellungen()`
/// mit, weil sie die Zeile ohnehin schon holt. Hier steht nur, was angezeigt
/// wird, wenn dieser Aufruf scheitert — dann ein leicht veralteter Satz statt
/// einer leeren Zeile unter dem Vereinsnamen.
///
/// Der Slogan ist die Auflösung des Vereinsnamens: **I**ntegration,
/// **C**hancen, **D**iversity, **360**, **S**upport. Wer ein Wort tauscht oder
/// die Reihenfolge ändert, zerstört genau das.
///
/// ⚠️ Gradzeichen U+00B0 (°), seit 13.08.2026 anstelle des ausgeschriebenen
/// „Grad". Zwei Zeichen sehen ihm zum Verwechseln ähnlich und sind falsch:
/// U+00BA (º, spanische Ordnungszahlen) und U+2070 (⁰, hochgestellte Null).
/// Das richtige Zeichen steht in Latin-1 und wird damit überall dargestellt —
/// auch dort, wo Emoji scheitern.
///
/// ⚠️ Dieselbe Zeile steht ein drittes Mal im Webauftritt (`SLOGAN` in
/// `header.php` auf icd360s.de). Das ist Absicht und kein Versehen: der
/// PHP-FPM-Pool jener Website läuft mit `clear_env = yes` und ohne `DB_PASS`,
/// kann die Datenbank also gar nicht lesen — und genau diese Trennung ist der
/// Grund, warum ein Einbruch in die Website keine Mitgliederdaten erreicht.
/// Wer den Slogan ändert, fasst DB, Website und diese Konstante an.
const String kVisitenkarteSlogan =
    'Integration · Chancen · Diversity · 360° Support';

/// Der Kern des Leitsatzes aus § 2 der Satzung, gekürzt auf Kartenlänge.
///
/// ⚠️ Der volle Wortlaut steht auf icd360s.de (`LEITSATZ` in header.php). Hier
/// steht eine Kurzform, und sie ist als solche erkennbar — der Satzungstext
/// wird nicht umformuliert und als Zitat ausgegeben.
const String kVisitenkarteLeitsatz =
    'Der Vorstand besteht mehrheitlich aus Menschen mit Behinderung. '
    'Selbstvertretung statt Fürsorge.';

/// Der Webauftritt, auf beiden Kartenseiten.
///
/// ⚠️ Steht als Konstante da, weil `vereineinstellungen` **keine** Spalte für
/// die Adresse hat — die Tabelle führt Anschrift, Register, Finanzamt und
/// Telefon, aber kein Web. `mailBuildSignature()` auf dem Server hält sie
/// deshalb ebenfalls im Code. Wer den Auftritt umzieht, fasst beide Stellen an;
/// eine Spalte dafür wäre die sauberere Lösung, aber das ist eine
/// Schemaänderung und gehört nicht in eine Visitenkarte.
const String kVisitenkarteWeb = 'icd360s.de';

/// Die sechs Arbeitsfelder für die Rückseite.
///
/// ⚠️ Quelle ist § 3 der Satzung, in der Bündelung, die auch der Webauftritt
/// unter „Was wir konkret tun" verwendet (`ueberuns.php`). Nicht frei
/// formuliert: was ein gemeinnütziger Verein anbietet, muss von der Satzung
/// gedeckt sein, und zwei verschiedene Selbstbeschreibungen wären genau die
/// Art Widerspruch, die bei einer Prüfung auffällt.
const List<(String, String)> kVisitenkarteLeistungen = [
  ('Behörden & Anträge', 'Begleitung, Formulare, Bescheide, Fristen'),
  ('Sprache', 'Dolmetschen, Übersetzen, Telefonate mit Ämtern'),
  ('Alltag', 'Einkauf, Arzt- und Therapietermine, Nahverkehr'),
  ('Bildung & Arbeit', 'Anerkennung, Bewerbung, digitale Grundbildung'),
  ('Geld & Existenz', 'Haushaltsplanung, Ansprüche, Nothilfe'),
  ('Zusammen leben', 'Begegnung, Sport, Freizeit, Nachbarschaft'),
];

/// ⚠️ Diese Zeile ist kein Kleingedrucktes.
///
/// § 3 Abs. 4 der Satzung schließt Rechts-, Steuer- und medizinische Beratung
/// ausdrücklich aus. Eine Visitenkarte wird weitergegeben, oft ohne dass ein
/// Gespräch dazu stattgefunden hat — wer sie ohne diesen Satz liest, kann den
/// Verein für eine Beratungsstelle halten. Für den Verein wäre das ein
/// Haftungsrisiko nach dem RDG, für die Person eine Enttäuschung mehr.
const String kVisitenkarteAbgrenzung =
    'Keine Rechts-, Steuer- oder medizinische Beratung (§ 3 Abs. 4 der Satzung) '
    '— wir vermitteln an zugelassene Fachleute weiter.';

// Farben: siehe lib/utils/visitenkarte_farben.dart — einmal für Bildschirm
// und Druck, damit der Ausdruck nicht anders aussieht als die Karte.

/// 85 × 55 mm, das ISO-nahe Standardformat einer Visitenkarte in Deutschland.
const double _kKartenBreite = 480;
const double _kKartenVerhaeltnis = 85 / 55;

class _VisitenkarteState extends State<Visitenkarte> {
  bool _showFront = true;
  bool _isLoading = true;
  bool _baueBogen = false;

  // ── Person ──────────────────────────────────────────────────────────────
  String _vorname = '';
  String _vorname2 = '';
  String _nachname = '';
  String _name = '';
  String _email = '';
  String _telefonMobil = '';
  String _telefonFix = '';

  /// Kommt fertig gebeugt und nummeriert vom Server („1. Vorsitzender").
  ///
  /// ⚠️ Lässt sich hier nicht ausrechnen: für „1." oder „2." müsste der Client
  /// die ids **aller** Vorsitzenden kennen, und die kennt er nicht. Vorher
  /// stand deshalb „Vorsitzer" auf der Karte — bei Michaela-Christine Weber
  /// zusätzlich in der falschen Form.
  String _funktion = '';
  bool _istGruender = false;
  List<SprachAnzeige> _sprachen = const [];

  // ── Verein ──────────────────────────────────────────────────────────────
  String _vereinsname = 'ICD360S e.V.';
  String _slogan = kVisitenkarteSlogan;
  String _vereinFestnetz = '';
  String _vereinAdresse = '';
  String _register = '';
  String _registergericht = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Profil und Vereinsdaten kommen aus zwei Endpunkten und werden deshalb
  /// **gleichzeitig** geholt: nacheinander wäre die Karte doppelt so lange
  /// leer, und die beiden hängen nicht voneinander ab.
  Future<void> _loadData() async {
    final ergebnisse = await Future.wait([
      _ladeProfil(),
      _ladeVerein(),
    ]);

    if (!mounted) return;
    setState(() {
      _uebernehmeProfil(ergebnisse[0]);
      _uebernehmeVerein(ergebnisse[1]);
      _isLoading = false;
    });
  }

  Future<Map<String, dynamic>> _ladeProfil() async {
    try {
      final r = await widget.apiService.getProfile(widget.mitgliedernummer);
      if (r['success'] == true) return r;
    } catch (e) {
      LoggerService().error('Visitenkarte: Profil: $e', tag: 'Visitenkarte');
    }
    return const {};
  }

  /// ⚠️ Ein Fehlschlag hier darf die Karte nicht leeren.
  ///
  /// `vereineinstellungen.php` verlangt eine Admin-Rolle. Das trifft im
  /// Vorsitzer-Programm immer zu — aber wenn es einmal nicht zutrifft oder das
  /// Netz fehlt, sollen Name, Amt und Mobilnummer trotzdem dastehen. Die
  /// Vereinszeilen entfallen dann einfach; sie werden nirgends hart erwartet.
  Future<Map<String, dynamic>> _ladeVerein() async {
    try {
      final r = await widget.apiService.getVereineinstellungen();
      if (r['success'] == true && r['data'] is Map) {
        return Map<String, dynamic>.from(r['data'] as Map);
      }
    } catch (e) {
      LoggerService().error('Visitenkarte: Verein: $e', tag: 'Visitenkarte');
    }
    return const {};
  }

  String _text(Map<String, dynamic> m, String schluessel) =>
      (m[schluessel] ?? '').toString().trim();

  void _uebernehmeProfil(Map<String, dynamic> p) {
    _vorname = _text(p, 'vorname');
    _vorname2 = _text(p, 'vorname2');
    _nachname = _text(p, 'nachname');
    _name = _text(p, 'name');
    _email = _text(p, 'email');
    _telefonMobil = _text(p, 'telefon_mobil');
    _telefonFix = _text(p, 'telefon_fix');
    _istGruender = p['ist_gruender'] == true;

    // Ältere Server kennen `funktion` nicht. Dann bleibt es bei der alten,
    // ungebeugten Bezeichnung — eine leere Zeile wäre schlechter als eine
    // grobe.
    _funktion = _text(p, 'funktion');
    if (_funktion.isEmpty) _funktion = _rolleGrob(_text(p, 'role'));

    final roh = p['languages'];
    _sprachen = roh is List ? sprachAnzeigen(roh) : const [];
  }

  void _uebernehmeVerein(Map<String, dynamic> v) {
    final name = _text(v, 'vereinsname');
    if (name.isNotEmpty) _vereinsname = name;
    // Nur überschreiben, wenn wirklich etwas dasteht: eine leere Spalte darf
    // die Zeile unter dem Vereinsnamen nicht verschwinden lassen.
    final slogan = _text(v, 'slogan');
    if (slogan.isNotEmpty) _slogan = slogan;
    _vereinFestnetz = _text(v, 'telefon_fix');
    _vereinAdresse = _text(v, 'adresse');
    _register = _text(v, 'registernummer');
    _registergericht = _text(v, 'registergericht');
  }

  /// Rückfall, wenn der Server `funktion` nicht liefert. Ohne Beugung und ohne
  /// Nummer — genau das, was die Karte vorher immer angezeigt hat.
  String _rolleGrob(String role) => switch (role) {
        'vorsitzer' => 'Vorsitz',
        'schatzmeister' => 'Schatzmeister',
        'kassierer' => 'Kassenwart',
        'mitgliedergrunder' => 'Gründungsmitglied',
        '' => '',
        _ => 'Mitglied',
      };

  /// Der Festnetzanschluss der Person, sonst der des Vereins.
  ///
  /// ⚠️ In `users.telefon_fix` steht bei allen sechs Vorstandsmitgliedern
  /// NULL — es gibt im Verein genau einen Festnetzanschluss, und der gehört
  /// dem Verein. Der Rückfall ist deshalb der Regelfall, nicht die Ausnahme.
  /// Trägt jemand später eine eigene Durchwahl ein, gewinnt sie.
  String get _festnetz => _telefonFix.isNotEmpty ? _telefonFix : _vereinFestnetz;

  void _flipCard() => setState(() => _showFront = !_showFront);

  /// Der Kartinhalt für den Druckbogen.
  ///
  /// ⚠️ Wird aus **demselben** Zustand gebaut, aus dem die Karte auf dem Schirm
  /// entsteht. Zwei Wege zu denselben Daten wären zwei Wege, die auseinander
  /// laufen — und man sähe es erst auf gedrucktem Papier.
  VisitenkarteDaten get _daten => VisitenkarteDaten(
        vereinsname: _vereinsname,
        slogan: _slogan,
        vorname: vornameVoll(_vorname, _vorname2),
        nachname: nachnameOder(_nachname, fallbackName: _name),
        funktion: _funktion,
        istGruender: _istGruender,
        sprachen: _sprachen,
        email: _email,
        festnetz: _festnetz,
        mobil: _telefonMobil,
        web: kVisitenkarteWeb,
        mitgliedernummer: widget.mitgliedernummer,
        anschrift: _anschriftEinzeilig,
        register: [
          if (_register.isNotEmpty) _register,
          if (_registergericht.isNotEmpty) _registergericht,
        ].join(' · '),
      );

  /// Die Anschrift ohne c/o-Zeile, in einer Zeile.
  ///
  /// Die c/o-Zeile wiederholt nur den Namen, der auf der Vorderseite steht —
  /// auf der Rückseite einer 85-mm-Karte ist dafür kein Platz zu verschenken.
  String get _anschriftEinzeilig => _vereinAdresse
      .split(RegExp(r'\r\n|\r|\n'))
      .map((z) => z.trim())
      .where((z) => z.isNotEmpty && !z.toLowerCase().startsWith('c/o'))
      .join(' · ');

  Future<void> _druckbogen() async {
    setState(() => _baueBogen = true);
    try {
      await visitenkartenBogenTeilen(_daten);
    } catch (e) {
      LoggerService().error('Visitenkarte: PDF: $e', tag: 'Visitenkarte');
      if (!mounted) return;
      // Der Grund muss auf den Schirm — ein stiller Fehlschlag sieht für den
      // Nutzer genauso aus wie ein Knopf, der nichts tut.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF nicht erstellt: $e')),
      );
    } finally {
      if (mounted) setState(() => _baueBogen = false);
    }
  }

  Future<void> _kopiereKontakt() async {
    final zeilen = <String>[
      personName(_vorname, _vorname2, _nachname, fallbackName: _name),
      if (_funktion.isNotEmpty) _funktion + (_istGruender ? ' · Gründer' : ''),
      _vereinsname,
      if (_email.isNotEmpty) _email,
      if (_festnetz.isNotEmpty) 'Tel. $_festnetz',
      if (_telefonMobil.isNotEmpty) 'Mobil $_telefonMobil',
      'https://$kVisitenkarteWeb',
    ];
    await Clipboard.setData(ClipboardData(text: zeilen.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kontaktdaten kopiert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Auf dem Telefon ist der Dialog schmaler als die Karte. Dann wird
            // die Karte schmaler statt abgeschnitten — das Verhältnis bleibt.
            final breite = math.min(_kKartenBreite, constraints.maxWidth);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _flipCard,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: _showFront
                        ? _buildVorderseite(breite)
                        : _buildRuckseite(breite),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _flipCard,
                      icon: const Icon(Icons.flip_to_back, size: 18),
                      label: Text(_showFront ? 'Rückseite' : 'Vorderseite'),
                    ),
                    TextButton.icon(
                      onPressed: _isLoading ? null : _kopiereKontakt,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Kontaktdaten kopieren'),
                    ),
                    TextButton.icon(
                      onPressed: (_isLoading || _baueBogen) ? null : _druckbogen,
                      icon: _baueBogen
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.print, size: 18),
                      label: Text('$kKartenProBogen Karten als PDF'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// ⚠️ Weiß mit einem 6-mm-Tealbalken an der Stange — nicht mehr vollflächig
  /// eingefärbt.
  ///
  /// Die vollflächige Fassung sah auf dem Schirm gut aus und war für den Druck
  /// ein Fehlkauf: zehn Karten × zwei Seiten sind bei einem Tintendrucker eine
  /// halbe Patrone je Bogen, das Papier wellt sich, der Auftrag wird fleckig.
  /// Jetzt trägt die Karte **7 % Farbfläche statt 100 %** (6 × 55 mm von
  /// 85 × 55 mm).
  ///
  /// ⚠️ Bildschirm und Druck zeigen bewusst DASSELBE. Eine Karte, die man auf
  /// dem Schirm abnimmt und die dann anders aus dem Drucker kommt, wäre keine
  /// Vorschau, sondern eine zweite Gestaltung.
  ///
  /// Nebenbei wird der Kontrast dadurch besser: dunkles Teal auf Weiß sind
  /// 7,17 : 1, und eine helle Fläche verliert im Druck weniger als eine große
  /// dunkle.
  BoxDecoration _kartenRahmen() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      );

  /// Der Balken an der Stange, auf beiden Seiten gleich.
  Widget _balken() => Container(width: 22, color: kVkTonHell);

  // ══ Vorderseite ═════════════════════════════════════════════════════════

  Widget _buildVorderseite(double breite) {
    return Container(
      key: const ValueKey('front'),
      width: breite,
      constraints: BoxConstraints(minHeight: breite / _kKartenVerhaeltnis),
      decoration: _kartenRahmen(),
      clipBehavior: Clip.antiAlias,
      child: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: CircularProgressIndicator(),
              ),
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _balken(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _kopf()),
                              _sprachSpalte(),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _namensZeile(),
                          const SizedBox(height: 4),
                          Text(
                            [_funktion, if (_istGruender) 'Gründer']
                                .where((t) => t.isNotEmpty)
                                .join('   ·   '),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: kVkTonHell,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _kontaktBlock(),
                          const SizedBox(height: 10),
                          _fuss(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _kopf() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _vereinsname,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: kVkTonHell,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 5),
        Container(height: 2.5, width: 44, color: kVkTonHell),
        const SizedBox(height: 6),
        Text(
          _slogan,
          style: const TextStyle(
            fontSize: 10.5,
            color: kVkTextLeise,
            letterSpacing: 0.2,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  /// Rollstuhlsymbol über den Sprachen, rechts neben dem Amt.
  ///
  /// ⚠️ Das Symbol steht nicht dekorativ da: es ist die Kurzform des
  /// Leitsatzes aus § 2 der Satzung. Deshalb trägt es eine Beschriftung für
  /// Vorleseprogramme und einen Tooltip — ein Bild, dessen Bedeutung nur
  /// Eingeweihte kennen, hätte auf einer Karte nichts verloren.
  /// Vorname(n) und Nachname auf **einer** Zeile.
  ///
  /// ⚠️ Niemand schreibt seinen Familiennamen unter seinen Vornamen; beim
  /// Weiterreichen liest sich das wie zwei Angaben statt wie ein Name. Der
  /// Nachname bleibt trotzdem hervorgehoben — halbfett auf derselben Zeile.
  ///
  /// ⚠️ Beide Teile kommen aus den Einzelfeldern, nicht aus `name` per
  /// Leerzeichen-Split: der hatte bei „Andreea Denisa Camelia Raduica" den
  /// Vornamen auf „Andreea" verkürzt. `vorname2` wird nur angehängt, wenn er
  /// nicht schon im Vornamen steckt (siehe lib/utils/person_name.dart).
  Widget _namensZeile() {
    final vor = vornameVoll(_vorname, _vorname2);
    final nach = nachnameOder(_nachname, fallbackName: _name);

    return Text.rich(
      TextSpan(
        children: [
          if (vor.isNotEmpty)
            TextSpan(
              text: nach.isEmpty ? vor : '$vor ',
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          if (nach.isNotEmpty)
            TextSpan(
              text: nach,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
        ],
      ),
      // Lange Namen brechen um, statt beschnitten zu werden — ein halber Name
      // ist schlimmer als eine zweite Zeile. Die Karte darf dafür wachsen.
      style: const TextStyle(
        fontSize: 19,
        color: kVkTextDunkel,
        letterSpacing: 0.2,
        height: 1.2,
      ),
    );
  }

  Widget _sprachSpalte() {
    // ⚠️ Der eingefasste Block ist keine Verzierung. Ohne ihn steht das
    // Rollstuhl-Emoji frei auf dem Blau — und Noto Color Emoji zeichnet ♿ mit
    // eigener blauer Kachel, also Blau auf Blau. Im gerenderten Bild sah es aus
    // wie ein versehentlich liegengebliebener Knopf. Die leicht aufgehellte
    // Fläche gibt dem Emoji einen Grund und fasst Symbol und Sprachen als das
    // zusammen, was sie sind: die Angaben zur Erreichbarkeit dieser Person.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kVkTonFlaeche,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kVkTonHell.withAlpha(60)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: kVisitenkarteLeitsatz,
            child: Semantics(
              label: 'Selbstvertretung von Menschen mit Behinderung',
              child: const Text('♿', style: TextStyle(fontSize: 20)),
            ),
          ),
          if (_sprachen.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in _sprachen) _sprachChip(s),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Flagge **und** Kürzel, immer beide.
  ///
  /// ⚠️ Auf Windows gibt es keine Flaggen-Emoji — Segoe UI Emoji bildet die
  /// Regional-Indicator-Paare nicht ab, dort stehen dann die zwei Buchstaben
  /// des Ländercodes. Und eine Flagge ist ohnehin keine Sprache (🇬🇧 ist ein
  /// Land, Englisch wird auch anderswo gesprochen). Das Kürzel trägt die
  /// Information, die Flagge hilft beim schnellen Erfassen. Details in
  /// `lib/utils/sprach_flaggen.dart`.
  Widget _sprachChip(SprachAnzeige s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.5),
      child: Tooltip(
        message: s.bezeichnung,
        child: Semantics(
          label: 'Sprache: ${s.bezeichnung}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ⚠️ Bilddatei statt Emoji. Auf Windows bildet Segoe UI Emoji die
              // Regional-Indicator-Paare nicht ab — dort stand vorher nur der
              // Ländercode, also zweimal dasselbe untereinander. Mit der Datei
              // sehen alle vier Plattformen und der Druck dasselbe.
              if (flaggenPfad(s.code) != null)
                Image.asset(
                  flaggenPfad(s.code)!,
                  width: 17,
                  // `contain`, nicht `fill`: die Fahnen haben verschiedene
                  // Seitenverhältnisse und würden sonst gestreckt.
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              const SizedBox(height: 2),
              Text(
                s.kuerzel,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: kVkTextLeise,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kontaktBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_email.isNotEmpty)
          _kontaktZeile(Icons.alternate_email, Text(
            _email,
            style: const TextStyle(fontSize: 12, color: kVkTextDunkel),
            overflow: TextOverflow.ellipsis,
          )),
        if (_festnetz.isNotEmpty)
          _kontaktZeile(
            Icons.phone,
            PhoneText(
              _festnetz,
              color: kVkTonHell,
              style: const TextStyle(fontSize: 12, color: kVkTextDunkel),
            ),
          ),
        if (_telefonMobil.isNotEmpty)
          _kontaktZeile(
            Icons.smartphone,
            PhoneText(
              _telefonMobil,
              color: kVkTonHell,
              style: const TextStyle(fontSize: 12, color: kVkTextDunkel),
            ),
          ),
      ],
    );
  }

  Widget _kontaktZeile(IconData icon, Widget inhalt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: kVkTonHell),
          const SizedBox(width: 7),
          Flexible(child: inhalt),
        ],
      ),
    );
  }

  /// Unten links die Benutzernummer, unten rechts der Webauftritt.
  ///
  /// Vorher stand rechts ein Ausweis-Symbol ohne Beschriftung — es sagte
  /// dasselbe wie die Nummer links, nur ungenauer. Die Web-Adresse ist die
  /// einzige Kontaktangabe, die auf der Karte noch fehlte, und der Globus ist
  /// eines der wenigen Symbole, die ohne Erklärung verstanden werden.
  Widget _fuss() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            widget.mitgliedernummer,
            style: TextStyle(
              fontSize: 11,
              color: kVkTextLeise,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 14, color: kVkTonHell),
            const SizedBox(width: 6),
            Text(
              kVisitenkarteWeb,
              style: TextStyle(
                fontSize: 12,
                color: kVkTonHell,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ══ Rückseite ═══════════════════════════════════════════════════════════

  Widget _buildRuckseite(double breite) {
    return Container(
      key: const ValueKey('back'),
      width: breite,
      constraints: BoxConstraints(minHeight: breite / _kKartenVerhaeltnis),
      decoration: _kartenRahmen(),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _balken(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 12),
                child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Was wir tun',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: kVkTonDunkel,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                _vereinsname,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: kVkTextLeise,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Container(height: 2, width: 42, color: kVkTonHell),
          const SizedBox(height: 10),
          for (final (titel, was) in kVisitenkarteLeistungen)
            _leistungsZeile(titel, was),
          const SizedBox(height: 8),
          _leitsatzBlock(),
          const SizedBox(height: 7),
          Text(
            kVisitenkarteAbgrenzung,
            style: TextStyle(
              fontSize: 8.5,
              height: 1.3,
              fontStyle: FontStyle.italic,
              color: kVkTextLeise,
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 7),
                    _ruckseitenFuss(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leistungsZeile(String titel, String was) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: kVkTonHell,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$titel  ',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kVkTextDunkel,
                    ),
                  ),
                  TextSpan(
                    text: was,
                    style: TextStyle(
                      fontSize: 10,
                      color: kVkTextLeise,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leitsatzBlock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: kVkTonFlaeche,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: kVkTonHell, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('♿', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kVisitenkarteLeitsatz,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.35,
                color: kVkTextDunkel,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruckseitenFuss() {
    // Die Anschrift steht in `vereineinstellungen.adresse` mehrzeilig, mit der
    // c/o-Zeile voran. Auf der Karte wird daraus eine Zeile — der Platz reicht
    // nicht für drei, und die c/o-Zeile wiederholt nur den Namen von vorne.
    final adresszeilen = _vereinAdresse
        .split(RegExp(r'\r\n|\r|\n'))
        .map((z) => z.trim())
        .where((z) => z.isNotEmpty && !z.toLowerCase().startsWith('c/o'))
        .toList();

    final register = [
      if (_register.isNotEmpty) _register,
      if (_registergericht.isNotEmpty) _registergericht,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (adresszeilen.isNotEmpty)
          Text(
            adresszeilen.join(' · '),
            style: TextStyle(fontSize: 9, color: kVkTextLeise),
          ),
        Text(
          [
            kVisitenkarteWeb,
            if (register.isNotEmpty) register,
            'gemeinnützig',
          ].join(' · '),
          style: TextStyle(fontSize: 9, color: kVkTextLeise),
        ),
      ],
    );
  }
}
