import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../utils/arzt_termin_schreiben.dart';
import 'file_viewer_dialog.dart';

/// Ärzte ▸ Termin ▸ Terminverwaltung — bestätigen, verschieben, absagen.
///
/// WARUM ES DAS GIBT
/// Viele Praxen verlangen eine Terminbestätigung. Dafür gab es hier nichts.
/// Und die beiden vorhandenen Knöpfe „Absage" und „Verschieben" am Kopf der
/// Terminliste erzeugten bloß einen Text zum Herauskopieren — verschickt
/// wurde nie etwas, und am Termin selbst änderte sich nichts.
///
/// 🔴 EIN WIDGET FÜR ALLE SECHS REITER. Hausarzt & Co. liegen in
/// `gesundheit_tab_content.dart`, Augenarzt, HNO, Krankenhaus, MD und
/// Rheumatologie in je einer entkoppelten Kopie. Wer diesen Abschnitt sechsmal
/// hineinkopiert, hat ab dem ersten Tag sechs Fassungen desselben Briefes —
/// genau der Fehler, den der gemeinsame Anfrage-Dialog schon einmal beseitigt
/// hat.
///
/// ⚠️ HIER ENTSTEHT KEIN BRIEFTEXT. Er kommt fertig vom Server
/// (`api/helpers/arzt_termin_schreiben.php`), einmal als PDF und einmal als
/// Text, aus derselben Quelle. Wer den Text hier noch einmal formuliert,
/// lässt Mail und Fax auseinanderlaufen.
///
/// ⚠️ Verschickt wird über [ApiService.sendMail] und
/// [ApiService.sipgateFaxAction] — dieselben zwei Wege wie bei der
/// Terminanfrage. Der Server baut nur; ein dritter Sendeweg wäre eine zweite
/// Wahrheit, und das Fax stünde in keinem Fax-Bildschirm.

/// Welcher Speicher steht hinter diesem Reiter?
///
/// 🔴 WIRD NICHT GERATEN. `gesundheit_augenarzt` steht sowohl in
/// `mitglied_arzt_termine` (Altbestand) als auch in `augenarzt_termin` — daran
/// ist #454 gescheitert („dieselbe id in zwei Tabellen war zwei verschiedene
/// Praxen"). Der Reiter weiß, aus welchem Speicher er liest, und sagt es.
enum ArztTerminQuelle {
  gemeinsam,
  augenarzt,
  hno,
  krankenhaus,
  md,
  rheumatologie,
}

extension ArztTerminQuelleX on ArztTerminQuelle {
  String get schluessel => switch (this) {
        ArztTerminQuelle.gemeinsam => 'gemeinsam',
        ArztTerminQuelle.augenarzt => 'augenarzt',
        ArztTerminQuelle.hno => 'hno',
        ArztTerminQuelle.krankenhaus => 'krankenhaus',
        ArztTerminQuelle.md => 'md',
        ArztTerminQuelle.rheumatologie => 'rheumatologie',
      };
}

/// Der Abschnitt „Terminverwaltung" im Detailfenster eines Termins.
///
/// Steht im Reiter „Details", direkt unter den Angaben und neben den Notizen —
/// dort, wo man hinsieht, wenn man einen Termin geöffnet hat, um etwas mit ihm
/// zu tun.
class ArztTerminManagement extends StatelessWidget {
  final ApiService api;
  final User user;
  final String arztTitel;

  /// Der Termin, wie ihn die Liste liefert (`id`, `datum`, `uhrzeit`,
  /// `status`, …).
  final Map<String, dynamic> termin;

  /// Die gewählte Praxis (`praxis_name`, `arzt_name`, `strasse`, `plz_ort`,
  /// `email`, `fax`) — dieselbe Karte, die auch
  /// `terminanfrageDatenBauen` erwartet.
  final Map<String, dynamic> arzt;

  final ArztTerminQuelle quelle;

  /// ⚠️ Wird durchgereicht, NICHT aus dem Termin gelesen: die Listen liefern
  /// den `arzt_type` nicht in jeder Zeile mit, und ohne ihn schreibt der
  /// Speicheraufruf ins Leere — der Brief wäre raus und die Korrespondenzzeile
  /// nirgends.
  final String arztType;

  /// 🔴 MUSS die Speicherfunktion DIESES Reiters sein — die fünf entkoppelten
  /// Reiter schreiben in eigene Tabellen und haben je eine eigene
  /// (`saveHnoTermin`, `saveAugenarztTermin`, …). Wird hier überall
  /// `saveArztTermin` gereicht, kompiliert es, der Brief geht raus, und die
  /// Korrespondenzzeile landet in der falschen Tabelle — im Reiter erscheint
  /// sie NIE. Dieselbe Falle wie bei `terminanfrageAblegen`.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) speichern;

  /// Wird nach jeder Änderung gerufen: der Reiter lädt seine Liste neu.
  final VoidCallback onAktualisiert;

  const ArztTerminManagement({
    super.key,
    required this.api,
    required this.user,
    required this.arztTitel,
    required this.termin,
    required this.arzt,
    required this.quelle,
    required this.arztType,
    required this.speichern,
    required this.onAktualisiert,
  });

  String get _status => (termin['status']?.toString() ?? 'offen').isEmpty
      ? 'offen'
      : termin['status'].toString();

  /// `2026-08-29 20:15:00` → `29.08.2026, 20:15 Uhr`.
  ///
  /// ⚠️ Die rohe Marke aus der Datenbank stand hier zuerst so, wie sie kam.
  /// Auf dem gerenderten Bild las sich das als „seit 2026-08-29 20:15:00" —
  /// die einzige Stelle im ganzen Reiter mit ISO-Datum und Sekunden. Beim
  /// Lesen des Codes fällt so etwas nicht auf, auf dem Bild sofort.
  ///
  /// ⚠️ Kein `DateFormat` mit fester Länge: kommt etwas anderes als die
  /// erwartete Form, bleibt es unverändert stehen. Lieber eine ungewohnte
  /// Schreibweise als ein falsches Datum.
  String get _seit {
    final roh = (termin['status_am']?.toString() ?? '').trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})').firstMatch(roh);
    if (m == null) return roh;
    return '${m.group(3)}.${m.group(2)}.${m.group(1)}, '
        '${m.group(4)}:${m.group(5)} Uhr';
  }

  // ⚠️ `MaterialColor`, nicht `Color`: `F.h()` braucht die Farbtonleiter
  // (50…900). Mit `Color` scheitert schon die Analyse.
  static (MaterialColor, IconData) _statusOptik(String status) => switch (status) {
        'bestaetigt' => (Colors.green, Icons.event_available),
        'verschoben' => (Colors.blue, Icons.event_repeat),
        'abgesagt' => (Colors.red, Icons.event_busy),
        _ => (Colors.grey, Icons.help_outline),
      };

  @override
  Widget build(BuildContext context) {
    final (farbe, symbol) = _statusOptik(_status);
    final praxisFehlt = (arzt['praxis_name']?.toString() ?? '').isEmpty &&
        (arzt['arzt_name']?.toString() ?? '').isEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: F.h(Colors.teal, 50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(Colors.teal, 200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.fact_check, size: 18, color: F.h(Colors.teal, 700)),
            const SizedBox(width: 6),
            // ⚠️ `Expanded` statt `Spacer`: mit `Spacer` beansprucht der Titel
            // seine volle natürliche Breite, und die Pastille „Verlegung
            // erbeten" lief rechts hinaus — gemessen 9,6 px schon bei 560 dp,
            // auf einem Pixel 8 Pro (416 dp nutzbar) entsprechend mehr. Beim
            // Lesen des Codes war davon nichts zu sehen; gefunden hat es erst
            // die Golden-Aufnahme. Derselbe Fehlertyp wie bei der Kopfleiste
            // der Terminliste ein paar Dateien weiter.
            Expanded(
              child: Text('Terminverwaltung',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: F.h(Colors.teal, 800))),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: F.h(farbe, 100),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: F.h(farbe, 300)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(symbol, size: 13, color: F.h(farbe, 700)),
                const SizedBox(width: 4),
                Text(kAtsStatusLabel[_status] ?? _status,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: F.h(farbe, 800))),
              ]),
            ),
          ]),
          if (_seit.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('seit $_seit',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ],
          const SizedBox(height: 10),
          // ⚠️ Ohne Praxis gibt es weder Anschrift noch Kanal. Die Knöpfe
          // wären aus, und das sieht nach kaputt aus statt nach „es fehlt ein
          // Arzt". Also lieber sagen, was fehlt.
          if (praxisFehlt)
            Row(children: [
              Icon(Icons.info_outline,
                  size: 15, color: F.h(Colors.orange, 700)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Zuerst einen $arztTitel auswählen — ohne Praxis gibt es '
                    'keine Anschrift und keinen Sendeweg.',
                    style: TextStyle(
                        fontSize: 11.5, color: F.h(Colors.orange, 800))),
              ),
            ])
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final eintrag in kAtsArten.entries)
                _knopf(context, eintrag.key, eintrag.value),
            ]),
        ],
      ),
    );
  }

  Widget _knopf(BuildContext context, String art, String label) {
    final (farbe, symbol) = switch (art) {
      'bestaetigen' => (Colors.green, Icons.event_available),
      'verschieben' => (Colors.blue, Icons.event_repeat),
      _ => (Colors.red, Icons.event_busy),
    };
    return OutlinedButton.icon(
      onPressed: () => zeigeArztTerminSchreiben(
        context,
        api: api,
        user: user,
        arztTitel: arztTitel,
        termin: termin,
        arzt: arzt,
        quelle: quelle,
        arztType: arztType,
        art: art,
        speichern: speichern,
        onAktualisiert: onAktualisiert,
      ),
      icon: Icon(symbol, size: 16, color: F.h(farbe, 700)),
      label: Text(label,
          style: TextStyle(fontSize: 12, color: F.h(farbe, 700))),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: F.h(farbe, 300)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}

/// Öffnet das Schreiben-Fenster. Gibt `true` zurück, wenn etwas rausging.
Future<bool> zeigeArztTerminSchreiben(
  BuildContext context, {
  required ApiService api,
  required User user,
  required String arztTitel,
  required Map<String, dynamic> termin,
  required Map<String, dynamic> arzt,
  required ArztTerminQuelle quelle,
  required String arztType,
  required String art,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>)
      speichern,
  required VoidCallback onAktualisiert,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _SchreibenDialog(
      api: api,
      user: user,
      arztTitel: arztTitel,
      termin: termin,
      arzt: arzt,
      quelle: quelle,
      arztType: arztType,
      art: art,
      speichern: speichern,
    ),
  );
  if (ok == true) onAktualisiert();
  return ok == true;
}

class _SchreibenDialog extends StatefulWidget {
  final ApiService api;
  final User user;
  final String arztTitel;
  final Map<String, dynamic> termin;
  final Map<String, dynamic> arzt;
  final ArztTerminQuelle quelle;
  final String arztType;
  final String art;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) speichern;

  const _SchreibenDialog({
    required this.api,
    required this.user,
    required this.arztTitel,
    required this.termin,
    required this.arzt,
    required this.quelle,
    required this.arztType,
    required this.art,
    required this.speichern,
  });

  @override
  State<_SchreibenDialog> createState() => _SchreibenDialogState();
}

class _SchreibenDialogState extends State<_SchreibenDialog> {
  final Set<String> _gewaehlt = {};
  final TextEditingController _freitext = TextEditingController();
  DateTime? _wunschDatum;
  TimeOfDay? _von;
  TimeOfDay? _bis;

  String _kanal = '';
  bool _sendet = false;
  bool _baut = false;
  String _fehler = '';
  String _signatur = '';

  String get _mail => (widget.arzt['email']?.toString() ?? '').trim();
  String get _fax => (widget.arzt['fax']?.toString() ?? '').trim();
  bool get _mailMoeglich => _mail.contains('@');
  bool get _faxMoeglich => _fax.replaceAll(RegExp(r'[^0-9]'), '').length >= 6;

  @override
  void initState() {
    super.initState();
    // E-Mail zuerst, wenn beides geht: sie kostet nichts, kommt sofort an und
    // die Antwort landet lesbar im Postfach statt als Bild im Faxeingang.
    _kanal = _mailMoeglich ? 'email' : (_faxMoeglich ? 'fax' : '');
    _signaturHolen();
  }

  @override
  void dispose() {
    _freitext.dispose();
    super.dispose();
  }

  /// 🔴 Die Signatur kommt NICHT von selbst. `api/mail/send.php` reicht `body`
  /// unverändert weiter; angehängt wird sie im Client. Wer wie hier direkt
  /// `sendMail()` ruft, umgeht sie — die Praxis bekäme eine Mail ohne
  /// Absenderblock, ohne Verein, ohne Impressum. Nachgesehen am 21.08.2026,
  /// dieselbe Stelle wie im Anfrage-Dialog.
  ///
  /// ⚠️ Sie beginnt mit `-- ` und enthält KEINE Grußformel, deshalb bleibt
  /// „Mit freundlichen Grüßen" samt Namen des Mitglieds im Brieftext stehen
  /// und die Vereinssignatur kommt darunter. Zwei Unterschriften wären es
  /// nur, wenn die Signatur selbst grüßte.
  Future<void> _signaturHolen() async {
    try {
      final sig = await widget.api.getMailSignature();
      if (sig['success'] == true) {
        _signatur = (sig['signature'] ?? '').toString();
      }
    } catch (_) {
      // Ohne Signatur ist der Brief schlechter, aber immer noch ein Brief.
    }
  }

  String get _titel => kAtsArten[widget.art] ?? 'Schreiben';

  /// `2026-09-03` → `03.09.2026`. Alles andere bleibt, wie es ist.
  ///
  /// ⚠️ Kein `DateFormat` mit fester Länge: steht in der Zeile bereits
  /// deutsches Format, machte ein blindes Umformatieren aus `03.09.2026`
  /// schnell `09.03.2026`. Dieselbe Vorsicht wie in
  /// `terminanfrage_versand_dialog.dart`.
  static String _deutschesDatum(String roh) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(roh);
    return m == null ? roh : '${m.group(3)}.${m.group(2)}.${m.group(1)}';
  }

  Map<String, dynamic> _nutzlast({required bool alsFax}) {
    // ⚠️ `user.name` ist der VOLLE Name. Ein naives `nachname ?? name` ergibt
    // bei fehlendem Nachnamen „Ionut Ionut Doe" — auf einem Blatt, das in
    // der Karteikarte der Praxis landet. Dieselbe Behandlung wie in
    // `terminanfrageDatenBauen`.
    final nachname = (widget.user.nachname ?? '').trim();
    final vorname = nachname.isEmpty ? '' : (widget.user.vorname ?? '').trim();
    String zeit(TimeOfDay? t) => t == null
        ? ''
        : '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';

    return {
      'action': 'vorschau',
      'art': widget.art,
      'gruende': _gewaehlt.toList(),
      'freitext': _freitext.text.trim(),
      'termin_datum': widget.termin['datum']?.toString() ?? '',
      'termin_uhrzeit': widget.termin['uhrzeit']?.toString() ?? '',
      'wunsch_datum': _wunschDatum == null
          ? ''
          : '${_wunschDatum!.year}-'
              '${_wunschDatum!.month.toString().padLeft(2, '0')}-'
              '${_wunschDatum!.day.toString().padLeft(2, '0')}',
      'wunsch_von': zeit(_von),
      'wunsch_bis': zeit(_bis),
      'vorname': vorname,
      'nachname': nachname.isEmpty ? widget.user.name.trim() : nachname,
      'geburtsdatum': widget.user.geburtsdatum ?? '',
      'strasse': [widget.user.strasse, widget.user.hausnummer]
          .where((e) => (e ?? '').isNotEmpty)
          .join(' '),
      'plz': widget.user.plz ?? '',
      'ort': widget.user.ort ?? '',
      'praxis_name': widget.arzt['praxis_name']?.toString() ?? '',
      'arzt_name': widget.arzt['arzt_name']?.toString() ?? '',
      'praxis_strasse': widget.arzt['strasse']?.toString() ?? '',
      'praxis_plz_ort': widget.arzt['plz_ort']?.toString() ?? '',
      'praxis_fax': _fax,
      'als_fax': alsFax,
    };
  }

  /// Holt Brief und PDF vom Server. `null` = es gab einen Grund, und der
  /// steht dann im Fehlerkasten.
  Future<Map<String, dynamic>?> _bauen({required bool alsFax}) async {
    final lokal = atsSchreibenPruefen(
      art: widget.art,
      gruende: _gewaehlt.toList(),
      freitext: _freitext.text,
    );
    if (lokal != null) {
      setState(() => _fehler = lokal);
      return null;
    }
    setState(() {
      _baut = true;
      _fehler = '';
    });
    try {
      final r = await widget.api.arztTerminSchreiben(_nutzlast(alsFax: alsFax));
      if (r['success'] != true) {
        setState(() => _fehler =
            r['message']?.toString() ?? 'Der Brief konnte nicht gebaut werden.');
        return null;
      }
      return Map<String, dynamic>.from(r);
    } catch (e) {
      setState(() => _fehler = 'Der Brief konnte nicht gebaut werden: $e');
      return null;
    } finally {
      if (mounted) setState(() => _baut = false);
    }
  }

  /// ⚠️ ÜBER FileViewerDialog, NICHT über `Printing`. `Printing.layoutPdf`
  /// ist kein Betrachter, sondern der Druckdialog — wer nur nachsehen will,
  /// was er gleich verschickt, bekäme eine Druckerauswahl vorgesetzt. Und
  /// `PdfPreview` aus demselben Paket hat am 19.08.2026 auf Linux Mint die
  /// ganze App geschlossen (Absturz in nativem Code, den kein try/catch in
  /// Dart auffängt). Siehe die Begründung an `_pdfAnsehen` in
  /// `vertrag_elektronische_kuendigung.dart`.
  ///
  /// Das PDF berührt dabei nie die Platte: es geht als Bytes hinein.
  Future<void> _pdfAnsehen() async {
    final r = await _bauen(alsFax: _kanal == 'fax');
    if (r == null || !mounted) return;
    final bytes =
        Uint8List.fromList(base64Decode(r['pdf_base64'].toString()));
    await FileViewerDialog.showFromBytes(
        context, bytes, (r['filename'] ?? 'Schreiben.pdf').toString());
  }

  Future<void> _senden() async {
    final alsFax = _kanal == 'fax';
    final r = await _bauen(alsFax: alsFax);
    if (r == null || !mounted) return;

    final betreff = (r['betreff'] ?? _titel).toString();
    final briefText = (r['text'] ?? '').toString();
    setState(() {
      _sendet = true;
      _fehler = '';
    });
    try {
      String empfaenger;
      String gesendet;
      String sitzung = '';
      // ⚠️ Die Kennungen des Versands. Ohne sie ist an der
      // Korrespondenzzeile spaeter nicht mehr feststellbar, ob die Nachricht
      // je angekommen ist — „gesendet" heisst nur, dass unser Server sie
      // uebernommen hat.
      String messageId = '';
      int faxId = 0;

      if (alsFax) {
        final pdf =
            Uint8List.fromList(base64Decode(r['pdf_base64'].toString()));
        final praxis = (widget.arzt['praxis_name']?.toString() ?? '');
        // ⚠️ Weiter Zeitrahmen: das PDF geht als base64 zu uns und von dort
        // zu sipgate. Die üblichen 12 s rissen die Übertragung ab, nachdem
        // sie halb oben war — und der Mensch sähe „Zeitüberschreitung" bei
        // einem Fax, das gleich darauf trotzdem rausgeht.
        final res = await widget.api.sipgateFaxAction({
          'action': 'senden',
          'empfaenger': _fax,
          'empfaenger_name': praxis.isEmpty ? widget.arztTitel : praxis,
          'dateiname': (r['filename'] ?? 'Schreiben.pdf').toString(),
          'inhalt_b64': base64Encode(pdf),
        }, timeout: const Duration(seconds: 90));
        if (res['success'] != true) {
          setState(() => _fehler =
              res['message']?.toString() ?? 'Das Fax wurde nicht angenommen.');
          return;
        }
        empfaenger = _fax;
        // ⚠️ OHNE Mailsignatur: das PDF trägt Absenderblock und Grußformel
        // bereits, und die Signatur gehört zur E-Mail, nicht zum Brief. Was
        // hier abgelegt wird, ist der Inhalt des versandten PDFs.
        gesendet = briefText;
        sitzung = res['session_id']?.toString() ?? '';
        // ⚠️ `id` ist unsere Faxzeile, NICHT die sipgate-Sitzung. Nur mit ihr
        // lässt sich der Stand später nachfassen; die Sitzungsnummer steht
        // bloß im Sendebericht.
        faxId = (res['id'] as num?)?.toInt() ?? 0;
      } else {
        gesendet =
            _signatur.trim().isEmpty ? briefText : '$briefText\n$_signatur';
        final res = await widget.api
            .sendMail(to: _mail, subject: betreff, body: gesendet);
        if (res['success'] != true) {
          setState(() => _fehler = res['message']?.toString() ??
              'Die E-Mail wurde nicht angenommen.');
          return;
        }
        empfaenger = _mail;
        messageId = res['message_id']?.toString() ?? '';
      }

      await _ablegen(
        alsFax: alsFax,
        betreff: betreff,
        text: gesendet,
        empfaenger: empfaenger,
        sitzung: sitzung,
        messageId: messageId,
        faxId: faxId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        // ⚠️ „an sipgate übergeben", nicht „zugestellt" — die Zustellung
        // verfolgt `sipgate_fax_status.php` nach.
        content: Text(alsFax
            ? 'Fax an sipgate übergeben'
                '${sitzung.isEmpty ? '' : ' (Sitzung $sitzung)'}'
            : 'E-Mail an $empfaenger gesendet'),
        backgroundColor: Colors.green.shade700,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _fehler = 'Fehler beim Versand: $e');
    } finally {
      if (mounted) setState(() => _sendet = false);
    }
  }

  /// Legt ab, was rausging: Status am Termin und eine Korrespondenzzeile.
  ///
  /// ⚠️ Beides darf scheitern, ohne dass der Versand als Fehler gilt — der
  /// Brief IST raus. Ein „Fehlgeschlagen" nach erfolgreichem Versand wäre die
  /// schlechtere Lüge: der Mensch schickt ihn ein zweites Mal, und die Praxis
  /// bekommt zwei Absagen.
  Future<void> _ablegen({
    required bool alsFax,
    required String betreff,
    required String text,
    required String empfaenger,
    required String sitzung,
    required String messageId,
    required int faxId,
  }) async {
    final heute = DateTime.now();
    final datum = '${heute.year}-${heute.month.toString().padLeft(2, '0')}-'
        '${heute.day.toString().padLeft(2, '0')}';

    try {
      await widget.api.arztTerminSchreiben({
        'action': 'status',
        'quelle': widget.quelle.schluessel,
        'termin_id': widget.termin['id'],
        'user_id': widget.user.id,
        'status': atsStatusFuer(widget.art),
      });
      // Damit der Reiter den neuen Stand sofort zeigt, auch bevor er neu lädt.
      widget.termin['status'] = atsStatusFuer(widget.art);
    } catch (_) {}

    try {
      final korr = List<Map<String, dynamic>>.from(
          widget.termin['korrespondenz'] ?? const []);
      korr.add({
        'datum': datum,
        'art': alsFax ? 'fax' : 'email',
        'richtung': 'ausgehend',
        'betreff': betreff,
        'inhalt': text,
        if (sitzung.isNotEmpty) 'sitzung_id': sitzung,
        // ⚠️ Die Kennung reist AN DER ZEILE mit, nicht in den Notizen des
        // Termins. Die Terminanfrage legt sie dort ab, weil ihre Terminzeile
        // feste Spalten hat — aber ein Termin kann mehrere Schreiben tragen,
        // und mit einer Kennung in den Notizen bekämen alle den Stand des
        // zuletzt versandten. Hier hängt jede Zeile an ihrem eigenen Versand.
        if (messageId.isNotEmpty) 'message_id': messageId,
        if (faxId > 0) 'fax_id': faxId,
        // ⚠️ Der Stand IM AUGENBLICK des Versands, nicht das Ergebnis. sipgate
        // hat das Fax übernommen, mehr weiß niemand. Er steht hier, damit die
        // Zeile sofort „Unterwegs" zeigt statt einer Lücke, bis die Nachfrage
        // zurück ist — und weil er NICHT endgültig ist, wird weiter
        // nachgefasst, bis er es ist.
        if (faxId > 0) 'fax_status': 'in_zustellung',
        'empfaenger': empfaenger,
      });
      widget.termin['korrespondenz'] = korr;
      // ⚠️ `update` OHNE `datum`: nur dieser Zweig schreibt bei
      // `gesundheit_termine_save.php` die Korrespondenz, ohne den Termin
      // selbst anzufassen. Mit `datum` liefe er in den Vollschreib-Zweig und
      // überschriebe Uhrzeit, Diagnose und Notizen mit dem, was hier nicht
      // mitgegeben wird.
      await widget.speichern({
        'action': 'update',
        'user_id': widget.user.id,
        'arzt_type': widget.arztType,
        'termin_id': widget.termin['id'],
        'korrespondenz': korr,
      });
    } catch (_) {}
  }

  // ── Oberfläche ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final katalog = atsKatalog(widget.art);
    final farbe = switch (widget.art) {
      'bestaetigen' => Colors.green,
      'verschieben' => Colors.blue,
      _ => Colors.red,
    };
    // ⚠️ Deutsches Datum, nicht die ISO-Form aus der Datenbank. Auf der
    // Golden-Aufnahme stand „Termin am 2026-09-03" — die einzige Stelle im
    // Fenster mit ISO-Datum, direkt über einem Brief, der das Datum deutsch
    // schreibt.
    final datum = _deutschesDatum(widget.termin['datum']?.toString() ?? '');
    final uhr = widget.termin['uhrzeit']?.toString() ?? '';

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.description, size: 20, color: F.h(farbe, 700)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$_titel – ${widget.arztTitel}',
              style: const TextStyle(fontSize: 15)),
        ),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Um welchen Termin geht es? Ohne das steht der Brief im Raum.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: F.h(Colors.grey, 100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.event, size: 15, color: F.h(Colors.grey, 700)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      datum.isEmpty
                          ? 'Termin ohne Datum'
                          : 'Termin am $datum${uhr.isEmpty ? '' : ' um $uhr Uhr'}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              _abschnitt(widget.art == 'bestaetigen'
                  ? 'Hinweise an die Praxis (optional)'
                  : 'Grund (mehrere möglich)'),
              // ⚠️ Kästchen, KEINE Chips. Die erste Fassung nahm `FilterChip`
              // in einem `Wrap` — auf der Golden-Aufnahme stand dort „Eine
              // Begleitperson des Ver", abgeschnitten. Ein Chip bricht seine
              // Beschriftung nicht um, er wird nur breiter; die längsten
              // Einträge hier sind ganze Sätze („Begleitung und Sprachmittlung
              // durch den Verein nur in einem anderen Zeitfenster möglich").
              // Wer die Hälfte eines Grundes liest, hakt den falschen an.
              // Dieselbe Bauart wie im Jobcenter-Briefdialog.
              for (final e in katalog.entries)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  visualDensity: VisualDensity.compact,
                  activeColor: F.h(farbe, 700),
                  value: _gewaehlt.contains(e.key),
                  onChanged: (an) => setState(() {
                    if (an == true) {
                      _gewaehlt.add(e.key);
                    } else {
                      _gewaehlt.remove(e.key);
                    }
                    _fehler = '';
                  }),
                  title: Text(e.value, style: const TextStyle(fontSize: 12.5)),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _freitext,
                maxLines: 2,
                onChanged: (_) => setState(() => _fehler = ''),
                decoration: InputDecoration(
                  labelText: 'Ergänzung (optional)',
                  hintText: 'Was die Liste nicht trifft',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              if (widget.art == 'verschieben') ...[
                const SizedBox(height: 14),
                _abschnitt('Wunschzeitraum (optional)'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 400)),
                        locale: const Locale('de'),
                      );
                      if (d != null) setState(() => _wunschDatum = d);
                    },
                    icon: const Icon(Icons.calendar_today, size: 14),
                    label: Text(
                        _wunschDatum == null
                            ? 'ab Tag'
                            : 'ab ${_wunschDatum!.day.toString().padLeft(2, '0')}.'
                                '${_wunschDatum!.month.toString().padLeft(2, '0')}.',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  _zeitKnopf('von', _von, (t) => setState(() => _von = t)),
                  _zeitKnopf('bis', _bis, (t) => setState(() => _bis = t)),
                ]),
              ],
              const SizedBox(height: 14),
              _abschnitt('Wie soll es rausgehen?'),
              _kanalWahl(),
              if (_fehler.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: F.h(Colors.red, 50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: F.h(Colors.red, 200)),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline,
                        size: 16, color: F.h(Colors.red, 700)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_fehler,
                          style: TextStyle(
                              fontSize: 12, color: F.h(Colors.red, 800))),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_sendet || _baut) ? null : () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        // ⚠️ Die Vorschau ist nicht Zierde: was dort steht, geht so raus.
        // Deshalb ist sie auch ohne gewählten Kanal erreichbar — man liest sie
        // ja gerade, um sich zu vergewissern.
        TextButton.icon(
          onPressed: (_sendet || _baut) ? null : _pdfAnsehen,
          icon: _baut
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf, size: 16),
          label: const Text('PDF ansehen'),
        ),
        FilledButton.icon(
          onPressed:
              (_kanal.isEmpty || _sendet || _baut) ? null : _senden,
          icon: _sendet
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(_kanal == 'fax' ? Icons.fax : Icons.email, size: 16),
          label: Text(_kanal == 'fax' ? 'Per Fax senden' : 'Per E-Mail senden'),
          style: FilledButton.styleFrom(backgroundColor: F.h(farbe, 700)),
        ),
      ],
    );
  }

  Widget _abschnitt(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: F.h(Colors.grey, 700))),
      );

  Widget _zeitKnopf(
      String label, TimeOfDay? wert, void Function(TimeOfDay) setzen) {
    return OutlinedButton.icon(
      onPressed: () async {
        final t = await showTimePicker(
            context: context,
            initialTime: wert ?? const TimeOfDay(hour: 9, minute: 0));
        if (t != null) setzen(t);
      },
      icon: const Icon(Icons.schedule, size: 14),
      label: Text(
          wert == null
              ? label
              : '${wert.hour.toString().padLeft(2, '0')}:'
                  '${wert.minute.toString().padLeft(2, '0')} Uhr',
          style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _kanalWahl() {
    // ⚠️ Ein ausgeschalteter Knopf ohne Grund sieht nach kaputt aus. Fehlt
    // die Faxnummer oder die Mailadresse der Praxis, steht das dabei — sonst
    // sucht der Mensch den Fehler bei sich.
    return Column(children: [
      _kanalZeile(
        wert: 'email',
        symbol: Icons.email,
        titel: 'E-Mail',
        unten: _mailMoeglich ? _mail : 'Keine E-Mail-Adresse der Praxis',
        moeglich: _mailMoeglich,
      ),
      const SizedBox(height: 6),
      _kanalZeile(
        wert: 'fax',
        symbol: Icons.fax,
        titel: 'Fax (PDF)',
        unten: _faxMoeglich ? _fax : 'Keine Faxnummer der Praxis',
        moeglich: _faxMoeglich,
      ),
    ]);
  }

  Widget _kanalZeile({
    required String wert,
    required IconData symbol,
    required String titel,
    required String unten,
    required bool moeglich,
  }) {
    final an = _kanal == wert;
    return InkWell(
      onTap: moeglich ? () => setState(() => _kanal = wert) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: an ? F.h(Colors.teal, 50) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: an ? F.h(Colors.teal, 400) : F.h(Colors.grey, 300)),
        ),
        child: Row(children: [
          Icon(symbol,
              size: 17,
              color: moeglich ? F.h(Colors.teal, 700) : F.h(Colors.grey, 400)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titel,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: moeglich ? null : F.h(Colors.grey, 500))),
                Text(unten,
                    style: TextStyle(
                        fontSize: 11,
                        color: moeglich
                            ? F.h(Colors.grey, 600)
                            : F.h(Colors.orange, 700))),
              ],
            ),
          ),
          if (an) Icon(Icons.check_circle, size: 17, color: F.h(Colors.teal, 700)),
        ]),
      ),
    );
  }
}
