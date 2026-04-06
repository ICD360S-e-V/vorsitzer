import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/clipboard_helper.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../screens/webview_screen.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';

class FinanzenKreditWidget extends StatefulWidget {
  final Map<String, dynamic> Function(String) getData;
  final Future<void> Function(String, Map<String, dynamic>) saveData;
  final Future<void> Function(String) loadData;
  final bool Function(String) isLoading;
  final bool Function(String) isSaving;
  final Future<void> Function(String, String, dynamic) autoSaveField;
  final ApiService apiService;
  final int userId;

  const FinanzenKreditWidget({
    super.key,
    required this.getData,
    required this.saveData,
    required this.loadData,
    required this.isLoading,
    required this.isSaving,
    required this.autoSaveField,
    required this.apiService,
    required this.userId,
  });

  @override
  State<FinanzenKreditWidget> createState() => _FinanzenKreditWidgetState();
}

class _FinanzenKreditWidgetState extends State<FinanzenKreditWidget> {
  static const String _type = 'finanzen_kredit';

  // ── Kreditversicherung Datenbank ──
  static const List<Map<String, String>> _versicherungDB = [
    {
      'anbieter': 'CNP Santander Insurance Europe DAC',
      'art': 'Restschuldversicherung',
      'adresse': 'Postfach 32 10 80, 40425 Düsseldorf',
      'telefon': '0800-5888 544',
      'email': 'Service@ger.cnpsantander.com',
      'website': 'www.cnpsantander.de',
      'leistungen': 'Kreditabsicherung bei Tod, Arbeitsunfähigkeit',
    },
    {
      'anbieter': 'CNP Santander Insurance Life DAC',
      'art': 'Kreditlebensversicherung',
      'adresse': 'Postfach 32 10 80, 40425 Düsseldorf',
      'telefon': '0800-5888 544',
      'email': 'Service@ger.cnpsantander.com',
      'website': 'www.cnpsantander.de',
      'leistungen': 'Lebensversicherung zur Kreditabsicherung bei Tod',
    },
    {
      'anbieter': 'Allianz Lebensversicherungs-AG',
      'art': 'Restschuldversicherung',
      'adresse': 'Reinsburgstraße 19, 70178 Stuttgart',
      'telefon': '0800-4 100 104',
      'email': 'service@allianz.de',
      'website': 'www.allianz.de',
      'leistungen': 'Tod, Arbeitsunfähigkeit, Arbeitslosigkeit',
    },
    {
      'anbieter': 'CreditLife AG (Rheinland Versicherungsgruppe)',
      'art': 'Restschuldversicherung',
      'adresse': 'RheinLandplatz, 41460 Neuss',
      'telefon': '02131 290-0',
      'email': 'info@creditlife.net',
      'website': 'www.creditlife.net',
      'leistungen': 'Tod, Arbeitsunfähigkeit, Arbeitslosigkeit, schwere Krankheit',
    },
    {
      'anbieter': 'Cardif Allgemeine Versicherung (BNP Paribas)',
      'art': 'Restschuldversicherung',
      'adresse': 'Friolzheimer Straße 28, 70499 Stuttgart',
      'telefon': '0711 82055-200',
      'email': 'service.de@cardif.com',
      'website': 'www.cardif.de',
      'leistungen': 'Tod, Arbeitsunfähigkeit, Arbeitslosigkeit',
    },
    {
      'anbieter': 'R+V Versicherung AG',
      'art': 'Restschuldversicherung',
      'adresse': 'Raiffeisenplatz 1, 65189 Wiesbaden',
      'telefon': '0611 533-0',
      'email': 'info@ruv.de',
      'website': 'www.ruv.de',
      'leistungen': 'Tod, Arbeitsunfähigkeit',
    },
    {
      'anbieter': 'ERGO Vorsorge Lebensversicherung AG',
      'art': 'Kreditlebensversicherung',
      'adresse': 'ERGO-Platz 1, 40198 Düsseldorf',
      'telefon': '0800 3746 000',
      'email': 'service@ergo.de',
      'website': 'www.ergo.de',
      'leistungen': 'Tod, Arbeitsunfähigkeit, Arbeitslosigkeit',
    },
    {
      'anbieter': 'AXA Versicherung AG',
      'art': 'Restschuldversicherung',
      'adresse': 'Colonia-Allee 10-20, 51067 Köln',
      'telefon': '0221 148-0',
      'email': 'info@axa.de',
      'website': 'www.axa.de',
      'leistungen': 'Tod, Arbeitsunfähigkeit',
    },
  ];

  List<Map<String, dynamic>> _kredite = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  void _initFromData(Map<String, dynamic> data) {
    if (_initialized && data.isNotEmpty) return;
    if (data.isEmpty) return;
    _initialized = true;
    final raw = data['kredite'];
    if (raw is List) {
      _kredite = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  }

  void _saveKredite() {
    widget.autoSaveField(_type, 'kredite', _kredite);
  }

  void _addKredit() {
    _showKreditDialog(null, null);
  }

  void _editKredit(int index) {
    _showKreditDialog(_kredite[index], index);
  }

  void _showKreditDetailDialog(int index) {
    final k = _kredite[index];
    final verlauf = k['verlauf'] is List
        ? List<Map<String, dynamic>>.from((k['verlauf'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
        : <Map<String, dynamic>>[];

    showDialog(
      context: context,
      builder: (dlgCtx) => DefaultTabController(
        length: 4,
        child: StatefulBuilder(
          builder: (dlgCtx, setDlg) {
            final isLaufend = k['status']?.toString() == 'laufend';
            final isAbbezahlt = k['status']?.toString() == 'abbezahlt';
            final statusColor = isLaufend ? Colors.green : (isAbbezahlt ? Colors.blue : Colors.red);
            final statusLabel = isLaufend ? 'Laufend' : (isAbbezahlt ? 'Abbezahlt' : 'Gekündigt');

            return AlertDialog(
              contentPadding: EdgeInsets.zero,
              titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.account_balance, size: 18, color: statusColor.shade700),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k['bank_name']?.toString() ?? 'Kredit', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      if ((k['kreditart']?.toString() ?? '').isNotEmpty)
                        Text(k['kreditart'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: statusColor.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor.shade300)),
                      child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.shade800)),
                    ),
                    const SizedBox(width: 4),
                    IconButton(icon: Icon(Icons.edit, size: 16, color: Colors.blue.shade600), tooltip: 'Bearbeiten',
                      onPressed: () { Navigator.pop(dlgCtx); _editKredit(index); },
                      padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx),
                      padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                  ]),
                  const SizedBox(height: 4),
                  TabBar(
                    labelColor: Colors.orange.shade700,
                    unselectedLabelColor: Colors.grey.shade500,
                    indicatorColor: Colors.orange.shade700,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: const [
                      Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
                      Tab(icon: Icon(Icons.track_changes, size: 16), text: 'Verlauf'),
                      Tab(icon: Icon(Icons.shield, size: 16), text: 'Versicherung'),
                      Tab(icon: Icon(Icons.email, size: 16), text: 'Korrespondenz'),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 550, height: 500,
                child: TabBarView(children: [
                  // ── Tab 1: Details (read-only) ──
                  SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if ((k['vertragsnummer']?.toString() ?? '').isNotEmpty)
                      _detailCard(Icons.tag, 'Vertragsnummer', k['vertragsnummer'].toString()),
                    if ((k['betrag']?.toString() ?? '').isNotEmpty)
                      _detailCard(Icons.euro, 'Kreditbetrag', '${k['betrag']} €'),
                    if ((k['monatliche_rate']?.toString() ?? '').isNotEmpty)
                      _detailCard(Icons.calendar_today, 'Monatliche Rate', '${k['monatliche_rate']} €'),
                    if ((k['zinssatz']?.toString() ?? '').isNotEmpty)
                      _detailCard(Icons.percent, 'Zinssatz', '${k['zinssatz']} %'),
                    if ((k['restschuld']?.toString() ?? '').isNotEmpty)
                      _detailCard(Icons.money_off, 'Restschuld', '${k['restschuld']} €'),
                    if ((k['laufzeit_bis']?.toString() ?? '').isNotEmpty)
                      _detailCard(Icons.event, 'Laufzeit bis', _formatDate(k['laufzeit_bis'].toString())),
                    if ((k['ansprechpartner']?.toString() ?? '').isNotEmpty)
                      _detailCard(Icons.person_outline, 'Ansprechpartner', k['ansprechpartner'].toString()),
                    if ((k['telefon']?.toString() ?? '').isNotEmpty)
                      _detailCard(Icons.phone, 'Telefon', k['telefon'].toString()),
                    if ((k['notizen']?.toString() ?? '').isNotEmpty)
                      _detailCard(Icons.note, 'Notizen', k['notizen'].toString()),
                  ])),

                  // ── Tab 2: Verlauf ──
                  StatefulBuilder(builder: (vCtx, setVerlauf) {
                    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.timeline, size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Text('Kredit-Verlauf', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                        const Spacer(),
                        FilledButton.icon(
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Eintrag', style: TextStyle(fontSize: 11)),
                          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
                          onPressed: () {
                            final vDatumC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
                            final vBetragC = TextEditingController();
                            final vNotizenC = TextEditingController();
                            String vTyp = 'zahlung';
                            showDialog(context: vCtx, builder: (addCtx) => StatefulBuilder(
                              builder: (addCtx, setAdd) => AlertDialog(
                                title: Row(children: [
                                  Icon(Icons.add_circle, size: 18, color: Colors.orange.shade600),
                                  const SizedBox(width: 8),
                                  const Text('Neuer Verlaufseintrag', style: TextStyle(fontSize: 14)),
                                ]),
                                content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Wrap(spacing: 6, runSpacing: 4, children: [
                                    for (final t in [('zahlung', 'Zahlung', Icons.payment, Colors.green), ('sondertilgung', 'Sondertilgung', Icons.bolt, Colors.blue), ('zinsaenderung', 'Zinsänderung', Icons.trending_up, Colors.purple), ('mahnung', 'Mahnung', Icons.warning, Colors.red), ('kontakt', 'Kontakt Bank', Icons.phone, Colors.amber), ('sonstiges', 'Sonstiges', Icons.note, Colors.grey)])
                                      ChoiceChip(
                                        label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(t.$3, size: 13, color: vTyp == t.$1 ? Colors.white : t.$4.shade700), const SizedBox(width: 4), Text(t.$2, style: TextStyle(fontSize: 10, color: vTyp == t.$1 ? Colors.white : t.$4.shade700))]),
                                        selected: vTyp == t.$1, selectedColor: t.$4.shade600,
                                        onSelected: (_) => setAdd(() => vTyp = t.$1),
                                      ),
                                  ]),
                                  const SizedBox(height: 12),
                                  TextFormField(controller: vDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                                      final p = await showDatePicker(context: addCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
                                      if (p != null) vDatumC.text = DateFormat('dd.MM.yyyy').format(p);
                                    }))),
                                  const SizedBox(height: 10),
                                  TextFormField(controller: vBetragC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Betrag (€)', prefixIcon: Icon(Icons.euro, size: 16, color: Colors.green.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                  const SizedBox(height: 10),
                                  TextFormField(controller: vNotizenC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                ])),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(addCtx), child: const Text('Abbrechen')),
                                  FilledButton(onPressed: () {
                                    Navigator.pop(addCtx);
                                    verlauf.insert(0, {
                                      'typ': vTyp,
                                      'datum': vDatumC.text,
                                      'betrag': vBetragC.text.trim(),
                                      'notiz': vNotizenC.text.trim(),
                                    });
                                    k['verlauf'] = verlauf;
                                    _kredite[index] = k;
                                    _saveKredite();
                                    setVerlauf(() {});
                                  }, child: const Text('Hinzufügen')),
                                ],
                              ),
                            ));
                          },
                        ),
                      ]),
                      const SizedBox(height: 12),

                      if (verlauf.isEmpty)
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                          child: Column(children: [
                            Icon(Icons.timeline, size: 36, color: Colors.grey.shade300),
                            const SizedBox(height: 6),
                            Text('Noch keine Verlaufseinträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                          ]),
                        )
                      else
                        ...verlauf.asMap().entries.map((entry) {
                          final vi = entry.key;
                          final v = entry.value;
                          final vTyp = v['typ']?.toString() ?? 'sonstiges';
                          final vTypColors = {'zahlung': Colors.green, 'sondertilgung': Colors.blue, 'zinsaenderung': Colors.purple, 'mahnung': Colors.red, 'kontakt': Colors.amber, 'sonstiges': Colors.grey};
                          final vTypIcons = {'zahlung': Icons.payment, 'sondertilgung': Icons.bolt, 'zinsaenderung': Icons.trending_up, 'mahnung': Icons.warning, 'kontakt': Icons.phone, 'sonstiges': Icons.note};
                          final vTypLabels = {'zahlung': 'Zahlung', 'sondertilgung': 'Sondertilgung', 'zinsaenderung': 'Zinsänderung', 'mahnung': 'Mahnung', 'kontakt': 'Kontakt Bank', 'sonstiges': 'Sonstiges'};
                          final vc = vTypColors[vTyp] ?? Colors.grey;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(color: vc.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: vc.shade200)),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: vc.shade100, borderRadius: BorderRadius.circular(8)),
                                child: Icon(vTypIcons[vTyp] ?? Icons.note, size: 18, color: vc.shade700),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text(vTypLabels[vTyp] ?? vTyp, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: vc.shade800)),
                                  const SizedBox(width: 8),
                                  Text(v['datum']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                ]),
                                if ((v['betrag']?.toString() ?? '').isNotEmpty)
                                  Text('${v['betrag']} €', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                                if ((v['notiz']?.toString() ?? '').isNotEmpty)
                                  Text(v['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
                              ])),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300),
                                tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: () {
                                  verlauf.removeAt(vi);
                                  k['verlauf'] = verlauf;
                                  _kredite[index] = k;
                                  _saveKredite();
                                  setVerlauf(() {});
                                },
                              ),
                            ]),
                          );
                        }),
                    ]));
                  }),

                  // ── Tab 3: Versicherung ──
                  StatefulBuilder(builder: (vsCtx, setVers) {
                    final versicherung = k['versicherung'] is Map
                        ? Map<String, dynamic>.from(k['versicherung'] as Map)
                        : <String, dynamic>{};
                    final hasVers = (versicherung['versicherungsart']?.toString() ?? '').isNotEmpty ||
                        (versicherung['anbieter']?.toString() ?? '').isNotEmpty;

                    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.shield, size: 16, color: Colors.indigo.shade700),
                        const SizedBox(width: 6),
                        Text('Kreditversicherung / Restschuldversicherung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                      ]),
                      const SizedBox(height: 4),
                      Text('Absicherung bei Arbeitsunfähigkeit, Arbeitslosigkeit oder Tod', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      const SizedBox(height: 16),

                      if (!hasVers) ...[
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                          child: Column(children: [
                            Icon(Icons.shield_outlined, size: 36, color: Colors.grey.shade300),
                            const SizedBox(height: 6),
                            Text('Keine Versicherung hinterlegt', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                          ]),
                        ),
                        const SizedBox(height: 12),
                      ] else ...[
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if ((versicherung['anbieter']?.toString() ?? '').isNotEmpty)
                              _detailCard(Icons.business, 'Anbieter', versicherung['anbieter'].toString()),
                            if ((versicherung['versicherungsart']?.toString() ?? '').isNotEmpty)
                              _detailCard(Icons.category, 'Art', versicherung['versicherungsart'].toString()),
                            if ((versicherung['versicherungsnummer']?.toString() ?? '').isNotEmpty)
                              _detailCard(Icons.tag, 'Versicherungs-Nr.', versicherung['versicherungsnummer'].toString()),
                            if ((versicherung['leistungsnr_fall']?.toString() ?? '').isNotEmpty)
                              _detailCard(Icons.confirmation_number, 'Leistungs-Nr. / Fall', versicherung['leistungsnr_fall'].toString()),
                            if ((versicherung['monatliche_praemie']?.toString() ?? '').isNotEmpty)
                              _detailCard(Icons.euro, 'Monatl. Prämie', '${versicherung['monatliche_praemie']} €'),
                            if ((versicherung['deckungssumme']?.toString() ?? '').isNotEmpty)
                              _detailCard(Icons.security, 'Deckungssumme', '${versicherung['deckungssumme']} €'),
                            if ((versicherung['laufzeit_bis']?.toString() ?? '').isNotEmpty)
                              _detailCard(Icons.event, 'Laufzeit bis', versicherung['laufzeit_bis'].toString()),
                            if ((versicherung['leistungen']?.toString() ?? '').isNotEmpty)
                              _detailCard(Icons.checklist, 'Leistungen', versicherung['leistungen'].toString()),
                            if ((versicherung['portal_url']?.toString() ?? '').isNotEmpty ||
                                (versicherung['portal_user']?.toString() ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(Icons.language, size: 14, color: Colors.blue.shade700),
                                    const SizedBox(width: 6),
                                    Text('Online-Portal', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                                  ]),
                                  const SizedBox(height: 6),
                                  if ((versicherung['portal_url']?.toString() ?? '').isNotEmpty)
                                    InkWell(
                                      onTap: () {
                                        String url = versicherung['portal_url'].toString();
                                        if (!url.startsWith('http')) url = 'https://$url';
                                        Navigator.of(context).push(MaterialPageRoute(
                                          builder: (_) => WebViewScreen(
                                            url: url,
                                            title: versicherung['anbieter']?.toString() ?? 'Portal',
                                            autoFillUsername: versicherung['portal_user']?.toString(),
                                            autoFillPassword: versicherung['portal_passwort']?.toString(),
                                          ),
                                        ));
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(8)),
                                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Icon(Icons.link, size: 16, color: Colors.blue.shade700),
                                          const SizedBox(width: 10),
                                          SizedBox(width: 110, child: Text('Login-URL', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                                          Expanded(child: Text(versicherung['portal_url'].toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700, decoration: TextDecoration.underline))),
                                          const SizedBox(width: 6),
                                          Icon(Icons.open_in_new, size: 14, color: Colors.blue.shade600),
                                        ]),
                                      ),
                                    ),
                                  if ((versicherung['portal_user']?.toString() ?? '').isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                                      child: Row(children: [
                                        Icon(Icons.person, size: 16, color: Colors.orange.shade600),
                                        const SizedBox(width: 10),
                                        SizedBox(width: 110, child: Text('Benutzer', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                                        Expanded(child: Text(versicherung['portal_user'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                        IconButton(
                                          icon: Icon(Icons.copy, size: 16, color: Colors.blue.shade400),
                                          tooltip: 'Benutzername kopieren',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          onPressed: () {
                                            ClipboardHelper.copy(context, versicherung['portal_user'].toString(), 'Benutzername');
                                          },
                                        ),
                                      ]),
                                    ),
                                  if ((versicherung['portal_passwort']?.toString() ?? '').isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                                      child: Row(children: [
                                        Icon(Icons.lock, size: 16, color: Colors.orange.shade600),
                                        const SizedBox(width: 10),
                                        SizedBox(width: 110, child: Text('Passwort', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                                        const Expanded(child: Text('••••••••', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                        IconButton(
                                          icon: Icon(Icons.copy, size: 16, color: Colors.blue.shade400),
                                          tooltip: 'Passwort kopieren',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          onPressed: () {
                                            ClipboardHelper.copy(context, versicherung['portal_passwort'].toString(), 'Passwort');
                                          },
                                        ),
                                      ]),
                                    ),
                                ]),
                              ),
                            ],
                            if ((versicherung['notizen']?.toString() ?? '').isNotEmpty)
                              _detailCard(Icons.note, 'Notizen', versicherung['notizen'].toString()),
                          ]),
                        ),
                        const SizedBox(height: 12),
                      ],

                      FilledButton.icon(
                        icon: Icon(hasVers ? Icons.edit : Icons.add, size: 14),
                        label: Text(hasVers ? 'Versicherung bearbeiten' : 'Versicherung hinzufügen', style: const TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600),
                        onPressed: () {
                          final anbieterC = TextEditingController(text: versicherung['anbieter']?.toString() ?? '');
                          final artC = TextEditingController(text: versicherung['versicherungsart']?.toString() ?? '');
                          final nummerC = TextEditingController(text: versicherung['versicherungsnummer']?.toString() ?? '');
                          final leistungsnrC = TextEditingController(text: versicherung['leistungsnr_fall']?.toString() ?? '');
                          final praemieC = TextEditingController(text: versicherung['monatliche_praemie']?.toString() ?? '');
                          final deckungC = TextEditingController(text: versicherung['deckungssumme']?.toString() ?? '');
                          final laufzeitC = TextEditingController(text: versicherung['laufzeit_bis']?.toString() ?? '');
                          final leistungenC = TextEditingController(text: versicherung['leistungen']?.toString() ?? '');
                          final portalUrlC = TextEditingController(text: versicherung['portal_url']?.toString() ?? '');
                          final portalUserC = TextEditingController(text: versicherung['portal_user']?.toString() ?? '');
                          final portalPassC = TextEditingController(text: versicherung['portal_passwort']?.toString() ?? '');
                          final vNotizenC = TextEditingController(text: versicherung['notizen']?.toString() ?? '');

                          showDialog(context: vsCtx, builder: (vsDlg) => AlertDialog(
                            title: Row(children: [
                              Icon(Icons.shield, size: 18, color: Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              const Text('Kreditversicherung', style: TextStyle(fontSize: 14)),
                            ]),
                            content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Row(children: [
                                Expanded(child: TextFormField(controller: anbieterC, decoration: InputDecoration(labelText: 'Versicherungsanbieter *', prefixIcon: Icon(Icons.business, size: 16, color: Colors.indigo.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), hintText: 'z.B. Allianz, CosmosDirekt...', hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400)))),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  icon: Icon(Icons.list_alt, size: 14, color: Colors.indigo.shade600),
                                  label: Text('Datenbank', style: TextStyle(fontSize: 10, color: Colors.indigo.shade600)),
                                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), side: BorderSide(color: Colors.indigo.shade300)),
                                  onPressed: () {
                                    showDialog(context: vsDlg, builder: (dbCtx) => SimpleDialog(
                                      title: Row(children: [
                                        Icon(Icons.shield, size: 18, color: Colors.indigo.shade700),
                                        const SizedBox(width: 8),
                                        const Text('Kreditversicherung auswählen', style: TextStyle(fontSize: 14)),
                                      ]),
                                      children: _versicherungDB.map((v) => SimpleDialogOption(
                                        onPressed: () {
                                          Navigator.pop(dbCtx);
                                          anbieterC.text = v['anbieter'] ?? '';
                                          artC.text = v['art'] ?? '';
                                          leistungenC.text = v['leistungen'] ?? '';
                                          vNotizenC.text = [
                                            if ((v['adresse'] ?? '').isNotEmpty) 'Adresse: ${v['adresse']}',
                                            if ((v['telefon'] ?? '').isNotEmpty) 'Tel: ${v['telefon']}',
                                            if ((v['email'] ?? '').isNotEmpty) 'E-Mail: ${v['email']}',
                                            if ((v['website'] ?? '').isNotEmpty) 'Web: ${v['website']}',
                                          ].join('\n');
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(v['anbieter'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                                            Text(v['art'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                            if ((v['telefon'] ?? '').isNotEmpty || (v['email'] ?? '').isNotEmpty)
                                              Text('${v['telefon'] ?? ''}  ·  ${v['email'] ?? ''}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                          ]),
                                        ),
                                      )).toList(),
                                    ));
                                  },
                                ),
                              ]),
                              const SizedBox(height: 10),
                              TextFormField(controller: artC, decoration: InputDecoration(labelText: 'Versicherungsart', prefixIcon: Icon(Icons.category, size: 16, color: Colors.blue.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), hintText: 'z.B. Restschuldversicherung, Kreditlebensversicherung', hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400))),
                              const SizedBox(height: 10),
                              TextFormField(controller: nummerC, decoration: InputDecoration(labelText: 'Versicherungsnummer', prefixIcon: Icon(Icons.tag, size: 16, color: Colors.grey.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                              const SizedBox(height: 10),
                              TextFormField(controller: leistungsnrC, decoration: InputDecoration(labelText: 'Leistungs-Nr. / Fall', prefixIcon: Icon(Icons.confirmation_number, size: 16, color: Colors.grey.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(child: TextFormField(controller: praemieC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Monatl. Prämie (€)', prefixIcon: Icon(Icons.euro, size: 16, color: Colors.green.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                                const SizedBox(width: 10),
                                Expanded(child: TextFormField(controller: deckungC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Deckungssumme (€)', prefixIcon: Icon(Icons.security, size: 16, color: Colors.orange.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                              ]),
                              const SizedBox(height: 10),
                              TextFormField(controller: laufzeitC, readOnly: true, decoration: InputDecoration(labelText: 'Laufzeit bis', prefixIcon: Icon(Icons.event, size: 16, color: Colors.indigo.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                                  final p = await showDatePicker(context: vsDlg, initialDate: DateTime.tryParse(laufzeitC.text) ?? DateTime.now().add(const Duration(days: 365)), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
                                  if (p != null) laufzeitC.text = DateFormat('dd.MM.yyyy').format(p);
                                }))),
                              const SizedBox(height: 10),
                              TextFormField(controller: leistungenC, maxLines: 2, decoration: InputDecoration(labelText: 'Leistungen / Deckung', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), hintText: 'z.B. Tod, Arbeitsunfähigkeit, Arbeitslosigkeit', hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400))),
                              const SizedBox(height: 14),
                              // ── Online-Portal Zugangsdaten ──
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(Icons.language, size: 14, color: Colors.blue.shade700),
                                    const SizedBox(width: 6),
                                    Text('Online-Portal Zugangsdaten', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                                  ]),
                                  const SizedBox(height: 8),
                                  TextFormField(controller: portalUrlC, decoration: InputDecoration(labelText: 'Portal-Website (Login-URL)', prefixIcon: Icon(Icons.link, size: 16, color: Colors.blue.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), hintText: 'z.B. https://mein.cnpsantander.de', hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400))),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Expanded(child: TextFormField(controller: portalUserC, decoration: InputDecoration(labelText: 'Benutzername / E-Mail / Nr.', prefixIcon: Icon(Icons.person, size: 16, color: Colors.blue.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                                    const SizedBox(width: 8),
                                    Expanded(child: TextFormField(controller: portalPassC, obscureText: true, decoration: InputDecoration(labelText: 'Passwort', prefixIcon: Icon(Icons.lock, size: 16, color: Colors.blue.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                                  ]),
                                ]),
                              ),
                              const SizedBox(height: 10),
                              TextFormField(controller: vNotizenC, maxLines: 2, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                            ]))),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(vsDlg), child: const Text('Abbrechen')),
                              if (hasVers) TextButton(
                                onPressed: () {
                                  Navigator.pop(vsDlg);
                                  k['versicherung'] = null;
                                  _kredite[index] = k;
                                  _saveKredite();
                                  setVers(() {});
                                },
                                child: Text('Entfernen', style: TextStyle(color: Colors.red.shade600)),
                              ),
                              FilledButton(onPressed: () {
                                Navigator.pop(vsDlg);
                                k['versicherung'] = {
                                  'anbieter': anbieterC.text.trim(),
                                  'versicherungsart': artC.text.trim(),
                                  'versicherungsnummer': nummerC.text.trim(),
                                  'leistungsnr_fall': leistungsnrC.text.trim(),
                                  'monatliche_praemie': praemieC.text.trim(),
                                  'deckungssumme': deckungC.text.trim(),
                                  'laufzeit_bis': laufzeitC.text.trim(),
                                  'leistungen': leistungenC.text.trim(),
                                  'portal_url': portalUrlC.text.trim(),
                                  'portal_user': portalUserC.text.trim(),
                                  'portal_passwort': portalPassC.text.trim(),
                                  'notizen': vNotizenC.text.trim(),
                                };
                                _kredite[index] = k;
                                _saveKredite();
                                setVers(() {});
                              }, child: const Text('Speichern')),
                            ],
                          ));
                        },
                      ),
                    ]));
                  }),

                  // ── Tab 4: Korrespondenz ──
                  _KreditKorrespondenzTab(apiService: widget.apiService, userId: widget.userId, kreditIndex: index),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _detailCard(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Colors.orange.shade600),
        const SizedBox(width: 10),
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  void _deleteKredit(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kredit löschen?', style: TextStyle(fontSize: 15)),
        content: Text('${_kredite[index]['bank_name'] ?? 'Kredit'} wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _kredite.removeAt(index));
              _saveKredite();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showKreditDialog(Map<String, dynamic>? existing, int? editIndex) {
    final bankNameC = TextEditingController(text: existing?['bank_name']?.toString() ?? '');
    final kreditartC = TextEditingController(text: existing?['kreditart']?.toString() ?? '');
    final betragC = TextEditingController(text: existing?['betrag']?.toString() ?? '');
    final rateC = TextEditingController(text: existing?['monatliche_rate']?.toString() ?? '');
    final zinssatzC = TextEditingController(text: existing?['zinssatz']?.toString() ?? '');
    final laufzeitBisC = TextEditingController(text: existing?['laufzeit_bis']?.toString() ?? '');
    final vertragsnummerC = TextEditingController(text: existing?['vertragsnummer']?.toString() ?? '');
    final restschuldC = TextEditingController(text: existing?['restschuld']?.toString() ?? '');
    final ansprechpartnerC = TextEditingController(text: existing?['ansprechpartner']?.toString() ?? '');
    final telefonC = TextEditingController(text: existing?['telefon']?.toString() ?? '');
    final notizenC = TextEditingController(text: existing?['notizen']?.toString() ?? '');
    String status = existing?['status']?.toString() ?? 'laufend';

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.credit_card, size: 18, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text(editIndex != null ? 'Kredit bearbeiten' : 'Neuer Kredit', style: const TextStyle(fontSize: 15))),
          ]),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bank Name
                  TextFormField(
                    controller: bankNameC,
                    decoration: InputDecoration(
                      labelText: 'Bank / Kreditgeber *',
                      prefixIcon: Icon(Icons.account_balance, size: 18, color: Colors.teal.shade600),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      hintText: 'z.B. Sparkasse Ulm, Targobank...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Kreditart
                  TextFormField(
                    controller: kreditartC,
                    decoration: InputDecoration(
                      labelText: 'Kreditart',
                      prefixIcon: Icon(Icons.category, size: 18, color: Colors.blue.shade600),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      hintText: 'z.B. Ratenkredit, Autokredit, Baufinanzierung, Dispo...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Vertragsnummer
                  TextFormField(
                    controller: vertragsnummerC,
                    decoration: InputDecoration(
                      labelText: 'Vertragsnummer',
                      prefixIcon: Icon(Icons.tag, size: 18, color: Colors.grey.shade600),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Betrag + Rate
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: betragC,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Kreditbetrag (€)',
                            prefixIcon: Icon(Icons.euro, size: 18, color: Colors.green.shade600),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: rateC,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Monatl. Rate (€)',
                            prefixIcon: Icon(Icons.calendar_today, size: 18, color: Colors.orange.shade600),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Zinssatz + Restschuld
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: zinssatzC,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Zinssatz (%)',
                            prefixIcon: Icon(Icons.percent, size: 18, color: Colors.purple.shade600),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: restschuldC,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Restschuld (€)',
                            prefixIcon: Icon(Icons.money_off, size: 18, color: Colors.red.shade600),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Laufzeit bis
                  TextFormField(
                    controller: laufzeitBisC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Laufzeit bis',
                      prefixIcon: Icon(Icons.event, size: 18, color: Colors.indigo.shade600),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dlgCtx,
                            initialDate: DateTime.tryParse(laufzeitBisC.text) ?? DateTime.now().add(const Duration(days: 365)),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2060),
                            locale: const Locale('de'),
                          );
                          if (picked != null) {
                            setDlgState(() => laufzeitBisC.text = DateFormat('yyyy-MM-dd').format(picked));
                          }
                        },
                      ),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Status
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Text('Status:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('Laufend', style: TextStyle(fontSize: 11, color: status == 'laufend' ? Colors.white : Colors.green.shade700)),
                        selected: status == 'laufend',
                        selectedColor: Colors.green.shade600,
                        backgroundColor: Colors.green.shade50,
                        side: BorderSide(color: status == 'laufend' ? Colors.green.shade600 : Colors.green.shade200),
                        onSelected: (_) => setDlgState(() => status = 'laufend'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text('Abbezahlt', style: TextStyle(fontSize: 11, color: status == 'abbezahlt' ? Colors.white : Colors.blue.shade700)),
                        selected: status == 'abbezahlt',
                        selectedColor: Colors.blue.shade600,
                        backgroundColor: Colors.blue.shade50,
                        side: BorderSide(color: status == 'abbezahlt' ? Colors.blue.shade600 : Colors.blue.shade200),
                        onSelected: (_) => setDlgState(() => status = 'abbezahlt'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text('Gekündigt', style: TextStyle(fontSize: 11, color: status == 'gekuendigt' ? Colors.white : Colors.red.shade700)),
                        selected: status == 'gekuendigt',
                        selectedColor: Colors.red.shade600,
                        backgroundColor: Colors.red.shade50,
                        side: BorderSide(color: status == 'gekuendigt' ? Colors.red.shade600 : Colors.red.shade200),
                        onSelected: (_) => setDlgState(() => status = 'gekuendigt'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Ansprechpartner + Telefon
                  TextFormField(
                    controller: ansprechpartnerC,
                    decoration: InputDecoration(
                      labelText: 'Ansprechpartner',
                      prefixIcon: Icon(Icons.person_outline, size: 18, color: Colors.amber.shade700),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: telefonC,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Telefon',
                      prefixIcon: Icon(Icons.phone, size: 18, color: Colors.amber.shade700),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Notizen
                  TextFormField(
                    controller: notizenC,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Notizen',
                      prefixIcon: const Icon(Icons.note, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              onPressed: () {
                if (bankNameC.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bitte Bank / Kreditgeber angeben'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                final kredit = {
                  'bank_name': bankNameC.text.trim(),
                  'kreditart': kreditartC.text.trim(),
                  'vertragsnummer': vertragsnummerC.text.trim(),
                  'betrag': betragC.text.trim(),
                  'monatliche_rate': rateC.text.trim(),
                  'zinssatz': zinssatzC.text.trim(),
                  'restschuld': restschuldC.text.trim(),
                  'laufzeit_bis': laufzeitBisC.text.trim(),
                  'status': status,
                  'ansprechpartner': ansprechpartnerC.text.trim(),
                  'telefon': telefonC.text.trim(),
                  'notizen': notizenC.text.trim(),
                };
                Navigator.pop(dlgCtx);
                setState(() {
                  if (editIndex != null) {
                    _kredite[editIndex] = kredit;
                  } else {
                    _kredite.add(kredit);
                  }
                });
                _saveKredite();
              },
              icon: const Icon(Icons.save, size: 16),
              label: Text(editIndex != null ? 'Aktualisieren' : 'Hinzufügen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade600, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading(_type)) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = widget.getData(_type);
    _initFromData(data);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.orange.shade50, Colors.orange.shade100]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.credit_card, size: 28, color: Colors.orange.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kredite & Darlehen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                      Text('Laufende und abgeschlossene Kredite', style: TextStyle(fontSize: 11, color: Colors.orange.shade600)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _addKredit,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Neuer Kredit', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Kredite list
          if (_kredite.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.credit_card_off, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('Keine Kredite vorhanden', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  const SizedBox(height: 4),
                  Text('Klicken Sie auf "Neuer Kredit" um einen Kredit hinzuzufügen', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ],
              ),
            )
          else
            ..._kredite.asMap().entries.map((entry) {
              final i = entry.key;
              final k = entry.value;
              final isLaufend = k['status']?.toString() == 'laufend';
              final isAbbezahlt = k['status']?.toString() == 'abbezahlt';
              final statusColor = isLaufend ? Colors.green : (isAbbezahlt ? Colors.blue : Colors.red);
              final statusLabel = isLaufend ? 'Laufend' : (isAbbezahlt ? 'Abbezahlt' : 'Gekündigt');

              return InkWell(
                onTap: () => _showKreditDetailDialog(i),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.shade200),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: statusColor.shade50,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance, size: 18, color: statusColor.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              k['bank_name']?.toString() ?? 'Kredit',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: statusColor.shade800),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: statusColor.shade300),
                            ),
                            child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.shade800)),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.edit, size: 16, color: Colors.blue.shade600),
                            onPressed: () => _editKredit(i),
                            tooltip: 'Bearbeiten',
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            padding: EdgeInsets.zero,
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade600),
                            onPressed: () => _deleteKredit(i),
                            tooltip: 'Löschen',
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    // Details
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          if ((k['kreditart']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.category, 'Kreditart', k['kreditart'].toString()),
                          if ((k['vertragsnummer']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.tag, 'Vertragsnr.', k['vertragsnummer'].toString()),
                          if ((k['betrag']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.euro, 'Kreditbetrag', '${k['betrag']} €'),
                          if ((k['monatliche_rate']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.calendar_today, 'Monatl. Rate', '${k['monatliche_rate']} €'),
                          if ((k['zinssatz']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.percent, 'Zinssatz', '${k['zinssatz']} %'),
                          if ((k['restschuld']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.money_off, 'Restschuld', '${k['restschuld']} €'),
                          if ((k['laufzeit_bis']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.event, 'Laufzeit bis', _formatDate(k['laufzeit_bis'].toString())),
                          if ((k['ansprechpartner']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.person_outline, 'Ansprechpartner', k['ansprechpartner'].toString()),
                          if ((k['telefon']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.phone, 'Telefon', k['telefon'].toString()),
                          if ((k['notizen']?.toString() ?? '').isNotEmpty)
                            _infoRow(Icons.note, 'Notizen', k['notizen'].toString()),
                        ],
                      ),
                    ),
                  ],
                ),
              ));
            }),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return DateFormat('dd.MM.yyyy').format(d);
  }
}

// ═══════════════════════════════════════════════════════
// KREDIT KORRESPONDENZ TAB (Eingang / Ausgang)
// ═══════════════════════════════════════════════════════
class _KreditKorrespondenzTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int kreditIndex;

  const _KreditKorrespondenzTab({required this.apiService, required this.userId, required this.kreditIndex});

  @override
  State<_KreditKorrespondenzTab> createState() => _KreditKorrespondenzTabState();
}

class _KreditKorrespondenzTabState extends State<_KreditKorrespondenzTab> {
  List<Map<String, dynamic>> _docs = [];
  bool _isLoading = true;
  String _filter = 'alle'; // alle, eingang, ausgang

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getKreditKorrespondenz(widget.userId, kreditIndex: widget.kreditIndex);
      if (res['success'] == true && res['data'] is List) {
        _docs = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[KreditKorr] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _addKorrespondenz(String richtung) async {
    final datumC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    String methode = richtung == 'eingang' ? 'post' : 'email';
    List<PlatformFile> selectedFiles = [];

    final confirmed = await showDialog<bool>(context: context, builder: (dlgCtx) => StatefulBuilder(
      builder: (dlgCtx, setDlg) => AlertDialog(
        title: Row(children: [
          Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18, color: richtung == 'eingang' ? Colors.green.shade700 : Colors.blue.shade700),
          const SizedBox(width: 8),
          Text(richtung == 'eingang' ? 'Eingang hinzufügen' : 'Ausgang hinzufügen', style: const TextStyle(fontSize: 14)),
        ]),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Methode
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final m in [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('telefon', 'Telefon', Icons.phone), ('fax', 'Fax', Icons.fax), ('online', 'Online-Portal', Icons.language)])
              ChoiceChip(
                label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : Colors.grey.shade700))]),
                selected: methode == m.$1, selectedColor: Colors.indigo.shade600,
                onSelected: (_) => setDlg(() => methode = m.$1),
              ),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
              final p = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
              if (p != null) datumC.text = DateFormat('dd.MM.yyyy').format(p);
            }))),
          const SizedBox(height: 10),
          TextFormField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff / Titel *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextFormField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          // File picker (max 20)
          OutlinedButton.icon(
            icon: Icon(Icons.attach_file, size: 16, color: Colors.teal.shade600),
            label: Text(selectedFiles.isEmpty ? 'Dokumente anhängen (max. 20)' : '${selectedFiles.length} Datei${selectedFiles.length > 1 ? 'en' : ''} ausgewählt', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade300)),
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
              if (result != null) {
                setDlg(() {
                  selectedFiles.addAll(result.files);
                  if (selectedFiles.length > 20) selectedFiles = selectedFiles.sublist(0, 20);
                });
              }
            },
          ),
          if (selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...selectedFiles.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.description, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                Text('${((e.value.size) / 1024).toStringAsFixed(0)} KB', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => setDlg(() => selectedFiles.removeAt(e.key))),
              ]),
            )),
          ],
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () {
            if (betreffC.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff angeben'), backgroundColor: Colors.orange));
              return;
            }
            Navigator.pop(dlgCtx, true);
          }, child: const Text('Speichern')),
        ],
      ),
    ));

    if (confirmed != true) return;

    // Upload - if files, upload each with same metadata; if no files, upload once without file
    try {
      int successCount = 0;
      int failCount = 0;
      final gId = const Uuid().v4();
      if (selectedFiles.isEmpty) {
        final res = await widget.apiService.uploadKreditKorrespondenz(
          userId: widget.userId, kreditIndex: widget.kreditIndex,
          richtung: richtung, titel: betreffC.text.trim(), datum: datumC.text,
          betreff: betreffC.text.trim(), notiz: notizC.text.trim(), methode: methode, gruppeId: gId,
        );
        if (res['success'] == true) { successCount++; } else { failCount++; debugPrint('[KreditKorr] Upload error: ${res['message']}'); }
      } else {
        for (final f in selectedFiles) {
          if (f.path == null) continue;
          final res = await widget.apiService.uploadKreditKorrespondenz(
            userId: widget.userId, kreditIndex: widget.kreditIndex,
            richtung: richtung, titel: betreffC.text.trim(), datum: datumC.text,
            betreff: betreffC.text.trim(), notiz: notizC.text.trim(), methode: methode, gruppeId: gId,
            filePath: f.path!, fileName: f.name,
          );
          if (res['success'] == true) { successCount++; } else { failCount++; debugPrint('[KreditKorr] Upload error for ${f.name}: ${res['message']}'); }
        }
      }
      if (mounted) {
        if (failCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$successCount gespeichert, $failCount fehlgeschlagen'), backgroundColor: Colors.orange));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${successCount > 1 ? '$successCount Dokumente' : 'Korrespondenz'} gespeichert'), backgroundColor: Colors.green));
        }
      }
      _loadDocs();
    } catch (e) {
      debugPrint('[KreditKorr] Upload exception: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _viewDoc(int docId, String fileName) async {
    try {
      final response = await widget.apiService.downloadKreditKorrespondenzDoc(docId);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        if (mounted) {
          FileViewerDialog.showFromBytes(context, response.bodyBytes, fileName);
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler (${response.statusCode})'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _downloadDoc(int docId, String fileName) async {
    try {
      final response = await widget.apiService.downloadKreditKorrespondenzDoc(docId);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        // Save to Downloads folder
        final String downloadsPath;
        if (Platform.isMacOS) {
          downloadsPath = '${Platform.environment['HOME']}/Downloads';
        } else if (Platform.isWindows) {
          downloadsPath = '${Platform.environment['USERPROFILE']}\\Downloads';
        } else {
          downloadsPath = Directory.systemTemp.path;
        }

        var destFile = File('$downloadsPath${Platform.pathSeparator}$fileName');
        int counter = 1;
        while (destFile.existsSync()) {
          final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
          final base = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
          destFile = File('$downloadsPath${Platform.pathSeparator}${base}_($counter)$ext');
          counter++;
        }

        await destFile.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$fileName gespeichert in Downloads'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(label: 'Öffnen', textColor: Colors.white, onPressed: () {
              Process.run('open', [destFile.path]);
            }),
          ));
        }
        // Auto-open the file
        Process.run('open', [destFile.path]);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download fehlgeschlagen (${response.statusCode})'), backgroundColor: Colors.red));
      }
    } catch (e) {
      debugPrint('[KreditKorr] Download error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download-Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final filteredRaw = _filter == 'alle' ? _docs : _docs.where((d) => d['richtung'] == _filter).toList();
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final doc in filteredRaw) {
      final gId = doc['gruppe_id']?.toString() ?? 'single_${doc['id']}';
      grouped.putIfAbsent(gId, () => []).add(doc);
    }
    final groups = grouped.values.toList();
    final eingangCount = grouped.values.where((g) => g.first['richtung'] == 'eingang').length;
    final ausgangCount = grouped.values.where((g) => g.first['richtung'] == 'ausgang').length;

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header with add buttons
      Row(children: [
        Icon(Icons.email, size: 16, color: Colors.teal.shade700),
        const SizedBox(width: 6),
        Text('Korrespondenz', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
        const Spacer(),
        FilledButton.icon(
          icon: const Icon(Icons.call_received, size: 14),
          label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorrespondenz('eingang'),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          icon: const Icon(Icons.call_made, size: 14),
          label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorrespondenz('ausgang'),
        ),
      ]),
      const SizedBox(height: 10),

      // Filter chips
      Row(children: [
        ChoiceChip(label: Text('Alle (${_docs.length})', style: TextStyle(fontSize: 10, color: _filter == 'alle' ? Colors.white : Colors.grey.shade700)), selected: _filter == 'alle', selectedColor: Colors.teal.shade600, onSelected: (_) => setState(() => _filter = 'alle')),
        const SizedBox(width: 6),
        ChoiceChip(label: Text('Eingang ($eingangCount)', style: TextStyle(fontSize: 10, color: _filter == 'eingang' ? Colors.white : Colors.green.shade700)), selected: _filter == 'eingang', selectedColor: Colors.green.shade600, onSelected: (_) => setState(() => _filter = 'eingang')),
        const SizedBox(width: 6),
        ChoiceChip(label: Text('Ausgang ($ausgangCount)', style: TextStyle(fontSize: 10, color: _filter == 'ausgang' ? Colors.white : Colors.blue.shade700)), selected: _filter == 'ausgang', selectedColor: Colors.blue.shade600, onSelected: (_) => setState(() => _filter = 'ausgang')),
      ]),
      const SizedBox(height: 12),

      if (groups.isEmpty)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Column(children: [
            Icon(Icons.email_outlined, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 6),
            Text('Keine Korrespondenz vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ]),
        )
      else
        ...groups.map((docGroup) {
          final first = docGroup.first;
          final isEingang = first['richtung'] == 'eingang';
          final color = isEingang ? Colors.green : Colors.blue;
          const methodeIcons = {'email': Icons.email, 'post': Icons.mail, 'telefon': Icons.phone, 'fax': Icons.fax, 'online': Icons.language};
          const methodeLabels = {'email': 'E-Mail', 'post': 'Post', 'telefon': 'Telefon', 'fax': 'Fax', 'online': 'Portal'};
          final m = first['methode']?.toString() ?? 'post';
          final datumStr = first['datum']?.toString() ?? '';
          final datumFmt = datumStr.isNotEmpty ? (() { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(datumStr)); } catch (_) { return datumStr; } })() : '';
          final files = docGroup.where((d) => (d['file_name']?.toString() ?? '').isNotEmpty).toList();

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Icon(isEingang ? Icons.call_received : Icons.call_made, size: 18, color: color.shade700),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(first['betreff']?.toString() ?? first['titel']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade800), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(methodeIcons[m] ?? Icons.mail, size: 10, color: color.shade700),
                        const SizedBox(width: 3),
                        Text(methodeLabels[m] ?? m, style: TextStyle(fontSize: 9, color: color.shade700)),
                      ]),
                    ),
                    if (files.length > 1) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                        child: Text('${files.length} Dateien', style: TextStyle(fontSize: 9, color: Colors.grey.shade700)),
                      ),
                    ],
                  ]),
                  Row(children: [
                    Text(datumFmt, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ]),
                  if ((first['notiz']?.toString() ?? '').isNotEmpty)
                    Text(first['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300),
                  tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () async {
                    for (final d in docGroup) {
                      await widget.apiService.deleteKreditKorrespondenz(d['id'] is int ? d['id'] : int.parse(d['id'].toString()));
                    }
                    _loadDocs();
                  },
                ),
              ]),
              if (files.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...files.map((f) => Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: 4),
                  child: Row(children: [
                    Icon(Icons.attach_file, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Expanded(child: Text(f['file_name'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)),
                    IconButton(
                      icon: Icon(Icons.visibility, size: 14, color: Colors.indigo.shade500),
                      tooltip: 'Ansehen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () => _viewDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString()),
                    ),
                    IconButton(
                      icon: Icon(Icons.download, size: 14, color: Colors.teal.shade600),
                      tooltip: 'Herunterladen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () => _downloadDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString()),
                    ),
                  ]),
                )),
              ],
            ]),
          );
        }),
    ]));
  }
}
