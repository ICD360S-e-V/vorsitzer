import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/fax_badge_service.dart';
import '../utils/file_picker_helper.dart';
import '../widgets/file_viewer_dialog.dart';
import 'fax_nummer_waehlen_screen.dart';
import '../utils/app_farben.dart';

/// Ein Dokument, das mitgefaxt werden soll.
class FaxAnhang {
  final String name;
  final List<int> bytes;
  const FaxAnhang(this.name, this.bytes);
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
  const SipgateFaxScreen({super.key});

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
  bool _sendet = false;
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

  /// Damit das Sendefeld sichtbar wird, wenn „Antworten" es füllt.
  final ScrollController _blaettern = ScrollController();

  @override
  void initState() {
    super.initState();
    _laden(live: true);
  }

  @override
  void dispose() {
    _sucheEntprellen?.cancel();
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

  Map<String, dynamic> _listenAnfrage(int offset) => {
        'action': 'list',
        'limit': _seitenGroesse,
        'offset': offset,
        if (_suche.text.trim().isNotEmpty) 'suche': _suche.text.trim(),
        if (_stand.isNotEmpty) 'stand': _stand,
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
      gewaehlt.add(FaxAnhang(datei.name, gelesen));
    }

    setState(() => _dokumente = gewaehlt);
  }

  /// Ein einzelnes Dokument abschicken. Gibt die Antwort zurück.
  Future<Map<String, dynamic>> _einesSenden(
    FaxAnhang anhang, {
    required bool mitDeckblatt,
    bool deckblattSeparat = false,
    String gruppe = '',
    int pos = 0,
    int von = 0,
  }) {
    return _api.sipgateFaxAction({
      'action': 'senden',
      'empfaenger': _empfaenger.text.trim(),
      'empfaenger_name': _name.text.trim(),
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

  Future<void> _senden() async {
    if (_dokumente.isEmpty) { _melde('Kein Dokument gewählt', fehler: true); return; }
    if (_empfaenger.text.trim().isEmpty) { _melde('Keine Empfängernummer', fehler: true); return; }

    final mehrere = _dokumente.length > 1;
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(mehrere ? '${_dokumente.length} Faxe jetzt senden?' : 'Fax jetzt senden?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('An: ${_empfaenger.text.trim()}'),
          const SizedBox(height: 6),
          for (final d in _dokumente) Text('• ${d.name}', style: const TextStyle(fontSize: 13)),
          if (mehrere) ...[
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
          const SizedBox(height: 8),
          const Text('Ein gesendetes Fax lässt sich nicht zurückholen.',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Senden')),
        ],
      ),
    );
    if (bestaetigt != true) return;

    setState(() => _sendet = true);
    var separat = false;
    var erfolge = 0;
    String letzteMeldung = '';
    // ⚠️ Der Gruppenschlüssel kommt vom SERVER, nicht von hier: er soll für
    // alle Teile derselbe sein, und die erste Antwort liefert ihn. Selbst
    // einen zu würfeln hieße, dem Server ein Format vorzuschreiben, das er
    // nicht prüft.
    var gruppe = '';

    for (var i = 0; i < _dokumente.length; i++) {
      var r = await _einesSenden(
        _dokumente[i],
        // ⚠️ Das Deckblatt gehört nur an das ERSTE Fax. An jedes zu hängen
        // hieße, dem Empfänger dieselbe Ankündigung viermal zu schicken.
        mitDeckblatt: _deckblatt && i == 0,
        deckblattSeparat: separat,
        gruppe: gruppe,
        pos: mehrere ? i + 1 : 0,
        von: mehrere ? _dokumente.length : 0,
      );

      // ⚠️ Das gesiegelte Dokument: der Server lehnt das Zusammenfügen ab und
      // sagt WARUM (`grund: signiert`). Erst hier wird gefragt, statt in einer
      // Sackgasse zu enden — und die Antwort gilt dann für den ganzen Vorgang.
      if (r['success'] != true && '${r['grund'] ?? ''}' == 'signiert') {
        if (!mounted) break;
        final weiter = await _siegelFrage();
        if (weiter == null) { letzteMeldung = 'Abgebrochen'; break; }
        if (weiter) {
          separat = true;
          r = await _einesSenden(_dokumente[i],
              mitDeckblatt: true, deckblattSeparat: true,
              gruppe: gruppe, pos: mehrere ? i + 1 : 0, von: mehrere ? _dokumente.length : 0);
        } else {
          setState(() => _deckblatt = false);
          r = await _einesSenden(_dokumente[i],
              mitDeckblatt: false,
              gruppe: gruppe, pos: mehrere ? i + 1 : 0, von: mehrere ? _dokumente.length : 0);
        }
      }

      letzteMeldung = r['message']?.toString() ?? '';
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

    if (!mounted) return;
    setState(() => _sendet = false);

    final alle = erfolge == _dokumente.length;
    _melde(
      alle
          ? (mehrere ? '$erfolge Faxe an sipgate übergeben' : letzteMeldung)
          : 'Nach $erfolge von ${_dokumente.length} abgebrochen: $letzteMeldung',
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
        }
      });
      await _laden();
    }
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
      // Berichte anhängen heißt viele Seiten zusammenfügen — das dauert.
    }, timeout: const Duration(seconds: 120));
    if (!mounted) return;
    if (r['success'] != true) {
      _melde(r['message']?.toString() ?? 'Journal nicht erstellbar', fehler: true);
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

  Future<void> _nachsehen(Map<String, dynamic> f) async {
    final r = await _api.sipgateFaxAction({'action': 'stand', 'id': f['id']});
    _melde(r['success'] == true
        ? 'Stand: ${_statusText(r['status']?.toString() ?? '', r['fax_status_type']?.toString())}'
        : (r['message']?.toString() ?? 'Stand nicht abfragbar'), fehler: r['success'] != true);
    await _laden();
  }

  Future<void> _loeschen(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Fax löschen?'),
        // ⚠️ Der Hinweis ist keine Floskel: bei sipgate ist das Dokument nach
        // 30 Tagen ohnehin weg, unsere Kopie ist die einzige, die bleibt.
        content: const Text('Das Dokument wird auch von unserem Server gelöscht. '
            'sipgate hält seinen Verlauf nur 30 Tage — danach gibt es keine zweite Kopie.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.sipgateFaxAction({'action': 'loeschen', 'id': f['id']});
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    await _laden();
  }

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fax'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Faxjournal — Nachweis zum Vorlegen',
            onPressed: _journal,
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
      body: _lade
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _laden(live: true),
              child: ListView(
                controller: _blaettern,
                padding: const EdgeInsets.all(16),
                children: [
                  _zugangsfeld(),
                  const SizedBox(height: 16),
                  if (_zugang['eingerichtet'] == true) ...[
                    _sendefeld(),
                    const SizedBox(height: 24),
                  ],
                  _verlaufsfeld(),
                ],
              ),
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

  Widget _zeile(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: TextStyle(color: F.h(Colors.grey, 600), fontSize: 13))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
        ]),
      );

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
                final ziel = await Navigator.of(context).push<FaxZiel>(
                    MaterialPageRoute(builder: (_) => const FaxNummerWaehlenScreen()));
                if (ziel == null) return;
                setState(() {
                  _empfaenger.text = ziel.nummer;
                  // Den Namen gleich mit: sonst steht im Verlauf später nur
                  // eine Rufnummer, und die sagt in einem Jahr nichts mehr.
                  if (_name.text.trim().isEmpty) _name.text = ziel.name;
                });
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _dokumenteWaehlen,
            icon: const Icon(Icons.attach_file),
            label: Text(_dokumente.isEmpty
                ? 'PDF wählen'
                : _dokumente.length == 1
                    ? _dokumente.first.name
                    : '${_dokumente.length} Dokumente'),
          ),
          if (_dokumente.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final d in _dokumente)
                  Text('• ${d.name}',
                      style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
                const SizedBox(height: 4),
                Text('Gehen als eigene Faxe nacheinander — ein Vorgang, '
                    'je ein Sendebericht.',
                    style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
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
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sendet ? null : _senden,
              icon: _sendet
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_sendet
                  ? 'Wird übertragen …'
                  : _dokumente.length > 1
                      ? '${_dokumente.length} Faxe senden'
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
        ..._faxe.map(_faxZeile),
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
      return Icon(ikone, color: farbe);
    }
    return SizedBox(
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
    );
  }

  Widget _faxZeile(Map<String, dynamic> f) {
    final status = (f['status'] ?? '').toString();
    final roh = f['fax_status_type']?.toString();
    final (ikone, farbe) = _statusZeichen(status, roh);
    final ein = f['richtung'] == 'ein';
    final name = (f['empfaenger_name'] ?? '').toString();
    final nummer = (f['empfaenger'] ?? '').toString();
    final fehler = (f['fehler'] ?? '').toString();
    final bezugText = (f['bezug_text'] ?? '').toString();
    final notiz = (f['notiz'] ?? '').toString();
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
              '${(f['gesendet_am'] ?? f['erstellt_am'] ?? '').toString()}',
              style: TextStyle(color: farbe, fontSize: 12)),
          // Zu welchem Vorgang gehört das Fax? Sechs Endpunkte schreiben in
          // denselben Verlauf; ohne diese Zeile beantwortet er ein Jahr später
          // die Frage „ist die Vollmacht je rausgegangen?" nicht mehr.
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
              'name'     => _nameSetzen(f),
              'gelesen'  => _alsGelesen(f),
              'stand'    => _nachsehen(f),
              'loeschen' => _loeschen(f),
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
              const PopupMenuItem(value: 'loeschen',
                  child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Löschen'))),
            ],
          ),
        ]),
      ),
    );
  }
}
