import 'package:flutter/material.dart';
import 'phone_link.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import '../utils/cloud_picker_helper.dart';
import 'file_viewer_dialog.dart';
import 'korrespondenz_attachments_widget.dart';
import 'feld_reihe.dart';
import 'vermieter_dokumente.dart';
import 'vermieter_inkasso.dart';
import 'vermieter_korrespondenz.dart';
import '../utils/app_farben.dart';

/// Behörde ▸ Vermieter.
///
/// Seit 2026-08-19 hat ein Mitglied MEHRERE Vermieter. Der Einstieg ist
/// deshalb eine Liste; ein Tippen darauf öffnet die Akte dieses einen
/// Vermieters:
///
///   Details · Mietvertrag
///
/// ⚠️ Seit 20.08.2026 trägt der Vermieter NUR noch seine Stammdaten und
/// die Liste seiner Verträge. Bescheinigung, Zahlung, Inkasso,
/// Korrespondenz, Vollmacht und Akteneinsicht sind eine Ebene tiefer
/// gewandert — sie entstehen aus EINEM Mietverhältnis, nicht aus der
/// Firma. Wer zweimal beim selben Vermieter gewohnt hat, konnte vorher
/// nicht sagen, welche Miete zu welcher Wohnung gehörte.
class BehordeVermieterContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const BehordeVermieterContent({super.key, required this.apiService, required this.userId});
  @override
  State<BehordeVermieterContent> createState() => _BehordeVermieterContentState();
}

class _BehordeVermieterContentState extends State<BehordeVermieterContent> {
  List<Map<String, dynamic>> _vermieter = [];
  Map<String, dynamic>? _offen;
  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  /// [leise] lädt nach, OHNE die Ladeanzeige zu setzen.
  ///
  /// ⚠️ Das ist keine Feinheit, sondern die Reparatur einer Endlosschleife:
  /// die geöffnete Akte meldet nach jedem eigenen Laden zurück, damit die
  /// Zähler in der Liste stimmen. Setzte dieser Rücklauf `_laedt`, ersetzte
  /// der Aufbau hier die ganze Akte durch die Ladeanzeige — die Akte wurde
  /// abgeräumt, kam neu, lud, meldete zurück, und das ohne Ende. Auf dem
  /// Gerät sah das aus wie ein Flackern, das „nach ein paar Klicks aufhört".
  Future<void> _laden({bool leise = false}) async {
    if (!leise) setState(() => _laedt = true);
    try {
      final res = await widget.apiService.listVermieter(widget.userId);
      if (res['success'] == true) {
        _vermieter = List<Map<String, dynamic>>.from(res['vermieter'] as List? ?? []);
        // Den geöffneten Vermieter mitziehen: nach dem Speichern stünde
        // sonst der Stand von vorher im Kopf der Akte.
        if (_offen != null) {
          _offen = _vermieter.where((v) => v['id'] == _offen!['id']).firstOrNull;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _laedt = false);
  }

  /// Sucht in der öffentlichen Vermieter-Datenbank und legt den gewählten
  /// Eintrag als eigenen Vermieter an. Die Felder werden KOPIERT, nicht
  /// verknüpft — ändert die öffentliche Liste später eine Anschrift, darf
  /// das die Akte von vorgestern nicht rückwirkend umschreiben.
  void _ausDatenbank() {
    final sucheC = TextEditingController();
    List<Map<String, dynamic>> alle = [];
    List<Map<String, dynamic>> gefiltert = [];
    bool laedt = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
        if (laedt && alle.isEmpty) {
          widget.apiService.searchVermieterDatenbank('').then((res) {
            if (res['success'] == true) {
              alle = (res['results'] as List?)
                      ?.map((e) => Map<String, dynamic>.from(e as Map))
                      .toList() ??
                  [];
            }
            gefiltert = List.from(alle);
            setDlg(() => laedt = false);
          }).catchError((Object _) {
            setDlg(() => laedt = false);
            return null;
          });
        }
        void filtern(String q) {
          if (q.isEmpty) {
            setDlg(() => gefiltert = List.from(alle));
            return;
          }
          final k = q.toLowerCase();
          setDlg(() => gefiltert = alle
              .where((s) =>
                  (s['name']?.toString() ?? '').toLowerCase().contains(k) ||
                  (s['ort']?.toString() ?? '').toLowerCase().contains(k))
              .toList());
        }

        return AlertDialog(
          title: Row(children: [
            Icon(Icons.apartment, color: F.h(Colors.deepPurple, 700)),
            const SizedBox(width: 8),
            const Flexible(
                child: Text('Vermieter auswählen',
                    style: TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
          ]),
          content: SizedBox(
            width: dialogBreite(ctx2, 500),
            height: 400,
            child: Column(children: [
              TextField(
                controller: sucheC,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Filter…',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: filtern,
              ),
              const SizedBox(height: 12),
              if (laedt) const LinearProgressIndicator(),
              Expanded(
                child: gefiltert.isEmpty
                    ? Center(
                        child: Text(laedt ? '' : 'Keine Vermieter gefunden',
                            style: TextStyle(color: F.h(Colors.grey, 400))))
                    : ListView.builder(
                        itemCount: gefiltert.length,
                        itemBuilder: (_, i) {
                          final s = gefiltert[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: F.h(Colors.deepPurple, 100),
                                child: Icon(Icons.apartment,
                                    color: F.h(Colors.deepPurple, 700), size: 20),
                              ),
                              title: Text(s['name'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text(
                                  '${s['strasse'] ?? ''}, ${s['plz'] ?? ''} ${s['ort'] ?? ''}',
                                  style: const TextStyle(fontSize: 11)),
                              // ⚠️ Der Anrufknopf stammt aus der
                              // Zwischenzeit auf origin/main und bleibt:
                              // Auswählen ist der Griff auf die Zeile,
                              // Anrufen bekommt eine eigene Fläche.
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                PhoneCallButton(
                                    number: s['telefon']?.toString(),
                                    label: s['name']?.toString()),
                                Icon(Icons.add_circle_outline,
                                    color: Colors.deepPurple.shade400),
                              ]),
                              onTap: () async {
                                Navigator.pop(ctx);
                                await widget.apiService.saveVermieter(widget.userId, {
                                  'vermieter_db_id': s['id'],
                                  for (final f in const [
                                    'name', 'strasse', 'plz', 'ort',
                                    'telefon', 'fax', 'email', 'website',
                                    'typ', 'notiz',
                                  ])
                                    f: s[f]?.toString() ?? '',
                                  'status': 'aktiv',
                                });
                                _laden();
                              },
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ],
        );
      }),
    );
  }

  /// Frei erfasster Vermieter — oder Bearbeiten eines vorhandenen.
  /// Nicht jeder Privatvermieter steht in der Datenbank.
  void _bearbeiten([Map<String, dynamic>? v]) {
    final istNeu = v == null;
    final c = <String, TextEditingController>{
      for (final f in const [
        'name', 'strasse', 'plz', 'ort', 'telefon', 'fax', 'email', 'website', 'typ', 'notiz',
      ])
        f: TextEditingController(text: v?[f]?.toString() ?? ''),
    };
    String status = v?['status']?.toString() ?? 'aktiv';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Text(istNeu ? 'Vermieter erfassen' : 'Vermieter bearbeiten',
            style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: c['name'],
                decoration: InputDecoration(
                  labelText: 'Name *',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: c['typ'],
                decoration: InputDecoration(
                  labelText: 'Art',
                  hintText: 'z. B. Hausverwaltung, Genossenschaft, privat',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: c['strasse'],
                decoration: InputDecoration(
                  labelText: 'Straße und Nr.',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: c['plz'],
                    decoration: InputDecoration(
                      labelText: 'PLZ',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: c['ort'],
                    decoration: InputDecoration(
                      labelText: 'Ort',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: c['telefon'],
                    decoration: InputDecoration(
                      labelText: 'Telefon',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: c['fax'],
                    decoration: InputDecoration(
                      labelText: 'Fax',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: c['email'],
                decoration: InputDecoration(
                  labelText: 'E-Mail',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: c['website'],
                decoration: InputDecoration(
                  labelText: 'Website',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                for (final s in const ['aktiv', 'ehemalig']) ...[
                  ChoiceChip(
                    label: Text(s == 'aktiv' ? 'Aktuell' : 'Ehemalig',
                        style: const TextStyle(fontSize: 11)),
                    selected: status == s,
                    onSelected: (_) => setDlg(() => status = s),
                  ),
                  const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: c['notiz'],
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Notiz',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              if (c['name']!.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(
                  content: Text('Ohne Namen lässt sich der Vermieter später nicht zuordnen'),
                  backgroundColor: Colors.orange,
                ));
                return;
              }
              Navigator.pop(ctx);
              final res = await widget.apiService.saveVermieter(widget.userId, {
                if (!istNeu) 'id': v['id'],
                if (!istNeu && v['vermieter_db_id'] != null) 'vermieter_db_id': v['vermieter_db_id'],
                for (final e in c.entries) e.key: e.value.text.trim(),
                'status': status,
              });
              if (!mounted) return;
              if (res['success'] != true) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
                  backgroundColor: Colors.red,
                ));
                return;
              }
              // ⚠️ Leise, solange eine Akte offen ist: dieser Knopf sitzt
              // AUCH im Kopf der Akte. Mit Ladeanzeige flöge man beim
              // Speichern der Stammdaten aus dem gerade offenen Reiter
              // zurück auf „Details".
              _laden(leise: _offen != null);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
            child: Text(istNeu ? 'Anlegen' : 'Speichern'),
          ),
        ],
      )),
    );
  }

  Future<void> _loeschen(Map<String, dynamic> v) async {
    final z = v['counts'] as Map<String, dynamic>? ?? const {};
    final behalten = <String>[
      if ((z['mietvertraege'] ?? 0) != 0) '${z['mietvertraege']} Mietvertrag/-verträge',
      if ((z['bescheinigungen'] ?? 0) != 0) '${z['bescheinigungen']} Bescheinigung(en)',
      if ((z['zahlungen'] ?? 0) != 0) '${z['zahlungen']} Zahlung(en)',
    ];
    final weg = <String>[
      if ((z['korrespondenz'] ?? 0) != 0) '${z['korrespondenz']} Schriftverkehr-Eintrag/-Einträge',
      if ((z['vorfaelle'] ?? 0) != 0) '${z['vorfaelle']} Inkasso-Vorfall/-Vorfälle',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vermieter entfernen?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('„${v['name'] ?? ''}" wird aus der Liste genommen.'),
          if (behalten.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Beruhigt an genau der Stelle, an der man sonst abbricht.
            Text('Bleibt erhalten: ${behalten.join(', ')} — danach ohne Zuordnung.',
                style: TextStyle(fontSize: 12, color: F.h(Colors.green, 800))),
          ],
          if (weg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Wird mit gelöscht: ${weg.join(', ')} samt Dokumenten.',
                style: TextStyle(fontSize: 12, color: F.h(Colors.red, 700))),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entfernen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.apiService.deleteVermieter(widget.userId, v['id'] as int);
    if (!mounted) return;
    if (_offen?['id'] == v['id']) setState(() => _offen = null);
    _laden();
  }

  @override
  Widget build(BuildContext context) {
    if (_laedt) return const Center(child: CircularProgressIndicator());

    if (_offen != null) {
      return _VermieterAkte(
        key: ValueKey(_offen!['id']),
        apiService: widget.apiService,
        userId: widget.userId,
        vermieter: _offen!,
        onZurueck: () => setState(() => _offen = null),
        onBearbeiten: () => _bearbeiten(_offen),
        // Nur die Zähler auffrischen — die Akte darf dabei stehen bleiben.
        onReload: () => _laden(leise: true),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        // ⚠️ Überschrift und zwei Knöpfe passen auf dem Telefon nicht in
        // eine Zeile — gemessen 415 px Überlauf auf 411 dp. Unter 520 dp
        // steht die Überschrift deshalb über den Knöpfen, statt sie aus
        // dem Bild zu schieben. Der Vorsitzer arbeitet auch am Pixel.
        child: LayoutBuilder(builder: (_, c) {
          final eng = c.maxWidth < 520;
          final titel = Text('Zuständige Vermieter (${_vermieter.length})',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: F.h(Colors.deepPurple, 800)));
          final knoepfe = <Widget>[
            TextButton.icon(
              onPressed: () => _bearbeiten(),
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('Frei erfassen', style: TextStyle(fontSize: 12)),
            ),
            ElevatedButton.icon(
              onPressed: _ausDatenbank,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Aus Datenbank', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
            ),
          ];
          if (!eng) {
            return Row(children: [
              Flexible(child: titel),
              const Spacer(),
              knoepfe[0],
              const SizedBox(width: 4),
              knoepfe[1],
            ]);
          }
          // ⚠️ Wrap, nicht Row: bei Schriftgröße 2,0 passen auch die
          // beiden Knöpfe allein nicht mehr nebeneinander (gemessen
          // 277 px Überlauf). Wrap bricht dann um, statt abzuschneiden.
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            titel,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: knoepfe,
            ),
          ]);
        }),
      ),
      Expanded(
        child: _vermieter.isEmpty
            // ⚠️ Scrollbar, nicht bloß zentriert: bei Schriftgröße 2,0
            // bricht der Erklärtext auf mehr Zeilen um und der leere
            // Zustand läuft unten über (gemessen 41 px). Ausgerechnet der
            // Hinweis, der beim Anfangen hilft, wäre dann abgeschnitten —
            // und die Schriftgröße stellt ein, wer sie braucht.
            ? SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.apartment, size: 64, color: F.h(Colors.grey, 300)),
                    const SizedBox(height: 16),
                    Text('Kein Vermieter erfasst',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: F.h(Colors.grey, 500))),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Text(
                        'Mehrere sind möglich — jeder Umzug bekommt seinen eigenen '
                        'Eintrag mit Verträgen, Zahlungen und Schriftverkehr.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 400), height: 1.4),
                      ),
                    ),
                  ]),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _vermieter.length,
                itemBuilder: (_, i) {
                  final v = _vermieter[i];
                  final ehemalig = v['status'] == 'ehemalig';
                  final z = v['counts'] as Map<String, dynamic>? ?? const {};
                  final teile = <String>[
                    if ((z['mietvertraege'] ?? 0) != 0) '${z['mietvertraege']} Vertrag',
                    if ((z['zahlungen'] ?? 0) != 0) '${z['zahlungen']} Zahlungen',
                    if ((z['korrespondenz'] ?? 0) != 0) '${z['korrespondenz']} Schreiben',
                    if ((z['vorfaelle'] ?? 0) != 0) '${z['vorfaelle']} Inkasso',
                  ];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => setState(() => _offen = v),
                      leading: CircleAvatar(
                        backgroundColor:
                            ehemalig ? F.h(Colors.grey, 200) : F.h(Colors.deepPurple, 100),
                        child: Icon(Icons.apartment,
                            color: ehemalig ? F.h(Colors.grey, 600) : F.h(Colors.deepPurple, 700),
                            size: 20),
                      ),
                      title: Row(children: [
                        Flexible(
                          child: Text(v['name']?.toString() ?? '',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: ehemalig ? F.h(Colors.grey, 600) : null),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (ehemalig) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                                color: F.h(Colors.grey, 200),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text('Ehemalig',
                                style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: F.h(Colors.grey, 700))),
                          ),
                        ],
                      ]),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              if ((v['typ']?.toString() ?? '').isNotEmpty) v['typ'].toString(),
                              '${v['strasse'] ?? ''} ${v['plz'] ?? ''} ${v['ort'] ?? ''}'.trim(),
                            ].where((s) => s.isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (teile.isNotEmpty)
                            Text(teile.join(' · '),
                                style: TextStyle(fontSize: 10.5, color: Colors.deepPurple.shade400)),
                        ],
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: Icon(Icons.edit_outlined,
                              size: 18, color: Colors.deepPurple.shade300),
                          onPressed: () => _bearbeiten(v),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                          onPressed: () => _loeschen(v),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ==================== Die Akte EINES Vermieters ====================

class _VermieterAkte extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> vermieter;
  final VoidCallback onZurueck;
  final VoidCallback onBearbeiten;
  final Future<void> Function() onReload;

  const _VermieterAkte({
    super.key,
    required this.apiService,
    required this.userId,
    required this.vermieter,
    required this.onZurueck,
    required this.onBearbeiten,
    required this.onReload,
  });

  @override
  State<_VermieterAkte> createState() => _VermieterAkteState();
}

class _VermieterAkteState extends State<_VermieterAkte> with TickerProviderStateMixin {
  late TabController _tabC;
  List<Map<String, dynamic>> _mietvertraege = [];
  bool _laedt = true;

  int get _vermieterId => widget.vermieter['id'] as int;

  @override
  void initState() {
    super.initState();
    _tabC = TabController(length: 2, vsync: this);
    _laden();
  }

  @override
  void dispose() {
    _tabC.dispose();
    super.dispose();
  }

  /// Lädt NUR die Listen dieses einen Vermieters — der Server grenzt das
  /// über `vermieter_id` ein. Ohne die Eingrenzung stünden hier auch die
  /// Verträge der anderen Vermieter desselben Mitglieds.
  /// [leise] laesst die schon sichtbaren Reiter stehen, statt sie fuer die
  /// Dauer des Nachladens durch die Ladeanzeige zu ersetzen. Beim ersten
  /// Aufbau ist noch nichts da, dort ist die Anzeige richtig.
  Future<void> _laden({bool leise = false}) async {
    if (!leise) setState(() => _laedt = true);
    try {
      final res = await widget.apiService
          .getVermieterData(widget.userId, vermieterId: _vermieterId);
      if (res['success'] == true) {
        // Nur noch die Verträge: Bescheinigungen und Zahlungen hängen
        // seit 20.08.2026 am Vertrag und werden dort geladen.
        _mietvertraege = (res['mietvertraege'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
      }
    } catch (_) {}
    if (mounted) setState(() => _laedt = false);
    // Die Zähler in der Liste dahinter stimmen sonst nicht mehr.
    await widget.onReload();
  }

  Tab _tab(String text, IconData icon, bool gefuellt) => Tab(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: gefuellt ? F.h(Colors.green, 600) : F.h(Colors.grey, 400)),
          const SizedBox(width: 6),
          Text(text),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final v = widget.vermieter;
    final ehemalig = v['status'] == 'ehemalig';
    return Column(children: [
      Container(
        color: F.h(Colors.deepPurple, 50),
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: 'Zurück zur Vermieterliste',
            onPressed: widget.onZurueck,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v['name']?.toString() ?? '',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: ehemalig ? F.h(Colors.grey, 700) : F.h(Colors.deepPurple, 900)),
                  overflow: TextOverflow.ellipsis),
              Text(
                [
                  if ((v['typ']?.toString() ?? '').isNotEmpty) v['typ'].toString(),
                  '${v['strasse'] ?? ''} ${v['plz'] ?? ''} ${v['ort'] ?? ''}'.trim(),
                  if (ehemalig) 'ehemalig',
                ].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 18, color: Colors.deepPurple.shade400),
            tooltip: 'Stammdaten bearbeiten',
            onPressed: widget.onBearbeiten,
          ),
        ]),
      ),
      TabBar(
        controller: _tabC,
        labelColor: F.h(Colors.deepPurple, 800),
        unselectedLabelColor: F.h(Colors.grey, 500),
        indicatorColor: Colors.deepPurple,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          _tab('Details', Icons.info_outline, true),
          _tab('Mietvertrag', Icons.description, _mietvertraege.isNotEmpty),
        ],
      ),
      Expanded(
        child: _laedt
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(controller: _tabC, children: [
                _VermieterDetails(vermieter: v),
                _MietvertragTab(
                  mietvertraege: _mietvertraege,
                  apiService: widget.apiService,
                  userId: widget.userId,
                  vermieterId: _vermieterId,
                  vermieterName: (v['name']?.toString() ?? '').trim(),
                  onReload: () => _laden(leise: true),
                ),
              ]),
      ),
    ]);
  }
}

class _VermieterDetails extends StatelessWidget {
  final Map<String, dynamic> vermieter;
  const _VermieterDetails({required this.vermieter});

  @override
  Widget build(BuildContext context) {
    final s = vermieter;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: F.h(Colors.deepPurple, 50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: F.h(Colors.deepPurple, 200)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: F.h(Colors.deepPurple, 100),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.apartment, color: F.h(Colors.deepPurple, 700), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['name']?.toString() ?? '',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: F.h(Colors.deepPurple, 800))),
                  if ((s['typ']?.toString() ?? '').isNotEmpty)
                    Text(s['typ'].toString(),
                        style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade500)),
                ]),
              ),
            ]),
            const Divider(height: 20),
            _zeile(Icons.location_on, 'Adresse',
                '${s['strasse'] ?? ''}, ${s['plz'] ?? ''} ${s['ort'] ?? ''}'.trim()),
            _zeile(Icons.phone, 'Telefon', s['telefon']?.toString() ?? ''),
            // ⚠️ `Icons.print` steht bewusst NICHT in `_phoneIcons` — eine
            // Faxnummer darf keine Wählfläche werden. Ein Tipp daneben
            // riefe sonst ein Faxgerät an.
            _zeile(Icons.print, 'Fax', s['fax']?.toString() ?? ''),
            _zeile(Icons.email, 'E-Mail', s['email']?.toString() ?? ''),
            _zeile(Icons.language, 'Website', s['website']?.toString() ?? ''),
            if ((s['notiz']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: F.flaeche,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepPurple.shade100),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.deepPurple.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s['notiz'].toString(),
                        style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _zeile(IconData icon, String label, String wert) {
    if (wert.isEmpty || wert == ',') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.deepPurple.shade400),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(label, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
        ),
        Expanded(
          child: phoneAwareText(icon, wert, label: label, style: const TextStyle(fontSize: 13)),
        ),
      ]),
    );
  }
}

// ==================== TAB 2: Mietvertrag ====================
class _MietvertragTab extends StatefulWidget {
  final List<Map<String, dynamic>> mietvertraege;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  /// Bindet jeden neuen oder bearbeiteten Vertrag an genau diesen
  /// Vermieter. Ohne die id landete er wieder im gemeinsamen Topf des
  /// Mitglieds — und wäre in keiner Akte mehr zu finden.
  final int vermieterId;

  /// Sein Name — er reicht bis in den Widerspruch durch. Wer eine
  /// Forderung eintreiben lässt, ist der Gläubiger; das steht im
  /// Mietvertrag, und niemand soll es abtippen müssen.
  final String vermieterName;
  const _MietvertragTab({required this.mietvertraege, required this.apiService, required this.userId, required this.vermieterId, required this.vermieterName, required this.onReload});
  @override
  State<_MietvertragTab> createState() => _MietvertragTabState();
}
class _MietvertragTabState extends State<_MietvertragTab> {
  void _add([Map<String, dynamic>? e]) {
    final isEdit = e != null;
    final strasseC = TextEditingController(text: e?['strasse'] ?? '');
    final hausnrC = TextEditingController(text: e?['hausnummer'] ?? '');
    final plzC = TextEditingController(text: e?['plz'] ?? '');
    final ortC = TextEditingController(text: e?['ort'] ?? '');
    final kaltC = TextEditingController(text: e?['kaltmiete'] ?? '');
    final warmC = TextEditingController(text: e?['warmmiete'] ?? '');
    final nkC = TextEditingController(text: e?['nebenkosten'] ?? '');
    final heizC = TextEditingController(text: e?['heizkosten'] ?? '');
    final kautionC = TextEditingController(text: e?['kaution'] ?? '');
    // Wohnfläche in m² — relevant für Beratungshilfe §6 BerHG D2 + WBS.
    final qmC = TextEditingController(text: e?['wohnflaeche_qm'] ?? '');
    // Etage / Stockwerk — Freitext: "EG", "1. OG", "2. OG", "DG",
    // "UG", "Souterrain", "Maisonette" usw.
    final etageC = TextEditingController(text: e?['etage'] ?? '');
    final faelligC = TextEditingController(text: e?['faelligkeit'] ?? '');
    final beginnC = TextEditingController(text: e?['mietbeginn'] ?? '');
    final endeC = TextEditingController(text: e?['mietende'] ?? '');
    final kuendC = TextEditingController(text: e?['kuendigungsfrist'] ?? '');
    final notizC = TextEditingController(text: e?['notiz'] ?? '');
    String vertragsart = e?['vertragsart'] ?? 'unbefristet';
    String mietobjekt = e?['mietobjekt'] ?? 'wohnung';
    String zahlungsart = e?['zahlungsart'] ?? 'ueberweisung';
    String status = e?['status'] ?? 'aktiv';
    // Warmmiete = Kaltmiete + Heizkosten + Nebenkosten (kalte Betriebskosten).
    void recalcWarm() {
      final k = double.tryParse(kaltC.text.replaceAll(',', '.')) ?? 0;
      final h = double.tryParse(heizC.text.replaceAll(',', '.')) ?? 0;
      final n = double.tryParse(nkC.text.replaceAll(',', '.')) ?? 0;
      if (k > 0 || h > 0 || n > 0) warmC.text = (k + h + n).toStringAsFixed(2);
    }
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Text(isEdit ? 'Mietvertrag bearbeiten' : 'Neuer Mietvertrag', style: const TextStyle(fontSize: 15)),
      content: SizedBox(width: dialogBreite(ctx2, 500), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('Unbefristet'), selected: vertragsart == 'unbefristet', onSelected: (_) => setDlg(() => vertragsart = 'unbefristet')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Befristet'), selected: vertragsart == 'befristet', onSelected: (_) => setDlg(() => vertragsart = 'befristet')),
          const SizedBox(width: 16),
          for (final o in ['wohnung', 'haus', 'zimmer']) ...[ChoiceChip(label: Text(o[0].toUpperCase() + o.substring(1)), selected: mietobjekt == o, onSelected: (_) => setDlg(() => mietobjekt = o)), const SizedBox(width: 4)],
        ]),
        const SizedBox(height: 10),
        Row(children: [Expanded(flex: 3, child: TextField(controller: strasseC, decoration: InputDecoration(labelText: 'Straße', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), SizedBox(width: 60, child: TextField(controller: hausnrC, decoration: InputDecoration(labelText: 'Nr.', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
        const SizedBox(height: 8),
        Row(children: [SizedBox(width: 80, child: TextField(controller: plzC, decoration: InputDecoration(labelText: 'PLZ', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8), Expanded(child: TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))))]),
        const SizedBox(height: 8),
        FeldReihe(
          // Drei bis fünf Felder nebeneinander lassen auf 448 dp
          // je 83–139 dp übrig — kein Überlauf, aber nichts mehr,
          // worin sich ein Datum eintippen ließe.
          felder: [
            TextField(
            controller: kaltC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Kaltmiete €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (_) => recalcWarm(),
          ),
            TextField(
            controller: heizC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Heizkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (_) => recalcWarm(),
          ),
            TextField(
            controller: nkC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Nebenkosten €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (_) => recalcWarm(),
          ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: warmC,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Warmmiete € (= Kalt + Heiz + NK)',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: Icon(Icons.functions, size: 16, color: F.h(Colors.grey, 500)),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: kautionC, decoration: InputDecoration(labelText: 'Kaution €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: TextField(
            controller: qmC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Wohnfläche',
              suffixText: 'm²',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          )),
          const SizedBox(width: 8),
          SizedBox(width: 120, child: TextField(
            controller: etageC,
            decoration: InputDecoration(
              labelText: 'Etage',
              hintText: 'z. B. 2. OG',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: (() {
              final t = faelligC.text.trim();
              if (t.isEmpty) return null;
              final m = RegExp(r'(\d{1,2})').firstMatch(t);
              return m?.group(1);
            })(),
            // Ohne `isExpanded` richtet sich ein Dropdown nach seinem
            // breitesten Eintrag, nicht nach dem Feld. Ein langer Name
            // sprengte damit die Zeile — gemessen 241 dp in
            // ordnungsmassnahmen_screen. Als Formularfeld soll es
            // ohnehin die volle Breite haben.
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Zahltag (Miete fällig am)',
              isDense: true,
              prefixIcon: const Icon(Icons.event, size: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: List.generate(31, (i) => (i + 1).toString())
                .map((d) => DropdownMenuItem(value: d, child: Text('$d. des Monats', style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (v) => setDlg(() { if (v != null) faelligC.text = '$v. des Monats'; }),
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: beginnC, readOnly: true, decoration: InputDecoration(labelText: 'Mietbeginn', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) beginnC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
          const SizedBox(width: 8), Expanded(child: TextField(controller: endeC, readOnly: true, decoration: InputDecoration(labelText: 'Mietende', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) endeC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }))]),
        const SizedBox(height: 8),
        Row(children: [
          for (final z in ['ueberweisung', 'sepa']) ...[ChoiceChip(label: Text(z == 'sepa' ? 'SEPA-Lastschrift' : 'Überweisung'), selected: zahlungsart == z, onSelected: (_) => setDlg(() => zahlungsart = z)), const SizedBox(width: 8)],
          const SizedBox(width: 16),
          for (final s in ['aktiv', 'gekuendigt', 'beendet']) ...[ChoiceChip(label: Text(s[0].toUpperCase() + s.substring(1)), selected: status == s, onSelected: (_) => setDlg(() => status = s)), const SizedBox(width: 4)],
        ]),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          final body = {
            if (isEdit) 'id': e['id'], 'vertragsart': vertragsart, 'mietobjekt': mietobjekt, 'strasse': strasseC.text, 'hausnummer': hausnrC.text,
            'plz': plzC.text, 'ort': ortC.text, 'kaltmiete': kaltC.text, 'heizkosten': heizC.text, 'warmmiete': warmC.text, 'nebenkosten': nkC.text,
            'kaution': kautionC.text, 'wohnflaeche_qm': qmC.text, 'etage': etageC.text, 'faelligkeit': faelligC.text, 'zahlungsart': zahlungsart, 'mietbeginn': beginnC.text,
            'mietende': endeC.text, 'kuendigungsfrist': kuendC.text, 'status': status, 'notiz': notizC.text,
          };
          final resp = await widget.apiService.vermieterAction(widget.userId, {'action': 'save_mietvertrag', 'vermieter_id': widget.vermieterId, 'mietvertrag': body});
          await widget.onReload();
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          final newId = resp['id'] is int ? resp['id'] as int : int.tryParse(resp['id']?.toString() ?? '');
          if (newId != null && newId > 0) {
            // Find updated mietvertrag from refreshed list and open detail modal
            final fresh = widget.mietvertraege.firstWhere((mv) => (mv['id'] as int?) == newId, orElse: () => {...body, 'id': newId});
            _openDetail(fresh);
          }
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white), child: Text(isEdit ? 'Speichern' : 'Hinzufügen'))],
    )));
  }

  void _openDetail(Map<String, dynamic> m) {
    // ⚠️ Bildschirmfüllend, nicht als Kärtchen. Der Vertrag trägt NEUN
    // Reiter — Details, Mietvertrag, Nebenkostenabrechnung,
    // Mietbescheinigung, Zahlungen, Inkasso, Korrespondenz, Vollmacht,
    // Akteneinsicht. In 800×620 abzüglich Rand blieb davon auf jedem
    // Bildschirm ein Guckloch, auf dem Telefon erst recht. Dieselbe
    // Reparatur wie beim Aktenzeichen, hier nur vergessen.
    showDialog(context: context, builder: (ctx) => Dialog.fullscreen(
      child: SizedBox.expand(
        child: MietvertragDetailModal(
          mietvertrag: m,
          apiService: widget.apiService,
          userId: widget.userId,
          vermieterName: widget.vermieterName,
          onEditDetails: () { Navigator.pop(ctx); _add(m); },
          onReload: widget.onReload,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final statusColors = {'aktiv': Colors.green, 'gekuendigt': Colors.orange, 'beendet': Colors.grey};
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('Mietverträge (${widget.mietvertraege.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: F.h(Colors.deepPurple, 800))),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _add(), icon: const Icon(Icons.add, size: 16), label: const Text('Neu', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white)),
      ])),
      Expanded(child: widget.mietvertraege.isEmpty
        // ⚠️ Seit alles am Vertrag hängt, ist ein Vermieter ohne Vertrag
        // eine Sackgasse: Zahlungen, Schriftverkehr und Inkasso haben
        // nichts, woran sie hängen könnten. Statt eines toten Bildschirms
        // steht hier, was zu tun ist — und der Knopf gleich daneben.
        ? SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.description_outlined, size: 56, color: F.h(Colors.grey, 300)),
              const SizedBox(height: 14),
              Text('Noch kein Mietvertrag',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: F.h(Colors.grey, 600))),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  'Zahlungen, Bescheinigungen, Schriftverkehr und Inkasso '
                  'gehören zu einer bestimmten Wohnung. Legen Sie zuerst den '
                  'Mietvertrag an — danach steht in ihm alles Weitere.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500), height: 1.45),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _add(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Mietvertrag anlegen'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              ),
            ])),
          )
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: widget.mietvertraege.length, itemBuilder: (ctx, i) {
            final m = widget.mietvertraege[i];
            final st = m['status']?.toString() ?? 'aktiv';
            final color = statusColors[st] ?? Colors.grey;
            return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
              onTap: () => _openDetail(m),
              leading: CircleAvatar(backgroundColor: F.h(color, 100), child: Icon(Icons.description, color: F.h(color, 700), size: 20)),
              title: Text('${m['strasse'] ?? ''} ${m['hausnummer'] ?? ''}, ${m['plz'] ?? ''} ${m['ort'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${m['kaltmiete'] ?? ''} € kalt · ${m['warmmiete'] ?? ''} € warm · ${m['vertragsart'] ?? ''}', style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: F.h(color, 100), borderRadius: BorderRadius.circular(12)),
                  child: Text(st[0].toUpperCase() + st.substring(1), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: F.h(color, 800)))),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                  await widget.apiService.vermieterAction(widget.userId, {'action': 'delete_mietvertrag', 'id': m['id']}); await widget.onReload();
                }),
              ]),
            ));
          })),
    ]);
  }
}

// ==================== TAB 3: Mietbescheinigung ====================
class _BescheinigungTab extends StatefulWidget {
  final List<Map<String, dynamic>> bescheinigungen;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  final int mietvertragId;
  const _BescheinigungTab({required this.bescheinigungen, required this.apiService, required this.userId, required this.mietvertragId, required this.onReload});
  @override
  State<_BescheinigungTab> createState() => _BescheinigungTabState();
}
class _BescheinigungTabState extends State<_BescheinigungTab> {
  static const _typLabels = {'wohnungsgeberbescheinigung': 'Wohnungsgeberbescheinigung', 'mietbescheinigung': 'Mietbescheinigung', 'vermieterbestaetigung': 'Vermieterbestätigung', 'nebenkostenabrechnung': 'Nebenkostenabrechnung', 'sonstiges': 'Sonstiges'};
  void _add([Map<String, dynamic>? e]) {
    final isEdit = e != null;
    String typ = e?['typ'] ?? 'mietbescheinigung';
    final datumC = TextEditingController(text: e?['datum'] ?? '');
    final gueltigC = TextEditingController(text: e?['gueltig_bis'] ?? '');
    final notizC = TextEditingController(text: e?['notiz'] ?? '');
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Text(isEdit ? 'Bescheinigung bearbeiten' : 'Neue Bescheinigung', style: const TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          isExpanded: true,initialValue: typ, decoration: InputDecoration(labelText: 'Typ', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _typLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => typ = v ?? typ)),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: gueltigC, readOnly: true, decoration: InputDecoration(labelText: 'Gültig bis', isDense: true, prefixIcon: const Icon(Icons.event, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) gueltigC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async { Navigator.pop(ctx);
          await widget.apiService.vermieterAction(widget.userId, {'action': 'save_bescheinigung', 'mietvertrag_id': widget.mietvertragId, 'bescheinigung': {if (isEdit) 'id': e['id'], 'typ': typ, 'datum': datumC.text, 'gueltig_bis': gueltigC.text, 'notiz': notizC.text}});
          await widget.onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white), child: Text(isEdit ? 'Speichern' : 'Hinzufügen'))],
    )));
  }
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('Bescheinigungen (${widget.bescheinigungen.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: F.h(Colors.deepPurple, 800))),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _add(), icon: const Icon(Icons.add, size: 16), label: const Text('Neu', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white)),
      ])),
      Expanded(child: widget.bescheinigungen.isEmpty
        ? Center(child: Text('Keine Bescheinigungen', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: widget.bescheinigungen.length, itemBuilder: (ctx, i) {
            final b = widget.bescheinigungen[i];
            final bId = int.tryParse(b['id'].toString()) ?? 0;
            return Card(margin: const EdgeInsets.only(bottom: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(onTap: () => _add(b), dense: true,
                leading: Icon(Icons.verified, color: Colors.deepPurple.shade400, size: 22),
                title: Text(_typLabels[b['typ']] ?? b['typ']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('${b['datum'] ?? ''}${(b['gueltig_bis']?.toString() ?? '').isNotEmpty ? ' · Gültig bis: ${b['gueltig_bis']}' : ''}', style: const TextStyle(fontSize: 11)),
                trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                  await widget.apiService.vermieterAction(widget.userId, {'action': 'delete_bescheinigung', 'id': b['id']}); await widget.onReload();
                })),
              Padding(padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8), child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'vermieter_bescheinigung', korrespondenzId: bId, memberId: widget.userId)),
            ]));
          })),
    ]);
  }
}

// ==================== TAB 4: Zahlungen ====================
class _ZahlungenTab extends StatefulWidget {
  final List<Map<String, dynamic>> zahlungen;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  final int mietvertragId;
  const _ZahlungenTab({required this.zahlungen, required this.apiService, required this.userId, required this.mietvertragId, required this.onReload});
  @override
  State<_ZahlungenTab> createState() => _ZahlungenTabState();
}
class _ZahlungenTabState extends State<_ZahlungenTab> {
  static const _statusLabels = {'bezahlt': ('Bezahlt', Colors.green), 'offen': ('Offen', Colors.orange), 'ueberfaellig': ('Überfällig', Colors.red), 'storniert': ('Storniert', Colors.grey)};
  void _add([Map<String, dynamic>? e]) {
    final isEdit = e != null;
    final monatC = TextEditingController(text: e?['monat'] ?? '');
    final betragC = TextEditingController(text: e?['betrag'] ?? '');
    final datumC = TextEditingController(text: e?['datum'] ?? '');
    final notizC = TextEditingController(text: e?['notiz'] ?? '');
    String zahlungsart = e?['zahlungsart'] ?? 'ueberweisung';
    String status = e?['status'] ?? 'bezahlt';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Text(isEdit ? 'Zahlung bearbeiten' : 'Neue Zahlung', style: const TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: monatC, decoration: InputDecoration(labelText: 'Monat', hintText: 'z.B. April 2026', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: betragC, decoration: InputDecoration(labelText: 'Betrag €', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 10),
        Row(children: [for (final z in ['ueberweisung', 'sepa', 'bar']) ...[ChoiceChip(label: Text(z == 'sepa' ? 'SEPA' : z == 'bar' ? 'Bar' : 'Überweisung', style: const TextStyle(fontSize: 11)), selected: zahlungsart == z, onSelected: (_) => setDlg(() => zahlungsart = z)), const SizedBox(width: 6)]]),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Zahlungsdatum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          isExpanded: true,initialValue: status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: _statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.$1, style: TextStyle(fontSize: 12, color: e.value.$2)))).toList(),
          onChanged: (v) => setDlg(() => status = v ?? status)),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async { Navigator.pop(ctx);
          await widget.apiService.vermieterAction(widget.userId, {'action': 'save_zahlung', 'mietvertrag_id': widget.mietvertragId, 'zahlung': {if (isEdit) 'id': e['id'], 'monat': monatC.text, 'betrag': betragC.text, 'zahlungsart': zahlungsart, 'datum': datumC.text, 'status': status, 'notiz': notizC.text}});
          await widget.onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white), child: Text(isEdit ? 'Speichern' : 'Hinzufügen'))],
    )));
  }
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('Zahlungen (${widget.zahlungen.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: F.h(Colors.deepPurple, 800))),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _add(), icon: const Icon(Icons.add, size: 16), label: const Text('Neu', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white)),
      ])),
      Expanded(child: widget.zahlungen.isEmpty
        ? Center(child: Text('Keine Zahlungen', style: TextStyle(color: F.h(Colors.grey, 500))))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: widget.zahlungen.length, itemBuilder: (ctx, i) {
            final z = widget.zahlungen[i];
            final st = z['status']?.toString() ?? 'offen';
            final stInfo = _statusLabels[st] ?? ('Offen', Colors.orange);
            return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(onTap: () => _add(z), dense: true,
              leading: Icon(st == 'bezahlt' ? Icons.check_circle : Icons.pending, color: stInfo.$2, size: 22),
              title: Text('${z['monat'] ?? ''} — ${z['betrag'] ?? ''} €', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${z['datum'] ?? ''} · ${z['zahlungsart'] == 'sepa' ? 'SEPA' : z['zahlungsart'] == 'bar' ? 'Bar' : 'Überweisung'}', style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: stInfo.$2.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text(stInfo.$1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: stInfo.$2.shade800))),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () async {
                  await widget.apiService.vermieterAction(widget.userId, {'action': 'delete_zahlung', 'id': z['id']}); await widget.onReload();
                }),
              ]),
            ));
          })),
    ]);
  }
}

// ==================== MIETVERTRAG DETAIL MODAL ====================
// Three tabs: Details (read-only summary with "bearbeiten" button), Mietvertrag (upload contract),
// Nebenkostenabrechnung (per-year, with rechnungsdatum / Abrechnungszeitraum / Fälligkeit / Nachzahlung-Guthaben + amount + file).

/// Die Akte EINES Mietvertrags — neun Reiter.
///
/// ⚠️ Öffentlich, damit die Auflösungstests sie messen können. Neun Reiter
/// auf 411 dp sind kein Selbstläufer, und hinter einem Tippen versteckte
/// Bildschirme werden sonst nie gemessen.
class MietvertragDetailModal extends StatefulWidget {
  final Map<String, dynamic> mietvertrag;
  final ApiService apiService;
  final int userId;
  final VoidCallback onEditDetails;
  final Future<void> Function() onReload;

  /// Der Vermieter, zu dem dieser Vertrag gehört.
  final String vermieterName;
  const MietvertragDetailModal({
    super.key,
    required this.mietvertrag,
    required this.apiService,
    required this.userId,
    required this.onEditDetails,
    required this.onReload,
    this.vermieterName = '',
  });
  @override
  State<MietvertragDetailModal> createState() => MietvertragDetailModalState();
}

class MietvertragDetailModalState extends State<MietvertragDetailModal> with TickerProviderStateMixin {
  late TabController _tabC;
  List<Map<String, dynamic>> _docs = [];
  bool _loading = false;

  // Bescheinigungen und Zahlungen dieses EINEN Vertrags. Der Server
  // grenzt sie über `mietvertrag_id` ein — ohne das stünden hier die
  // aller Wohnungen des Mitglieds.
  List<Map<String, dynamic>> _bescheinigungen = [], _zahlungen = [];

  @override
  void initState() { super.initState(); _tabC = TabController(length: 9, vsync: this); _loadDocs(); _ladeListen(); }
  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  int get _mvId => widget.mietvertrag['id'] is int ? widget.mietvertrag['id'] as int : int.tryParse(widget.mietvertrag['id']?.toString() ?? '') ?? 0;

  Future<void> _ladeListen() async {
    if (_mvId <= 0) return;
    try {
      final res = await widget.apiService.getVermieterData(widget.userId, mietvertragId: _mvId);
      if (!mounted || res['success'] != true) return;
      setState(() {
        _bescheinigungen = (res['bescheinigungen'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _zahlungen = (res['zahlungen'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      });
    } catch (_) {}
  }

  /// Kurzname des Vertrags für Überschriften — die Anschrift ist das,
  /// woran man eine Wohnung wiedererkennt, nicht ihre id.
  String get _bezeichnung {
    final m = widget.mietvertrag;
    final s = '${m['strasse'] ?? ''} ${m['hausnummer'] ?? ''}'.trim();
    return s.isEmpty ? 'Mietvertrag' : s;
  }

  Future<void> _loadDocs() async {
    if (_mvId <= 0) return;
    setState(() => _loading = true);
    final r = await widget.apiService.listVermieterDokumente(userId: widget.userId, mietvertragId: _mvId);
    if (!mounted) return;
    final list = (r['dokumente'] ?? []) as List;
    setState(() {
      _docs = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _mietvertragDocs => _docs.where((d) => d['dokument_typ'] == 'mietvertrag').toList();
  List<Map<String, dynamic>> get _nkaDocs => _docs.where((d) => d['dokument_typ'] == 'nebenkostenabrechnung').toList();

  @override
  Widget build(BuildContext context) {
    final m = widget.mietvertrag;
    final adresse = '${m['strasse'] ?? ''} ${m['hausnummer'] ?? ''}, ${m['plz'] ?? ''} ${m['ort'] ?? ''}'.trim();
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: F.h(Colors.deepPurple, 50), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: Row(children: [
          Icon(Icons.home_work, color: F.h(Colors.deepPurple, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text(adresse, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: F.h(Colors.deepPurple, 800)), overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      // ⚠️ `isScrollable`: neun Reiter passen auf keinem Telefon in eine
      // feste Zeile. Ohne das schneidet Flutter sie stillschweigend ab —
      // und „Akteneinsicht" wäre auf dem Pixel schlicht nicht erreichbar.
      TabBar(
        controller: _tabC,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: F.h(Colors.deepPurple, 800),
        unselectedLabelColor: F.h(Colors.grey, 500),
        indicatorColor: Colors.deepPurple.shade700,
        tabs: [
          const Tab(text: 'Details', icon: Icon(Icons.info_outline, size: 18)),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.description, size: 18), const SizedBox(width: 6), Text('Mietvertrag${_mietvertragDocs.isEmpty ? '' : ' (${_mietvertragDocs.length})'}')])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.receipt_long, size: 18), const SizedBox(width: 6), Text('Nebenkostenabrechnung${_nkaDocs.isEmpty ? '' : ' (${_nkaDocs.length})'}')])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.verified, size: 18), const SizedBox(width: 6), Text('Mietbescheinigung${_bescheinigungen.isEmpty ? '' : ' (${_bescheinigungen.length})'}')])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.payments, size: 18), const SizedBox(width: 6), Text('Zahlungen${_zahlungen.isEmpty ? '' : ' (${_zahlungen.length})'}')])),
          const Tab(text: 'Inkasso', icon: Icon(Icons.gavel, size: 18)),
          const Tab(text: 'Korrespondenz', icon: Icon(Icons.mail, size: 18)),
          const Tab(text: 'Vollmacht', icon: Icon(Icons.assignment_ind, size: 18)),
          const Tab(text: 'Akteneinsicht', icon: Icon(Icons.fact_check, size: 18)),
        ],
      ),
      Expanded(child: TabBarView(controller: _tabC, children: [
        _detailsTab(m),
        _DokumenteTab(
          dokumentTyp: 'mietvertrag',
          mietvertragId: _mvId,
          userId: widget.userId,
          apiService: widget.apiService,
          docs: _mietvertragDocs,
          loading: _loading,
          onReload: _loadDocs,
        ),
        _NkaTab(
          mietvertragId: _mvId,
          userId: widget.userId,
          apiService: widget.apiService,
          docs: _nkaDocs,
          loading: _loading,
          onReload: _loadDocs,
        ),
        _BescheinigungTab(
          bescheinigungen: _bescheinigungen,
          apiService: widget.apiService,
          userId: widget.userId,
          mietvertragId: _mvId,
          onReload: _ladeListen,
        ),
        _ZahlungenTab(
          zahlungen: _zahlungen,
          apiService: widget.apiService,
          userId: widget.userId,
          mietvertragId: _mvId,
          onReload: _ladeListen,
        ),
        VermieterInkassoTab(
          apiService: widget.apiService,
          userId: widget.userId,
          mietvertragId: _mvId,
          vertragBezeichnung: _bezeichnung,
          vermieterName: widget.vermieterName,
        ),
        VermieterKorrespondenz(
          apiService: widget.apiService,
          userId: widget.userId,
          ebene: VermieterKorrEbene.vermieter,
          parentId: _mvId,
        ),
        const VermieterVollmachtPlatzhalter(bezug: 'den Vermieter'),
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: VermieterDokumente(
            apiService: widget.apiService,
            userId: widget.userId,
            typ: 'v_akteneinsicht',
            parentId: _mvId,
            titel: 'Unterlagen aus der Akteneinsicht',
            hinweis: 'Hier liegen Unterlagen, die beim Vermieter zu DIESER '
                'Wohnung angefordert wurden — etwa Belege zur '
                'Nebenkostenabrechnung nach § 259 BGB. Eigene Schreiben '
                'gehören unter Korrespondenz.',
          ),
        ),
      ])),
    ]);
  }

  Widget _detailsTab(Map<String, dynamic> m) {
    Widget row(String label, String value, {IconData? icon}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) Padding(padding: const EdgeInsets.only(right: 8, top: 2), child: Icon(icon, size: 16, color: F.h(Colors.grey, 600))),
        SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
        Expanded(child: Text(value.isEmpty ? '–' : value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
    String s(k) => (m[k] ?? '').toString();
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ⚠️ Expanded statt Spacer: ein freier Text in einer Row nimmt sich
      // seine volle natürliche Breite. Auf 411 dp lief die Zeile um 146 px
      // über — bis dahin war das Modal 800 dp breit und die Frage stellte
      // sich nie. Seit es neun Reiter trägt, wird es auch am Telefon
      // gemessen.
      Row(children: [
        Expanded(
          child: Text('Stammdaten',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.deepPurple, 800)),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(onPressed: widget.onEditDetails, icon: const Icon(Icons.edit, size: 14), label: const Text('Bearbeiten', style: TextStyle(fontSize: 12))),
      ]),
      const Divider(),
      row('Vertragsart', s('vertragsart'), icon: Icons.assignment),
      row('Mietobjekt', s('mietobjekt'), icon: Icons.home),
      row('Adresse', '${s('strasse')} ${s('hausnummer')}, ${s('plz')} ${s('ort')}', icon: Icons.location_on),
      row('Kaltmiete', '${s('kaltmiete')} €', icon: Icons.euro),
      row('Heizkosten', '${s('heizkosten')} €', icon: Icons.local_fire_department),
      row('Nebenkosten', '${s('nebenkosten')} €', icon: Icons.receipt_long),
      row('Warmmiete', '${s('warmmiete')} €', icon: Icons.functions),
      row('Kaution', '${s('kaution')} €', icon: Icons.savings),
      row(
        'Wohnfläche',
        s('wohnflaeche_qm').isEmpty ? '' : '${s('wohnflaeche_qm')} m²',
        icon: Icons.square_foot,
      ),
      row('Etage', s('etage'), icon: Icons.stairs),
      _zahltagRow(m),
      row('Zahlungsart', s('zahlungsart'), icon: Icons.payments),
      row('Mietbeginn', s('mietbeginn'), icon: Icons.event_available),
      row('Mietende', s('mietende'), icon: Icons.event_busy),
      row('Kündigungsfrist', s('kuendigungsfrist'), icon: Icons.timer),
      row('Status', s('status'), icon: Icons.flag),
      if (s('notiz').isNotEmpty) row('Notiz', s('notiz'), icon: Icons.notes),
    ]));
  }

  /// Inline-editable Zahltag row: dropdown 1..31, saves on selection.
  Widget _zahltagRow(Map<String, dynamic> m) {
    final current = (m['faelligkeit'] ?? '').toString();
    final m1 = RegExp(r'(\d{1,2})').firstMatch(current);
    final selected = m1?.group(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.event, size: 16, color: F.h(Colors.grey, 600))),
        SizedBox(width: 140, child: Text('Zahltag', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(
              hintText: 'Tag im Monat wählen',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              isDense: true,
            ),
            style: TextStyle(fontSize: 12, color: F.hd(Colors.black, F.textStark)),
            items: List.generate(31, (i) => (i + 1).toString())
                .map((d) => DropdownMenuItem(value: d, child: Text('$d. des Monats', style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (v) async { if (v != null) await _saveZahltag(v); },
          ),
        ),
      ]),
    );
  }

  Future<void> _saveZahltag(String day) async {
    final newValue = '$day. des Monats';
    final m = widget.mietvertrag;
    // Optimistic update so the UI reflects the change immediately
    setState(() => m['faelligkeit'] = newValue);
    await widget.apiService.vermieterAction(widget.userId, {
      'action': 'save_mietvertrag',
      'mietvertrag': {
        'id': m['id'],
        'vertragsart': m['vertragsart'] ?? '', 'mietobjekt': m['mietobjekt'] ?? '',
        'strasse': m['strasse'] ?? '', 'hausnummer': m['hausnummer'] ?? '',
        'plz': m['plz'] ?? '', 'ort': m['ort'] ?? '',
        'kaltmiete': m['kaltmiete'] ?? '', 'heizkosten': m['heizkosten'] ?? '', 'warmmiete': m['warmmiete'] ?? '', 'nebenkosten': m['nebenkosten'] ?? '',
        'kaution': m['kaution'] ?? '', 'wohnflaeche_qm': m['wohnflaeche_qm'] ?? '', 'etage': m['etage'] ?? '', 'faelligkeit': newValue,
        'zahlungsart': m['zahlungsart'] ?? '', 'mietbeginn': m['mietbeginn'] ?? '', 'mietende': m['mietende'] ?? '',
        'kuendigungsfrist': m['kuendigungsfrist'] ?? '', 'status': m['status'] ?? '', 'notiz': m['notiz'] ?? '',
      },
    });
    await widget.onReload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Zahltag auf $newValue gesetzt'),
      backgroundColor: Colors.green.shade600,
      duration: const Duration(seconds: 2),
    ));
  }
}

// ==================== TAB: Mietvertrag-Dokumente (generic upload list) ====================
class _DokumenteTab extends StatelessWidget {
  final String dokumentTyp;
  final int mietvertragId;
  final int userId;
  final ApiService apiService;
  final List<Map<String, dynamic>> docs;
  final bool loading;
  final Future<void> Function() onReload;
  const _DokumenteTab({
    required this.dokumentTyp,
    required this.mietvertragId,
    required this.userId,
    required this.apiService,
    required this.docs,
    required this.loading,
    required this.onReload,
  });

  /// [ausCloud] gesetzt = die Dateien kommen schon aus dem Cloud; der
  /// Geräte-Dialog entfällt, alles danach bleibt identisch.
  Future<void> _upload(BuildContext context, {FilePickerResult? ausCloud}) async {
    if (mietvertragId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte zuerst Mietvertrag speichern')));
      return;
    }
    final result = ausCloud ??
        await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf','jpg','jpeg','png','tiff','bmp'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    int ok = 0; String? lastErr;
    for (final f in result.files.where((f) => f.path != null)) {
      final r = await apiService.uploadVermieterDokument(
        userId: userId, mietvertragId: mietvertragId,
        dokumentTyp: dokumentTyp, filePath: f.path!, fileName: f.name,
      );
      if (r['success'] == true) { ok++; } else { lastErr = r['message']?.toString() ?? 'Upload fehlgeschlagen'; }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(lastErr == null ? '$ok Datei(en) hochgeladen' : 'Fehler: $lastErr'),
      backgroundColor: lastErr == null ? Colors.green.shade600 : Colors.red.shade600,
    ));
    await onReload();
  }

  Future<void> _view(BuildContext context, Map<String, dynamic> d) async {
    try {
      final resp = await apiService.downloadVermieterDokument(userId: userId, dokumentId: d['id'] as int);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      if (!context.mounted) return;
      final shown = await FileViewerDialog.showFromBytes(context, resp.bodyBytes, d['filename']?.toString() ?? 'dokument');
      if (!shown && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Format nicht unterstützt: ${d['filename']}')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öffnen fehlgeschlagen: $e')));
    }
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Dokument löschen?', style: TextStyle(fontSize: 15)),
      content: Text(d['filename']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
      ],
    ));
    if (ok != true) return;
    await apiService.deleteVermieterDokument(userId: userId, dokumentId: d['id'] as int);
    await onReload();
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.folder_open, size: 20, color: F.h(Colors.deepPurple, 700)),
        const SizedBox(width: 8),
        Text('Mietvertrag-Dokumente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: F.h(Colors.deepPurple, 800))),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => _upload(context),
          icon: const Icon(Icons.upload_file, size: 16),
          label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade600, foregroundColor: Colors.white),
        ),
        const SizedBox(width: 6),
        CloudPickButton(
          memberId: userId,
          apiService: apiService,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'tiff', 'bmp'],
          onPicked: (r) => _upload(context, ausCloud: r),
        ),
      ])),
      Expanded(child: loading
        ? const Center(child: CircularProgressIndicator())
        : docs.isEmpty
          ? Center(child: Text('Noch keine Dokumente hochgeladen', style: TextStyle(color: F.h(Colors.grey, 500), fontStyle: FontStyle.italic, fontSize: 12)))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: docs.length, itemBuilder: (ctx, i) {
              final d = docs[i];
              final mime = (d['mime_type'] ?? '').toString();
              return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                dense: true, visualDensity: VisualDensity.compact,
                leading: Icon(mime.contains('pdf') ? Icons.picture_as_pdf : Icons.image, color: F.h(Colors.deepPurple, 700)),
                title: Text(d['filename']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                subtitle: Text('${_fmtSize(d['file_size'] as int)} · ${(d['uploaded_at']?.toString() ?? '').substring(0, 16)}', style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: Icon(Icons.visibility, size: 18, color: F.h(Colors.blue, 700)), tooltip: 'Öffnen', onPressed: () => _view(context, d)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () => _delete(context, d)),
                ]),
              ));
            }),
      ),
    ]);
  }
}

// ==================== TAB: Nebenkostenabrechnung (year-grouped + meta fields) ====================
class _NkaTab extends StatelessWidget {
  final int mietvertragId;
  final int userId;
  final ApiService apiService;
  final List<Map<String, dynamic>> docs;
  final bool loading;
  final Future<void> Function() onReload;
  const _NkaTab({
    required this.mietvertragId,
    required this.userId,
    required this.apiService,
    required this.docs,
    required this.loading,
    required this.onReload,
  });

  /// Group docs by jahr (desc). Years with no docs are shown only if present in selectableYears via "+ Neue NKA".
  Map<int, List<Map<String, dynamic>>> get _byYear {
    final out = <int, List<Map<String, dynamic>>>{};
    for (final d in docs) {
      final j = d['jahr'] is int ? d['jahr'] as int : int.tryParse(d['jahr']?.toString() ?? '');
      if (j == null) continue;
      out.putIfAbsent(j, () => []).add(d);
    }
    return out;
  }

  Future<void> _addNkaDialog(BuildContext context) async {
    if (mietvertragId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte zuerst Mietvertrag speichern')));
      return;
    }
    final now = DateTime.now();
    int jahr = now.year - 1; // NKA covers previous year by default
    final rdC = TextEditingController(text: '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}');
    final vonC = TextEditingController(text: '01.01.${now.year - 1}');
    final bisC = TextEditingController(text: '31.12.${now.year - 1}');
    // Default Fälligkeit = today + 30 days
    final due = now.add(const Duration(days: 30));
    final fC = TextEditingController(text: '${due.day.toString().padLeft(2, '0')}.${due.month.toString().padLeft(2, '0')}.${due.year}');
    final betragC = TextEditingController();
    final notizC = TextEditingController();
    String typ = 'nachzahlung';
    final picked = <PlatformFile>[];

    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.receipt_long, size: 18, color: F.h(Colors.deepPurple, 700)), const SizedBox(width: 8), const Text('Neue Nebenkostenabrechnung', style: TextStyle(fontSize: 15))]),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: jahr,
            decoration: InputDecoration(labelText: 'Abrechnungsjahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: List.generate(now.year + 2 - 2025 + 1, (i) => 2025 + i).reversed.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
            onChanged: (v) {
              if (v == null) return;
              setDlg(() {
                jahr = v;
                vonC.text = '01.01.$jahr';
                bisC.text = '31.12.$jahr';
              });
            },
          )),
          const SizedBox(width: 8),
          Expanded(child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'nachzahlung', label: Text('Nachzahl.', style: TextStyle(fontSize: 11)), icon: Icon(Icons.arrow_upward, size: 14)),
              ButtonSegment(value: 'guthaben', label: Text('Guthaben', style: TextStyle(fontSize: 11)), icon: Icon(Icons.arrow_downward, size: 14)),
            ],
            selected: {typ},
            onSelectionChanged: (s) => setDlg(() => typ = s.first),
          )),
        ]),
        const SizedBox(height: 10),
        TextField(controller: rdC, readOnly: true, decoration: InputDecoration(labelText: 'Rechnungsdatum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de')); if (d != null) rdC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: vonC, readOnly: true, decoration: InputDecoration(labelText: 'Zeitraum von', isDense: true, prefixIcon: const Icon(Icons.event, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime(jahr, 1, 1), firstDate: DateTime(2000), lastDate: DateTime(2099), locale: const Locale('de')); if (d != null) vonC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: bisC, readOnly: true, decoration: InputDecoration(labelText: 'Zeitraum bis', isDense: true, prefixIcon: const Icon(Icons.event, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime(jahr, 12, 31), firstDate: DateTime(2000), lastDate: DateTime(2099), locale: const Locale('de')); if (d != null) bisC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: fC, readOnly: true, decoration: InputDecoration(labelText: 'Fälligkeit (Zahlungsfrist)', isDense: true, prefixIcon: const Icon(Icons.schedule, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: due, firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de')); if (d != null) fC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: betragC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Betrag €', isDense: true, prefixIcon: const Icon(Icons.euro, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz (optional)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () async {
              final r = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf','jpg','jpeg','png','tiff','bmp'], allowMultiple: true);
              if (r != null && r.files.isNotEmpty) {
                final keep = r.files.where((f) => f.path != null);
                setDlg(() {
                  final existingPaths = picked.map((p) => p.path).toSet();
                  for (final f in keep) { if (!existingPaths.contains(f.path)) picked.add(f); }
                });
              }
            },
            icon: Icon(picked.isEmpty ? Icons.attach_file : Icons.add, color: picked.isEmpty ? null : Colors.green),
            label: Text(picked.isEmpty ? 'Dateien auswählen (PDF/JPG, mehrere möglich)' : '${picked.length} Datei(en) ausgewählt — weitere hinzufügen', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          )),
          const SizedBox(width: 6),
          CloudPickButton(
            memberId: userId,
            apiService: apiService,
            allowedExtensions: const ['pdf','jpg','jpeg','png','tiff','bmp'],
            kompakt: true,
            onPicked: (r) => setDlg(() {
              final existingPaths = picked.map((p) => p.path).toSet();
              for (final f in r.files.where((f) => f.path != null)) {
                if (!existingPaths.contains(f.path)) picked.add(f);
              }
            }),
          ),
        ]),
        if (picked.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: picked.asMap().entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Icon(Icons.insert_drive_file, size: 14, color: Colors.deepPurple.shade400),
              const SizedBox(width: 4),
              Expanded(child: Text(entry.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
              InkWell(
                onTap: () => setDlg(() => picked.removeAt(entry.key)),
                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close, size: 14, color: Colors.red.shade400)),
              ),
            ]),
          )).toList()),
        ),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: picked.isEmpty ? null : () async {
          Navigator.pop(ctx);
          int ok = 0; String? lastErr;
          for (final f in picked) {
            if (f.path == null) continue;
            final r = await apiService.uploadVermieterDokument(
              userId: userId, mietvertragId: mietvertragId,
              dokumentTyp: 'nebenkostenabrechnung', jahr: jahr,
              rechnungsdatum: rdC.text, zeitraumVon: vonC.text, zeitraumBis: bisC.text,
              faelligkeit: fC.text, nkaTyp: typ, betrag: betragC.text, notiz: notizC.text,
              filePath: f.path!, fileName: f.name,
            );
            if (r['success'] == true) { ok++; } else { lastErr = r['message']?.toString() ?? 'Upload fehlgeschlagen'; }
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(lastErr == null ? '$ok Nebenkostenabrechnung(en) gespeichert' : 'Fehler: $lastErr'),
            backgroundColor: lastErr == null ? Colors.green.shade700 : Colors.red.shade600,
          ));
          await onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white), child: const Text('Speichern')),
      ],
    )));
  }

  Future<void> _view(BuildContext context, Map<String, dynamic> d) async {
    try {
      final resp = await apiService.downloadVermieterDokument(userId: userId, dokumentId: d['id'] as int);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      if (!context.mounted) return;
      await FileViewerDialog.showFromBytes(context, resp.bodyBytes, d['filename']?.toString() ?? 'dokument');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öffnen fehlgeschlagen: $e')));
    }
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('NKA löschen?', style: TextStyle(fontSize: 15)),
      content: Text('Jahr ${d['jahr']} — ${d['filename']}', style: const TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
      ],
    ));
    if (ok != true) return;
    await apiService.deleteVermieterDokument(userId: userId, dokumentId: d['id'] as int);
    await onReload();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _byYear;
    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.receipt_long, size: 20, color: F.h(Colors.deepPurple, 700)),
        const SizedBox(width: 8),
        Text('Nebenkostenabrechnung nach Jahr', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: F.h(Colors.deepPurple, 800))),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => _addNkaDialog(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neue NKA', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: loading
        ? const Center(child: CircularProgressIndicator())
        : years.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_long, size: 48, color: F.h(Colors.grey, 300)),
              const SizedBox(height: 8),
              Text('Noch keine Nebenkostenabrechnungen', style: TextStyle(color: F.h(Colors.grey, 500), fontStyle: FontStyle.italic, fontSize: 13)),
              const SizedBox(height: 6),
              Text('Beim Hinzufügen wählen Sie das Abrechnungsjahr,\nRechnungsdatum, Zeitraum, Fälligkeit, Betrag und Typ.', textAlign: TextAlign.center, style: TextStyle(color: F.h(Colors.grey, 400), fontSize: 11)),
            ])))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: years.length, itemBuilder: (ctx, i) {
              final y = years[i];
              final items = grouped[y]!;
              // All docs for the same Abrechnungsjahr belong to ONE NKA (a single
              // Abrechnung often comes with multiple PDFs / pages / annexes).
              // Show one card per year with the meta once and all files listed below.
              return _NkaYearCard(
                year: y,
                docs: items,
                initiallyExpanded: i == 0,
                onView: (d) => _view(context, d),
                onDelete: (d) => _delete(context, d),
              );
            }),
      ),
    ]);
  }
}

/// One NKA per Abrechnungsjahr — meta shown once, all attached files listed below.
class _NkaYearCard extends StatelessWidget {
  final int year;
  final List<Map<String, dynamic>> docs;
  final bool initiallyExpanded;
  final void Function(Map<String, dynamic>) onView;
  final void Function(Map<String, dynamic>) onDelete;
  const _NkaYearCard({
    required this.year,
    required this.docs,
    required this.initiallyExpanded,
    required this.onView,
    required this.onDelete,
  });

  /// Meta is taken from the first uploaded doc — they all share the same NKA
  /// (rechnungsdatum / zeitraum / fälligkeit / betrag / typ / notiz are written
  /// identically by the upload dialog for every file in the same submission).
  /// We prefer a doc that actually has meta filled in over an empty one.
  Map<String, dynamic> get _metaDoc {
    final withMeta = docs.firstWhere(
      (d) => (d['nka_typ'] ?? '').toString().isNotEmpty || (d['betrag'] ?? '').toString().isNotEmpty,
      orElse: () => docs.first,
    );
    return withMeta;
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final meta = _metaDoc;
    final typ = (meta['nka_typ'] ?? '').toString();
    final isNach = typ == 'nachzahlung';
    final typColor = typ.isEmpty ? Colors.grey : (isNach ? Colors.red : Colors.green);
    final betrag = (meta['betrag'] ?? '').toString();
    final rd = (meta['rechnungsdatum'] ?? '').toString();
    final zv = (meta['zeitraum_von'] ?? '').toString();
    final zb = (meta['zeitraum_bis'] ?? '').toString();
    final faellig = (meta['faelligkeit'] ?? '').toString();
    final notiz = (meta['notiz'] ?? '').toString();

    Widget metaRow(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 12, color: F.h(Colors.grey, 600)),
        const SizedBox(width: 4),
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 700)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
      ]),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: CircleAvatar(backgroundColor: F.h(Colors.deepPurple, 100), child: Text('$year', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.deepPurple, 800)))),
        title: Row(children: [
          Expanded(child: Text('Abrechnungsjahr $year', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          if (typ.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: F.h(typColor, 100), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isNach ? Icons.arrow_upward : Icons.arrow_downward, size: 11, color: F.h(typColor, 800)),
            const SizedBox(width: 2),
            Text(isNach ? 'Nachzahlung' : 'Guthaben', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: F.h(typColor, 800))),
          ])),
        ]),
        subtitle: Row(children: [
          if (betrag.isNotEmpty) ...[
            Icon(Icons.euro, size: 12, color: F.h(typColor, 700)),
            const SizedBox(width: 2),
            Text('$betrag €', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(typColor, 900))),
            const SizedBox(width: 8),
          ],
          Icon(Icons.folder_open, size: 12, color: F.h(Colors.grey, 600)),
          const SizedBox(width: 2),
          Text('${docs.length} Datei(en)', style: const TextStyle(fontSize: 11)),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        children: [
          // Meta block (once per NKA)
          if (rd.isNotEmpty || zv.isNotEmpty || zb.isNotEmpty || faellig.isNotEmpty || notiz.isNotEmpty) Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: F.h(Colors.grey, 50), borderRadius: BorderRadius.circular(8), border: Border.all(color: F.h(Colors.grey, 200))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (rd.isNotEmpty) metaRow(Icons.calendar_today, 'Rechnungsdatum', rd),
              if (zv.isNotEmpty || zb.isNotEmpty) metaRow(Icons.event, 'Zeitraum', '${zv.isEmpty ? '?' : zv} – ${zb.isEmpty ? '?' : zb}'),
              if (faellig.isNotEmpty) metaRow(Icons.schedule, 'Fällig bis', faellig),
              if (notiz.isNotEmpty) metaRow(Icons.notes, 'Notiz', notiz),
            ]),
          ),
          const SizedBox(height: 8),
          // Files block
          Row(children: [
            Icon(Icons.attach_file, size: 14, color: F.h(Colors.grey, 700)),
            const SizedBox(width: 4),
            Text('Beigefügte Dateien:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
          ]),
          const SizedBox(height: 4),
          ...docs.map((d) {
            final mime = (d['mime_type'] ?? '').toString();
            final filename = (d['filename'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: F.flaeche, borderRadius: BorderRadius.circular(6), border: Border.all(color: F.h(Colors.grey, 200))),
                child: Row(children: [
                  Icon(mime.contains('pdf') ? Icons.picture_as_pdf : Icons.image, size: 16, color: F.h(Colors.deepPurple, 700)),
                  const SizedBox(width: 6),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(filename, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                    Text(_fmtSize(d['file_size'] as int), style: TextStyle(fontSize: 9, color: F.h(Colors.grey, 600))),
                  ])),
                  IconButton(icon: Icon(Icons.visibility, size: 16, color: F.h(Colors.blue, 700)), tooltip: 'Öffnen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => onView(d)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => onDelete(d)),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }
}
