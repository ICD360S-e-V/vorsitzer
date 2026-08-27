import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';
import 'bussgeld_vorfall_details_dialog.dart';
import 'bussgeld_vorfall_dialog.dart';

/// Der Vorgangs-Manager einer Bußgeldstelle.
///
/// ⚠️ Ein eigener Bildschirm, kein Anhängsel unter der Karte. Die Vorgänge
/// einer Stelle sind eine Akte: man sucht darin, filtert nach dem, was noch
/// offen ist, und arbeitet sie ab. Unter einer Karte gequetscht wächst diese
/// Liste mit jedem Schreiben weiter, bis die Anschrift der Stelle — der
/// eigentliche Inhalt der Karte — nach unten aus dem Bild wandert.
class BussgeldVorgaengeManager extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  /// Die zuständige Stelle, wie `user_bussgeldstelle.php` sie liefert.
  final Map<String, dynamic>? stelle;

  /// Die Vorgänge beim Öffnen; der Manager lädt danach selbst nach.
  final List<Map<String, dynamic>> vorfaelle;

  const BussgeldVorgaengeManager({
    super.key,
    required this.apiService,
    required this.userId,
    required this.stelle,
    required this.vorfaelle,
  });

  @override
  State<BussgeldVorgaengeManager> createState() => _BussgeldVorgaengeManagerState();
}

/// Wonach sich die Liste einschränken lässt.
enum _Filter { alle, offen, frist, erledigt, andere }

class _BussgeldVorgaengeManagerState extends State<BussgeldVorgaengeManager> {
  late List<Map<String, dynamic>> _alle;
  final _suche = TextEditingController();
  _Filter _filter = _Filter.alle;
  bool _laedt = false;

  /// Zustände, die als abgeschlossen gelten.
  static const _fertig = {'bezahlt', 'rechtskraeftig', 'eingestellt', 'abgeschlossen'};

  @override
  void initState() {
    super.initState();
    _alle = List<Map<String, dynamic>>.from(widget.vorfaelle);
  }

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    setState(() => _laedt = true);
    final r = await widget.apiService.getUserBussgeldstelle(widget.userId);
    if (!mounted) return;
    setState(() {
      _laedt = false;
      if (r['vorfaelle'] is List) {
        _alle = List<Map<String, dynamic>>.from(
            (r['vorfaelle'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
    });
  }

  /// Gehört dieser Vorgang zur Stelle, die gerade als zuständig gilt?
  ///
  /// ⚠️ Jeder Vorgang trägt die Stelle, bei der er angelegt wurde
  /// (`stelle_id`, bei Freitext `stelle_name`). Der Manager einer Stelle
  /// zeigt darum ihre Vorgänge.
  ///
  /// ⚠️ Was zu einer ANDEREN Stelle gehört, wird deshalb aber nicht
  /// versteckt: es bekommt einen eigenen Filter mit sichtbarer Zahl. Wer die
  /// zuständige Stelle wechselt, verlöre sonst den Zugang zu allem, was
  /// vorher lief — unerreichbare Daten sind schlimmer als eine Zeile zu viel.
  bool _gehoertZurStelle(Map<String, dynamic> v) {
    final s = widget.stelle;
    if (s == null) return true;
    final sId = s['stelle_id'];
    final vId = v['stelle_id'];
    if (sId != null && vId != null) return '\$sId' == '\$vId';
    // Freitext-Stellen haben keine id — dann entscheidet der Name.
    final sName = (s['stelle_name']?.toString() ?? '').trim();
    final vName = (v['stelle_name']?.toString() ?? '').trim();
    if (sName.isEmpty || vName.isEmpty) return sId == null && vId == null;
    return sName == vName;
  }

  bool _istOffen(Map<String, dynamic> v) => !_fertig.contains(v['status']);

  /// ⚠️ „Frist läuft" heißt: sie läuft NOCH und der Vorgang ist offen. Ein
  /// bezahlter Bescheid mit abgelaufener Frist gehört nicht in diesen Filter —
  /// sonst steht dauerhaft eine rote Zahl da, die niemand mehr wegbekommt.
  bool _fristLaeuft(Map<String, dynamic> v) {
    if (!_istOffen(v)) return false;
    final t = v['tage_bis_frist'];
    return t is int && t <= 7;
  }

  List<Map<String, dynamic>> get _gefiltert {
    final q = _suche.text.trim().toLowerCase();
    return _alle.where((v) {
      // Vorgänge anderer Stellen erscheinen nur in ihrem eigenen Filter.
      final eigen = _gehoertZurStelle(v);
      if (_filter == _Filter.andere) {
        if (eigen) return false;
      } else if (!eigen) {
        return false;
      }
      switch (_filter) {
        case _Filter.offen:
          if (!_istOffen(v)) return false;
        case _Filter.frist:
          if (!_fristLaeuft(v)) return false;
        case _Filter.erledigt:
          if (_istOffen(v)) return false;
        case _Filter.alle:
        case _Filter.andere:
          break;
      }
      if (q.isEmpty) return true;
      // Gesucht wird in dem, was auf dem Schreiben steht.
      for (final f in ['aktenzeichen', 'vorwurf', 'tatort_ort', 'kennzeichen', 'stelle_name']) {
        if ((v[f]?.toString().toLowerCase() ?? '').contains(q)) return true;
      }
      return false;
    }).toList();
  }

  Iterable<Map<String, dynamic>> get _eigene => _alle.where(_gehoertZurStelle);
  int get _anzahlEigen  => _eigene.length;
  int get _anzahlOffen  => _eigene.where(_istOffen).length;
  int get _anzahlFrist  => _eigene.where(_fristLaeuft).length;
  int get _anzahlAndere => _alle.length - _anzahlEigen;

  int? get _stelleId {
    final r = widget.stelle?['stelle_id'];
    return r is int ? r : int.tryParse(r?.toString() ?? '');
  }

  /// Der "+"-Weg: nur das Aktenzeichen, dann steht der Vorgang.
  ///
  /// ⚠️ Bewusst NICHT das große Formular. Wer ein Schreiben in der Hand hält,
  /// hat als erstes das Aktenzeichen — Beträge, Tatort und Punktestand stehen
  /// weiter unten auf dem Blatt und können warten. Ein Formular mit zwanzig
  /// Feldern am Anfang führt dazu, dass der Vorgang gar nicht erst angelegt
  /// wird.
  ///
  /// ⚠️ Die Stelle kommt aus der Zuständigkeit, nicht aus einer Auswahl:
  /// jeder Vorgang gehört zu der Behörde, bei der er angelegt wurde.
  Future<void> _schnellAnlegen() async {
    if (widget.stelle == null || (widget.stelle!['stelle_name']?.toString().isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erst eine zuständige Bußgeldstelle hinterlegen — '
                      'ein Vorgang gehört immer zu einer Behörde.')));
      return;
    }
    final az = TextEditingController();
    String art = 'bussgeldbescheid';
    DateTime? zugang = DateTime.now();
    DateTime? bescheid;

    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) {
        Widget dat(String label, DateTime? wert, ValueChanged<DateTime?> setzen, {String? hilfe}) => InkWell(
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: wert ?? DateTime.now(),
                    firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) ss(() => setzen(d));
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder(), isDense: true, helperText: hilfe,
                  suffixIcon: wert == null ? const Icon(Icons.calendar_today, size: 16)
                      : IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => ss(() => setzen(null))),
                ),
                child: Text(wert == null ? '\u2014' : _datum(_iso(wert))!),
              ),
            );
        return AlertDialog(
          title: Row(children: [
            Icon(Icons.gavel, color: F.h(Colors.deepOrange, 700)),
            const SizedBox(width: 8),
            const Expanded(child: Text('Aktenzeichen erfassen')),
          ]),
          content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Icon(Icons.account_balance, size: 15, color: F.h(Colors.grey, 600)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(widget.stelle!['stelle_name'].toString(),
                      style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
                ])),
            TextField(
              key: const Key('bg_schnell_az'),
              controller: az,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Aktenzeichen *', border: OutlineInputBorder(), isDense: true,
                hintText: 'genau wie auf dem Schreiben'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: art,
              decoration: const InputDecoration(labelText: 'Art des Schreibens',
                  border: OutlineInputBorder(), isDense: true),
              items: [for (final e in kBussgeldArten.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => ss(() => art = v ?? art),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: dat('Datum des Schreibens', bescheid, (d) => bescheid = d)),
              const SizedBox(width: 10),
              Expanded(child: dat('Zugegangen am', zugang, (d) => zugang = d, hilfe: 'Fristbeginn')),
            ]),
            const SizedBox(height: 6),
            Text('Alles Weitere \u2014 Vorwurf, Betr\u00E4ge, Tatort \u2014 l\u00E4sst sich danach im Vorgang erg\u00E4nzen.',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
              child: const Text('Anlegen und \u00F6ffnen'),
            ),
          ],
        );
      },
    ));
    if (ok != true) return;
    if (az.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ohne Aktenzeichen findet die Beh\u00F6rde den Vorgang nicht \u2014 bitte eintragen.')));
      }
      return;
    }

    setState(() => _laedt = true);
    final r = await widget.apiService.saveBussgeldVorfall(widget.userId, {
      'stelle_id': _stelleId,
      'stelle_name': widget.stelle!['stelle_name'],
      'art': art,
      'aktenzeichen': az.text.trim(),
      'bescheid_datum': bescheid == null ? null : _iso(bescheid!),
      'zugang_datum': zugang == null ? null : _iso(zugang!),
    });
    if (!mounted) return;
    setState(() => _laedt = false);
    if (r['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nicht angelegt: ${r['message'] ?? 'unbekannter Fehler'}'),
        backgroundColor: F.h(Colors.red, 700)));
      return;
    }
    await _laden();
    if (!mounted) return;
    // Direkt in den Vorgang: dort stehen Details, Korrespondenz,
    // Widerspruch und Vollmacht.
    await _oeffnen({'id': r['id']});
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _oeffnen(Map<String, dynamic> v) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => BussgeldVorfallDetailsDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        vorfallId: v['id'] as int,
      ),
    );
    if (mounted) await _laden();
  }

  Future<void> _loeschen(Map<String, dynamic> v) async {
    final sicher = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Vorgang löschen?'),
      content: Text('„${v['aktenzeichen'] ?? 'ohne Aktenzeichen'}" wird endgültig entfernt — '
          'mit Schriftverkehr, Unterlagen, Einspruch und Vollmachten.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
      ],
    ));
    if (sicher != true) return;
    final r = await widget.apiService.deleteBussgeldVorfall(widget.userId, v['id'] as int);
    if (!mounted) return;
    if (r['success'] == true) {
      await _laden();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nicht gelöscht: ${r['message'] ?? 'unbekannter Fehler'}'),
        backgroundColor: F.h(Colors.red, 700)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste = _gefiltert;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 780,
        height: 660,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            color: F.h(Colors.deepOrange, 700),
            child: Row(children: [
              const Icon(Icons.folder_shared, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Vorgänge',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(widget.stelle?['stelle_name']?.toString() ?? 'ohne zuständige Stelle',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ])),
              if (_laedt) const Padding(padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context, true)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Expanded(child: TextField(
                key: const Key('bg_mgr_suche'),
                controller: _suche,
                decoration: InputDecoration(
                  hintText: 'Aktenzeichen, Vorwurf, Ort oder Kennzeichen',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _suche.text.isEmpty ? null : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _suche.clear()),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              )),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                key: const Key('bg_mgr_neu'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Aktenzeichen'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
                onPressed: _schnellAnlegen,
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _chip('Alle', _anzahlEigen, _Filter.alle, Colors.blueGrey),
              const SizedBox(width: 6),
              _chip('Offen', _anzahlOffen, _Filter.offen, Colors.blue),
              const SizedBox(width: 6),
              _chip('Frist läuft', _anzahlFrist, _Filter.frist, Colors.orange),
              const SizedBox(width: 6),
              _chip('Erledigt', _anzahlEigen - _anzahlOffen, _Filter.erledigt, Colors.green),
              // ⚠️ Nur sichtbar, wenn es welche gibt — sonst stünde dauerhaft
              // eine Null da, die nach einem Fehler aussieht.
              if (_anzahlAndere > 0) ...[
                const SizedBox(width: 6),
                _chip('Andere Stelle', _anzahlAndere, _Filter.andere, Colors.purple),
              ],
            ]),
          ),
          const Divider(height: 20),
          Expanded(child: liste.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_anzahlEigen == 0 && _filter != _Filter.andere
                        ? Icons.inbox : Icons.search_off,
                        size: 44, color: F.h(Colors.grey, 400)),
                    const SizedBox(height: 10),
                    Text(_anzahlEigen == 0 && _filter != _Filter.andere
                        ? 'Noch kein Aktenzeichen für diese Stelle'
                        : 'Kein Treffer',
                        style: TextStyle(color: F.h(Colors.grey, 700))),
                    const SizedBox(height: 4),
                    Text(_anzahlEigen == 0 && _filter != _Filter.andere
                        ? 'Über „Aktenzeichen" ein Schreiben dieser Stelle eintragen — '
                          'die Frist wird dann aus dem Zugangsdatum mitgerechnet.'
                        : 'Andere Suche oder anderen Filter versuchen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 500))),
                  ])))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: liste.length,
                  itemBuilder: (_, i) => _zeile(liste[i]),
                )),
        ]),
      ),
    );
  }

  Widget _chip(String text, int n, _Filter f, MaterialColor farbe) {
    final aktiv = _filter == f;
    return Expanded(child: InkWell(
      onTap: () => setState(() => _filter = f),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: aktiv ? F.h(farbe, 100) : F.h(Colors.grey, 100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: aktiv ? F.h(farbe, 400) : F.h(Colors.grey, 300)),
        ),
        child: Column(children: [
          Text('$n', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
              color: aktiv ? F.h(farbe, 800) : F.h(Colors.grey, 700))),
          Text(text, style: TextStyle(fontSize: 11,
              color: aktiv ? F.h(farbe, 800) : F.h(Colors.grey, 600))),
        ]),
      ),
    ));
  }

  Widget _zeile(Map<String, dynamic> v) {
    final tage = v['tage_bis_frist'];
    final offen = _istOffen(v);
    final abgelaufen = offen && tage is int && tage < 0;
    final knapp = offen && tage is int && tage >= 0 && tage <= 3;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          abgelaufen ? Icons.error_outline : offen ? Icons.description_outlined : Icons.check_circle_outline,
          color: abgelaufen ? F.h(Colors.red, 700)
               : knapp ? F.h(Colors.orange, 800)
               : offen ? F.h(Colors.grey, 600) : F.h(Colors.green, 700),
        ),
        title: Text(
          '${kBussgeldArten[v['art']] ?? v['art']} · ${v['aktenzeichen'] ?? 'ohne Aktenzeichen'}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (v['vorwurf'] != null) Text(v['vorwurf'].toString(),
              style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Wrap(spacing: 12, runSpacing: 2, children: [
            if (v['zugang_datum'] != null)
              Text('zugegangen ${_datum(v['zugang_datum'])}', style: const TextStyle(fontSize: 11)),
            if (v['frist_bis'] != null)
              Text(
                abgelaufen ? 'Frist abgelaufen ${_datum(v['frist_bis'])}'
                           : 'Frist ${_datum(v['frist_bis'])}${tage is int && offen ? ' (noch $tage T.)' : ''}',
                style: TextStyle(fontSize: 11,
                    color: abgelaufen ? F.h(Colors.red, 700) : knapp ? F.h(Colors.orange, 800) : null,
                    fontWeight: (abgelaufen || knapp) ? FontWeight.bold : null)),
            if (v['betrag_gesamt'] != null)
              Text('${_euro(v['betrag_gesamt'])} €', style: const TextStyle(fontSize: 11)),
            Text(kBussgeldStatus[v['status']] ?? v['status'].toString(),
                style: TextStyle(fontSize: 11, color: F.h(Colors.blue, 700))),
            // Damit im Filter „Andere Stelle" zu sehen ist, WELCHE das war.
            if (!_gehoertZurStelle(v) && v['stelle_name'] != null)
              Text(v['stelle_name'].toString(),
                  style: TextStyle(fontSize: 11, color: F.h(Colors.purple, 700))),
          ]),
        ]),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          color: F.h(Colors.red, 600),
          tooltip: 'Vorgang löschen',
          onPressed: () => _loeschen(v),
        ),
        onTap: () => _oeffnen(v),
      ),
    );
  }

  static String? _datum(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    if (d == null) return iso?.toString();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  static String _euro(dynamic v) {
    final d = double.tryParse(v?.toString() ?? '');
    return d == null ? (v?.toString() ?? '') : d.toStringAsFixed(2).replaceAll('.', ',');
  }
}
