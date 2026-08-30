/// Der Reiter „Vollmacht" unter Behörde ▸ Krankenkasse.
///
/// ⚠️ EIGENE Datei, nicht in `behorde_krankenkasse.dart`: die ist mit 5363
/// Zeilen schon jetzt kaum noch zu übersehen, und der Pflegegrad-Teil liegt
/// aus demselben Grund längst daneben.
///
/// 🟢 Gilt für JEDE gesetzliche Krankenkasse. Welche zuständig ist, steht im
/// Reiter „Zuständige Krankenkasse" desselben Bildschirms; hier steht kein
/// Kassenname. Die Daten des Mitglieds kommen aus der Verifizierung Stufe 1,
/// die des Vereins aus den Vereinseinstellungen — beides holt der Server, der
/// Bildschirm tippt nichts nach.
///
/// ⚠️ NICHT für eine private Krankenversicherung. Dort ist der Versicherer
/// kein Sozialleistungsträger; § 13 SGB X und § 73 Abs. 2 SGG greifen nicht.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/signatur_service.dart';
import '../utils/app_farben.dart';
import 'file_viewer_dialog.dart';
import 'vollmacht_link_aktionen.dart';

/// Die drei Bereiche — Schlüssel identisch mit `kkVollmachtBereiche()` auf dem
/// Server.
///
/// ⚠️ Der Server lehnt einen unbekannten Schlüssel nicht ab, er ignoriert ihn:
/// das Kästchen wäre angekreuzt und im PDF leer. Deshalb kommen die
/// BESCHRIFTUNGEN mit der Antwort von `vollmacht_data.php` (`bereiche_katalog`)
/// — der Bildschirm darf nichts anbieten, was im PDF nicht steht.
const List<String> kKkBereiche = ['leistungen', 'mitgliedschaft', 'pflege'];

/// Der Behördenschlüssel — er steht in `member_vollmachten.behoerde` und in den
/// beiden Positivlisten von `vollmacht_data.php` und `vollmacht_create.php`.
const String kKkBehoerde = 'krankenkasse';

/// Der Dokumenttyp des Unterschriftsvorgangs.
///
/// ⚠️ Landet als Text in `dokument_signaturen.dokument_typ`. Ein Tippfehler
/// fällt nirgends auf: der Vorgang entsteht, wird unterschrieben und gesiegelt
/// — nur wiederfinden lässt er sich nicht mehr unter dem Namen, unter dem ihn
/// jemand sucht.
const String kKkDokumentTyp = 'krankenkasse_vollmacht';

/// Trägt das PDF dieser Vollmacht eine Zeile für den Vorstand?
///
/// 🔴 Erste Quelle ist `unterschrift_felder` — sie beschreibt das ERZEUGTE
/// Blatt, geschrieben während des Zeichnens. Zweite Quelle ist die Ankreuzung
/// in `options_json`, aus der die Zeile überhaupt entstanden ist.
///
/// ⚠️ Bis zum 30.08.2026 lieferte `vollmacht_list.php` `unterschrift_felder`
/// gar nicht mit. Der Wert war immer leer, und wer daraus „kein Vorstand"
/// schloss, stellte die Vollmacht nur dem Mitglied zur Unterschrift —
/// während dessen Zeile auf dem Blatt gedruckt stand. Kein Fehler, keine
/// Meldung, die Vollmacht wurde nur nie fertig. Deshalb hat diese Funktion
/// zwei Quellen und keinen stillen Rückfall.
///
/// ⚠️ Fehlen beide (Zeilen aus der Zeit vor diesem Reiter), gilt die bisherige
/// Regel: zwei Unterschriften. Nichts darf hierdurch leichter fertig werden
/// als vorher.
bool kkBrauchtVorstand(Map<String, dynamic> v) {
  final felder = '${v['unterschrift_felder'] ?? ''}'.trim();
  if (felder.isNotEmpty) return felder.contains('bevollmaechtigter');
  // ⚠️ `jsonDecode('')` wirft eine FormatException — und eine Funktion, die
  // entscheidet, WER unterschreiben muss, darf nicht abstürzen, sondern muss
  // auf die vorsichtige Antwort fallen. Vom Test gefunden, nicht im Betrieb.
  Map opt = const {};
  final roh = v['options_json'];
  if (roh is Map) {
    opt = roh;
  } else if (roh is String && roh.trim().isNotEmpty) {
    try {
      final d = jsonDecode(roh);
      if (d is Map) opt = d;
    } on FormatException {
      return true;
    }
  }
  final u = opt['unterschriften'];
  if (u is Map && u.containsKey('vorstand')) return u['vorstand'] == true;
  return true;
}

/// Ein Bereich steht in GENAU EINER der beiden Spalten.
///
/// ⚠️ Als freie Funktion, damit die Regel prüfbar ist. Sie steht ein zweites
/// Mal auf dem Server (`vollmacht_krankenkasse_lib.php`), und dort ist sie die
/// verbindliche — hier sorgt sie nur dafür, dass der Bildschirm nicht etwas
/// anderes zeigt, als gleich im PDF steht. Wer sie hier ändert, ändert sie
/// dort mit.
///
/// ⚠️ Stufe A (handeln) schließt die Auskunft ein. Stünde ein Bereich in
/// beiden Spalten, sagte das Blatt zugleich „darf handeln" und „ausschließlich
/// Auskunft" — und die Kasse müsste raten, was gilt.
void kkBereichWaehlen(
  Map<String, bool> handeln,
  Map<String, bool> auskunft,
  String bereich, {
  required bool inSpalteA,
  required bool an,
}) {
  if (inSpalteA) {
    handeln[bereich] = an;
    if (an) auskunft[bereich] = false;
  } else {
    auskunft[bereich] = an;
    if (an) handeln[bereich] = false;
  }
}

class KrankenkasseVollmachtTab extends StatefulWidget {
  final ApiService apiService;
  final User user;
  final String adminMitgliedernummer;

  /// Meldet die Zahl der Vollmachten an den Reiter darüber.
  ///
  /// ⚠️ Der Reiter zeigt sie als Plakette. Ohne diesen Rückruf stünde dort
  /// für immer nichts, während darunter drei Vollmachten liegen — eine Zahl,
  /// die etwas anderes behauptet als der Inhalt, ist schlimmer als keine.
  final void Function(int)? onCountChanged;

  /// Vorgeladene Antwort statt eines Serveraufrufs — NUR zum Ansehen der Seite.
  ///
  /// ⚠️ Ohne diese Naht lässt sich der Reiter gar nicht zeichnen: `ApiService`
  /// ist ein Singleton mit privatem Konstruktor, also nicht zu ersetzen, und
  /// ohne Netz bleibt beim Rendern nur die Fehleransicht übrig. Genau das
  /// Formular, in dem die Ankreuzungen stehen, bekäme man nie zu Gesicht — und
  /// bei jeder bisherigen Sitzung hat erst das Ansehen der fertigen Seite die
  /// Fehler gezeigt, die im Code nicht zu erkennen waren.
  ///
  /// ⚠️ Sie ersetzt NUR das Laden. Alles darunter — Kataloge, Ausschluss der
  /// zweiten Spalte, Knöpfe — ist derselbe Code wie im Betrieb.
  @visibleForTesting
  final Map<String, dynamic>? vorschauDaten;

  /// Vorgeladene Vollmachtsliste — ebenfalls nur zum Ansehen der Seite.
  @visibleForTesting
  final List<Map<String, dynamic>>? vorschauListe;

  /// Vorgeladene Unterschriftsvorgänge — nur zum Ansehen der Seite.
  @visibleForTesting
  final Map<int, List<Signaturvorgang>>? vorschauSignaturen;

  const KrankenkasseVollmachtTab({
    super.key,
    required this.apiService,
    required this.user,
    required this.adminMitgliedernummer,
    this.onCountChanged,
    this.vorschauDaten,
    this.vorschauListe,
    this.vorschauSignaturen,
  });

  @override
  State<KrankenkasseVollmachtTab> createState() => _KrankenkasseVollmachtTabState();
}

class _KrankenkasseVollmachtTabState extends State<KrankenkasseVollmachtTab> {
  static const _farbe = Colors.teal;

  bool _laedt = true;
  String? _fehler;
  Map<String, dynamic> _daten = {};
  List<Map<String, dynamic>> _liste = [];

  /// Unterschriftsvorgänge je Vollmacht-Id.
  ///
  /// 🔴 Ohne sie zeigte die Karte NICHTS über die Unterschriften — nicht wer
  /// unterschrieben hat, nicht wann, und es gab keinen Weg, die gesiegelte
  /// Fassung zu öffnen. Am 30.08.2026 hatten beide Seiten eine Vollmacht
  /// unterschrieben und gesiegelt, und auf dem Schirm war davon nichts zu
  /// sehen.
  ///
  /// ⚠️ Gezählt wird über die GRUPPE, nicht über die gelieferten Zeilen:
  /// `SignaturService.liste` steht unter EINEM Mitglied, die Zeile des
  /// Vorstands trägt eine andere `user_id`. Über die Zeilen gezählt käme
  /// „1 von 1" heraus, wo zwei angefordert sind.
  Map<int, List<Signaturvorgang>> _signaturen = {};

  // Ankreuzungen der Erstellung.
  final Map<String, bool> _handeln = {for (final b in kKkBereiche) b: false};
  final Map<String, bool> _auskunft = {for (final b in kKkBereiche) b: false};
  final Map<String, bool> _umfang = {};
  final Map<String, bool> _online = {};
  bool _post = false;
  bool _widerrufAlt = false;
  bool _vorstandUnterschreibt = false;
  DateTime _gueltigAb = DateTime.now();
  DateTime? _gueltigBis;

  int? _erzeugt;
  int? _stelltZu;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  int _vid(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

  void _melden(String text, Color farbe) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text), backgroundColor: farbe,
      duration: const Duration(seconds: 6)));
  }

  Future<void> _laden() async {
    final vorschau = widget.vorschauDaten;
    if (vorschau != null) {
      setState(() {
        _daten = Map<String, dynamic>.from(vorschau);
        _liste = widget.vorschauListe ?? const [];
        _signaturen = widget.vorschauSignaturen ?? const {};
        _laedt = false;
      });
      return;
    }
    setState(() { _laedt = true; _fehler = null; });
    try {
      final d = await widget.apiService.getVollmachtData(widget.user.id, kKkBehoerde);
      final l = await widget.apiService.listVollmachten(widget.user.id, kKkBehoerde);
      if (!mounted) return;
      if (d['success'] != true) {
        setState(() { _laedt = false; _fehler = (d['message'] ?? 'Daten nicht abrufbar').toString(); });
        return;
      }
      // ⚠️ Die Mitgliedsnummer des Anfordernden ist der Identitätsnachweis.
      // Fehlt sie, bleibt die Liste ohne Unterschriftsstand — lieber keine
      // Angabe als eine erfundene.
      final sigs = <int, List<Signaturvorgang>>{};
      final anf = widget.adminMitgliedernummer.trim();
      if (anf.isNotEmpty) {
        for (final s in await SignaturService()
            .liste(callerMitgliedernummer: anf, userId: widget.user.id)) {
          if (s.quelleTabelle != 'member_vollmachten' || s.quelleId == null) continue;
          sigs.putIfAbsent(s.quelleId!, () => []).add(s);
        }
      }
      final roh = (l['vollmachten'] ?? l['items'] ?? const []);
      setState(() {
        _daten = Map<String, dynamic>.from(d);
        _liste = roh is List
            ? roh.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];
        _signaturen = sigs;
        _laedt = false;
      });
      widget.onCountChanged?.call(_liste.length);
    } catch (e) {
      if (mounted) {
        setState(() { _laedt = false; _fehler = '$e'; });
      }
    }
  }

  Map<String, dynamic> get _recht =>
      _daten['recht'] is Map ? Map<String, dynamic>.from(_daten['recht']) : {};

  /// Beschriftungen aus der Serverantwort — nie aus einer Kopie hier.
  Map<String, String> _katalog(String schluessel) {
    final k = _recht[schluessel];
    if (k is! Map) return {};
    return {for (final e in k.entries) '${e.key}': '${e.value}'};
  }

  String get _kasse {
    final k = _daten['kasse'];
    if (k is Map) return '${k['name'] ?? ''}'.trim();
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (_laedt) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_fehler != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, color: F.h(Colors.red, 400), size: 40),
          const SizedBox(height: 10),
          Text(_fehler!, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _laden,
            icon: const Icon(Icons.refresh, size: 16), label: const Text('Erneut laden')),
        ])));
    }

    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: F.h(_farbe, 50),
          child: TabBar(
            labelColor: F.h(_farbe, 800),
            unselectedLabelColor: F.h(Colors.grey, 600),
            indicatorColor: F.h(_farbe, 700),
            tabs: [
              const Tab(icon: Icon(Icons.add_circle_outline, size: 18), text: 'Erstellen'),
              Tab(icon: const Icon(Icons.history, size: 18),
                  text: 'Verlauf (${_liste.length})'),
            ])),
        Expanded(child: TabBarView(children: [
          _erstellen(),
          _verlauf(),
        ])),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  Erstellen
  // ══════════════════════════════════════════════════════════════════

  Widget _kopf(IconData symbol, String titel, {String? unter}) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(symbol, size: 17, color: F.h(_farbe, 700)),
        const SizedBox(width: 7),
        Expanded(child: Text(titel, style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold, color: F.h(_farbe, 800)))),
      ]),
      if (unter != null) Padding(
        padding: const EdgeInsets.only(top: 3, left: 24),
        child: Text(unter, style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700)))),
    ]));

  Widget _hinweis(String text, {MaterialColor? ton, IconData symbol = Icons.info_outline}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: F.h(ton ?? Colors.blue, 50),
      border: Border.all(color: F.h(ton ?? Colors.blue, 200)),
      borderRadius: BorderRadius.circular(8)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(symbol, size: 15, color: F.h(ton ?? Colors.blue, 700)),
      const SizedBox(width: 7),
      Expanded(child: Text(text, style: TextStyle(
        fontSize: 11.5, color: F.h(ton ?? Colors.blue, 900)))),
    ]));

  Widget _erstellen() {
    final bereiche = _katalog('bereiche_katalog');
    final umfang   = _katalog('umfang_katalog');
    final online   = _katalog('online_katalog');
    final nurBeiHandeln = (_recht['nur_bei_handeln'] is List)
        ? (_recht['nur_bei_handeln'] as List).map((e) => '$e').toSet()
        : <String>{};
    final darfHandeln = _handeln.values.any((v) => v);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Für welche Kasse ─────────────────────────────────────────
        //
        // ⚠️ Steht GANZ OBEN. Niemand soll eine Vollmacht für eine Kasse
        // ausstellen, während im Reiter daneben eine andere eingetragen ist.
        if (_kasse.isEmpty)
          _hinweis('Im Reiter „Zuständige Krankenkasse" ist keine Kasse eingetragen. '
              'Die Vollmacht kann trotzdem erzeugt werden, nennt dann aber keine '
              'Kasse — und ein Blatt ohne Adressaten nimmt niemand entgegen.',
              ton: Colors.orange, symbol: Icons.warning_amber_outlined)
        else
          _hinweis('Diese Vollmacht wird für „$_kasse" ausgestellt, samt der bei ihr '
              'errichteten Pflegekasse (§ 46 Abs. 1 SGB XI).', ton: Colors.teal),

        _kopf(Icons.gavel, 'Rechtsgrundlage'),
        Text('${_recht['norm'] ?? '§ 13 Abs. 1 SGB X'} · '
             '${_recht['vertretung_norm'] ?? ''}',
          style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),

        // ── Stufe A ──────────────────────────────────────────────────
        _kopf(Icons.edit_note, 'A. Auskunft UND Handeln',
          unter: 'Der Verein darf in diesen Bereichen Auskünfte bekommen und handeln — '
                 'zum Beispiel Anträge stellen.'),
        for (final b in kKkBereiche)
          CheckboxListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: F.h(_farbe, 700),
            value: _handeln[b] ?? false,
            title: Text(bereiche[b] ?? b, style: const TextStyle(fontSize: 13)),
            // ⚠️ Ein Bereich steht in GENAU EINER Spalte. Das Kreuz hier nimmt
            // das Kreuz drüben weg — der Server tut dasselbe, aber wer es erst
            // im fertigen PDF sieht, hat etwas anderes angekreuzt als gemeint.
            onChanged: (v) => setState(() => kkBereichWaehlen(
              _handeln, _auskunft, b, inSpalteA: true, an: v ?? false))),

        // ── Stufe B ──────────────────────────────────────────────────
        _kopf(Icons.visibility_outlined, 'B. Ausschließlich Auskunft',
          unter: 'Nur Auskünfte, kein Handeln.'),
        for (final b in kKkBereiche)
          CheckboxListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: F.h(_farbe, 700),
            value: _auskunft[b] ?? false,
            title: Text(bereiche[b] ?? b, style: const TextStyle(fontSize: 13)),
            onChanged: (v) => setState(() => kkBereichWaehlen(
              _handeln, _auskunft, b, inSpalteA: false, an: v ?? false))),

        // ── Was der Verein dort tun darf ─────────────────────────────
        _kopf(Icons.checklist, 'In den angekreuzten Bereichen'),
        for (final e in umfang.entries)
          if (!(nurBeiHandeln.contains(e.key) && !darfHandeln))
            CheckboxListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: F.h(_farbe, 700),
              value: _umfang[e.key] ?? false,
              title: Text(e.value, style: const TextStyle(fontSize: 12.5)),
              onChanged: (v) => setState(() => _umfang[e.key] = v ?? false)),
        if (!darfHandeln && nurBeiHandeln.isNotEmpty)
          _hinweis('Anträge und Widerspruch stehen erst zur Wahl, wenn oben unter A '
              'mindestens ein Bereich angekreuzt ist — wer nur Auskunft bekommt, '
              'stellt keine Anträge.', ton: Colors.grey),

        // ── Online-Konto ─────────────────────────────────────────────
        _kopf(Icons.computer, 'Online-Konto der Kasse',
          unter: 'Der Verein verwaltet das Konto — das Mitglied behält seinen '
                 'eigenen Zugang.'),
        for (final e in online.entries)
          CheckboxListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: F.h(_farbe, 700),
            value: _online[e.key] ?? false,
            title: Text(e.value, style: const TextStyle(fontSize: 12.5)),
            onChanged: (v) => setState(() => _online[e.key] = v ?? false)),
        _hinweis('Die elektronische Patientenakte (ePA) ist NICHT dabei. Eine Vertretung '
            'dafür benennt das Mitglied ausschließlich in der ePA selbst '
            '(§ 343 SGB V); die Kasse hat auf deren Inhalte keinen Zugriff.',
            ton: Colors.orange, symbol: Icons.folder_off_outlined),

        // ── Postvollmacht ────────────────────────────────────────────
        _kopf(Icons.markunread_mailbox_outlined, 'Postvollmacht'),
        CheckboxListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: F.h(Colors.orange, 700),
          value: _post,
          title: const Text('Die Post der Kasse geht nur noch an den Verein',
            style: TextStyle(fontSize: 13)),
          subtitle: Text(_post
              ? 'Das Mitglied bekommt dann keine Briefe der Kasse mehr.'
              : 'Ohne dieses Kreuz bekommt das Mitglied seine Post wie bisher.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
          onChanged: (v) => setState(() => _post = v ?? false)),

        // ⚠️ EIGENE Überschrift. Auf der gerenderten Seite stand dieses Kreuz
        // unter „Postvollmacht" und las sich wie ein Teil davon — es hat damit
        // nichts zu tun: es löscht alle früheren Vollmachten gegenüber dieser
        // Kasse. Im Code war nichts zu sehen, erst auf dem Bild.
        _kopf(Icons.cancel_outlined, 'Frühere Vollmachten'),
        CheckboxListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: F.h(Colors.red, 700),
          value: _widerrufAlt,
          title: const Text('Frühere Vollmachten gegenüber dieser Kasse widerrufen',
            style: TextStyle(fontSize: 13)),
          subtitle: Text(_widerrufAlt
              ? 'Im Blatt steht dann ausdrücklich, dass alle bisher erteilten '
                'Vollmachten gegenüber dieser Kasse erlöschen.'
              : 'Ohne dieses Kreuz bleiben frühere Vollmachten unberührt.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
          onChanged: (v) => setState(() => _widerrufAlt = v ?? false)),

        // ── Unterschriften ───────────────────────────────────────────
        _kopf(Icons.draw_outlined, 'Unterschriften'),
        _hinweis('Die Kassen verlangen allein die Unterschrift des Mitglieds — die '
            'Vollmacht ist eine einseitige Erklärung (§ 167 Abs. 1 BGB). Geprüft an '
            'den Formularen von TK, AOK und BARMER.', ton: Colors.teal),
        CheckboxListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: F.h(_farbe, 700),
          value: _vorstandUnterschreibt,
          title: const Text('Zusätzlich vom Vorstand unterschreiben lassen',
            style: TextStyle(fontSize: 13)),
          subtitle: Text('Nur nötig, wenn eine Kasse es ausdrücklich verlangt. '
              'Solange die Unterschrift fehlt, bleibt die Vollmacht unfertig.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
          onChanged: (v) => setState(() => _vorstandUnterschreibt = v ?? false)),

        // ── Gültigkeit ───────────────────────────────────────────────
        _kopf(Icons.event, 'Gültigkeit'),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.today, size: 15),
            label: Text('ab ${_datum(_gueltigAb)}', style: const TextStyle(fontSize: 12)),
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _gueltigAb,
                firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (d != null && mounted) setState(() => _gueltigAb = d);
            })),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.event_busy, size: 15),
            label: Text(_gueltigBis == null ? 'bis auf Widerruf' : 'bis ${_datum(_gueltigBis!)}',
              style: const TextStyle(fontSize: 12)),
            onPressed: () async {
              final d = await showDatePicker(context: context,
                initialDate: _gueltigBis ?? DateTime.now().add(const Duration(days: 365)),
                firstDate: _gueltigAb, lastDate: DateTime(2100));
              if (mounted) setState(() => _gueltigBis = d);
            })),
          if (_gueltigBis != null)
            IconButton(
              tooltip: 'Befristung entfernen',
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => setState(() => _gueltigBis = null)),
        ]),

        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: F.h(_farbe, 700), foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),
          icon: _erzeugt == -1
              ? const SizedBox(width: 15, height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf, size: 18),
          label: const Text('Vollmacht erzeugen'),
          onPressed: _erzeugt == -1 ? null : _erzeugen)),
      ]),
    );
  }

  static String _datum(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  /// ISO aus der Serverantwort als deutsches Datum — so, wie es auch im PDF
  /// steht. Zwei Schreibweisen für dasselbe Datum laden zum Vergleichen ein
  /// und wecken den Verdacht, es seien zwei verschiedene Angaben.
  static String _ausIso(dynamic roh) {
    final s = '${roh ?? ''}'.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    return m == null ? s : '${m[3]}.${m[2]}.${m[1]}';
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _erzeugen() async {
    // ⚠️ Ohne einen einzigen Bereich ist das Blatt eine Vollmacht über nichts.
    // Der Server lehnt es ebenfalls ab — hier steht der Grund, bevor der
    // Knopf gedrückt wird.
    if (!_handeln.values.any((v) => v) && !_auskunft.values.any((v) => v)) {
      _melden('Mindestens ein Bereich muss angekreuzt sein — unter A oder unter B.',
              Colors.orange);
      return;
    }
    setState(() => _erzeugt = -1);
    try {
      final r = await widget.apiService.createVollmacht({
        'user_id': widget.user.id,
        'behoerde': kKkBehoerde,
        'valid_from': _iso(_gueltigAb),
        if (_gueltigBis != null) 'valid_until': _iso(_gueltigBis!),
        'options': {
          'handeln': _handeln, 'auskunft': _auskunft,
          'umfang': _umfang, 'online': _online,
          'post': _post, 'widerruf_alt': _widerrufAlt,
          'unterschriften': {'vorstand': _vorstandUnterschreibt},
        },
      });
      if (!mounted) return;
      if (r['success'] == true) {
        final sprache = '${r['translation_language'] ?? ''}'.trim();
        _melden(sprache.isEmpty
            ? 'Vollmacht erzeugt — nur deutsche Fassung'
            : 'Vollmacht erzeugt — deutsche Fassung und Leseexemplar '
              '(${sprache.toUpperCase()})', Colors.green);
        await _laden();
      } else {
        _melden('${r['message'] ?? 'Erzeugung fehlgeschlagen'}', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _erzeugt = null);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  Verlauf
  // ══════════════════════════════════════════════════════════════════

  Widget _verlauf() {
    if (_liste.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(
        'Noch keine Vollmacht erzeugt.',
        style: TextStyle(color: F.h(Colors.grey, 500)))));
    }
    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _liste.length,
        itemBuilder: (_, i) => _karte(_liste[i])),
    );
  }

  Widget _karte(Map<String, dynamic> v) {
    final id = _vid(v['id']);
    var status = '${v['status'] ?? ''}';
    final widerrufen = status == 'revoked';
    final sprache = '${v['translation_language'] ?? ''}'.trim();
    final hatLeseexemplar = sprache.isNotEmpty
        && '${v['pdf_translation_filename'] ?? ''}'.trim().isNotEmpty;

    // 🔴 Die Plakette kommt aus `status`, die Zeile darunter aus der
    // Unterschriftsgruppe. Stimmen sie nicht überein, sagt die Karte zwei
    // entgegengesetzte Dinge — auf der gerenderten Seite stand oben „wartet
    // auf Unterschrift" und darunter „Von beiden unterschrieben".
    //
    // Maßgeblich ist die GRUPPE: sie ist der jüngere Stand. `status` zieht
    // erst nach, wenn jemand ihn neu berechnet, und `quelleAlsUnterzeichnet-
    // Merken` rührt eine Zeile gar nicht an, die schon weitergewandert ist.
    final gruppeFertig = _signiertVerfuegbar(id) != null;
    if (gruppeFertig && (status == 'draft' || status == 'wartet_unterschriften')) {
      status = 'unterzeichnet';
    }
    final (Color ton, String wort) = switch (status) {
      'aktiv'        => (Colors.green.shade700,  'aktiv'),
      'eingereicht'  => (Colors.blue.shade700,   'eingereicht'),
      'unterzeichnet'=> (Colors.teal.shade700,   'unterschrieben'),
      'wartet_unterschriften' => (Colors.orange.shade800, 'wartet auf Unterschrift'),
      'revoked'      => (Colors.red.shade700,    'widerrufen'),
      'expired'      => (Colors.grey,            'abgelaufen'),
      _              => (Colors.grey.shade700,   'Entwurf'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.assignment_ind, size: 17, color: ton),
            const SizedBox(width: 7),
            Expanded(child: Text('Vollmacht #$id',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: ton.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5)),
              child: Text(wort, style: TextStyle(fontSize: 10.5, color: ton))),
          ]),
          const SizedBox(height: 4),
          Text('gültig ab ${_ausIso(v['valid_from'])}'
               '${_ausIso(v['valid_until']).isEmpty
                    ? ' · bis auf Widerruf' : ' bis ${_ausIso(v['valid_until'])}'}',
            style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
          _unterschriftsstand(id),
          if (widerrufen && '${v['revoked_reason'] ?? ''}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(
              'Grund: ${v['revoked_reason']}',
              style: TextStyle(fontSize: 11, color: F.h(Colors.red, 700)))),

          const Divider(height: 18),

          // ── Ansehen ──────────────────────────────────────────────
          Wrap(spacing: 6, runSpacing: 4, children: [
            _knopf('Deutsche Fassung', Icons.picture_as_pdf,
                   () => _pdf(id, typ: 'pdf')),
            if (hatLeseexemplar)
              _knopf('Leseexemplar (${sprache.toUpperCase()})', Icons.translate,
                     () => _pdf(id, typ: 'translation')),
            // ⚠️ Nur, wenn es sie WIRKLICH gibt. Ein Knopf, der nichts tun
            // kann, ist schlimmer als keiner.
            if (_signiertVerfuegbar(id) != null)
              _knopf('Unterschriebene Fassung', Icons.verified,
                     () => _signiertOeffnen(id)),
          ]),

          const SizedBox(height: 10),
          // ── An das Mitglied ──────────────────────────────────────
          Text('An das Mitglied', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 4),
          VollmachtLinkKnoepfe(
            farbe: _farbe,
            widerrufen: widerrufen,
            signierbar: status == 'wartet_unterschriften',
            // ⚠️ Auf einer WIDERRUFENEN Vollmacht darf hier nicht stehen, man
            // solle erst zur Unterschrift stellen — diesen Weg gibt es dort
            // nicht mehr. Auf der gerenderten Seite stand genau das.
            signierHinweis: widerrufen
                ? 'Diese Vollmacht ist widerrufen — sie kann nicht mehr '
                  'unterschrieben werden.'
                : (status == 'wartet_unterschriften'
                    ? ''
                    : 'Erst „Zur Unterschrift stellen" drücken — der Link führt zu '
                      'einem offenen Vorgang, er legt keinen an.'),
            onSenden: (zweck) => widget.apiService
                .kkVollmachtLinkSenden(vollmachtId: id, zweck: zweck),
            onGesendet: _laden),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _knopf('In den Chat', Icons.chat_outlined,
                   widerrufen ? null : () => _inDenChat(v)),
            _knopf(_stelltZu == id ? 'läuft …' : 'Zur Unterschrift stellen', Icons.draw,
                   (widerrufen || _stelltZu != null) ? null : () => _zurUnterschrift(v)),
          ]),

          const SizedBox(height: 10),
          // ── An die Kasse ─────────────────────────────────────────
          Text('An die Kasse', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _knopf('Per E-Mail', Icons.mail_outline,
                   widerrufen ? null : () => _senden(id, fax: false)),
            _knopf('Per Fax', Icons.print_outlined,
                   widerrufen ? null : () => _senden(id, fax: true)),
            _knopf('Per Post eingetragen', Icons.markunread_mailbox_outlined,
                   widerrufen ? null : () => _postEintragen(id)),
            _knopf('Protokoll', Icons.receipt_long_outlined, () => _protokoll(id)),
          ]),
          // ⚠️ Steht DA, nicht in einem Tooltip: auf einem Telefon sieht einen
          // Tooltip niemand. Und es ist die Regel, nicht die Ausnahme.
          Padding(padding: const EdgeInsets.only(top: 5), child: Text(
            'Die meisten Kassen nehmen die Vollmacht nur per Post oder über ihr '
            'eigenes Portal an. Dann ausdrucken, verschicken und hier eintragen.',
            style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)))),

          if (!widerrufen) ...[
            const Divider(height: 18),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(
              icon: Icon(Icons.cancel_outlined, size: 15, color: F.h(Colors.red, 700)),
              label: Text('Widerrufen',
                style: TextStyle(fontSize: 12, color: F.h(Colors.red, 700))),
              onPressed: () => _widerrufen(id))),
          ],
        ])),
    );
  }

  /// Wie weit die Unterschriften sind — als Zeile auf der Karte.
  ///
  /// ⚠️ Über die GRUPPE gezählt (`gruppeSigniert`/`gruppeGesamt`), nicht über
  /// die gelieferten Zeilen. Die Zeile des Vorstands trägt eine andere
  /// `user_id` und ist beim Zählen über das Mitglied gar nicht dabei.
  Widget _unterschriftsstand(int id) {
    final vg = _signaturen[id] ?? const <Signaturvorgang>[];
    if (vg.isEmpty) return const SizedBox.shrink();
    final abgelehnt = vg.any((x) => x.status == 'abgelehnt');
    final fertig = vg.first.gruppeSigniert, gesamt = vg.first.gruppeGesamt;
    final alle = vg.first.gruppeVollstaendig;
    final ton = abgelehnt
        ? F.h(Colors.red, 700)
        : (alle ? F.h(Colors.green, 700) : F.h(Colors.orange, 800));
    return Padding(padding: const EdgeInsets.only(top: 4), child:
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(abgelehnt ? Icons.block
                       : (alle ? Icons.verified : Icons.hourglass_bottom),
             size: 14, color: ton),
        const SizedBox(width: 5),
        Expanded(child: Text(
          abgelehnt
              ? 'Unterschrift abgelehnt'
              : (alle
                  ? (gesamt > 1 ? 'Von beiden unterschrieben' : 'Unterschrieben')
                  : '$fertig von $gesamt unterschrieben'),
          style: TextStyle(fontSize: 11.5, color: ton))),
      ]));
  }

  /// Die gesiegelte Fassung — erst, wenn die ganze Gruppe unterschrieben hat.
  ///
  /// ⚠️ Ebenfalls über die Gruppe. Im Anwaltszweig hat genau dieser blinde
  /// Fleck dazu geführt, dass eine bereits unterschriebene Vollmacht
  /// widerrufen wurde, weil es aussah, als sei nichts geschehen.
  Signaturvorgang? _signiertVerfuegbar(int id) {
    final vg = _signaturen[id] ?? const <Signaturvorgang>[];
    if (vg.isEmpty || !vg.first.gruppeVollstaendig) return null;
    return vg.firstWhere((x) => x.istSigniert, orElse: () => vg.first);
  }

  Future<void> _signiertOeffnen(int id) async {
    final vorgang = _signiertVerfuegbar(id);
    if (vorgang == null) return;
    final bytes = await SignaturService().herunterladen(
      callerMitgliedernummer: widget.adminMitgliedernummer.trim(),
      signaturId: vorgang.id, welche: 'signiert');
    if (!mounted) return;
    if (bytes == null) {
      // Der Siegel-Cron läuft jede Minute. „Noch nicht da" ist kein Fehler,
      // aber es muss dastehen — sonst sucht jemand an der falschen Stelle.
      _melden('Die unterschriebene Fassung ist noch nicht gesiegelt — das '
              'geschieht wenige Minuten nach der letzten Unterschrift', Colors.orange);
      return;
    }
    await FileViewerDialog.showFromBytes(
        context, Uint8List.fromList(bytes), 'vollmacht_unterschrieben_$id.pdf');
  }

  Widget _knopf(String text, IconData symbol, VoidCallback? aktion) => OutlinedButton.icon(
    icon: Icon(symbol, size: 14),
    label: Text(text, style: const TextStyle(fontSize: 11)),
    style: OutlinedButton.styleFrom(
      foregroundColor: aktion == null ? F.h(Colors.grey, 500) : F.h(_farbe, 700),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    onPressed: aktion);

  Future<void> _pdf(int id, {required String typ}) async {
    final r = await widget.apiService.downloadVollmachtPdf(id, type: typ);
    if (!mounted) return;
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
      _melden('PDF konnte nicht geladen werden (${r.statusCode})', Colors.red);
      return;
    }
    await FileViewerDialog.showFromBytes(context, r.bodyBytes,
        typ == 'translation' ? 'vollmacht_leseexemplar_$id.pdf' : 'vollmacht_$id.pdf');
  }

  /// Das Leseexemplar in das Postfach DES MITGLIEDS.
  ///
  /// ⚠️ Es ist sein Recht zu wissen, was er unterschreibt. Unterschrieben und
  /// bei der Kasse eingereicht wird weiter allein die deutsche Fassung.
  Future<void> _inDenChat(Map<String, dynamic> v) async {
    final id = _vid(v['id']);
    final nummer = widget.user.mitgliedernummer.trim();
    final anf = widget.adminMitgliedernummer.trim();
    if (nummer.isEmpty || anf.isEmpty) {
      _melden('Empfänger nicht ermittelbar', Colors.red);
      return;
    }
    final sprache = '${v['translation_language'] ?? ''}'.trim();
    final uebersetzt = sprache.isNotEmpty
        && '${v['pdf_translation_filename'] ?? ''}'.trim().isNotEmpty;

    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('In den Chat senden?', style: TextStyle(fontSize: 16)),
      content: Text(uebersetzt
          ? 'Das Leseexemplar (${sprache.toUpperCase()}) geht an $nummer.\n\n'
            'Unterschrieben und bei der Kasse eingereicht wird weiter allein die '
            'deutsche Fassung — das steht auch auf jeder Seite des Leseexemplars.'
          : 'Die deutsche Fassung geht an $nummer.\n\n'
            'Ein Leseexemplar in der Sprache des Mitglieds gibt es für diese '
            'Vollmacht nicht. Der Verein erläutert den Inhalt mündlich.',
        style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: F.h(_farbe, 700), foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('Senden')),
      ]));
    if (ok != true || !mounted) return;

    File? temp;
    try {
      // ⚠️ Bei vorhandenem Leseexemplar wird GENAU DAS geholt. Ohne den Typ
      // ginge stillschweigend das deutsche Blatt hinaus, während der Dialog
      // eine Übersetzung angekündigt hat.
      final r = await widget.apiService
          .downloadVollmachtPdf(id, type: uebersetzt ? 'translation' : 'pdf');
      if (!mounted) return;
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _melden('Fehler (${r.statusCode})', Colors.red);
        return;
      }
      final g = await widget.apiService.adminStartChat(anf, nummer);
      final cid = int.tryParse('${g['conversation_id'] ?? ''}')
          ?? int.tryParse('${(g['data'] as Map?)?['conversation_id'] ?? ''}') ?? 0;
      if (cid <= 0) { _melden('Kein Gespräch mit $nummer gefunden', Colors.red); return; }

      temp = File('${(await getTemporaryDirectory()).path}/'
          'vollmacht_$id${uebersetzt ? '_$sprache' : ''}.pdf');
      await temp.writeAsBytes(r.bodyBytes, flush: true);
      final res = await widget.apiService.uploadChatAttachments(
        conversationId: cid, mitgliedernummer: anf, files: [temp],
        message: uebersetzt
            ? 'Vollmacht (Leseexemplar) — Krankenkasse'
            : 'Vollmacht — Krankenkasse');
      if (!mounted) return;
      final erfolg = res['success'] == true;
      // ⚠️ Erst jetzt protokollieren, nachdem der Server den Empfang bestätigt
      // hat. Vorher einzutragen hieße, eine Sendung zu behaupten, die
      // vielleicht nie ankam — und darauf verlässt sich später jemand.
      if (erfolg) {
        await widget.apiService.kkVollmachtVersandEintragen(
          vollmachtId: id, empfaenger: nummer, weg: 'chat',
          fassung: uebersetzt ? 'uebersetzung' : 'original',
          sprache: uebersetzt ? sprache : 'de');
      }
      if (!mounted) return;
      _melden(erfolg ? 'An $nummer gesendet' : 'Konnte nicht gesendet werden',
              erfolg ? Colors.green : Colors.red);
      if (erfolg) _laden();
    } catch (e) {
      if (mounted) _melden('Fehler: $e', Colors.red);
    } finally {
      if (temp != null && await temp.exists()) { await temp.delete(); }
    }
  }

  /// Stellt die Vollmacht zur Unterschrift.
  ///
  /// ⚠️ Immer die DEUTSCHE Fassung — sie ist die verbindliche. Das
  /// Leseexemplar trägt kein Unterschriftsfeld.
  ///
  /// ⚠️ Wer unterschreibt, steht in `unterschrift_felder` des PDF und damit in
  /// der Vollmacht selbst — nicht in einer Regel hier. Bei der Krankenkasse
  /// ist die zweite Unterschrift abwählbar.
  Future<void> _zurUnterschrift(Map<String, dynamic> v) async {
    final id = _vid(v['id']);
    final anf = widget.adminMitgliedernummer.trim();
    final vorsitzerId = _vid(v['vorsitzer_id']);
    if (anf.isEmpty) {
      _melden('Unterzeichner nicht ermittelbar — bitte die Liste neu laden', Colors.red);
      return;
    }
    // 🔴 WER unterschreiben muss, steht in `unterschrift_felder` — der
    // Erzeuger schreibt dort während des Zeichnens hinein, welche
    // Unterschriftsfelder das PDF wirklich trägt.
    //
    // ⚠️ Bis zum 30.08.2026 lieferte `vollmacht_list.php` diese Spalte gar
    // nicht mit. Der Wert war immer leer, `mitVorstand` immer false — und
    // damit wurde die Vollmacht nur dem Mitglied zur Unterschrift gestellt,
    // während die Zeile des Vorstands auf dem Blatt stand. Keine Meldung,
    // kein Fehler: die Vollmacht wurde einfach nie fertig.
    //
    // ⚠️ Deshalb wird hier NICHT mehr stillschweigend auf „nur das Mitglied"
    // zurückgefallen. Fehlt das Feld, entscheidet die Ankreuzung aus
    // `options_json` — dieselbe, aus der der Erzeuger die zweite Zeile
    // gedruckt hat.
    final mitVorstand = kkBrauchtVorstand(v) && vorsitzerId > 0;

    final los = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Zur Unterschrift stellen?', style: TextStyle(fontSize: 16)),
      content: Text(mitVorstand
          ? 'Die deutsche Fassung geht an beide Unterzeichner: an das Mitglied als '
            'Vollmachtgeber und an den Vorstand als Bevollmächtigten. Beide '
            'unterschreiben in ihrer eigenen App und bekommen einen Code auf ihre '
            'Mobilnummer.\n\nWirksam wird die Vollmacht erst, wenn beide '
            'unterschrieben haben.'
          : 'Die deutsche Fassung geht an das Mitglied. Es unterschreibt in seiner '
            'App oder über den SMS-Link und bekommt einen Code auf seine Mobilnummer.'
            '\n\nEine Unterschrift des Vereins ist nicht nötig — die Vollmacht ist '
            'eine einseitige Erklärung des Mitglieds (§ 167 Abs. 1 BGB).',
        style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: F.h(_farbe, 700), foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('Stellen')),
      ]));
    if (los != true || !mounted) return;

    setState(() => _stelltZu = id);
    try {
      final r = await widget.apiService.downloadVollmachtPdf(id);
      if (!mounted) return;
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _melden('PDF konnte nicht geladen werden (${r.statusCode})', Colors.red);
        return;
      }
      final e = await SignaturService().anfordernAusBytes(
        callerMitgliedernummer: anf,
        userId: widget.user.id,
        dokumentTyp: kKkDokumentTyp,
        dokumentTitel: 'Vollmacht — Krankenkasse',
        pdfBytes: r.bodyBytes,
        dateiname: '${v['pdf_filename'] ?? 'vollmacht_$id.pdf'}',
        fristBis: DateTime.now().add(const Duration(days: 14)),
        quelleTabelle: 'member_vollmachten',
        quelleId: id,
        unterzeichner: [
          Unterzeichner(userId: widget.user.id, rolle: 'vollmachtgeber'),
          if (mitVorstand) Unterzeichner(userId: vorsitzerId, rolle: 'bevollmaechtigter'),
        ],
      );
      if (!mounted) return;
      _melden(e.ok ? 'Zur Unterschrift gestellt' : (e.fehler ?? 'Anforderung fehlgeschlagen'),
              e.ok ? Colors.green : Colors.red);
      if (e.ok) _laden();
    } finally {
      if (mounted) setState(() => _stelltZu = null);
    }
  }

  Future<void> _senden(int id, {required bool fax}) async {
    final d = await widget.apiService.kkVollmachtVorlagen(id);
    if (!mounted) return;
    if (d['success'] != true) {
      _melden('${d['message'] ?? 'Vorlagen nicht abrufbar'}', Colors.red);
      return;
    }
    if (d['bereit'] != true) {
      final s = d['unterschrieben'] ?? 0, n = d['noetig'] ?? 0;
      _melden('Es gibt noch keine unterschriebene Fassung'
          '${n != 0 ? ' ($s von $n Unterschriften liegen vor)' : ''}.', Colors.orange);
      return;
    }
    final ziel = fax ? '${d['fax'] ?? ''}' : '${d['empfaenger'] ?? ''}';
    final stelle = '${d['stelle'] ?? 'die Kasse'}';
    if (ziel.trim().isEmpty) {
      // ⚠️ Der Grund gehört dazu: „keine Nummer hinterlegt" ist bei einer
      // Kasse meist kein Versehen, sondern die Lage.
      _melden('Für $stelle ist ${fax ? 'keine Faxnummer' : 'keine E-Mail-Adresse'} '
          'hinterlegt. ${d['kontakt_quelle'] == 'keine'
              ? 'Zu dieser Geschäftsstelle steht überhaupt kein Eintrag im Verzeichnis.'
              : 'Die meisten Kassen nehmen die Vollmacht nur per Post oder über ihr '
                'Portal an.'}', Colors.orange);
      return;
    }

    final vorlagen = d['vorlagen'] is Map ? Map<String, dynamic>.from(d['vorlagen']) : {};
    String gewaehlt = vorlagen.keys.isNotEmpty ? '${vorlagen.keys.first}' : 'einreichen';

    final los = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: Text(fax ? 'Vollmacht per Fax' : 'Vollmacht per E-Mail',
          style: const TextStyle(fontSize: 16)),
        content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('An: $stelle', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Text(ziel, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
            const SizedBox(height: 12),
            if (!fax) ...[
              const Text('Anschreiben', style: TextStyle(fontSize: 12)),
              for (final e in vorlagen.entries)
                ListTile(
                  dense: true, contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    gewaehlt == '${e.key}'
                        ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 18,
                    color: gewaehlt == '${e.key}'
                        ? F.h(_farbe, 700) : F.h(Colors.grey, 500)),
                  title: Text('${(e.value as Map)['titel'] ?? e.key}',
                    style: const TextStyle(fontSize: 12.5)),
                  subtitle: Text('${(e.value as Map)['hinweis'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                  onTap: () => setDlg(() => gewaehlt = '${e.key}')),
            ] else
              Text('Das Fax geht serverseitig über sipgate. Erfolg heißt „an sipgate '
                  'übergeben", nicht „zugestellt" — die Zustellung wird nachverfolgt.',
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
          ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: F.h(_farbe, 700), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('Senden')),
        ])));
    if (los != true || !mounted) return;

    final r = fax
        ? await widget.apiService.kkVollmachtFaxSenden(vollmachtId: id)
        : await widget.apiService.kkVollmachtMailSenden(vollmachtId: id, vorlage: gewaehlt);
    if (!mounted) return;
    _melden('${r['message'] ?? (r['success'] == true ? 'Gesendet' : 'Fehlgeschlagen')}',
            r['success'] == true ? Colors.green : Colors.red);
    if (r['success'] == true) _laden();
  }

  /// Eine Sendung per Post von Hand eintragen — bei den Kassen der Regelfall.
  Future<void> _postEintragen(int id) async {
    final ctrl = TextEditingController(text: _kasse);
    final los = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Per Post verschickt', style: TextStyle(fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Trägt die Sendung ins Protokoll ein. Verschickt wird sie von Hand — '
              'die meisten Kassen nehmen die Vollmacht nur per Post oder über ihr Portal an.',
            style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(labelText: 'An wen', isDense: true,
              border: OutlineInputBorder())),
        ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: F.h(_farbe, 700), foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('Eintragen')),
      ]));
    if (los != true || !mounted) return;
    final empf = ctrl.text.trim();
    if (empf.isEmpty) { _melden('Bitte angeben, an wen die Vollmacht ging.', Colors.orange); return; }
    final r = await widget.apiService.kkVollmachtVersandEintragen(
      vollmachtId: id, empfaenger: empf, weg: 'post');
    if (!mounted) return;
    _melden(r['success'] == true ? 'Eingetragen' : '${r['message'] ?? 'Fehler'}',
            r['success'] == true ? Colors.green : Colors.red);
    if (r['success'] == true) _laden();
  }

  Future<void> _protokoll(int id) async {
    final r = await widget.apiService.kkVollmachtVersandListe(id);
    if (!mounted) return;
    final items = (r['items'] is List)
        ? (r['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final links = (r['links'] is List)
        ? (r['links'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final linkBlock = vollmachtLinkBlock(links);

    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Versandprotokoll', style: TextStyle(fontSize: 16)),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty && linkBlock == null)
            Text('Noch keine Sendung eingetragen.',
              style: TextStyle(fontSize: 12.5, color: F.h(Colors.grey, 600))),
          for (final z in items)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${kVollmachtVersandWege['${z['weg'] ?? ''}'] ?? '${z['weg'] ?? ''}'}'
                     ' · ${z['gesendet_am'] ?? ''}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text('an ${z['empfaenger'] ?? ''}', style: const TextStyle(fontSize: 12)),
                if ('${z['gesendet_von_name'] ?? ''}'.trim().isNotEmpty)
                  Text('durch ${z['gesendet_von_name']}',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                if ('${z['notiz'] ?? ''}'.trim().isNotEmpty)
                  Text('${z['notiz']}',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
              ])),
          if (linkBlock != null) linkBlock,
        ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  Future<void> _widerrufen(int id) async {
    final ctrl = TextEditingController();
    final los = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Vollmacht widerrufen', style: TextStyle(fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ⚠️ Der Satz ist keine Floskel: § 13 Abs. 1 Satz 4 SGB X. Wer hier
          // widerruft und die Kasse nicht benachrichtigt, hat gegenüber der
          // Kasse nichts widerrufen.
          const Text('Die Vollmacht wird als widerrufen markiert und geht danach '
              'nirgendwohin mehr.\n\n'
              'Gegenüber der Kasse wird der Widerruf erst wirksam, wenn er ihr ZUGEHT '
              '(§ 13 Abs. 1 Satz 4 SGB X) — er muss ihr also noch schriftlich '
              'mitgeteilt werden.', style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(controller: ctrl,
            decoration: const InputDecoration(labelText: 'Grund (optional)',
              isDense: true, border: OutlineInputBorder())),
        ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: F.h(Colors.red, 700), foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('Widerrufen')),
      ]));
    if (los != true || !mounted) return;
    final r = await widget.apiService.revokeVollmacht(id, reason: ctrl.text.trim());
    if (!mounted) return;
    _melden(r['success'] == true ? 'Vollmacht widerrufen' : '${r['message'] ?? 'Fehler'}',
            r['success'] == true ? Colors.orange : Colors.red);
    if (r['success'] == true) _laden();
  }
}
