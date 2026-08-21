import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';
import '../utils/app_farben.dart';

/// Tab „Verordnung" der Arzt-Seite (neben Vorsorge).
///
/// Häusliche Krankenpflege wird vom Arzt auf dem Vordruck **Muster 12**
/// verordnet, Rechtsgrundlage **§ 37 SGB V**. Zahler ist die **Kranken**kasse,
/// nicht die Pflegekasse — das ist der Unterschied zum Pflegegrad (SGB XI),
/// der unter Behörde ▸ Krankenkasse ▸ Pflegekasse liegt. Ausgeführt wird die
/// Verordnung von einem **Pflegedienst** aus `pflegedienst_datenbank`.
///
/// Der Vordruck hat drei Ausfertigungen — 12a Krankenkasse, 12b Pflegedienst,
/// 12c verordnende Praxis. Genau deshalb hat eine Verordnung hier zwei
/// getrennte Korrespondenz-Stränge: einen mit der Kasse und einen mit dem
/// Dienst. Im Streitfall zählt, wer wann was gesagt hat.
///
/// Backend: `/api/admin/hkp_verordnung_manage.php`, Tabellen `hkp_verordnungen`,
/// `hkp_verordnung_korrespondenz`, `hkp_pflegedienst_korrespondenz`.
/// Diagnose und Leistungen liegen AES-256-GCM-verschlüsselt (ENC_MASTER_KEY).

/// Erst- oder Folgeverordnung. Die Erstverordnung ist auf **14 Tage**
/// begrenzt, damit sich die verordnende Person vom Erfolg überzeugen kann.
const kHkpVerordnungsarten = <(String, String, String)>[
  ('erstverordnung', 'Erstverordnung', 'längstens 14 Tage'),
  ('folgeverordnung', 'Folgeverordnung', 'in den letzten 3 Werktagen vor Ablauf ausstellen'),
];

/// Die vier Formen der häuslichen Krankenpflege nach § 37 SGB V.
const kHkpVersorgungsarten = <(String, String, String)>[
  ('krankenhausvermeidung', 'Krankenhausvermeidungspflege', '§ 37 Abs. 1 — bis 4 Wochen je Krankheitsfall'),
  ('krankenhausverkuerzung', 'Krankenhausverkürzungspflege', '§ 37 Abs. 1 — verkürzt den stationären Aufenthalt'),
  ('sicherungspflege', 'Sicherungspflege', '§ 37 Abs. 2 — sichert die ärztliche Behandlung, nur Behandlungspflege'),
  ('unterstuetzungspflege', 'Unterstützungspflege', '§ 37 Abs. 1a — nach Akutereignis, ohne Behandlungspflege'),
];

const kHkpStatus = <(String, String, MaterialColor)>[
  ('offen', 'Offen', Colors.grey),
  ('eingereicht', 'Bei der Kasse eingereicht', Colors.blue),
  ('genehmigt', 'Genehmigt', Colors.green),
  ('teilgenehmigt', 'Teilweise genehmigt', Colors.amber),
  ('abgelehnt', 'Abgelehnt', Colors.red),
  ('abgelaufen', 'Abgelaufen', Colors.blueGrey),
];

/// Leistungsverzeichnis der HKP-Richtlinie, gekürzt auf das, was in der
/// Praxis eines Vereins dieser Größe vorkommt. Die Ziffern sind die des
/// Verzeichnisses; leer heißt „nicht ziffernpflichtig".
/// Freitext bleibt trotzdem möglich — der Katalog ist Vorschlag, nicht Zwang.
const kHkpLeistungsbereiche = <(String, String, String)>[
  ('behandlungspflege', 'Behandlungspflege', '§ 37 Abs. 2 SGB V'),
  ('grundpflege', 'Grundpflege', '§ 37 Abs. 1 SGB V'),
  ('hauswirtschaft', 'Hauswirtschaftliche Versorgung', '§ 37 Abs. 1 SGB V'),
];

const kHkpLeistungskatalog = <String, List<(String, String)>>{
  'behandlungspflege': [
    ('26', 'Medikamentengabe'),
    ('26', 'Richten von Medikamenten'),
    ('18', 'Injektion subkutan'),
    ('19', 'Injektion intramuskulär'),
    ('11', 'Blutzuckermessung'),
    ('10', 'Blutdruckmessung'),
    ('31', 'Verbandwechsel'),
    ('31a', 'Versorgung chronischer / schwer heilender Wunden'),
    ('31', 'Kompressionsstrümpfe / -verbände An- und Ausziehen'),
    ('21', 'Katheterisierung der Harnblase'),
    ('22', 'Versorgung eines suprapubischen Katheters'),
    ('14', 'Dekubitusbehandlung'),
    ('30', 'Stomabehandlung'),
    ('1', 'Absaugen der oberen Luftwege'),
    ('17', 'Infusion / Anlegen und Überwachen'),
    ('27a', 'Psychiatrische häusliche Krankenpflege'),
    ('7', 'Anleitung zur Behandlungspflege'),
  ],
  'grundpflege': [
    ('', 'Körperpflege'),
    ('', 'Ernährung'),
    ('', 'Mobilität / Lagern'),
    ('', 'An- und Auskleiden'),
  ],
  'hauswirtschaft': [
    ('', 'Einkaufen'),
    ('', 'Kochen / Zubereiten von Mahlzeiten'),
    ('', 'Reinigen der Wohnung'),
    ('', 'Waschen / Wäschepflege'),
    ('', 'Beheizen der Wohnung'),
  ],
};

/// Die drei Ausfertigungen des Vordrucks, jede mit eigenem Ablagefach.
///
/// Amtlich ist Muster 12 dreiteilig: **12a** für die Krankenkasse (zweiseitig,
/// auf der Rückseite steht der Antrag des Versicherten), **12b** für den
/// Pflegedienst, **12c** für die verordnende Vertragsarztpraxis.
///
/// Dazu kommt ein viertes Fach für die **Ausfertigung des Versicherten**.
/// ⚠️ Es trägt bewusst KEINE Nummer: der Vordruck sieht für das Mitglied kein
/// eigenes Blatt vor, es ist die Kopie, die es in die Hand bekommt. Wer ihm
/// „12c" anhängte, behauptete etwas Falsches über ein Formular, auf das sich
/// Kasse und Dienst berufen — 12c ist die Ausfertigung der Praxis, und die
/// hat hier ein eigenes Fach.
///
/// ⚠️ Die `modul`-Namen müssen PAARWEISE VERSCHIEDEN bleiben. Anhänge sind
/// allein über (modul, korrespondenz_id) zugeordnet — zwei Fächer mit
/// demselben Namen zeigten stillschweigend dieselben Dateien, und ein Löschen
/// im einen Fach entfernte sie auch im anderen. Ein Test hält das fest.
const kHkpAusfertigungen = <(String, String, String, IconData)>[
  (
    'hkp_vo_kasse',
    'Für die Krankenkasse',
    'Ausfertigung 12a, zweiseitig — die Rückseite trägt den Antrag des Versicherten. '
        'Hierher gehört auch der Genehmigungsbescheid.',
    Icons.account_balance,
  ),
  (
    'hkp_vo_pflegedienst',
    'Für den Pflegedienst',
    'Ausfertigung 12b — das Exemplar, mit dem der Dienst die Leistung erbringt und abrechnet.',
    Icons.medical_services,
  ),
  (
    'hkp_vo_vertragsarzt',
    'Für den Vertragsarzt',
    'Ausfertigung 12c — bleibt normalerweise in der verordnenden Praxis. '
        'Liegt uns eine Kopie vor, etwa als Nachweis der Ausstellung, gehört sie hierher.',
    Icons.local_hospital,
  ),
  (
    'hkp_vo_versicherte',
    'Ausfertigung des Versicherten',
    'Das Exemplar, das dem Mitglied ausgehändigt wurde. Der Vordruck sieht dafür '
        'kein eigenes Blatt vor — deshalb trägt dieses Fach keine Nummer.',
    Icons.badge,
  ),
];

String _hkpLabel(List<(String, String, dynamic)> liste, String key) {
  for (final e in liste) {
    if (e.$1 == key) return e.$2;
  }
  return key;
}

MaterialColor _hkpStatusFarbe(String key) {
  for (final s in kHkpStatus) {
    if (s.$1 == key) return s.$3;
  }
  return Colors.grey;
}

/// 'YYYY-MM-DD' → '17.08.2026'. Alles andere kommt unverändert zurück:
/// ein leeres Feld darf nicht als „01.01.1970" auf dem Schirm landen.
String hkpDatumLesbar(String iso) {
  final t = iso.trim();
  if (t.length < 10) return t;
  final d = DateTime.tryParse(t.substring(0, 10));
  if (d == null) return t;
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

/// Der Server liefert Beträge als JSON-Zahl (`10.5`). Unverändert angezeigt
/// stünde in einem deutschen Eingabefeld „10.5", während der Nutzer „10,50"
/// eingetippt hat — beim Speichern nimmt der Server beides, aber beim
/// Wiederöffnen sähe es aus, als hätte die App den Wert verändert.
String hkpBetragLesbar(dynamic betrag) {
  if (betrag == null) return '';
  final d = betrag is num ? betrag.toDouble() : double.tryParse(betrag.toString().replaceAll(',', '.'));
  if (d == null) return betrag.toString();
  return d.toStringAsFixed(2).replaceAll('.', ',');
}

/// Verbleibende Tage bis [bis] (ISO). null = kein auswertbares Datum.
/// Negativ heißt abgelaufen — der Aufrufer entscheidet, wie laut er das sagt.
int? hkpTageBis(String bis) {
  final t = bis.trim();
  if (t.length < 10) return null;
  final d = DateTime.tryParse(t.substring(0, 10));
  if (d == null) return null;
  final heute = DateTime.now();
  return DateTime(d.year, d.month, d.day)
      .difference(DateTime(heute.year, heute.month, heute.day))
      .inDays;
}

class HkpVerordnungTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String arztType;
  final String arztTitle;

  /// Name der behandelnden Praxis — Vorbelegung für neue Verordnungen.
  final String? arztName;

  const HkpVerordnungTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.arztType,
    required this.arztTitle,
    this.arztName,
  });

  @override
  State<HkpVerordnungTab> createState() => _HkpVerordnungTabState();
}

class _HkpVerordnungTabState extends State<HkpVerordnungTab> {
  List<Map<String, dynamic>> _verordnungen = [];
  bool _loading = true;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final r = await widget.apiService.hkpVerordnungAction({
        'action': 'list',
        'user_id': widget.userId,
        'arzt_type': widget.arztType,
      });
      if (!mounted) return;
      setState(() {
        _verordnungen = (r['verordnungen'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        // Ein fehlgeschlagener Abruf darf nicht wie „keine Verordnungen"
        // aussehen — sonst legt jemand eine zweite an, die es längst gibt.
        _fehler = r['success'] == true ? null : (r['message']?.toString() ?? 'Konnte nicht geladen werden');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fehler = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _oeffne(Map<String, dynamic>? vo) async {
    await showDialog(
      context: context,
      builder: (_) => _VerordnungDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        arztType: widget.arztType,
        arztTitle: widget.arztTitle,
        arztName: widget.arztName,
        verordnung: vo,
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _infoBanner(),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Text('Verordnungen (${_verordnungen.length})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              FilledButton.icon(
                onPressed: () => _oeffne(null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Neue Verordnung'),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600),
              ),
            ]),
            const SizedBox(height: 10),
            if (_fehler != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: F.h(Colors.red, 50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: F.h(Colors.red, 200)),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline, size: 16, color: F.h(Colors.red, 700)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_fehler!, style: TextStyle(fontSize: 11, color: F.h(Colors.red, 800)))),
                  TextButton(onPressed: _load, child: const Text('Erneut', style: TextStyle(fontSize: 11))),
                ]),
              ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (_verordnungen.isEmpty && _fehler == null)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: F.h(Colors.grey, 50),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: F.h(Colors.grey, 300)),
                ),
                child: Column(children: [
                  Icon(Icons.assignment_outlined, size: 44, color: F.h(Colors.grey, 400)),
                  const SizedBox(height: 8),
                  Text('Noch keine Verordnung erfasst',
                      style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
                  const SizedBox(height: 4),
                  Text('Mit „Neue Verordnung" das Muster 12 hochladen und die Daten erfassen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
                ]),
              )
            else
              ..._verordnungen.map(_karte),
          ]),
        ),
      ),
    ]);
  }

  Widget _infoBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: F.h(Colors.teal, 50),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: F.h(Colors.teal, 200)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: F.h(Colors.teal, 800), size: 18),
          const SizedBox(width: 8),
          Expanded(
            // Text.rich statt RichText: RichText erbt den DefaultTextStyle
            // NICHT, die Schriftart des Themes käme also nie an.
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.teal, 900), height: 1.4),
                children: const [
                  TextSpan(text: 'Verordnung häuslicher Krankenpflege ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(
                      text: '(Muster 12, § 37 SGB V). Zahler ist die Krankenkasse — nicht die Pflegekasse. '
                          'Erstverordnung längstens 14 Tage; Folgeverordnung in den letzten drei Werktagen vor Ablauf ausstellen. '
                          'Spätestens am vierten Werktag nach Ausstellung bei der Kasse einreichen — bis zur Entscheidung trägt sie die Kosten. '
                          'Zuzahlung: 10 % je Tag für längstens 28 Tage im Jahr, zusätzlich 10 € je Verordnung.'),
                ],
              ),
            ),
          ),
        ]),
      );

  Widget _karte(Map<String, dynamic> v) {
    final status = v['status']?.toString() ?? 'offen';
    final farbe = _hkpStatusFarbe(status);
    final bis = v['zeitraum_bis']?.toString() ?? '';
    final tage = hkpTageBis(bis);
    final pd = v['pflegedienst'] is Map ? Map<String, dynamic>.from(v['pflegedienst'] as Map) : null;
    final art = v['verordnungsart']?.toString() ?? '';
    final isErst = art == 'erstverordnung';

    // „Läuft ab" nur solange die Verordnung überhaupt noch laufen kann.
    // Bei abgelehnt/abgelaufen wäre der Countdown eine Fehlmeldung.
    final zeigtFrist = tage != null && status != 'abgelehnt' && status != 'abgelaufen';

    return InkWell(
      onTap: () => _oeffne(v),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: F.flaeche,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: F.h(farbe, 200)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.assignment, size: 20, color: F.h(Colors.teal, 700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_hkpLabel(kHkpVersorgungsarten, v['versorgungsart']?.toString() ?? ''),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
            _chip(_hkpLabel(kHkpVerordnungsarten, art), isErst ? Colors.indigo : Colors.purple),
            const SizedBox(width: 4),
            _chip(_hkpLabel(kHkpStatus, status), farbe),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (bis.isNotEmpty || (v['zeitraum_von']?.toString() ?? '').isNotEmpty)
              _zeile(Icons.date_range,
                  '${hkpDatumLesbar(v['zeitraum_von']?.toString() ?? '')} – ${hkpDatumLesbar(bis)}'),
            if ((v['diagnose_icd10']?.toString() ?? '').isNotEmpty)
              _zeile(Icons.medical_information, v['diagnose_icd10'].toString()),
            if (pd != null && (pd['name']?.toString() ?? '').isNotEmpty)
              _zeile(Icons.medical_services, pd['name'].toString()),
            _zeile(Icons.checklist, '${(v['leistungen'] as List?)?.length ?? 0} Leistungen'),
          ]),
          if (zeigtFrist) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tage < 0
                    ? F.h(Colors.red, 50)
                    : tage <= 3
                        ? F.h(Colors.orange, 50)
                        : F.h(Colors.green, 50),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tage < 0
                    ? 'Zeitraum seit ${-tage} Tag${-tage == 1 ? '' : 'en'} abgelaufen'
                    : tage == 0
                        ? 'Läuft heute ab — Folgeverordnung fällig'
                        : tage <= 3
                            ? 'Noch $tage Tag${tage == 1 ? '' : 'e'} — jetzt ist das Fenster für die Folgeverordnung'
                            : 'Noch $tage Tage',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: tage < 0
                      ? F.h(Colors.red, 700)
                      : tage <= 3
                          ? F.h(Colors.orange, 800)
                          : F.h(Colors.green, 700),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String text, MaterialColor c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: F.h(c, 50), borderRadius: BorderRadius.circular(6), border: Border.all(color: F.h(c, 200))),
        child: Text(text, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: F.h(c, 800))),
      );

  Widget _zeile(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 13, color: F.h(Colors.grey, 600)),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
      ]);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Detailansicht einer Verordnung: Details · Korrespondenz · Pflegedienst
// ═══════════════════════════════════════════════════════════════════════════

class _VerordnungDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String arztType;
  final String arztTitle;
  final String? arztName;

  /// null = neue Verordnung.
  final Map<String, dynamic>? verordnung;

  const _VerordnungDialog({
    required this.apiService,
    required this.userId,
    required this.arztType,
    required this.arztTitle,
    this.arztName,
    this.verordnung,
  });

  @override
  State<_VerordnungDialog> createState() => _VerordnungDialogState();
}

class _VerordnungDialogState extends State<_VerordnungDialog> {
  late Map<String, dynamic> _v;
  bool _saving = false;

  late final TextEditingController _arztNameC;
  late final TextEditingController _icdC;
  late final TextEditingController _diagnoseC;
  late final TextEditingController _zuzahlungC;
  late final TextEditingController _ablehnungC;
  late final TextEditingController _notizenC;

  List<Map<String, dynamic>> _leistungen = [];

  int get _id => int.tryParse(_v['id']?.toString() ?? '') ?? 0;
  bool get _istNeu => _id <= 0;

  @override
  void initState() {
    super.initState();
    _v = widget.verordnung != null
        ? Map<String, dynamic>.from(widget.verordnung!)
        : <String, dynamic>{
            'verordnungsart': 'erstverordnung',
            'versorgungsart': 'sicherungspflege',
            'status': 'offen',
            'ausstellungsdatum': _heuteIso(),
            'zeitraum_von': _heuteIso(),
            // Erstverordnung ist auf 14 Tage begrenzt — das ist die
            // gesetzliche Obergrenze, also die richtige Vorbelegung.
            'zeitraum_bis': _plusTageIso(13),
          };
    _leistungen = (_v['leistungen'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    _arztNameC = TextEditingController(text: _v['arzt_name']?.toString() ?? widget.arztName ?? '');
    _icdC = TextEditingController(text: _v['diagnose_icd10']?.toString() ?? '');
    _diagnoseC = TextEditingController(text: _v['diagnose_text']?.toString() ?? '');
    _zuzahlungC = TextEditingController(text: hkpBetragLesbar(_v['zuzahlung_betrag']));
    _ablehnungC = TextEditingController(text: _v['ablehnung_grund']?.toString() ?? '');
    _notizenC = TextEditingController(text: _v['notizen']?.toString() ?? '');
  }

  static String _heuteIso() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _plusTageIso(int tage) {
    final d = DateTime.now().add(Duration(days: tage));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _arztNameC.dispose();
    _icdC.dispose();
    _diagnoseC.dispose();
    _zuzahlungC.dispose();
    _ablehnungC.dispose();
    _notizenC.dispose();
    super.dispose();
  }

  Future<bool> _speichern() async {
    setState(() => _saving = true);
    try {
      final r = await widget.apiService.hkpVerordnungAction({
        'action': 'save',
        'user_id': widget.userId,
        'arzt_type': widget.arztType,
        'verordnung': {
          if (_id > 0) 'id': _id,
          'verordnungsart': _v['verordnungsart'],
          'versorgungsart': _v['versorgungsart'],
          'status': _v['status'],
          'ausstellungsdatum': _v['ausstellungsdatum'] ?? '',
          'zeitraum_von': _v['zeitraum_von'] ?? '',
          'zeitraum_bis': _v['zeitraum_bis'] ?? '',
          'eingereicht_am': _v['eingereicht_am'] ?? '',
          'genehmigt_am': _v['genehmigt_am'] ?? '',
          'genehmigt_bis': _v['genehmigt_bis'] ?? '',
          'unfall': _v['unfall'] == true,
          'ser_bvg': _v['ser_bvg'] == true,
          'haeufigkeit_pflegefachkraft': _v['haeufigkeit_pflegefachkraft'] == true,
          'zuzahlung_betrag': _zuzahlungC.text.trim(),
          'zuzahlung_befreit': _v['zuzahlung_befreit'] == true,
          'pflegedienst_id': _v['pflegedienst_id'] ?? 0,
          'pflegedienst_name': (_v['pflegedienst'] is Map)
              ? (_v['pflegedienst'] as Map)['name']?.toString() ?? ''
              : '',
          'arzt_name': _arztNameC.text.trim(),
          'diagnose_icd10': _icdC.text.trim(),
          'diagnose_text': _diagnoseC.text.trim(),
          'leistungen': _leistungen,
          'ablehnung_grund': _ablehnungC.text.trim(),
          'notizen': _notizenC.text.trim(),
        },
      });
      if (!mounted) return false;
      if (r['success'] != true) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nicht gespeichert: ${r['message'] ?? 'unbekannter Fehler'}'),
          backgroundColor: Colors.red,
        ));
        return false;
      }
      setState(() {
        if (r['verordnung'] is Map) {
          _v = Map<String, dynamic>.from(r['verordnung'] as Map);
          _leistungen =
              (_v['leistungen'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        } else {
          _v['id'] = r['id'];
        }
        _saving = false;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
      return false;
    }
  }

  Future<void> _loeschen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Verordnung löschen?'),
        content: const Text(
            'Die Verordnung und die gesamte Korrespondenz mit Kasse und Pflegedienst werden gelöscht. '
            'Hochgeladene Dokumente bleiben davon unberührt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.apiService
        .hkpVerordnungAction({'action': 'delete', 'user_id': widget.userId, 'id': _id});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 820,
          height: 680,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(children: [
                Icon(Icons.assignment, color: F.h(Colors.teal, 700)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_istNeu ? 'Neue Verordnung' : 'Verordnung häuslicher Krankenpflege',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    Text('Muster 12 · § 37 SGB V · ${widget.arztTitle}',
                        style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
                  ]),
                ),
                if (!_istNeu)
                  IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                      tooltip: 'Verordnung löschen',
                      onPressed: _loeschen),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            TabBar(
              labelColor: F.h(Colors.teal, 700),
              unselectedLabelColor: F.h(Colors.grey, 500),
              indicatorColor: Colors.teal.shade700,
              tabs: const [
                Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
                Tab(icon: Icon(Icons.mail_outline, size: 18), text: 'Korrespondenz'),
                Tab(icon: Icon(Icons.medical_services, size: 18), text: 'Pflegedienst'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                _detailsTab(),
                // Korrespondenz und Pflegedienst hängen an der id. Vor dem
                // ersten Speichern gibt es sie nicht — das wird gesagt, statt
                // eine leere Liste zu zeigen, die man für „nichts da" hält.
                _istNeu
                    ? _erstSpeichernHinweis('Korrespondenz')
                    : _HkpKorrespondenzListe(
                        apiService: widget.apiService,
                        userId: widget.userId,
                        verordnungId: _id,
                        kanal: 'kasse',
                        titel: 'Korrespondenz zur Verordnung',
                        hinweis: 'Kasse, Praxis, Medizinischer Dienst — Ausfertigung 12a und 12c.',
                        farbe: Colors.teal,
                        attachmentModul: 'hkp_verordnung_korr',
                      ),
                _istNeu
                    ? _erstSpeichernHinweis('Pflegedienst')
                    : _PflegedienstTab(
                        apiService: widget.apiService,
                        userId: widget.userId,
                        verordnungId: _id,
                        pflegedienst: _v['pflegedienst'] is Map
                            ? Map<String, dynamic>.from(_v['pflegedienst'] as Map)
                            : null,
                        onAuswahl: (pd) async {
                          setState(() {
                            _v['pflegedienst'] = pd;
                            _v['pflegedienst_id'] = pd == null ? 0 : pd['id'];
                          });
                          await _speichern();
                        },
                      ),
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                if (!_istNeu)
                  Text('Zuletzt geändert: ${_v['updated_at']?.toString().split('.').first ?? '—'}',
                      style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 500))),
                const Spacer(),
                TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Schließen')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600),
                  icon: _saving
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 16),
                  label: Text(_istNeu ? 'Anlegen' : 'Speichern'),
                  onPressed: _saving
                      ? null
                      : () async {
                          // Messenger vor dem await greifen: danach ist der
                          // Kontext dieses Buttons möglicherweise schon weg.
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await _speichern();
                          if (ok) {
                            messenger.showSnackBar(const SnackBar(
                                content: Text('Gespeichert'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 1)));
                          }
                        },
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _erstSpeichernHinweis(String was) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.save_outlined, size: 42, color: F.h(Colors.grey, 300)),
            const SizedBox(height: 8),
            Text('$was ist nach dem Anlegen verfügbar',
                style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
            const SizedBox(height: 4),
            Text('Erst Details ausfüllen und „Anlegen" drücken.',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
          ]),
        ),
      );

  // ── Tab 1: Details ────────────────────────────────────────────────────
  Widget _detailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _abschnitt(Icons.assignment_outlined, 'Art der Verordnung'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in kHkpVerordnungsarten)
            ChoiceChip(
              label: Text(a.$2, style: const TextStyle(fontSize: 11.5)),
              selected: _v['verordnungsart'] == a.$1,
              selectedColor: F.h(Colors.teal, 100),
              onSelected: (_) => setState(() => _v['verordnungsart'] = a.$1),
            ),
        ]),
        const SizedBox(height: 4),
        Text(_hilfeText(kHkpVerordnungsarten, _v['verordnungsart']?.toString() ?? ''),
            style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic)),
        const SizedBox(height: 16),
        _abschnitt(Icons.category_outlined, 'Form der häuslichen Krankenpflege'),
        RadioGroup<String>(
          groupValue: _v['versorgungsart']?.toString(),
          onChanged: (val) => setState(() => _v['versorgungsart'] = val),
          child: Column(children: [
            for (final a in kHkpVersorgungsarten)
              RadioListTile<String>(
                value: a.$1,
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                activeColor: Colors.teal.shade600,
                title: Text(a.$2, style: const TextStyle(fontSize: 12.5)),
                subtitle: Text(a.$3, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        _abschnitt(Icons.date_range, 'Zeitraum und Ausstellung'),
        Row(children: [
          Expanded(child: _datumFeld('Ausgestellt am', 'ausstellungsdatum')),
          const SizedBox(width: 10),
          Expanded(child: _datumFeld('Zeitraum von', 'zeitraum_von')),
          const SizedBox(width: 10),
          Expanded(child: _datumFeld('Zeitraum bis', 'zeitraum_bis')),
        ]),
        _fristHinweis(),
        const SizedBox(height: 14),
        _abschnitt(Icons.medical_information_outlined, 'Diagnose'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 130,
            child: TextField(
              controller: _icdC,
              decoration: const InputDecoration(
                  labelText: 'ICD-10', isDense: true, border: OutlineInputBorder(), hintText: 'I50.9'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _diagnoseC,
              decoration: const InputDecoration(
                  labelText: 'Diagnose im Klartext', isDense: true, border: OutlineInputBorder()),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        _abschnitt(Icons.checklist, 'Verordnete Leistungen'),
        _leistungenBlock(),
        const SizedBox(height: 14),
        _abschnitt(Icons.check_box_outlined, 'Ankreuzfelder des Vordrucks'),
        _schalter('Unfall / Unfallfolgen', 'unfall',
            'Ein Arbeits- oder Wegeunfall führt zur Unfallkasse statt zur Krankenkasse.'),
        _schalter('Soziales Entschädigungsrecht (SER/BVG)', 'ser_bvg',
            'Feld 5 des Vordrucks — Verordnung auf Grundlage des SGB XIV.'),
        _schalter('Häufigkeit/Dauer legt die Pflegefachkraft fest', 'haeufigkeit_pflegefachkraft',
            'Feld 7, neu seit 2024. Angekreuzt heißt: die Entscheidung über Häufigkeit und Dauer ist '
            'an die Pflegefachkraft übertragen — dann darf die verordnende Praxis sie nicht selbst eintragen.'),
        const SizedBox(height: 14),
        _abschnitt(Icons.account_balance, 'Weg zur Krankenkasse'),
        DropdownButtonFormField<String>(
          // Ein unbekannter Status aus der DB darf nicht zum Absturz führen —
          // DropdownButtonFormField wirft, wenn der Wert nicht in items steht.
          initialValue: kHkpStatus.any((s) => s.$1 == _v['status']) ? _v['status']?.toString() : 'offen',
          decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
          style: TextStyle(fontSize: 13, color: F.textStark),
          items: [
            for (final s in kHkpStatus)
              DropdownMenuItem(value: s.$1, child: Text(s.$2, style: const TextStyle(fontSize: 13)))
          ],
          onChanged: (val) => setState(() => _v['status'] = val),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _datumFeld('Eingereicht am', 'eingereicht_am')),
          const SizedBox(width: 10),
          Expanded(child: _datumFeld('Genehmigt am', 'genehmigt_am')),
          const SizedBox(width: 10),
          Expanded(child: _datumFeld('Genehmigt bis', 'genehmigt_bis')),
        ]),
        if (_v['status'] == 'abgelehnt' || _v['status'] == 'teilgenehmigt') ...[
          const SizedBox(height: 10),
          TextField(
            controller: _ablehnungC,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Begründung der Kasse', isDense: true, border: OutlineInputBorder(), alignLabelWithHint: true),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text('Gegen einen ablehnenden Bescheid ist Widerspruch möglich — Frist ein Monat ab Zugang.',
              style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 14),
        _abschnitt(Icons.euro, 'Zuzahlung'),
        Row(children: [
          SizedBox(
            width: 150,
            child: TextField(
              controller: _zuzahlungC,
              enabled: _v['zuzahlung_befreit'] != true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Betrag', isDense: true, border: OutlineInputBorder(), suffixText: '€'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: CheckboxListTile(
              value: _v['zuzahlung_befreit'] == true,
              onChanged: (b) => setState(() => _v['zuzahlung_befreit'] = b == true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Colors.teal.shade600,
              title: const Text('Von Zuzahlung befreit', style: TextStyle(fontSize: 12.5)),
              subtitle: Text('Befreiung nach § 62 SGB V liegt vor',
                  style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text('10 % der Kosten je Tag, längstens 28 Tage im Kalenderjahr, zusätzlich 10 € je Verordnung (§ 61 SGB V).',
            style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic)),
        const SizedBox(height: 14),
        _abschnitt(Icons.local_hospital_outlined, 'Verordnende Praxis'),
        TextField(
          controller: _arztNameC,
          decoration: const InputDecoration(
              labelText: 'Arzt / Praxis', isDense: true, border: OutlineInputBorder()),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 14),
        _abschnitt(Icons.notes, 'Notizen'),
        TextField(
          controller: _notizenC,
          maxLines: 3,
          decoration: const InputDecoration(
              isDense: true, border: OutlineInputBorder(), alignLabelWithHint: true),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 18),
        _abschnitt(Icons.attach_file, 'Die Ausfertigungen (Muster 12)'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
              'Der Vordruck ist dreiteilig — 12a Krankenkasse, 12b Pflegedienst, 12c verordnende Praxis —, '
              'dazu die Kopie des Mitglieds. Jede hat ihr eigenes Fach, sonst liegt am Ende ein Stapel, '
              'dem niemand mehr ansieht, welches Blatt zur Kasse ging.',
              style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600), height: 1.35)),
        ),
        if (_istNeu)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: F.h(Colors.amber, 50),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: F.h(Colors.amber, 200)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: F.h(Colors.amber, 800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Der Scan des Vordrucks kann hochgeladen werden, sobald die Verordnung angelegt ist.',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.amber, 900))),
              ),
            ]),
          )
        else
          ...kHkpAusfertigungen.map((a) => _ausfertigung(a)),
        const SizedBox(height: 12),
      ]),
    );
  }

  String _hilfeText(List<(String, String, String)> liste, String key) {
    for (final e in liste) {
      if (e.$1 == key) return e.$3;
    }
    return '';
  }

  /// Ein Ablagefach je Ausfertigung. Jedes bekommt seinen eigenen `modul`,
  /// damit die Dateien getrennt bleiben und nicht in einem Haufen landen,
  /// in dem niemand mehr sieht, welches Blatt zur Kasse ging.
  Widget _ausfertigung((String, String, String, IconData) a) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: F.h(Colors.grey, 50),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: F.h(Colors.grey, 200)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(a.$4, size: 16, color: F.h(Colors.teal, 700)),
            const SizedBox(width: 7),
            Text(a.$2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800))),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 6),
            child: Text(a.$3, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600), height: 1.35)),
          ),
          KorrAttachmentsWidget(
            apiService: widget.apiService,
            memberId: widget.userId,
            modul: a.$1,
            korrespondenzId: _id,
            allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
            maxFiles: 20,
          ),
        ]),
      );

  Widget _abschnitt(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(i, size: 17, color: F.h(Colors.teal, 700)),
          const SizedBox(width: 7),
          Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800))),
        ]),
      );

  Widget _schalter(String titel, String key, String hilfe) => CheckboxListTile(
        value: _v[key] == true,
        onChanged: (b) => setState(() => _v[key] = b == true),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: Colors.teal.shade600,
        title: Text(titel, style: const TextStyle(fontSize: 12.5)),
        subtitle: Text(hilfe, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
      );

  Widget _datumFeld(String label, String key) {
    final iso = _v[key]?.toString() ?? '';
    return TextField(
      readOnly: true,
      controller: TextEditingController(text: hkpDatumLesbar(iso)),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: iso.isEmpty
            ? const Icon(Icons.calendar_today, size: 15)
            : IconButton(
                icon: const Icon(Icons.clear, size: 15),
                tooltip: 'Datum entfernen',
                onPressed: () => setState(() => _v[key] = ''),
              ),
      ),
      onTap: () async {
        final p = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(iso.length >= 10 ? iso.substring(0, 10) : '') ?? DateTime.now(),
          firstDate: DateTime(2015),
          lastDate: DateTime(2040),
          locale: const Locale('de'),
        );
        if (p != null) {
          setState(() => _v[key] =
              '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
        }
      },
    );
  }

  /// Prüft, was am Zeitraum auffällt, ohne etwas zu verbieten: die 14-Tage-Grenze
  /// gilt für die Erstverordnung, und ein Bis vor dem Von ist immer ein Vertipper.
  Widget _fristHinweis() {
    final von = DateTime.tryParse((_v['zeitraum_von']?.toString() ?? '').padRight(10).substring(0, 10).trim());
    final bis = DateTime.tryParse((_v['zeitraum_bis']?.toString() ?? '').padRight(10).substring(0, 10).trim());
    if (von == null || bis == null) return const SizedBox.shrink();

    final tage = bis.difference(von).inDays + 1; // beide Tage zählen mit
    final warnungen = <String>[
      if (bis.isBefore(von)) 'Das Ende liegt vor dem Beginn.',
      if (!bis.isBefore(von) && _v['verordnungsart'] == 'erstverordnung' && tage > 14)
        'Erstverordnung über $tage Tage — zulässig sind längstens 14.',
    ];
    if (warnungen.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('$tage Tage', style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: F.h(Colors.orange, 50),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: F.h(Colors.orange, 200)),
        ),
        child: Row(children: [
          Icon(Icons.warning_amber, size: 15, color: F.h(Colors.orange, 800)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(warnungen.join(' '),
                style: TextStyle(fontSize: 10.5, color: F.h(Colors.orange, 900))),
          ),
        ]),
      ),
    );
  }

  // ── Leistungen ────────────────────────────────────────────────────────
  Widget _leistungenBlock() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_leistungen.isEmpty)
        Text('Noch keine Leistung erfasst.', style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 500)))
      else
        ..._leistungen.asMap().entries.map((e) {
          final l = e.value;
          final bereich = l['bereich']?.toString() ?? '';
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: F.h(Colors.grey, 50),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: F.h(Colors.grey, 200)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if ((l['ziffer']?.toString() ?? '').isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: F.h(Colors.teal, 50), borderRadius: BorderRadius.circular(4)),
                        child: Text('Nr. ${l['ziffer']}',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800))),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(l['bezeichnung']?.toString() ?? '',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _hkpLabel(kHkpLeistungsbereiche, bereich),
                      if ((l['haeufigkeit']?.toString() ?? '').isNotEmpty) l['haeufigkeit'].toString(),
                      if ((l['dauer_von']?.toString() ?? '').isNotEmpty ||
                          (l['dauer_bis']?.toString() ?? '').isNotEmpty)
                        '${hkpDatumLesbar(l['dauer_von']?.toString() ?? '')} – ${hkpDatumLesbar(l['dauer_bis']?.toString() ?? '')}',
                      if (l['durch_pflegefachkraft'] == true) 'Häufigkeit durch Pflegefachkraft',
                    ].join(' · '),
                    style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
                  ),
                ]),
              ),
              IconButton(
                icon: Icon(Icons.edit, size: 16, color: F.h(Colors.teal, 600)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () => _leistungDialog(index: e.key),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () => setState(() => _leistungen.removeAt(e.key)),
              ),
            ]),
          );
        }),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        onPressed: () => _leistungDialog(),
        icon: const Icon(Icons.add, size: 15),
        label: const Text('Leistung hinzufügen', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(foregroundColor: F.h(Colors.teal, 700), visualDensity: VisualDensity.compact),
      ),
    ]);
  }

  void _leistungDialog({int? index}) {
    final vorhanden = index != null ? Map<String, dynamic>.from(_leistungen[index]) : <String, dynamic>{};
    String bereich = vorhanden['bereich']?.toString() ?? 'behandlungspflege';
    final bezC = TextEditingController(text: vorhanden['bezeichnung']?.toString() ?? '');
    final zifferC = TextEditingController(text: vorhanden['ziffer']?.toString() ?? '');
    final haeufC = TextEditingController(text: vorhanden['haeufigkeit']?.toString() ?? '');
    String von = vorhanden['dauer_von']?.toString() ?? '';
    String bis = vorhanden['dauer_bis']?.toString() ?? '';
    bool durchPfk = vorhanden['durch_pflegefachkraft'] == true;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c2, setD) {
        final katalog = kHkpLeistungskatalog[bereich] ?? const <(String, String)>[];
        return AlertDialog(
          title: Text(index == null ? 'Leistung hinzufügen' : 'Leistung bearbeiten',
              style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final b in kHkpLeistungsbereiche)
                    ChoiceChip(
                      label: Text(b.$2, style: const TextStyle(fontSize: 11)),
                      selected: bereich == b.$1,
                      selectedColor: F.h(Colors.teal, 100),
                      onSelected: (_) => setD(() => bereich = b.$1),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(_hilfeText(kHkpLeistungsbereiche, bereich),
                    style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                const SizedBox(height: 12),
                Text('Aus dem Leistungsverzeichnis übernehmen',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
                const SizedBox(height: 4),
                SizedBox(
                  height: 120,
                  child: Scrollbar(
                    child: ListView(
                      children: [
                        for (final k in katalog)
                          InkWell(
                            onTap: () => setD(() {
                              zifferC.text = k.$1;
                              bezC.text = k.$2;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                              child: Row(children: [
                                if (k.$1.isNotEmpty)
                                  SizedBox(
                                    width: 34,
                                    child: Text('Nr. ${k.$1}',
                                        style: TextStyle(fontSize: 9.5, color: F.h(Colors.teal, 700))),
                                  )
                                else
                                  const SizedBox(width: 34),
                                Expanded(child: Text(k.$2, style: const TextStyle(fontSize: 12))),
                              ]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 18),
                Row(children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: zifferC,
                      decoration: const InputDecoration(labelText: 'Nr.', isDense: true, border: OutlineInputBorder()),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: bezC,
                      decoration:
                          const InputDecoration(labelText: 'Bezeichnung', isDense: true, border: OutlineInputBorder()),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: haeufC,
                  enabled: !durchPfk,
                  decoration: InputDecoration(
                    labelText: 'Häufigkeit / Dauer',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: '3x täglich',
                    helperText: durchPfk ? 'Legt die Pflegefachkraft fest' : null,
                    helperStyle: const TextStyle(fontSize: 9.5),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: durchPfk,
                  onChanged: (b) => setD(() => durchPfk = b == true),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.teal.shade600,
                  title: const Text('Häufigkeit/Dauer durch die Pflegefachkraft', style: TextStyle(fontSize: 12)),
                  subtitle: Text('Feld 7 des Vordrucks — dann trägt die Praxis hier nichts ein.',
                      style: TextStyle(fontSize: 9.5, color: F.h(Colors.grey, 600))),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final p = await showDatePicker(
                            context: c2,
                            initialDate: DateTime.tryParse(von.length >= 10 ? von.substring(0, 10) : '') ?? DateTime.now(),
                            firstDate: DateTime(2015),
                            lastDate: DateTime(2040),
                            locale: const Locale('de'));
                        if (p != null) {
                          setD(() => von =
                              '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
                        }
                      },
                      child: Text(von.isEmpty ? 'Dauer von' : hkpDatumLesbar(von),
                          style: const TextStyle(fontSize: 11.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final p = await showDatePicker(
                            context: c2,
                            initialDate: DateTime.tryParse(bis.length >= 10 ? bis.substring(0, 10) : '') ?? DateTime.now(),
                            firstDate: DateTime(2015),
                            lastDate: DateTime(2040),
                            locale: const Locale('de'));
                        if (p != null) {
                          setD(() => bis =
                              '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
                        }
                      },
                      child: Text(bis.isEmpty ? 'Dauer bis' : hkpDatumLesbar(bis),
                          style: const TextStyle(fontSize: 11.5)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600),
              onPressed: () {
                if (bezC.text.trim().isEmpty) return;
                final neu = <String, dynamic>{
                  'bereich': bereich,
                  'bezeichnung': bezC.text.trim(),
                  'ziffer': zifferC.text.trim(),
                  'haeufigkeit': durchPfk ? '' : haeufC.text.trim(),
                  'dauer_von': von,
                  'dauer_bis': bis,
                  'durch_pflegefachkraft': durchPfk,
                };
                setState(() {
                  if (index == null) {
                    _leistungen.add(neu);
                  } else {
                    _leistungen[index] = neu;
                  }
                });
                Navigator.pop(c);
              },
              child: const Text('Übernehmen'),
            ),
          ],
        );
      }),
    ).then((_) {
      bezC.dispose();
      zifferC.dispose();
      haeufC.dispose();
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Tab 3: Pflegedienst — Auswahl + Details + eigene Korrespondenz
// ═══════════════════════════════════════════════════════════════════════════

class _PflegedienstTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int verordnungId;
  final Map<String, dynamic>? pflegedienst;
  final Future<void> Function(Map<String, dynamic>? pd) onAuswahl;

  const _PflegedienstTab({
    required this.apiService,
    required this.userId,
    required this.verordnungId,
    required this.pflegedienst,
    required this.onAuswahl,
  });

  @override
  State<_PflegedienstTab> createState() => _PflegedienstTabState();
}

class _PflegedienstTabState extends State<_PflegedienstTab> {
  Future<void> _suche() async {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> treffer = [];
    bool laedt = false;

    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c2, setD) {
        Future<void> los() async {
          setD(() => laedt = true);
          try {
            final r = await widget.apiService.searchPflegedienst(search: searchC.text.trim());
            if (r['success'] == true && r['pflegedienste'] is List) {
              treffer = (r['pflegedienste'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            }
          } catch (_) {}
          setD(() => laedt = false);
        }

        return AlertDialog(
          title: const Text('Pflegedienst suchen', style: TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(children: [
              TextField(
                controller: searchC,
                autofocus: true,
                onSubmitted: (_) => los(),
                decoration: InputDecoration(
                  hintText: 'Name oder Ort…',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(icon: const Icon(Icons.search, size: 18), onPressed: los),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Quelle: Pflegedienst-Datenbank',
                    style: TextStyle(fontSize: 9.5, color: F.h(Colors.grey, 400))),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: laedt
                    ? const Center(child: CircularProgressIndicator())
                    : treffer.isEmpty
                        ? Center(
                            child: Text('Suchbegriff eingeben und suchen',
                                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500))))
                        : ListView.builder(
                            itemCount: treffer.length,
                            itemBuilder: (_, i) {
                              final p = treffer[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(Icons.medical_services, size: 18, color: F.h(Colors.teal, 600)),
                                title: Text(p['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                                subtitle: Text(
                                    [p['strasse'], p['plz_ort']]
                                        .where((e) => (e?.toString() ?? '').isNotEmpty)
                                        .join(', '),
                                    style: const TextStyle(fontSize: 11)),
                                onTap: () => Navigator.pop(c, p),
                              );
                            },
                          ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen'))],
        );
      }),
    ).then((gewaehlt) async {
      searchC.dispose();
      if (gewaehlt is Map) {
        await widget.onAuswahl(Map<String, dynamic>.from(gewaehlt));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pd = widget.pflegedienst;
    if (pd == null || (pd['name']?.toString() ?? '').isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.medical_services_outlined, size: 44, color: F.h(Colors.grey, 300)),
            const SizedBox(height: 8),
            Text('Noch kein Pflegedienst zugeordnet',
                style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
            const SizedBox(height: 4),
            Text('Der Pflegedienst führt die Verordnung aus und erhält Ausfertigung 12b.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600),
              onPressed: _suche,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Pflegedienst suchen'),
            ),
          ]),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
          child: Row(children: [
            Icon(Icons.medical_services, size: 18, color: F.h(Colors.teal, 700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(pd['name']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
            ),
            IconButton(
                icon: const Icon(Icons.swap_horiz, size: 18),
                tooltip: 'Anderen Pflegedienst wählen',
                onPressed: _suche),
            IconButton(
                icon: Icon(Icons.link_off, size: 18, color: Colors.red.shade400),
                tooltip: 'Zuordnung aufheben',
                onPressed: () => widget.onAuswahl(null)),
          ]),
        ),
        TabBar(
          labelColor: F.h(Colors.teal, 700),
          unselectedLabelColor: F.h(Colors.grey, 500),
          indicatorColor: Colors.teal.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
            Tab(icon: Icon(Icons.mail_outline, size: 16), text: 'Korrespondenz'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _details(pd),
            _HkpKorrespondenzListe(
              apiService: widget.apiService,
              userId: widget.userId,
              verordnungId: widget.verordnungId,
              kanal: 'pflegedienst',
              titel: 'Korrespondenz mit dem Pflegedienst',
              hinweis: 'Einsatzplan, Leistungsnachweis, Rückfragen — Ausfertigung 12b.',
              farbe: Colors.teal,
              attachmentModul: 'hkp_pflegedienst_korr',
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _details(Map<String, dynamic> pd) {
    Widget zeile(IconData i, String label, String val) {
      if (val.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: F.h(Colors.teal, 600)),
          const SizedBox(width: 10),
          SizedBox(width: 90, child: Text(label, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))),
          Expanded(child: Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(pd['name']?.toString() ?? '',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800))),
        const Divider(height: 24),
        zeile(
            Icons.location_on,
            'Adresse',
            [pd['strasse'], pd['plz_ort']].where((e) => (e?.toString() ?? '').isNotEmpty).join(', ')),
        zeile(Icons.phone, 'Telefon', pd['telefon']?.toString() ?? ''),
        zeile(Icons.print, 'Fax', pd['fax']?.toString() ?? ''),
        zeile(Icons.email, 'E-Mail', pd['email']?.toString() ?? ''),
        zeile(Icons.language, 'Website', pd['website']?.toString() ?? ''),
        zeile(Icons.notes, 'Notizen', pd['notizen']?.toString() ?? ''),
        if ((pd['id']?.toString() ?? '0') == '0')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'Dieser Eintrag steht nicht mehr in der Pflegedienst-Datenbank — angezeigt wird der gespeicherte Name.',
                style: TextStyle(fontSize: 10.5, color: F.h(Colors.orange, 800), fontStyle: FontStyle.italic)),
          ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Korrespondenz — einmal geschrieben, für beide Kanäle (Kasse, Pflegedienst)
// ═══════════════════════════════════════════════════════════════════════════

class _HkpKorrespondenzListe extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int verordnungId;

  /// 'kasse' oder 'pflegedienst' — entscheidet über die Tabelle auf dem Server.
  final String kanal;
  final String titel;
  final String hinweis;
  final MaterialColor farbe;

  /// Eigener modul-Name je Kanal: Anhänge sind nur über (modul, id) verschlüsselt
  /// zugeordnet, ein gemeinsamer Name würde beide Stränge vermischen.
  final String attachmentModul;

  const _HkpKorrespondenzListe({
    required this.apiService,
    required this.userId,
    required this.verordnungId,
    required this.kanal,
    required this.titel,
    required this.hinweis,
    required this.farbe,
    required this.attachmentModul,
  });

  @override
  State<_HkpKorrespondenzListe> createState() => _HkpKorrespondenzListeState();
}

class _HkpKorrespondenzListeState extends State<_HkpKorrespondenzListe> {
  List<Map<String, dynamic>> _korr = [];
  bool _geladen = false;

  static const _kontaktarten = <(String, String, IconData)>[
    ('online', 'Online', Icons.language),
    ('email', 'E-Mail', Icons.email),
    ('fax', 'Fax', Icons.print),
    ('telefonisch', 'Telefonisch', Icons.phone),
    ('persoenlich', 'Persönlich', Icons.person),
    ('post', 'Post', Icons.local_post_office),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.apiService.hkpVerordnungAction({
        'action': 'korr_list',
        'user_id': widget.userId,
        'verordnung_id': widget.verordnungId,
        'kanal': widget.kanal,
      });
      if (!mounted) return;
      if (r['success'] == true && r['korrespondenz'] is List) {
        _korr = (r['korrespondenz'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _geladen = true);
  }

  String _kontaktLabel(String k) {
    for (final e in _kontaktarten) {
      if (e.$1 == k) return e.$2;
    }
    return k;
  }

  IconData _kontaktIcon(String k) {
    for (final e in _kontaktarten) {
      if (e.$1 == k) return e.$3;
    }
    return Icons.contact_mail;
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${widget.titel} (${_korr.length})',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              Text(widget.hinweis, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
            ]),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.call_received, size: 14),
            label: const Text('Eingang', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero),
            onPressed: () => _dialog('eingang'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            icon: const Icon(Icons.call_made, size: 14),
            label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero),
            onPressed: () => _dialog('ausgang'),
          ),
        ]),
      ),
      Expanded(
        child: _korr.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mail_outline, size: 46, color: F.h(Colors.grey, 300)),
                  const SizedBox(height: 6),
                  Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500))),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _korr.length,
                itemBuilder: (_, i) {
                  final k = _korr[i];
                  final isEingang = k['richtung'] == 'eingang';
                  final ka = k['kontaktart']?.toString() ?? '';
                  return InkWell(
                    onTap: () => _dialog(k['richtung']?.toString() ?? 'ausgang', vorhanden: k),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: F.flaeche,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isEingang ? F.h(Colors.green, 200) : F.h(Colors.blue, 200)),
                      ),
                      child: Row(children: [
                        Icon(isEingang ? Icons.call_received : Icons.call_made,
                            size: 18, color: isEingang ? F.h(Colors.green, 700) : F.h(Colors.blue, 700)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                                (k['betreff']?.toString() ?? '').isNotEmpty
                                    ? k['betreff'].toString()
                                    : 'Ohne Betreff',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isEingang ? F.h(Colors.green, 800) : F.h(Colors.blue, 800))),
                            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Text(isEingang ? 'Eingang' : 'Ausgang',
                                  style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                              if (ka.isNotEmpty) ...[
                                Text('  •  ', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 400))),
                                Icon(_kontaktIcon(ka), size: 11, color: F.h(Colors.grey, 600)),
                                const SizedBox(width: 3),
                                Text(_kontaktLabel(ka), style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                              ],
                              if ((k['datum']?.toString() ?? '').isNotEmpty) ...[
                                Text('  •  ', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 400))),
                                Text(k['datum'].toString(),
                                    style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                              ],
                            ]),
                            if ((k['inhalt']?.toString() ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(k['inhalt'].toString(),
                                    style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 700)),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ]),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => _loeschen(int.tryParse(k['id']?.toString() ?? '') ?? 0),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _loeschen(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text('Diesen Korrespondenz-Eintrag wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.apiService.hkpVerordnungAction({
        'action': 'korr_delete',
        'user_id': widget.userId,
        'id': id,
        'kanal': widget.kanal,
      });
    } catch (_) {}
    await _load();
  }

  void _dialog(String richtung, {Map<String, dynamic>? vorhanden}) {
    Map<String, dynamic>? cur = vorhanden;
    bool bearbeiten = vorhanden == null;
    String rich = vorhanden?['richtung']?.toString() ?? richtung;
    String kontaktart = vorhanden?['kontaktart']?.toString() ?? '';
    final datumC = TextEditingController(text: vorhanden?['datum']?.toString() ?? '');
    final betreffC = TextEditingController(text: vorhanden?['betreff']?.toString() ?? '');
    final inhaltC = TextEditingController(text: vorhanden?['inhalt']?.toString() ?? '');
    bool speichert = false;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c2, setD) {
        final isEingang = rich == 'eingang';
        final curId = int.tryParse(cur?['id']?.toString() ?? '') ?? 0;

        Widget roZeile(String label, String val, {IconData? icon}) {
          if (val.trim().isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 84, child: Text(label, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)))),
              if (icon != null) ...[Icon(icon, size: 13, color: F.h(Colors.grey, 700)), const SizedBox(width: 4)],
              Expanded(child: Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            ]),
          );
        }

        Widget nurLesen() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              roZeile('Richtung', isEingang ? 'Eingang' : 'Ausgang',
                  icon: isEingang ? Icons.call_received : Icons.call_made),
              if (kontaktart.isNotEmpty)
                roZeile('Kontaktart', _kontaktLabel(kontaktart), icon: _kontaktIcon(kontaktart)),
              roZeile('Datum', datumC.text),
              roZeile('Betreff', betreffC.text),
              if (inhaltC.text.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Inhalt', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                const SizedBox(height: 3),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: F.h(Colors.grey, 50),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: F.h(Colors.grey, 200))),
                  child: Text(inhaltC.text, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ]);

        Widget bearbeitung() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, children: [
                for (final r in [
                  ('eingang', 'Eingang', Icons.call_received, Colors.green),
                  ('ausgang', 'Ausgang', Icons.call_made, Colors.blue)
                ])
                  ChoiceChip(
                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(r.$3, size: 14, color: rich == r.$1 ? Colors.white : F.h(Colors.grey, 700)),
                      const SizedBox(width: 4),
                      Text(r.$2, style: TextStyle(fontSize: 11, color: rich == r.$1 ? Colors.white : F.textStark)),
                    ]),
                    selected: rich == r.$1,
                    selectedColor: r.$4,
                    onSelected: (_) => setD(() => rich = r.$1),
                  ),
              ]),
              const SizedBox(height: 12),
              Text('Kontaktart',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final ka in _kontaktarten)
                  ChoiceChip(
                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(ka.$3, size: 13, color: kontaktart == ka.$1 ? Colors.white : F.h(Colors.grey, 700)),
                      const SizedBox(width: 4),
                      Text(ka.$2,
                          style: TextStyle(fontSize: 11, color: kontaktart == ka.$1 ? Colors.white : F.textStark)),
                    ]),
                    selected: kontaktart == ka.$1,
                    selectedColor: widget.farbe.shade500,
                    onSelected: (_) => setD(() => kontaktart = kontaktart == ka.$1 ? '' : ka.$1),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: datumC,
                readOnly: true,
                decoration: const InputDecoration(
                    labelText: 'Datum',
                    isDense: true,
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today, size: 16)),
                onTap: () async {
                  final p = await showDatePicker(
                      context: c2,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2040),
                      locale: const Locale('de'));
                  if (p != null) {
                    setD(() => datumC.text =
                        '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}');
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: betreffC,
                  decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: inhaltC,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: 'Inhalt',
                      isDense: true,
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true)),
            ]);

        return AlertDialog(
          title: Row(children: [
            Icon(isEingang ? Icons.call_received : Icons.call_made,
                size: 20, color: isEingang ? F.h(Colors.green, 700) : F.h(Colors.blue, 700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  vorhanden == null
                      ? 'Neue Korrespondenz'
                      : (bearbeiten ? 'Korrespondenz bearbeiten' : 'Korrespondenz'),
                  style: const TextStyle(fontSize: 15)),
            ),
            if (!bearbeiten)
              IconButton(
                  icon: Icon(Icons.edit, size: 18, color: F.h(widget.farbe, 600)),
                  tooltip: 'Bearbeiten',
                  onPressed: () => setD(() => bearbeiten = true)),
          ]),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                bearbeiten ? bearbeitung() : nurLesen(),
                if (curId > 0) ...[
                  const Divider(height: 24),
                  KorrAttachmentsWidget(
                    apiService: widget.apiService,
                    memberId: widget.userId,
                    modul: widget.attachmentModul,
                    korrespondenzId: curId,
                    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
                    maxFiles: 20,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('PDF/JPG/PNG · max. 20 gleichzeitig',
                        style: TextStyle(fontSize: 9, color: F.h(Colors.grey, 400))),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Text('Dateien können nach dem Speichern hinzugefügt werden.',
                      style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 500), fontStyle: FontStyle.italic)),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: speichert ? null : () => Navigator.pop(c),
                child: Text(bearbeiten ? 'Abbrechen' : 'Schließen')),
            if (bearbeiten)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: widget.farbe.shade600),
                onPressed: speichert
                    ? null
                    : () async {
                        setD(() => speichert = true);
                        try {
                          final res = await widget.apiService.hkpVerordnungAction({
                            'action': 'korr_save',
                            'user_id': widget.userId,
                            'verordnung_id': widget.verordnungId,
                            'kanal': widget.kanal,
                            'korr': {
                              if (curId > 0) 'id': curId,
                              'richtung': rich,
                              'kontaktart': kontaktart,
                              'datum': datumC.text.trim(),
                              'betreff': betreffC.text.trim(),
                              'inhalt': inhaltC.text.trim(),
                            },
                          });
                          if (!mounted) return;
                          if (res['success'] != true) {
                            setD(() => speichert = false);
                            if (c2.mounted) {
                              ScaffoldMessenger.of(c2).showSnackBar(SnackBar(
                                  content: Text('Nicht gespeichert: ${res['message'] ?? 'unbekannter Fehler'}'),
                                  backgroundColor: Colors.red));
                            }
                            return;
                          }
                          final neuId = int.tryParse(res['id']?.toString() ?? '') ?? curId;
                          await _load();
                          if (!c2.mounted) return;
                          setD(() {
                            cur = {
                              'id': neuId,
                              'richtung': rich,
                              'kontaktart': kontaktart,
                              'datum': datumC.text.trim(),
                              'betreff': betreffC.text.trim(),
                              'inhalt': inhaltC.text.trim(),
                            };
                            bearbeiten = false;
                            speichert = false;
                          });
                        } catch (e) {
                          setD(() => speichert = false);
                          if (c2.mounted) {
                            ScaffoldMessenger.of(c2)
                                .showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                          }
                        }
                      },
                child: speichert
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Speichern'),
              ),
          ],
        );
      }),
    ).then((_) {
      datumC.dispose();
      betreffC.dispose();
      inhaltC.dispose();
    });
  }
}
