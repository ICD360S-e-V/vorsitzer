import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mail_models.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/api_service.dart';
import 'vermieter_dokumente.dart';
import '../utils/app_farben.dart';

/// Widerspruch gegen die Forderung des Inkassobüros.
///
/// ⚠️ NICHT der Widerspruch gegen den Mahnbescheid. Die beiden zu
/// verwechseln kostet den Fall:
///
/// | | gegen das Inkassobüro | gegen den Mahnbescheid |
/// |---|---|---|
/// | wohin | an das Büro | an das Mahngericht |
/// | Frist | **keine** | zwei Wochen ab Zustellung |
/// | Form | formfrei | Vordruck oder Schriftform (§ 690 Abs. 3 ZPO) |
/// | steht in | diesem Reiter | Reiter „Mahnverfahren" |
///
/// Wer hier bestreitet, hat damit NICHT dem Mahnbescheid widersprochen —
/// und umgekehrt.
/// Der Betreff eines Widerspruchs.
///
/// ⚠️ Frei stehend, damit ein Test ihn festhalten kann: die Nummer trifft
/// erst nach dem Aufbau des Reiters ein, und genau dort ist sie vorher
/// verlorengegangen.
String widerspruchBetreff(String? aktenzeichen, String? bezeichnung) {
  final az = (aktenzeichen ?? '').trim();
  if (az.isNotEmpty) return 'Aktenzeichen $az - Widerspruch';
  final b = (bezeichnung ?? '').trim();
  return b.isEmpty ? 'Widerspruch gegen Ihre Forderung' : 'Widerspruch — $b';
}

class VermieterWiderspruch extends StatefulWidget {
  final ApiService apiService;
  final int vorfallId;
  final int userId;

  /// Für den Brieftext: wie das Büro heißt und unter welchem Aktenzeichen
  /// es schreibt. Ohne beides ist der Text nur eine Hülle.
  final String? inkassoName;
  final String? aktenzeichen;

  /// Fax und E-Mail des Büros aus der Inkasso-Datenbank. Hat es beides,
  /// geht der Widerspruch auf beiden Wegen raus — ein Büro, das eine
  /// Zuschrift „nicht erhalten" hat, soll es zweimal nicht erhalten haben
  /// müssen.
  final String? inkassoFax;
  final String? inkassoEmail;

  /// Straße und PLZ/Ort des Büros — für das Anschriftenfeld des Briefs.
  final String? inkassoStrasse;
  final String? inkassoPlzOrt;

  /// Fällt zurück, wenn noch kein Aktenzeichen erfasst ist — ein Betreff
  /// aus einem einzigen Wort ordnet nichts zu.
  final String? vorfallBezeichnung;

  /// Der Vorfall selbst — aus ihm kommen Forderung und Grund, damit
  /// niemand abtippt, was längst erfasst ist.
  final Map<String, dynamic>? vorfall;

  /// Der Vermieter dieses Mietvertrages — er ist der Gläubiger.
  ///
  /// ⚠️ Das war einmal bewusst LEER, mit dem Argument: „von Ihnen
  /// benannter Gläubiger" ist, wen das BÜRO als Auftraggeber nennt, und
  /// das ist oft der Vermieter, aber nicht immer — Forderungen werden
  /// verkauft. Das Argument stimmt, die Schlussfolgerung war falsch: es
  /// führte dazu, dass die Zeile im Brief entweder fehlte oder von Hand
  /// abgetippt wurde, obwohl der Vermieter im selben Vertrag steht.
  ///
  /// Aufgelöst wird der Widerspruch nicht durch Weglassen, sondern indem
  /// der Brief sagt, WOHER der Name kommt — siehe `_glaeubigerZeile()`.
  final String? glaeubigerName;

  const VermieterWiderspruch({
    super.key,
    required this.apiService,
    required this.vorfallId,
    required this.userId,
    this.inkassoName,
    this.aktenzeichen,
    this.inkassoFax,
    this.inkassoEmail,
    this.inkassoStrasse,
    this.inkassoPlzOrt,
    this.vorfallBezeichnung,
    this.vorfall,
    this.glaeubigerName,
  });

  @override
  State<VermieterWiderspruch> createState() => _VermieterWiderspruchState();
}

/// Die Gründe, aus denen eine Forderung üblicherweise bestritten wird.
///
/// ⚠️ Das ist eine Merkhilfe, kein Katalog: der freie Text darunter bleibt
/// das Entscheidende. Eine angekreuzte Zeile ohne Begründung überzeugt
/// niemanden — § 13a RDG verlangt vom Büro eine konkrete Darlegung, und
/// dasselbe Maß gilt für die Antwort darauf.
const _kGruende = <String, String>{
  'kein_vertrag': 'Ein Vertrag wurde nie geschlossen',
  'bereits_bezahlt': 'Die Forderung ist bereits bezahlt',
  'widerrufen': 'Der Vertrag wurde fristgerecht widerrufen',
  'leistung_mangelhaft': 'Die Leistung wurde nicht oder mangelhaft erbracht',
  'hoehe_falsch': 'Die Höhe der Hauptforderung stimmt nicht',
  'verjaehrt': 'Die Forderung ist verjährt (§ 195 BGB: drei Jahre)',
  'kosten_ueberhoeht': 'Die Inkassokosten sind überhöht oder nicht geschuldet',
  'kein_verzug': 'Es lag kein Verzug vor — dann sind auch keine Kosten geschuldet',
  'identitaet': 'Ich bin nicht die Person, gegen die sich die Forderung richtet',
  'unklar': 'Die Forderung ist trotz Nachfrage nicht nachvollziehbar dargelegt',
  // ⚠️ Der stärkste Einwand überhaupt — und der, auf den Inkassobüros
  // setzen, dass niemand ihn kennt.
  'restschuldbefreiung': 'Die Forderung ist von der Restschuldbefreiung erfasst (§ 301 InsO)',
  // ⚠️ Der andere Fall: das Verfahren LÄUFT noch. Dann gilt nicht § 301,
  // sondern § 87 InsO — Insolvenzgläubiger können ihre Forderungen nur
  // nach den Vorschriften des Verfahrens verfolgen — und § 89 InsO, der
  // die Einzelzwangsvollstreckung verbietet. Wer beides verwechselt,
  // beruft sich auf eine Befreiung, die es noch gar nicht gibt.
  'insolvenz_laufend': 'Über mein Vermögen läuft ein Insolvenzverfahren (§§ 87, 89 InsO)',
};

const _kVersandweg = <String, String>{
  'fax': 'Fax (für uns kostenlos)',
  'einschreiben': 'Einwurfeinschreiben',
  'brief': 'Brief',
  'email': 'E-Mail',
  'persoenlich': 'Persönlich übergeben',
  'online': 'Online-Portal',
};

/// Wie das Beleg-Feld heißt, hängt vom Weg ab — „Sendungsnummer" bei einem
/// Fax abzufragen führt nur dazu, dass es leer bleibt.
const _kBelegFeld = <String, String>{
  'fax': 'Sendebericht (Kennung / Uhrzeit)',
  'einschreiben': 'Sendungsnummer',
  'brief': 'Beleg',
  'email': 'Nachweis (z. B. Zeitstempel)',
  'persoenlich': 'Wer hat es entgegengenommen',
  'online': 'Vorgangsnummer',
};

const _kStatus = <String, String>{
  'entwurf': 'Entwurf',
  'versendet': 'Versendet',
  'reaktion_offen': 'Antwort steht aus',
  'anerkannt': 'Büro hat nachgegeben',
  'abgelehnt': 'Büro bleibt dabei',
  'erledigt': 'Erledigt',
};

/// „1240.55" → „1.240,55 €". Der Betrag steht im Schreiben deutsch, und
/// so muss er im Widerspruch zurückkommen — sonst wirkt er wie eine
/// andere Zahl.
///
/// ⚠️ Der Punkt ist zweideutig, und die erste Fassung hat genau daran
/// falsch gerechnet: sie warf jeden Punkt als Tausenderzeichen weg und
/// machte aus 1240.55 die Zahl 124.055,00 €. Ein falscher Betrag in
/// einem Widerspruch ist schlimmer als gar keiner — er gibt dem Büro
/// die Antwort „Sie bestreiten einen Betrag, den wir nie gefordert
/// haben" frei Haus.
///
/// Die Regel: kommen Punkt UND Komma vor, ist das LETZTE Zeichen das
/// Dezimaltrennzeichen. Kommt nur ein Punkt vor, entscheidet, wie viele
/// Ziffern folgen — genau drei heißt Tausender (1.240), alles andere
/// Dezimalstelle (1240.55, 268.5).
String widerspruchBetrag(String roh) {
  final t = roh.trim().replaceAll('€', '').replaceAll(' ', '');
  if (t.isEmpty) return '';

  final normal = _zahlLesen(t);
  final z = double.tryParse(normal);
  if (z == null) return '$t €';

  final ganz = z.truncate().abs().toString();
  final mitPunkt = StringBuffer();
  for (var i = 0; i < ganz.length; i++) {
    if (i > 0 && (ganz.length - i) % 3 == 0) mitPunkt.write('.');
    mitPunkt.write(ganz[i]);
  }
  final rest = ((z.abs() - z.truncate().abs()) * 100).round().toString().padLeft(2, '0');
  return '${z < 0 ? '-' : ''}$mitPunkt,$rest €';
}

/// Macht aus einer getippten Zahl eine, die `double.tryParse` versteht.
///
/// ⚠️ Hier ist schon einmal ein Betrag um den Faktor 100 verrutscht, mit
/// echtem Geld im Brief: gespeichert war `11.629.88` — zwei Punkte, weil
/// jemand die Dezimalstelle mit einem Punkt getippt hat. Die alte Regel
/// las „mehrere Punkte = alles Tausender" und machte daraus
/// 1.162.988,00 € statt 11.629,88 €.
///
/// Die Regel jetzt, in dieser Reihenfolge:
///
/// 1. Punkt UND Komma → das LETZTE der beiden trennt die Dezimalstellen,
///    das andere sind Tausender. (1.240,55 und 1,240.55)
/// 2. Nur ein Zeichen, aber mehrfach → alle bis auf das letzte sind
///    Tausender; das letzte trennt, WENN darauf nicht genau drei Ziffern
///    folgen. (11.629.88 → 11629.88; 1.162.988 → 1162988)
/// 3. Einmal vorhanden → genau drei Ziffern danach heißt Tausender,
///    alles andere Dezimalstelle. (1.240 → 1240; 1240.55 → 1240.55)
String _zahlLesen(String t) {
  final letzterPunkt = t.lastIndexOf('.');
  final letztesKomma = t.lastIndexOf(',');

  if (letzterPunkt >= 0 && letztesKomma >= 0) {
    return letztesKomma > letzterPunkt
        ? t.replaceAll('.', '').replaceAll(',', '.')
        : t.replaceAll(',', '');
  }

  final zeichen = letztesKomma >= 0 ? ',' : (letzterPunkt >= 0 ? '.' : '');
  if (zeichen.isEmpty) return t;

  final letzte = letztesKomma >= 0 ? letztesKomma : letzterPunkt;
  final nachkomma = t.length - letzte - 1;
  final mehrfach = t.indexOf(zeichen) != letzte;

  // Genau drei Ziffern nach dem letzten Zeichen: Tausender, überall.
  if (nachkomma == 3) return t.replaceAll(zeichen, '');

  // Sonst trennt das letzte Zeichen; alle davor sind Tausender.
  final vorn = t.substring(0, letzte).replaceAll(zeichen, '');
  final hinten = t.substring(letzte + 1);
  return mehrfach ? '$vorn.$hinten' : '$vorn.$hinten';
}
class _VermieterWiderspruchState extends State<VermieterWiderspruch> {
  bool _geladen = false;
  bool _speichert = false;
  String? _fehler;
  bool _vorhanden = false;

  String _umfang = 'voll';
  String _status = 'entwurf';
  /// ⚠️ MEHRERE Wege, nicht einer. In der Praxis geht der Widerspruch
  /// gleichzeitig per Fax und per E-Mail raus. Stand hier nur einer, ging
  /// der Nachweis für den zweiten verloren — und damit die Antwort auf
  /// „bei uns ist nichts angekommen".
  final Set<String> _versandwege = {'fax'};
  bool _sendet = false;
  final List<String> _sendeProtokoll = [];
  bool _kopieGlaeubiger = true;
  bool _auskunftVerlangt = true;
  final Set<String> _gruende = {};

  /// Die Insolvenzvorgänge des Mitglieds. Der Beschluss liegt dort — ihn
  /// hier ein zweites Mal zu erfassen hieße, zwei Wahrheiten zu pflegen.
  ///
  /// ⚠️ Sie kommen aus ZWEI Tabellen: ältere Verfahren stehen als
  /// Gerichtsvorfall, neuere als Insolvenzakte. Deshalb reicht eine `id`
  /// nicht — dieselbe Zahl gibt es in beiden. `_quelle` sagt, welche
  /// gemeint ist, und ohne sie lädt der Anhang das falsche Dokument.
  List<Map<String, dynamic>> _akten = [];
  int? _akteId;
  String? _quelle;

  /// Die Dokumente des gewählten Vorgangs. Der Brief kündigt den
  /// Beschluss an — dann muss er auch mitgehen.
  ///
  /// Sie kommen mit der Liste mit, nicht über einen zweiten Ruf: der
  /// Server liest ohnehin beide Tabellen, und ein Nachladen je Auswahl
  /// wäre ein Netzweg für Daten, die schon da sind.
  List<Map<String, dynamic>> _akteDocs = [];
  final Set<int> _anhaenge = {};
  String _signatur = '';

  /// Name des Mitglieds, für das wir handeln — er MUSS ins Schreiben:
  /// das Büro kennt den Verein nicht, es kennt den Schuldner.
  ///
  /// Die Mitgliedsnummer wird geladen, steht aber nur hier im Reiter.
  /// Im Brief hat sie nichts verloren: eine interne Ordnungszahl des
  /// Vereins nützt dem Empfänger nichts und wandert sonst in seine Akte.
  String _mitgliedName = '';
  String _mitgliedNummer = '';

  /// Vorbelegt AUS: die Zeile wird erst gebraucht, wenn ein Büro die
  /// Befugnis in Frage stellt. Ungefragt eine Rechtsgrundlage zu nennen
  /// wirft die Frage erst auf.
  bool _rdgNennen = false;

  /// Wie der Verein auftritt.
  ///
  /// ⚠️ Vorbelegt mit `bote`, und das ist die wichtigere der beiden
  /// Möglichkeiten:
  ///
  ///   bote        Die Erklärung ist die des MITGLIEDS. Es widerspricht,
  ///               es unterschreibt; der Verein übermittelt sie nur über
  ///               seinen Anschluss. Der Verein gibt keine eigene
  ///               Erklärung ab — § 174 BGB greift nicht, und die Frage
  ///               nach einer Vollmacht stellt sich nicht.
  ///   vertreter   Der Verein handelt in fremdem Namen (§ 164 BGB). Dann
  ///               gehört die Vollmacht beigelegt, sonst kann das
  ///               Schreiben nach § 174 BGB unverzüglich zurückgewiesen
  ///               werden.
  String _auftritt = 'bote';

  /// ⚠️ Der Ausweg aus § 174 BGB, und der wird fast immer übersehen:
  /// Satz 2 schließt die Zurückweisung aus, wenn der VOLLMACHTGEBER den
  /// anderen von der Bevollmächtigung in Kenntnis gesetzt hat. Eine
  /// kurze Zeile des Mitglieds an das Büro genügt — danach kann der
  /// Verein per Fax und E-Mail schreiben, ohne dass die Urkunde je
  /// vorgelegt werden muss.
  bool _vollmachtAngezeigt = false;

  final _begruendungC = TextEditingController();
  final _einschreibenC = TextEditingController();
  final _reaktionC = TextEditingController();
  final _notizC = TextEditingController();
  /// ⚠️ Eigenes Feld, nicht fest verdrahtet. „Widerspruch" allein landet
  /// in einem Büro mit tausend Vorgängen im Nichts — die Zuordnung
  /// geschieht über das Aktenzeichen, und das steht deshalb im Betreff.
  final _betreffC = TextEditingController();
  // Der Bezug: welches Schreiben, welche Beträge. Ohne das ist ein
  // Widerspruch abtubar — „Ihrer Forderung widerspreche ich" lässt offen,
  // welcher.
  final _schreibenVom = TextEditingController();
  final _glaeubigerC = TextEditingController();

  /// Ob der Gläubiger aus unserer Akte stammt und unverändert dasteht.
  /// Davon hängt ab, welchen Satz der Brief schreibt — nicht die Optik.
  bool _glaeubigerAusAkte = false;
  final _vertragRefC = TextEditingController();
  final _hauptC = TextEditingController();
  final _kostenC = TextEditingController();
  final _zinsenC = TextEditingController();
  final _gesamtC = TextEditingController();
  final _versendetAm = TextEditingController();
  final _reaktionAm = TextEditingController();

  @override
  void initState() {
    super.initState();
    _laden();
  }

  /// ⚠️ Das Aktenzeichen trifft SPÄTER ein als dieser Reiter.
  ///
  /// `_VorfallDetail` baut die Reiter sofort und lädt seine Aktenzeichen
  /// erst danach — beim ersten Aufbau ist `aktenzeichen` also null, und
  /// der Betreff bekam die Ersatzfassung „Widerspruch gegen Ihre
  /// Forderung". Wenn die Nummer dann ankam, stand sie nirgends, weil
  /// `_laden()` nicht noch einmal läuft. Genau das war zu sehen.
  ///
  /// Nachgezogen wird nur, solange der Betreff unberührt ist: wer selbst
  /// etwas hineingeschrieben hat, dem wird es nicht überschrieben.
  @override
  void didUpdateWidget(VermieterWiderspruch alt) {
    super.didUpdateWidget(alt);
    if (alt.aktenzeichen != widget.aktenzeichen) {
      final vorher = _betreffAus(alt.aktenzeichen, alt.vorfallBezeichnung);
      if (_betreffC.text.trim().isEmpty || _betreffC.text.trim() == vorher) {
        setState(() => _betreffC.text = _betreffVorschlag());
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _begruendungC, _einschreibenC, _reaktionC, _notizC, _versendetAm, _reaktionAm,
      _betreffC, _schreibenVom, _glaeubigerC, _vertragRefC,
      _hauptC, _kostenC, _zinsenC, _gesamtC
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _laden() async {
    try {
      final res = await widget.apiService.getVermieterWiderspruch(widget.vorfallId);
      final akten = await widget.apiService.listInsolvenzQuellen(widget.userId);
      if (!mounted) return;
      _akten = List<Map<String, dynamic>>.from(akten['quellen'] as List? ?? []);
      // ⚠️ Nicht warten, bis jemand daran denkt: ist am Mitglied eine
      // Insolvenz vermerkt, ist das der stärkste Einwand überhaupt — und
      // der, den ein Büro einkalkuliert, wenn niemand ihn kennt. Die Akte
      // wird deshalb von selbst gewählt und der passende Grund gesetzt.
      _akteAuswerten();
      // Die Signatur ist dieselbe, die unter jeder von Hand geschriebenen
      // Mail steht — sonst käme aus demselben Haus zweierlei Post.
      try {
        final sig = await widget.apiService.getMailSignature();
        if (sig['success'] == true) _signatur = '${sig['signature'] ?? ''}';
      } catch (_) {}
      try {
        final u = await widget.apiService.getUserDetails(widget.userId);
        final d = (u['user'] ?? u['data'] ?? u) as Map<String, dynamic>?;
        if (d != null) {
          _mitgliedName = [d['vorname'], d['nachname']]
              .map((x) => (x?.toString() ?? '').trim())
              .where((x) => x.isNotEmpty)
              .join(' ');
          _mitgliedNummer = (d['mitgliedernummer']?.toString() ?? '').trim();
        }
      } catch (_) {}
      final d = res['exists'] == true ? (res['data'] as Map<String, dynamic>?) : null;
      setState(() {
        _fehler = null;
        _geladen = true;
        _vorhanden = d != null;
        if (d != null) {
          _umfang = d['umfang']?.toString() ?? 'voll';
          _status = d['status']?.toString() ?? 'entwurf';
          // Genau eine der beiden Spalten ist gesetzt. Welche, sagt die
          // Herkunft — ohne sie wäre die Zahl mehrdeutig.
          final vorfall = int.tryParse(d['insolvenz_vorfall_id']?.toString() ?? '');
          final akte = int.tryParse(d['insolvenz_akte_id']?.toString() ?? '');
          if (vorfall != null && vorfall > 0) {
            _akteId = vorfall;
            _quelle = 'gericht_vorfall';
          } else if (akte != null && akte > 0) {
            _akteId = akte;
            _quelle = 'insolvenz_akte';
          }
          // Der Server liefert das SET kommagetrennt zurück.
          _versandwege
            ..clear()
            ..addAll((d['versandweg']?.toString() ?? '')
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty));
          _kopieGlaeubiger = (int.tryParse(d['kopie_an_glaeubiger']?.toString() ?? '0') ?? 0) == 1;
          _auskunftVerlangt = (int.tryParse(d['auskunft_verlangt']?.toString() ?? '0') ?? 0) == 1;
          _versendetAm.text = d['versendet_am']?.toString() ?? '';
          _reaktionAm.text = d['reaktion_am']?.toString() ?? '';
          _begruendungC.text = d['begruendung']?.toString() ?? '';
          _einschreibenC.text = d['einschreiben_nr']?.toString() ?? '';
          _reaktionC.text = d['reaktion_text']?.toString() ?? '';
          _notizC.text = d['notizen']?.toString() ?? '';
          _betreffC.text = d['betreff']?.toString() ?? '';
          _schreibenVom.text = d['schreiben_vom']?.toString() ?? '';
          _glaeubigerC.text = d['glaeubiger']?.toString() ?? '';
          // Was gespeichert ist, hat ein Mensch stehen lassen oder
          // getippt — dann ist es keine Vermutung mehr aus der Akte.
          if (_glaeubigerC.text.trim().isNotEmpty) _glaeubigerAusAkte = false;
          _vertragRefC.text = d['vertrag_ref']?.toString() ?? '';
          _hauptC.text = d['hauptforderung']?.toString() ?? '';
          _kostenC.text = d['inkassokosten']?.toString() ?? '';
          _zinsenC.text = d['zinsen']?.toString() ?? '';
          _gesamtC.text = d['gesamtbetrag']?.toString() ?? '';
          _gruende
            ..clear()
            ..addAll(((d['gruende'] as List?) ?? const []).map((e) => e.toString()));
        }
        // ⚠️ NACH dem Laden, nicht davor. Vorher stand der Vorschlag zuerst
        // da und wurde anschließend vom gespeicherten Wert überschrieben —
        // der bei jedem Widerspruch leer ist, der vor Einführung des Feldes
        // angelegt wurde. Auf dem Gerät war der Betreff deshalb schlicht
        // leer, und ein Schreiben ohne Betreff ordnet niemand zu.
        if (_betreffC.text.trim().isEmpty) _betreffC.text = _betreffVorschlag();
        _bezugVorbelegen();
      });
      // ⚠️ Ohne diese Zeile blieb die Anlagenliste beim ÖFFNEN leer: sie
      // wurde nur beim Umschalten des Dropdowns gefüllt. Wer den
      // Widerspruch später wieder aufmachte, sah keine Dokumente — und es
      // ging auch keines mit, obwohl der Vorgang gewählt war.
      if (_akteId != null && mounted) setState(_docsAusQuelle);
      await _schreibenDatumSuchen();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fehler = e.toString();
        _geladen = true;
      });
    }
  }

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    final res = await widget.apiService.saveVermieterWiderspruch(widget.vorfallId, {
      'umfang': _umfang,
      'status': _status,
      'versandweg': _versandwege.toList(),
      'versendet_am': _versendetAm.text,
      'reaktion_am': _reaktionAm.text,
      'kopie_an_glaeubiger': _kopieGlaeubiger ? 1 : 0,
      'auskunft_verlangt': _auskunftVerlangt ? 1 : 0,
      // ⚠️ Beide Spalten werden IMMER geschrieben, die nicht gemeinte auf
      // 0. Sonst bliebe beim Wechsel der Herkunft die alte Verknüpfung
      // stehen und der Vorgang hinge an zwei Akten.
      'insolvenz_akte_id': _quelle == 'insolvenz_akte' ? (_akteId ?? 0) : 0,
      'insolvenz_vorfall_id': _quelle == 'gericht_vorfall' ? (_akteId ?? 0) : 0,
      'gruende': _gruende.toList(),
      'betreff': _betreffC.text.trim(),
      'schreiben_vom': _schreibenVom.text,
      'glaeubiger': _glaeubigerC.text.trim(),
      'vertrag_ref': _vertragRefC.text.trim(),
      'hauptforderung': _hauptC.text.trim(),
      'inkassokosten': _kostenC.text.trim(),
      'zinsen': _zinsenC.text.trim(),
      'gesamtbetrag': _gesamtC.text.trim(),
      'begruendung': _begruendungC.text.trim(),
      'einschreiben_nr': _einschreibenC.text.trim(),
      'reaktion_text': _reaktionC.text.trim(),
      'notizen': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Gespeichert' : 'Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
      backgroundColor: ok ? Colors.green.shade600 : Colors.red,
    ));
    if (ok) _laden();
  }

  /// Wählt den Insolvenzvorgang und setzt den Grund, der zu seinem Stand
  /// passt. Läuft das Verfahren noch, ist es NICHT § 301.
  ///
  /// ⚠️ Drei Ausgänge, nicht zwei. Der dritte ist der wichtigste: ein
  /// Gerichtsvorfall führt kein Feld `phase` — dort steht nur ein Status
  /// wie `bewilligt`, und der sagt, dass dem ANTRAG stattgegeben wurde,
  /// nicht, dass am Ende Restschuldbefreiung erteilt ist. Die beiden
  /// Gründe schließen einander aus und tragen verschiedene Paragraphen
  /// ins Schreiben; einen davon zu raten hieße, im Brief an ein
  /// Inkassobüro etwas zu behaupten, das aus den Daten nicht folgt.
  /// Also: Vorgang wählen, Dokumente anbieten, Grund offen lassen.
  void _akteAuswerten() {
    if (_akten.isEmpty || _akteId != null) return;
    Map<String, dynamic>? befreit;
    Map<String, dynamic>? laufend;
    for (final a in _akten) {
      final phase = (a['phase']?.toString() ?? '').toLowerCase();
      final status = (a['status']?.toString() ?? '').toLowerCase();
      if (phase == 'restschuldbefreiung') {
        befreit ??= a;
      } else if (phase == 'laufend' || status == 'laufend' || status == 'eroeffnet') {
        laufend ??= a;
      }
    }
    final gewaehlt = befreit ?? laufend ?? _akten.first;
    _akteId = int.tryParse(gewaehlt['id']?.toString() ?? '');
    _quelle = gewaehlt['herkunft']?.toString();
    if (befreit != null) {
      _gruende.add('restschuldbefreiung');
    } else if (laufend != null) {
      _gruende.add('insolvenz_laufend');
    }
    _docsAusQuelle();
  }

  /// Übernimmt die Dokumente des gewählten Vorgangs und kreuzt an, was
  /// nach Beschluss aussieht — das ist das Dokument, um das es geht.
  void _docsAusQuelle() {
    final gewaehlt = _akten
        .where((a) =>
            a['id'].toString() == _akteId.toString() &&
            (a['herkunft']?.toString() ?? '') == (_quelle ?? ''))
        .firstOrNull;
    _akteDocs = List<Map<String, dynamic>>.from(
        (gewaehlt?['dokumente'] ?? const []) as List);
    _anhaenge.clear();
    for (final d in _akteDocs) {
      final txt =
          '${d['kategorie'] ?? ''} ${d['datei_name'] ?? d['dateiname'] ?? ''}'
              .toLowerCase();
      if (txt.contains('beschluss') || txt.contains('restschuld')) {
        final i = int.tryParse(d['id']?.toString() ?? '');
        if (i != null) _anhaenge.add(i);
      }
    }
  }

  /// Füllt den Bezug aus dem, was schon erfasst ist.
  ///
  /// ⚠️ Nur LEERE Felder. Was gespeichert oder getippt wurde, bleibt —
  /// eine Vorbelegung, die eine eingetragene Zahl überschreibt, ist
  /// schlimmer als gar keine: sie ändert einen Betrag im Brief, ohne dass
  /// jemand es merkt.
  void _bezugVorbelegen() {
    final v = widget.vorfall;
    if (v == null) return;
    final forderung = (v['forderung_brutto']?.toString() ?? '').trim();
    if (_hauptC.text.trim().isEmpty) _hauptC.text = forderung;
    if (_gesamtC.text.trim().isEmpty) _gesamtC.text = forderung;
    final g = (widget.glaeubigerName ?? '').trim();
    if (_glaeubigerC.text.trim().isEmpty && g.isNotEmpty) {
      _glaeubigerC.text = g;
      _glaeubigerAusAkte = true;
    }
    if (_vertragRefC.text.trim().isEmpty) {
      _vertragRefC.text = (v['bezeichnung']?.toString() ?? '').trim();
    }
  }

  /// Das Datum des Inkasso-Schreibens: das jüngste EINGEHENDE Stück
  /// Korrespondenz dieses Vorfalls. Genau das ist der Brief, dem
  /// widersprochen wird — abtippen muss es niemand.
  Future<void> _schreibenDatumSuchen() async {
    if (_schreibenVom.text.trim().isNotEmpty) return;
    try {
      final res = await widget.apiService
          .listVermieterInkassoKorrespondenz(widget.vorfallId);
      if (!mounted) return;
      final eingehend = List<Map<String, dynamic>>.from(res['items'] as List? ?? [])
          .where((k) => (k['richtung']?.toString() ?? '') == 'eingehend')
          .toList();
      if (eingehend.isEmpty) return;
      eingehend.sort((a, b) =>
          (b['datum']?.toString() ?? '').compareTo(a['datum']?.toString() ?? ''));
      final d = eingehend.first['datum']?.toString() ?? '';
      if (d.length >= 10 && _schreibenVom.text.trim().isEmpty) {
        setState(() => _schreibenVom.text = d.substring(0, 10));
      }
    } catch (_) {}
  }


  /// Nur für den Test: welche Tabelle beim Anhang gelesen wird, ist
  /// sonst nur über den vollständigen Versand erreichbar — mit Vorschau,
  /// Knopfdruck und Netz. Geprüft werden soll aber genau eine Zeile.
  @visibleForTesting
  Future<List<MailOutgoingAttachment>> anhaengeFuerTest() => _anhaengeHolen();

  /// Nur für den Test: der fertige Brieftext.
  @visibleForTesting
  String brieftextFuerTest() => _brieftext();

  /// Nur für den Test: die Ablage in der Korrespondenz. Der volle
  /// Sendeweg braucht sipgate, einen Mailserver und einen Knopfdruck in
  /// einer Vorschau — geprüft werden soll aber, WAS abgelegt wird.
  @visibleForTesting
  Future<void> versandAblegenFuerTest(
          String weg, String ziel, List<String> anlagen) =>
      _inKorrespondenzAblegen(weg, ziel, anlagen);

  /// Holt die angekreuzten Dokumente als Bytes.
  Future<List<MailOutgoingAttachment>> _anhaengeHolen() async {
    final raus = <MailOutgoingAttachment>[];
    for (final id in _anhaenge) {
      try {
        final d = _akteDocs.where((x) => x['id'].toString() == id.toString()).firstOrNull;
        // ⚠️ Die Herkunft steht am Dokument, nicht am Reiter: sie
        // entscheidet, in welcher Tabelle der Server nachsieht. Ein fest
        // verdrahteter Typ läge in der Hälfte der Fälle daneben — und
        // zwar lautlos, denn eine fremde id von 26 gibt es dort auch.
        final quelle = (d?['quelle']?.toString() ?? _quelle ?? 'insolvenz_akte');
        final r = await widget.apiService
            .downloadVermieterDoc(type: quelle, id: id);
        if (r.statusCode != 200) continue;
        final name = (d?['datei_name'] ?? d?['dateiname'] ?? 'Beschluss_$id.pdf').toString();
        raus.add(MailOutgoingAttachment(filename: name, bytes: r.bodyBytes));
      } catch (_) {}
    }
    return raus;
  }

  /// Die Gläubigerzeile — und der Grund, warum es zwei Fassungen gibt.
  ///
  /// ⚠️ „Von Ihnen benannter Gläubiger" behauptet etwas über IHREN Brief:
  /// dass sie diesen Namen genannt haben. Steht dort der Vermieter aus
  /// unserer Akte, ist das im Zweifel eine Falschzitierung — Forderungen
  /// werden verkauft, und das Büro kann einen anderen Auftraggeber nennen.
  /// Ein Widerspruch, der die Gegenseite falsch zitiert, verliert genau
  /// die Genauigkeit, aus der er seine Kraft zieht.
  ///
  /// Also zwei wahre Sätze statt eines bequemen: kommt der Name aus
  /// unserer Akte, sagt der Brief das auch — und verlangt im selben Zug
  /// Berichtigung. Das passt zur Darlegung nach § 13a RDG, die den
  /// Auftraggeber ohnehin benannt haben will.
  String _glaeubigerZeile() {
    final g = _glaeubigerC.text.trim();
    return _glaeubigerAusAkte
        ? 'Gläubiger nach unseren Unterlagen: $g '
            '(bitte berichtigen, falls Sie für einen anderen Auftraggeber tätig werden)'
        : 'Von Ihnen benannter Gläubiger: $g';
  }

  /// Betreff: die Sache zuerst, dann das Aktenzeichen.
  ///
  /// ⚠️ Beide Reihenfolgen sind üblich, und die Wahl liegt beim Verein —
  /// so ist sie getroffen (20.08.2026). Wichtig ist nur, dass BEIDES
  /// dasteht: die Bezugsnummer, weil das Büro danach ablegt, und das
  /// Anliegen, weil eine Nummer allein ein Ordnungsmerkmal ist und keine
  /// Aussage. Der Betreff bleibt ohnehin ein änderbares Feld.
  String _betreffVorschlag() =>
      widerspruchBetreff(widget.aktenzeichen, widget.vorfallBezeichnung);

  static String _betreffAus(String? a, String? b) => widerspruchBetreff(a, b);

  String get _betreff =>
      _betreffC.text.trim().isEmpty ? _betreffVorschlag() : _betreffC.text.trim();

  /// Der KÖRPER des Schreibens: Anrede, Text, Grußformel, Signatur.
  ///
  /// ⚠️ OHNE Betreffzeile. In der E-Mail steht der Betreff im Kopf — ihn
  /// im Text zu wiederholen sieht nach Serienbrief aus. Im Brief steht er
  /// an seinem eigenen Platz, und dort ohne das Wort „Betreff": das ist
  /// seit der DIN 5008 von 2011 veraltet, die Zeile steht allein und fett.
  ///
  /// ⚠️ Eigene Formulierung, absichtlich keine Abschrift eines fremden
  /// Musterbriefs. Sie sagt dasselbe: bestreiten, Nachweis verlangen,
  /// nichts anerkennen.
  String _brieftext({bool alsBrief = true}) {
    final buero = (widget.inkassoName ?? '').trim();
    final p = StringBuffer();
    // ⚠️ Der Bezug steht VOR der Anrede, wie im Geschäftsbrief üblich —
    // wer das Schreiben öffnet, sieht in der ersten Zeile, worum es geht,
    // und muss nicht bis zum Betrag lesen.
    final bezug = <String>[
      if (_schreibenVom.text.length >= 10)
        'Ihr Schreiben vom ${_deutschDatum(_schreibenVom.text)}',
      if ((widget.aktenzeichen ?? '').trim().isNotEmpty)
        'Ihr Aktenzeichen: ${widget.aktenzeichen!.trim()}',
      if (_glaeubigerC.text.trim().isNotEmpty) _glaeubigerZeile(),
      if (_vertragRefC.text.trim().isNotEmpty)
        'Von Ihnen benannter Vorgang: ${_vertragRefC.text.trim()}',
      if (_hauptC.text.trim().isNotEmpty) 'Hauptforderung: ${_betrag(_hauptC.text)}',
      if (_zinsenC.text.trim().isNotEmpty) 'Zinsen: ${_betrag(_zinsenC.text)}',
      if (_kostenC.text.trim().isNotEmpty) 'Inkassokosten: ${_betrag(_kostenC.text)}',
      if (_gesamtC.text.trim().isNotEmpty) 'Gesamtbetrag: ${_betrag(_gesamtC.text)}',
    ];
    // ⚠️ Der Bezugsblock steht NUR im gedruckten Brief über der Anrede —
    // dort gehört er hin (DIN 5008). In einer E-Mail liest sich ein
    // Datenblock vor der Anrede wie ein versehentlich mitgeschicktes
    // Formular. Dort werden Datum und Betrag stattdessen in den ersten
    // Satz gezogen, wo sie hingehören.
    if (alsBrief && bezug.isNotEmpty) {
      for (final z in bezug) {
        p.writeln(z);
      }
      p.writeln();
    }
    p.writeln('Sehr geehrte Damen und Herren,');
    p.writeln();
    // ⚠️ Direkt nach der Anrede und vor der Sache: das Büro muss wissen,
    // WER schreibt und für WEN, bevor es den ersten Einwand liest.
    // Sonst landet der Brief als „unbekannter Absender" im Stapel.
    if (_mitgliedName.isNotEmpty && _auftritt == 'vertreter') {
      p.write('wir zeigen an, dass wir ');
      p.write(_mitgliedName);
      p.writeln(' in dieser Angelegenheit vertreten.');
      p.writeln('$_mitgliedName ist Mitglied unseres Vereins; die Bearbeitung dieses '
          'Vorgangs erfolgt durch uns.');
      if (_rdgNennen) {
        p.writeln('Unsere Befugnis folgt aus § 7 Absatz 1 Nummer 1 des '
            'Rechtsdienstleistungsgesetzes: Rechtsdienstleistungen gegenüber Mitgliedern '
            'im Rahmen des satzungsmäßigen Aufgabenbereichs.');
      }
      if (_vollmachtAngezeigt) {
        p.writeln('$_mitgliedName hat Sie über die Bevollmächtigung bereits in Kenntnis '
            'gesetzt; eine Zurückweisung nach § 174 Satz 1 BGB ist damit nach Satz 2 '
            'ausgeschlossen.');
      } else {
        p.writeln('Eine Vollmacht liegt bei.');
      }
      p.writeln('Wir bitten Sie, sich in dieser Sache ausschließlich an uns zu wenden.');
      p.writeln();
    }
    // In der Mail trägt der erste Satz, was im Brief oben steht.
    final datum = (!alsBrief && _schreibenVom.text.length >= 10)
        ? ' mit Schreiben vom ${_deutschDatum(_schreibenVom.text)}'
        : '';
    final summe = (!alsBrief && _gesamtC.text.trim().isNotEmpty)
        ? ' über ${_betrag(_gesamtC.text)}'
        : '';
    p.write('der von Ihnen${buero.isEmpty ? '' : ' ($buero)'}$datum geltend gemachten '
        'Forderung$summe ');
    switch (_umfang) {
      case 'teilweise':
        p.writeln('widerspreche ich teilweise.');
      case 'nur_kosten':
        p.writeln('widerspreche ich hinsichtlich der Inkassokosten.');
      default:
        p.writeln('widerspreche ich in vollem Umfang.');
    }
    p.writeln('Eine Zahlung leiste ich nicht.');
    if (_gruende.isNotEmpty) {
      p.writeln();
      p.writeln('Begründung:');
      for (final g in _gruende) {
        p.writeln('- ${_kGruende[g] ?? g}');
      }
    }
    final frei = _begruendungC.text.trim();
    if (frei.isNotEmpty) {
      p.writeln();
      p.writeln(frei);
    }
    if (_gruende.contains('restschuldbefreiung')) {
      final akte = _akten.where((a) => a['id'] == _akteId).firstOrNull;
      final az = (akte?['az_gericht']?.toString() ?? '').trim();
      final ende = (akte?['ende_am']?.toString() ?? '').trim();
      p.writeln();
      p.write('Über mein Vermögen wurde das Insolvenzverfahren durchgeführt');
      if (az.isNotEmpty) p.write(' (Aktenzeichen $az)');
      p.write('; die Restschuldbefreiung wurde erteilt');
      if (ende.length >= 10) {
        p.write(' (Beschluss vom '
            '${ende.substring(8, 10)}.${ende.substring(5, 7)}.${ende.substring(0, 4)})');
      }
      p.writeln('.');
      p.writeln('Nach § 301 Absatz 1 der Insolvenzordnung wirkt sie gegen ALLE '
          'Insolvenzgläubiger — auch gegen diejenigen, die ihre Forderung nicht '
          'angemeldet haben. Die Forderung ist damit nicht mehr durchsetzbar. '
          'Sollten Sie sich auf eine Ausnahme nach § 302 InsO berufen, weisen Sie '
          'bitte nach, dass die Forderung unter Angabe dieses Rechtsgrundes zur '
          'Insolvenztabelle angemeldet wurde.');
      // ⚠️ Nur ankündigen, was tatsächlich mitgeht. Ein Brief, der eine
      // Anlage nennt, die fehlt, lädt zur Rückfrage ein — und die kostet
      // die Wochen, die man gerade sparen wollte.
      if (_anhaenge.isNotEmpty) {
        p.writeln(_anhaenge.length == 1
            ? 'Eine Abschrift des Beschlusses liegt bei.'
            : 'Abschriften der Beschlüsse liegen bei.');
      }
    }
    if (_gruende.contains('insolvenz_laufend')) {
      final akte = _akten.where((a) => a['id'] == _akteId).firstOrNull;
      final az = (akte?['az_gericht']?.toString() ?? '').trim();
      p.writeln();
      p.write('Über mein Vermögen ist ein Insolvenzverfahren eröffnet');
      if (az.isNotEmpty) p.write(' (Aktenzeichen $az)');
      p.writeln('.');
      p.writeln('Nach § 87 der Insolvenzordnung können Insolvenzgläubiger ihre Forderungen '
          'nur nach den Vorschriften über das Insolvenzverfahren verfolgen; nach § 89 InsO '
          'ist die Zwangsvollstreckung für einzelne Insolvenzgläubiger während des '
          'Verfahrens unzulässig. Ihre Forderung ist, soweit sie vor Eröffnung entstanden '
          'ist, zur Tabelle anzumelden — nicht bei mir einzuziehen.');
      p.writeln('Ich bitte Sie, sich an den Insolvenzverwalter zu wenden.');
    }
    if (_auskunftVerlangt) {
      p.writeln();
      p.writeln('Zugleich fordere ich Sie auf, die Forderung nach § 13a des '
          'Rechtsdienstleistungsgesetzes darzulegen: Name und Anschrift Ihres '
          'Auftraggebers, der Grund der Forderung mit Gegenstand und Datum des '
          'Vertragsschlusses, die Berechnung etwaiger Zinsen sowie Art, Höhe und '
          'Entstehungsgrund der geltend gemachten Inkassokosten. Bis dahin ist '
          'die Forderung für mich nicht überprüfbar.');
    }
    p.writeln();
    p.writeln('Ich weise darauf hin, dass eine bestrittene Forderung nicht die '
        'Voraussetzungen des § 31 Absatz 2 Nummer 4 und 5 des '
        'Bundesdatenschutzgesetzes erfüllt. Eine Übermittlung an eine '
        'Auskunftei wäre danach unzulässig.');
    p.writeln();
    p.writeln('Dieses Schreiben ist kein Anerkenntnis der Forderung, auch nicht '
        'dem Grunde nach.');
    p.writeln();
    if (!alsBrief) {
      final rest = <String>[
        if ((widget.aktenzeichen ?? '').trim().isNotEmpty)
          'Ihr Aktenzeichen: ${widget.aktenzeichen!.trim()}',
        if (_glaeubigerC.text.trim().isNotEmpty) _glaeubigerZeile(),
        if (_vertragRefC.text.trim().isNotEmpty)
          'Von Ihnen benannter Vorgang: ${_vertragRefC.text.trim()}',
        if (_hauptC.text.trim().isNotEmpty) 'Hauptforderung: ${_betrag(_hauptC.text)}',
        if (_zinsenC.text.trim().isNotEmpty) 'Zinsen: ${_betrag(_zinsenC.text)}',
        if (_kostenC.text.trim().isNotEmpty) 'Inkassokosten: ${_betrag(_kostenC.text)}',
      ];
      if (rest.isNotEmpty) {
        p.writeln();
        // Am Ende, unter der Sache — nicht vor der Anrede.
        p.writeln('Zur Zuordnung:');
        for (final z in rest) {
          p.writeln('  $z');
        }
      }
      p.writeln();
    }
    p.writeln('Mit freundlichen Grüßen');
    p.writeln();
    if (_auftritt == 'bote' && _mitgliedName.isNotEmpty) {
      p.writeln(_mitgliedName);
      // ⚠️ OHNE Mitgliedsnummer. Sie ist eine interne Ordnungszahl des
      // Vereins — das Büro kann damit nichts anfangen, und was der
      // Empfänger nicht braucht, gehört nicht in ein Schreiben, das in
      // seine Akte wandert. Dass jemand Mitglied ist, erklärt dagegen,
      // warum das Fax vom Vereinsanschluss kommt, und bleibt deshalb.
      p.writeln('Mitglied des ICD360S e.V.');
      p.writeln();
      // ⚠️ Der Übermittlungsvermerk ist keine Höflichkeit, sondern die
      // ehrliche Angabe, warum Absender und Anschluss auseinanderfallen.
      // Ohne ihn sieht ein Fax vom Vereinsanschluss mit fremdem Absender
      // nach Unstimmigkeit aus — und genau daran hängen sich Büros auf.
      p.writeln('— Übermittelt im Auftrag und im Namen des Absenders über den '
          'Anschluss des ICD360S e.V. Antworten bitte an die oben genannte Person; '
          'eine Antwort über den Verein erreicht sie ebenfalls.');
    }
    if (_signatur.trim().isNotEmpty && _auftritt == 'vertreter') {
      p.writeln();
      p.writeln(_signatur.trimRight());
    }
    return p.toString();
  }

  /// Der Brief als PDF — das Fax nimmt nichts anderes an.
  ///
  /// ⚠️ Nach DIN 5008 gesetzt, nicht als Textblock aufs Blatt geworfen:
  /// Ränder 25/20/45/25 mm, Anschriftenfeld oben links, Datum rechts,
  /// Betreffzeile fett und OHNE das Wort „Betreff" (seit 2011 veraltet),
  /// dann der Text. Die Norm ist keine Pflicht — aber ein deutscher
  /// Empfänger erwartet sie, und ein Schreiben, das sie einhält, wird
  /// anders gelesen als eines, das es nicht tut. Bei einem Widerspruch
  /// gegen ein Inkassobüro ist genau das der Punkt.
  Future<Uint8List> _alsPdf() async {
    final doc = pw.Document();
    final empfaenger = <String>[
      (widget.inkassoName ?? '').trim(),
      (widget.inkassoStrasse ?? '').trim(),
      (widget.inkassoPlzOrt ?? '').trim(),
    ].where((z) => z.isNotEmpty).toList();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      // 25 mm links, 20 mm rechts, 45 mm oben (Sichtfenster), 25 mm unten.
      margin: const pw.EdgeInsets.fromLTRB(
          25 * PdfPageFormat.mm, 45 * PdfPageFormat.mm,
          20 * PdfPageFormat.mm, 25 * PdfPageFormat.mm),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Anschriftenfeld
          for (final z in empfaenger)
            pw.Text(z, style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
          pw.SizedBox(height: 24),
          // Datum rechtsbündig
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(_heuteDeutsch(), style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.SizedBox(height: 24),
          // Betreffzeile: fett, allein, ohne das Wort „Betreff"
          pw.Text(_betreff,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 18),
          pw.Text(_brieftext(),
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
        ],
      ),
    ));
    return doc.save();
  }

  String _betrag(String roh) => widerspruchBetrag(roh);



  String _deutschDatum(String iso) {
    if (iso.length < 10) return iso;
    return '${iso.substring(8, 10)}.${iso.substring(5, 7)}.${iso.substring(0, 4)}';
  }

  String _heuteDeutsch() {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2, '0')}.${n.month.toString().padLeft(2, '0')}.${n.year}';
  }

  /// Schickt den Widerspruch auf EINEM Weg — dem, dessen Knopf gedrückt
  /// wurde.
  ///
  /// ⚠️ Ausdrücklich nicht beides auf einmal. Ob ein Widerspruch per Fax
  /// oder per E-Mail rausgeht, ist eine Entscheidung im Einzelfall und
  /// gehört dem, der sie trifft — nicht einem Knopf, der es gut meint.
  /// Wer beides will, drückt beides; dann stehen auch beide Wege einzeln
  /// im Protokoll.
  Future<void> _sendenPer(String weg) async {
    final ziel = weg == 'fax'
        ? (widget.inkassoFax ?? '').trim()
        : (widget.inkassoEmail ?? '').trim();
    if (ziel.isEmpty) return;

    // ⚠️ Erst zeigen, dann senden. Ein Widerspruch geht an ein
    // Inkassobüro und lässt sich nicht zurückholen; ein Knopf, der beim
    // ersten Druck sofort raus ist, ist an dieser Stelle falsch. Die
    // Vorschau zeigt genau das, was gleich rausgeht — Empfänger, Betreff,
    // Text —, nicht eine Zusammenfassung davon.
    final los = await _vorschauZeigen(weg, ziel);
    if (los != true || !mounted) return;

    setState(() => _sendet = true);
    var ok = false;
    String zeile;
    // Was mitging und wie es quittiert wurde — kommt gleich in die
    // Korrespondenz. `_sendeProtokoll` lebt nur in dieser Sitzung.
    final anlagenVermerk = <String>[];

    if (weg == 'fax') {
      try {
        final pdf = await _alsPdf();
        final res = await widget.apiService.sipgateFaxAction({
          'action': 'senden',
          'empfaenger': ziel,
          'empfaenger_name': widget.inkassoName ?? '',
          'dateiname': 'Widerspruch.pdf',
          'inhalt_b64': base64Encode(pdf),
        });
        ok = res['success'] == true;
        zeile = 'Fax an $ziel: ${ok ? 'abgeschickt' : (res['message'] ?? 'fehlgeschlagen')}';

        // ⚠️ sipgate nimmt EIN PDF je Sendung. Die Anlagen gehen deshalb
        // als eigene Faxe hinterher, jede einzeln quittiert. Sie in ein
        // Dokument zu falten wäre schöner, hiesse aber, fremde PDFs zu
        // verschmelzen — und ein stillschweigend halb übernommener
        // Beschluss ist schlimmer als zwei Sendungen.
        if (ok) {
          for (final a in await _anhaengeHolen()) {
            try {
              final r2 = await widget.apiService.sipgateFaxAction({
                'action': 'senden',
                'empfaenger': ziel,
                'empfaenger_name': widget.inkassoName ?? '',
                'dateiname': a.filename,
                'inhalt_b64': base64Encode(a.bytes),
              });
              final q = r2['success'] == true
                  ? 'abgeschickt'
                  : '${r2['message'] ?? 'fehlgeschlagen'}';
              _sendeProtokoll.add('${_heuteDeutsch()} — Anlage „${a.filename}" per Fax: $q');
              anlagenVermerk.add('Anlage „${a.filename}" als eigenes Fax: $q');
            } catch (e) {
              _sendeProtokoll.add('${_heuteDeutsch()} — Anlage „${a.filename}" per Fax: $e');
              anlagenVermerk.add('Anlage „${a.filename}" als eigenes Fax: $e');
            }
          }
        }
      } catch (e) {
        zeile = 'Fax an $ziel: $e';
      }
    } else {
      try {
        final anhaenge = await _anhaengeHolen();
        final res = await widget.apiService.sendMail(
          to: ziel,
          subject: _betreff,
          body: _brieftext(alsBrief: false),
          attachments: anhaenge,
        );
        ok = res['success'] == true;
        zeile = 'E-Mail an $ziel: ${ok ? 'abgeschickt' : (res['message'] ?? 'fehlgeschlagen')}'
            '${ok && anhaenge.isNotEmpty ? ' (mit ${anhaenge.length} Anlage(n))' : ''}';
        for (final a in anhaenge) {
          anlagenVermerk.add('Anlage „${a.filename}" im selben Mail');
        }
      } catch (e) {
        zeile = 'E-Mail an $ziel: $e';
      }
    }

    if (!mounted) return;
    setState(() {
      _sendet = false;
      _sendeProtokoll.add('${_heuteDeutsch()} — $zeile');
      if (ok) {
        _versandwege.add(weg);
        _versendetAm.text = DateTime.now().toIso8601String().substring(0, 10);
        if (_status == 'entwurf') _status = 'reaktion_offen';
      }
    });
    if (ok) {
      // ⚠️ Sofort ablegen. Ein Widerspruch, der raus ist, aber bei uns als
      // Entwurf steht, ist beim nächsten Öffnen ein Rätsel.
      await _speichern();
      await _inKorrespondenzAblegen(weg, ziel, anlagenVermerk);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(zeile),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  /// Legt das abgeschickte Schreiben als AUSGANG in der Korrespondenz des
  /// Vorfalls ab.
  ///
  /// ⚠️ Vorher stand davon nichts in der Akte. Es gab nur `_sendeProtokoll`
  /// — eine Liste, die mit dem Schliessen des Reiters verschwindet — und
  /// einen Hinweis, der den Menschen bat, es von Hand abzuheften. Damit
  /// war der Widerspruch zwar raus, aber der Verlauf des Vorfalls zeigte
  /// ihn nicht: unter Ausgang stand nichts, und wer zwei Jahre später
  /// nachsah, fand einen Eingang ohne Antwort. Genau der Eindruck, den
  /// eine Gegenseite gern hätte.
  ///
  /// Was abgelegt wird, ist der WORTLAUT, der rausging — nicht ein
  /// Vermerk „wurde gefaxt". Beim Anbieter ist der Verlauf nach ein paar
  /// Monaten gelöscht; unsere Akte muss den Text selbst tragen.
  Future<void> _inKorrespondenzAblegen(
      String weg, String ziel, List<String> anlagen) async {
    final notiz = StringBuffer()
      ..writeln(weg == 'fax' ? 'Per Fax an $ziel' : 'Per E-Mail an $ziel')
      ..writeln('Automatisch abgelegt beim Versand aus dem Widerspruch.');
    if (anlagen.isNotEmpty) {
      notiz.writeln('');
      for (final a in anlagen) {
        notiz.writeln('• $a');
      }
    }
    if (weg == 'fax') {
      // Der Satz gehoert an den Vorgang, nicht nur auf den Bildschirm:
      // wer den Eintrag spaeter liest, soll nicht glauben, der Zugang sei
      // damit belegt.
      notiz.writeln('');
      notiz.writeln('⚠️ Der „OK"-Vermerk des Sendeberichts ist nach der '
          'Rechtsprechung des BGH kein Anscheinsbeweis für den Zugang.');
    }
    try {
      final res = await widget.apiService.saveVermieterInkassoKorrespondenz(
        widget.vorfallId,
        {
          'datum': DateTime.now().toIso8601String().substring(0, 10),
          'richtung': 'ausgehend',
          // Genau die Schlüssel, die die Korrespondenz kennt — `fax` und
          // `email` heissen dort ebenso.
          'medium': weg,
          'erledigt': 1,
          'betreff': _betreff,
          'text': _brieftext(alsBrief: false),
          'notizen': notiz.toString().trimRight(),
        },
      );
      if (!mounted) return;
      // ⚠️ Ein fehlgeschlagenes Ablegen wird GEMELDET, nicht verschluckt.
      // Der Brief ist raus; wenn die Akte ihn nicht hat, muss das jemand
      // erfahren, solange der Text noch auf dem Schirm steht.
      setState(() => _sendeProtokoll.add(res['success'] == true
          ? '${_heuteDeutsch()} — unter Korrespondenz ▸ Ausgang abgelegt'
          : '${_heuteDeutsch()} — ⚠️ NICHT in der Korrespondenz abgelegt: '
              '${res['message'] ?? 'unbekannter Fehler'}'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendeProtokoll
          .add('${_heuteDeutsch()} — ⚠️ NICHT in der Korrespondenz abgelegt: $e'));
    }
  }

  /// Zeigt, was gleich rausgeht, und fragt. Gibt true zurück, wenn
  /// gesendet werden soll.
  Future<bool?> _vorschauZeigen(String weg, String ziel) {
    final istFax = weg == 'fax';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(istFax ? Icons.fax : Icons.email_outlined, color: F.h(Colors.purple, 700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(istFax ? 'Vorschau — Fax' : 'Vorschau — E-Mail',
                style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis),
          ),
        ]),
        content: SizedBox(
          width: dialogBreite(ctx, 560),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _vorschauZeile('An', ziel),
              _vorschauZeile('Betreff', _betreff),
              if (istFax)
                _vorschauZeile('Sendung 1', 'Widerspruch.pdf — der Text unten, als PDF gesetzt'),
              // ⚠️ Auch wenn NICHTS mitgeht, steht das da. „Keine Zeile"
              // heißt für den Leser „wird schon passen" — und dann geht
              // der Beschluss nicht mit, obwohl der Brief ihn ankündigt.
              if (_anhaenge.isEmpty)
                _vorschauZeile('Anlagen', 'keine — es geht nur das Schreiben raus'),
              if (_anhaenge.isNotEmpty)
                for (var i = 0; i < _anhaenge.length; i++)
                  _vorschauZeile(
                      istFax ? 'Sendung ${i + 2}' : (i == 0 ? 'Anlagen' : ''),
                      (_akteDocs
                                  .where((d) =>
                                      d['id'].toString() == _anhaenge.elementAt(i).toString())
                                  .firstOrNull?['dateiname'] ??
                              'Anlage ${i + 1}')
                          .toString()),
              if (istFax && _anhaenge.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                      'Die Anlagen gehen als eigene Faxe hinterher — sipgate nimmt ein PDF '
                      'je Sendung. Jede wird einzeln quittiert.',
                      style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
                ),
              if (!istFax && _signatur.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                      '⚠️ Keine Signatur geladen — die Mail geht ohne Absenderblock raus.',
                      style: TextStyle(fontSize: 11.5, color: F.h(Colors.orange, 900))),
                ),
              const Divider(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: F.h(Colors.grey, 50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: F.h(Colors.grey, 300)),
                ),
                child: SelectableText(
                    istFax
                        // Beim Fax steht der Betreff auf dem Blatt, in der
                        // Mail im Kopf — die Vorschau zeigt jeweils das,
                        // was der Empfänger wirklich sieht.
                        ? '$_betreff\n\n${_brieftext()}'
                        : _brieftext(alsBrief: false),
                    style: const TextStyle(fontSize: 11.5, height: 1.5, fontFamily: 'monospace')),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send, size: 16),
            label: Text(istFax ? 'Fax jetzt senden' : 'E-Mail jetzt senden'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _vorschauZeile(String label, String wert) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 70,
            child: Text(label, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ),
          Expanded(
            child: Text(wert,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
          ),
        ]),
      );

  /// Die paar Zeilen, die das Mitglied selbst schickt. Danach greift
  /// § 174 Satz 2 BGB und die Frage nach der Urkunde ist erledigt.
  void _anzeigetextZeigen() {
    final az = (widget.aktenzeichen ?? '').trim();
    final text = StringBuffer()
      ..writeln(az.isEmpty ? 'Bevollmächtigung' : 'Aktenzeichen $az - Bevollmächtigung')
      ..writeln()
      ..writeln('Sehr geehrte Damen und Herren,')
      ..writeln()
      ..writeln('hiermit teile ich Ihnen mit, dass ich den ICD360S e.V. in dieser '
          'Angelegenheit bevollmächtigt habe. Bitte richten Sie Ihre Korrespondenz '
          'ab sofort dorthin.')
      ..writeln()
      ..writeln('Mit freundlichen Grüßen')
      ..writeln()
      ..writeln(_mitgliedName.isEmpty ? '[Name des Mitglieds]' : _mitgliedName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zeilen für das Mitglied', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: dialogBreite(ctx, 520),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Das Mitglied schickt diese Zeilen selbst an das Büro — per E-Mail, Fax '
                  'oder Brief. Danach ist die Zurückweisung nach § 174 BGB ausgeschlossen, '
                  'und wir können ohne Urkunde weiterschreiben.',
                  style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700), height: 1.4)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: F.h(Colors.grey, 50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: F.h(Colors.grey, 300)),
                ),
                child: SelectableText(text.toString(),
                    style: const TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace')),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text.toString()));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Kopieren'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  /// Das Band ganz oben: dieses Mitglied hatte oder hat ein
  /// Insolvenzverfahren.
  ///
  /// ⚠️ Es hängt NICHT am angekreuzten Grund, sondern an der Akte. Wer
  /// den Reiter öffnet, soll es sehen, bevor er irgendetwas tippt — bei
  /// einer erteilten Restschuldbefreiung ist jede andere Begründung
  /// zweitrangig.
  Widget _insolvenzBand() {
    final befreit = _akten.any((a) =>
        (a['phase']?.toString() ?? '').toLowerCase() == 'restschuldbefreiung');
    final akte = _akten
            .where((a) =>
                a['id'].toString() == _akteId.toString() &&
                (a['herkunft']?.toString() ?? '') == (_quelle ?? ''))
            .firstOrNull ??
        _akten.first;
    final az = (akte['aktenzeichen'] ?? akte['az_gericht'] ?? '').toString().trim();
    final ende = (akte['ende_am']?.toString() ?? '').trim();
    final laufend = _akten.any((a) {
      final ph = (a['phase']?.toString() ?? '').toLowerCase();
      final st = (a['status']?.toString() ?? '').toLowerCase();
      return ph == 'laufend' || st == 'laufend' || st == 'eroeffnet';
    });

    if (befreit) {
      return _hinweis(
          Colors.green,
          Icons.verified,
          'Für dieses Mitglied ist eine Restschuldbefreiung vermerkt',
          '${az.isEmpty ? '' : 'Aktenzeichen $az. '}'
          '${ende.length >= 10 ? 'Beschluss vom ${_deutschDatum(ende)}. ' : ''}'
          '§ 301 Abs. 1 InsO wirkt gegen ALLE Insolvenzgläubiger, auch gegen die, die '
          'nie angemeldet haben. Der Grund ist unten bereits angekreuzt und die Akte '
          'gewählt — prüfen Sie nur noch, ob die Forderung aus der Zeit VOR '
          'Verfahrenseröffnung stammt.');
    }
    if (laufend) {
      return _hinweis(
          Colors.orange,
          Icons.hourglass_top,
          'Für dieses Mitglied läuft ein Insolvenzverfahren',
          '${az.isEmpty ? '' : 'Aktenzeichen $az. '}'
          'Eine Restschuldbefreiung ist noch nicht vermerkt — § 301 InsO greift also '
          'noch nicht. Es gelten §§ 87, 89 InsO: die Forderung gehört zur Tabelle und an '
          'den Verwalter, nicht an das Mitglied. Der passende Grund ist unten angekreuzt.');
    }
    // ⚠️ Der dritte Fall, und der häufigste bei älteren Verfahren: es ist
    // eine Insolvenz vermerkt, aber der Datensatz sagt nicht, wie sie
    // ausging. Der Vorgang wird gewählt und die Beschlüsse werden zum
    // Anhängen angeboten — welcher der beiden Gründe zutrifft, entscheidet
    // ein Mensch mit dem Beschluss in der Hand. § 301 und §§ 87/89 sind
    // verschiedene Aussagen; die falsche im Brief nimmt dem Widerspruch
    // seine Kraft, und geraten wäre sie hier.
    final stand = (akte['status']?.toString() ?? '').trim();
    return _hinweis(
        Colors.blue,
        Icons.gavel_outlined,
        'Für dieses Mitglied ist eine Insolvenz vermerkt',
        '${az.isEmpty ? '' : 'Aktenzeichen $az. '}'
        '${stand.isEmpty ? '' : 'Vermerkter Stand: $stand. '}'
        'Der Vorgang ist unten gewählt und die Beschlüsse stehen zum Anhängen bereit. '
        'Welcher Grund gilt, sagt der Datensatz nicht: bei ERTEILTER '
        'Restschuldbefreiung § 301 InsO, bei noch laufendem Verfahren §§ 87, 89 InsO. '
        'Bitte am Beschluss ablesen und unten ankreuzen — der Reiter rät das nicht.');
  }

  Widget _hinweis(MaterialColor farbe, IconData symbol, String titel, String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: farbe.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: farbe.shade200),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(symbol, size: 18, color: farbe.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titel,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold, color: farbe.shade900)),
              const SizedBox(height: 3),
              Text(text,
                  style: TextStyle(fontSize: 11.5, color: farbe.shade900, height: 1.45)),
            ]),
          ),
        ]),
      );

  Widget _abschnitt(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 800))),
      );

  /// Ein Geldfeld, das zeigt, wie es gelesen wird.
  ///
  /// ⚠️ Das ist die eigentliche Reparatur. Ein Betrag ist hier schon
  /// einmal um den Faktor 100 verrutscht — `11.629.88` wurde als
  /// 1.162.988,00 € in den Brief gesetzt — und aufgefallen ist es erst
  /// am fertigen Schreiben. Wer beim Tippen sieht, was daraus wird,
  /// merkt es in derselben Sekunde.
  Widget _geld(String label, TextEditingController c) {
    final roh = c.text.trim();
    final gelesen = widerspruchBetrag(roh);
    // Unlesbar heißt: es steht so im Brief, wie es dasteht. Das ist eine
    // Warnung, kein Fehler — aber eine sichtbare.
    final unlesbar = roh.isNotEmpty && gelesen.endsWith('$roh €');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      if (roh.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3, left: 4),
          child: Row(children: [
            Icon(unlesbar ? Icons.warning_amber : Icons.arrow_right_alt,
                size: 14,
                color: unlesbar ? F.h(Colors.orange, 800) : F.h(Colors.grey, 600)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                unlesbar ? 'keine Zahl — steht so im Brief' : 'im Brief: $gelesen',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: unlesbar ? FontWeight.bold : FontWeight.w500,
                    color: unlesbar ? F.h(Colors.orange, 900) : F.h(Colors.grey, 700)),
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget _datum(String label, TextEditingController c, {String? hinweis}) => TextField(
        controller: c,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: hinweis,
          helperMaxLines: 3,
          isDense: true,
          prefixIcon: const Icon(Icons.calendar_today, size: 16),
          suffixIcon: c.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () => setState(c.clear),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: DateTime.tryParse(c.text) ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2040),
            locale: const Locale('de'),
          );
          if (d != null) setState(() => c.text = d.toIso8601String().substring(0, 10));
        },
      );

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    if (_fehler != null) return LadeFehler(meldung: _fehler!, onErneut: _laden);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ⚠️ Noch vor allem anderen: ist am Mitglied eine Insolvenz
        // vermerkt, entscheidet das den Fall — und zwar unabhängig davon,
        // ob jemand daran gedacht hat, den Grund anzukreuzen. Deshalb
        // steht das Band immer da, sobald eine Akte existiert.
        if (_akten.isNotEmpty) _insolvenzBand(),
        // ⚠️ Ganz oben, weil die Verwechslung den Fall kostet.
        _hinweis(Colors.blue, Icons.compare_arrows, 'Nicht der Widerspruch gegen den Mahnbescheid',
            'Dieser Widerspruch geht an das Inkassobüro: formfrei, ohne gesetzliche Frist. '
            'Der Widerspruch gegen einen Mahnbescheid geht an das GERICHT, hat zwei Wochen '
            'Frist und braucht Vordruck oder Schriftform — er steht im Reiter „Mahnverfahren". '
            'Das eine ersetzt das andere nicht.'),
        _hinweis(Colors.green, Icons.shield_outlined, 'Bestreiten schützt vor dem SCHUFA-Eintrag',
            'Solange die Forderung bestritten ist, fehlt die Voraussetzung des § 31 Abs. 2 '
            'Nr. 4 und 5 BDSG — eine Meldung an eine Auskunftei ist dann unzulässig. '
            '⚠️ Das gilt NICHT mehr, sobald ein Titel vorliegt (etwa ein '
            'Vollstreckungsbescheid) oder die Forderung anerkannt wurde.'),
        _hinweis(Colors.red, Icons.dangerous_outlined, 'Nichts unterschreiben, nichts anzahlen',
            'Eine Ratenzahlungsvereinbarung oder eine Teilzahlung ist ein Anerkenntnis: '
            'die Verjährung beginnt danach von vorn (§ 212 Abs. 1 Nr. 1 BGB), und das '
            'Bestreiten ist verbraucht. Wer bestreitet, zahlt nichts — auch nicht „erst mal '
            'einen Teil, um Ruhe zu haben".'),

        _abschnitt('Umfang'),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in const {
            'voll': 'Vollständig (100 %)',
            'teilweise': 'Teilweise',
            'nur_kosten': 'Nur die Inkassokosten',
          }.entries)
            ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 11.5)),
              selected: _umfang == e.key,
              onSelected: (_) => setState(() => _umfang = e.key),
            ),
        ]),

        _abschnitt('Gründe'),
        for (final e in _kGruende.entries)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _gruende.contains(e.key),
            onChanged: (v) => setState(() {
              if (v == true) {
                _gruende.add(e.key);
              } else {
                _gruende.remove(e.key);
              }
            }),
            title: Text(e.value, style: const TextStyle(fontSize: 12.5)),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _begruendungC,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: 'Eigene Begründung',
            helperText: 'Je genauer, desto besser — ein Kreuz allein überzeugt niemanden.',
            helperMaxLines: 2,
            alignLabelWithHint: true,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _auskunftVerlangt,
          onChanged: (v) => setState(() => _auskunftVerlangt = v ?? false),
          title: const Text('Darlegung nach § 13a RDG verlangen',
              style: TextStyle(fontSize: 12.5)),
          subtitle: Text(
              'Auftraggeber, Vertragsgegenstand und -datum, Zinsberechnung, Art und Höhe '
              'der Inkassokosten. Kommt nichts, ist die Forderung nicht überprüfbar — '
              'und das ist selbst ein Grund.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _kopieGlaeubiger,
          onChanged: (v) => setState(() => _kopieGlaeubiger = v ?? false),
          title: const Text('Kopie an den ursprünglichen Gläubiger',
              style: TextStyle(fontSize: 12.5)),
          subtitle: Text(
              'Über die Forderung entscheidet er, nicht das Büro. Oft zieht er den '
              'Auftrag zurück, sobald er vom Streit erfährt.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
        ),

        // ⚠️ Die Bedingung war einmal enger: nur wenn ein Insolvenzgrund
        // angekreuzt war. Damit hing der Vorgangswähler samt Anlagenliste
        // an einer Entscheidung, die genau dann noch NICHT gefallen ist,
        // wenn der Datensatz den Grund nicht hergibt — also bei den
        // älteren Verfahren. Der Beschluss lag in der Akte, und es gab
        // keinen Weg, ihn anzuhängen.
        if (_gruende.contains('restschuldbefreiung') ||
            _gruende.contains('insolvenz_laufend') ||
            _akten.isNotEmpty) ...[
          _abschnitt(_gruende.contains('restschuldbefreiung')
              ? 'Restschuldbefreiung'
              : _gruende.contains('insolvenz_laufend')
                  ? 'Laufendes Insolvenzverfahren'
                  : 'Insolvenz'),
          if (_gruende.contains('insolvenz_laufend'))
            _hinweis(Colors.orange, Icons.hourglass_top, 'Das Verfahren läuft noch',
                'Dann gilt NICHT § 301 InsO — eine Befreiung gibt es noch nicht. Es gelten '
                '§ 87 InsO (Forderungen nur nach den Vorschriften des Verfahrens verfolgbar) '
                'und § 89 InsO (keine Einzelzwangsvollstreckung). Die Forderung gehört zur '
                'Tabelle angemeldet und an den Verwalter gerichtet, nicht an das Mitglied. '
                '⚠️ Schulden, die NACH Eröffnung entstanden sind, sind davon nicht erfasst.'),
          _hinweis(Colors.green, Icons.verified_user, '§ 301 Abs. 1 InsO wirkt gegen ALLE',
              'Auch gegen Gläubiger, die ihre Forderung nie angemeldet haben. Genau darauf '
              'setzen Büros, die alte Forderungen aufkaufen und Jahre später anschreiben: '
              'dass niemand widerspricht. Die Forderung erlischt zwar nicht, sie wird zur '
              'unvollkommenen Verbindlichkeit — zahlbar, wenn man will, aber nicht '
              'durchsetzbar. Vollstreckung ist ausgeschlossen.'),
          _hinweis(Colors.orange, Icons.report_problem_outlined, 'Zwei Fälle, in denen es NICHT gilt',
              'Erstens die Ausnahmen des § 302 InsO — Forderungen aus vorsätzlich begangener '
              'unerlaubter Handlung, vorsätzlich vorenthaltener Unterhalt, bestimmte '
              'Steuerschulden, Geldstrafen, Verfahrenskostendarlehen. ⚠️ Bei der unerlaubten '
              'Handlung nur, wenn sie UNTER ANGABE DIESES RECHTSGRUNDES zur Tabelle '
              'angemeldet wurde — das lässt man sich nachweisen. Zweitens Schulden, die '
              'NACH Verfahrenseröffnung entstanden sind; die sind nie erfasst.'),
          if (_akten.isEmpty)
            _hinweis(Colors.grey, Icons.folder_off_outlined, 'Keine Insolvenz hinterlegt',
                'Unter Behörde ▸ Gericht ▸ Insolvenzgericht liegt der Vorgang samt '
                'Beschluss. Ist er dort angelegt, lässt er sich hier auswählen und '
                'Aktenzeichen und Datum stehen von selbst im Schreiben.')
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _akteId == null || _quelle == null
                  ? null
                  : '$_quelle:$_akteId',
              decoration: InputDecoration(
                labelText: 'Insolvenzvorgang',
                helperText: 'Aktenzeichen und Beschlussdatum kommen daraus in den Brief.',
                helperMaxLines: 2,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              // ⚠️ Der Wert ist `herkunft:id`, keine blosse Zahl. Beide
              // Tabellen fangen bei 1 an; mit nur der id waehlte der
              // Reiter irgendwann stillschweigend den falschen Vorgang.
              items: _akten
                  .map((a) => DropdownMenuItem(
                        value: '${a['herkunft']}:${a['id']}',
                        child: Text(
                            [a['bezeichnung'], a['aktenzeichen'] ?? a['az_gericht']]
                                .where((x) => (x?.toString() ?? '').trim().isNotEmpty)
                                .join(' · '),
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                final teile = v.split(':');
                setState(() {
                  _quelle = teile.first;
                  _akteId = int.tryParse(teile.last);
                  _docsAusQuelle();
                });
              },
            ),
          if (_akteId != null) ...[
            const SizedBox(height: 12),
            Text('Was mitgeht',
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 600))),
            const SizedBox(height: 4),
            if (_akteDocs.isEmpty)
              _hinweis(Colors.orange, Icons.attach_file, 'Kein Dokument in der Akte',
                  'Der Brief kündigt „Eine Abschrift des Beschlusses liegt bei" an. Solange '
                  'nichts angehängt ist, bleibt dieser Satz weg — eine Anlage anzukündigen, '
                  'die nicht mitgeht, ist schlimmer als keine.')
            else
              ..._akteDocs.map((d) {
                final id = int.tryParse(d['id']?.toString() ?? '') ?? 0;
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _anhaenge.contains(id),
                  onChanged: (an) => setState(() {
                    if (an == true) {
                      _anhaenge.add(id);
                    } else {
                      _anhaenge.remove(id);
                    }
                  }),
                  title: Text(
                      (d['datei_name'] ?? d['dateiname'] ?? d['filename'] ?? '')
                          .toString(),
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis),
                  subtitle: (d['kategorie']?.toString() ?? '').isEmpty
                      ? null
                      : Text(d['kategorie'].toString(),
                          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                );
              }),
          ],
        ],

        _abschnitt('Worauf sich der Widerspruch bezieht'),
        _hinweis(Colors.blue, Icons.auto_awesome, 'Aus dem Vorgang übernommen',
            'Forderung und Bezeichnung kommen aus dem Vorfall, das Datum aus dem jüngsten '
            'eingehenden Schreiben dieser Akte, der Gläubiger ist der Vermieter dieses '
            'Mietvertrages. Alles lässt sich überschreiben, Eingetragenes wird nie '
            'überschrieben.'),
        _datum('Datum des Inkasso-Schreibens', _schreibenVom,
            hinweis: 'Steht oben auf dem Brief, den Sie bestreiten.'),
        const SizedBox(height: 10),
        TextField(
          controller: _glaeubigerC,
          // Sobald jemand tippt, ist der Name bestätigt und nicht mehr
          // bloß aus der Akte übernommen — der Brief formuliert um.
          onChanged: (_) {
            if (_glaeubigerAusAkte) setState(() => _glaeubigerAusAkte = false);
          },
          decoration: InputDecoration(
            labelText: 'Gläubiger',
            helperText: _glaeubigerAusAkte
                ? 'Aus der Akte: der Vermieter dieses Vertrages. Der Brief sagt das auch '
                    'so und bittet um Berichtigung. ⚠️ Nennt das Büro einen anderen '
                    'Auftraggeber — Forderungen werden verkauft —, tragen Sie diesen ein.'
                : 'Wen das Büro als Auftraggeber nennt — nicht das Büro selbst.',
            helperMaxLines: 4,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _vertragRefC,
          decoration: InputDecoration(
            labelText: 'Rechnungs- oder Vertragsnummer',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _geld('Hauptforderung €', _hauptC)),
          const SizedBox(width: 8),
          Expanded(child: _geld('Zinsen €', _zinsenC)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _geld('Inkassokosten €', _kostenC)),
          const SizedBox(width: 8),
          Expanded(child: _geld('Gesamtbetrag €', _gesamtC)),
        ]),

        _abschnitt('Wer schreibt'),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in const {
            'bote': 'Im Namen des Mitglieds (wir übermitteln nur)',
            'vertreter': 'Als Bevollmächtigte des Mitglieds',
          }.entries)
            ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 11.5)),
              selected: _auftritt == e.key,
              onSelected: (_) => setState(() => _auftritt = e.key),
            ),
        ]),
        const SizedBox(height: 10),
        if (_auftritt == 'bote')
          _hinweis(Colors.green, Icons.forward_to_inbox, 'Die Erklärung ist die des Mitglieds',
              'Der Widerspruch steht in der Ich-Form und trägt den Namen des Mitglieds; '
              'wir übermitteln ihn nur über unseren Anschluss. Der Verein gibt damit keine '
              'eigene Erklärung ab — § 174 BGB greift nicht, und die Frage nach einer '
              'Vollmacht stellt sich gar nicht erst. Ein Übermittlungsvermerk am Ende sagt, '
              'warum Absender und Faxanschluss auseinanderfallen.')
        else
          _hinweis(Colors.orange, Icons.assignment_ind_outlined, 'Wir handeln in fremdem Namen',
              'Dann gehört die Vollmacht beigelegt: nach § 174 BGB kann das Schreiben sonst '
              'unverzüglich zurückgewiesen werden, und die Sache steht wieder am Anfang.'),
        const SizedBox(height: 6),
        _hinweis(Colors.grey, Icons.info_outline, 'Warum das keine Rechtsberatung ist',
            'Eine Forderung zu bestreiten, weil eine Restschuldbefreiung vorliegt, ist das '
            'Weitergeben einer Tatsache: der Beschluss existiert, er liegt bei, § 301 InsO '
            'spricht für sich. § 2 Abs. 1 RDG setzt eine rechtliche PRÜFUNG DES '
            'EINZELFALLS voraus — die findet hier nicht statt. Erst wenn zu beurteilen ist, '
            'ob eine Ausnahme nach § 302 InsO greift oder ob die Schuld vor oder nach '
            'Verfahrenseröffnung entstanden ist, wird es eine Frage für jemanden mit '
            'Zulassung.'),
        const SizedBox(height: 8),
        if (_mitgliedName.isEmpty)
        if (_mitgliedName.isEmpty)
          _hinweis(Colors.orange, Icons.person_off_outlined, 'Kein Name geladen',
              'Ohne den Namen kann das Schreiben nicht sagen, von wem es kommt — das Büro '
              'kennt den Verein nicht, es kennt den Schuldner. Ohne ihn bleibt der '
              'Absenderblock weg.')
        else
          // Die Nummer steht hier zur Kontrolle, wer gemeint ist —
          // im Brief taucht sie nicht auf.
          _hinweis(Colors.grey, Icons.badge_outlined, 'Absender',
              '$_mitgliedName'
              '${_mitgliedNummer.isEmpty ? '' : ' · Mitgliedsnummer $_mitgliedNummer (nur hier, nicht im Brief)'}'),
        const SizedBox(height: 8),
        if (_auftritt == 'vertreter') ...[
          _hinweis(Colors.red, Icons.description_outlined, 'Eine Kopie der Vollmacht genügt nicht',
              'Nach § 174 Satz 1 BGB muss die VollmachtsURKUNDE vorgelegt werden — eine '
              'Telefaxkopie oder ein Scan ist keine. Wer die Vollmacht faxt, hat sie im '
              'Sinne der Vorschrift nicht vorgelegt, und das Büro kann unverzüglich '
              'zurückweisen (in der Regel binnen einer Woche; danach ist es zu spät).'),
          _hinweis(Colors.green, Icons.how_to_reg, 'Der Ausweg: § 174 Satz 2 BGB',
              'Die Zurückweisung ist AUSGESCHLOSSEN, wenn das Mitglied das Büro selbst über '
              'die Bevollmächtigung informiert hat. Eine kurze Zeile genügt — danach kann '
              'der Verein per Fax und E-Mail schreiben, ohne die Urkunde je vorlegen zu '
              'müssen. Das ist der einfachere Weg als das Einschreiben mit dem Original.'),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _vollmachtAngezeigt,
            onChanged: (v) => setState(() => _vollmachtAngezeigt = v ?? false),
            title: const Text('Das Mitglied hat das Büro über die Vollmacht informiert',
                style: TextStyle(fontSize: 12.5)),
            subtitle: Text(
                'Dann nennt der Brief § 174 Satz 2 BGB, statt eine Anlage anzukündigen, '
                'die per Fax ohnehin keine Urkunde wäre.',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ),
          if (!_vollmachtAngezeigt)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: OutlinedButton.icon(
                onPressed: () => _anzeigetextZeigen(),
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('Text für das Mitglied anzeigen',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _rdgNennen,
          onChanged: (v) => setState(() => _rdgNennen = v ?? false),
          title: const Text('Befugnis nach § 7 RDG im Schreiben nennen',
              style: TextStyle(fontSize: 12.5)),
          subtitle: Text(
              'Nennt § 7 Abs. 1 Nr. 1 RDG als Grundlage. Sinnvoll, wenn ein Büro die '
              'Befugnis in Frage stellt — sonst nicht nötig.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ),
        ],

        _abschnitt('Betreff'),
        TextField(
          controller: _betreffC,
          decoration: InputDecoration(
            labelText: 'Betreff',
            helperText: 'Mit Aktenzeichen — daran ordnet das Büro den Vorgang zu.',
            helperMaxLines: 2,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (_) => setState(() {}),
        ),

        _abschnitt('Musterschreiben'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: F.h(Colors.grey, 50),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: F.h(Colors.grey, 300)),
          ),
          child: SelectableText('$_betreff\n\n${_brieftext()}',
              style: const TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace')),
        ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: '$_betreff\n\n${_brieftext()}'));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Text kopiert'),
                duration: Duration(seconds: 2),
              ));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Text kopieren', style: TextStyle(fontSize: 12)),
          ),
        ]),

        _abschnitt('Jetzt senden'),
        Builder(builder: (_) {
          final fax = (widget.inkassoFax ?? '').trim();
          final mail = (widget.inkassoEmail ?? '').trim();
          if (fax.isEmpty && mail.isEmpty) {
            return _hinweis(Colors.grey, Icons.info_outline, 'Keine Fax-Nummer, keine E-Mail',
                'Für dieses Büro ist weder Fax noch E-Mail hinterlegt. Ergänzen Sie beides '
                'in der Inkasso-Datenbank, dann geht der Widerspruch von hier aus raus.');
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: F.h(Colors.purple, 50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: F.h(Colors.purple, 200)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (fax.isNotEmpty)
                  Row(children: [
                    Icon(Icons.fax, size: 15, color: Colors.purple.shade400),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Fax: $fax', style: const TextStyle(fontSize: 12.5))),
                  ]),
                if (fax.isNotEmpty && mail.isNotEmpty) const SizedBox(height: 4),
                if (mail.isNotEmpty)
                  Row(children: [
                    Icon(Icons.email_outlined, size: 15, color: Colors.purple.shade400),
                    const SizedBox(width: 8),
                    Expanded(child: Text('E-Mail: $mail', style: const TextStyle(fontSize: 12.5))),
                  ]),
                const SizedBox(height: 10),
                // ⚠️ Vor dem Knopf, nicht danach: ob der Beschluss mitgeht,
                // muss man sehen können, BEVOR man drückt.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _anhaenge.isEmpty ? F.h(Colors.orange, 50) : F.h(Colors.green, 50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _anhaenge.isEmpty ? F.h(Colors.orange, 200) : F.h(Colors.green, 200)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_anhaenge.isEmpty ? Icons.warning_amber : Icons.attach_file,
                        size: 16,
                        color: _anhaenge.isEmpty
                            ? F.h(Colors.orange, 800)
                            : F.h(Colors.green, 800)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _anhaenge.isEmpty
                            ? 'Es geht NUR das Schreiben raus — keine Anlage. Der Beschluss '
                              'des Insolvenzgerichts wird nicht mitgeschickt.'
                            : '${_anhaenge.length} Anlage(n) gehen mit: '
                              '${_anhaenge.map((i) {
                                final d = _akteDocs
                                    .where((x) => x['id'].toString() == i.toString())
                                    .firstOrNull;
                                return (d?['datei_name'] ?? d?['dateiname'] ?? 'Anlage')
                                    .toString();
                              }).join(', ')}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: _anhaenge.isEmpty
                                ? F.h(Colors.orange, 900)
                                : F.h(Colors.green, 900),
                            height: 1.4),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                Text(
                  'Jeder Weg auf eigenen Knopfdruck. Wer beides schicken will, '
                  'drückt beides — dann steht auch beides einzeln im Protokoll.',
                  style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700), height: 1.4),
                ),
                const SizedBox(height: 12),
                // ⚠️ Wrap, nicht Row: zwei Knöpfe mit diesen Beschriftungen
                // passen auf einem 411-dp-Telefon nicht nebeneinander.
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (fax.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _sendet ? null : () => _sendenPer('fax'),
                      icon: _sendet
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.fax, size: 16),
                      label: const Text('Per Fax senden'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple, foregroundColor: Colors.white),
                    ),
                  if (mail.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _sendet ? null : () => _sendenPer('email'),
                      icon: _sendet
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.email_outlined, size: 16),
                      label: const Text('Per E-Mail senden'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.shade400, foregroundColor: Colors.white),
                    ),
                ]),
              ]),
            ),
            if (_sendeProtokoll.isNotEmpty) ...[
              const SizedBox(height: 10),
              // ⚠️ Jeder Weg einzeln quittiert. „Gesendet" für beides wäre
              // eine Lüge, sobald einer scheitert.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: F.h(Colors.grey, 50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: F.h(Colors.grey, 300)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final z in _sendeProtokoll)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(z,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: z.contains('abgeschickt')
                                    ? F.h(Colors.green, 800)
                                    : F.h(Colors.red, 800))),
                      ),
                  ],
                ),
              ),
            ],
          ]);
        }),

        _abschnitt('Versand'),
        // ⚠️ Fax zuerst, weil er über unseren Anschluss nichts kostet und
        // sofort draußen ist. Die verbreitete Faustregel „nur
        // Einwurfeinschreiben zählt" ist hier zu grob: sie stammt aus
        // Fällen mit gesetzlicher Frist. Dieser Widerspruch hat keine.
        _hinweis(Colors.green, Icons.fax, 'Fax — kostenlos und sofort draußen',
            'Über unseren Anschluss kostet ein Fax nichts, und es ist in derselben '
            'Minute beim Büro. Für diesen Widerspruch gibt es keine gesetzliche Frist, '
            'also zählt vor allem, DASS bestritten wurde und was drinstand — beides '
            'belegt der Sendebericht zusammen mit der abgelegten Seite.'),
        _hinweis(Colors.orange, Icons.rule, 'Der „OK"-Vermerk ist kein Zugangsnachweis',
            'Der BGH sieht im „OK" des Sendeberichts keinen Anscheinsbeweis für den '
            'Zugang — er belegt nur, dass eine Verbindung zustande kam. Wer den Zugang '
            'später beweisen können MUSS, schickt zusätzlich ein Einwurfeinschreiben. '
            'Für den Widerspruch gegen einen MAHNBESCHEID gilt das besonders: dort läuft '
            'eine Frist, und die ist gewahrt, wenn das Schreiben beim Gericht eingeht — '
            'nicht, wenn es abgeschickt wurde.'),
        _hinweis(Colors.green, Icons.move_to_inbox, 'Der Versand legt sich selbst ab',
            'Was rausgeht, steht danach als Ausgang unter Korrespondenz — mit Datum, '
            'Weg, Empfänger, dem vollständigen Wortlaut und den Anlagen. ⚠️ Den '
            'Sendebericht des Anbieters ersetzt das nicht: liegt er als Datei vor, '
            'gehört er dazu. Beim Anbieter ist der Verlauf nach ein paar Monaten '
            'gelöscht.'),
        Text('Wege — mehrere möglich',
            style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 600))),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in _kVersandweg.entries)
            FilterChip(
              label: Text(e.value, style: const TextStyle(fontSize: 11.5)),
              selected: _versandwege.contains(e.key),
              onSelected: (an) => setState(() {
                if (an) {
                  _versandwege.add(e.key);
                } else {
                  _versandwege.remove(e.key);
                }
              }),
            ),
        ]),
        const SizedBox(height: 10),
        _datum('Versendet am', _versendetAm),
        const SizedBox(height: 10),
        TextField(
          controller: _einschreibenC,
          decoration: InputDecoration(
            labelText: _versandwege.length == 1
                ? (_kBelegFeld[_versandwege.first] ?? 'Beleg')
                : 'Belege (Sendebericht, Sendungsnummer …)',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),

        _abschnitt('Eigene Unterlagen'),
        VermieterDokumente(
          apiService: widget.apiService,
          userId: widget.userId,
          typ: 'ws_dokument',
          parentId: widget.vorfallId,
          farbe: Colors.purple,
          titel: 'Widerspruch und Belege',
          hinweis: 'Das unterschriebene Schreiben, der Sendebericht des Fax, die '
              'Einlieferungsquittung, die Antwort des Büros — und bei einer '
              'Restschuldbefreiung der Beschluss. Der Verlauf beim Fax-Anbieter ist '
              'nach 30 Tagen gelöscht, und zwei Jahre später erinnert sich niemand mehr.',
        ),

        _abschnitt('Stand und Antwort'),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _status,
          decoration: InputDecoration(
            labelText: 'Status',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: _kStatus.entries
              .map((e) => DropdownMenuItem(
                  value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12))))
              .toList(),
          onChanged: (v) => setState(() => _status = v ?? _status),
        ),
        const SizedBox(height: 10),
        _datum('Antwort erhalten am', _reaktionAm),
        const SizedBox(height: 10),
        TextField(
          controller: _reaktionC,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Was geantwortet wurde',
            alignLabelWithHint: true,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notizC,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Notizen',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),

        const SizedBox(height: 18),
        Row(children: [
          ElevatedButton.icon(
            onPressed: _speichert ? null : _speichern,
            icon: _speichert
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
          ),
          const Spacer(),
          if (_vorhanden)
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Widerspruch löschen?'),
                    content: const Text(
                        'Gründe, Text und Versanddaten werden entfernt. Der Vorfall bleibt.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Abbrechen')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Löschen', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                await widget.apiService.deleteVermieterWiderspruch(widget.vorfallId);
                if (!mounted) return;
                setState(() {
                  _gruende.clear();
                  _umfang = 'voll';
                  _status = 'entwurf';
                  _versandwege
                    ..clear()
                    ..add('fax');
                });
                _laden();
              },
              icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
              label: Text('Löschen', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
            ),
        ]),
      ]),
    );
  }
}
