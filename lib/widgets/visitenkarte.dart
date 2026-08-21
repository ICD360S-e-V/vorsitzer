import 'dart:math' as math;

import 'package:barcode_widget/barcode_widget.dart';
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
import '../utils/visitenkarte_masse.dart';
import '../utils/visitenkarte_pdf.dart';
import '../utils/visitenkarte_sprachen.dart';
import '../utils/app_farben.dart';

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

/// Rückfall für den Webauftritt, wenn `vereineinstellungen.website` nicht zu
/// erreichen ist.
///
/// ⚠️ Die **Datenbank ist die Quelle**. Die Spalte gibt es seit dem
/// 14.08.2026; vorher stand die Adresse nur hier im Code, und der Auftritt
/// wäre bei einem Umzug an zwei Stellen zu ändern gewesen — einer davon in
/// einer Datei, die niemand vermutet, der eine Web-Adresse sucht.
///
/// Hier steht nur, was angezeigt wird, wenn der Aufruf scheitert: dann eine
/// womöglich veraltete Adresse statt einer leeren Stelle in der Fußzeile.
const String kVisitenkarteWeb = 'icd360s.de';

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

  /// Kommt fertig gebeugt und nummeriert vom Server („1. Vorsitzender").
  ///
  /// ⚠️ Lässt sich hier nicht ausrechnen: für „1." oder „2." müsste der Client
  /// die ids **aller** Vorsitzenden kennen, und die kennt er nicht. Vorher
  /// stand deshalb „Vorsitzer" auf der Karte — bei Michaela-Christine Weber
  /// zusätzlich in der falschen Form.
  String _funktion = '';
  bool _istGruender = false;
  List<SprachAnzeige> _sprachen = const [];

  /// Anredeform und Nummer des Vorsitzes — die Bausteine, aus denen das Amt in
  /// einer anderen Sprache als Deutsch neu gesetzt wird. Kommen seit dem
  /// 14.08.2026 vom Server; bei einem älteren bleibt es bei [_funktion].
  String _anredeform = 'neutral';
  int? _vorsitzNr;

  /// Die Sprache, in der Karte und Bogen gesetzt werden.
  ///
  /// ⚠️ Hat **nichts** mit [_sprachen] zu tun. Die Fahnen auf der Karte sagen,
  /// welche Sprachen die Person spricht; diese hier sagt, in welcher Sprache
  /// die Karte gedruckt wird. Zwei verschiedene Aussagen, deshalb auch zwei
  /// getrennte Bedienelemente — die Fahnen auf der Karte sind nicht anklickbar.
  String _kartenSprache = kVisitenkarteStandardsprache;

  VisitenkarteTexte get _t => visitenkarteTexte(_kartenSprache);

  // ── Verein ──────────────────────────────────────────────────────────────
  String _vereinsname = 'ICD360S e.V.';
  String _slogan = kVisitenkarteSlogan;
  String _rolle = '';
  String _web = kVisitenkarteWeb;
  String _vereinFestnetz = '';
  String _vereinMobil = '';
  String _vereinFax = '';
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
    _rolle = _text(p, 'role');
    _name = _text(p, 'name');
    _istGruender = p['ist_gruender'] == true;

    // Ältere Server kennen `funktion` nicht. Dann bleibt es bei der alten,
    // ungebeugten Bezeichnung — eine leere Zeile wäre schlechter als eine
    // grobe.
    _funktion = _text(p, 'funktion');
    if (_funktion.isEmpty) _funktion = _rolleGrob(_text(p, 'role'));

    final anrede = _text(p, 'anredeform');
    _anredeform = anrede.isEmpty ? 'neutral' : anrede;
    final nr = p['vorsitz_nr'];
    _vorsitzNr = nr is int ? nr : int.tryParse('${nr ?? ''}');

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
    // Nur überschreiben, wenn wirklich etwas dasteht — eine leere Spalte darf
    // die Fußzeile nicht leeren.
    final web = _text(v, 'website');
    if (web.isNotEmpty) _web = web;
    _vereinFestnetz = _text(v, 'telefon_fix');
    _vereinMobil = _text(v, 'mobil');
    _vereinFax = _text(v, 'fax');
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

  /// ⚠️ Auf der Visitenkarte stehen die Anschlüsse des **Vereins**, nicht die
  /// der Person.
  ///
  /// Entscheidung des Users vom 14.08.2026, und sie hat einen handfesten
  /// Grund: eine Visitenkarte wird weitergegeben und liegt danach in fremden
  /// Ablagen. Wer sie in fünf Jahren hervorholt, soll den Verein erreichen —
  /// auch dann, wenn die Person, die sie überreicht hat, längst nicht mehr im
  /// Vorstand ist. Private Anschlüsse würden mit der Karte weiterwandern und
  /// blieben erreichbar, lange nachdem sie es sollten.
  ///
  /// `users.telefon_mobil` und `users.telefon_fix` bleiben davon unberührt —
  /// sie werden im Profil und in der Mail-Signatur weiter verwendet.
  /// Die Vereinsadresse dieser Person — abgeleitet, nicht aus `users.email`.
  ///
  /// Ämter bekommen ihre Initialen (`icd@`, `mcw@`), alle übrigen die
  /// Mitgliedsnummer. Die Regel und ihre Begründung stehen bei
  /// [vereinsAdresse]; kurz: in `users.email` steht bei mehreren
  /// Vorstandsmitgliedern eine **private** Adresse, und die gehört nicht auf
  /// eine Karte, die der Verein ausgibt und die weitergereicht wird.
  String get _email => vereinsAdresse(
        rolle: _rolle,
        mitgliedernummer: widget.mitgliedernummer,
        vorname: _vorname,
        vorname2: _vorname2,
        nachname: _nachname,
        domain: _web.isNotEmpty ? _web : kVisitenkarteWeb,
      );

  String get _festnetz => _vereinFestnetz;
  String get _fax => _vereinFax;
  String get _mobil => _vereinMobil;

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
        rolleKey: _rolle,
        anredeform: _anredeform,
        vorsitzNr: _vorsitzNr,
        istGruender: _istGruender,
        sprachen: _sprachen,
        email: _email,
        festnetz: _festnetz,
        fax: _fax,
        mobil: _mobil,
        web: _web,
        mitgliedernummer: widget.mitgliedernummer,
        anschrift: _anschriftEinzeilig,
        register: [
          if (_register.isNotEmpty) _register,
          if (_registergericht.isNotEmpty) _registergericht,
        ].join(' · '),
      );

  /// Die Fahnenleiste, mit der die Sprache der Karte gewählt wird.
  ///
  /// ⚠️ **Nicht zu verwechseln mit den Fahnen auf der Karte selbst.** Die dort
  /// sagen, welche Sprachen die Person spricht, und sind bewusst nicht
  /// anklickbar. Diese hier sagt, in welcher Sprache Karte und Bogen gesetzt
  /// werden. Beides über dieselben Fahnen zu bedienen, hieße zwei verschiedene
  /// Aussagen in ein Bedienelement zu legen.
  ///
  /// ⚠️ Die Reihenfolge ist nicht alphabetisch: vorn stehen die Sprachen, die
  /// im Verein tatsächlich vorkommen (Stand 14.08.2026: de 21, ro 14, ru 10,
  /// en 4, uk 3, tr 1 Mitglieder). Damit ist der Regelfall ohne Scrollen
  /// erreichbar; alphabetisch läge Rumänisch hinter zwanzig Fahnen, die
  /// niemand braucht.
  Widget _sprachwahl(double breite) {
    const vorn = ['de', 'ro', 'ru', 'uk', 'en', 'tr'];
    final rest = kVisitenkarteSprachen.keys
        .where((c) => !vorn.contains(c))
        .toList()
      ..sort((a, b) => kVisitenkarteSprachen[a]!
          .eigenname
          .toLowerCase()
          .compareTo(kVisitenkarteSprachen[b]!.eigenname.toLowerCase()));
    final reihenfolge = [...vorn, ...rest];

    return SizedBox(
      width: breite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sprache der Karte · ${_t.eigenname}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kVkTextLeise,
            ),
          ),
          const SizedBox(height: 6),
          // ⚠️ `Wrap`, KEIN waagerechtes Scrollen.
          //
          // Die erste Fassung war ein `SingleChildScrollView` in der
          // Waagerechten. Auf dem Telefon geht das; am Rechner nicht: Flutter
          // lässt Mausziehen an Scrollflächen standardmäßig nicht zu und
          // zeichnet keine Bildlaufleiste. Auf dem Linux-Rechner des Vorstands
          // war deshalb hinter Frankreich Schluss — die restlichen 17 Fahnen
          // waren da, nur unerreichbar. Eine Bedienung, die man nicht sieht,
          // gibt es nicht.
          //
          // Umgebrochen sind es bei 480 dp Kartenbreite drei Reihen, auf einem
          // 360-dp-Telefon vier. Das kostet Höhe und ist es wert.
          Wrap(
            children: [
              for (final code in reihenfolge) _sprachKnopf(code),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sprachKnopf(String code) {
    final t = kVisitenkarteSprachen[code]!;
    final pfad = flaggenPfad(code);
    final gewaehlt = code == _kartenSprache;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: t.eigenname,
        child: Semantics(
          button: true,
          selected: gewaehlt,
          label: 'Karte auf ${t.eigenname}',
          child: InkWell(
            onTap: () => setState(() => _kartenSprache = code),
            borderRadius: BorderRadius.circular(6),
            // ⚠️ 44 dp Trefferfläche (WCAG 2.5.5). Die Fahne selbst ist 30 dp
            // breit; in einem Verein, dessen Vorstand mehrheitlich aus Menschen
            // mit Behinderung besteht, ist das keine Feinheit.
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: gewaehlt ? kVkTonFlaeche : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: gewaehlt ? kVkTonHell : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: pfad != null
                      ? Image.asset(pfad,
                          width: 30, height: 20, fit: BoxFit.contain)
                      // Sollte nie eintreten — ein Test hält Fahnen und
                      // Fassungen deckungsgleich. Falls doch, lieber das
                      // Kürzel als ein Loch in der Leiste.
                      : Text(code.toUpperCase(),
                          style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
      await visitenkartenBogenTeilen(_daten, sprache: _kartenSprache);
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
      if (_fax.isNotEmpty) 'Fax $_fax',
      if (_mobil.isNotEmpty) 'Mobil $_mobil',
      'https://$_web',
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
                const SizedBox(height: 10),
                _sprachwahl(breite),
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
        color: F.flaeche,
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

  /// Die Vorderseite — **maßgleich mit dem Druckbogen**.
  ///
  /// ⚠️ Jede Größe kommt aus `lib/utils/visitenkarte_masse.dart` und wird mit
  /// [bildschirmSkala] umgerechnet. Vorher hatte der Schirm eigene Zahlen, und
  /// beim Nachmessen war jedes Element 9 bis 39 % kleiner als im Druck — das
  /// Sprachkürzel um 39 %, der Tealbalken um 35 %. Wer die Karte auf dem Schirm
  /// abnimmt und dann druckt, bekam etwas anderes, als er abgenommen hatte.
  ///
  /// Was der Schirm zusätzlich kann und der Druck nicht: die Rufnummern sind
  /// wählbar (`PhoneText`). Das ändert nichts an der Größe.
  Widget _buildVorderseite(double breite) {
    final k = bildschirmSkala(breite);

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
                  Container(width: kBalkenBreite * k, color: kVkTonHell),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(kPolster * k),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _kopf(k)),
                              _sprachSpalte(k),
                            ],
                          ),
                          SizedBox(height: kAbstandLinieSlogan * k),
                          Text(
                            _slogan,
                            style: TextStyle(
                              fontSize: kGradSlogan * k,
                              color: kVkTextLeise,
                              height: kZeilenHoehe,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _namensZeile(k),
                                    SizedBox(height: kAbstandNameAmt * k),
                                    Text(
                                      [
                                        _daten.funktionIn(_t),
                                        if (_istGruender) _t.gruender
                                      ]
                                          .where((t) => t.isNotEmpty)
                                          .join('  ·  '),
                                      style: TextStyle(
                                        fontSize: kGradAmt * k,
                                        fontWeight: FontWeight.w700,
                                        color: kVkTonHell,
                                        height: kZeilenHoehe,
                                      ),
                                    ),
                                    SizedBox(height: kAbstandAmtKontakt * k),
                                    _kontaktBlock(k),
                                  ],
                                ),
                              ),
                              SizedBox(width: kAbstandQrSpalte * k),
                              _qrFeld(k),
                            ],
                          ),
                          const Spacer(),
                          _fuss(k),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _kopf(double k) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _vereinsname,
          style: TextStyle(
            fontSize: kGradVereinsname * k,
            fontWeight: FontWeight.bold,
            color: kVkTonHell,
            letterSpacing: 0.5 * k,
            height: kZeilenHoehe,
          ),
        ),
        SizedBox(height: kAbstandNameLinie * k),
        Container(
          height: kLinieHoehe * k,
          width: kLinieBreite * k,
          color: kVkTonHell,
        ),
      ],
    );
  }

  /// Vorname(n) und Nachname auf **einer** Zeile, Nachname halbfett.
  ///
  /// ⚠️ Beide Teile kommen aus den Einzelfeldern, nicht aus `name` per
  /// Leerzeichen-Split: der hatte bei „Andreea Denisa Camelia Raduica" den
  /// Vornamen auf „Andreea" verkürzt. `vorname2` wird nur angehängt, wenn er
  /// nicht schon im Vornamen steckt (siehe lib/utils/person_name.dart).
  Widget _namensZeile(double k) {
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
      style: TextStyle(
        fontSize: kGradName * k,
        color: kVkTextDunkel,
        height: kZeilenHoehe,
      ),
    );
  }

  /// ♿ über den Sprachen, rechts oben — wie im Druck.
  ///
  /// ⚠️ Das Symbol ist die Kurzform des Leitsatzes aus § 2 der Satzung, keine
  /// Verzierung. Deshalb trägt es eine Beschriftung für Vorleseprogramme und
  /// einen Tooltip; ein Bild, dessen Bedeutung nur Eingeweihte kennen, hätte
  /// auf einer Karte nichts verloren.
  Widget _sprachSpalte(double k) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: _t.leitsatz,
          child: Semantics(
            label: 'Selbstvertretung von Menschen mit Behinderung',
            child: Image.asset(
              'assets/ikonen/accessible.png',
              width: kGradRollstuhl * k,
              height: kGradRollstuhl * k,
              fit: BoxFit.contain,
            ),
          ),
        ),
        if (_sprachen.isNotEmpty) ...[
          SizedBox(height: kAbstandRollstuhlFahnen * k),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final s in _sprachen) _sprachChip(s, k)],
          ),
        ],
      ],
    );
  }

  /// Nur die Fahne. Die Kürzel „DE · RO · EN" standen bis zum 14.08.2026
  /// darunter und sind auf Entscheidung des Users entfallen — sie sagten
  /// dasselbe wie die Fahne darüber und kosteten Höhe im engsten Teil der
  /// Karte.
  ///
  /// ⚠️ Für Vorleseprogramme geht dabei nichts verloren: die Beschriftung
  /// nennt weiterhin die ausgeschriebene Sprache („Sprache: Rumänisch"), und
  /// die trägt mehr als ein Kürzel es je konnte. Sichtbar ist sie nicht, im
  /// Druck gibt es sie naturgemäß auch nicht.
  ///
  /// Die Fahne ist eine mitgelieferte Bilddatei — auf Windows gibt es keine
  /// Flaggen-Emoji, und im PDF ebenso wenig; die Gründe stehen in
  /// lib/utils/flaggen.dart.
  Widget _sprachChip(SprachAnzeige s, double k) {
    return Padding(
      padding: EdgeInsets.only(left: kFahneAbstand * k),
      child: Tooltip(
        message: s.bezeichnung,
        child: Semantics(
          label: 'Sprache: ${s.bezeichnung}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (flaggenPfad(s.code) != null)
                Image.asset(
                  flaggenPfad(s.code)!,
                  width: kFahneBreite * k,
                  height: kFahneHoehe * k,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kontaktBlock(double k) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_email.isNotEmpty)
          _kontaktZeile(k, Icons.email, Text(
            _email,
            style: TextStyle(
                fontSize: kGradKontakt * k,
                color: kVkTextDunkel,
                height: kZeilenHoehe),
            overflow: TextOverflow.ellipsis,
          )),
        if (_festnetz.isNotEmpty)
          _kontaktZeile(k, Icons.phone, PhoneText(
            _festnetz,
            color: kVkTextDunkel,
            style: TextStyle(
                fontSize: kGradKontakt * k,
                color: kVkTextDunkel,
                height: kZeilenHoehe),
          )),
        if (_fax.isNotEmpty)
          _kontaktZeile(k, Icons.fax, Text(
            _fax,
            style: TextStyle(
                fontSize: kGradKontakt * k,
                color: kVkTextDunkel,
                height: kZeilenHoehe),
          )),
        if (_mobil.isNotEmpty)
          _kontaktZeile(k, Icons.smartphone, PhoneText(
            _mobil,
            color: kVkTextDunkel,
            style: TextStyle(
                fontSize: kGradKontakt * k,
                color: kVkTextDunkel,
                height: kZeilenHoehe),
          )),
      ],
    );
  }

  Widget _kontaktZeile(double k, IconData icon, Widget inhalt) {
    return Padding(
      padding: EdgeInsets.only(bottom: kAbstandKontaktZeilen * k),
      child: Row(
        children: [
          SizedBox(
            width: kSpalteIkone * k,
            child: Icon(icon, size: kIkoneKontakt * k, color: kVkTonHell),
          ),
          Flexible(child: inhalt),
        ],
      ),
    );
  }

  /// Das QR-Feld: ein MECARD, den die Kamera als „Kontakt speichern" anbietet.
  ///
  /// ⚠️ Die Kantenlänge hängt an der Modulzahl, nicht am Geschmack — 49 × 49
  /// Module ergeben im Druck bei 20 mm 0,41 mm je Modul. Die Rechnung und die
  /// Schwelle stehen in visitenkarte_masse.dart; ein Test schlägt an, wenn
  /// jemand ein Feld in den MECARD aufnimmt und der Code dichter wird.
  Widget _qrFeld(double k) {
    return SizedBox(
      width: kQrKante * k,
      height: kQrKante * k,
      child: BarcodeWidget(
        // Stufe L wie im Druck — die Begründung steht dort.
        barcode: Barcode.qrCode(
          errorCorrectLevel: BarcodeQRCorrectionLevel.low,
        ),
        data: _daten.vcard,
        color: kVkTextDunkel,
        drawText: false,
      ),
    );
  }

  /// Unten links die Benutzernummer, unten rechts der Webauftritt.
  ///
  /// ⚠️ Die Benutzernummer ist zugleich der **Anmeldename**
  /// (`api/auth/login_mitglied.php`), nicht bloß eine Ordnungszahl. Sie stand
  /// am 13.08.2026 kurz nicht auf der Karte; **auf Entscheidung des Users
  /// steht sie wieder darauf**. Nicht erneut aufwerfen.
  Widget _fuss(double k) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            widget.mitgliedernummer,
            style: TextStyle(
              fontSize: kGradFussNummer * k,
              color: kVkTextLeise,
              height: kZeilenHoehe,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: 6 * k),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: kIkoneWeb * k, color: kVkTonHell),
            SizedBox(width: 3 * k),
            Text(
              _web,
              style: TextStyle(
                fontSize: kGradFussWeb * k,
                color: kVkTonHell,
                fontWeight: FontWeight.w700,
                height: kZeilenHoehe,
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
              Expanded(
                child: Text(
                  _t.ueberschrift,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: kVkTonHell,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                _vereinsname,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: kVkTextLeise,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Container(height: 2, width: 30, color: kVkTonHell),
          const SizedBox(height: 7),
          // Die Schlagwörter aus der Satzung — dieselbe Liste wie im Druck,
          // siehe kVisitenkarteSchlagworte in lib/utils/visitenkarte_pdf.dart.
          // Der Trennpunkt steht in der Vereinsfarbe: er ordnet, ohne
          // mitgelesen zu werden.
          Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < _t.schlagworte.length; i++) ...[
                  TextSpan(text: _t.schlagworte[i]),
                  if (i < _t.schlagworte.length - 1)
                    const TextSpan(
                      text: '  ·  ',
                      style: TextStyle(color: kVkTonHell),
                    ),
                ],
              ],
            ),
            style: TextStyle(
              // ⚠️ Derselbe Faktor wie im Druck: dort steht die deutsche
              // Fassung auf 7 pt, hier auf 11,5 px. Sprachen, deren Block sonst
              // die Fußzeile verdrängen würde, schrumpfen im Druck — und
              // schrumpfen damit auch hier, sonst zeigte die Vorschau eine
              // Karte, die es so nicht gibt.
              fontSize: 11.5 * _t.schlagwortGrad / 7,
              color: kVkTextDunkel,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          _leitsatzBlock(),
          const SizedBox(height: 7),
          Text(
            _t.abgrenzung,
            style: TextStyle(
              fontSize: 8.5,
              height: 1.3,
              fontStyle: FontStyle.italic,
              color: kVkTextLeise,
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: F.h(Colors.grey, 300)),
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
          Image.asset('assets/ikonen/accessible.png', width: 15, height: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _t.leitsatz,
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
            _web,
            if (register.isNotEmpty) register,
            _t.gemeinnuetzig,
          ].join(' · '),
          style: TextStyle(fontSize: 9, color: kVkTextLeise),
        ),
      ],
    );
  }
}
