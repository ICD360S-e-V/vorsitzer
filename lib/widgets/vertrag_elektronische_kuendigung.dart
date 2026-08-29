import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../utils/kuendigung_autofill.dart' show kKuendigungBestaetigungMail;
import '../utils/kuendigung_schreiben.dart';

/// Verträge → Vertrag → „Elektronische Kündigung".
///
/// Erzeugt aus den Vertragsdaten ein Kündigungsschreiben, zeigt es als PDF
/// und schickt es über die Wege, die die App ohnehin betreibt: Fax über
/// sipgate, E-Mail über den eingebauten Mailclient. Danach steht der
/// WORTLAUT in der Korrespondenz des Vertrages.
///
/// ⚠️ Gebaut nach dem Muster des Widerspruchs gegen ein Inkassobüro
/// (`vermieter_widerspruch.dart`) — dort ist derselbe Weg schon einmal
/// durchdacht worden. Übernommen sind vor allem drei Entscheidungen:
///
///  1. **Erst zeigen, dann senden.** Eine Kündigung lässt sich nicht
///     zurückholen. Die Vorschau zeigt genau das, was rausgeht — Empfänger,
///     Betreff, Wortlaut —, keine Zusammenfassung davon.
///  2. **Fax und E-Mail sind zwei Knöpfe, nicht einer.** Wer beides will,
///     drückt beides; dann stehen auch beide Wege einzeln im Protokoll.
///  3. **Sofort ablegen.** Was raus ist, gehört in die Akte, bevor jemand
///     den Reiter schliesst.
class VertragElektronischeKuendigung extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final int userId;

  /// Die Zeile aus `mitglied_vertraege`, entschlüsselt, mit den vom Server
  /// angehängten Feldern `versicherung_name` / `versicherung_sparte`.
  final Map<String, dynamic> vertrag;

  /// Damit die Liste hinter dem Dialog den neuen Stand zeigt.
  final VoidCallback? onChanged;

  const VertragElektronischeKuendigung({
    super.key,
    required this.apiService,
    required this.vertragId,
    required this.userId,
    required this.vertrag,
    this.onChanged,
  });

  @override
  State<VertragElektronischeKuendigung> createState() =>
      _VertragElektronischeKuendigungState();
}

class _VertragElektronischeKuendigungState
    extends State<VertragElektronischeKuendigung> {
  bool _laedt = true;
  bool _sendet = false;

  Map<String, dynamic>? _stammdaten;

  // Empfänger — vorbelegt aus der Versicherungs-Datenbank, aber editierbar.
  // ⚠️ Editierbar, weil nicht jeder Vertrag eine Versicherung ist: bei
  // Mobilfunk oder Strom steht in `mitglied_vertraege` nur ein Anbietername
  // und sonst nichts. Ein Reiter, der dort gar nichts anbietet, wäre für die
  // Hälfte der Verträge nutzlos.
  final _empfName = TextEditingController();
  final _empfStrasse = TextEditingController();
  final _empfPlzOrt = TextEditingController();
  final _empfFax = TextEditingController();
  final _empfMail = TextEditingController();

  final _nummer = TextEditingController();
  final _zumDatum = TextEditingController();
  final _grund = TextEditingController();
  final _zusatz = TextEditingController();

  KuendigungsArt _art = KuendigungsArt.naechstmoeglich;
  KuendigungsUnterzeichner _wer = KuendigungsUnterzeichner.mitglied;
  bool _sepa = true;

  /// Was in dieser Sitzung tatsächlich rausging.
  final List<String> _protokoll = [];

  String get _kategorie => widget.vertrag['kategorie']?.toString() ?? '';
  String get _nummerLabel => kuendigungNummerLabel(_kategorie);

  @override
  void initState() {
    super.initState();
    _nummer.text = widget.vertrag['vertragsnummer']?.toString() ?? '';
    _laden();
  }

  @override
  void dispose() {
    for (final c in [
      _empfName,
      _empfStrasse,
      _empfPlzOrt,
      _empfFax,
      _empfMail,
      _nummer,
      _zumDatum,
      _grund,
      _zusatz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _laden() async {
    Map<String, dynamic>? stamm;
    try {
      final r = await widget.apiService.getUserDetails(widget.userId);
      if (r['success'] == true && r['user'] is Map) {
        stamm = Map<String, dynamic>.from(r['user'] as Map);
      }
    } catch (_) {
      // Ohne Stammdaten bleibt der Absenderblock leer und der Mensch trägt
      // ihn nach. Ein Netzfehler darf den Reiter nicht verschliessen.
    }

    // Empfängerdaten: bei Versicherungsverträgen aus der Stammtabelle, sonst
    // nur der Anbietername aus dem Vertrag.
    var name =
        widget.vertrag['versicherung_name']?.toString() ??
        widget.vertrag['anbieter']?.toString() ??
        '';
    var strasse = '';
    var plzOrt = '';
    var fax = '';
    var mail = '';
    final versId = int.tryParse(
      widget.vertrag['versicherung_id']?.toString() ?? '',
    );
    if (versId != null) {
      try {
        final r = await widget.apiService.getVersicherungen();
        if (r['success'] == true && r['data'] is List) {
          for (final e in (r['data'] as List)) {
            final m = Map<String, dynamic>.from(e as Map);
            if (m['id']?.toString() == versId.toString()) {
              name = m['name']?.toString() ?? name;
              strasse = m['strasse']?.toString() ?? '';
              plzOrt = m['plz_ort']?.toString() ?? '';
              fax = m['fax']?.toString() ?? '';
              mail = m['email']?.toString() ?? '';
              break;
            }
          }
        }
      } catch (_) {
        /* siehe oben */
      }
    }

    if (!mounted) return;
    setState(() {
      _stammdaten = stamm;
      _empfName.text = name;
      _empfStrasse.text = strasse;
      _empfPlzOrt.text = plzOrt;
      _empfFax.text = fax;
      _empfMail.text = mail;
      _laedt = false;
    });
  }

  String _s(String key) => (_stammdaten?[key]?.toString() ?? '').trim();

  String get _absenderName =>
      [_s('vorname'), _s('nachname')].where((x) => x.isNotEmpty).join(' ');

  String get _absenderStrasse =>
      [_s('strasse'), _s('hausnummer')].where((x) => x.isNotEmpty).join(' ');

  String get _absenderPlzOrt =>
      [_s('plz'), _s('ort')].where((x) => x.isNotEmpty).join(' ');

  String _heute() {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2, '0')}.'
        '${n.month.toString().padLeft(2, '0')}.${n.year}';
  }

  KuendigungsDaten get _daten => KuendigungsDaten(
    empfaengerName: _empfName.text.trim(),
    empfaengerStrasse: _empfStrasse.text.trim(),
    empfaengerPlzOrt: _empfPlzOrt.text.trim(),
    absenderName: _absenderName,
    absenderStrasse: _absenderStrasse,
    absenderPlzOrt: _absenderPlzOrt,
    vertragsBezeichnung: _bezeichnung,
    vertragsNummer: _nummer.text.trim(),
    nummerLabel: _nummerLabel,
    kundenNummer: widget.vertrag['kundennummer']?.toString() ?? '',
    rufNummer: widget.vertrag['telefonnummer']?.toString() ?? '',
    art: _art,
    zumDatum: _zumDatum.text.trim(),
    grund: _grund.text.trim(),
    unterzeichner: _wer,
    vereinName: 'ICD360S e.V.',
    bestaetigungAn: kKuendigungBestaetigungMail,
    sepaWiderrufen: _sepa,
    zusatz: _zusatz.text.trim(),
    datum: _heute(),
  );

  /// Was gekündigt wird — bei Versicherungen die Sparte, sonst der Tarif.
  String get _bezeichnung {
    final tarif = widget.vertrag['tarif']?.toString().trim() ?? '';
    if (_kategorie == 'versicherung') {
      final label = _spartenLabel[tarif];
      if (label != null) return label;
    }
    return tarif;
  }

  static const _spartenLabel = <String, String>{
    'kfz': 'KFZ-Versicherung',
    'haftpflicht': 'Privathaftpflichtversicherung',
    'hausrat': 'Hausratversicherung',
    'leben': 'Lebensversicherung',
    'kranken': 'Krankenzusatzversicherung',
    'rechtsschutz': 'Rechtsschutzversicherung',
    'unfall': 'Unfallversicherung',
    'berufsunfaehigkeit': 'Berufsunfähigkeitsversicherung',
    'reise': 'Reiseversicherung',
    'tier': 'Tierversicherung',
    'sonstige': 'Versicherungsvertrag',
  };

  // ================= PDF =================

  Future<Uint8List> _alsPdf() =>
      kuendigungAlsPdf(_daten, sendewegVermerk: _sendWegVermerk);

  /// „Per Telefax an …" über dem Anschriftenfeld — steht im Brief, damit der
  /// Empfänger sieht, auf welchem Weg die Erklärung kam.
  String _sendWegVermerk = '';

  Future<void> _pdfAnsehen() async {
    final fehlt = kuendigungFehlendeAngaben(_daten);
    if (fehlt.isNotEmpty) {
      _melden('Es fehlt: ${fehlt.join(', ')}', Colors.orange);
      return;
    }
    final bytes = await _alsPdf();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          'Kuendigung_${_nummer.text.trim().replaceAll(RegExp(r'\s+'), '')}.pdf',
    );
  }

  // ================= Versand =================

  /// ⚠️ Ausdrücklich nicht beide Wege auf einen Knopf. Ob eine Kündigung per
  /// Fax oder per E-Mail rausgeht, ist eine Entscheidung im Einzelfall und
  /// gehört dem, der sie trifft. Wer beides will, drückt beides — dann steht
  /// auch jeder Weg einzeln im Protokoll und in der Akte.
  Future<void> _senden(String weg) async {
    final ziel = weg == 'fax' ? _empfFax.text.trim() : _empfMail.text.trim();
    if (ziel.isEmpty) {
      _melden(
        weg == 'fax'
            ? 'Keine Fax-Nummer hinterlegt.'
            : 'Keine E-Mail-Adresse hinterlegt.',
        Colors.orange,
      );
      return;
    }
    final fehlt = kuendigungFehlendeAngaben(_daten);
    if (fehlt.isNotEmpty) {
      _melden('Es fehlt: ${fehlt.join(', ')}', Colors.orange);
      return;
    }

    final los = await _vorschau(weg, ziel);
    if (los != true || !mounted) return;

    setState(() {
      _sendet = true;
      _sendWegVermerk = weg == 'fax'
          ? 'Per Telefax an $ziel'
          : 'Per E-Mail an $ziel';
    });

    final d = _daten;
    var ok = false;
    String zeile;
    try {
      if (weg == 'fax') {
        final pdf = await _alsPdf();
        final res = await widget.apiService.sipgateFaxAction({
          'action': 'senden',
          'empfaenger': ziel,
          'empfaenger_name': d.empfaengerName,
          'dateiname': 'Kuendigung.pdf',
          'inhalt_b64': base64Encode(pdf),
        });
        ok = res['success'] == true;
        zeile =
            'Fax an $ziel: '
            '${ok ? 'abgeschickt' : (res['message'] ?? 'fehlgeschlagen')}';
      } else {
        final res = await widget.apiService.sendMail(
          to: ziel,
          subject: kuendigungBetreff(d),
          body: kuendigungBrieftext(d, alsBrief: false),
          // ⚠️ Lesebestätigung angefordert. Sie beweist den Zugang nicht,
          // aber sie ist der einzige Beleg, den dieser Weg überhaupt
          // hergibt — und sie kostet nichts.
          requestReceipt: true,
        );
        ok = res['success'] == true;
        zeile =
            'E-Mail an $ziel: '
            '${ok ? 'abgeschickt' : (res['message'] ?? 'fehlgeschlagen')}';
      }
    } catch (e) {
      zeile = weg == 'fax' ? 'Fax an $ziel: $e' : 'E-Mail an $ziel: $e';
    }

    if (!mounted) return;
    setState(() {
      _sendet = false;
      _protokoll.add('${_heute()} — $zeile');
    });

    if (ok) {
      // ⚠️ Sofort ablegen und am Vertrag festhalten. Eine Kündigung, die
      // raus ist, während der Vertrag noch als ungekündigt dasteht, ist
      // beim nächsten Öffnen ein Rätsel — und beim übernächsten ein
      // zweites Schreiben.
      await _inKorrespondenz(weg, ziel);
      await _amVertragFesthalten(weg);
      widget.onChanged?.call();
    } else {
      _melden(zeile, Colors.red);
    }
  }

  Future<void> _inKorrespondenz(String weg, String ziel) async {
    final d = _daten;
    final notiz = StringBuffer()
      ..writeln(weg == 'fax' ? 'Per Fax an $ziel' : 'Per E-Mail an $ziel')
      ..writeln(
        'Automatisch abgelegt beim Versand aus der elektronischen '
        'Kündigung.',
      )
      ..writeln();
    if (weg == 'fax') {
      // Gehört an den Vorgang, nicht nur auf den Bildschirm: wer den
      // Eintrag später liest, soll nicht glauben, der Zugang sei belegt.
      notiz
        ..writeln(
          '⚠️ Der „OK"-Vermerk des Sendeberichts ist nach der '
          'Rechtsprechung des BGH kein Anscheinsbeweis für den Zugang.',
        )
        ..writeln();
    }
    // Der WORTLAUT, nicht ein Vermerk „wurde gefaxt". Beim Anbieter ist der
    // Verlauf nach Monaten gelöscht; unsere Akte muss den Text selbst tragen.
    notiz.writeln(kuendigungBrieftext(d));
    try {
      await widget.apiService.saveVertraegeKorrespondenz({
        'vertrag_id': widget.vertragId,
        'richtung': 'ausgang',
        'methode': weg == 'fax' ? 'fax' : 'email',
        'datum': DateTime.now().toIso8601String().substring(0, 10),
        'betreff': kuendigungBetreff(d),
        'notiz': notiz.toString(),
      });
    } catch (_) {
      _melden(
        'Versand ok, Ablage in der Korrespondenz fehlgeschlagen.',
        Colors.orange,
      );
    }
  }

  /// Schreibt `gekuendigt_am` und den Weg an den Vertrag.
  ///
  /// ⚠️ Der Endpunkt setzt JEDES nicht gesendete Feld auf NULL
  /// (`$vals[$f] = $input[$f] ?? null`). Deshalb geht die ganze Zeile
  /// zurück, nicht nur die zwei geänderten Felder — sonst wären nach einer
  /// Kündigung Tarif, Beginn und Kosten weg.
  Future<void> _amVertragFesthalten(String weg) async {
    final v = Map<String, dynamic>.from(widget.vertrag);
    final heute = DateTime.now().toIso8601String().substring(0, 10);
    try {
      await widget.apiService.saveVertrag(widget.userId, {
        'id': widget.vertragId,
        'kategorie': v['kategorie'],
        'versicherung_id': v['versicherung_id'],
        'anbieter': v['anbieter'],
        'vertragsnummer': _nummer.text.trim(),
        'kundennummer': v['kundennummer'],
        'tarif': v['tarif'],
        'monatliche_kosten': v['monatliche_kosten'],
        'vertragsbeginn': v['vertragsbeginn'],
        'mindestlaufzeit': v['mindestlaufzeit'],
        'kuendigungsfrist': v['kuendigungsfrist'],
        'gekuendigt_am': heute,
        'vertragsende': v['vertragsende'],
        'telefonnummer': v['telefonnummer'],
        'datenvolumen': v['datenvolumen'],
        'login_email': v['login_email'],
        'shared_account':
            v['shared_account'] == 1 || v['shared_account'] == true,
        'notizen': v['notizen'],
        'is_active': v['is_active'] == 1 || v['is_active'] == true,
      });
      if (mounted) {
        setState(() {
          widget.vertrag['gekuendigt_am'] = heute;
          widget.vertrag['vertragsnummer'] = _nummer.text.trim();
        });
      }
    } catch (_) {
      _melden(
        'Versand ok, aber „Gekündigt am" konnte nicht gespeichert '
        'werden.',
        Colors.orange,
      );
    }
    // `weg` bleibt vorerst nur in der Korrespondenz — `kuendigung_methode`
    // gehört einem Dokument, nicht dem Vertrag, und wird von der
    // Kündigungs-Chronologie gepflegt.
  }

  void _melden(String text, Color farbe) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: farbe,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<bool?> _vorschau(String weg, String ziel) {
    final d = _daten;
    final istFax = weg == 'fax';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(
              istFax ? Icons.fax : Icons.email_outlined,
              color: F.h(Colors.red, 700),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                istFax ? 'Vorschau — Fax' : 'Vorschau — E-Mail',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _vorschauZeile(istFax ? 'Fax an' : 'E-Mail an', ziel),
                _vorschauZeile('Empfänger', d.empfaengerName),
                _vorschauZeile('Betreff', kuendigungBetreff(d)),
                const Divider(height: 18),
                SelectableText(
                  kuendigungBrieftext(d, alsBrief: istFax),
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: F.h(Colors.red, 50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: F.h(Colors.red, 200)),
                  ),
                  child: Text(
                    'Eine Kündigung lässt sich nicht zurückholen. Prüfen Sie '
                    '${d.nummerLabel} und Empfänger, bevor Sie senden.',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.red, 800)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(istFax ? Icons.fax : Icons.send, size: 16),
            label: Text(istFax ? 'Fax jetzt senden' : 'E-Mail jetzt senden'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          ),
        ],
      ),
    );
  }

  Widget _vorschauZeile(String label, String wert) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            '$label:',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
          ),
        ),
        Expanded(
          child: Text(
            wert.isEmpty ? '—' : wert,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  // ================= Oberfläche =================

  @override
  Widget build(BuildContext context) {
    if (_laedt) return const Center(child: CircularProgressIndicator());
    final gekuendigt = (widget.vertrag['gekuendigt_am']?.toString() ?? '')
        .trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.send_and_archive,
                size: 18,
                color: F.h(Colors.red, 700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Elektronische Kündigung',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: F.h(Colors.red, 800),
                  ),
                ),
              ),
            ],
          ),
          if (gekuendigt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _hinweis(
                Colors.orange,
                Icons.info_outline,
                'Dieser Vertrag ist bereits als gekündigt vermerkt',
                'Gekündigt am $gekuendigt. Ein zweites Schreiben ist meist '
                    'unnötig — prüfen Sie erst die Korrespondenz.',
              ),
            ),
          const SizedBox(height: 12),

          _abschnitt('Vertrag'),
          TextField(
            controller: _nummer,
            decoration: InputDecoration(
              labelText: '$_nummerLabel *',
              helperText: _kategorie == 'versicherung'
                  ? 'Steht auf dem Versicherungsschein und auf jeder '
                        'Beitragsrechnung.'
                  : 'Ohne sie kann der Empfänger die Kündigung keinem Vertrag '
                        'zuordnen.',
              helperMaxLines: 2,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _lesefeld('Vertragsgegenstand', _bezeichnung),
          _lesefeld(
            'Vertragsinhaber',
            [
              _absenderName,
              _absenderStrasse,
              _absenderPlzOrt,
            ].where((x) => x.isNotEmpty).join(', '),
          ),

          const SizedBox(height: 16),
          _abschnitt('Empfänger'),
          _feld(_empfName, 'Name'),
          _feld(_empfStrasse, 'Straße'),
          _feld(_empfPlzOrt, 'PLZ und Ort'),
          Row(
            children: [
              Expanded(child: _feld(_empfFax, 'Fax')),
              const SizedBox(width: 8),
              Expanded(child: _feld(_empfMail, 'E-Mail')),
            ],
          ),

          const SizedBox(height: 16),
          _abschnitt('Kündigung'),
          RadioGroup<KuendigungsArt>(
            groupValue: _art,
            onChanged: (v) => setState(() => _art = v ?? _art),
            child: Column(
              children: [
                _radio(
                  KuendigungsArt.naechstmoeglich,
                  'Zum nächstmöglichen Termin',
                  'Sicher, wenn das Ablaufdatum nicht feststeht — kann keine '
                      'Frist reißen.',
                ),
                _radio(
                  KuendigungsArt.zumDatum,
                  'Zu einem bestimmten Datum',
                  'Nur wählen, wenn das Datum aus dem Vertrag belegt ist.',
                ),
                _radio(
                  KuendigungsArt.ausserordentlich,
                  'Außerordentlich',
                  'Sonderkündigungsrecht, z. B. nach Beitragserhöhung oder '
                      'Schadenfall.',
                ),
              ],
            ),
          ),
          if (_art == KuendigungsArt.zumDatum) ...[
            const SizedBox(height: 8),
            _feld(_zumDatum, 'Zum Datum (TT.MM.JJJJ)'),
          ],
          if (_art == KuendigungsArt.ausserordentlich) ...[
            const SizedBox(height: 8),
            _feld(_grund, 'Grund *'),
          ],
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _sepa,
            onChanged: (v) => setState(() => _sepa = v ?? true),
            title: const Text(
              'SEPA-Lastschriftmandat mitwiderrufen',
              style: TextStyle(fontSize: 12),
            ),
            subtitle: Text(
              'Wirkt erst zum Vertragsende — offene Beiträge bleiben fällig.',
              style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
            ),
          ),

          const SizedBox(height: 8),
          _abschnitt('Unterschrift'),
          RadioGroup<KuendigungsUnterzeichner>(
            groupValue: _wer,
            onChanged: (v) => setState(() => _wer = v ?? _wer),
            child: Column(
              children: [
                _radioWer(
                  KuendigungsUnterzeichner.mitglied,
                  'Das Mitglied unterschreibt selbst',
                  'Empfohlen. § 174 BGB spielt dann keine Rolle.',
                ),
                _radioWer(
                  KuendigungsUnterzeichner.verein,
                  'Der Verein unterschreibt als Bevollmächtigter',
                  'Nur mit Vollmacht — siehe Warnung unten.',
                ),
              ],
            ),
          ),
          if (_wer == KuendigungsUnterzeichner.verein)
            _hinweis(
              Colors.red,
              Icons.warning_amber,
              '§ 174 S. 1 BGB — Zurückweisung möglich',
              'Eine Kündigung ist ein einseitiges Rechtsgeschäft. Legt der '
                  'Bevollmächtigte keine Vollmachtsurkunde vor, darf der '
                  'Empfänger sie unverzüglich zurückweisen — und per Fax oder '
                  'E-Mail lässt sich ein Original nicht vorlegen. Schicken Sie '
                  'in diesem Fall zusätzlich Einschreiben mit Rückschein und der '
                  'Vollmacht im Original, oder lassen Sie das Mitglied selbst '
                  'unterschreiben.',
            ),

          const SizedBox(height: 12),
          TextField(
            controller: _zusatz,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Zusätzliche Sätze (optional)',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _sendet ? null : _pdfAnsehen,
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('PDF erzeugen und ansehen'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sendet ? null : () => _senden('email'),
                  icon: const Icon(Icons.email, size: 18),
                  label: const Text('Per E-Mail senden'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sendet ? null : () => _senden('fax'),
                  icon: const Icon(Icons.fax, size: 18),
                  label: const Text('Per Fax senden'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                  ),
                ),
              ),
            ],
          ),
          if (_sendet)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),

          const SizedBox(height: 8),
          Text(
            'Fax und E-Mail sind bewusst zwei Knöpfe. Wer beide Wege will, '
            'drückt beide — dann steht jeder Weg einzeln im Protokoll.',
            style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
          ),

          if (_protokoll.isNotEmpty) ...[
            const SizedBox(height: 16),
            _abschnitt('Versandprotokoll'),
            for (final z in _protokoll)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 13,
                      color: F.h(Colors.grey, 600),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(z, style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Der Wortlaut jedes abgeschickten Schreibens liegt im Reiter '
              'Korrespondenz — das Protokoll hier lebt nur in dieser Sitzung.',
              style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _abschnitt(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: F.h(Colors.grey, 700),
      ),
    ),
  );

  Widget _feld(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );

  Widget _lesefeld(String label, String wert) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
          ),
        ),
        Expanded(
          child: Text(
            wert.isEmpty ? '—' : wert,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _radio(KuendigungsArt wert, String titel, String unter) =>
      RadioListTile<KuendigungsArt>(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: wert,
        title: Text(titel, style: const TextStyle(fontSize: 12)),
        subtitle: Text(
          unter,
          style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
        ),
      );

  Widget _radioWer(KuendigungsUnterzeichner wert, String titel, String unter) =>
      RadioListTile<KuendigungsUnterzeichner>(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: wert,
        title: Text(titel, style: const TextStyle(fontSize: 12)),
        subtitle: Text(
          unter,
          style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
        ),
      );

  Widget _hinweis(
    MaterialColor farbe,
    IconData icon,
    String titel,
    String text,
  ) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: F.h(farbe, 50),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: F.h(farbe, 300)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: F.h(farbe, 700)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: F.h(farbe, 900),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(fontSize: 11, color: F.h(farbe, 900)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
