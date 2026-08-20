import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'phone_link.dart';
import 'vermieter_dokumente.dart';
import 'vermieter_korrespondenz.dart';
import 'vermieter_mahnverfahren.dart';
import 'vermieter_widerspruch.dart';

/// Inkasso unterhalb eines MIETVERTRAGS:
///
///   Zuständige Inkasso  ·  Vorfall
///                            └─ Aktenzeichen
///                                 └─ Details · Korrespondenz · Vollmacht · Akteneinsicht
///
/// ⚠️ Der Vorfall ist die Ebene, die es beim Vertrag (Strom) nicht gibt:
/// Ein Mietverhältnis erzeugt über die Jahre mehrere getrennte Vorgänge —
/// Mietrückstand 2024, Nebenkostennachzahlung 2025 — und jeder davon kann
/// beim Inkassobüro unter mehreren Aktenzeichen laufen. Ohne diese Ebene
/// lägen alle Aktenzeichen in einem Topf, und niemand könnte mehr sagen,
/// welche Forderung zu welchem Vorgang gehört.
///
/// ⚠️ Seit 20.08.2026 hängt das Ganze am MIETVERTRAG, nicht mehr am
/// Vermieter. Eine Forderung entsteht aus einer bestimmten Wohnung — bei
/// zwei Wohnungen desselben Vermieters wäre sonst nicht mehr zu sagen,
/// aus welcher.
class VermieterInkassoTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int mietvertragId;
  final String vertragBezeichnung;

  const VermieterInkassoTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.mietvertragId,
    required this.vertragBezeichnung,
  });

  @override
  State<VermieterInkassoTab> createState() => _VermieterInkassoTabState();
}

const _kStatusFarben = <String, MaterialColor>{
  'offen': Colors.orange,
  'in_bearbeitung': Colors.blue,
  'vergleich': Colors.teal,
  'ratenzahlung': Colors.indigo,
  'widerspruch': Colors.deepOrange,
  'gerichtlich': Colors.red,
  'abgeschlossen': Colors.green,
  'zurueckgewiesen': Colors.grey,
};

const _kStatusNamen = <String, String>{
  'offen': 'Offen',
  'in_bearbeitung': 'In Bearbeitung',
  'vergleich': 'Vergleich',
  'ratenzahlung': 'Ratenzahlung',
  'widerspruch': 'Widerspruch',
  'gerichtlich': 'Gerichtlich',
  'abgeschlossen': 'Abgeschlossen',
  'zurueckgewiesen': 'Zurückgewiesen',
};

String _datumDeutsch(Object? iso) {
  final s = iso?.toString() ?? '';
  if (s.length < 10) return '';
  return '${s.substring(8, 10)}.${s.substring(5, 7)}.${s.substring(0, 4)}';
}

Widget _statusChip(String? status) {
  final s = status ?? 'offen';
  final f = _kStatusFarben[s] ?? Colors.grey;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: f.shade50, borderRadius: BorderRadius.circular(12)),
    child: Text(_kStatusNamen[s] ?? s,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: f.shade800)),
  );
}

/// Ein Datumsfeld, das ISO an den Server gibt und deutsch anzeigt.
Widget _datumFeld({
  required BuildContext context,
  required TextEditingController controller,
  required String label,
  required VoidCallback onChanged,
}) {
  return TextField(
    controller: controller,
    readOnly: true,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      prefixIcon: const Icon(Icons.calendar_today, size: 16),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.clear, size: 16),
              onPressed: () {
                controller.clear();
                onChanged();
              },
            ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
    onTap: () async {
      final d = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2040),
        locale: const Locale('de'),
      );
      if (d != null) {
        controller.text = d.toIso8601String().substring(0, 10);
        onChanged();
      }
    },
  );
}

class _VermieterInkassoTabState extends State<VermieterInkassoTab> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: Colors.purple.shade50,
          // ⚠️ `isScrollable`, obwohl es nur zwei Reiter sind: bei
          // Schriftgröße 2,0 passt allein „Zuständige Inkasso" nicht mehr
          // in die halbe Breite eines 411-dp-Telefons — gemessen 43 px
          // Überlauf. Zwei Reiter sind kein Grund, eine feste Zeile zu
          // nehmen; die Schriftgröße stellt ein, wer sie braucht.
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.purple.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.purple.shade700,
            tabs: const [
              Tab(icon: Icon(Icons.business_center, size: 16), text: 'Zuständige Inkasso'),
              Tab(icon: Icon(Icons.folder_special, size: 16), text: 'Vorfall'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            _ZustaendigeInkasso(
              apiService: widget.apiService,
              mietvertragId: widget.mietvertragId,
            ),
            _VorfallListe(
              apiService: widget.apiService,
              userId: widget.userId,
              mietvertragId: widget.mietvertragId,
            ),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Zuständige Inkasso — Lupe in die Inkasso-Datenbank, dann die Karte
//
// ⚠️ Der Block „Unser Ansprechpartner dort" (Name, Durchwahl, E-Mail,
// eigenes Zeichen, Notizen) ist am 20.08.2026 entfallen — er war nie
// ausgefüllt und trug nichts zur Sache bei. Die Felder existieren
// serverseitig noch, werden aber nicht mehr geschrieben.
// ══════════════════════════════════════════════════════════════════════

class _ZustaendigeInkasso extends StatefulWidget {
  final ApiService apiService;
  final int mietvertragId;
  const _ZustaendigeInkasso({required this.apiService, required this.mietvertragId});

  @override
  State<_ZustaendigeInkasso> createState() => _ZustaendigeInkassoState();
}

class _ZustaendigeInkassoState extends State<_ZustaendigeInkasso> {
  Map<String, dynamic>? _aktuell;
  bool _geladen = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    try {
      final eigen = await widget.apiService.getVermieterInkasso(widget.mietvertragId);
      if (!mounted) return;
      // ⚠️ `exists` steht auf der Wurzel der Antwort, nicht in `data`.
      setState(() {
        _aktuell = eigen['exists'] == true ? (eigen['data'] as Map<String, dynamic>?) : null;
        _fehler = null;
        _geladen = true;
      });
    } catch (e) {
      // ⚠️ Ohne diesen Zweig bliebe `_geladen` für immer false und die
      // Ladeanzeige drehte sich endlos. Ein Test ist genau darauf zehn
      // Minuten hängen geblieben; am Telefon ohne Empfang hätte niemand
      // gewusst, worauf er wartet.
      if (!mounted) return;
      setState(() { _fehler = e.toString(); _geladen = true; });
    }
  }

  /// Sucht in der Inkasso-Datenbank — dieselbe Lupe wie beim Vermieter,
  /// damit derselbe Handgriff überall dasselbe tut.
  void _suchen() {
    final sucheC = TextEditingController();
    List<Map<String, dynamic>> alle = [];
    List<Map<String, dynamic>> gefiltert = [];
    bool laedt = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
        if (laedt && alle.isEmpty) {
          widget.apiService.listVermieterInkassoDatenbank().then((res) {
            alle = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
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
              .where((f) =>
                  (f['firmenname']?.toString() ?? '').toLowerCase().contains(k) ||
                  (f['plz_ort']?.toString() ?? '').toLowerCase().contains(k))
              .toList());
        }

        return AlertDialog(
          title: Row(children: [
            Icon(Icons.business_center, color: Colors.purple.shade700),
            const SizedBox(width: 8),
            const Flexible(
                child: Text('Inkasso auswählen',
                    style: TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
          ]),
          content: SizedBox(
            width: 500,
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
                        child: Text(laedt ? '' : 'Keine Inkasso-Firma gefunden',
                            style: TextStyle(color: Colors.grey.shade400)))
                    : ListView.builder(
                        itemCount: gefiltert.length,
                        itemBuilder: (_, i) {
                          final f = gefiltert[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.purple.shade100,
                                child: Icon(Icons.business_center,
                                    color: Colors.purple.shade700, size: 20),
                              ),
                              title: Text(f['firmenname']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text(
                                  '${f['strasse'] ?? ''}, ${f['plz_ort'] ?? ''}'.trim(),
                                  style: const TextStyle(fontSize: 11)),
                              trailing:
                                  Icon(Icons.check_circle_outline, color: Colors.purple.shade400),
                              onTap: () async {
                                Navigator.pop(ctx);
                                // Auswählen IST das Speichern — ein
                                // eigener Knopf für einen einzigen
                                // gewählten Eintrag wäre ein Schritt ohne
                                // Zweck. Genauso beim Vermieter.
                                final res = await widget.apiService.saveVermieterInkasso(
                                    widget.mietvertragId, {'inkasso_id': f['id']});
                                if (!mounted) return;
                                if (res['success'] != true) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(
                                        'Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
                                    backgroundColor: Colors.red,
                                  ));
                                  return;
                                }
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

  Future<void> _entfernen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zuordnung entfernen?'),
        content: const Text(
            'Nur die Firma wird entfernt. Vorfälle und Aktenzeichen bleiben erhalten — '
            'sie gehören zum Mietverhältnis, nicht zur Firma.'),
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
    await widget.apiService.deleteVermieterInkasso(widget.mietvertragId);
    _laden();
  }

  Widget _zeile(String label, String? wert, {IconData? symbol}) {
    final w = (wert ?? '').trim();
    if (w.isEmpty) return const SizedBox.shrink();
    // ⚠️ Bei Schriftgröße 2,0 lief die Zeile um 43 px über. Schuld war
    // nicht die Beschriftung, sondern die IBAN: 22 Zeichen am Stück, die
    // sich nirgends umbrechen lassen. Deshalb zwei Dinge — die Marke
    // steht bei engem Platz ÜBER dem Wert statt daneben, und die IBAN
    // wird in Vierergruppen gesetzt. Das bricht nicht nur um, es ist
    // auch die Form, in der sie auf dem Schreiben steht, mit dem
    // verglichen werden soll.
    final marke = Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600));
    final inhalt = phoneAwareText(symbol ?? Icons.info_outline, w,
        label: label, style: const TextStyle(fontSize: 12.5));
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: LayoutBuilder(builder: (_, c) {
        final eng = c.maxWidth < 340 * MediaQuery.textScalerOf(context).scale(1.0);
        if (eng) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (symbol != null) ...[
                Icon(symbol, size: 15, color: Colors.purple.shade300),
                const SizedBox(width: 6),
              ],
              Flexible(child: marke),
            ]),
            const SizedBox(height: 2),
            inhalt,
            const SizedBox(height: 4),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (symbol != null) ...[
            Icon(symbol, size: 15, color: Colors.purple.shade300),
            const SizedBox(width: 8),
          ],
          SizedBox(width: 132, child: marke),
          Expanded(child: inhalt),
        ]);
      }),
    );
  }

  /// `DE23360100430999684438` → `DE23 3601 0043 0999 6844 38`
  String _ibanLesbar(String roh) {
    final k = roh.replaceAll(' ', '').toUpperCase();
    if (k.length < 8) return roh;
    final teile = <String>[];
    for (var i = 0; i < k.length; i += 4) {
      teile.add(k.substring(i, i + 4 > k.length ? k.length : i + 4));
    }
    return teile.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    if (_fehler != null) return LadeFehler(meldung: _fehler!, onErneut: _laden);
    final f = _aktuell?['inkasso_lookup'] as Map<String, dynamic>?;

    if (f == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.business_center, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text('Keine Inkasso-Firma zugeordnet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                'Wählen Sie die Firma, die im Schreiben als Absender steht — '
                'nicht die, an die überwiesen werden soll.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.45),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _suchen,
              icon: const Icon(Icons.search, size: 20),
              label: const Text('Inkasso suchen'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
          ]),
        ),
      );
    }

    final iban = (f['iban']?.toString() ?? '').trim();
    final hinweis = (f['zahlungshinweis']?.toString() ?? '').trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Zuständige Inkasso',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple.shade800),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _suchen,
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: const Text('Ändern', style: TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                    color: Colors.purple.shade100, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.business_center, color: Colors.purple.shade700, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(f['firmenname']?.toString() ?? '',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple.shade900)),
              ),
              IconButton(
                icon: Icon(Icons.close, color: Colors.red.shade400),
                tooltip: 'Zuordnung entfernen',
                onPressed: _entfernen,
              ),
            ]),
            const Divider(height: 20),
            _zeile('Anschrift',
                '${f['strasse'] ?? ''}, ${f['plz_ort'] ?? ''}'.trim().replaceAll(RegExp(r'^,\s*'), ''),
                symbol: Icons.location_on),
            _zeile('Telefon', f['telefon']?.toString(), symbol: Icons.phone),
            _zeile('Fax', f['fax']?.toString(), symbol: Icons.print),
            _zeile('E-Mail', f['email']?.toString(), symbol: Icons.email),
            _zeile('Website', f['website']?.toString(), symbol: Icons.language),
            _zeile('Geschäftsführung', f['geschaeftsfuehrer']?.toString(), symbol: Icons.person),
            _zeile('Handelsregister', f['hrb']?.toString(), symbol: Icons.account_balance),
            _zeile('USt-IdNr.', f['ust_id']?.toString(), symbol: Icons.tag),
            // Die Erlaubnis nach dem RDG ist der Grund, warum ein
            // Inkassobüro überhaupt fordern darf. Sie gehört sichtbar in
            // die Akte, nicht in eine Fußnote.
            _zeile('RDG-Erlaubnis', f['rdg_lizenz']?.toString(), symbol: Icons.verified_user),
          ]),
        ),
        const SizedBox(height: 14),

        // ── Bankverbindung ────────────────────────────────────────────
        // ⚠️ Der gefährlichste Block der ganzen Akte. Eine falsche IBAN
        // ist Geld, das weg ist, während die Forderung bestehen bleibt —
        // und gefälschte Inkassoschreiben unterscheiden sich oft NUR in
        // dieser Zeile. Deshalb steht hier immer dabei, woher die Zahlen
        // stammen, und niemals nur die nackte IBAN.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: iban.isEmpty ? Colors.amber.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: iban.isEmpty ? Colors.amber.shade200 : Colors.purple.shade100),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ⚠️ Expanded, obwohl das Wort kurz aussieht: bei Schriftgröße
            // 2,0 ist „Bankverbindung" plus Symbol breiter als ein
            // 411-dp-Telefon abzüglich der Polster — gemessen 43 px
            // Überlauf. Ein freier Text in einer Row nimmt sich immer
            // seine volle natürliche Breite, egal wie kurz er wirkt.
            Row(children: [
              Icon(Icons.account_balance_wallet,
                  size: 16, color: iban.isEmpty ? Colors.amber.shade800 : Colors.purple.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Bankverbindung',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: iban.isEmpty ? Colors.amber.shade900 : Colors.purple.shade800)),
              ),
            ]),
            const SizedBox(height: 10),
            if (iban.isEmpty)
              Text(
                'Für diese Firma ist keine allgemeine Bankverbindung hinterlegt. '
                'Empfänger, IBAN, BIC und Verwendungszweck stehen ausschließlich '
                'auf dem jeweiligen Schreiben.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.45),
              )
            else ...[
              _zeile('Kontoinhaber', f['bank_inhaber']?.toString()),
              _zeile('Bank', f['bank_name']?.toString()),
              _zeile('IBAN', _ibanLesbar(iban)),
              _zeile('BIC', f['bic']?.toString()),
            ],
            if (hinweis.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.red.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(hinweis,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.red.shade900, height: 1.45)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Vor jeder Zahlung mit dem Original-Schreiben abgleichen.',
              style: TextStyle(
                  fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
            ),
          ]),
        ),
        if ((f['notizen']?.toString() ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(f['notizen'].toString(),
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.4)),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Vorfall-Liste → ein Vorfall → seine Aktenzeichen
// ══════════════════════════════════════════════════════════════════════

class _VorfallListe extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int mietvertragId;
  const _VorfallListe({
    required this.apiService,
    required this.userId,
    required this.mietvertragId,
  });

  @override
  State<_VorfallListe> createState() => _VorfallListeState();
}

class _VorfallListeState extends State<_VorfallListe> {
  List<Map<String, dynamic>> _items = [];
  bool _geladen = false;
  String? _fehler;
  Map<String, dynamic>? _offen;

  /// Der Name des Büros — für den Kopf des Widerspruchsschreibens. Wird
  /// hier einmal geholt und weitergereicht, statt in jedem Vorfall neu.
  String? _inkassoName;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    late final Map<String, dynamic> res;
    try {
      res = await widget.apiService.listVermieterVorfaelle(widget.mietvertragId);
      final ink = await widget.apiService.getVermieterInkasso(widget.mietvertragId);
      if (ink['exists'] == true) {
        final lookup = (ink['data'] as Map<String, dynamic>?)?['inkasso_lookup']
            as Map<String, dynamic>?;
        _inkassoName = lookup?['firmenname']?.toString();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _fehler = e.toString(); _geladen = true; });
      return;
    }
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _fehler = null;
      _geladen = true;
      // Der geöffnete Vorfall wird mitgezogen, damit nach dem Speichern
      // nicht plötzlich der alte Stand im Kopf des Detailbereichs steht.
      if (_offen != null) {
        final id = _offen!['id'];
        _offen = _items.where((v) => v['id'] == id).firstOrNull;
      }
    });
  }

  void _bearbeiten([Map<String, dynamic>? v]) {
    final istNeu = v == null;
    final bezC = TextEditingController(text: v?['bezeichnung']?.toString() ?? '');
    final grundC = TextEditingController(text: v?['grund']?.toString() ?? '');
    final fordC = TextEditingController(text: v?['forderung_brutto']?.toString() ?? '');
    final gezahltC = TextEditingController(text: v?['gezahlt']?.toString() ?? '');
    final notizC = TextEditingController(text: v?['notizen']?.toString() ?? '');
    final eroeffnetC = TextEditingController(text: v?['eroeffnet_am']?.toString() ?? '');
    final fristC = TextEditingController(text: v?['naechste_frist']?.toString() ?? '');
    final geschlossenC = TextEditingController(text: v?['geschlossen_am']?.toString() ?? '');
    String status = v?['status']?.toString() ?? 'offen';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Text(istNeu ? 'Neuer Vorfall' : 'Vorfall bearbeiten',
            style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: bezC,
                decoration: InputDecoration(
                  labelText: 'Bezeichnung *',
                  hintText: 'z. B. Mietrückstand 2026',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: grundC,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Grund der Forderung',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: fordC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Forderung €',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: gezahltC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Davon gezahlt €',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: status,
                decoration: InputDecoration(
                  labelText: 'Status',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: _kStatusNamen.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (x) => setDlg(() => status = x ?? status),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _datumFeld(
                    context: ctx2,
                    controller: eroeffnetC,
                    label: 'Eröffnet am',
                    onChanged: () => setDlg(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _datumFeld(
                    context: ctx2,
                    controller: fristC,
                    label: 'Nächste Frist',
                    onChanged: () => setDlg(() {}),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              _datumFeld(
                context: ctx2,
                controller: geschlossenC,
                label: 'Geschlossen am',
                onChanged: () => setDlg(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notizC,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notizen',
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
              if (bezC.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(
                  content: Text('Ohne Bezeichnung lässt sich der Vorfall später nicht wiederfinden'),
                  backgroundColor: Colors.orange,
                ));
                return;
              }
              Navigator.pop(ctx);
              final res = await widget.apiService.saveVermieterVorfall(widget.mietvertragId, {
                if (!istNeu) 'id': v['id'],
                'bezeichnung': bezC.text.trim(),
                'grund': grundC.text.trim(),
                'forderung_brutto': fordC.text.trim(),
                'gezahlt': gezahltC.text.trim(),
                'notizen': notizC.text.trim(),
                'status': status,
                'eroeffnet_am': eroeffnetC.text,
                'naechste_frist': fristC.text,
                'geschlossen_am': geschlossenC.text,
              });
              if (!mounted) return;
              if (res['success'] != true) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
                  backgroundColor: Colors.red,
                ));
                return;
              }
              _laden();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
            child: Text(istNeu ? 'Anlegen' : 'Speichern'),
          ),
        ],
      )),
    );
  }

  Future<void> _loeschen(Map<String, dynamic> v) async {
    final anzahl = int.tryParse(v['aktenzeichen_count']?.toString() ?? '0') ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vorfall löschen?'),
        content: Text(anzahl > 0
            ? 'Mit dem Vorfall verschwinden auch seine $anzahl Aktenzeichen, '
                'deren Schriftverkehr und alle hinterlegten Dokumente.'
            : 'Der Vorfall wird endgültig entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.apiService.deleteVermieterVorfall(v['id'] as int);
    if (!mounted) return;
    if (_offen?['id'] == v['id']) setState(() => _offen = null);
    _laden();
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    if (_fehler != null) return LadeFehler(meldung: _fehler!, onErneut: _laden);

    if (_offen != null) {
      return _VorfallDetail(
        apiService: widget.apiService,
        userId: widget.userId,
        vorfall: _offen!,
        inkassoName: _inkassoName,
        onZurueck: () => setState(() => _offen = null),
        onBearbeiten: () => _bearbeiten(_offen),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          // Dieselbe Vorsicht wie bei der Korrespondenz-Überschrift:
          // ein freier Text in einer Row nimmt sich seine volle Breite.
          Expanded(
            child: Text('Vorfälle (${_items.length})',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple.shade800),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _bearbeiten(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: _items.isEmpty
            // Scrollbar aus demselben Grund wie in der Vermieterliste:
            // bei großer Schrift läuft der Erklärtext sonst unten heraus.
            ? SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.folder_special, size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Kein Vorfall erfasst',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        'Ein Vorfall bündelt einen Vorgang — etwa einen Mietrückstand — '
                        'mit allen Aktenzeichen, unter denen er beim Inkassobüro läuft.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final v = _items[i];
                  final anzahl = int.tryParse(v['aktenzeichen_count']?.toString() ?? '0') ?? 0;
                  final frist = v['naechste_frist']?.toString() ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => setState(() => _offen = v),
                      leading: CircleAvatar(
                        backgroundColor: (_kStatusFarben[v['status']] ?? Colors.grey).shade50,
                        child: Icon(Icons.gavel,
                            size: 20,
                            color: (_kStatusFarben[v['status']] ?? Colors.grey).shade700),
                      ),
                      title: Text(v['bezeichnung']?.toString() ?? '(ohne Bezeichnung)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$anzahl Aktenzeichen'
                            '${(v['forderung_brutto']?.toString() ?? '').isNotEmpty ? ' · ${v['forderung_brutto']} €' : ''}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (frist.isNotEmpty)
                            Text('Nächste Frist: ${_datumDeutsch(frist)}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.w600)),
                        ],
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        _statusChip(v['status']?.toString()),
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

// ══════════════════════════════════════════════════════════════════════
// Ein Vorfall: Kopfdaten + seine Aktenzeichen
// ══════════════════════════════════════════════════════════════════════

class _VorfallDetail extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> vorfall;
  final String? inkassoName;
  final VoidCallback onZurueck;
  final VoidCallback onBearbeiten;

  const _VorfallDetail({
    required this.apiService,
    required this.userId,
    required this.vorfall,
    required this.onZurueck,
    required this.onBearbeiten,
    this.inkassoName,
  });

  @override
  State<_VorfallDetail> createState() => _VorfallDetailState();
}

class _VorfallDetailState extends State<_VorfallDetail> {
  List<Map<String, dynamic>> _akten = [];
  bool _geladen = false;
  String? _fehler;

  int get _vorfallId => widget.vorfall['id'] as int;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void didUpdateWidget(_VorfallDetail alt) {
    super.didUpdateWidget(alt);
    if (alt.vorfall['id'] != widget.vorfall['id']) _laden();
  }

  Future<void> _laden() async {
    try {
      final res = await widget.apiService.listVermieterAktenzeichen(_vorfallId);
      if (!mounted) return;
      setState(() {
        _akten = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
        _fehler = null;
        _geladen = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _fehler = e.toString(); _geladen = true; });
    }
  }

  void _bearbeiten([Map<String, dynamic>? a]) {
    final istNeu = a == null;
    final azC = TextEditingController(text: a?['aktenzeichen']?.toString() ?? '');
    final bezC = TextEditingController(text: a?['bezeichnung']?.toString() ?? '');
    final fordC = TextEditingController(text: a?['forderung_brutto']?.toString() ?? '');
    final gezahltC = TextEditingController(text: a?['gezahlt']?.toString() ?? '');
    final notizC = TextEditingController(text: a?['notizen']?.toString() ?? '');
    final eroeffnetC = TextEditingController(text: a?['eroeffnet_am']?.toString() ?? '');
    final fristC = TextEditingController(text: a?['naechste_frist']?.toString() ?? '');
    final geschlossenC = TextEditingController(text: a?['geschlossen_am']?.toString() ?? '');
    String status = a?['status']?.toString() ?? 'offen';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Text(istNeu ? 'Neues Aktenzeichen' : 'Aktenzeichen bearbeiten',
            style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: azC,
                decoration: InputDecoration(
                  labelText: 'Aktenzeichen *',
                  hintText: 'wie im Schreiben des Inkassobüros',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bezC,
                decoration: InputDecoration(
                  labelText: 'Bezeichnung',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: fordC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Forderung €',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: gezahltC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Davon gezahlt €',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: status,
                decoration: InputDecoration(
                  labelText: 'Status',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: _kStatusNamen.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (x) => setDlg(() => status = x ?? status),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _datumFeld(
                    context: ctx2,
                    controller: eroeffnetC,
                    label: 'Eröffnet am',
                    onChanged: () => setDlg(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _datumFeld(
                    context: ctx2,
                    controller: fristC,
                    label: 'Nächste Frist',
                    onChanged: () => setDlg(() {}),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              _datumFeld(
                context: ctx2,
                controller: geschlossenC,
                label: 'Geschlossen am',
                onChanged: () => setDlg(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notizC,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notizen',
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
              if (azC.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(
                  content: Text('Das Aktenzeichen ist die Kennung, unter der das Büro schreibt'),
                  backgroundColor: Colors.orange,
                ));
                return;
              }
              Navigator.pop(ctx);
              final res = await widget.apiService.saveVermieterAktenzeichen(_vorfallId, {
                if (!istNeu) 'id': a['id'],
                'aktenzeichen': azC.text.trim(),
                'bezeichnung': bezC.text.trim(),
                'forderung_brutto': fordC.text.trim(),
                'gezahlt': gezahltC.text.trim(),
                'notizen': notizC.text.trim(),
                'status': status,
                'eroeffnet_am': eroeffnetC.text,
                'naechste_frist': fristC.text,
                'geschlossen_am': geschlossenC.text,
              });
              if (!mounted) return;
              if (res['success'] != true) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
                  backgroundColor: Colors.red,
                ));
                return;
              }
              _laden();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
            child: Text(istNeu ? 'Anlegen' : 'Speichern'),
          ),
        ],
      )),
    );
  }

  void _oeffnen(Map<String, dynamic> a) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(
          width: 820,
          height: 640,
          child: VermieterAktenzeichenDetail(
            apiService: widget.apiService,
            userId: widget.userId,
            aktenzeichen: a,
            onBearbeiten: () {
              Navigator.pop(ctx);
              _bearbeiten(a);
            },
          ),
        ),
      ),
    ).then((_) => _laden());
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vorfall;
    // ⚠️ Vier Reiter, und `isScrollable`: „Mahnverfahren" und
    // „Korrespondenz" nebeneinander sprengen bei großer Schrift jede
    // feste Zeile. Gemessen wurde das an derselben Stelle schon dreimal.
    return DefaultTabController(
      length: 5,
      child: Column(children: [
        Container(
          color: Colors.purple.shade50,
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              tooltip: 'Zurück zu den Vorfällen',
              onPressed: widget.onZurueck,
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v['bezeichnung']?.toString() ?? '(ohne Bezeichnung)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14, color: Colors.purple.shade900),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  [
                    if ((v['forderung_brutto']?.toString() ?? '').isNotEmpty)
                      '${v['forderung_brutto']} €',
                    if ((v['gezahlt']?.toString() ?? '').isNotEmpty) 'gezahlt ${v['gezahlt']} €',
                    if ((v['eroeffnet_am']?.toString() ?? '').isNotEmpty)
                      'seit ${_datumDeutsch(v['eroeffnet_am'])}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            _statusChip(v['status']?.toString()),
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 18, color: Colors.purple.shade400),
              tooltip: 'Vorfall bearbeiten',
              onPressed: widget.onBearbeiten,
            ),
          ]),
        ),
        Container(
          color: Colors.purple.shade50,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.purple.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.purple.shade700,
            tabs: const [
              Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
              Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
              Tab(icon: Icon(Icons.assignment_ind, size: 16), text: 'Vollmacht'),
              Tab(icon: Icon(Icons.gavel, size: 16), text: 'Mahnverfahren'),
              // ⚠️ Direkt neben dem Mahnverfahren, weil die beiden ständig
              // verwechselt werden — und weil man dann sieht, dass es zwei
              // sind. Der eine geht an das Gericht, der andere an das Büro.
              Tab(icon: Icon(Icons.block, size: 16), text: 'Widerspruch'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            _detailsMitAktenzeichen(v),
            VermieterKorrespondenz(
              apiService: widget.apiService,
              userId: widget.userId,
              ebene: VermieterKorrEbene.inkasso,
              parentId: _vorfallId,
              farbe: Colors.purple,
            ),
            const VermieterVollmachtPlatzhalter(bezug: 'das Inkassobüro'),
            VermieterMahnverfahren(
              apiService: widget.apiService,
              vorfallId: _vorfallId,
            ),
            VermieterWiderspruch(
              apiService: widget.apiService,
              vorfallId: _vorfallId,
              inkassoName: widget.inkassoName,
              // Das erste Aktenzeichen des Vorfalls reicht für den
              // Briefkopf; laufen mehrere, steht das übrige im Text.
              aktenzeichen: _akten.isEmpty
                  ? null
                  : _akten.first['aktenzeichen']?.toString(),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Die Kopfdaten des Vorfalls und darunter seine Aktenzeichen.
  ///
  /// ⚠️ Die Aktenzeichen stehen hier und nicht in einem eigenen Reiter:
  /// sie SIND ein Teil der Angaben zum Vorgang — unter welchen Nummern er
  /// beim Büro läuft. Ein eigener Reiter dafür hätte fünf ergeben, und
  /// die Nummer allein sagt nichts ohne den Vorgang daneben.
  Widget _detailsMitAktenzeichen(Map<String, dynamic> v) {
    return Column(children: [
      if ((v['grund']?.toString() ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(v['grund'].toString(),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Text('Aktenzeichen (${_akten.length})',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: Colors.purple.shade800),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _bearbeiten(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: !_geladen
            ? const Center(child: CircularProgressIndicator())
            : _fehler != null
                ? LadeFehler(meldung: _fehler!, onErneut: _laden)
                : _akten.isEmpty
                    ? Center(
                        child: Text('Noch kein Aktenzeichen zu diesem Vorfall',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade500)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _akten.length,
                        itemBuilder: (_, i) {
                          final a = _akten[i];
                          final frist = a['naechste_frist']?.toString() ?? '';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () => _oeffnen(a),
                              leading: CircleAvatar(
                                backgroundColor:
                                    (_kStatusFarben[a['status']] ?? Colors.grey).shade50,
                                child: Icon(Icons.description,
                                    size: 20,
                                    color: (_kStatusFarben[a['status']] ?? Colors.grey).shade700),
                              ),
                              title: Text(a['aktenzeichen']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((a['bezeichnung']?.toString() ?? '').isNotEmpty)
                                    Text(a['bezeichnung'].toString(),
                                        style: const TextStyle(fontSize: 11)),
                                  if ((a['forderung_brutto']?.toString() ?? '').isNotEmpty)
                                    Text('${a['forderung_brutto']} €'
                                        '${(a['gezahlt']?.toString() ?? '').isNotEmpty ? ' · gezahlt ${a['gezahlt']} €' : ''}',
                                        style: const TextStyle(fontSize: 11)),
                                  if (frist.isNotEmpty)
                                    Text('Nächste Frist: ${_datumDeutsch(frist)}',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.red.shade400,
                                            fontWeight: FontWeight.w600)),
                                ],
                              ),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                _statusChip(a['status']?.toString()),
                                IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      size: 18, color: Colors.red.shade300),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Aktenzeichen löschen?'),
                                        content: const Text(
                                            'Die Akteneinsicht-Dokumente dieses Aktenzeichens '
                                            'werden mit entfernt. Der Schriftverkehr bleibt — '
                                            'er gehört zum Vorfall, nicht zur Nummer.'),
                                        actions: [
                                          TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text('Abbrechen')),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Löschen',
                                                style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    await widget.apiService
                                        .deleteVermieterAktenzeichen(a['id'] as int);
                                    _laden();
                                  },
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

// ══════════════════════════════════════════════════════════════════════
// Ein Aktenzeichen: Details · Korrespondenz · Vollmacht · Akteneinsicht
// ══════════════════════════════════════════════════════════════════════

class VermieterAktenzeichenDetail extends StatelessWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> aktenzeichen;
  final VoidCallback onBearbeiten;

  const VermieterAktenzeichenDetail({
    super.key,
    required this.apiService,
    required this.userId,
    required this.aktenzeichen,
    required this.onBearbeiten,
  });

  @override
  Widget build(BuildContext context) {
    final a = aktenzeichen;
    final id = a['id'] as int;
    // ⚠️ Nur noch zwei Reiter: Korrespondenz und Vollmacht sind am
    // 20.08.2026 an den VORFALL gewandert. Ein Vorgang läuft oft unter
    // mehreren Aktenzeichen — die Briefe dazu sind dieselbe Unterhaltung
    // und dürfen nicht auf die Nummern verteilt liegen.
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          color: Colors.purple.shade50,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['aktenzeichen']?.toString() ?? '',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple.shade900)),
                if ((a['bezeichnung']?.toString() ?? '').isNotEmpty)
                  Text(a['bezeichnung'].toString(), style: const TextStyle(fontSize: 11.5)),
              ]),
            ),
            _statusChip(a['status']?.toString()),
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 18, color: Colors.purple.shade400),
              tooltip: 'Bearbeiten',
              onPressed: onBearbeiten,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.purple.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.purple.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
            Tab(icon: Icon(Icons.fact_check, size: 18), text: 'Akteneinsicht'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _AktenzeichenDetails(aktenzeichen: a),
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: VermieterDokumente(
                apiService: apiService,
                userId: userId,
                typ: 'ink_akteneinsicht',
                parentId: id,
                farbe: Colors.purple,
                titel: 'Unterlagen aus der Akteneinsicht',
                hinweis: 'Hier liegen die Unterlagen, die beim Inkassobüro zu diesem '
                    'Aktenzeichen angefordert wurden — nicht die eigenen Schreiben. '
                    'Die stehen unter Korrespondenz.',
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _AktenzeichenDetails extends StatelessWidget {
  final Map<String, dynamic> aktenzeichen;
  const _AktenzeichenDetails({required this.aktenzeichen});

  @override
  Widget build(BuildContext context) {
    final a = aktenzeichen;
    final zeilen = <String, String>{
      'Aktenzeichen': a['aktenzeichen']?.toString() ?? '',
      'Bezeichnung': a['bezeichnung']?.toString() ?? '',
      'Status': _kStatusNamen[a['status']] ?? (a['status']?.toString() ?? ''),
      'Forderung': (a['forderung_brutto']?.toString() ?? '').isEmpty
          ? ''
          : '${a['forderung_brutto']} €',
      'Davon gezahlt': (a['gezahlt']?.toString() ?? '').isEmpty ? '' : '${a['gezahlt']} €',
      'Eröffnet am': _datumDeutsch(a['eroeffnet_am']),
      'Nächste Frist': _datumDeutsch(a['naechste_frist']),
      'Geschlossen am': _datumDeutsch(a['geschlossen_am']),
    };
    // Offener Rest nur zeigen, wenn beide Zahlen da sind — sonst stünde
    // eine ausgerechnete Forderung da, die auf einer Lücke beruht.
    final f = double.tryParse((a['forderung_brutto']?.toString() ?? '').replaceAll(',', '.'));
    final g = double.tryParse((a['gezahlt']?.toString() ?? '').replaceAll(',', '.'));
    if (f != null && g != null) {
      zeilen['Offener Rest'] = '${(f - g).toStringAsFixed(2)} €';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in zeilen.entries)
          if (e.value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 130,
                  child: Text(e.key, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                ),
                Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13))),
              ]),
            ),
        if ((a['notizen']?.toString() ?? '').isNotEmpty) ...[
          const Divider(height: 24),
          Text('Notizen', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(a['notizen'].toString(), style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ]),
    );
  }
}

/// Der Vollmacht-Tab steht, die Urkunde noch nicht.
///
/// ⚠️ Absichtlich kein Knopf, der ein PDF erzeugt: die Vollmacht gegenüber
/// einem Vermieter oder einem Inkassobüro ist rechtsgeschäftliche
/// Vertretung nach § 164 BGB — nicht die Bevollmächtigung im
/// Verwaltungsverfahren nach § 13 SGB X, aus der die vorhandenen Vorlagen
/// stammen. Der Wortlaut muss geschrieben und freigegeben werden. Eine
/// Urkunde mit dem falschen Text wäre schlimmer als gar keine: sie sieht
/// gültig aus und wird eingereicht.
class VermieterVollmachtPlatzhalter extends StatelessWidget {
  final String bezug;
  const VermieterVollmachtPlatzhalter({super.key, required this.bezug});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.assignment_ind_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          Text('Vollmacht für $bezug',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          SizedBox(
            width: 420,
            child: Text(
              'Die Ablage steht bereit, der Wortlaut der Urkunde ist noch nicht '
              'freigegeben. Eine Vollmacht gegenüber einem privaten Gegenüber ist '
              'rechtsgeschäftliche Vertretung (§ 164 BGB) und nicht dieselbe wie '
              'die gegenüber einer Behörde — deshalb wird hier nichts aus den '
              'vorhandenen Vorlagen erzeugt.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.45),
            ),
          ),
        ]),
      ),
    );
  }
}
