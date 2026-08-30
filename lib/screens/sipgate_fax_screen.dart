import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart' show FileType, PlatformFile;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx show PdfDocument;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/fax_badge_service.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/file_viewer_dialog.dart';
import 'fax_nummer_waehlen_screen.dart';
import '../utils/app_farben.dart';

/// Die gemerkten Empfänger aus einem gespeicherten Entwurf.
///
/// ⚠️ Frei stehend und nicht in der Zustandsklasse, damit sie ohne
/// Bildschirm geprüft werden kann. Ein Entwurf kommt aus dem Speicher des
/// Geräts, also aus einer Quelle, die eine ältere Fassung geschrieben haben
/// kann — was nicht passt, wird übergangen statt zu werfen. Ein Absturz beim
/// Öffnen des Faxbildschirms wegen eines alten Entwurfs wäre der schlechteste
/// aller Ausgänge.
List<FaxZiel> faxZieleAusEntwurf(dynamic roh) {
  if (roh is! List) return const [];
  final raus = <FaxZiel>[];
  for (final e in roh) {
    if (e is! Map) continue;
    final nr = (e['nummer'] ?? '').toString().trim();
    if (nr.isEmpty) continue;
    raus.add(FaxZiel(nr, (e['name'] ?? '').toString().trim()));
  }
  return raus;
}

/// Die Grenzen, die **sipgate** setzt — nicht wir.
///
/// ⚠️ NACHGESCHLAGEN, NICHT GESCHÄTZT. sipgate schreibt im eigenen
/// Hilfecenter „Es können PDF-Dateien mit bis zu 10 MB" und „maximal 30
/// Seiten" (help.sipgate.de → Cloud Telefonanlage → Fax einrichten, abgerufen
/// am 24.08.2026, für neo und classic gleichlautend). Beides sind harte
/// Grenzen der Gegenseite. Sie bei uns höher zu setzen macht kein größeres
/// Fax möglich — es verschiebt den Fehlschlag nur hinter das Hochladen, also
/// genau hinter die Minuten, die der Mensch schon gewartet hat.
///
/// ⚠️ Die Bytegrenze meint die DATEI. Auf dem Weg zu sipgate wird sie base64
/// und bläht um ein Drittel auf; das ist auf dem Server bedacht
/// (`SIPGATE_FAX_MAX_B`) und hier nicht noch einmal zu rechnen.
const int kFaxMaxBytes = 10 * 1024 * 1024;

/// ⚠️ Diese Grenze hat bis zum 24.08.2026 an KEINER Stelle existiert — weder
/// hier noch auf dem Server. Ein 3 MB großes, 60-seitiges Dokument kam durch
/// jede unserer Prüfungen und wurde erst von sipgate abgewiesen.
const int kFaxMaxSeiten = 30;

/// Was einem gewählten Dokument im Weg steht. Leerer Text heißt „nichts".
///
/// ⚠️ Frei stehend und ohne Bildschirm prüfbar — dieselbe Überlegung wie bei
/// [faxZieleAusEntwurf].
///
/// ⚠️ `seiten == null` heißt **„nicht ermittelbar"**, nicht „null Seiten".
/// Ein Dokument, dessen Seiten sich nicht zählen lassen, wird durchgelassen:
/// die Zählung ist eine Vorwarnung, kein Torwächter. Ein sendbares Fax wegen
/// unserer eigenen Unfähigkeit zu blockieren wäre der schlechtere Fehler, und
/// sipgate prüft ohnehin selbst.
String faxDokumentBeanstandung(String name, int bytes, int? seiten) {
  if (bytes > kFaxMaxBytes) {
    final mb = (bytes / 1048576).toStringAsFixed(1);
    return '„$name" ist $mb MB groß — sipgate nimmt höchstens '
        '${kFaxMaxBytes ~/ 1048576} MB.';
  }
  if (seiten != null && seiten > kFaxMaxSeiten) {
    return '„$name" hat $seiten Seiten — sipgate faxt höchstens '
        '$kFaxMaxSeiten Seiten je Sendung.';
  }
  return '';
}

/// Die Überschrift, unter die ein Fax im Verlauf gehört.
///
/// ⚠️ `jetzt` kommt als Parameter, statt drinnen `DateTime.now()` zu rufen.
/// Sonst wäre die Funktion nur an dem Tag prüfbar, an dem der Test läuft.
String faxTagesgruppe(DateTime zeitpunkt, DateTime jetzt) {
  final tag = DateTime(zeitpunkt.year, zeitpunkt.month, zeitpunkt.day);
  final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
  final weg = heute.difference(tag).inDays;
  if (weg == 0) return 'Heute';
  if (weg == 1) return 'Gestern';
  const monate = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
  ];
  final m = monate[tag.month - 1];
  // Das Jahr nur, wenn es ein anderes ist — sonst steht es in einer Liste
  // fünfzig Mal da und trägt nichts bei.
  return tag.year == heute.year
      ? '${tag.day}. $m'
      : '${tag.day}. $m ${tag.year}';
}

/// Ein Dokument, das mitgefaxt werden soll.
class FaxAnhang {
  final String name;
  final List<int> bytes;

  /// Seitenzahl. `null` heißt „ließ sich nicht ermitteln" — siehe
  /// [faxDokumentBeanstandung].
  final int? seiten;

  /// Die erste Seite als kleines Bild, oder `null`.
  final Uint8List? vorschau;

  const FaxAnhang(this.name, this.bytes, {this.seiten, this.vorschau});
}

/// Fax über sipgate.
///
/// ⚠️ WARUM DAS NICHT AM VOIP-TELEFON HÄNGT
/// Die App telefoniert per SIP-over-WebSocket gegen sip.sipgate.de. Fax kann
/// diesen Weg nicht nehmen — ein Fax ist ein Modem, kein Gespräch, und ein
/// WebRTC-Stack hat weder T.38 noch einen G.711-Passthrough. Fax läuft
/// ausschließlich über die REST-API und braucht deshalb ein eigenes, zweites
/// Zugangsmittel: einen Personal Access Token.
///
/// ⚠️ WARUM DER VERLAUF UNSERER IST UND NICHT DER VON SIPGATE
/// sipgate löscht seinen Verlauf nach 30 Tagen (`historyLifeTime:
/// THIRTY_DAYS`, am Konto nachgesehen). Jedes gesendete und jedes empfangene
/// Dokument liegt deshalb verschlüsselt auf unserem Server. Was dieser
/// Bildschirm zeigt, überlebt die 30 Tage; was bei sipgate steht, nicht.
class SipgateFaxScreen extends StatefulWidget {
  /// Nur die Faxe zu EINEM Mitglied.
  ///
  /// 🔴 Bis zum 23.08.2026 gab es diesen Weg nicht — und er fehlte an beiden
  /// Enden: die Spalte, die sagt, wen ein Fax betrifft, existierte gar nicht,
  /// und `user_id` bedeutete je nach Sendeweg entweder „wer hat getippt" oder
  /// „um wen geht es". Ein Fax vom Jobcenter über ein Mitglied war von der
  /// Mitgliederakte aus nicht auffindbar.
  final int? betrifftUserId;

  /// Nur die Faxe zu EINEM Vorgang. ⚠️ Der Server konnte das seit dem
  /// 21.08. — der Bildschirm hat nie danach gefragt.
  final String? bezugTyp;
  final int? bezugId;

  /// Was in der Titelzeile steht, wenn gefiltert wird. Ohne das hieße der
  /// Bildschirm weiter „Fax" und sähe aus wie der ganze Verlauf, obwohl er
  /// einen Ausschnitt zeigt — die gefährlichste Art von Liste.
  final String? titel;

  /// Ohne eigenes Gerüst — für die Einbettung in einen Reiter.
  ///
  /// ⚠️ Ein Scaffold in einem TabBarView ergäbe eine zweite Titelleiste
  /// mitten in der Mitgliedsakte. Eingebettet fallen deshalb Titelleiste und
  /// ihre Knöpfe weg; Journal, Protokoll und Neuladen sind ohnehin Aktionen
  /// für den ganzen Verlauf und gehören nicht in eine einzelne Akte.
  final bool eingebettet;

  const SipgateFaxScreen({
    super.key,
    this.betrifftUserId,
    this.bezugTyp,
    this.bezugId,
    this.titel,
    this.eingebettet = false,
  });

  /// Zeigt der Bildschirm einen Ausschnitt statt des ganzen Verlaufs?
  bool get gefiltert =>
      betrifftUserId != null || (bezugTyp != null && bezugId != null);

  @override
  State<SipgateFaxScreen> createState() => _SipgateFaxScreenState();
}

class _SipgateFaxScreenState extends State<SipgateFaxScreen> {
  final ApiService _api = ApiService();

  final TextEditingController _empfaenger = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _betreff = TextEditingController();
  final TextEditingController _nachricht = TextEditingController();
  final TextEditingController _aktenzeichen = TextEditingController();
  final TextEditingController _suche = TextEditingController();

  bool _lade = true;

  /// Wurde beim Öffnen ein gespeicherter Entwurf eingesetzt?
  ///
  /// ⚠️ WOFÜR: ein Entwurf merkt sich Text, Empfänger und Aktenzeichen — die
  /// **Dokumente nicht**, und das mit Absicht: ein mehrseitiges PDF gehört
  /// nicht in `SharedPreferences`. Bis zum 24.08.2026 stand darüber aber kein
  /// Wort. Wer zurückkam, sah ein ausgefülltes Formular, drückte senden und
  /// bekam „Kein Dokument gewählt" — die Auskunft kam also erst, nachdem der
  /// Mensch dachte, er sei fertig.
  bool _entwurfOhneDokument = false;
  bool _sendet = false;

  /// Läuft gerade das Durchsehen gewählter Dokumente?
  ///
  /// ⚠️ Vier mehrseitige PDF durch pdfium zu schicken dauert auf der Tablette
  /// spürbar. Ohne dieses Kennzeichen stünde der Knopf still da und niemand
  /// wüsste, ob der Griff angekommen ist — die häufigste Reaktion darauf ist,
  /// ihn noch einmal zu drücken.
  bool _sichtetDokumente = false;
  bool _mehrLaedt = false;
  bool _deckblatt = false;
  Map<String, dynamic> _zugang = const {};
  List<Map<String, dynamic>> _faxe = const [];

  /// Verlaufsfilter. Serverseitig ausgewertet — `status` und `richtung` stehen
  /// genau dafür im Klartext in der Tabelle.
  String _stand = '';
  bool _mehrDa = false;
  int _gefunden = 0;
  Timer? _sucheEntprellen;

  /// Wie viele Zeilen auf einmal geholt werden. Absichtlich nicht „alle": bei
  /// fünf Jahren Betrieb wären das Tausende, entschlüsselt über genau die
  /// Mobilfunkleitung, die dieses Projekt an anderer Stelle als zu langsam
  /// beanstandet.
  static const int _seitenGroesse = 50;

  /// Die gewählten Dokumente. Bewusst als Bytes im Speicher und nicht als
  /// Pfad: auf Android liefert die Dateiauswahl einen content://-Verweis, der
  /// nach dem Schließen des Dialogs nicht mehr lesbar sein muss.
  List<FaxAnhang> _dokumente = [];

  /// Vorschaubilder, nach Fax-Id.
  ///
  /// ⚠️ Ein Eintrag mit Wert `null` heißt „schon versucht, gibt es nicht" —
  /// etwas anderes als „noch nicht geholt" (kein Eintrag). Ohne diesen
  /// Unterschied fragte der Bildschirm für jedes Fax ohne Vorschau bei jedem
  /// Neuaufbau erneut nach, also endlos.
  final Map<int, Uint8List?> _miniaturen = {};
  final Set<int> _miniaturLaeuft = {};

  /// Weitere Empfänger neben dem, der gerade im Feld steht.
  ///
  /// 🔴 WARUM ES DAS BRAUCHT
  /// Dieselbe Mitteilung geht regelmäßig an mehr als eine Stelle — Jobcenter
  /// und Familienkasse, Praxis und Krankenkasse. Bisher hieß das: alles
  /// zweimal tippen und die Dokumente zweimal auswählen, und wer beim zweiten
  /// Mal unterbrochen wird, hat die Hälfte verschickt und weiß es nicht.
  ///
  /// ⚠️ Jeder Empfänger wird ein EIGENER Vorgang, kein gemeinsamer. Der
  /// Gruppenschlüssel fasst zusammen, was zusammen an EINEN Empfänger ging;
  /// ein Sendebericht gilt immer nur für eine Gegenstelle. Zwei Empfänger in
  /// einen Vorgang zu werfen hieße, im Verlauf eine Zustellung zu behaupten,
  /// die für den anderen nie belegt wurde.
  List<FaxZiel> _weitereZiele = [];

  /// Damit das Sendefeld sichtbar wird, wenn „Antworten" es füllt.
  final ScrollController _blaettern = ScrollController();

  /// Schlüssel des Entwurfs.
  ///
  /// ⚠️ NUR TEXT, NIE DOKUMENTE. Die gewählten PDFs bleiben im Speicher —
  /// derselbe Grund, aus dem dieser Bildschirm ein angesehenes Fax nicht in
  /// den Temp-Ordner legt: ein Faxentwurf enthält Widersprüche und Atteste,
  /// und was auf der Platte liegt, überlebt die Sitzung und landet in
  /// Sicherungen. Wer die App neu startet, muss die Datei erneut wählen —
  /// das ist der Preis, und er ist richtig herum bezahlt.
  static const String _entwurfKey = 'fax_entwurf_v1';
  Timer? _entwurfSpeichern;

  @override
  void initState() {
    super.initState();
    _entwurfLaden();
    for (final c in [_empfaenger, _name, _betreff, _nachricht, _aktenzeichen]) {
      c.addListener(_entwurfAnstossen);
    }
    _laden(live: true);
  }

  /// ⚠️ Entprellt. Ohne das schriebe jede Taste in den Speicher — bei einer
  /// 900 Zeichen langen Nachricht neunhundert Schreibvorgänge.
  void _entwurfAnstossen() {
    _entwurfSpeichern?.cancel();
    _entwurfSpeichern = Timer(const Duration(milliseconds: 600), _entwurfSichern);
  }

  Future<void> _entwurfSichern() async {
    try {
      final p = await SharedPreferences.getInstance();
      final leer = _empfaenger.text.trim().isEmpty &&
          _name.text.trim().isEmpty &&
          _betreff.text.trim().isEmpty &&
          _nachricht.text.trim().isEmpty &&
          _aktenzeichen.text.trim().isEmpty &&
          _weitereZiele.isEmpty;
      if (leer) { await p.remove(_entwurfKey); return; }
      await p.setString(_entwurfKey, jsonEncode({
        'empfaenger': _empfaenger.text,
        'name': _name.text,
        'betreff': _betreff.text,
        'nachricht': _nachricht.text,
        'aktenzeichen': _aktenzeichen.text,
        'deckblatt': _deckblatt,
        'ziele': [for (final z in _weitereZiele) {'nummer': z.nummer, 'name': z.name}],
      }));
    } catch (_) {
      // Ein nicht gespeicherter Entwurf ist ein Ärgernis, kein Fehler, den
      // man dem Menschen mitten im Tippen melden müsste.
    }
  }

  Future<void> _entwurfLaden() async {
    try {
      final p = await SharedPreferences.getInstance();
      final roh = p.getString(_entwurfKey);
      if (roh == null || roh.isEmpty) return;
      final d = jsonDecode(roh);
      if (d is! Map) return;
      if (!mounted) return;
      setState(() {
        _empfaenger.text = (d['empfaenger'] ?? '').toString();
        _name.text = (d['name'] ?? '').toString();
        _betreff.text = (d['betreff'] ?? '').toString();
        _nachricht.text = (d['nachricht'] ?? '').toString();
        _aktenzeichen.text = (d['aktenzeichen'] ?? '').toString();
        _deckblatt = d['deckblatt'] == true;
        _weitereZiele = faxZieleAusEntwurf(d['ziele']);
        _entwurfOhneDokument = true;
      });
    } catch (_) {
      // Ein unlesbarer Entwurf wird verworfen, nicht gemeldet.
    }
  }

  Future<void> _entwurfVerwerfen() async {
    _entwurfSpeichern?.cancel();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_entwurfKey);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sucheEntprellen?.cancel();
    _entwurfSpeichern?.cancel();
    for (final c in [_empfaenger, _name, _betreff, _nachricht, _aktenzeichen]) {
      c.removeListener(_entwurfAnstossen);
    }
    _blaettern.dispose();
    _empfaenger.dispose();
    _name.dispose();
    _betreff.dispose();
    _nachricht.dispose();
    _aktenzeichen.dispose();
    _suche.dispose();
    super.dispose();
  }

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade700 : null,
      duration: Duration(seconds: fehler ? 6 : 3),
    ));
  }

  // ---------------------------------------------------------------------------
  //  Laden
  // ---------------------------------------------------------------------------

  /// ⚠️ Der Ausschnitt geht bei JEDER Abfrage mit — auch beim Nachladen und
  /// bei der Suche. Stünde er nur in der ersten, brächte „Mehr laden" den
  /// ganzen Verlauf in eine Liste, die sich als Mitgliedsakte ausgibt.
  Map<String, dynamic> _listenAnfrage(int offset) => {
        'action': 'list',
        'limit': _seitenGroesse,
        'offset': offset,
        if (_suche.text.trim().isNotEmpty) 'suche': _suche.text.trim(),
        if (_stand.isNotEmpty) 'stand': _stand,
        if (widget.betrifftUserId != null) 'betrifft_user_id': widget.betrifftUserId,
        if (widget.bezugTyp != null && widget.bezugId != null) ...{
          'bezug_typ': widget.bezugTyp,
          'bezug_id': widget.bezugId,
        },
      };

  Future<void> _laden({bool live = false}) async {
    setState(() => _lade = true);
    // ⚠️ `live` fragt sipgate wirklich. Ohne den Schalter sagt die Antwort nur,
    // was in unserer Tabelle steht — und ein zurückgezogener Token sieht dort
    // genauso aus wie ein gültiger.
    final z = await _api.sipgateFaxAction({'action': 'status', if (live) 'live': true});
    final l = await _api.sipgateFaxAction(_listenAnfrage(0));
    if (!mounted) return;
    setState(() {
      _zugang = z['success'] == true ? Map<String, dynamic>.from(z) : const {};
      _faxe = _zeilenAus(l);
      _gefunden = (l['gefunden'] as num?)?.toInt() ?? _faxe.length;
      _mehrDa = l['mehr'] == true;
      _lade = false;
    });
    _badgeUebernehmen(l);
  }

  /// Nächste Seite anhängen — nicht ersetzen.
  Future<void> _mehrLaden() async {
    if (_mehrLaedt || !_mehrDa) return;
    setState(() => _mehrLaedt = true);
    final l = await _api.sipgateFaxAction(_listenAnfrage(_faxe.length));
    if (!mounted) return;
    setState(() {
      _faxe = [..._faxe, ..._zeilenAus(l)];
      _mehrDa = l['mehr'] == true;
      _mehrLaedt = false;
    });
  }

  List<Map<String, dynamic>> _zeilenAus(Map<String, dynamic> antwort) =>
      antwort['success'] == true
          ? List<Map<String, dynamic>>.from(
              (antwort['faxe'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e)))
          : const [];

  /// Hält das Abzeichen im Kopf synchron, ohne eine zweite Anfrage.
  void _badgeUebernehmen(Map<String, dynamic> antwort) {
    final n = faxUngeleseneAusAntwort(antwort);
    if (n != null) FaxBadgeService().setzen(n);
  }

  void _neuFiltern() {
    _sucheEntprellen?.cancel();
    // ⚠️ Entprellt: sonst ginge je Tastendruck eine Anfrage raus, und die
    // Antworten kämen in beliebiger Reihenfolge zurück — die Liste passte dann
    // zum vorletzten Buchstaben.
    _sucheEntprellen = Timer(const Duration(milliseconds: 350), () => _laden());
  }

  // ---------------------------------------------------------------------------
  //  Zugang
  // ---------------------------------------------------------------------------

  Future<void> _tokenDialog() async {
    final id = TextEditingController(text: (_zugang['token_id'] ?? '').toString());
    final tok = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('sipgate-Zugang für Fax'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Fax braucht ein eigenes Zugangsmittel — die SIP-Zugangsdaten des '
              'VoIP-Telefons reichen dafür nicht.\n\n'
              'In app.sipgate.com unter „Personal Access Token" einen Token anlegen '
              'mit den Rechten:\n'
              '  • sessions:fax:write\n'
              '  • history:read\n'
              '  • faxlines:read',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: id,
              decoration: const InputDecoration(
                labelText: 'Token-ID', hintText: 'token-XXXXXX', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tok,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Token',
                // sipgate zeigt den Token genau einmal an. Wer ihn nicht
                // kopiert hat, legt einen neuen an — das gehört hier hin,
                // bevor jemand vergeblich sucht.
                helperText: 'Wird von sipgate nur einmal angezeigt',
                border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Prüfen & speichern')),
        ],
      ),
    );
    if (ok != true) return;

    // ⚠️ Der Server prüft live gegen sipgate, BEVOR er speichert. Ein
    // vertippter Token ließe sich sonst speichern, der Bildschirm zeigte
    // „eingerichtet", und der Fehler käme erst beim ersten Fax — also genau
    // dann, wenn es eilt.
    final r = await _api.sipgateFaxAction({
      'action': 'token_save',
      'token_id': id.text.trim(),
      'token': tok.text.trim(),
    });
    _melde(r['message']?.toString() ?? (r['success'] == true ? 'Gespeichert' : 'Fehlgeschlagen'),
        fehler: r['success'] != true);
    if (r['success'] == true) await _laden(live: true);
  }

  Future<void> _kennungSetzen() async {
    final r = await _api.sipgateFaxAction({
      'action': 'absenderkennung_setzen',
      'wert': (_zugang['absender'] ?? '').toString(),
    });
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    if (r['success'] == true) await _laden(live: true);
  }

  // ---------------------------------------------------------------------------
  //  Senden
  // ---------------------------------------------------------------------------

  Future<void> _dokumenteWaehlen() async {
    final res = await FilePickerHelper.pickFiles(
      dialogTitle: 'PDF zum Faxen wählen',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
      // ⚠️ sipgate nimmt EIN PDF je Sendung — mehrere Dateien werden deshalb
      // NICHT zusammengefügt, sondern als eigene Faxe hintereinander
      // geschickt, jedes mit eigenem Sendebericht. Fremde PDFs zu verschmelzen
      // wäre hübscher und falsch: ein stillschweigend halb übernommener
      // Beschluss ist schlimmer als zwei Sendungen. Dieselbe Entscheidung wie
      // im Widerspruchs-Bildschirm.
      allowMultiple: true,
    );
    final dateien = res?.files ?? const [];
    if (dateien.isEmpty) return;

    if (mounted) setState(() => _sichtetDokumente = true);
    try {
      await _dokumenteSichten(dateien);
    } finally {
      if (mounted) setState(() => _sichtetDokumente = false);
    }
  }

  /// Liest, prüft und sichtet die gewählten Dateien.
  Future<void> _dokumenteSichten(List<PlatformFile> dateien) async {
    final gewaehlt = <FaxAnhang>[];
    for (final datei in dateien) {
      final List<int>? gelesen = datei.bytes ??
          (datei.path != null ? await File(datei.path!).readAsBytes() : null);
      if (gelesen == null) {
        _melde('„${datei.name}" ist nicht lesbar', fehler: true);
        return;
      }
      // ⚠️ Hier prüfen, nicht erst auf dem Server: sipgate nimmt ausschließlich
      // PDF, und die Endung sagt nichts über den Inhalt. Ein umbenanntes Bild
      // käme erst zurück, nachdem es vollständig hochgeladen wurde — bei einem
      // mehrseitigen Dokument über die Mobilfunkleitung ist das eine Minute
      // Wartezeit für eine Auskunft, die hier sofort zu haben ist.
      const kopf = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
      final istPdf = gelesen.length > kopf.length &&
          List.generate(kopf.length, (i) => gelesen[i] == kopf[i]).every((b) => b);
      if (!istPdf) {
        _melde('„${datei.name}" ist kein PDF. sipgate faxt nur PDF.', fehler: true);
        return;
      }
      // ⚠️ Seiten zählen und die erste Seite ansehen — VOR dem Hochladen.
      // Die 10-MB-Grenze stand bis zum 24.08.2026 allein auf dem Server: ein
      // zu großes Dokument wurde erst abgewiesen, NACHDEM es über die
      // Mobilfunkleitung der Tablette oben war. Dieselbe Überlegung wie bei
      // der %PDF--Prüfung eine Zeile höher, nur teurer bezahlt.
      final durchgesehen = await _pdfDurchsehen(gelesen);
      final klage = faxDokumentBeanstandung(
          datei.name, gelesen.length, durchgesehen.seiten);
      if (klage.isNotEmpty) {
        _melde(klage, fehler: true);
        return;
      }
      gewaehlt.add(FaxAnhang(datei.name, gelesen,
          seiten: durchgesehen.seiten, vorschau: durchgesehen.bild));
    }

    setState(() {
      _dokumente = gewaehlt;
      _entwurfOhneDokument = false;
    });
  }

  /// Seitenzahl und ein kleines Bild der ersten Seite.
  ///
  /// ⚠️ Fällt STILL auf `(null, null)` zurück. pdfium scheitert an einem
  /// verschlüsselten oder ungewöhnlich gebauten PDF, das sipgate trotzdem
  /// faxt — eine Fehlermeldung wäre hier eine Behauptung über das Dokument,
  /// die wir nicht belegen können. Wer nicht zählen kann, schweigt und lässt
  /// durch.
  Future<({int? seiten, Uint8List? bild})> _pdfDurchsehen(List<int> roh) async {
    pdfrx.PdfDocument? doc;
    try {
      doc = await pdfrx.PdfDocument.openData(Uint8List.fromList(roh));
      final anzahl = doc.pages.length;
      Uint8List? bild;
      if (anzahl > 0) {
        final seite = doc.pages.first;
        // 40 dpi. Genug, um ein Blatt wiederzuerkennen; wenig genug, dass
        // vier gewählte Dokumente nicht den Speicher der Tablette füllen.
        // Der Verlauf rastert seine Vorschauen mit 30.
        final breite = (seite.width / 72.0 * 40).round();
        final hoehe = (seite.height / 72.0 * 40).round();
        if (breite > 0 && hoehe > 0) {
          final g = await seite.render(
              x: 0,
              y: 0,
              fullWidth: breite.toDouble(),
              fullHeight: hoehe.toDouble());
          if (g != null) bild = await _rgbaZuPng(g.pixels, breite, hoehe);
        }
      }
      return (seiten: anzahl, bild: bild);
    } catch (_) {
      return (seiten: null, bild: null);
    } finally {
      // ⚠️ Muss sein: pdfium hält das Dokument nativ, also außerhalb dessen,
      // was der Sammler von Dart je aufräumt. Vier Dokumente je Sendung, den
      // Tag über, sind sonst vier undichte Stellen je Sendung.
      try {
        await doc?.dispose();
      } catch (_) {}
    }
  }

  /// Rohe Bildpunkte als PNG, damit `Image.memory` sie zeigen kann.
  Future<Uint8List?> _rgbaZuPng(Uint8List punkte, int breite, int hoehe) async {
    try {
      final puffer = await ui.ImmutableBuffer.fromUint8List(punkte);
      final beschreibung = ui.ImageDescriptor.raw(puffer,
          width: breite, height: hoehe, pixelFormat: ui.PixelFormat.rgba8888);
      final kodierer = await beschreibung.instantiateCodec();
      final bild = (await kodierer.getNextFrame()).image;
      final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
      bild.dispose();
      kodierer.dispose();
      beschreibung.dispose();
      puffer.dispose();
      return daten?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Ein einzelnes Dokument abschicken. Gibt die Antwort zurück.
  ///
  /// ⚠️ Das Ziel kommt als Parameter, nicht mehr aus dem Eingabefeld. Solange
  /// es `_empfaenger.text` las, konnte es per Bauart nur einen Empfänger
  /// geben — und ein zweiter hätte still an den ersten gefaxt.
  Future<Map<String, dynamic>> _einesSenden(
    FaxAnhang anhang, {
    required FaxZiel ziel,
    required bool mitDeckblatt,
    bool deckblattSeparat = false,
    String gruppe = '',
    int pos = 0,
    int von = 0,
    bool trotzdem = false,
  }) {
    return _api.sipgateFaxAction({
      'action': 'senden',
      if (trotzdem) 'trotzdem': true,
      'empfaenger': ziel.nummer,
      'empfaenger_name': ziel.name,
      'dateiname': anhang.name,
      'inhalt_b64': base64Encode(anhang.bytes),
      if (mitDeckblatt) ...{
        'deckblatt': true,
        if (deckblattSeparat) 'deckblatt_separat': true,
        'betreff': _betreff.text.trim(),
        'nachricht': _nachricht.text,
        'aktenzeichen': _aktenzeichen.text.trim(),
      },
      if (gruppe.isNotEmpty) ...{
        'gruppe_key': gruppe,
        'gruppe_pos': pos,
        'gruppe_von': von,
      },
      // Ein mehrseitiges PDF geht zweimal über die Leitung: zu uns und von
      // uns zu sipgate. 90 s statt der üblichen 25.
    }, timeout: const Duration(seconds: 90));
  }

  /// Alle gewählten Dokumente an EIN Ziel.
  ///
  /// ⚠️ Eigener Gruppenschlüssel je Ziel. Der Schlüssel fasst zusammen, was
  /// gemeinsam an eine Gegenstelle ging; ein Sendebericht gilt immer nur für
  /// eine. Zwei Empfänger in einen Vorgang zu legen hieße, im Verlauf eine
  /// Zustellung zu behaupten, die für den zweiten nie belegt wurde.
  Future<({int erfolge, String meldung})> _anZielSenden(FaxZiel ziel) async {
    final mehrere = _dokumente.length > 1;
    var separat = false;
    var erfolge = 0;
    var gruppe = '';
    var meldung = '';

    for (var i = 0; i < _dokumente.length; i++) {
      var r = await _einesSenden(
        _dokumente[i],
        ziel: ziel,
        // ⚠️ Das Deckblatt gehört nur an das ERSTE Fax. An jedes zu hängen
        // hieße, dem Empfänger dieselbe Ankündigung viermal zu schicken.
        mitDeckblatt: _deckblatt && i == 0,
        deckblattSeparat: separat,
        gruppe: gruppe,
        pos: mehrere ? i + 1 : 0,
        von: mehrere ? _dokumente.length : 0,
      );

      // ⚠️ SCHON ZUGESTELLT? Dann nachfragen, nicht einfach senden.
      //
      // Gebremst wird ausschließlich, wenn dasselbe Dokument an dieselbe
      // Nummer nachweislich ANGEKOMMEN ist. War der erste Versuch
      // fehlgeschlagen, kommt diese Antwort gar nicht — dann ist die zweite
      // Sendung genau das Richtige und darf nichts im Weg stehen.
      if (r['success'] != true && '${r['grund'] ?? ''}' == 'dublette') {
        if (!mounted) break;
        final nochmal = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Wurde schon zugestellt'),
            content: Text('An ${ziel.nummer}\n\n${r['message'] ?? ''}',
                style: const TextStyle(fontSize: 13.5, height: 1.4)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Nicht senden')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Trotzdem senden')),
            ],
          ),
        );
        if (nochmal != true) { meldung = 'Abgebrochen — war schon zugestellt'; break; }
        r = await _einesSenden(_dokumente[i], ziel: ziel,
            mitDeckblatt: _deckblatt && i == 0, deckblattSeparat: separat,
            gruppe: gruppe, pos: mehrere ? i + 1 : 0, von: mehrere ? _dokumente.length : 0,
            trotzdem: true);
      }

      // ⚠️ Das gesiegelte Dokument: der Server lehnt das Zusammenfügen ab und
      // sagt WARUM (`grund: signiert`). Erst hier wird gefragt, statt in einer
      // Sackgasse zu enden — und die Antwort gilt dann für den ganzen Vorgang.
      if (r['success'] != true && '${r['grund'] ?? ''}' == 'signiert') {
        if (!mounted) break;
        final weiter = await _siegelFrage();
        if (weiter == null) { meldung = 'Abgebrochen'; break; }
        if (weiter) {
          separat = true;
          r = await _einesSenden(_dokumente[i], ziel: ziel,
              mitDeckblatt: true, deckblattSeparat: true,
              gruppe: gruppe, pos: mehrere ? i + 1 : 0, von: mehrere ? _dokumente.length : 0);
        } else {
          setState(() => _deckblatt = false);
          r = await _einesSenden(_dokumente[i], ziel: ziel,
              mitDeckblatt: false,
              gruppe: gruppe, pos: mehrere ? i + 1 : 0, von: mehrere ? _dokumente.length : 0);
        }
      }

      meldung = r['message']?.toString() ?? '';
      if (r['success'] == true) {
        erfolge++;
        final g = '${r['gruppe_key'] ?? ''}';
        if (g.isNotEmpty) gruppe = g;
      } else {
        // ⚠️ Nach einem Fehlschlag wird ABGEBROCHEN, nicht weitergefaxt. Wenn
        // schon der Widerspruch nicht durchkommt, sind drei Anlagen beim
        // Empfänger nur Papier ohne Bezug — und bei uns stünde ein Vorgang,
        // dessen Hauptstück fehlt.
        break;
      }
    }
    return (erfolge: erfolge, meldung: meldung);
  }

  Future<void> _senden() async {
    if (_dokumente.isEmpty) { _melde('Kein Dokument gewählt', fehler: true); return; }
    final ziele = _zieleJetzt();
    if (ziele.isEmpty) { _melde('Keine Empfängernummer', fehler: true); return; }

    final proZiel = _dokumente.length;
    final gesamt = proZiel * ziele.length;

    // 🔴 WAS KOSTET DIESES ZIEL — gefragt VOR dem Senden, nicht danach.
    //
    // Der Server lehnt Mehrwert- und Satellitennummern von sich aus ab. Hier
    // geht es um die Fälle dazwischen: 0180 und Ausland sind erlaubt und
    // kosten Guthaben. Beim Nachsehen am 23.08.2026 standen dort 18,64 € —
    // eine Zahl, bei der ein Zahlendreher zählt, und seit es mehrere
    // Empfänger je Sendung gibt, vervielfacht er sich.
    //
    // ⚠️ Eine Anfrage mehr vor einem Vorgang, der sich nicht zurückholen
    // lässt. Fällt sie aus, wird trotzdem gesendet: der Server prüft ohnehin
    // ein zweites Mal, und ein Netzfehler darf kein Fax verhindern.
    final warnungen = <String>[];
    try {
      final p = await _api.sipgateFaxAction({
        'action': 'ziel_pruefen',
        'nummern': [for (final z in ziele) z.nummer],
      });
      if (p['success'] == true) {
        for (final z in ((p['ziele'] as List?) ?? const []).whereType<Map>()) {
          final w = (z['warnung'] ?? '').toString();
          if (w.isNotEmpty) warnungen.add('${z['eingabe']}: $w');
          final g = (z['grund'] ?? '').toString();
          if (z['erlaubt'] != true && g.isNotEmpty) warnungen.add('${z['eingabe']}: $g');
        }
      }
    } catch (_) {
      // Kein Grund, das Senden aufzuhalten — der Server prüft noch einmal.
    }
    if (!mounted) return;

    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(gesamt > 1 ? '$gesamt Faxe jetzt senden?' : 'Fax jetzt senden?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('An:', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final z in ziele)
              Text(z.name.isEmpty ? z.nummer : '${z.name} · ${z.nummer}',
                  style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            const Text('Dokumente:', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final d in _dokumente) Text('• ${d.name}', style: const TextStyle(fontSize: 13)),
            if (proZiel > 1) ...[
              const SizedBox(height: 8),
              // Der Satz ist keine Floskel: er erklärt, warum gleich mehrere
              // Zeilen im Verlauf erscheinen und mehrere Berichte kommen.
              const Text(
                'sipgate überträgt ein Dokument je Sendung. Die Dateien gehen '
                'deshalb nacheinander als eigene Faxe — im Verlauf als ein '
                'Vorgang zusammengefasst, jedes mit eigenem Sendebericht.',
                style: TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ],
            if (ziele.length > 1) ...[
              const SizedBox(height: 8),
              const Text(
                'Jeder Empfänger wird ein eigener Vorgang mit eigenem '
                'Sendebericht — ein Bericht belegt immer nur eine Gegenstelle.',
                style: TextStyle(fontSize: 12.5, height: 1.35),
              ),
            ],
            if (warnungen.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final w in warnungen)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.euro_symbol, size: 14, color: F.h(Colors.orange, 800)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(w,
                        style: TextStyle(fontSize: 12.5, height: 1.3,
                            color: F.h(Colors.orange, 900))),
                  ),
                ]),
            ],
            const SizedBox(height: 8),
            const Text('Ein gesendetes Fax lässt sich nicht zurückholen.',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Senden')),
        ],
      ),
    );
    if (bestaetigt != true) return;

    setState(() => _sendet = true);
    var erfolge = 0;
    var letzteMeldung = '';
    final gescheitert = <String>[];

    for (final ziel in ziele) {
      final e = await _anZielSenden(ziel);
      erfolge += e.erfolge;
      if (e.meldung.isNotEmpty) letzteMeldung = e.meldung;
      // ⚠️ Ein Empfänger, bei dem es klemmt, hält die anderen NICHT auf —
      // anders als bei den Dokumenten eines Vorgangs. Dort hängen die Teile
      // zusammen; hier sind es getrennte Sendungen an getrennte Stellen, und
      // dass die Praxis besetzt ist, ist kein Grund, das Jobcenter nicht zu
      // beliefern. Wer ausfiel, steht am Ende namentlich da.
      if (e.erfolge < proZiel) {
        gescheitert.add(ziel.name.isEmpty ? ziel.nummer : ziel.name);
      }
      if (!mounted) return;
    }

    if (!mounted) return;
    setState(() => _sendet = false);

    final alle = erfolge == gesamt;
    _melde(
      alle
          ? (gesamt > 1 ? '$erfolge Faxe an sipgate übergeben' : letzteMeldung)
          : '$erfolge von $gesamt gesendet. Nicht durchgekommen: '
            '${gescheitert.join(", ")} — $letzteMeldung',
      fehler: !alle,
    );
    if (erfolge > 0) {
      setState(() {
        _dokumente = [];
        if (alle) {
          _empfaenger.clear();
          _name.clear();
          _betreff.clear();
          _nachricht.clear();
          _aktenzeichen.clear();
          _weitereZiele = [];
        }
      });
      // ⚠️ Nur wenn wirklich ALLES durch ist. Ist ein Empfänger ausgefallen,
      // bleibt der Entwurf stehen — sonst müsste man den Text für den zweiten
      // Versuch noch einmal schreiben, und zwar genau dann, wenn es eilt.
      if (alle) await _entwurfVerwerfen();
      await _laden();
    }
  }

  /// Die Empfänger dieser Sendung: die gemerkten plus der, der gerade im Feld
  /// steht.
  ///
  /// ⚠️ Das Feld zählt MIT, ohne dass man es erst „hinzufügen" muss. Der
  /// häufigste Fall ist ein einziger Empfänger; ihn zu einem Extraschritt zu
  /// zwingen, damit die Liste einheitlich ist, wäre eine Regel zugunsten des
  /// Codes.
  ///
  /// ⚠️ Doppelte Nummern fallen raus. Wer eine Nummer merkt und sie dann noch
  /// einmal tippt, will nicht zweimal dasselbe Fax dorthin schicken — und der
  /// Doppel-Schutz auf dem Server würde beim zweiten Mal nachfragen, was wie
  /// ein Fehler aussieht.
  List<FaxZiel> _zieleJetzt() {
    final raus = <FaxZiel>[];
    final gesehen = <String>{};
    void nimm(FaxZiel z) {
      final schluessel = z.nummer.replaceAll(RegExp(r'\D'), '');
      if (schluessel.isEmpty || !gesehen.add(schluessel)) return;
      raus.add(z);
    }
    for (final z in _weitereZiele) {
      nimm(z);
    }
    final feld = _empfaenger.text.trim();
    if (feld.isNotEmpty) nimm(FaxZiel(feld, _name.text.trim()));
    return raus;
  }

  /// Den Empfänger aus dem Feld in die Liste übernehmen und das Feld leeren.
  void _zielMerken() {
    final nr = _empfaenger.text.trim();
    if (nr.isEmpty) { _melde('Keine Nummer im Feld', fehler: true); return; }
    final schluessel = nr.replaceAll(RegExp(r'\D'), '');
    if (_weitereZiele.any((z) => z.nummer.replaceAll(RegExp(r'\D'), '') == schluessel)) {
      _melde('Diese Nummer steht schon in der Liste', fehler: true);
      return;
    }
    setState(() {
      _weitereZiele = [..._weitereZiele, FaxZiel(nr, _name.text.trim())];
      _empfaenger.clear();
      _name.clear();
    });
    _entwurfAnstossen();
  }

  /// Was tun, wenn das Dokument digital gesiegelt ist?
  ///
  /// `true` = Deckblatt als eigenes Fax, `false` = ohne Deckblatt,
  /// `null` = abbrechen.
  Future<bool?> _siegelFrage() => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Dokument ist gesiegelt'),
          content: const Text(
            'Dieses PDF trägt ein digitales Siegel — bei Vollmachten und '
            'Bescheinigungen dieses Vereins ist das der Normalfall.\n\n'
            'Ein Deckblatt davorzusetzen würde das Dokument neu schreiben und '
            'das Siegel zerstören. Es kann stattdessen als eigenes Fax '
            'vorausgeschickt werden; beide gehören dann zu einem Vorgang.',
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Ohne Deckblatt')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Als eigenes Fax')),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  //  Verlauf
  // ---------------------------------------------------------------------------

  /// Der Sendebericht — der eigentliche Nachweis.
  ///
  /// ⚠️ Er ist etwas anderes als der Status in der Liste. Unsere Zeile sagt
  /// „zugestellt", weil sipgate das sagt; der Bericht ist das Dokument dazu
  /// und nennt Absender, Empfänger, Zeitpunkt und Seitenzahl in einer Form,
  /// die man einem Amt, einem Gericht oder der Gegenseite vorlegt. Bei einem
  /// fristgebundenen Widerspruch ist er der Zugangsnachweis — ein Eintrag in
  /// unserer Datenbank ist es nicht.
  ///
  /// ⚠️ Eingegangene Faxe haben keinen: sipgate liefert dort `reportUrl: ""`.
  /// Deshalb entscheidet `hat_bericht` vom Server, ob der Knopf erscheint,
  /// und nicht die Senderichtung — falls sipgate das je ändert, zieht die
  /// Anzeige von allein mit.
  Future<void> _bericht(Map<String, dynamic> f) async {
    final r = await _api.sipgateFaxAction({'action': 'bericht', 'id': f['id']},
        timeout: const Duration(seconds: 60));
    if (r['success'] != true) {
      _melde(r['message']?.toString() ?? 'Sendebericht nicht abrufbar', fehler: true);
      return;
    }
    if (!mounted) return;
    try {
      final bytes = base64Decode(r['inhalt_b64'].toString());
      final name = (r['dateiname'] ?? 'Sendebericht.pdf').toString();
      await FileViewerDialog.showFromBytes(context, bytes, name);
    } catch (e) {
      _melde('Sendebericht ist beschädigt angekommen: $e', fehler: true);
    }
  }

  /// Der erkannte Text, vollständig.
  ///
  /// ⚠️ Wird EIGENS geholt. Bis zum 22.08.2026 ging er in jeder Listenzeile
  /// mit — im Schnitt 2.365 Zeichen je Fax, gut 40 kB für den ganzen Bestand
  /// — und dieser Bildschirm hat ihn kein einziges Mal angefasst. Jetzt steht
  /// in der Zeile ein Anriss, und wer weiterlesen will, fragt danach.
  Future<void> _volltext(Map<String, dynamic> f) async {
    final r = await _api.sipgateFaxAction({'action': 'volltext', 'id': f['id']});
    if (!mounted) return;
    if (r['success'] != true) {
      _melde(r['message']?.toString() ?? 'Text nicht abrufbar', fehler: true);
      return;
    }
    final text = (r['text'] ?? '').toString();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Erkannter Text'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty
                  ? 'Auf diesem Fax wurde kein Text erkannt.'
                  : text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ),
        actions: [
          // ⚠️ Der Hinweis gehört dazu und ist keine Bescheidenheitsfloskel:
          // Texterkennung auf einem Fax liest aus einem 200-dpi-Schwarzweiß-
          // bild. Wer die Zahl in einem Bescheid aus dieser Anzeige abschreibt
          // statt aus dem Dokument, schreibt irgendwann eine falsche ab.
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Text('Maschinell gelesen — verbindlich ist das Dokument.',
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen')),
        ],
      ),
    );
  }

  /// Einen Vorgang an ein Fax hängen — nachträglich.
  ///
  /// 🔴 Das ging bisher gar nicht. `bezug_text` wurde ausschließlich beim
  /// Senden geschrieben; nachgezählt am 22.08.2026 hatten 15 von 17 Faxen
  /// keinen Vorgang, und es gab keinen Weg, einen zu setzen. Ein EINGEGANGENES
  /// Fax konnte per Bauart nie einen haben — und ausgerechnet dort ist
  /// „wozu gehört das?" die erste Frage.
  Future<void> _vorgang(Map<String, dynamic> f) async {
    final c = TextEditingController(text: (f['bezug_text'] ?? '').toString());
    final neu = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Vorgang'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c,
            autofocus: true,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Bezeichnung',
              hintText: 'z. B. Widerspruch Jobcenter 08/2026',
              border: OutlineInputBorder(),
            ),
          ),
          Text(
            'Steht in der Liste und wird bei der Suche mitgelesen. Leer lassen '
            'entfernt den Vorgang.',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(d, c.text.trim()),
              child: const Text('Speichern')),
        ],
      ),
    );
    c.dispose();
    if (neu == null) return;
    final r = await _api.sipgateFaxAction({
      'action': 'bezug_setzen',
      'id': f['id'],
      'bezug_text': neu,
    });
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    if (r['success'] == true) await _laden();
  }

  /// Holt das Dokument vom Server. Gibt `null` zurück und meldet selbst,
  /// wenn es nicht geht.
  ///
  /// ⚠️ Die Bytes bleiben im Speicher und werden NICHT auf die Platte
  /// geschrieben. Auf dem Server liegt jedes Fax verschlüsselt; es hier
  /// nebenbei als Klartext-PDF in den Temp-Ordner zu legen, würde diesen
  /// Schutz aufheben — Temp-Dateien überleben die Sitzung, landen in Backups
  /// und sind auf einem geteilten Rechner für jeden lesbar. Ein Faxverlauf
  /// enthält Widersprüche, Atteste und Behördenpost.
  Future<Uint8List?> _dokumentHolen(Map<String, dynamic> f) async {
    final r = await _api.sipgateFaxAction({'action': 'dokument', 'id': f['id']},
        timeout: const Duration(seconds: 60));
    if (r['success'] != true) {
      _melde(r['message']?.toString() ?? 'Dokument nicht abrufbar', fehler: true);
      return null;
    }
    try {
      return base64Decode(r['inhalt_b64'].toString());
    } catch (e) {
      _melde('Dokument ist beschädigt angekommen: $e', fehler: true);
      return null;
    }
  }

  String _dateinameVon(Map<String, dynamic> f) {
    final n = (f['dateiname'] ?? '').toString().trim();
    return n.isEmpty ? 'Fax-${f['id']}.pdf' : n;
  }

  /// Das Auge: Fax ansehen, ohne dass es je die Platte berührt.
  ///
  /// ⚠️ ÜBER FileViewerDialog, NICHT über PdfPreview.
  ///
  /// Die erste Fassung baute hier einen eigenen Dialog mit `PdfPreview` aus
  /// dem Paket `printing`. Das hat am 19.08.2026 auf Linux Mint die **ganze
  /// App geschlossen**, sofort beim Antippen eines gefaxten Dokuments — ein
  /// Absturz in nativem Code, den kein try/catch in Dart auffangen kann.
  ///
  /// Der Grund ist eine Verwechslung: `PdfPreview` ist keine Anzeige, sondern
  /// die **Druckvorschau**. Sie rastert das Dokument über einen
  /// Plattformkanal, und dieser Weg trägt auf dem Linux-Desktop nicht.
  /// `FileViewerDialog` benutzt `PdfViewer.data()` aus `pdfrx` — einen
  /// echten Betrachter, der an rund zwei Dutzend Stellen dieser App seit
  /// Langem funktioniert.
  Future<void> _ansehen(Map<String, dynamic> f) async {
    final bytes = await _dokumentHolen(f);
    if (bytes == null || !mounted) return;
    // Ansehen heisst gelesen. Ein eigener Knopf dafür wäre eine Pflicht, die
    // niemand erfüllt — und dann leuchtet das Abzeichen für immer.
    if (f['richtung'] == 'ein' && f['gelesen'] != true) {
      unawaited(_alsGelesen(f));
    }
    await FileViewerDialog.showFromBytes(context, bytes, _dateinameVon(f));
  }

  Future<void> _alsGelesen(Map<String, dynamic> f) async {
    final r = await _api.sipgateFaxAction({'action': 'gelesen', 'id': f['id']});
    if (r['success'] != true || !mounted) return;
    setState(() => f['gelesen'] = true);
    FaxBadgeService().aktualisieren();
  }

  Future<void> _alleGelesen() async {
    final r = await _api.sipgateFaxAction({'action': 'gelesen', 'alle': true});
    if (!mounted) return;
    _melde(r['message']?.toString() ?? 'Eingang als gelesen vermerkt',
        fehler: r['success'] != true);
    await _laden();
  }

  /// Herunterladen — der Mensch bestimmt, wohin.
  ///
  /// ⚠️ Bewusst mit Auswahldialog statt still in den Temp-Ordner: das Fax
  /// verlässt hier den verschlüsselten Bereich, und das soll eine Entscheidung
  /// sein, keine Nebenwirkung.
  Future<void> _herunterladen(Map<String, dynamic> f, {Uint8List? vorhandene}) async {
    final bytes = vorhandene ?? await _dokumentHolen(f);
    if (bytes == null) return;
    try {
      final ziel = await FilePickerHelper.saveBytes(
        bytes: bytes,
        fileName: _dateinameVon(f),
        dialogTitle: 'Fax speichern',
      );
      if (ziel != null) _melde('Gespeichert: $ziel');
    } catch (e) {
      _melde('Speichern fehlgeschlagen: $e', fehler: true);
    }
  }

  /// Noch einmal senden — aus dem Dokument, das bei uns liegt.
  ///
  /// ⚠️ Eine besetzte Gegenstelle ist bei Behörden der Normalfall. Bisher
  /// hieß „fehlgeschlagen": das PDF noch einmal heraussuchen — und bei einem
  /// Fax, das aus der Jobcenter-Vollmacht heraus entstanden ist, gibt es die
  /// Datei auf dem Gerät überhaupt nicht.
  Future<void> _erneutSenden(Map<String, dynamic> f) async {
    final nummer = TextEditingController(text: '${f['empfaenger'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Noch einmal senden?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('„${_dateinameVon(f)}" liegt bei uns und wird erneut übertragen — '
              'die Datei muss nicht neu herausgesucht werden.',
              style: const TextStyle(fontSize: 13, height: 1.35)),
          const SizedBox(height: 12),
          TextField(
            controller: nummer,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Faxnummer',
              // Der häufigste Grund für einen zweiten Versuch ist eine falsche
              // Nummer — deshalb steht sie hier zum Ändern, nicht fest.
              helperText: 'Änderbar — der erste Versuch bleibt im Verlauf stehen',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Senden')),
        ],
      ),
    );
    if (ok != true) return;

    final r = await _api.sipgateFaxAction({
      'action': 'senden_erneut',
      'id': f['id'],
      'empfaenger': nummer.text.trim(),
    }, timeout: const Duration(seconds: 90));
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    await _laden();
  }

  /// Holt die Vorschau der ersten Seite — einmal je Fax.
  ///
  /// ⚠️ Ein Fax IST ein Bild. Der Verlauf zeigte nur Text, und der ist bei
  /// einem eingegangenen Fax fast leer: eine Rufnummer und ein von uns selbst
  /// erzeugter Dateiname. Woran man Behördenpost erkennt, ist der Briefkopf —
  /// und der steht auf Seite 1.
  ///
  /// ⚠️ Nach dem Bildaufbau angestoßen, nicht mitten darin: `setState` während
  /// `build` ist verboten, und ein Aufruf ohne diese Verzögerung würde bei
  /// jedem Neuaufbau erneut starten.
  void _miniaturAnfordern(int id) {
    if (_miniaturen.containsKey(id) || _miniaturLaeuft.contains(id)) return;
    _miniaturLaeuft.add(id);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = await _api.sipgateFaxAction({'action': 'miniatur', 'id': id},
          timeout: const Duration(seconds: 30));
      if (!mounted) return;
      Uint8List? bild;
      if (r['success'] == true) {
        try {
          bild = base64Decode(r['inhalt_b64'].toString());
        } catch (_) {
          bild = null;
        }
      }
      setState(() {
        _miniaturen[id] = bild;
        _miniaturLaeuft.remove(id);
      });
    });
  }

  /// Auf ein eingegangenes Fax antworten.
  ///
  /// ⚠️ Füllt nur das Sendefeld — es wird nichts von allein verschickt. Ein
  /// Fax lässt sich nicht zurückholen; ein Knopf, der sofort sendet, wäre an
  /// dieser Stelle eine Falle.
  void _antworten(Map<String, dynamic> f) {
    final nummer = '${f['empfaenger'] ?? ''}';
    if (nummer.isEmpty) {
      _melde('Zu diesem Fax ist keine Absendernummer gespeichert', fehler: true);
      return;
    }
    setState(() {
      _empfaenger.text = nummer;
      final name = '${f['empfaenger_name'] ?? ''}';
      if (name.isNotEmpty) _name.text = name;
      // Betreff nur vorschlagen, wenn das Deckblatt überhaupt an ist — sonst
      // stünde ein Wert in einem Feld, das niemand sieht.
      if (_deckblatt && _betreff.text.trim().isEmpty) {
        _betreff.text = 'Ihr Fax vom ${_datumKurz(f)}';
      }
    });
    // Nach oben, sonst füllt sich ein Formular außerhalb des Blickfelds und
    // es sieht aus, als sei nichts passiert.
    if (_blaettern.hasClients) {
      _blaettern.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    _melde('Empfänger übernommen — Dokument wählen und senden');
  }

  String _datumKurz(Map<String, dynamic> f) {
    final r = '${f['gesendet_am'] ?? f['erstellt_am'] ?? ''}';
    // „2026-08-21 18:22:54" -> „21.08.2026"
    final t = DateTime.tryParse(r);
    if (t == null) return r;
    return '${t.day.toString().padLeft(2, '0')}.'
        '${t.month.toString().padLeft(2, '0')}.${t.year}';
  }

  /// Die eigene Notiz zu einem Fax.
  ///
  /// ⚠️ Unsere, nicht die von sipgate. Deren Verlauf hat auch ein Notizfeld —
  /// und wird nach 30 Tagen gelöscht. Eine Notiz, die genau dann verschwindet,
  /// wenn man sie braucht, ist keine.
  Future<void> _notiz(Map<String, dynamic> f) async {
    final c = TextEditingController(text: '${f['notiz'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Notiz'),
        content: TextField(
          controller: c,
          maxLines: 4,
          maxLength: 1000,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Wozu ging das raus? Was kam zurück?',
            helperText: 'Bleibt bei uns — auch nach den 30 Tagen bei sipgate',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.sipgateFaxAction({
      'action': 'notiz_setzen', 'id': f['id'], 'notiz': c.text.trim(),
    });
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() => f['notiz'] = c.text.trim());
    }
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
  }

  /// Den angezeigten Namen von Hand setzen.
  Future<void> _nameSetzen(Map<String, dynamic> f) async {
    final c = TextEditingController(text: '${f['empfaenger_name'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Gegenstelle benennen'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'z. B. Amtsgericht Neu-Ulm',
            // Sagt, warum der Name danach stehen bleibt.
            helperText: 'Ein eingetragener Name wird nie automatisch ersetzt',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.sipgateFaxAction({
      'action': 'name_setzen', 'id': f['id'], 'name': c.text.trim(),
    });
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    await _laden();
  }

  /// Das Faxjournal — was ein Faxgerät ausdruckt, nur vollständig.
  ///
  /// ⚠️ WOFÜR: bei einem Streit über den Zugang eines fristgebundenen
  /// Schreibens ist das Journal das, was vorgelegt wird. Ein Bildschirmfoto
  /// ist kein Beleg.
  Future<void> _journal() async {
    var mitBerichten = true;
    var richtung = '';
    var siegeln = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, setzen) => AlertDialog(
          title: const Text('Faxjournal erstellen'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Eine Liste aller Sendungen mit Zeitpunkt, Gegenstelle, Seitenzahl '
              'und Ergebnis — als PDF zum Vorlegen.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: richtung,
              decoration: const InputDecoration(
                labelText: 'Umfang', isDense: true, border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: '', child: Text('Alles')),
                DropdownMenuItem(value: 'aus', child: Text('Nur gesendete')),
                DropdownMenuItem(value: 'ein', child: Text('Nur empfangene')),
              ],
              onChanged: (v) => setzen(() => richtung = v ?? ''),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: mitBerichten,
              onChanged: (v) => setzen(() => mitBerichten = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Sendeberichte anhängen'),
              subtitle: const Text(
                'Erst damit ist es ein Nachweis: das Journal ist unsere Angabe, '
                'die Berichte sind die Bestätigung des Netzbetreibers.',
                style: TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
            // ⚠️ Das Siegel läuft NICHT sofort: der Signierschlüssel liegt
            // auf dem Server so, dass der Webserver nicht herankommt — genau
            // deshalb kann ein Einbruch über die Webseite keine Dokumente im
            // Namen des Vereins siegeln. Ein Cron erledigt es innerhalb
            // weniger Minuten; darum steht das auch im Untertitel und nicht
            // erst hinterher in einer Fehlermeldung.
            CheckboxListTile(
              value: siegeln,
              onChanged: (v) => setzen(() => siegeln = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Digital siegeln'),
              subtitle: const Text(
                'Belegt, dass das Dokument von diesem Verein stammt und seither '
                'unverändert ist. Dauert ein paar Minuten — es wird auf dem '
                'Server gesiegelt, nicht hier.',
                style: TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d2, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(d2, true), child: const Text('Erstellen')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    _melde('Journal wird erstellt …');
    final r = await _api.sipgateFaxAction({
      'action': 'journal',
      if (richtung.isNotEmpty) 'richtung': richtung,
      'mit_berichten': mitBerichten,
      if (siegeln) 'siegel': true,
      // Berichte anhängen heißt viele Seiten zusammenfügen — das dauert.
    }, timeout: const Duration(seconds: 120));
    if (!mounted) return;
    if (r['success'] != true) {
      _melde(r['message']?.toString() ?? 'Journal nicht erstellbar', fehler: true);
      return;
    }
    if (siegeln) {
      final auftrag = (r['auftrag_id'] as num?)?.toInt() ?? 0;
      _melde(r['message']?.toString() ?? 'Zum Siegeln vorgemerkt');
      if (auftrag > 0) await _siegelAbholen(auftrag);
      return;
    }
    try {
      final bytes = base64Decode(r['inhalt_b64'].toString());
      _melde(r['message']?.toString() ?? '');
      await FileViewerDialog.showFromBytes(
          context, bytes, (r['dateiname'] ?? 'Faxjournal.pdf').toString());
    } catch (e) {
      _melde('Journal ist beschädigt angekommen: $e', fehler: true);
    }
  }

  /// Ein einzelnes Fax als Mappe: Deckblatt, Dokument und Sendebericht in
  /// EINEM PDF.
  ///
  /// ⚠️ WOFÜR: bis zum 24.08.2026 gab es das nur für den **ganzen** Verlauf.
  /// Wer ein Fax in eine Gerichtsakte legen wollte, lud Dokument und
  /// Sendebericht einzeln herunter — zwei Dateien, die einander nichts
  /// ansehen. Der Zugangsnachweis besteht aber aus beidem zusammen.
  ///
  /// ⚠️ Es ist DIESELBE Maschinerie wie beim Journal, nur mit `id`. Der Server
  /// konnte das längst (`case 'journal'` wertet `id` seit dem 21.08. aus) —
  /// gefragt hat nie jemand danach. Eine zweite Bauart daneben zu stellen
  /// hieße, zwei Wege zu pflegen, die dasselbe belegen sollen.
  Future<void> _mappe(Map<String, dynamic> f) async {
    final id = (f['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    var siegeln = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d2, setz) => AlertDialog(
          title: const Text('Mappe für die Akte'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'Ein PDF mit Deckblatt, dem Dokument und dem Sendebericht — '
              'das, was zusammen den Zugang belegt.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: siegeln,
              onChanged: (v) => setz(() => siegeln = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Digital siegeln'),
              subtitle: const Text(
                'Mit Zeitstempel. Dauert ein paar Minuten, weil ein eigener '
                'Lauf das übernimmt — die Mappe bleibt danach 30 Tage abrufbar.',
                style: TextStyle(fontSize: 12, height: 1.3),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d2, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(d2, true),
                child: const Text('Erstellen')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    _melde('Mappe wird erstellt …');
    final r = await _api.sipgateFaxAction({
      'action': 'journal',
      'id': id,
      // Bei EINEM Fax sind Dokument und Bericht der ganze Zweck — sie werden
      // nicht zur Wahl gestellt. ⚠️ `mit_dokumenten` wertet der Server NUR
      // aus, wenn `id` gesetzt ist: fünfhundert Dokumente an ein Journal zu
      // hängen wäre kein Journal mehr.
      'mit_berichten': true,
      'mit_dokumenten': true,
      if (siegeln) 'siegel': true,
    }, timeout: const Duration(seconds: 120));
    if (!mounted) return;
    if (r['success'] != true) {
      _melde(r['message']?.toString() ?? 'Mappe nicht erstellbar', fehler: true);
      return;
    }
    if (siegeln) {
      final auftrag = (r['auftrag_id'] as num?)?.toInt() ?? 0;
      _melde(r['message']?.toString() ?? 'Zum Siegeln vorgemerkt');
      if (auftrag > 0) await _siegelAbholen(auftrag);
      return;
    }
    try {
      final bytes = base64Decode(r['inhalt_b64'].toString());
      _melde(r['message']?.toString() ?? '');
      await FileViewerDialog.showFromBytes(
          context, bytes, 'Fax-$id-Mappe.pdf');
    } catch (e) {
      _melde('Mappe ist beschädigt angekommen: $e', fehler: true);
    }
  }

  /// Wartet auf das gesiegelte Journal und zeigt es dann.
  ///
  /// ⚠️ Fragt nach, statt zu blockieren: das Siegeln übernimmt der Cron, der
  /// alle fünf Minuten läuft. Ein Fortschrittsbalken, der so lange steht, ist
  /// eine Aufforderung, die App wegzulegen — und dann sieht man das Ergebnis
  /// nie. Deshalb ein Dialog, den man schließen darf: das Journal bleibt
  /// dreissig Tage abrufbar.
  Future<void> _siegelAbholen(int auftrag) async {
    var laeuft = true;
    var stand = 'offen';
    Timer? takt;

    Future<void> fragen(void Function(void Function()) setzen) async {
      final a = await _api.sipgateFaxAction(
          {'action': 'siegel', 'was': 'holen', 'auftrag_id': auftrag});
      if (a['success'] == true) {
        laeuft = false;
        takt?.cancel();
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        try {
          final name = (a['dateiname'] ?? 'Faxjournal.pdf').toString();
          await FileViewerDialog.showFromBytes(
              context, base64Decode(a['inhalt_b64'].toString()), name);
          if (mounted) await _zeitstempelAnbieten(a, name);
        } catch (e) {
          _melde('Gesiegeltes Journal ist beschädigt angekommen: $e', fehler: true);
        }
        return;
      }
      final neu = (a['stand'] ?? 'offen').toString();
      if (neu == 'fehler') {
        laeuft = false;
        takt?.cancel();
        if (mounted) setzen(() => stand = 'fehler');
        return;
      }
      if (mounted) setzen(() => stand = neu);
    }

    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d2, setzen) {
        takt ??= Timer.periodic(const Duration(seconds: 15), (_) {
          if (laeuft) fragen(setzen);
        });
        return AlertDialog(
          title: const Text('Journal wird gesiegelt'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (stand != 'fehler') const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              stand == 'fehler'
                  ? 'Das Siegeln ist fehlgeschlagen. Das Journal lässt sich '
                    'weiterhin ungesiegelt erstellen.'
                  : 'Der Server siegelt im Hintergrund; das dauert bis zu fünf '
                    'Minuten. Dieses Fenster darf geschlossen werden — das '
                    'fertige Journal bleibt dreissig Tage abrufbar.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () { laeuft = false; takt?.cancel(); Navigator.pop(d2); },
                child: const Text('Schließen')),
          ],
        );
      }),
    );
    laeuft = false;
    takt?.cancel();
  }

  /// Der RFC-3161-Zeitstempel zum gesiegelten Journal.
  ///
  /// ⚠️ EIGENE DATEI, und das ist keine Bequemlichkeit: der Stempel gilt über
  /// das FERTIGE Dokument. Er kann per Bauart nicht darin stehen — das
  /// Siegelblatt ist Teil dessen, worüber gestempelt wird. (Und TCPDFs
  /// `setTimeStamp()` ist ohnehin eine leere Hülle; ein Zeitstempel, den man
  /// zu haben glaubt und nicht hat, wäre schlimmer als keiner.)
  ///
  /// ⚠️ Fehlt er, wird das GESAGT und nicht verschwiegen. Das Siegel gilt
  /// trotzdem — nur der Zeitpunkt ist dann unsere eigene Angabe.
  Future<void> _zeitstempelAnbieten(Map<String, dynamic> a, String name) async {
    final b64 = a['tsa_b64'];
    if (b64 == null || b64.toString().isEmpty) {
      _melde('Das Journal ist gesiegelt, aber ohne Zeitstempel — der '
          'Zeitstempeldienst war nicht erreichbar. Der Lauf holt ihn nach.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Zeitstempel sichern'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Zum Journal gehört ein Zeitstempel eines unabhängigen Dienstes '
            '(${a['tsa_quelle'] ?? 'Zeitstempeldienst'}, ${a['tsa_zeit'] ?? ''}). '
            'Er belegt, dass die Datei zu diesem Zeitpunkt genau so vorlag.',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            'Er liegt als eigene Datei vor (.tsr) und gehört zum Journal — '
            'einzeln vorgelegt beweist keiner von beiden, was beide zusammen '
            'beweisen.',
            style: TextStyle(fontSize: 12.5, height: 1.35, color: F.h(Colors.grey, 700)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Später')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final roh = base64Decode(b64.toString());
      final tsName = '${name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')}.tsr';
      final ziel = await FilePickerHelper.saveBytes(
          bytes: Uint8List.fromList(roh), fileName: tsName);
      _melde(ziel != null ? 'Zeitstempel gespeichert' : 'Nicht gespeichert',
          fehler: ziel == null);
    } catch (e) {
      _melde('Zeitstempel liess sich nicht speichern: $e', fehler: true);
    }
  }

  Future<void> _nachsehen(Map<String, dynamic> f) async {
    final r = await _api.sipgateFaxAction({'action': 'stand', 'id': f['id']});
    _melde(r['success'] == true
        ? 'Stand: ${_statusText(r['status']?.toString() ?? '', r['fax_status_type']?.toString())}'
        : (r['message']?.toString() ?? 'Stand nicht abfragbar'), fehler: r['success'] != true);
    await _laden();
  }

  /// Die Löschsperre setzen oder aufheben.
  ///
  /// ⚠️ WOFÜR: nach sechs Jahren entfernt ein Fristlauf auf dem Server den
  /// Inhalt — das Dokument geht, der Nachweis (Empfänger, Zeitpunkt, Seiten,
  /// Ergebnis, Prüfsummen) bleibt. Art. 17 Abs. 3 lit. e DSGVO erlaubt es,
  /// länger aufzubewahren, solange ein Verfahren läuft; nur weiß das niemand,
  /// wenn es nirgends steht. Dieser Schalter ist die Stelle, an der es steht.
  ///
  /// ⚠️ Der Grund ist Pflicht, und zwar serverseitig. In fünf Jahren muss
  /// jemand entscheiden können, ob die Sperre noch gilt — mit „gesperrt" allein
  /// geht das nicht.
  Future<void> _loeschsperre(Map<String, dynamic> f) async {
    final an = f['nicht_loeschen'] != true;
    final grund = TextEditingController();
    final alt = (f['nicht_loeschen_grund'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(an ? 'Nicht löschen?' : 'Sperre aufheben?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            an
                ? 'Nach sechs Jahren entfernt der Server das Dokument und kürzt '
                  'den Sendebericht auf einen Auszug ohne Seitenbild. Empfänger, '
                  'Zeitpunkt, Seitenzahl, Ergebnis und die Prüfsummen bleiben.\n\n'
                  'Mit der Sperre passiert das nicht, solange sie steht — für '
                  'Faxe, zu denen ein Verfahren läuft.'
                : 'Danach gilt wieder die normale Frist: sechs Jahre ab '
                  'Jahresende, dann geht der Inhalt.'
                  '${alt.isEmpty ? '' : '\n\nBisheriger Grund: $alt'}',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          if (an) ...[
            const SizedBox(height: 12),
            TextField(
              controller: grund,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Welches Verfahren?',
                hintText: 'z. B. Klage SG Ulm, S 5 AS 123/26',
                helperText: 'Kommt ins Protokoll',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(an ? 'Sperren' : 'Aufheben')),
        ],
      ),
    );
    final text = grund.text.trim();
    grund.dispose();
    if (ok != true) return;

    final r = await _api.sipgateFaxAction({
      'action': 'loeschsperre',
      'id': f['id'],
      'sperren': an,
      'grund': text,
    });
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    await _laden();
  }

  /// Ein Fax ins Archiv legen — es wird NICHT mehr gelöscht.
  ///
  /// 🔴 Bis zum 23.08.2026 hieß dieser Knopf „Löschen" und tat das auch:
  /// Zeile weg, Dokument weg, Bericht weg, Miniatur weg, endgültig. Nach 30
  /// Tagen hat auch sipgate nichts mehr. Ein Griff, und der Nachweis war fort,
  /// ohne dass irgendwo stand, dass es ihn je gab — bei einem Archiv, das als
  /// Beweismittel dient, die gefährlichste Eigenschaft überhaupt.
  ///
  /// ⚠️ Der Grund ist Pflicht, und zwar serverseitig. Er steht danach im
  /// Protokoll neben Namen und Zeitpunkt. Ohne ihn wäre das Protokoll eine
  /// Liste von Vorgängen, die niemand erklären kann.
  Future<void> _weglegen(Map<String, dynamic> f) async {
    final grund = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ins Archiv legen?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Das Fax verschwindet aus dem Verlauf, bleibt aber vollständig '
            'erhalten — Dokument, Sendebericht und Vorschau. Es ist über den '
            'Filter „Archiv" jederzeit wieder da.\n\n'
            'Gelöscht wird nichts: Faxe sind Nachweise, und ein Archiv, aus '
            'dem sich spurlos etwas entfernen lässt, taugt als Nachweis nicht.\n\n'
            'Von selbst passiert das ohnehin: nach 14 Tagen wandert jedes Fax '
            'automatisch ins Archiv. Hier von Hand wegzulegen lohnt nur, wenn '
            'es jetzt schon aus dem Weg soll — dafür ist der Grund da.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: grund,
            autofocus: true,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Grund',
              hintText: 'z. B. Fehlversuch, Nummer war falsch',
              // ⚠️ Kurz gehalten: neben dem Zeichenzähler bleiben auf 360 dp
              // rund 24 Zeichen, alles darüber schneidet Flutter ab. Beim
              // Rendern gesehen, nicht vermutet.
              helperText: 'Kommt ins Protokoll',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Ins Archiv')),
        ],
      ),
    );
    final text = grund.text.trim();
    grund.dispose();
    if (ok != true) return;
    final r = await _api.sipgateFaxAction(
        {'action': 'loeschen', 'id': f['id'], 'grund': text});
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    if (r['success'] == true) await _laden();
  }

  Future<void> _zurueckholen(Map<String, dynamic> f) async {
    final r = await _api.sipgateFaxAction({'action': 'zurueckholen', 'id': f['id']});
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    if (r['success'] == true) await _laden();
  }

  /// Wer hat wann was mit diesem Fax gemacht — und warum.
  Future<void> _fahrtenbuch(Map<String, dynamic>? f) async {
    final r = await _api.sipgateFaxAction({
      'action': 'protokoll',
      if (f != null) 'id': f['id'],
    });
    if (!mounted) return;
    if (r['success'] != true) {
      _melde(r['message']?.toString() ?? 'Protokoll nicht abrufbar', fehler: true);
      return;
    }
    final eintraege = (r['eintraege'] as List?) ?? const [];
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(f == null ? 'Protokoll' : 'Protokoll zu Fax #${f['id']}'),
        content: SizedBox(
          width: 520,
          child: eintraege.isEmpty
              ? const Text('Keine Einträge.')
              : SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    for (final e in eintraege.whereType<Map>())
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_protokollWort(e['aktion']?.toString() ?? '')}'
                              '${f == null ? ' · Fax #${e['fax_id']}' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text('${e['erstellt_am'] ?? ''} · ${e['wer'] ?? ''}',
                              style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
                          if ('${e['grund'] ?? ''}'.isNotEmpty)
                            Text('${e['grund']}',
                                style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
                        ]),
                      ),
                  ]),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen'))],
      ),
    );
  }

  String _protokollWort(String a) => switch (a) {
        'abgelegt'         => 'Ins Archiv gelegt',
        'zurueckgeholt'    => 'Zurückgeholt',
        'notiz'            => 'Notiz geändert',
        'name'             => 'Gegenstelle umbenannt',
        'vorgang'          => 'Vorgang gesetzt',
        'vorgang_entfernt' => 'Vorgang entfernt',
        _                  => a,
      };

  // ---------------------------------------------------------------------------
  //  Darstellung
  // ---------------------------------------------------------------------------

  /// ⚠️ „gesendet" kommt hier bewusst nicht vor. sipgate bestätigt beim
  /// Absenden nur die Warteschlange; ob das Faxgerät der Gegenseite
  /// abgenommen hat, weiß erst die Nachverfolgung. Ein Wort, das jemand als
  /// Zustellnachweis lesen könnte, darf erst stehen, wenn es einer ist.
  String _statusText(String status, [String? roh]) {
    if (roh == 'UNBEKANNT') return 'Ausgang unbekannt';
    if (roh == 'VERFALLEN') return 'Bei sipgate nicht mehr abfragbar';
    return switch (status) {
      'zugestellt'     => 'Zugestellt',
      'fehlgeschlagen' => 'Fehlgeschlagen',
      'in_zustellung'  => 'In Zustellung …',
      'vorbereitet'    => 'Vorbereitet',
      'storniert'      => 'Storniert',
      'empfangen'      => 'Empfangen',
      _                => status,
    };
  }

  (IconData, Color) _statusZeichen(String status, [String? roh]) {
    if (roh == 'UNBEKANNT' || roh == 'VERFALLEN') return (Icons.help_outline, Colors.orange);
    return switch (status) {
      'zugestellt'     => (Icons.check_circle, Colors.green),
      'fehlgeschlagen' => (Icons.error, Colors.red),
      'in_zustellung'  => (Icons.schedule, Colors.amber),
      'empfangen'      => (Icons.call_received, Colors.blue),
      _                => (Icons.description_outlined, Colors.grey),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.eingebettet) return _koerper();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titel ?? 'Fax'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Faxjournal — Nachweis zum Vorlegen',
            onPressed: _journal,
          ),
          IconButton(
            icon: const Icon(Icons.history_edu_outlined),
            tooltip: 'Protokoll — wer hat wann was geändert',
            onPressed: () => _fahrtenbuch(null),
          ),
          IconButton(
            icon: const Icon(Icons.mark_email_read_outlined),
            tooltip: 'Eingang als gelesen vermerken',
            onPressed: _alleGelesen,
          ),
          IconButton(
            icon: const Icon(Icons.call_received),
            tooltip: 'Eingang von sipgate holen',
            onPressed: () async {
              final r = await _api.sipgateFaxAction({'action': 'eingang'},
                  timeout: const Duration(seconds: 60));
              _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
              await _laden();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu laden',
            onPressed: () => _laden(live: true),
          ),
        ],
      ),
      body: _koerper(),
    );
  }

  /// Der Inhalt ohne Gerüst — so kann derselbe Bildschirm in einem Reiter
  /// stehen (siehe `eingebettet`).
  Widget _koerper() {
    if (_lade) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: () => _laden(live: true),
      child: ListView(
        controller: _blaettern,
        padding: const EdgeInsets.all(16),
        children: [
          // ⚠️ Im Ausschnitt weder Zugangskarte noch Sendefeld: wer aus einer
          // Akte kommt, will die Faxe dazu sehen. Ein Sendefeld mit leerer
          // Empfängernummer wäre dort eine Einladung, versehentlich etwas an
          // niemanden zu schicken — und die Zugangskarte gehört in den
          // Faxbildschirm, nicht in jede Akte.
          if (!widget.gefiltert) ...[
            _zugangsfeld(),
            const SizedBox(height: 16),
            if (_zugang['eingerichtet'] == true) ...[
              _sendefeld(),
              const SizedBox(height: 24),
            ],
          ],
          if (widget.gefiltert)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(Icons.filter_alt_outlined, size: 16, color: F.h(Colors.grey, 700)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.betrifftUserId != null
                        ? 'Nur die Faxe zu diesem Mitglied — der vollständige '
                          'Verlauf steht im Faxbildschirm.'
                        : 'Nur die Faxe zu diesem Vorgang — der vollständige '
                          'Verlauf steht im Faxbildschirm.',
                    style: TextStyle(fontSize: 12.5, color: F.h(Colors.grey, 700)),
                  ),
                ),
              ]),
            ),
          _verlaufsfeld(),
        ],
      ),
    );
  }

  Widget _zugangsfeld() {
    final ein = _zugang['eingerichtet'] == true;
    final live = _zugang['live'];
    final anonym = _zugang['kennung_anonym'] == true;

    if (!ein) {
      return Card(
        color: Colors.orange.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.key_off, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(child: Text('Noch kein Fax-Zugang',
                  style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 8),
            Text(
              (_zugang['hinweis'] ?? 'Fax braucht einen eigenen Personal Access Token.').toString(),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _tokenDialog,
              icon: const Icon(Icons.key),
              label: const Text('Zugang einrichten'),
            ),
          ]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(live == false ? Icons.cloud_off : Icons.cloud_done,
                color: live == false ? Colors.red : Colors.green),
            const SizedBox(width: 10),
            Expanded(child: Text('Faxleitung ${_zugang['faxline_id'] ?? '—'}',
                style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              icon: const Icon(Icons.key, size: 20),
              tooltip: 'Zugang ändern',
              onPressed: _tokenDialog,
            ),
          ]),
          const SizedBox(height: 4),
          _zeile('Absender', (_zugang['absender'] ?? '—').toString()),
          _zeile('Token', (_zugang['token_id'] ?? '—').toString()),
          if (_zugang['geprueft_am'] != null)
            _zeile('Zuletzt geprüft', _zugang['geprueft_am'].toString()),
          // 🔴 DIE EINHEIT WAR DIE FALLE, NICHT DIE ZAHL.
          //
          // sipgate antwortet auf `GET /balance` mit `{"amount": 186378}`.
          // Wer das für Cent hält, liest 1.863,78 € — es sind 18,64 €, ein
          // Hundertstel davon (die Referenzanwendung von sipgate teilt durch
          // 10000). Der Unterschied entscheidet, ob die Zahl überhaupt einen
          // Zweck hat: bei 1.863 € schaut nie wieder jemand hin, bei 18,64 €
          // ist „reicht das noch?" eine echte Frage. Der Server rechnet um;
          // hier steht nur noch der fertige Text.
          if (_zugang['guthaben_text'] != null)
            _zeile('Guthaben', _zugang['guthaben_text'].toString()),
          if (_zugang['guthaben_knapp'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 16, color: F.h(Colors.orange, 800)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Das Guthaben wird knapp. Ist es aufgebraucht, weist sipgate '
                    'die Sendung ab — bei einem fristgebundenen Widerspruch am '
                    'letzten Tag ist das der Unterschied zwischen zugegangen und '
                    'nicht zugegangen.',
                    style: TextStyle(fontSize: 12.5, height: 1.35,
                        color: F.h(Colors.orange, 900)),
                  ),
                ),
              ]),
            ),
          // Wie viele Zeilen noch darauf warten, zu sipgate gespiegelt zu
          // werden. Ein paar sind harmlos — der Cron holt sie alle fünf
          // Minuten. Steht die Zahl über Tage, stimmt etwas nicht.
          if (((_zugang['sync_offen'] as num?)?.toInt() ?? 0) > 5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${_zugang['sync_offen']} Einträge noch nicht zu sipgate '
                'abgeglichen — dort stehen sie bis dahin als ungelesen.',
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)),
              ),
            ),
          if (live == false && (_zugang['live_fehler'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_zugang['live_fehler'].toString(),
                  style: TextStyle(color: F.h(Colors.red, 700), fontSize: 13)),
            ),
          // ⚠️ Ein Fax ohne Absenderkennung gilt bei Ämtern, Gerichten und
          // Praxen im Zweifel als nicht zuordenbar. Der Wert lässt sich im
          // sipgate-Kundencenter mit zwei Klicks zurücksetzen, deshalb wird er
          // bei jeder Live-Prüfung neu gelesen und hier gemeldet.
          if (anonym) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Die Faxleitung sendet ohne Absenderkennung.',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                  'Auf dem Sendebericht des Empfängers steht dann keine Rufnummer. '
                  'Ämter und Gerichte behandeln ein Fax ohne Kennung im Zweifel als '
                  'nicht zuordenbar — bei einer Frist ist das der Unterschied '
                  'zwischen zugegangen und nicht zugegangen.',
                  style: TextStyle(fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _kennungSetzen,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: Text('Nummer ${_zugang['absender'] ?? ''} anzeigen'),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  /// Wie viele Sendungen der Knopf auslöst: Dokumente mal Empfänger.
  ///
  /// ⚠️ Stand hier vorher nur die Zahl der Dokumente, hieße es „2 Faxe senden"
  /// bei zwei Dokumenten an drei Stellen — und es wären sechs. Bei etwas, das
  /// sich nicht zurückholen lässt, muss die Zahl auf dem Knopf die Zahl der
  /// Sendungen sein.
  /// Das Deckblatt ansehen, bevor es rausgeht.
  ///
  /// 🔴 WOFÜR: es ist die einzige Seite, die **wir** erzeugen — und bis zum
  /// 24.08.2026 hat sie niemand je gesehen, bevor sie bei einem Amt oder einem
  /// Gericht ankam. Auf ihr stehen Betreff, Aktenzeichen und die Seitenzahl,
  /// also genau das, woran bei einer Frist die Zuordnung hängt.
  ///
  /// ⚠️ Es wird nichts gesendet und nichts abgelegt — der Server schreibt für
  /// diese Anfrage keine Zeile in den Verlauf.
  Future<void> _deckblattAnsehen() async {
    final ziele = _zieleJetzt();
    // Die Seitenzahl des ERSTEN Dokuments: das Deckblatt geht nur davor.
    final seiten = _dokumente.isEmpty ? 0 : (_dokumente.first.seiten ?? 0);
    _melde('Deckblatt wird erzeugt …');
    final r = await _api.sipgateFaxAction({
      'action': 'deckblatt_probe',
      'empfaenger': ziele.isEmpty ? '' : ziele.first.nummer,
      'empfaenger_name': ziele.isEmpty ? '' : ziele.first.name,
      'betreff': _betreff.text.trim(),
      'nachricht': _nachricht.text,
      'aktenzeichen': _aktenzeichen.text.trim(),
      if (seiten > 0) 'seiten': seiten,
    });
    if (!mounted) return;
    if (r['success'] != true) {
      _melde(r['message']?.toString() ?? 'Deckblatt nicht erzeugbar', fehler: true);
      return;
    }
    try {
      final bytes = base64Decode(r['inhalt_b64'].toString());
      // ⚠️ Die Meldung kommt VOR dem Anzeigen. Sie sagt unter anderem, ob die
      // Nachricht gekürzt wurde — hinter dem Dialog gelesen wäre das zu spät.
      _melde(r['message']?.toString() ?? '');
      await FileViewerDialog.showFromBytes(
          context, bytes, 'Deckblatt-Vorschau.pdf');
    } catch (e) {
      _melde('Vorschau ist beschädigt angekommen: $e', fehler: true);
    }
  }

  int get _sendezahl => _dokumente.length * _zieleJetzt().length;

  Widget _zeile(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: TextStyle(color: F.h(Colors.grey, 600), fontSize: 13))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
        ]),
      );

  /// Ein gewähltes Dokument: erste Seite, Name, Seitenzahl, Größe.
  ///
  /// ⚠️ Die Seitenzahl steht auch dann da, wenn sie unbekannt ist — als
  /// „Seitenzahl unbekannt", nicht als Lücke. Eine fehlende Angabe sieht sonst
  /// aus wie „geprüft und in Ordnung", und genau das ist sie nicht.
  Widget _dokumentZeile(FaxAnhang d) {
    final mb = d.bytes.length / 1048576;
    final groesse = mb >= 0.1
        ? '${mb.toStringAsFixed(1)} MB'
        : '${(d.bytes.length / 1024).round()} kB';
    final seiten = d.seiten == null
        ? 'Seitenzahl unbekannt'
        : '${d.seiten} ${d.seiten == 1 ? 'Seite' : 'Seiten'}';
    // Knapp unter der Grenze ist kein Fehler, aber der Moment, in dem ein
    // Hinweis noch etwas nützt.
    final knapp = d.seiten != null && d.seiten! > kFaxMaxSeiten - 5;

    // ⚠️ MergeSemantics ist hier richtig und in `_faxZeile` FALSCH: diese
    // Zeile enthält nichts Bedienbares, die Verlaufszeile dagegen ein
    // Menü. Zusammengefasst wäre der Menüknopf nicht mehr einzeln
    // anwählbar — aus einer Verbesserung würde eine Sperre.
    return MergeSemantics(
      child: Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Das Papierbild sagt einem Bildschirmleser nichts, was nicht daneben
        // stünde — Name, Seitenzahl und Größe stehen als Text.
        ExcludeSemantics(child: Container(
          width: 40,
          height: 54,
          decoration: BoxDecoration(
            border: Border.all(color: F.h(Colors.grey, 400)),
            borderRadius: BorderRadius.circular(3),
            color: F.h(Colors.grey, 100),
          ),
          clipBehavior: Clip.antiAlias,
          child: d.vorschau != null
              ? Image.memory(d.vorschau!, fit: BoxFit.cover)
              : Icon(Icons.picture_as_pdf_outlined,
                  size: 20, color: F.h(Colors.grey, 500)),
        )),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('$seiten · $groesse',
                style: TextStyle(
                    fontSize: 12,
                    color: knapp ? F.h(Colors.orange, 800) : F.h(Colors.grey, 700))),
            if (knapp)
              Text('sipgate faxt höchstens $kFaxMaxSeiten Seiten je Sendung.',
                  style: TextStyle(fontSize: 11.5, color: F.h(Colors.orange, 800))),
          ]),
        ),
      ]),
      ),
    );
  }

  Widget _sendefeld() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Fax senden', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _empfaenger,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Faxnummer des Empfängers',
                  // ⚠️ Ohne Vorwahl ist nicht entscheidbar, welches Land
                  // gemeint ist — der Server weist solche Nummern ab.
                  //
                  // ⚠️ Als Beispiel stand hier die Faxnummer des Vereins.
                  // Kein Geheimnis — sie steht im Impressum —, aber im Feld
                  // „Faxnummer des EMPFÄNGERS" liest sie sich wie eine
                  // Vorgabe und lädt dazu ein, sich selbst zu faxen.
                  helperText: 'Mit Vorwahl, z. B. 030 12345678',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.contacts),
              // ⚠️ Führt zum FAX-Verzeichnis, nicht zum Telefonverzeichnis.
              // Letzteres schließt Faxspalten aus und konnte deshalb nur
              // Sprachnummern liefern — in ein Faxfeld.
              tooltip: 'Aus dem Faxverzeichnis wählen',
              onPressed: () async {
                final ziele = await Navigator.of(context).push<List<FaxZiel>>(
                    MaterialPageRoute(builder: (_) => const FaxNummerWaehlenScreen()));
                if (ziele == null || ziele.isEmpty) return;
                setState(() {
                  // Das erste kommt ins Feld, alle weiteren in die Liste —
                  // dieselbe Aufteilung, die `_zieleJetzt()` beim Senden
                  // wieder zusammenführt.
                  _empfaenger.text = ziele.first.nummer;
                  // Den Namen gleich mit: sonst steht im Verlauf später nur
                  // eine Rufnummer, und die sagt in einem Jahr nichts mehr.
                  if (_name.text.trim().isEmpty) _name.text = ziele.first.name;
                  if (ziele.length > 1) {
                    // ⚠️ Ziffernvergleich, nicht Textvergleich: „+49 731 …"
                    // und „0731 …" sind dieselbe Gegenstelle. Ohne das stünde
                    // sie zweimal in der Liste und bekäme zwei Faxe.
                    String k(String n) => n.replaceAll(RegExp(r'\D'), '');
                    final da = {
                      for (final z in _weitereZiele) k(z.nummer),
                      k(ziele.first.nummer),
                    };
                    _weitereZiele = [
                      ..._weitereZiele,
                      for (final z in ziele.skip(1))
                        if (k(z.nummer).isNotEmpty && da.add(k(z.nummer))) z,
                    ];
                  }
                });
                _entwurfAnstossen();
              },
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Empfänger (für den Verlauf)',
              hintText: 'z. B. Amtsgericht Neu-Ulm',
              border: OutlineInputBorder(),
            ),
          ),
          // --- weitere Empfänger ------------------------------------------
          //
          // 🔴 Bis zum 22.08.2026 ging ein Fax an genau eine Nummer. Dieselbe
          // Mitteilung an Jobcenter UND Familienkasse hieß: alles zweimal
          // tippen, die Dokumente zweimal auswählen — und wer dazwischen
          // unterbrochen wird, hat die Hälfte verschickt und weiß es nicht.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _zielMerken,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Weiteren Empfänger hinzufügen'),
            ),
          ),
          if (_weitereZiele.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  for (final z in _weitereZiele)
                    InputChip(
                      label: Text(z.name.isEmpty ? z.nummer : z.name,
                          style: const TextStyle(fontSize: 12.5)),
                      // Der Name allein ist zu wenig: zwei Stellen können
                      // denselben Namen tragen, und gefaxt wird die Nummer.
                      tooltip: z.name.isEmpty ? null : '${z.name} · ${z.nummer}',
                      avatar: const Icon(Icons.print_outlined, size: 16),
                      onDeleted: () {
                        setState(() => _weitereZiele =
                            _weitereZiele.where((x) => x != z).toList());
                        _entwurfAnstossen();
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          if (_entwurfOhneDokument && _dokumente.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 16, color: F.h(Colors.blue, 700)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Empfänger und Text stammen aus dem gemerkten Entwurf. '
                    'Das PDF war nicht dabei — Entwürfe merken sich keine '
                    'Dokumente. Bitte neu wählen.',
                    style: TextStyle(fontSize: 12, height: 1.3,
                        color: F.h(Colors.blue, 800)),
                  ),
                ),
              ]),
            ),
          OutlinedButton.icon(
            onPressed: _sichtetDokumente ? null : _dokumenteWaehlen,
            icon: _sichtetDokumente
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            label: Text(_sichtetDokumente
                ? 'Dokument wird durchgesehen …'
                : _dokumente.isEmpty
                    ? 'PDF wählen'
                    : _dokumente.length == 1
                        ? _dokumente.first.name
                        : '${_dokumente.length} Dokumente'),
          ),
          // ⚠️ WAS HIER STEHT, HAT BIS ZUM 24.08.2026 GEFEHLT: der Bildschirm
          // hat nie gezeigt, was das Haus verlässt. Gewählt wurde eine Datei,
          // geprüft wurde ihr %PDF--Kopf, und weg war sie. Ein Scan mit 40
          // Seiten ging ohne ein Wort ans Jobcenter.
          if (_dokumente.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final d in _dokumente) _dokumentZeile(d),
                if (_dokumente.length > 1) ...[
                  const SizedBox(height: 4),
                  Text('Gehen als eigene Faxe nacheinander — ein Vorgang, '
                      'je ein Sendebericht.',
                      style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
                ],
              ]),
            ),
          const SizedBox(height: 4),
          // --- Deckblatt ---------------------------------------------------
          CheckboxListTile(
            value: _deckblatt,
            onChanged: (v) => setState(() => _deckblatt = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Deckblatt voranstellen'),
            subtitle: const Text(
              'Absender, Empfänger, Betreff und Seitenzahl auf einem Blatt — '
              'bei Ämtern und Gerichten das, was die Zuordnung sichert.',
              style: TextStyle(fontSize: 12, height: 1.3),
            ),
          ),
          if (_deckblatt) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _betreff,
              decoration: const InputDecoration(
                labelText: 'Betreff', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _aktenzeichen,
              decoration: const InputDecoration(
                labelText: 'Aktenzeichen (optional)',
                border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nachricht,
              maxLines: 4,
              maxLength: 900,
              decoration: const InputDecoration(
                labelText: 'Nachricht (optional)',
                // ⚠️ Die Grenze ist keine Schikane: das Deckblatt muss
                // einseitig bleiben, sonst stimmt die Seitenzahl darauf nicht
                // mehr — und die ist bei einem fristgebundenen Schriftsatz
                // genau das, worauf es ankommt.
                helperText: 'Passt auf ein Blatt; längerer Text wird gekürzt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _deckblattAnsehen,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Deckblatt ansehen'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_sendet || _sichtetDokumente) ? null : _senden,
              icon: _sendet
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_sendet
                  ? 'Wird übertragen …'
                  : _sendezahl > 1
                      ? '$_sendezahl Faxe senden'
                      : 'Fax senden'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _verlaufsfeld() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Verlauf', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Text('$_gefunden', style: TextStyle(color: F.h(Colors.grey, 600))),
      ]),
      const SizedBox(height: 4),
      // ⚠️ Der Satz steht da, damit niemand den Verlauf für den von sipgate
      // hält und ihn dort sucht, wenn er nach fünf Wochen leer ist.
      Text('Liegt bei uns — sipgate löscht seinen Verlauf nach 30 Tagen.',
          style: TextStyle(color: F.h(Colors.grey, 600), fontSize: 12)),
      const SizedBox(height: 10),
      TextField(
        controller: _suche,
        onChanged: (_) => _neuFiltern(),
        decoration: InputDecoration(
          hintText: 'Suchen — Name, Nummer, Dateiname',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _suche.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Suche leeren',
                  icon: const Icon(Icons.clear),
                  onPressed: () { _suche.clear(); _laden(); },
                ),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _filterChip('', 'Alle'),
          _filterChip('offen', 'Offen'),
          _filterChip('fehler', 'Fehlgeschlagen'),
          _filterChip('zugestellt', 'Zugestellt'),
          _filterChip('ungelesen', 'Neu im Eingang'),
          // ⚠️ Sichtbar und nicht versteckt: sonst waere das Weglegen doch
          // wieder ein Verschwinden, nur mit mehr Schritten.
          _filterChip('archiv', 'Archiv'),
        ]),
      ),
      const SizedBox(height: 8),
      if (_faxe.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(child: Text(
            _suche.text.trim().isEmpty && _stand.isEmpty
                ? 'Noch kein Fax'
                : 'Nichts gefunden',
            style: TextStyle(color: F.h(Colors.grey, 600)),
          )),
        )
      else ...[
        ..._verlaufsZeilen(),
        if (_mehrDa)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: _mehrLaedt
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : OutlinedButton.icon(
                      onPressed: _mehrLaden,
                      icon: const Icon(Icons.expand_more),
                      label: Text('Mehr laden (${_faxe.length} von $_gefunden)'),
                    ),
            ),
          ),
      ],
    ]);
  }

  /// Der Verlauf mit Tagesüberschriften.
  ///
  /// ⚠️ WOFÜR: bis zum 24.08.2026 waren es fünfzig gleich aussehende Zeilen.
  /// Bei einer laufenden Frist ist die erste Frage „ist es heute rausgegangen?",
  /// und die wurde beantwortet, indem man Zeitstempel Zeile für Zeile las.
  ///
  /// ⚠️ Die Überschrift wechselt nur, wenn sie sich ändert. Beim Nachladen
  /// wächst die Liste unten an; weil hier bei jedem Aufbau neu gruppiert wird,
  /// steht über der ersten nachgeladenen Zeile keine zweite gleiche Überschrift.
  List<Widget> _verlaufsZeilen() {
    final raus = <Widget>[];
    final jetzt = DateTime.now();
    var letzte = '';
    for (final f in _faxe) {
      final roh = '${f['gesendet_am'] ?? f['erstellt_am'] ?? ''}';
      final t = DateTime.tryParse(roh);
      // Ohne lesbares Datum keine Überschrift — lieber gar keine als eine
      // erfundene. Die Zeile selbst kommt trotzdem.
      final gruppe = t == null ? '' : faxTagesgruppe(t, jetzt);
      if (gruppe.isNotEmpty && gruppe != letzte) {
        letzte = gruppe;
        raus.add(Padding(
          padding: EdgeInsets.only(top: raus.isEmpty ? 2 : 12, bottom: 2),
          child: Text(
            gruppe,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: F.h(Colors.grey, 700),
            ),
          ),
        ));
      }
      raus.add(_faxZeile(f));
    }
    return raus;
  }

  Widget _filterChip(String wert, String text) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(text),
          selected: _stand == wert,
          onSelected: (_) {
            setState(() => _stand = wert);
            _laden();
          },
        ),
      );

  /// Das Bild links: die erste Seite, wenn es sie gibt — sonst das Statuszeichen.
  ///
  /// ⚠️ Das Statuszeichen bleibt IMMER sichtbar, als kleine Marke auf dem Bild.
  /// Es trägt die einzige Information, die man in einer Liste wirklich braucht
  /// („ist es angekommen?"); die Vorschau sagt nur, worum es geht. Sie darf
  /// das Zeichen also ergänzen, nicht ersetzen.
  Widget _vorschau(Map<String, dynamic> f, IconData ikone, Color farbe, bool hatDokument) {
    final id = (f['id'] as num?)?.toInt() ?? 0;
    if (hatDokument && id > 0) _miniaturAnfordern(id);
    final bild = _miniaturen[id];

    if (bild == null) {
      // Kein Bild (noch nicht da, oder es gibt keins) — wie bisher.
      //
      // ⚠️ AUS DER VORLESE-AUSGABE GENOMMEN. Das Zeichen trägt den Status,
      // und der steht als Wort im Untertitel („Zugestellt · …"). Ein Icon
      // ohne Beschriftung liest ein Bildschirmleser ohnehin nicht vor; mit
      // Beschriftung käme dieselbe Auskunft zweimal. Farbe und Form sind hier
      // die Abkürzung fürs Auge, nicht die einzige Quelle — genau das verlangt
      // WCAG 1.4.1.
      return ExcludeSemantics(child: Icon(ikone, color: farbe));
    }
    return Semantics(
      image: true,
      label: 'Vorschau der ersten Seite',
      child: ExcludeSemantics(
        child: SizedBox(
      width: 40,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              // Weißer Grund: ein Fax ist Papier, und ein durchscheinendes
              // JPEG auf dunklem Untergrund liest sich wie ein Negativ.
              color: Colors.white,
              width: 40,
              height: 52,
              child: Image.memory(bild, fit: BoxFit.cover, alignment: Alignment.topCenter,
                  gaplessPlayback: true),
            ),
          ),
          Positioned(
            left: -4,
            bottom: -4,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(1),
              child: Icon(ikone, color: farbe, size: 16),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _faxZeile(Map<String, dynamic> f) {
    final status = (f['status'] ?? '').toString();
    final roh = f['fax_status_type']?.toString();
    final (ikone, farbe) = _statusZeichen(status, roh);
    final ein = f['richtung'] == 'ein';
    // ⚠️ 'gegenstelle', nicht 'empfaenger'. Die Spalte hiess bis zum
    // 22.08.2026 'empfaenger' und trug bei EINGEGANGENEN Faxen die Nummer des
    // ABSENDERS — ein Feld in beide Richtungen. Der Rückfall auf den alten
    // Schlüssel bleibt, solange der Server beide liefert; er verschwindet mit
    // der übernächsten Fassung.
    final name = (f['gegenstelle_name'] ?? f['empfaenger_name'] ?? '').toString();
    final nummer = (f['gegenstelle'] ?? f['empfaenger'] ?? '').toString();
    final gesendetVon = (f['gesendet_von'] ?? '').toString();
    final nachgetragen = (f['herkunft'] ?? 'app') == 'abgleich';
    final fehler = (f['fehler'] ?? '').toString();
    final bezugText = (f['bezug_text'] ?? '').toString();
    final notiz = (f['notiz'] ?? '').toString();
    // Der Anfang des erkannten Textes. Der ganze Text kommt erst auf Verlangen
    // — siehe `_volltext`.
    final ocrAuszug = (f['ocr_auszug'] ?? '').toString();
    final ocrZeichen = (f['ocr_zeichen'] as num?)?.toInt() ?? 0;
    final gruppeVon = (f['gruppe_von'] as num?)?.toInt() ?? 0;
    final gruppePos = (f['gruppe_pos'] as num?)?.toInt() ?? 0;
    final wiederholung = f['wiederholung_von'];
    // Der Server sagt, ob die Datei noch da ist. Ohne das zeigten Auge und
    // Download auf ein Dokument, das es nicht mehr gibt.
    final hatDokument = f['hat_dokument'] == true;
    // ⚠️ Vom Server, nicht aus der Richtung abgeleitet: eingegangene Faxe
    // haben heute keinen Bericht (sipgate liefert `reportUrl: ""`), aber das
    // ist deren Entscheidung und kann sich ändern.
    final hatBericht = f['hat_bericht'] == true;
    final ungelesen = ein && f['gelesen'] != true;
    // Weggelegt heisst nicht geloescht — die Zeile taucht nur unter dem Filter
    // „Archiv" auf, und dort bekommt sie andere Menuepunkte.
    final imArchiv = (f['abgelegt_am'] ?? '').toString().isNotEmpty;
    // ⚠️ Der Unterschied gehört auf den Schirm. Seit dem 29.08.2026 räumt ein
    // Lauf nach 14 Tagen von selbst auf — ohne diese Unterscheidung sähe eine
    // Entscheidung eines Menschen (die eine Begründung trägt) genauso aus wie
    // eine abgelaufene Frist (die keine hat), und man müsste jedes Mal ins
    // Protokoll schauen, um zu wissen, welche von beidem es war.
    final archivAuto = imArchiv && f['abgelegt_art'] == 'auto';
    // Nach Ablauf der Aufbewahrungsfrist entfernt der Server das Dokument und
    // kürzt den Sendebericht auf einen Auszug. `hat_dokument` wird dadurch von
    // selbst falsch, die Knöpfe verschwinden also ohne Zutun — aber ohne einen
    // Hinweis sähe das aus, als sei etwas verloren gegangen. Genau der
    // Unterschied, den ein Nachweisarchiv benennen muss.
    final inhaltWeg = (f['inhalt_geloescht_am'] ?? '').toString().isNotEmpty;
    final gesperrt = f['nicht_loeschen'] == true;
    // Ob das Dokument, das rausging, ein Siegel trug. Zusammen mit der
    // Prüfsumme ist das die Aussage „was gesendet wurde, war das gesiegelte
    // Dokument, unverändert" — bei einer Vollmacht genau die Frage, die
    // hinterher gestellt wird.
    final gesiegelt = f['signiert'] == true;
    // Um wen es geht — etwas anderes als „wer hat gesendet". Bis zum
    // 23.08.2026 stand beides in derselben Spalte, und drei Module schrieben
    // dort das Mitglied: der Verlauf hätte „gesendet von <Mitglied>" gezeigt.
    final betrifft = (f['betrifft_name'] ?? '').toString();
    // ⚠️ Gemessene Breite, nicht Plattform: die App läuft auch auf einem
    // Android-Tablet, wo `isMobile` wahr wäre, obwohl reichlich Platz ist.
    final schmal = MediaQuery.sizeOf(context).width < 420;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      // Ungelesenes hebt sich ab — aber nicht allein durch Farbe: der Titel
      // wird zusätzlich fett, und im Untertitel steht „Neu".
      color: ungelesen
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07)
          : null,
      child: ListTile(
        leading: _vorschau(f, ikone, farbe, hatDokument),
        title: Row(children: [
          Flexible(
            child: Text(
              name.isNotEmpty ? name : (nummer.isNotEmpty ? nummer : '—'),
              // ⚠️ Gedeckelt, und zwar auf dem Bild nachgemessen: ohne das
              // brach „Jobcenter Alb-Donau (Ulm)" auf einem 360-dp-Telefon in
              // DREI Zeilen um, die Karte wurde doppelt so hoch und die
              // Gruppenmarke rutschte hinter den Umbruch. Zwei Zeilen fassen
              // die realen Namen aus den Stammdaten; was länger ist, endet
              // sichtbar mit „…" statt die Liste auseinanderzuziehen.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: ungelesen ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          if (gruppeVon > 1) ...[
            const SizedBox(width: 6),
            // Sagt, dass dieses Fax Teil einer Sendung ist. Ohne das stünden
            // vier unverbundene Zeilen da, und niemand wüsste, dass sie
            // zusammengehören.
            Tooltip(
              message: 'Teil einer Sendung aus $gruppeVon Faxen',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: F.h(Colors.grey, 500)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$gruppePos/$gruppeVon',
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${ein ? 'Empfangen von' : 'An'} $nummer'
              '${f['seiten'] != null ? ' · ${f['seiten']} S.' : ''}'
              '${f['deckblatt'] == true ? ' · mit Deckblatt' : ''}'),
          Text('${ungelesen ? 'Neu · ' : ''}'
              '${_statusText(status, roh)} · '
              '${(f['gesendet_am'] ?? f['erstellt_am'] ?? '').toString()}'
              // ⚠️ Der Verein hat ZWEI Vorsitzende. „Wer hat es geschickt?"
              // ist bei einer Frist die erste Rückfrage, und die Antwort lag
              // in der Datenbank, ohne je angezeigt zu werden.
              '${gesendetVon.isNotEmpty ? ' · von $gesendetVon' : ''}',
              style: TextStyle(color: farbe, fontSize: 12)),
          // ⚠️ MUSS DASTEHEN. Nach Ablauf der Frist fehlt das Dokument, und
          // die Knöpfe dafür verschwinden von selbst — was von außen genauso
          // aussieht wie ein Datenverlust. Ein Nachweisarchiv, das nicht sagt,
          // warum etwas fehlt, sät genau den Zweifel, den es ausräumen soll.
          if (inhaltWeg)
            Row(children: [
              Icon(Icons.auto_delete_outlined, size: 12, color: F.h(Colors.grey, 700)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                    'Aufbewahrungsfrist abgelaufen — Dokument entfernt. '
                    'Empfänger, Zeitpunkt, Seitenzahl, Ergebnis und die '
                    'Prüfsummen bleiben; der Sendebericht liegt als Auszug vor.',
                    style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
              ),
            ]),
          // Eine Sperre ist eine Aussage über ein laufendes Verfahren. Sie
          // gehört sichtbar an die Zeile — sonst fällt in fünf Jahren
          // niemandem auf, dass sie noch steht.
          if (gesperrt)
            Row(children: [
              Icon(Icons.gavel_outlined, size: 12, color: F.h(Colors.indigo, 700)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                    'Nicht löschen — Verfahren läuft'
                    '${(f['nicht_loeschen_grund'] ?? '').toString().isEmpty ? '' : ': ${f['nicht_loeschen_grund']}'}',
                    style: TextStyle(fontSize: 11.5, color: F.h(Colors.indigo, 700))),
              ),
            ]),
          // ⚠️ Ein nachgetragenes Fax ist NICHT dasselbe wie eines aus
          // unserem Sendeweg: wir wissen davon nur, was sipgate erzählt —
          // kein Anlass, kein Bezug, keine Notiz. Das muss man ihm ansehen,
          // sonst gilt ein rekonstruierter Beleg als vollwertiger.
          if (nachgetragen)
            Row(children: [
              Icon(Icons.restore, size: 12, color: F.h(Colors.orange, 800)),
              const SizedBox(width: 4),
              Flexible(
                child: Text('Nachgetragen aus dem sipgate-Verlauf — ging an '
                    'unserem Sendeweg vorbei',
                    style: TextStyle(fontSize: 11.5, color: F.h(Colors.orange, 800))),
              ),
            ]),
          // Zu welchem Vorgang gehört das Fax? Sechs Endpunkte schreiben in
          // denselben Verlauf; ohne diese Zeile beantwortet er ein Jahr später
          // die Frage „ist die Vollmacht je rausgegangen?" nicht mehr.
          // ⚠️ Nur wenn nicht ohnehin nach diesem Mitglied gefiltert wird —
          // in der Akte des Mitglieds wäre die Zeile auf jedem Eintrag
          // dieselbe und damit nur Lärm.
          if (betrifft.isNotEmpty && widget.betrifftUserId == null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Icon(Icons.person_outline, size: 12, color: F.h(Colors.grey, 600)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('Betrifft $betrifft',
                      style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700)),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          if (gesiegelt)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Icon(Icons.verified_outlined, size: 12, color: F.h(Colors.green, 700)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('Gesiegeltes Dokument',
                      style: TextStyle(fontSize: 11.5, color: F.h(Colors.green, 800))),
                ),
              ]),
            ),
          if (bezugText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Icon(Icons.link, size: 12, color: F.h(Colors.grey, 600)),
                const SizedBox(width: 4),
                Flexible(child: Text(bezugText,
                    style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700)),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ),
          if (wiederholung != null)
            Text('Zweiter Versuch zu Fax #$wiederholung',
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
          // Die eigene Notiz. Sie steht bewusst UNTER dem Status: sie sagt,
          // warum das Fax rausging — nicht, ob es ankam.
          if (notiz.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.sticky_note_2_outlined, size: 12, color: F.h(Colors.grey, 600)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(notiz,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: F.h(Colors.grey, 800))),
                ),
              ]),
            ),
          // 🔴 DER ERKANNTE TEXT WAR DA UND WURDE NIE GEZEIGT.
          //
          // Er wird seit Wochen erkannt, gespeichert und durchsucht — nur zu
          // sehen war er nirgends. Bei einem EINGEGANGENEN Fax ist er das
          // Einzige, was etwas über den Inhalt sagt: Rufnummer und Dateiname
          // stammen von uns selbst, nicht vom Absender. Ohne diese zwei Zeilen
          // musste man jedes Fax öffnen, um zu wissen, worum es geht.
          if (ocrAuszug.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: InkWell(
                onTap: () => _volltext(f),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.text_snippet_outlined, size: 12, color: F.h(Colors.grey, 600)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      ocrAuszug,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, height: 1.3, color: F.h(Colors.grey, 700)),
                    ),
                  ),
                ]),
              ),
            ),
          if (fehler.isNotEmpty)
            Text(fehler, style: TextStyle(color: F.h(Colors.red, 700), fontSize: 12)),
        ]),
        isThreeLine: true,
        // ⚠️ Das Auge steht IMMER offen, der Rest nur, wo Platz ist.
        //
        // Ansehen und Herunterladen sind die beiden Dinge, die man mit einem
        // Fax tatsächlich tut — sie hinter zwei Tipps zu verstecken macht aus
        // dem Verlauf eine Liste, die man nur betrachten kann. Aber drei
        // Knöpfe belegen rund 144 dp; auf einem 360-dp-Telefon bliebe für
        // „Amtsgericht Neu-Ulm" und die Statuszeile zu wenig übrig, und
        // ListTile kürzt dann den Text statt die Knöpfe.
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (hatDokument)
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Ansehen — bleibt im Speicher, wird nicht abgelegt',
              onPressed: () => _ansehen(f),
            ),
          if (hatBericht && !schmal)
            IconButton(
              icon: const Icon(Icons.fact_check_outlined),
              tooltip: 'Sendebericht — Nachweis über Zustellung',
              onPressed: () => _bericht(f),
            ),
          if (hatDokument && !schmal)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Herunterladen',
              onPressed: () => _herunterladen(f),
            ),
          PopupMenuButton<String>(
            onSelected: (w) => switch (w) {
              'bericht'  => _bericht(f),
              'laden'    => _herunterladen(f),
              'erneut'   => _erneutSenden(f),
              'antwort'  => _antworten(f),
              'notiz'    => _notiz(f),
              'vorgang'  => _vorgang(f),
              'volltext' => _volltext(f),
              'name'     => _nameSetzen(f),
              'gelesen'  => _alsGelesen(f),
              'stand'    => _nachsehen(f),
              'weglegen'    => _weglegen(f),
              'zurueckholen'=> _zurueckholen(f),
              'sperre'      => _loeschsperre(f),
              'mappe'       => _mappe(f),
              'protokoll'   => _fahrtenbuch(f),
              _          => null,
            },
            itemBuilder: (c) => [
              if (hatBericht && schmal)
                const PopupMenuItem(value: 'bericht',
                    child: ListTile(leading: Icon(Icons.fact_check_outlined), title: Text('Sendebericht'))),
              if (hatDokument && schmal)
                const PopupMenuItem(value: 'laden',
                    child: ListTile(leading: Icon(Icons.download_outlined), title: Text('Herunterladen'))),
              // ⚠️ Nur für ausgehende Faxe mit Dokument: ein eingegangenes
              // „erneut zu senden" schickte es an den Absender zurück, und
              // ohne Dokument gäbe es nichts zu senden. Der Server lehnt
              // beides ab — der Knopf soll gar nicht erst erscheinen.
              if (!ein && hatDokument)
                const PopupMenuItem(value: 'erneut',
                    child: ListTile(leading: Icon(Icons.send_outlined), title: Text('Noch einmal senden'))),
              // ⚠️ Nur beim Eingang. „Antworten" auf ein Fax, das wir selbst
              // geschickt haben, hiesse an uns selbst zu faxen.
              if (ein)
                const PopupMenuItem(value: 'antwort',
                    child: ListTile(leading: Icon(Icons.reply), title: Text('Antworten'))),
              PopupMenuItem(value: 'notiz',
                  child: ListTile(
                      leading: const Icon(Icons.sticky_note_2_outlined),
                      title: Text(notiz.isEmpty ? 'Notiz hinzufügen' : 'Notiz ändern'))),
              PopupMenuItem(value: 'vorgang',
                  child: ListTile(
                      leading: const Icon(Icons.link),
                      title: Text(bezugText.isEmpty ? 'Vorgang zuordnen' : 'Vorgang ändern'))),
              // ⚠️ Nur, wenn wirklich Text erkannt wurde. Ein Menüpunkt, der
              // verlässlich „nichts erkannt" antwortet, ist einer, den man
              // einmal probiert und danach nie wieder.
              if (ocrZeichen > 0)
                PopupMenuItem(value: 'volltext',
                    child: ListTile(
                        leading: const Icon(Icons.text_snippet_outlined),
                        title: const Text('Erkannten Text lesen'),
                        subtitle: Text('$ocrZeichen Zeichen',
                            style: const TextStyle(fontSize: 11)))),
              // Eine Gegenstelle, die weder sipgate noch unsere Stammdaten
              // kennen, bleibt sonst für immer eine nackte Rufnummer.
              const PopupMenuItem(value: 'name',
                  child: ListTile(leading: Icon(Icons.badge_outlined), title: Text('Gegenstelle benennen'))),
              if (ungelesen)
                const PopupMenuItem(value: 'gelesen',
                    child: ListTile(leading: Icon(Icons.mark_email_read_outlined), title: Text('Als gelesen'))),
              // ⚠️ Kein eigener „Drucken"-Punkt: der Betrachter hinter dem
              // Auge hat ihn schon, und zwar auf dem Weg, der auf allen
              // Plattformen erprobt ist. Eine zweite Druckstrecke hier wäre
              // dieselbe Doppelung, die zum Absturz geführt hat.
              if (!ein && (f['session_id'] != null || status == 'in_zustellung'))
                const PopupMenuItem(value: 'stand',
                    child: ListTile(leading: Icon(Icons.refresh), title: Text('Stand nachsehen'))),
              const PopupMenuItem(value: 'mappe',
                  child: ListTile(
                      leading: Icon(Icons.folder_zip_outlined),
                      title: Text('Mappe für die Akte'))),
              const PopupMenuItem(value: 'protokoll',
                  child: ListTile(leading: Icon(Icons.history_edu_outlined),
                      title: Text('Protokoll'))),
              if (imArchiv)
                PopupMenuItem(
                    value: 'zurueckholen',
                    child: ListTile(
                        leading: const Icon(Icons.unarchive_outlined),
                        title: const Text('Zurück in den Verlauf'),
                        // ⚠️ Beim automatisch Weggelegten muss dabeistehen,
                        // dass es wiederkommt — sonst holt jemand es hervor,
                        // findet es zwei Wochen später erneut im Archiv und
                        // hält den Knopf für kaputt.
                        subtitle: archivAuto
                            ? const Text('kommt nach 14 Tagen von selbst zurück ins Archiv',
                                style: TextStyle(fontSize: 11))
                            : null)),
              if (!imArchiv)
                const PopupMenuItem(value: 'weglegen',
                    child: ListTile(leading: Icon(Icons.archive_outlined),
                        title: Text('Ins Archiv legen'))),
              // ⚠️ Nur solange es noch etwas zu schützen gibt. Auf einem
              // bereits gelöschten Inhalt wäre die Sperre eine Zusage, die
              // niemand mehr einlösen kann — der Server lehnt sie dort auch ab.
              if (!inhaltWeg)
                PopupMenuItem(
                    value: 'sperre',
                    child: ListTile(
                        leading: Icon(gesperrt ? Icons.lock_open_outlined : Icons.gavel_outlined),
                        title: Text(gesperrt
                            ? 'Löschsperre aufheben'
                            : 'Nicht löschen — Verfahren läuft'),
                        subtitle: Text(
                            gesperrt
                                ? 'danach gilt wieder die normale Frist'
                                : 'hält die Aufbewahrungsfrist an',
                            style: const TextStyle(fontSize: 11)))),
            ],
          ),
        ]),
      ),
    );
  }
}
