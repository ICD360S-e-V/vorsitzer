import 'package:flutter/material.dart';
import 'phone_link.dart';
import 'file_viewer_dialog.dart';
import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../utils/auslaenderbehoerde_vorfaelle.dart';
import '../utils/auslaenderbehoerde_dokumente.dart';
import '../utils/file_picker_helper.dart';

String _deFmt(DateTime p) =>
    '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';

class BehordeAuslaenderbehoerdeContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const BehordeAuslaenderbehoerdeContent({
    super.key,
    required this.apiService,
    required this.userId,
  });

  @override
  State<BehordeAuslaenderbehoerdeContent> createState() => _State();
}

class _State extends State<BehordeAuslaenderbehoerdeContent>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loaded = false, _loading = false;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _vorfaelle = [];

  /// Die Fortgeltungs-Angaben kommen vom Server, damit eine neue
  /// Ukraine-Verordnung ohne App-Release wirksam wird — die nächste ist im
  /// Herbst 2026 fällig. Die kompilierten Werte sind nur der Rückfall für den
  /// Fall, dass eine ältere Serverfassung sie nicht mitschickt.
  String _uaBis = kUkraineFortgeltungBis;
  String _uaStichtag = kUkraineStichtag;
  String _uaEuBis = kUkraineEuBeschlossenBis;

  /// Die Ämter in Reichweite des Vereins.
  ///
  /// ⚠️ Neu-Ulm: die Große Kreisstadt hat KEINE eigene Ausländerbehörde und
  /// verweist auf das Landratsamt — das ist auch für die Stadt zuständig.
  /// ⚠️ Ulm veröffentlicht keine E-Mail-Adresse im Klartext, nur ein
  /// Kontaktformular. Hier steht deshalb keine — geraten wird nicht.
  /// ⚠️ Der Alb-Donau-Kreis gehört dazu, weil viele mit Ulmer Postadresse
  /// tatsächlich im Landkreis wohnen und dann dorthin müssen.
  static const _aemter = [
    {
      'name': 'Landratsamt Neu-Ulm — Ausländer- und Staatsangehörigkeitsrecht',
      'adresse': 'Kantstraße 8, 89231 Neu-Ulm',
      'telefon': '0731 7040-51011',
      'telefon2': '0731 7040-51012',
      'fax': '0731 7040-51999',
      'email': 'poststelle@landkreis-nu.de',
      'oeffnungszeiten': 'Schalter Mo–Fr 10:00–12:00, nur mit Termin · '
          'telefonisch Mo–Fr 07:30–12:30, Do zusätzlich bis 17:30',
      'zustaendig': 'Landkreis Neu-Ulm einschließlich der Stadt Neu-Ulm',
    },
    {
      'name': 'Stadt Ulm — Ausländer- und Einbürgerungsbehörde',
      'adresse': 'Olgastraße 66, 89073 Ulm',
      'telefon': '0731 161-3334',
      'oeffnungszeiten': 'Ausländerwesen: Mo 08:00–12:00 und 14:00–16:00 (nachmittags mit Termin), '
          'Di 08:00–12:00, Do 08:00–12:00 und 14:00–17:30 (mit Termin), Fr 08:00–12:00 · Mi geschlossen',
      'zustaendig': 'nur Personen mit Wohnsitz in Ulm. Staatsangehörigkeitswesen '
          'hat eigene Öffnungszeiten und ist seit 01.05.2025 nur mit Termin erreichbar.',
    },
    {
      'name': 'Landratsamt Alb-Donau-Kreis — Ausländerrecht',
      'adresse': 'Schaffnerstraße 3, 89073 Ulm',
      'zustaendig': 'Gemeinden des Alb-Donau-Kreises (Blaustein, Erbach, Ehingen, Laichingen …)',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String _v(String f) => _data[f]?.toString() ?? '';

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.getAuslaenderbehoerdeData(widget.userId);
      if (res['success'] == true && mounted) {
        final raw = res['data'];
        if (raw is Map) {
          _data = {};
          for (final e in raw.entries) {
            final parts = e.key.toString().split('.');
            _data[parts.length == 2 ? parts[1] : e.key.toString()] = e.value;
          }
        }
        _vorfaelle = (res['vorfaelle'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // ⚠️ Nur übernehmen, was auch wirklich dasteht — ein leeres Feld
        // dürfte nie den kompilierten Wert löschen, sonst stünde nach einem
        // Serverfehler gar kein Datum auf dem Schirm.
        final ua = res['ukraine'];
        if (ua is Map) {
          final b = ua['fortgeltung_bis']?.toString() ?? '';
          final st = ua['stichtag']?.toString() ?? '';
          final eu = ua['eu_bis']?.toString() ?? '';
          if (b.isNotEmpty) _uaBis = b;
          if (st.isNotEmpty) _uaStichtag = st;
          if (eu.isNotEmpty) _uaEuBis = eu;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _loading = false;
        _loaded = true;
      });
    }
  }

  Future<void> _saveFields(Map<String, dynamic> fields) async {
    try {
      final mapped = <String, dynamic>{};
      for (final e in fields.entries) {
        mapped['stammdaten.${e.key}'] = e.value?.toString() ?? '';
      }
      await widget.apiService.saveAuslaenderbehoerdeData(widget.userId, mapped);
      for (final e in fields.entries) {
        _data[e.key] = e.value;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  /// Der jüngste Vorfall, der überhaupt einen Aufenthaltsstatus trägt.
  ///
  /// ⚠️ Die Liste kommt vom Server nach `id DESC`, also neueste zuerst — der
  /// erste Treffer ist damit der aktuelle Stand. Nach dem (verschlüsselten,
  /// frei getippten) Datum zu sortieren wäre nicht möglich.
  Map<String, dynamic>? get _aktuellerStand {
    for (final v in _vorfaelle) {
      final hatStatus = (v['aufenthaltsstatus']?.toString() ?? '').isNotEmpty ||
          (v['aufenthaltstitel']?.toString() ?? '').isNotEmpty ||
          (v['gueltig_bis']?.toString() ?? '').isNotEmpty;
      if (hatStatus) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_loading) _load();
    if (_loading || !_loaded) return const Center(child: CircularProgressIndicator());
    final amtGesetzt = _v('dienststelle').isNotEmpty;
    return Column(children: [
      TabBar(
        controller: _tabCtrl,
        labelColor: F.h(Colors.indigo, 700),
        unselectedLabelColor: F.h(Colors.grey, 500),
        indicatorColor: Colors.indigo.shade700,
        tabs: [
          Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: amtGesetzt ? Colors.green : Colors.red),
            const SizedBox(width: 4),
            const Icon(Icons.account_balance, size: 16),
            const SizedBox(width: 4),
            const Flexible(
                child: Text('Zuständige Ausländerbehörde', overflow: TextOverflow.ellipsis)),
          ])),
          Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _vorfaelle.isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4),
            const Icon(Icons.assignment, size: 16),
            const SizedBox(width: 4),
            const Flexible(child: Text('Vorfall', overflow: TextOverflow.ellipsis)),
          ])),
        ],
      ),
      Expanded(
          child: TabBarView(
              controller: _tabCtrl, children: [_buildAmtTab(), _buildVorfallTab()])),
    ]);
  }

  // ══ Reiter 1: das zuständige Amt ═══════════════════════════════════════
  Widget _buildAmtTab() {
    final selected = _aemter.firstWhere((b) => b['name'] == _v('dienststelle'),
        orElse: () => <String, String>{});
    final stand = _aktuellerStand;
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Zuständige Ausländerbehörde',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 700))),
          const SizedBox(height: 8),
          Autocomplete<Map<String, String>>(
            initialValue: TextEditingValue(text: _v('dienststelle')),
            displayStringForOption: (b) => b['name'] ?? '',
            optionsBuilder: (textEditingValue) {
              final q = textEditingValue.text.trim().toLowerCase();
              if (q.isEmpty) return _aemter;
              return _aemter.where((b) =>
                  (b['name'] ?? '').toLowerCase().contains(q) ||
                  (b['adresse'] ?? '').toLowerCase().contains(q));
            },
            fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            controller.clear();
                            setState(() => _data['dienststelle'] = '');
                            _saveFields({'dienststelle': ''});
                          },
                        )
                      : null,
                  hintText: 'Ausländerbehörde suchen…',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: (val) {
                  setState(() => _data['dienststelle'] = val.trim());
                  _saveFields({'dienststelle': val.trim()});
                  onFieldSubmitted();
                },
              );
            },
            optionsViewBuilder: (ctx, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280, maxWidth: 520),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: options
                          .map((b) => InkWell(
                                onTap: () => onSelected(b),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(b['name'] ?? '',
                                            style: const TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.bold)),
                                        if ((b['adresse'] ?? '').isNotEmpty)
                                          Text(b['adresse']!,
                                              style: TextStyle(
                                                  fontSize: 11, color: F.h(Colors.grey, 600))),
                                      ]),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              );
            },
            onSelected: (b) {
              setState(() => _data['dienststelle'] = b['name']);
              _saveFields({'dienststelle': b['name'] ?? ''});
            },
          ),
          const SizedBox(height: 16),
          if (_v('dienststelle').isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: F.h(Colors.indigo, 50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: F.h(Colors.indigo, 300))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.account_balance, size: 24, color: F.h(Colors.indigo, 700)),
                const SizedBox(width: 12),
                Expanded(
                    child:
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_v('dienststelle'),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: F.h(Colors.indigo, 800))),
                  if (selected.isNotEmpty) ...[
                    if ((selected['adresse'] ?? '').isNotEmpty)
                      _zeile(Icons.location_on, selected['adresse']!),
                    if ((selected['telefon'] ?? '').isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: PhoneTapTarget(
                              number: selected['telefon'],
                              label: _v('dienststelle'),
                              child: Row(children: [
                                Icon(Icons.phone, size: 12, color: F.h(Colors.grey, 600)),
                                const SizedBox(width: 4),
                                Text(
                                    selected['telefon']! +
                                        ((selected['telefon2'] ?? '').isNotEmpty
                                            ? '  (A–Ko)'
                                            : ''),
                                    style: TextStyle(
                                        fontSize: 11, color: F.h(Colors.grey, 700))),
                              ]))),
                    if ((selected['telefon2'] ?? '').isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: PhoneTapTarget(
                              number: selected['telefon2'],
                              label: _v('dienststelle'),
                              child: Row(children: [
                                Icon(Icons.phone, size: 12, color: F.h(Colors.grey, 600)),
                                const SizedBox(width: 4),
                                Text('${selected['telefon2']!}  (Kp–Z)',
                                    style: TextStyle(
                                        fontSize: 11, color: F.h(Colors.grey, 700))),
                              ]))),
                    if ((selected['fax'] ?? '').isNotEmpty)
                      _zeile(Icons.print, 'Fax ${selected['fax']}'),
                    if ((selected['email'] ?? '').isNotEmpty)
                      _zeile(Icons.email, selected['email']!),
                    if ((selected['oeffnungszeiten'] ?? '').isNotEmpty)
                      _zeile(Icons.schedule, selected['oeffnungszeiten']!, klein: true),
                    if ((selected['zustaendig'] ?? '').isNotEmpty)
                      _zeile(Icons.info_outline, 'Zuständig: ${selected['zustaendig']}',
                          klein: true),
                  ] else
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Manuell eingegeben',
                            style: TextStyle(
                                fontSize: 10,
                                color: F.h(Colors.grey, 600),
                                fontStyle: FontStyle.italic))),
                ])),
              ]),
            ),
          const SizedBox(height: 16),
          // Der aktuelle Stand — nur wenn es ihn wirklich gibt.
          if (stand != null) _standKarte(stand),
          const SizedBox(height: 12),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 14, color: F.h(Colors.grey, 500)),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(
                        'Aufenthaltsstatus, Titel, Aktenzeichen und Gültigkeit werden pro Vorfall '
                        'erfasst — jede Verlängerung ist ein eigener Vorgang mit eigenem Ablaufdatum.',
                        style: TextStyle(
                            fontSize: 11,
                            color: F.h(Colors.grey, 600),
                            fontStyle: FontStyle.italic))),
              ])),
          // ⚠️ Einbürgerung ist nicht die Ausländerbehörde. Der Hinweis steht
          // hier, weil beide fast immer im selben Haus sitzen und man den
          // Unterschied sonst erst im Anschreiben bemerkt.
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: F.h(Colors.amber, 50),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: F.h(Colors.amber, 200))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber, size: 14, color: F.h(Colors.amber, 800)),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(
                        'Einbürgerung und Staatsangehörigkeit macht die Staatsangehörigkeits'
                        'behörde — meist dasselbe Haus, aber eigener Schalter. Diese Vorgänge '
                        'gehören in den Reiter „Landratsamt".',
                        style: TextStyle(fontSize: 10, color: F.h(Colors.amber, 900)))),
              ])),
        ]));
  }

  Widget _zeile(IconData icon, String text, {bool klein = false}) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 12, color: F.h(Colors.grey, 600)),
        const SizedBox(width: 4),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: klein ? 10 : 11,
                    color: F.h(Colors.grey, klein ? 600 : 700)))),
      ]));

  Widget _standKarte(Map<String, dynamic> v) {
    final typ = v['typ']?.toString() ?? '';
    // 🔴 § 24 zuerst: dort gilt das Kartendatum nicht, und eine Ablaufwarnung
    // wäre falsch. Siehe kUkraineFortgeltungBis.
    if (abFortgeltung(typ)) return _fortgeltungKarte(v);
    final ablauf = abDatumLesen(v['gueltig_bis']?.toString());
    final faellig = abLaeuftBaldAb(typ, ablauf);
    final abgelaufen = ablauf != null &&
        DateTime(ablauf.year, ablauf.month, ablauf.day).isBefore(
            DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));
    final farbe = abgelaufen ? Colors.red : (faellig ? Colors.orange : Colors.green);
    final info = abTypFinden(typ);
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: F.h(farbe, 50),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: F.h(farbe, 300))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.badge, size: 18, color: F.h(farbe, 700)),
            const SizedBox(width: 8),
            Text('Aktueller Stand',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: F.h(farbe, 800))),
          ]),
          const SizedBox(height: 6),
          if ((v['aufenthaltstitel']?.toString() ?? '').isNotEmpty)
            Text(v['aufenthaltstitel'].toString(),
                style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 800))),
          if ((v['aufenthaltsstatus']?.toString() ?? '').isNotEmpty)
            Text(kAufenthaltsstatusLabel[v['aufenthaltsstatus'].toString()] ??
                    v['aufenthaltsstatus'].toString(),
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
          if ((v['aktenzeichen']?.toString() ?? '').isNotEmpty)
            Text('Aktenzeichen: ${v['aktenzeichen']}',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          if (ablauf != null) ...[
            const SizedBox(height: 4),
            Text(
                abgelaufen
                    ? 'Abgelaufen am ${v['gueltig_bis']}'
                    : 'Gültig bis ${v['gueltig_bis']}',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: F.h(farbe, 800))),
            if (faellig && info?.frist != null)
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                      abgelaufen
                          ? 'Bitte umgehend bei der Ausländerbehörde vorsprechen.'
                          : 'Verlängerung jetzt beantragen — ${info!.frist!.dokument}.',
                      style: TextStyle(fontSize: 11, color: F.h(farbe, 900)))),
          ],
          const SizedBox(height: 4),
          Text('aus Vorfall: ${v['titel']?.toString().isNotEmpty == true ? v['titel'] : typ}',
              style: TextStyle(
                  fontSize: 10,
                  color: F.h(Colors.grey, 600),
                  fontStyle: FontStyle.italic)),
        ]));
  }

  /// Der Stand bei gesetzlicher Fortgeltung (§ 24, Ukraine).
  ///
  /// ⚠️ Hier steht bewusst KEIN „läuft ab" und keine Aufforderung zu einem
  /// Termin. Was hier fehlt, ist wichtiger als was dasteht.
  Widget _fortgeltungKarte(Map<String, dynamic> v) {
    final kartenDatum = v['gueltig_bis']?.toString() ?? '';
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: F.h(Colors.green, 50),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: F.h(Colors.green, 300))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.verified, size: 18, color: F.h(Colors.green, 700)),
            const SizedBox(width: 8),
            Text('Gilt kraft Verordnung weiter',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: F.h(Colors.green, 800))),
          ]),
          const SizedBox(height: 6),
          Text('Aufenthaltserlaubnis nach § 24 AufenthG',
              style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 800))),
          const SizedBox(height: 4),
          Text('Verlängert bis $_uaBis',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: F.h(Colors.green, 800))),
          const SizedBox(height: 6),
          Text(
              'Kein Antrag, kein Termin, keine neue Karte. Die Erlaubnis gilt auch '
              'dann, wenn das Datum auf der Karte abgelaufen ist'
              '${kartenDatum.isEmpty ? '' : ' (dort steht $kartenDatum)'}.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 800))),
          const SizedBox(height: 8),
          // ⚠️ Der Stichtag ist die eine Bedingung, an der es scheitern kann —
          // wer ihn verpasst hat, fällt aus der Fortgeltung heraus und braucht
          // die Behörde doch.
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: F.h(Colors.amber, 50),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: F.h(Colors.amber, 200))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 14, color: F.h(Colors.amber, 800)),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(
                        'Voraussetzung: die Erlaubnis war am $_uaStichtag gültig. '
                        'War sie das nicht, gilt die Fortgeltung nicht — dann bitte die '
                        'Ausländerbehörde ansprechen. Das gilt auch für Mitglieder ohne '
                        'ukrainische Staatsangehörigkeit.',
                        style: TextStyle(fontSize: 10, color: F.h(Colors.amber, 900)))),
              ])),
          const SizedBox(height: 6),
          Text(
              'Die EU hat den Schutz bereits bis $_uaEuBis verlängert; '
              'Deutschland muss das noch in einer eigenen Verordnung nachvollziehen.',
              style: TextStyle(
                  fontSize: 10,
                  color: F.h(Colors.grey, 600),
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 4),
          Text(
              'aus Vorfall: ${v['titel']?.toString().isNotEmpty == true ? v['titel'] : kUkraineTyp}',
              style: TextStyle(
                  fontSize: 10,
                  color: F.h(Colors.grey, 600),
                  fontStyle: FontStyle.italic)),
        ]));
  }

  // ══ Reiter 2: Vorfälle ═════════════════════════════════════════════════
  Widget _buildVorfallTab() {
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(Icons.assignment, size: 18, color: F.h(Colors.indigo, 700)),
            const SizedBox(width: 8),
            Text('${_vorfaelle.length} Vorfälle',
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
            const Spacer(),
            FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Neuer Vorfall', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero),
                onPressed: () => _showVorfallDialog()),
          ])),
      Expanded(
          child: _vorfaelle.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.assignment_late, size: 48, color: F.h(Colors.grey, 300)),
                  const SizedBox(height: 8),
                  Text('Keine Vorfälle',
                      style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500))),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _vorfaelle.length,
                  itemBuilder: (_, i) => _vorfallKarte(_vorfaelle[i]))),
    ]);
  }

  Widget _vorfallKarte(Map<String, dynamic> v) {
    final status = v['status']?.toString() ?? 'offen';
    final sc = status == 'erledigt'
        ? Colors.green
        : status == 'in_bearbeitung'
            ? Colors.orange
            : Colors.blue;
    final typ = v['typ']?.toString() ?? '';
    final ablauf = abDatumLesen(v['gueltig_bis']?.toString());
    final faellig = abLaeuftBaldAb(typ, ablauf);
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showVorfallDetailDialog(v),
            child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: F.h(Colors.indigo, 50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: F.h(Colors.indigo, 200))),
                child: Row(children: [
                  Icon(Icons.assignment, size: 18, color: F.h(Colors.indigo, 700)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                          child: Text(
                              v['titel']?.toString().isNotEmpty == true
                                  ? v['titel'].toString()
                                  : typ,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: F.h(Colors.indigo, 800)))),
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: F.h(sc, 100), borderRadius: BorderRadius.circular(6)),
                          child: Text(
                              status == 'erledigt'
                                  ? 'Erledigt'
                                  : status == 'in_bearbeitung'
                                      ? 'In Bearbeitung'
                                      : 'Offen',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: F.h(sc, 800)))),
                    ]),
                    if ((v['datum']?.toString() ?? '').isNotEmpty)
                      Text(v['datum'].toString(),
                          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                    if (typ.isNotEmpty && typ != v['titel'])
                      Text(typ,
                          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
                    if (abFortgeltung(typ))
                      Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(children: [
                            Icon(Icons.verified,
                                size: 12, color: F.h(Colors.green, 700)),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(
                                    'gilt kraft Verordnung bis $_uaBis',
                                    style: TextStyle(
                                        fontSize: 11, color: F.h(Colors.green, 800)))),
                          ]))
                    else if (ablauf != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(children: [
                            Icon(faellig ? Icons.warning_amber : Icons.event_available,
                                size: 12,
                                color: faellig
                                    ? F.h(Colors.orange, 800)
                                    : F.h(Colors.grey, 600)),
                            const SizedBox(width: 4),
                            Text('gültig bis ${v['gueltig_bis']}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight:
                                        faellig ? FontWeight.bold : FontWeight.normal,
                                    color: faellig
                                        ? F.h(Colors.orange, 900)
                                        : F.h(Colors.grey, 600))),
                          ])),
                  ])),
                  const SizedBox(width: 4),
                  IconButton(
                      icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () async {
                        final id = v['id'] is int
                            ? v['id'] as int
                            : int.parse(v['id'].toString());
                        await widget.apiService
                            .deleteAuslaenderbehoerdeVorfall(widget.userId, id);
                        await _load();
                      }),
                ]))));
  }

  /// Neu oder bearbeiten — dasselbe Formular, damit die Felder nicht
  /// auseinanderlaufen.
  void _showVorfallDialog([Map<String, dynamic>? vorhanden]) {
    final id = vorhanden == null
        ? 0
        : (vorhanden['id'] is int
            ? vorhanden['id'] as int
            : int.parse(vorhanden['id'].toString()));
    final titelC = TextEditingController(text: vorhanden?['titel']?.toString() ?? '');
    final datumC = TextEditingController(text: vorhanden?['datum']?.toString() ?? '');
    final aktenC = TextEditingController(text: vorhanden?['aktenzeichen']?.toString() ?? '');
    final notizC = TextEditingController(text: vorhanden?['notiz']?.toString() ?? '');
    final titelDokC =
        TextEditingController(text: vorhanden?['aufenthaltstitel']?.toString() ?? '');
    final gueltigC = TextEditingController(text: vorhanden?['gueltig_bis']?.toString() ?? '');
    final sachC = TextEditingController(text: vorhanden?['sachbearbeiter']?.toString() ?? '');
    String typ = vorhanden?['typ']?.toString() ?? '';
    String status = vorhanden?['status']?.toString() ?? 'offen';
    String aufStatus = vorhanden?['aufenthaltsstatus']?.toString() ?? '';

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
              final info = abTypFinden(typ);
              return AlertDialog(
                title: Row(children: [
                  Icon(id == 0 ? Icons.add_circle : Icons.edit,
                      size: 18, color: F.h(Colors.indigo, 700)),
                  const SizedBox(width: 8),
                  Text(id == 0 ? 'Neuer Vorfall' : 'Vorfall bearbeiten',
                      style: const TextStyle(fontSize: 14)),
                ]),
                content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Nach Gruppen unterteilt — 41 Einträge am Stück findet
                      // niemand wieder.
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: typ.isEmpty ? null : typ,
                          decoration: InputDecoration(
                              labelText: 'Anliegen',
                              isDense: true,
                              border:
                                  OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                          items: [
                            for (final g in kAbGruppen) ...[
                              DropdownMenuItem<String>(
                                  enabled: false,
                                  value: '__$g',
                                  child: Text(g.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: F.h(Colors.indigo, 400)))),
                              ...abTypenDerGruppe(g).map((t) => DropdownMenuItem<String>(
                                  value: t.name,
                                  child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Text(t.name,
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis)))),
                            ],
                          ],
                          onChanged: (v) {
                            if (v == null || v.startsWith('__')) return;
                            setDlg(() {
                              typ = v;
                              if (titelC.text.isEmpty) titelC.text = v;
                            });
                          }),
                      if (info?.recht != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(info!.recht!,
                                    style: TextStyle(
                                        fontSize: 11, color: F.h(Colors.grey, 600))))),
                      if (info?.hinweis != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: F.h(Colors.amber, 50),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: F.h(Colors.amber, 200))),
                                child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline,
                                          size: 14, color: F.h(Colors.amber, 800)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(info!.hinweis!,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: F.h(Colors.amber, 900)))),
                                    ]))),
                      const SizedBox(height: 12),
                      TextField(
                          controller: titelC,
                          decoration: InputDecoration(
                              labelText: 'Titel',
                              isDense: true,
                              border:
                                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                      const SizedBox(height: 12),
                      _dateField('Datum', datumC, ctx, setDlg),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: status,
                          decoration: InputDecoration(
                              labelText: 'Status',
                              isDense: true,
                              border:
                                  OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                          items: const [
                            DropdownMenuItem(value: 'offen', child: Text('Offen', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'in_bearbeitung', child: Text('In Bearbeitung', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'erledigt', child: Text('Erledigt', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (v) => setDlg(() => status = v ?? 'offen')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: aktenC,
                          decoration: InputDecoration(
                              labelText: 'Aktenzeichen',
                              prefixIcon: const Icon(Icons.folder, size: 18),
                              isDense: true,
                              border:
                                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                      const SizedBox(height: 12),
                      TextField(
                          controller: sachC,
                          decoration: InputDecoration(
                              labelText: 'Sachbearbeiter/in',
                              prefixIcon: const Icon(Icons.support_agent, size: 18),
                              isDense: true,
                              border:
                                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                      // Der Statusblock erscheint nur, wenn der Vorgang
                      // überhaupt ein befristetes Dokument erzeugt.
                      if (info?.frist != null || info?.fortgeltung == true) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(children: [
                          Icon(Icons.badge, size: 14, color: F.h(Colors.indigo, 600)),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                                  info!.frist?.dokument ??
                                      'Elektronischer Aufenthaltstitel (eAT-Karte)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: F.h(Colors.indigo, 700)))),
                        ]),
                        Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                    info.frist?.laufzeit ??
                                        'gilt kraft Verordnung weiter — das Datum auf der '
                                            'Karte ist nur noch Aufdruck',
                                    style: TextStyle(
                                        fontSize: 10, color: F.h(Colors.grey, 600))))),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: kAufenthaltsstatusLabel.containsKey(aufStatus)
                                ? aufStatus
                                : '',
                            decoration: InputDecoration(
                                labelText: 'Aufenthaltsstatus',
                                isDense: true,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            items: kAufenthaltsstatusLabel.entries
                                .map((e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value,
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) => setDlg(() => aufStatus = v ?? '')),
                        const SizedBox(height: 12),
                        TextField(
                            controller: titelDokC,
                            decoration: InputDecoration(
                                labelText: 'Aufenthaltstitel / Bescheinigung',
                                hintText: 'z. B. § 25 Abs. 1 AufenthG',
                                prefixIcon: const Icon(Icons.description, size: 18),
                                isDense: true,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)))),
                        const SizedBox(height: 12),
                        _dateField(
                            info.fortgeltung
                                ? 'Datum auf der Karte (nur Aufdruck)'
                                : 'Gültig bis',
                            gueltigC,
                            ctx,
                            setDlg),
                        const SizedBox(height: 6),
                        // 🔴 Bei Fortgeltung steht hier bewusst KEINE
                        // Ablauferinnerung — es gibt nichts zu erinnern.
                        Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: info.fortgeltung
                                    ? F.h(Colors.green, 50)
                                    : F.h(Colors.blue, 50),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: info.fortgeltung
                                        ? F.h(Colors.green, 200)
                                        : F.h(Colors.blue, 200))),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                      info.fortgeltung
                                          ? Icons.verified
                                          : Icons.notifications_active,
                                      size: 14,
                                      color: info.fortgeltung
                                          ? F.h(Colors.green, 800)
                                          : F.h(Colors.blue, 800)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(
                                          info.fortgeltung
                                              ? 'Es wird nicht an einen Ablauf erinnert: die '
                                                  'Erlaubnis gilt kraft Verordnung bis '
                                                  '$_uaBis weiter, ohne Antrag '
                                                  'und ohne neue Karte.'
                                              : 'Der Vorfall wird ab ${info.frist!.vorwarnungTage} Tagen '
                                                  'vor Ablauf hervorgehoben.',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: info.fortgeltung
                                                  ? F.h(Colors.green, 900)
                                                  : F.h(Colors.blue, 900)))),
                                ])),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                          controller: notizC,
                          maxLines: 2,
                          decoration: InputDecoration(
                              labelText: 'Notiz',
                              isDense: true,
                              border:
                                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                  FilledButton(
                      onPressed: typ.isEmpty
                          ? null
                          : () async {
                              await widget.apiService.saveAuslaenderbehoerdeVorfall(
                                  widget.userId, {
                                if (id > 0) 'id': id,
                                'typ': typ,
                                'titel': titelC.text.trim(),
                                'status': status,
                                'datum': datumC.text.trim(),
                                'aktenzeichen': aktenC.text.trim(),
                                'notiz': notizC.text.trim(),
                                'aufenthaltsstatus': _statusblockSichtbar(info) ? aufStatus : '',
                                'aufenthaltstitel': _statusblockSichtbar(info)
                                    ? titelDokC.text.trim()
                                    : '',
                                'sachbearbeiter': sachC.text.trim(),
                                'gueltig_bis':
                                    _statusblockSichtbar(info) ? gueltigC.text.trim() : '',
                              });
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _load();
                            },
                      child: const Text('Speichern')),
                ],
              );
            }));
  }

  void _showVorfallDetailDialog(Map<String, dynamic> v) {
    final vid = v['id'] is int ? v['id'] as int : int.parse(v['id'].toString());
    showDialog(
        context: context,
        builder: (ctx) => Dialog(
            child: SizedBox(
                width: 620,
                height: 560,
                child: _AbVorfallDetail(
                    apiService: widget.apiService,
                    userId: widget.userId,
                    vorfallId: vid,
                    vorfall: v,
                    uaBis: _uaBis,
                    uaStichtag: _uaStichtag,
                    onBearbeiten: () {
                      Navigator.pop(ctx);
                      _showVorfallDialog(v);
                    },
                    onChanged: _load))));
  }

  /// Wird der Aufenthaltsblock angezeigt? Genau dann darf er auch gespeichert
  /// werden — sonst schriebe ein Typwechsel im Dialog stumm Werte fort, die
  /// gar nicht mehr auf dem Schirm stehen.
  static bool _statusblockSichtbar(AbVorfallTyp? info) =>
      info?.frist != null || info?.fortgeltung == true;

  Widget _dateField(
      String label, TextEditingController c, BuildContext ctx, StateSetter setDlg) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
      const SizedBox(height: 4),
      TextField(
          controller: c,
          readOnly: true,
          decoration: InputDecoration(
              hintText: 'TT.MM.JJJJ',
              prefixIcon: const Icon(Icons.calendar_today, size: 20),
              suffixIcon: c.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setDlg(() => c.clear())),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          onTap: () async {
            final p = await showDatePicker(
                context: ctx,
                initialDate: abDatumLesen(c.text) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2045),
                locale: const Locale('de'));
            if (p != null) setDlg(() => c.text = _deFmt(p));
          }),
    ]);
  }
}

/// Aufenthaltsstatus — dieselben Werte wie in der Fassung vor der Umstellung,
/// damit übernommene Daten weiter lesbar sind.
const kAufenthaltsstatusLabel = <String, String>{
  '': 'Nicht ausgewählt',
  'aufenthaltserlaubnis': 'Aufenthaltserlaubnis (befristet)',
  'niederlassungserlaubnis': 'Niederlassungserlaubnis (unbefristet)',
  'blaue_karte': 'Blaue Karte EU',
  'duldung': 'Duldung',
  'gestattung': 'Aufenthaltsgestattung',
  'visum': 'Visum',
  'eu_buerger': 'EU-Freizügigkeit',
  'einbuergerung': 'Einbürgerung beantragt',
};

/// Detailansicht eines Vorfalls: Details · Korrespondenz · Verlauf · Termine.
class _AbVorfallDetail extends StatefulWidget {
  final ApiService apiService;
  final int userId, vorfallId;
  final Map<String, dynamic> vorfall;
  final VoidCallback onChanged;
  final VoidCallback onBearbeiten;

  /// Durchgereicht statt hier erneut kompiliert: sonst zeigte der Detailschirm
  /// nach einer neuen Verordnung ein anderes Datum als die Übersicht.
  final String uaBis, uaStichtag;

  const _AbVorfallDetail({
    required this.apiService,
    required this.userId,
    required this.vorfallId,
    required this.vorfall,
    required this.onChanged,
    required this.onBearbeiten,
    required this.uaBis,
    required this.uaStichtag,
  });

  @override
  State<_AbVorfallDetail> createState() => _AbVorfallDetailState();
}

class _AbVorfallDetailState extends State<_AbVorfallDetail> {
  bool _loaded = false;
  List<Map<String, dynamic>> _korr = [], _verlauf = [], _termine = [];

  /// Je Art höchstens eines — der Server erzwingt das über
  /// UNIQUE(vorfall_id, art), hier ist es nur die Abbildung davon.
  Map<String, Map<String, dynamic>> _dokumente = {};

  /// Welche Art gerade hochlädt (`null` = keine). Kein bloßes `bool`: sonst
  /// sperrte ein laufender Titel-Upload auch den Knopf des Zusatzblatts.
  String? _laedt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiService
          .getAuslaenderbehoerdeVorfallDetail(widget.userId, widget.vorfallId);
      if (res['success'] == true && mounted) {
        _korr = (res['korrespondenz'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _verlauf = (res['verlauf'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _termine = (res['termine'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // ⚠️ Beide Formen lesen. PHP kodiert eine LEERE Karte als `[]`, nicht
        // als `{}` — hier zwar mit `(object)` erzwungen, aber ein `as Map` auf
        // eine Liste wirft, statt `null` zu liefern, und das ergäbe in einem
        // Release-Bau eine graue Fläche ohne jede Meldung.
        final dk = res['dokumente'];
        _dokumente = {};
        if (dk is Map) {
          for (final e in dk.entries) {
            if (e.value is Map) {
              _dokumente[e.key.toString()] =
                  Map<String, dynamic>.from(e.value as Map);
            }
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vorfall;
    final status = v['status']?.toString() ?? 'offen';
    final sc = status == 'erledigt'
        ? Colors.green
        : status == 'in_bearbeitung'
            ? Colors.orange
            : Colors.blue;
    // Der Dokumentenreiter erscheint nur, wo es überhaupt ein Papier gibt —
    // zu einer Rückkehrberatung gehört keines.
    final arten = abDokArtenFuerTyp(v['typ']?.toString());
    return DefaultTabController(
        length: arten.isEmpty ? 4 : 5,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(children: [
                Icon(Icons.assignment, size: 18, color: F.h(Colors.indigo, 700)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        v['titel']?.toString().isNotEmpty == true
                            ? v['titel'].toString()
                            : (v['typ']?.toString() ?? ''),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: F.h(Colors.indigo, 800)),
                        overflow: TextOverflow.ellipsis)),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: F.h(sc, 100), borderRadius: BorderRadius.circular(6)),
                    child: Text(
                        status == 'erledigt'
                            ? 'Erledigt'
                            : status == 'in_bearbeitung'
                                ? 'In Bearbeitung'
                                : 'Offen',
                        style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.bold, color: F.h(sc, 800)))),
                const SizedBox(width: 4),
                IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Bearbeiten',
                    onPressed: widget.onBearbeiten),
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context)),
              ])),
          TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: F.h(Colors.indigo, 700),
              unselectedLabelColor: F.h(Colors.grey, 500),
              indicatorColor: Colors.indigo.shade700,
              tabs: [
                const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
                if (arten.isNotEmpty)
                  Tab(
                      icon: Icon(
                          _dokumente.length >= arten.length
                              ? Icons.task_alt
                              : Icons.upload_file,
                          size: 16),
                      text: 'Aufenthaltstitel (${_dokumente.length}/${arten.length})'),
                Tab(
                    icon: const Icon(Icons.email, size: 16),
                    text: 'Korrespondenz (${_korr.length})'),
                Tab(icon: const Icon(Icons.timeline, size: 16), text: 'Verlauf (${_verlauf.length})'),
                Tab(icon: const Icon(Icons.event, size: 16), text: 'Termine (${_termine.length})'),
              ]),
          Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(children: [
                      _buildDetails(v),
                      if (arten.isNotEmpty) _buildDokumente(v, arten),
                      _buildKorr(),
                      _buildVerlauf(),
                      _buildTermine(),
                    ])),
        ]));
  }

  Widget _buildDetails(Map<String, dynamic> v) {
    final typ = v['typ']?.toString() ?? '';
    final info = abTypFinden(typ);
    final hatStatus = ['aufenthaltsstatus', 'aufenthaltstitel', 'gueltig_bis']
        .any((k) => (v[k]?.toString() ?? '').isNotEmpty);
    final ablauf = abDatumLesen(v['gueltig_bis']?.toString());
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _infoRow(Icons.category, 'Anliegen', typ),
          if (info?.recht != null) _infoRow(Icons.gavel, 'Rechtsgrundlage', info!.recht),
          _infoRow(Icons.title, 'Titel', v['titel']),
          _infoRow(Icons.calendar_today, 'Datum', v['datum']),
          _infoRow(Icons.folder, 'Aktenzeichen', v['aktenzeichen']),
          _infoRow(Icons.support_agent, 'Sachbearbeiter/in', v['sachbearbeiter']),
          if (hatStatus) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.badge, size: 13, color: F.h(Colors.indigo, 600)),
              const SizedBox(width: 6),
              Text('Aufenthalt',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: F.h(Colors.indigo, 700))),
            ]),
            const SizedBox(height: 6),
            _infoRow(
                Icons.verified_user,
                'Aufenthaltsstatus',
                kAufenthaltsstatusLabel[v['aufenthaltsstatus']?.toString() ?? ''] ??
                    v['aufenthaltsstatus']),
            _infoRow(Icons.description, 'Aufenthaltstitel', v['aufenthaltstitel']),
            _infoRow(
                Icons.event_busy,
                abFortgeltung(typ) ? 'Datum auf der Karte' : 'Gültig bis',
                v['gueltig_bis']),
            if (abFortgeltung(typ))
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: F.h(Colors.green, 50),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: F.h(Colors.green, 200))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.verified, size: 14, color: F.h(Colors.green, 800)),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                'Gilt kraft Verordnung bis ${widget.uaBis} weiter — '
                                'ohne Antrag, ohne Termin, ohne neue Karte, auch wenn das '
                                'Datum oben abgelaufen ist. Voraussetzung: gültig am '
                                '${widget.uaStichtag}.',
                                style:
                                    TextStyle(fontSize: 10, color: F.h(Colors.green, 900)))),
                      ]))),
            if (ablauf != null && abLaeuftBaldAb(typ, ablauf))
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: F.h(Colors.orange, 50),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: F.h(Colors.orange, 200))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.warning_amber, size: 14, color: F.h(Colors.orange, 800)),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                'Läuft in Kürze ab. Die Verlängerung muss VOR Ablauf beantragt '
                                'sein — sonst wird eine Fiktionsbescheinigung nötig.',
                                style:
                                    TextStyle(fontSize: 10, color: F.h(Colors.orange, 900)))),
                      ]))),
          ],
          if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(8)),
                child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 12))),
          ],
        ]));
  }

  // ══ Dokumente: Aufenthaltstitel und Zusatzblatt ═══════════════════════
  Widget _buildDokumente(Map<String, dynamic> v, List<String> arten) {
    final typ = v['typ']?.toString() ?? '';
    final info = abTypFinden(typ);
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final art in arten) ...[
            _dokPlatz(art, info),
            const SizedBox(height: 16),
          ],
          Text('PDF, JPG, JPEG oder PNG · höchstens 20 MB · je Platz eine Datei',
              style: TextStyle(
                  fontSize: 10,
                  color: F.h(Colors.grey, 500),
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
          Text(
              'Ändern sich die Nebenbestimmungen, stellt die Behörde ein neues '
              'Zusatzblatt aus — ohne neue Karte. Dann bitte nur diesen Platz '
              'ersetzen.',
              style: TextStyle(
                  fontSize: 10,
                  color: F.h(Colors.grey, 500),
                  fontStyle: FontStyle.italic)),
        ]));
  }

  Widget _dokPlatz(String art, AbVorfallTyp? info) {
    final d = _dokumente[art];
    final titel = abDokTitelFuerArt(art, info?.frist?.dokument);
    final zweck = abDokZweckFuerArt(art);
    final optional = abDokOptional(art);
    final laeuft = _laedt == art;
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: F.h(Colors.grey, 50),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: F.h(Colors.grey, 300))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_dokIcon(art), size: 15, color: F.h(Colors.indigo, 600)),
            const SizedBox(width: 6),
            Expanded(
                child: Text(titel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: F.h(Colors.indigo, 700)))),
            if (optional)
              Text('optional',
                  style: TextStyle(fontSize: 9, color: F.h(Colors.grey, 500))),
          ]),
          const SizedBox(height: 4),
          Text(zweck, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
          const SizedBox(height: 10),
          if (d == null)
            Row(children: [
              Icon(Icons.upload_file, size: 20, color: F.h(Colors.grey, 400)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      optional
                          ? 'Nichts hinterlegt — gibt es nicht in jedem Fall'
                          : 'Noch nichts hinterlegt',
                      style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)))),
            ])
          else
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: F.h(Colors.indigo, 50),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: F.h(Colors.indigo, 200))),
                child: Row(children: [
                  Icon(
                      (d['mime']?.toString() ?? '').contains('pdf')
                          ? Icons.picture_as_pdf
                          : Icons.image,
                      size: 20,
                      color: F.h(Colors.indigo, 700)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(d['original_name']?.toString() ?? '',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                        Text(
                            [
                              _groesse((d['groesse'] as num?)?.toInt() ?? 0),
                              // ⚠️ Das Datum gehört dazu: ein neues Zusatzblatt
                              // wird auch OHNE neue Karte ausgestellt, sobald
                              // sich eine Nebenbestimmung ändert. Ohne Datum
                              // ließe sich nicht sagen, ob das hinterlegte
                              // Blatt noch den heutigen Stand zeigt.
                              _hochgeladenAm(d['created_at']?.toString()),
                            ].where((t) => t.isNotEmpty).join(' · '),
                            style: TextStyle(
                                fontSize: 10, color: F.h(Colors.grey, 600))),
                      ])),
                  IconButton(
                      icon: Icon(Icons.visibility,
                          size: 18, color: F.h(Colors.indigo, 700)),
                      tooltip: 'Ansehen',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _dokAnsehen(d)),
                  IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: Colors.red.shade400),
                      tooltip: 'Löschen',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _dokLoeschen(d, titel)),
                ])),
          const SizedBox(height: 10),
          Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                  icon: laeuft
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.attach_file, size: 16),
                  label: Text(d == null ? 'Hochladen' : 'Ersetzen',
                      style: const TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero),
                  // ⚠️ Nur der eigene Knopf sperrt. Sonst blockierte ein
                  // laufender Titel-Upload auch das Zusatzblatt.
                  onPressed: laeuft ? null : () => _dokHochladen(art, titel))),
        ]));
  }

  IconData _dokIcon(String art) => switch (art) {
        kAbDokRueckseite => Icons.flip_to_back,
        kAbDokZusatzblatt => Icons.article,
        kAbDokFortgeltung => Icons.verified,
        _ => Icons.badge,
      };

  /// „hochgeladen am 04.09.2026" aus dem Serverzeitstempel. Leer, wenn er
  /// fehlt oder unlesbar ist — lieber nichts als ein erfundenes Datum.
  String _hochgeladenAm(String? roh) {
    final t = (roh ?? '').trim();
    if (t.isEmpty) return '';
    final d = DateTime.tryParse(t);
    if (d == null) return '';
    return 'hochgeladen am ${_deFmt(d)}';
  }

  String _groesse(int b) => b >= 1024 * 1024
      ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(b / 1024).toStringAsFixed(0)} kB';

  void _sagen(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _dokHochladen(String art, String titel) async {
    final auswahl = await FilePickerHelper.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: kAbDokEndungen,
    );
    final datei = (auswahl?.files ?? []).firstOrNull;
    if (datei == null) return;
    final grund = abDokAblehnung(datei.name, datei.size);
    if (grund != null) {
      _sagen(grund, fehler: true);
      return;
    }
    if (datei.path == null) {
      _sagen('Diese Datei lässt sich hier nicht lesen.', fehler: true);
      return;
    }

    setState(() => _laedt = art);
    final r = await widget.apiService.uploadAuslaenderbehoerdeDokument(
        userId: widget.userId,
        vorfallId: widget.vorfallId,
        art: art,
        pfad: datei.path!,
        dateiname: datei.name);
    if (!mounted) return;
    setState(() => _laedt = null);
    if (r['success'] == true) {
      _sagen('$titel gespeichert');
      await _load();
      widget.onChanged();
    } else {
      // ⚠️ Den Grund des Servers zeigen. Ein stilles Zurücksetzen ist für den
      // Nutzer nicht von „ich habe danebengetippt" zu unterscheiden.
      _sagen('Nicht hochgeladen: ${r['message'] ?? 'unbekannter Fehler'}',
          fehler: true);
    }
  }

  /// Zeigt das Papier IM PROGRAMM, aus dem Arbeitsspeicher.
  ///
  /// ⚠️ Nicht auf die Platte und nicht an ein fremdes Programm: ein
  /// Aufenthaltstitel trägt Name, Geburtsdatum, Lichtbild und Aufenthaltsstatus
  /// eines Mitglieds. Auf dem Server liegt er mit einigem Aufwand
  /// verschlüsselt — ihn hier entschlüsselt abzulegen gäbe das wieder her, und
  /// ein fremder Betrachter behielte ihn ohnehin (eigener Verlauf, eigene
  /// Wolkensicherung).
  Future<void> _dokAnsehen(Map<String, dynamic> d) async {
    final id =
        d['id'] is int ? d['id'] as int : int.tryParse(d['id'].toString()) ?? 0;
    final r = await widget.apiService
        .downloadAuslaenderbehoerdeDokument(widget.userId, id);
    if (!mounted) return;
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
      _sagen('Nicht abrufbar (HTTP ${r.statusCode}).', fehler: true);
      return;
    }
    final name = d['original_name']?.toString() ?? 'dokument.pdf';
    final gezeigt =
        await FileViewerDialog.showFromBytes(context, r.bodyBytes, name);
    if (!gezeigt && mounted) {
      _sagen('Dieser Dateityp lässt sich hier nicht anzeigen: $name',
          fehler: true);
    }
  }

  Future<void> _dokLoeschen(Map<String, dynamic> d, String titel) async {
    final sicher = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('$titel löschen?', style: const TextStyle(fontSize: 15)),
              content: Text('„${d['original_name'] ?? ''}" wird endgültig entfernt.',
                  style: const TextStyle(fontSize: 13)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Abbrechen')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Löschen')),
              ],
            ));
    if (sicher != true) return;
    final id =
        d['id'] is int ? d['id'] as int : int.tryParse(d['id'].toString()) ?? 0;
    final r =
        await widget.apiService.deleteAuslaenderbehoerdeDokument(widget.userId, id);
    if (!mounted) return;
    if (r['success'] == true) {
      _sagen('$titel gelöscht');
      await _load();
      widget.onChanged();
    } else {
      _sagen('Nicht gelöscht: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  Widget _infoRow(IconData icon, String label, dynamic wert) {
    final t = wert?.toString() ?? '';
    if (t.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: F.h(Colors.grey, 600)),
          const SizedBox(width: 8),
          SizedBox(
              width: 140,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: F.h(Colors.grey, 700)))),
          // ⚠️ phoneAwareText statt Text: hinter „Sachbearbeiter/in" steht in
          // der Regel ein Name, manchmal aber eine Durchwahl. Der Helfer
          // entscheidet selbst und lässt Nicht-Nummern in Ruhe — eine
          // Ausnahme in rufnummern_waehlbar_test.dart wäre die schlechtere
          // Antwort, weil eine tote Nummer auf dem Schirm wie eine lebende
          // aussieht.
          Expanded(
              child: phoneAwareText(icon, t,
                  style: const TextStyle(fontSize: 12), label: label)),
        ]));
  }

  Widget _liste({
    required List<Map<String, dynamic>> eintraege,
    required IconData leerIcon,
    required String leerText,
    required String neuText,
    required VoidCallback onNeu,
    required Widget Function(Map<String, dynamic>) bauer,
  }) {
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                  icon: const Icon(Icons.add, size: 14),
                  label: Text(neuText, style: const TextStyle(fontSize: 11)),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero),
                  onPressed: onNeu))),
      Expanded(
          child: eintraege.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(leerIcon, size: 40, color: F.h(Colors.grey, 300)),
                  const SizedBox(height: 8),
                  Text(leerText,
                      style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500))),
                ]))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: eintraege.map(bauer).toList())),
    ]);
  }

  Widget _zeileKarte(
      {required IconData icon,
      required String titel,
      required String unter,
      required VoidCallback onLoeschen}) {
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: F.h(Colors.grey, 50),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: F.h(Colors.grey, 200))),
        child: Row(children: [
          Icon(icon, size: 16, color: F.h(Colors.indigo, 600)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titel,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            if (unter.isNotEmpty)
              Text(unter, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ])),
          IconButton(
              icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: onLoeschen),
        ]));
  }

  Widget _buildKorr() => _liste(
      eintraege: _korr,
      leerIcon: Icons.mail_outline,
      leerText: 'Keine Korrespondenz',
      neuText: 'Eintrag',
      onNeu: _korrDialog,
      bauer: (k) => _zeileKarte(
          icon: (k['richtung'] == 'ausgang') ? Icons.call_made : Icons.call_received,
          titel: k['betreff']?.toString() ?? '',
          unter: [
            k['datum']?.toString() ?? '',
            k['methode']?.toString() ?? '',
            (k['richtung'] == 'ausgang') ? 'Ausgang' : 'Eingang',
          ].where((s) => s.isNotEmpty).join(' · '),
          onLoeschen: () async {
            await widget.apiService
                .deleteAuslaenderbehoerdeKorr(widget.userId, (k['id'] as num).toInt());
            await _load();
            widget.onChanged();
          }));

  Widget _buildVerlauf() => _liste(
      eintraege: _verlauf,
      leerIcon: Icons.timeline,
      leerText: 'Kein Verlauf',
      neuText: 'Schritt',
      onNeu: _verlaufDialog,
      bauer: (e) => _zeileKarte(
          icon: Icons.check_circle_outline,
          titel: e['aktion']?.toString() ?? '',
          unter: [e['datum']?.toString() ?? '', e['notiz']?.toString() ?? '']
              .where((s) => s.isNotEmpty)
              .join(' · '),
          onLoeschen: () async {
            await widget.apiService
                .deleteAuslaenderbehoerdeVerlauf(widget.userId, (e['id'] as num).toInt());
            await _load();
            widget.onChanged();
          }));

  Widget _buildTermine() => _liste(
      eintraege: _termine,
      leerIcon: Icons.event_busy,
      leerText: 'Keine Termine',
      neuText: 'Termin',
      onNeu: _terminDialog,
      bauer: (t) => _zeileKarte(
          icon: Icons.event,
          titel: [t['datum']?.toString() ?? '', t['uhrzeit']?.toString() ?? '']
              .where((s) => s.isNotEmpty)
              .join(' um '),
          unter: [t['ort']?.toString() ?? '', t['notiz']?.toString() ?? '']
              .where((s) => s.isNotEmpty)
              .join(' · '),
          onLoeschen: () async {
            await widget.apiService
                .deleteAuslaenderbehoerdeTermin(widget.userId, (t['id'] as num).toInt());
            await _load();
            widget.onChanged();
          }));

  Widget _feld(TextEditingController c, String label, {int zeilen = 1}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
          controller: c,
          maxLines: zeilen,
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))));

  Widget _datumFeld(TextEditingController c, String label, BuildContext ctx, StateSetter s) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: c,
              readOnly: true,
              decoration: InputDecoration(
                  labelText: label,
                  hintText: 'TT.MM.JJJJ',
                  prefixIcon: const Icon(Icons.calendar_today, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final p = await showDatePicker(
                    context: ctx,
                    initialDate: abDatumLesen(c.text) ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2045),
                    locale: const Locale('de'));
                if (p != null) s(() => c.text = _deFmt(p));
              }));

  void _korrDialog() {
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final methodeC = TextEditingController();
    final notizC = TextEditingController();
    String richtung = 'eingang';
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
                  title: const Text('Korrespondenz', style: TextStyle(fontSize: 14)),
                  content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                        DropdownButtonFormField<String>(
                            initialValue: richtung,
                            decoration: InputDecoration(
                                labelText: 'Richtung',
                                isDense: true,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            items: const [
                              DropdownMenuItem(value: 'eingang', child: Text('Eingang', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'ausgang', child: Text('Ausgang', style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: (v) => setDlg(() => richtung = v ?? 'eingang')),
                        const SizedBox(height: 12),
                        _datumFeld(datumC, 'Datum', ctx, setDlg),
                        _feld(betreffC, 'Betreff'),
                        _feld(methodeC, 'Methode (Brief, E-Mail, persönlich …)'),
                        _feld(notizC, 'Notiz', zeilen: 2),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                    FilledButton(
                        onPressed: () async {
                          await widget.apiService.saveAuslaenderbehoerdeKorr(
                              widget.userId, widget.vorfallId, {
                            'richtung': richtung,
                            'methode': methodeC.text.trim(),
                            'datum': datumC.text.trim(),
                            'betreff': betreffC.text.trim(),
                            'notiz': notizC.text.trim(),
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _load();
                          widget.onChanged();
                        },
                        child: const Text('Speichern')),
                  ],
                )));
  }

  void _verlaufDialog() {
    final datumC = TextEditingController();
    final aktionC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
                  title: const Text('Verlaufsschritt', style: TextStyle(fontSize: 14)),
                  content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                        _datumFeld(datumC, 'Datum', ctx, setDlg),
                        _feld(aktionC, 'Aktion'),
                        _feld(notizC, 'Notiz', zeilen: 2),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                    FilledButton(
                        onPressed: () async {
                          await widget.apiService.saveAuslaenderbehoerdeVerlauf(
                              widget.userId, widget.vorfallId, {
                            'datum': datumC.text.trim(),
                            'aktion': aktionC.text.trim(),
                            'notiz': notizC.text.trim(),
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _load();
                          widget.onChanged();
                        },
                        child: const Text('Speichern')),
                  ],
                )));
  }

  void _terminDialog() {
    final datumC = TextEditingController();
    final uhrzeitC = TextEditingController();
    final ortC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
                  title: const Text('Termin', style: TextStyle(fontSize: 14)),
                  content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                        _datumFeld(datumC, 'Datum', ctx, setDlg),
                        _feld(uhrzeitC, 'Uhrzeit'),
                        _feld(ortC, 'Ort'),
                        _feld(notizC, 'Notiz', zeilen: 2),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                    FilledButton(
                        onPressed: () async {
                          await widget.apiService.saveAuslaenderbehoerdeTermin(
                              widget.userId, widget.vorfallId, {
                            'datum': datumC.text.trim(),
                            'uhrzeit': uhrzeitC.text.trim(),
                            'ort': ortC.text.trim(),
                            'notiz': notizC.text.trim(),
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _load();
                          widget.onChanged();
                        },
                        child: const Text('Speichern')),
                  ],
                )));
  }
}
