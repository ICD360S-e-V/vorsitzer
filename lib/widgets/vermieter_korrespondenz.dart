import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'vermieter_dokumente.dart';

/// Schriftverkehr im Vermieter-Modul — an zwei Stellen dasselbe Werkzeug,
/// aber getrennte Akten:
///
///   [VermieterKorrEbene.vermieter]  Briefe an und vom Vermieter selbst
///   [VermieterKorrEbene.inkasso]    Briefe an und vom Inkassobüro,
///                                   gebunden an EIN Aktenzeichen
///
/// ⚠️ Die beiden dürfen nie zusammenlaufen. Eine Mahnung des Inkassobüros
/// unter „Korrespondenz mit dem Vermieter" abgelegt sieht aus wie ein
/// Schreiben des Vermieters — und genau daran hängt, wer wem was schuldet
/// und wer überhaupt zur Forderung Stellung nehmen darf.
enum VermieterKorrEbene { vermieter, inkasso }

const _kMedien = <String, String>{
  'brief': 'Brief',
  'email': 'E-Mail',
  'fax': 'Fax',
  'telefon': 'Telefon',
  'online': 'Online-Portal',
  'sms': 'SMS',
  'sonstiges': 'Sonstiges',
};

class VermieterKorrespondenz extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final VermieterKorrEbene ebene;

  /// vermieter_id bei [VermieterKorrEbene.vermieter],
  /// aktenzeichen_id bei [VermieterKorrEbene.inkasso].
  final int parentId;

  final MaterialColor farbe;

  const VermieterKorrespondenz({
    super.key,
    required this.apiService,
    required this.userId,
    required this.ebene,
    required this.parentId,
    this.farbe = Colors.deepPurple,
  });

  @override
  State<VermieterKorrespondenz> createState() => _VermieterKorrespondenzState();
}

class _VermieterKorrespondenzState extends State<VermieterKorrespondenz> {
  List<Map<String, dynamic>> _items = [];
  bool _geladen = false;
  String? _fehler;

  bool get _istInkasso => widget.ebene == VermieterKorrEbene.inkasso;
  String get _docTyp => _istInkasso ? 'ink_korr' : 'v_korr';

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void didUpdateWidget(VermieterKorrespondenz alt) {
    super.didUpdateWidget(alt);
    if (alt.parentId != widget.parentId || alt.ebene != widget.ebene) _laden();
  }

  Future<void> _laden() async {
    try {
      final res = _istInkasso
          ? await widget.apiService.listVermieterInkassoKorrespondenz(widget.parentId)
          : await widget.apiService.listVermieterKorrespondenz(widget.userId, widget.parentId);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
        _fehler = null;
        _geladen = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _fehler = e.toString(); _geladen = true; });
    }
  }

  Future<void> _speichern(Map<String, dynamic> daten) async {
    final res = _istInkasso
        ? await widget.apiService.saveVermieterInkassoKorrespondenz(widget.parentId, daten)
        : await widget.apiService.saveVermieterKorrespondenz(widget.userId, widget.parentId, daten);
    if (!mounted) return;
    if (res['success'] != true) {
      // Der Grund gehört auf den Bildschirm. Ohne ihn ist „abgelehnt"
      // von „danebengetippt" nicht zu unterscheiden.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    _laden();
  }

  Future<void> _loeschen(Map<String, dynamic> k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text('Der Eintrag und seine Anhänge werden endgültig entfernt.'),
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
    final id = k['id'] as int;
    final res = _istInkasso
        ? await widget.apiService.deleteVermieterInkassoKorrespondenz(id)
        : await widget.apiService.deleteVermieterKorrespondenz(widget.userId, id);
    if (res['success'] == true) {
      _laden();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nicht gelöscht: ${res['message'] ?? 'unbekannter Grund'}'),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _bearbeiten([Map<String, dynamic>? k]) {
    final istNeu = k == null;
    final betreffC = TextEditingController(text: k?['betreff']?.toString() ?? '');
    final textC = TextEditingController(text: k?['text']?.toString() ?? '');
    final notizC = TextEditingController(text: k?['notizen']?.toString() ?? '');
    final datumC = TextEditingController(
      text: k?['datum']?.toString() ?? DateTime.now().toIso8601String().substring(0, 10),
    );
    String richtung = k?['richtung']?.toString() ?? 'eingehend';
    String medium = k?['medium']?.toString() ?? 'brief';
    bool erledigt = (int.tryParse(k?['erledigt']?.toString() ?? '0') ?? 0) == 1;
    final c = widget.farbe;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Text(istNeu ? 'Neuer Schriftverkehr' : 'Schriftverkehr bearbeiten',
            style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                for (final r in const ['eingehend', 'ausgehend']) ...[
                  ChoiceChip(
                    label: Text(r == 'eingehend' ? 'Eingehend' : 'Ausgehend',
                        style: const TextStyle(fontSize: 11)),
                    selected: richtung == r,
                    onSelected: (_) => setDlg(() => richtung = r),
                  ),
                  const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: datumC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Datum',
                      isDense: true,
                      prefixIcon: const Icon(Icons.calendar_today, size: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onTap: () async {
                      final jetzt = DateTime.tryParse(datumC.text) ?? DateTime.now();
                      final d = await showDatePicker(
                        context: ctx2,
                        initialDate: jetzt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2040),
                        locale: const Locale('de'),
                      );
                      // Das Feld geht an den Server, deshalb ISO. Angezeigt
                      // wird in der Liste deutsch.
                      if (d != null) setDlg(() => datumC.text = d.toIso8601String().substring(0, 10));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: medium,
                    decoration: InputDecoration(
                      labelText: 'Weg',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: _kMedien.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setDlg(() => medium = v ?? medium),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: betreffC,
                decoration: InputDecoration(
                  labelText: 'Betreff',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: textC,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Inhalt',
                  alignLabelWithHint: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notizC,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Interne Notiz',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: erledigt,
                onChanged: (v) => setDlg(() => erledigt = v ?? false),
                title: const Text('Erledigt', style: TextStyle(fontSize: 12.5)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _speichern({
                if (!istNeu) 'id': k['id'],
                'datum': datumC.text,
                'richtung': richtung,
                'medium': medium,
                'erledigt': erledigt ? 1 : 0,
                'betreff': betreffC.text.trim(),
                'text': textC.text.trim(),
                'notizen': notizC.text.trim(),
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white),
            child: Text(istNeu ? 'Anlegen' : 'Speichern'),
          ),
        ],
      )),
    );
  }

  String _datumDeutsch(Object? iso) {
    final s = iso?.toString() ?? '';
    if (s.length < 10) return s;
    return '${s.substring(8, 10)}.${s.substring(5, 7)}.${s.substring(0, 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.farbe;
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    if (_fehler != null) return LadeFehler(meldung: _fehler!, onErneut: _laden);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        // ⚠️ Expanded statt Spacer: die Überschrift ist lang, und ein
        // unbeschränkter Text in einer Row nimmt sich seine volle
        // natürliche Breite — gemessen 226 px Überlauf auf einem 411-dp-
        // Telefon. So bricht sie stattdessen um.
        child: Row(children: [
          Expanded(
            child: Text(
              _istInkasso
                  ? 'Schriftverkehr mit dem Inkassobüro (${_items.length})'
                  : 'Schriftverkehr mit dem Vermieter (${_items.length})',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c.shade800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _bearbeiten(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: _items.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Noch kein Schriftverkehr erfasst',
                      style: TextStyle(color: Colors.grey.shade500)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final k = _items[i];
                  final eingehend = (k['richtung']?.toString() ?? 'eingehend') == 'eingehend';
                  final erledigt = (int.tryParse(k['erledigt']?.toString() ?? '0') ?? 0) == 1;
                  final betreff = (k['betreff']?.toString() ?? '').trim();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: eingehend ? Colors.blue.shade50 : c.shade50,
                        child: Icon(
                          eingehend ? Icons.call_received : Icons.call_made,
                          size: 18,
                          color: eingehend ? Colors.blue.shade700 : c.shade700,
                        ),
                      ),
                      title: Text(
                        betreff.isEmpty ? '(ohne Betreff)' : betreff,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: betreff.isEmpty ? Colors.grey : null,
                        ),
                      ),
                      subtitle: Text(
                        '${_datumDeutsch(k['datum'])} · ${_kMedien[k['medium']] ?? k['medium']}'
                        '${erledigt ? ' · erledigt' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (erledigt)
                          Icon(Icons.check_circle, size: 18, color: Colors.green.shade400),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: 18, color: c.shade300),
                          onPressed: () => _bearbeiten(k),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                          onPressed: () => _loeschen(k),
                        ),
                      ]),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        if ((k['text']?.toString() ?? '').isNotEmpty) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(k['text'].toString(),
                                style: const TextStyle(fontSize: 12.5, height: 1.4)),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if ((k['notizen']?.toString() ?? '').isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade100),
                            ),
                            child: Text('Notiz: ${k['notizen']}',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800)),
                          ),
                          const SizedBox(height: 10),
                        ],
                        VermieterDokumente(
                          apiService: widget.apiService,
                          userId: widget.userId,
                          typ: _docTyp,
                          parentId: k['id'] as int,
                          farbe: c,
                          titel: 'Anhänge',
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
