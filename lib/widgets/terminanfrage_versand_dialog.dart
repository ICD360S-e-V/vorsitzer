import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/ticket_service.dart';
import '../utils/terminanfrage_pdf.dart';
import '../utils/terminanfrage_vorlagen.dart';

/// Der Versanddialog hinter dem Anfrage-Knopf — für alle Ärzte-Tabs derselbe.
///
/// WAS SICH ÄNDERT
/// Vorher war der Knopf ein Notizzettel: man kreuzte an, WIE man die Anfrage
/// gestellt hatte (telefonisch, online, postalisch), erzeugte einen Text und
/// kopierte ihn von Hand in ein Mailprogramm. Der Weg nach draußen fand
/// außerhalb der App statt, und ob er stattfand, wusste niemand.
///
/// Jetzt geht die Anfrage von hier aus raus — als E-Mail (Text) oder als Fax
/// (PDF), beides aus derselben Quelle ([terminanfrageText]).
///
/// 🔴 ANGEBOTEN WIRD NUR, WAS DIE PRAXIS AUCH HAT.
/// Kein Knopf, der beim Drücken sagt „geht nicht": hat der Arzt keine
/// Faxnummer hinterlegt, ist der Faxknopf aus — und darunter steht, warum,
/// samt Hinweis, wo man die Nummer nachträgt. Ein toter Knopf ohne Grund ist
/// schlimmer als kein Knopf: man drückt ihn wieder und wieder.
///
/// ⚠️ EIN EINZIGER DIALOG FÜR ALLE TABS, mit Absicht. Die alte Fassung lag in
/// sechs Dateien als Kopie; eine Textkorrektur musste sechsmal gemacht werden,
/// und dass sie sechsmal gemacht wurde, hat nie jemand geprüft.
///
/// ⚠️ DER DIALOG SPEICHERT NICHTS SELBST. Die Tabs legen ihre Termine sehr
/// unterschiedlich ab (`saveArztTermin` bei 21 Tabs, `sanitaetshausAction` beim
/// Sanitätshaus), und ein Dialog, der beide Wege kennt, kennt bald auch den
/// dritten. Er meldet über [onGesendet], was rausgegangen ist; ablegen tut es
/// der Tab.
///
/// ⚠️ GEMELDET WIRD NUR ERFOLG. Bei einem Fehlschlag wird [onGesendet] NICHT
/// gerufen — eine Akte, in der ein Versand steht, der nie stattfand, ist
/// schlimmer als eine, in der er fehlt: auf die erste verlässt sich jemand.
/// Dieselbe Regel wie beim Vollmachtversand.

/// Was rausgegangen ist — für die Ablage im jeweiligen Tab.
class TerminanfrageErgebnis {
  /// `email` oder `fax` — passt zu `anfrage_methode` in der Terminliste.
  final String methode;
  final TerminanfrageVorlage vorlage;
  final String betreff;

  /// Der versandte Text (bei Fax der Text, aus dem das PDF gebaut wurde).
  final String text;

  /// Wohin es ging: Mailadresse oder Faxnummer.
  final String empfaenger;

  /// Nur beim Fax: die sipgate-Sitzung, unter der sich die Zustellung
  /// nachverfolgen lässt.
  ///
  /// ⚠️ „an sipgate übergeben" ist NICHT „zugestellt". Wer das verwechselt,
  /// schreibt in die Akte eine Zustellung, die vielleicht nie stattfand.
  final String sitzungId;

  const TerminanfrageErgebnis({
    required this.methode,
    required this.vorlage,
    required this.betreff,
    required this.text,
    required this.empfaenger,
    this.sitzungId = '',
  });
}

/// Baut die Briefdaten aus dem, was der Tab ohnehin hat.
///
/// ⚠️ [krankenkasse] und [verein] holt der Dialog selbst nach — der Tab muss
/// dafür nichts vorbereiten. Sonst müsste jeder der 22 Tabs dieselben zwei
/// Abfragen kennen, und der erste, der sie vergisst, verschickt einen Brief
/// ohne Versichertennummer, ohne dass etwas fehlschlägt.
TerminanfrageDaten terminanfrageDatenBauen({
  required String arztTyp,
  required User user,
  required Map<String, dynamic> arzt,
  required List<Map<String, dynamic>> termine,
}) {
  final (anzahl, letzter) = terminanfrageHistorie(termine);

  // ⚠️ `user.name` ist der VOLLE Name. Ein naives `user.nachname ?? user.name`
  // ergibt bei fehlendem Nachnamen „Ionut" + „Ionut Duinea" = „Ionut Ionut
  // Duinea" — und zwar auf einem Dokument, das später als Nachweis dienen
  // soll. Dieselbe Klasse Fehler wie das verschluckte `ț`. Fällt der Nachname
  // aus, trägt `name` allein den ganzen Namen und der Vorname bleibt leer.
  final nachname = (user.nachname ?? '').trim();
  final vorname = nachname.isEmpty ? '' : (user.vorname ?? '').trim();

  return TerminanfrageDaten(
    arztTyp: arztTyp,
    vorname: vorname,
    nachname: nachname.isEmpty ? user.name.trim() : nachname,
    geburtsdatum: _alsDeutschesDatum(user.geburtsdatum ?? ''),
    strasse: [user.strasse, user.hausnummer]
        .where((e) => (e ?? '').isNotEmpty)
        .join(' '),
    plz: user.plz ?? '',
    ort: user.ort ?? '',
    praxisName: arzt['praxis_name']?.toString() ?? '',
    arztName: arzt['arzt_name']?.toString() ?? '',
    praxisStrasse: arzt['strasse']?.toString() ?? '',
    praxisPlzOrt: arzt['plz_ort']?.toString() ?? '',
    praxisEmail: arzt['email']?.toString() ?? '',
    praxisFax: arzt['fax']?.toString() ?? '',
    userId: user.id,
    erfassteTermine: anzahl,
    letzterTermin: letzter,
  );
}

/// `2026-08-20` → `20.08.2026`. Alles andere bleibt, wie es ist.
///
/// ⚠️ Kein `DateFormat` mit fester Länge: in `users.geburtsdatum` steht bei
/// manchen Mitgliedern bereits deutsches Format, bei anderen ISO. Ein blindes
/// Umformatieren machte aus `14.03.1985` schnell `03.14.1985`.
String _alsDeutschesDatum(String roh) {
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(roh);
  if (iso == null) return roh;
  return '${iso.group(3)}.${iso.group(2)}.${iso.group(1)}';
}

/// Legt eine versandte Anfrage ab: Terminzeile, Korrespondenzeintrag, Ticket.
///
/// 🔴 [speichern] MUSS die Speicherfunktion DIESES Tabs sein.
/// Die fünf entkoppelten Tabs schreiben in eigene Tabellen und haben je eine
/// eigene Funktion (`saveHnoTermin`, `saveAugenarztTermin`, …); nur die
/// sechzehn gemeinsamen nehmen `saveArztTermin`. Der erste Anlauf rief überall
/// `saveArztTermin` — es kompiliert, die Methode gibt es ja, und `flutter
/// analyze` schweigt. Die Wirkung wäre gewesen: das Fax geht raus, die Meldung
/// sagt „übergeben", und der Termin landet in der falschen Tabelle — im Tab
/// erscheint er NIE. Deshalb wird die Funktion hier hereingereicht und nicht
/// erraten.
///
/// ⚠️ Der Korrespondenzeintrag entsteht in einem ZWEITEN Aufruf (`update` mit
/// `korrespondenz`, ohne `datum`). Die entkoppelten Endpunkte nehmen ihn zwar
/// schon beim `add` entgegen, `gesundheit_termine_save.php` aber NICHT —
/// nachgesehen am 21.08.2026: dort kennt nur der `update`-Zweig das Feld. Ein
/// gemeinsamer Weg ist eine Anfrage mehr und dafür überall derselbe.
///
/// ⚠️ Schlägt der zweite Aufruf fehl, bleibt der Termin ohne Korrespondenz —
/// das ist der harmlose Ausgang. Andersherum stünde eine Korrespondenz ohne
/// Termin in der Akte.
Future<void> terminanfrageAblegen({
  required TicketService ticketService,
  required User user,
  required String arztTyp,
  required String arztTitel,
  required Map<String, dynamic> arzt,
  required TerminanfrageErgebnis ergebnis,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>) speichern,
}) async {
  final heute = DateTime.now();
  final datum = '${heute.year}-${heute.month.toString().padLeft(2, '0')}-'
      '${heute.day.toString().padLeft(2, '0')}';
  final arztOrt = [
    if ((arzt['praxis_name']?.toString() ?? '').isNotEmpty) arzt['praxis_name'],
    if ((arzt['arzt_name']?.toString() ?? '').isNotEmpty) arzt['arzt_name'],
    if ((arzt['strasse']?.toString() ?? '').isNotEmpty) arzt['strasse'],
    if ((arzt['plz_ort']?.toString() ?? '').isNotEmpty) arzt['plz_ort'],
  ].join(', ');

  // ⚠️ `datum` ist der Tag des VERSANDS, nicht der Termin — den kennt zu
  // diesem Zeitpunkt niemand, die Praxis muss ihn erst nennen. Genau dafür
  // gibt es `typ: anfrage`.
  final notiz = [
    'Vorlage: ${ergebnis.vorlage.titel}',
    'Gesendet an: ${ergebnis.empfaenger}',
    // ⚠️ Die Sitzungsnummer ist der einzige Faden zum Sendebericht: sipgate
    // löscht seinen Verlauf nach 30 Tagen.
    if (ergebnis.sitzungId.isNotEmpty) 'sipgate-Sitzung: ${ergebnis.sitzungId}',
  ].join('\n');

  int? terminId;
  try {
    final res = await speichern({
      'action': 'add',
      'user_id': user.id,
      'arzt_type': arztTyp,
      'datum': datum,
      'typ': 'anfrage',
      'anfrage_methode': ergebnis.methode,
      'diagnose': ergebnis.betreff,
      'notizen': notiz,
      'arzt_ort': arztOrt,
    });
    // `jsonResponse` mischt die Nutzlast in die Wurzel — die neue Id liegt
    // direkt unter `id`, nicht unter `data`.
    if (res['success'] == true) terminId = int.tryParse('${res['id'] ?? ''}');
  } catch (err) {
    debugPrint('[Terminanfrage] Termin ablegen: $err');
  }

  // Der versandte Text landet als ausgehende Korrespondenz am Termin — dort
  // sucht ihn jeder, der später fragt „was haben wir denen eigentlich
  // geschrieben?".
  if (terminId != null) {
    try {
      await speichern({
        'action': 'update',
        'user_id': user.id,
        'arzt_type': arztTyp,
        'termin_id': terminId,
        'korrespondenz': [
          {
            'datum': datum,
            'art': ergebnis.methode,
            'richtung': 'ausgehend',
            'betreff': ergebnis.betreff,
            'inhalt': ergebnis.text,
          }
        ],
      });
    } catch (err) {
      debugPrint('[Terminanfrage] Korrespondenz ablegen: $err');
    }
  }

  try {
    final praxis = arzt['praxis_name']?.toString() ??
        arzt['arzt_name']?.toString() ??
        arztTitel;
    await ticketService.createTicket(
      mitgliedernummer: user.mitgliedernummer,
      subject: 'Arzt-Anfrage: $arztTitel \u2014 ${user.name}',
      message: [
        'Arzt: $praxis ($arztTitel)',
        'Patient: ${user.name} (${user.mitgliedernummer})',
        'Versandt am: $datum per '
            '${ergebnis.methode == 'fax' ? 'Fax' : 'E-Mail'}',
        'An: ${ergebnis.empfaenger}',
        if (ergebnis.sitzungId.isNotEmpty)
          'sipgate-Sitzung: ${ergebnis.sitzungId}',
        '',
        ergebnis.betreff,
      ].join('\n'),
      priority: 'medium',
      systemTicket: true,
      scheduledDate: datum,
    );
  } catch (err) {
    debugPrint('[Terminanfrage] Ticket create error: $err');
  }
}

/// Öffnet den Versanddialog. Gibt `true` zurück, wenn etwas rausgegangen ist.
Future<bool> zeigeTerminanfrageVersand(
  BuildContext context, {
  required ApiService api,
  required String arztTitel,
  required TerminanfrageDaten basis,
  required Future<void> Function(TerminanfrageErgebnis) onGesendet,
}) async {
  final ergebnis = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TerminanfrageDialog(
      api: api,
      arztTitel: arztTitel,
      basis: basis,
      onGesendet: onGesendet,
    ),
  );
  return ergebnis ?? false;
}

class _TerminanfrageDialog extends StatefulWidget {
  final ApiService api;
  final String arztTitel;
  final TerminanfrageDaten basis;
  final Future<void> Function(TerminanfrageErgebnis) onGesendet;

  const _TerminanfrageDialog({
    required this.api,
    required this.arztTitel,
    required this.basis,
    required this.onGesendet,
  });

  @override
  State<_TerminanfrageDialog> createState() => _TerminanfrageDialogState();
}

class _TerminanfrageDialogState extends State<_TerminanfrageDialog> {
  late TerminanfrageVorlage _vorlage;

  /// Über welchen Weg es rausgeht: `email` oder `fax`. Leer = keiner möglich.
  ///
  /// 🔴 DER KANAL WIRD VORHER GEWÄHLT, NICHT ERST BEIM DRÜCKEN.
  /// Vorher gab es zwei Sendeknöpfe und eine Vorschau, die zu keinem von
  /// beiden gehörte: sie baute den Text mit dem Platzhalter `vorschau`, und
  /// weil der weder `fax` noch `email` ist, standen BEIDE Rückwege darin —
  /// „per E-Mail an … oder per Fax an … oder telefonisch …". Verschickt wurde
  /// dann etwas anderes: die Mail nannte nur die Mailadresse, das Fax nur die
  /// Faxnummer. Ein Kasten mit der Überschrift „So geht es raus", der etwas
  /// anderes zeigt als das, was rausgeht, ist schlimmer als gar keine
  /// Vorschau — man liest ihn ja gerade, um sich zu vergewissern.
  String _kanal = '';

  final Set<String> _anlaesse = {};
  final _freitext = TextEditingController();
  bool _beleg = false;
  bool _begleitung = true;
  bool _laedt = true;
  bool _sendet = false;
  String _fehler = '';

  /// Nachgeladen: Versichertennummer und die Rückwege des Vereins.
  String _kkName = '';
  String _kkNummer = '';
  String _vereinName = '';
  String _vereinMail = '';
  String _vereinFax = '';
  String _vereinTel = '';

  /// Die Mailsignatur, wie sie auch das Verfassen-Fenster anhängt.
  ///
  /// 🔴 SIE KOMMT NICHT VON SELBST. Im ersten Anlauf stand hier der Kommentar
  /// „ohne Signatur — die hängt `api/mail/send.php` an". Das war schlicht
  /// falsch, nachgesehen am 21.08.2026: `send.php` reicht `body` unverändert
  /// an die Mail-API weiter, und angehängt wird die Signatur vom CLIENT, in
  /// `mail_compose_screen.dart` über `signature.php`. Wer wie hier direkt
  /// `sendMail()` ruft, umgeht sie — der Arzt bekam eine Mail ohne Absender-
  /// block, ohne Verein, ohne Impressum.
  ///
  /// ⚠️ Die Signatur beginnt mit `-- ` und enthält KEINE Grußformel (siehe
  /// `mailBuildSignature()`), deshalb bleibt „Mit freundlichen Grüßen" im
  /// Brieftext stehen und die Signatur kommt darunter.
  String _signatur = '';

  ArztFach get _fach => arztFachFuer(widget.basis.arztTyp);

  @override
  void initState() {
    super.initState();
    _vorlage = vorgewaehlteVorlage(widget.basis.erfassteTermine);
    // E-Mail zuerst, wenn beides geht: sie kostet nichts, kommt sofort an und
    // die Antwort landet lesbar im Postfach statt als Bild im Faxeingang.
    _kanal = _mailMoeglich ? 'email' : (_faxMoeglich ? 'fax' : '');
    _nachladen();
  }

  @override
  void dispose() {
    _freitext.dispose();
    super.dispose();
  }

  /// ⚠️ Beide Abfragen dürfen scheitern, ohne dass der Dialog scheitert. Ohne
  /// Versichertennummer ist der Brief schlechter, aber immer noch ein Brief —
  /// und ein Dialog, der wegen einer Nebenabfrage gar nicht aufgeht, kostet
  /// den Termin ganz.
  Future<void> _nachladen() async {
    try {
      final kk = await widget.api.getBehoerdeData(_userId, 'krankenkasse');
      if (kk['success'] == true && kk['data'] != null) {
        final d = Map<String, dynamic>.from(kk['data']);
        _kkName = d['name']?.toString() ?? '';
        _kkNummer = d['versichertennummer']?.toString() ?? '';
      }
    } catch (_) {}
    try {
      final v = await widget.api.getVereineinstellungen();
      if (v['success'] == true && v['data'] != null) {
        final d = Map<String, dynamic>.from(v['data']);
        _vereinName = d['vereinsname']?.toString() ?? '';
        _vereinMail = d['email']?.toString() ?? '';
        _vereinFax = d['fax']?.toString() ?? '';
        _vereinTel = d['telefon_fix']?.toString() ?? '';
      }
    } catch (_) {}
    try {
      final sig = await widget.api.getMailSignature();
      if (sig['success'] == true) _signatur = (sig['signature'] ?? '').toString();
    } catch (_) {}
    if (mounted) setState(() => _laedt = false);
  }

  int get _userId => widget.basis.userId;

  // ── Kanäle ─────────────────────────────────────────────────────────

  String get _arztMail => widget.basis.praxisEmail.trim();
  String get _arztFax => widget.basis.praxisFax.trim();

  bool get _mailMoeglich => _arztMail.contains('@') && _arztMail.length > 4;

  /// ⚠️ sipgate verlangt eine vollständige Nummer MIT Vorwahl und lehnt sonst
  /// ab — erst nachdem der Mensch gewartet hat. Deshalb wird hier gezählt,
  /// bevor der Knopf überhaupt angeht: unter sechs Ziffern ist es keine
  /// Faxnummer, sondern ein Durchwahlrest.
  bool get _faxMoeglich =>
      _arztFax.replaceAll(RegExp(r'[^0-9]'), '').length >= 6;

  /// Die Daten, wie sie im Moment in den Brief gehen.
  ///
  /// ⚠️ Der Rückweg wird PRO KANAL gesetzt: in einem Fax die Faxnummer zu
  /// nennen und die Mailadresse wegzulassen ist kein Detail — die Praxis
  /// antwortet auf dem Weg, den sie zuerst liest, und der Verein soll die
  /// Antwort dort bekommen, wo er sie auch sucht.
  TerminanfrageDaten _daten(String kanal) {
    final b = widget.basis;
    return TerminanfrageDaten(
      arztTyp: b.arztTyp,
      vorname: b.vorname,
      nachname: b.nachname,
      geburtsdatum: b.geburtsdatum,
      strasse: b.strasse,
      plz: b.plz,
      ort: b.ort,
      krankenkasse: _kkName,
      versichertennummer: _kkNummer,
      praxisName: b.praxisName,
      arztName: b.arztName,
      praxisStrasse: b.praxisStrasse,
      praxisPlzOrt: b.praxisPlzOrt,
      praxisEmail: b.praxisEmail,
      praxisFax: b.praxisFax,
      userId: b.userId,
      anlaesse: _anlaesse.toList(),
      anliegen: _freitext.text,
      ueberweisungLiegtVor: _beleg,
      begleitung: _begleitung,
      erfassteTermine: b.erfassteTermine,
      letzterTermin: b.letzterTermin,
      // ⚠️ POSITIV formuliert: genannt wird NUR der gewählte Weg.
      // Vorher stand hier `kanal == 'fax' ? '' : _vereinMail` — eine
      // Ausschluss-Logik, die bei jedem dritten Wert (und sei es der
      // Platzhalter `vorschau`) BEIDE Wege durchließ. Genau daran ist die
      // Vorschau zur Lüge geworden. Mit dieser Form kann das nicht mehr
      // passieren: was nicht ausdrücklich gewählt ist, bleibt leer.
      rueckantwortEmail: kanal == 'email' ? _vereinMail : '',
      rueckantwortFax: kanal == 'fax' ? _vereinFax : '',
      rueckantwortTelefon: _vereinTel,
      vereinsname: _vereinName,
    );
  }

  // ── Senden ─────────────────────────────────────────────────────────

  /// Der Mailtext, wie er wirklich rausgeht — Brief plus Signatur.
  ///
  /// ⚠️ EINE Stelle, weil derselbe Text zweimal gebraucht wird: einmal zum
  /// Senden und einmal für die Korrespondenzzeile. Zwei Aufbauten liefen
  /// auseinander, und in der Akte stünde etwas anderes als beim Empfänger.
  String _mailText(TerminanfrageDaten d, TerminanfrageText t) {
    final brief = t.alsMailText(d, stimme: TerminanfrageStimme.wir);
    return _signatur.trim().isEmpty ? brief : '$brief\n$_signatur';
  }

  Future<void> _sendeMail() async {
    final d = _daten('email');
    // ⚠️ Wir-Fassung: die Mail geht aus dem Vereinspostfach und trägt die
    // Signatur eines Vorstandsmitglieds. In der Ich-Fassung stünden zwei
    // Unterschriften unter derselben Mail.
    final t = terminanfrageText(_vorlage, d, stimme: TerminanfrageStimme.wir);
    setState(() {
      _sendet = true;
      _fehler = '';
    });
    try {
      final gesendet = _mailText(d, t);
      final res = await widget.api.sendMail(
        to: _arztMail,
        subject: t.betreff,
        body: gesendet,
      );
      if (res['success'] != true) {
        setState(() => _fehler = res['message']?.toString() ??
            'Die E-Mail wurde nicht angenommen.');
        return;
      }
      await widget.onGesendet(TerminanfrageErgebnis(
        methode: 'email',
        vorlage: _vorlage,
        betreff: t.betreff,
        text: gesendet,
        empfaenger: _arztMail,
      ));
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _sendet = false);
    }
  }

  Future<void> _sendeFax() async {
    final d = _daten('fax');
    final t = terminanfrageText(_vorlage, d);
    final heute = DateTime.now();
    final datum = '${heute.day.toString().padLeft(2, '0')}.'
        '${heute.month.toString().padLeft(2, '0')}.${heute.year}';
    setState(() {
      _sendet = true;
      _fehler = '';
    });
    try {
      final pdf = await terminanfragePdf(
        vorlage: _vorlage,
        daten: d,
        datum: datum,
        empfaengerFax: _arztFax,
      );
      // ⚠️ Weiter Zeitrahmen: ein mehrseitiges PDF geht als base64 zu uns und
      // von dort zu sipgate. Die üblichen 12 s rissen die Übertragung ab,
      // nachdem sie halb oben war — und der Mensch sähe „Zeitüberschreitung"
      // bei einem Fax, das gleich darauf trotzdem rausgeht.
      final res = await widget.api.sipgateFaxAction({
        'action': 'senden',
        'empfaenger': _arztFax,
        'empfaenger_name': d.praxisName.isEmpty ? widget.arztTitel : d.praxisName,
        'dateiname': terminanfrageDateiname(d, datum),
        'inhalt_b64': base64Encode(pdf),
      }, timeout: const Duration(seconds: 90));

      if (res['success'] != true) {
        setState(() => _fehler =
            res['message']?.toString() ?? 'Das Fax wurde nicht angenommen.');
        return;
      }
      await widget.onGesendet(TerminanfrageErgebnis(
        methode: 'fax',
        vorlage: _vorlage,
        betreff: t.betreff,
        // ⚠️ Beim Fax OHNE Mailsignatur: das PDF hat Absenderblock und
        // Grußformel bereits, und der Signaturblock gehört zur E-Mail, nicht
        // zum Brief. Was hier steht, ist der Inhalt des versandten PDFs.
        text: t.alsMailText(d),
        empfaenger: _arztFax,
        sitzungId: res['session_id']?.toString() ?? '',
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _fehler = 'Fehler beim Faxversand: $e');
    } finally {
      if (mounted) setState(() => _sendet = false);
    }
  }

  // ── Oberfläche ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Die Vorschau zeigt die Fassung des gewählten Kanals — die Mail in der
    // Wir-Fassung, das Fax in der Ich-Fassung. Sonst wäre der Kasten „So geht
    // es raus" schon wieder eine Behauptung.
    final vorschau = terminanfrageText(_vorlage, _daten(_kanal),
        stimme: _kanal == 'email'
            ? TerminanfrageStimme.wir
            : TerminanfrageStimme.ich);

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.send, size: 20, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Terminanfrage – ${widget.arztTitel}',
              style: const TextStyle(fontSize: 15)),
        ),
      ]),
      content: SizedBox(
        width: 520,
        child: _laedt
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _vorauswahlHinweis(),
                    const SizedBox(height: 12),
                    _abschnitt('Art der Anfrage'),
                    _vorlagenBand(),
                    const SizedBox(height: 14),
                    _abschnitt('Grund (mehrere möglich)'),
                    _anlassBand(),
                    _fachHinweis(),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _freitext,
                      maxLines: 2,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Ergänzung (optional)',
                        hintText: 'Was die Liste nicht trifft',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    _belegZeile(),
                    _begleitungZeile(),
                    const SizedBox(height: 12),
                    _abschnitt('Wie soll es rausgehen?'),
                    _kanalWahl(),
                    const SizedBox(height: 12),
                    _vorschauKasten(vorschau),
                    if (_fehler.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _fehlerKasten(),
                    ],
                  ],
                ),
              ),
      ),
      actions: _laedt
          ? [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen'))
            ]
          : [
              TextButton(
                onPressed: _sendet ? null : () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton.icon(
                onPressed: (_kanal.isEmpty || _sendet)
                    ? null
                    : (_kanal == 'fax' ? _sendeFax : _sendeMail),
                icon: _sendet
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_kanal == 'fax' ? Icons.fax : Icons.email, size: 16),
                label: Text(
                  _sendet
                      ? 'Wird gesendet …'
                      : _kanal == 'fax'
                          ? 'Fax senden'
                          : 'E-Mail senden',
                  style: const TextStyle(fontSize: 12),
                ),
                style: FilledButton.styleFrom(
                    backgroundColor: _kanal == 'fax'
                        ? Colors.orange.shade700
                        : Colors.blue.shade700),
              ),
            ],
    );
  }

  /// Die Kanalwahl.
  ///
  /// 🔴 DER GRUND STEHT AUF DEM SCHIRM, NICHT IN EINEM TOOLTIP.
  /// Erste Fassung: zwei Sendeknöpfe, der nicht mögliche ausgegraut, der Grund
  /// in einem `Tooltip`. Auf dem Schreibtisch sieht man ihn beim Darüberfahren
  /// — auf dem Pixel, auf dem diese App läuft, gibt es kein Darüberfahren, und
  /// ein deaktivierter Knopf nimmt auch kein langes Tippen an. Der Grund wäre
  /// also genau dort unsichtbar gewesen, wo er gebraucht wird, und der
  /// ausgegraute Knopf sähe aus wie ein Fehler der App.
  Widget _kanalWahl() {
    if (_kanal.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.block, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Für ${widget.arztTitel} sind weder E-Mail-Adresse noch '
              'Faxnummer hinterlegt. Beides lässt sich beim Arzt oben '
              'nachtragen; danach geht die Anfrage von hier aus raus.',
              style: TextStyle(fontSize: 11, height: 1.35, color: Colors.red.shade900),
            ),
          ),
        ]),
      );
    }
    return Row(children: [
      Expanded(
        child: _kanalKarte(
          kanal: 'email',
          moeglich: _mailMoeglich,
          icon: Icons.email,
          farbe: Colors.blue,
          titel: 'E-Mail',
          ziel: _arztMail,
          grund: 'Keine E-Mail-Adresse hinterlegt',
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _kanalKarte(
          kanal: 'fax',
          moeglich: _faxMoeglich,
          icon: Icons.fax,
          farbe: Colors.orange,
          titel: 'Fax (PDF)',
          ziel: _arztFax,
          grund: 'Keine Faxnummer hinterlegt',
        ),
      ),
    ]);
  }

  Widget _kanalKarte({
    required String kanal,
    required bool moeglich,
    required IconData icon,
    required MaterialColor farbe,
    required String titel,
    required String ziel,
    required String grund,
  }) {
    final gewaehlt = _kanal == kanal;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: moeglich ? () => setState(() => _kanal = kanal) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: !moeglich
              ? Colors.grey.shade100
              : (gewaehlt ? farbe.shade50 : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: !moeglich
                  ? Colors.grey.shade300
                  : (gewaehlt ? farbe.shade400 : Colors.grey.shade300)),
        ),
        child: Row(children: [
          Icon(icon,
              size: 16,
              color: !moeglich ? Colors.grey.shade400 : farbe.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: !moeglich
                            ? Colors.grey.shade500
                            : Colors.grey.shade900)),
                Text(
                  moeglich ? ziel : grund,
                  style: TextStyle(
                      fontSize: 10,
                      fontStyle: moeglich ? FontStyle.normal : FontStyle.italic,
                      color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (moeglich)
            Icon(
                gewaehlt
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: gewaehlt ? farbe.shade700 : Colors.grey.shade400),
        ]),
      ),
    );
  }

  Widget _abschnitt(String titel) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(titel,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700)),
      );

  /// Sagt, warum diese Vorlage vorgewählt ist — und dass es eine Vermutung
  /// aus unserer Akte ist, keine Feststellung über die Praxis.
  Widget _vorauswahlHinweis() {
    final neu = widget.basis.erfassteTermine == 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: neu ? Colors.amber.shade50 : Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: neu ? Colors.amber.shade200 : Colors.teal.shade200),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(neu ? Icons.person_add_alt : Icons.history,
            size: 16,
            color: neu ? Colors.amber.shade800 : Colors.teal.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            vorauswahlBegruendung(
                widget.basis.erfassteTermine, widget.basis.letzterTermin),
            style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: neu ? Colors.amber.shade900 : Colors.teal.shade900),
          ),
        ),
      ]),
    );
  }

  Widget _vorlagenBand() => Column(
        children: TerminanfrageVorlage.values.map((v) {
          final gewaehlt = _vorlage == v;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _vorlage = v),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      gewaehlt ? Colors.orange.shade50 : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: gewaehlt
                          ? Colors.orange.shade400
                          : Colors.grey.shade300),
                ),
                child: Row(children: [
                  Icon(
                      gewaehlt
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: gewaehlt
                          ? Colors.orange.shade700
                          : Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.titel,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: gewaehlt
                                    ? Colors.orange.shade900
                                    : Colors.grey.shade800)),
                        Text(v.erklaerung,
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          );
        }).toList(),
      );

  Widget _anlassBand() => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: _fach.anlaesse.map((a) {
          final an = _anlaesse.contains(a.kurz);
          return FilterChip(
            label: Text(a.kurz, style: const TextStyle(fontSize: 11)),
            selected: an,
            showCheckmark: false,
            avatar: Icon(
                an ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: an ? Colors.white : Colors.grey.shade600),
            selectedColor: Colors.teal.shade600,
            labelStyle: TextStyle(
                fontSize: 11, color: an ? Colors.white : Colors.grey.shade800),
            onSelected: (_) => setState(
                () => an ? _anlaesse.remove(a.kurz) : _anlaesse.add(a.kurz)),
          );
        }).toList(),
      );

  /// Fachspezifische Warnungen, die kein Text im Brief ersetzen kann.
  Widget _fachHinweis() {
    final typ = widget.basis.arztTyp;
    String? text;
    if (typ == 'gesundheit_psychiater') {
      // ⚠️ Für einen Termin muss niemand seine Diagnose auf ein Fax schreiben.
      // Ein Fax landet in einer Anmeldung offen im Ausgabefach.
      text = 'Für einen Termin genügt oft die Art der Anfrage. Ein Grund muss '
          'hier nicht angekreuzt werden — was hier steht, liegt in der '
          'Anmeldung offen aus.';
    } else if (typ == 'gesundheit_md') {
      // 🔴 Die häufigste teure Verwechslung im ganzen Bereich.
      text = 'Ein Widerspruch gehört nicht hierher: Widersprochen wird dem '
          'Bescheid der Pflegekasse, dort und innerhalb eines Monats. Der '
          'Medizinische Dienst begutachtet nur und entscheidet nichts.';
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 14, color: Colors.amber.shade800),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.35,
                      color: Colors.amber.shade900))),
        ]),
      ),
    );
  }

  /// ⚠️ Standardmäßig AUS, auch wo die Überweisung im Fach üblich ist. Der
  /// Satz „Eine Überweisung liegt vor" ist eine Zusage; wer sie voreingestellt
  /// mitschickt und dann ohne Papier dasteht, hat den Termin umsonst gehabt.
  /// Der Hinweis sagt nur, dass es in diesem Fach üblich IST.
  Widget _belegZeile() => CheckboxListTile(
        value: _beleg,
        onChanged: (v) => setState(() => _beleg = v ?? false),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('${_fach.belegName} liegt vor',
            style: const TextStyle(fontSize: 12)),
        subtitle: Text(
          _fach.ueberweisungUeblich
              ? 'In diesem Fach üblich — bitte nachsehen, bevor Sie es zusagen.'
              : 'Nur ankreuzen, wenn das Papier wirklich vorliegt.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      );

  Widget _begleitungZeile() => SwitchListTile(
        value: _begleitung,
        onChanged: (v) => setState(() => _begleitung = v),
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('Begleitung durch den Verein',
            style: TextStyle(fontSize: 12)),
        subtitle: Text(
          _begleitung
              ? 'Der Brief bittet um einen Termin $kVereinErreichbarkeit — '
                  'nur dann kann jemand zum Übersetzen mitkommen.'
              : 'Ohne Bitte um eine bestimmte Terminlage.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      );

  /// ⚠️ Die Vorschau ist nicht Zierde. Was hier steht, geht so raus — und es
  /// ist die letzte Stelle, an der ein Mensch merkt, dass ein Grund
  /// angekreuzt ist, der nicht stimmt.
  Widget _vorschauKasten(TerminanfrageText t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.visibility, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text('So geht es raus',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700)),
          ]),
          const SizedBox(height: 6),
          SelectableText(t.betreff,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: SingleChildScrollView(
              child: SelectableText(
                t.absaetze.join('\n\n'),
                style: const TextStyle(fontSize: 11, height: 1.4),
              ),
            ),
          ),
        ]),
      );

  Widget _fehlerKasten() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_fehler,
                style: TextStyle(fontSize: 11, color: Colors.red.shade900)),
          ),
        ]),
      );

}
