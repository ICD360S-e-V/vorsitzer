import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'phone_link.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../utils/person_name.dart';
import '../utils/sprach_flaggen.dart';

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
/// Der Webauftritt, auf beiden Kartenseiten.
///
/// ⚠️ Steht als Konstante da, weil `vereineinstellungen` **keine** Spalte für
/// die Adresse hat — die Tabelle führt Anschrift, Register, Finanzamt und
/// Telefon, aber kein Web. `mailBuildSignature()` auf dem Server hält sie
/// deshalb ebenfalls im Code. Wer den Auftritt umzieht, fasst beide Stellen an;
/// eine Spalte dafür wäre die sauberere Lösung, aber das ist eine
/// Schemaänderung und gehört nicht in eine Visitenkarte.
const String kVisitenkarteWeb = 'icd360s.de';

const String kVisitenkarteLeitsatz =
    'Der Vorstand besteht mehrheitlich aus Menschen mit Behinderung. '
    'Selbstvertretung statt Fürsorge.';

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

const Color _kKartenBlau = Color(0xFF4a90d9);
const Color _kKartenBlauDunkel = Color(0xFF357abd);

/// 85 × 55 mm, das ISO-nahe Standardformat einer Visitenkarte in Deutschland.
const double _kKartenBreite = 480;
const double _kKartenVerhaeltnis = 85 / 55;

class _VisitenkarteState extends State<Visitenkarte> {
  bool _showFront = true;
  bool _isLoading = true;

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
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  BoxDecoration _kartenRahmen({required bool vorne}) => BoxDecoration(
        gradient: vorne
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kKartenBlau, _kKartenBlauDunkel],
              )
            : null,
        color: vorne ? null : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: vorne ? null : Border.all(color: _kKartenBlau, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(38),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      );

  // ══ Vorderseite ═════════════════════════════════════════════════════════

  Widget _buildVorderseite(double breite) {
    return Container(
      key: const ValueKey('front'),
      width: breite,
      constraints: BoxConstraints(minHeight: breite / _kKartenVerhaeltnis),
      decoration: _kartenRahmen(vorne: true),
      padding: const EdgeInsets.all(20),
      child: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _kopf(),
                // 12, nicht 18: mit den 18 kam die Karte bei geladener Schrift
                // auf 480 × 317 statt auf die 310,6 des Kartenformats. Gemessen,
                // nicht geschätzt — siehe test/_ansicht_visitenkarte.dart.
                const SizedBox(height: 12),
                _personMitSprachen(),
                const SizedBox(height: 14),
                _kontaktBlock(),
                const SizedBox(height: 12),
                _fuss(),
              ],
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
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 3,
          width: 52,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(204),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _slogan,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.white.withAlpha(225),
            letterSpacing: 0.3,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _personMitSprachen() {
    return Row(
      // Mittig statt oben: der Sprachblock soll auf Höhe des AMTES stehen, nicht
      // auf Höhe des Vornamens. Oben ausgerichtet hing er im Bild über der
      // Namenszeile und wirkte wie ein abgelegter Knopf.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _namensZeile(),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (_funktion.isNotEmpty) _pille(_funktion),
                  if (_istGruender) _pille('Gründer', gedaempft: true),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _sprachSpalte(),
      ],
    );
  }

  /// Vorname(n) und Nachname auf **einer** Zeile.
  ///
  /// ⚠️ Vorher standen sie untereinander. Das ist auf einer Visitenkarte falsch:
  /// niemand schreibt seinen Familiennamen unter seinen Vornamen, und beim
  /// Weiterreichen liest es sich wie zwei Angaben statt wie ein Name.
  ///
  /// Der Nachname bleibt trotzdem hervorgehoben — halbfett auf derselben Zeile,
  /// nicht auf einer eigenen. Das ist die übliche Setzung auf Geschäftskarten
  /// und hält den Familiennamen auffindbar, ohne den Namen zu zerreißen.
  ///
  /// ⚠️ Beide Teile kommen aus den Einzelfeldern, nicht aus `name` per
  /// Leerzeichen-Split. Der Split hatte bei „Andreea Denisa Camelia Raduica"
  /// den Vornamen auf „Andreea" verkürzt und drei Namensteile in den Nachnamen
  /// geschoben; `vorname2` wird nur angehängt, wenn er nicht schon im Vornamen
  /// steckt (siehe lib/utils/person_name.dart).
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
      // Lange Namen brechen um, statt beschnitten oder gestaucht zu werden —
      // ein halber Name ist schlimmer als eine zweite Zeile. Die Karte darf
      // dafür wachsen, ihre Höhe ist eine Mindesthöhe.
      style: const TextStyle(
        fontSize: 18,
        color: Colors.white,
        letterSpacing: 0.3,
        height: 1.2,
      ),
    );
  }

  Widget _pille(String text, {bool gedaempft = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(gedaempft ? 26 : 51),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(gedaempft ? 71 : 102)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: gedaempft ? FontWeight.w400 : FontWeight.w500,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  /// Rollstuhlsymbol über den Sprachen, rechts neben dem Amt.
  ///
  /// ⚠️ Das Symbol steht nicht dekorativ da: es ist die Kurzform des
  /// Leitsatzes aus § 2 der Satzung. Deshalb trägt es eine Beschriftung für
  /// Vorleseprogramme und einen Tooltip — ein Bild, dessen Bedeutung nur
  /// Eingeweihte kennen, hätte auf einer Karte nichts verloren.
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
        color: Colors.white.withAlpha(28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(64)),
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
              if (s.flagge != null)
                Text(s.flagge!, style: const TextStyle(fontSize: 15)),
              Text(
                s.kuerzel,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Colors.white.withAlpha(220),
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
            style: const TextStyle(fontSize: 12, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          )),
        if (_festnetz.isNotEmpty)
          _kontaktZeile(
            Icons.phone,
            PhoneText(
              _festnetz,
              color: Colors.white,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        if (_telefonMobil.isNotEmpty)
          _kontaktZeile(
            Icons.smartphone,
            PhoneText(
              _telefonMobil,
              color: Colors.white,
              style: const TextStyle(fontSize: 12, color: Colors.white),
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
          Icon(icon, size: 14, color: Colors.white70),
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
              color: Colors.white.withAlpha(178),
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
            Icon(Icons.language, size: 14, color: Colors.white.withAlpha(200)),
            const SizedBox(width: 6),
            Text(
              kVisitenkarteWeb,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withAlpha(235),
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
      decoration: _kartenRahmen(vorne: false),
      padding: const EdgeInsets.all(18),
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
                    color: _kKartenBlauDunkel,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                _vereinsname,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Container(height: 2, width: 42, color: _kKartenBlau),
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
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 7),
          _ruckseitenFuss(),
        ],
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
                color: _kKartenBlau,
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
                      color: Color(0xFF243B53),
                    ),
                  ),
                  TextSpan(
                    text: was,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade700,
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
        color: _kKartenBlau.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: _kKartenBlau, width: 3)),
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
                color: Color(0xFF243B53),
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
            style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
          ),
        Text(
          [
            kVisitenkarteWeb,
            if (register.isNotEmpty) register,
            'gemeinnützig',
          ].join(' · '),
          style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
