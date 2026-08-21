import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';
import '../utils/app_farben.dart';

/// Anhänge im Vermieter-Modul. Vier Ablagen, ein Widget — die Ablage
/// steckt allein im [typ]:
///
///   v_korr            Anhang einer Korrespondenz mit dem Vermieter
///   v_akteneinsicht   Unterlagen aus der Akteneinsicht beim Vermieter
///   ink_korr          Anhang einer Korrespondenz mit dem Inkassobüro
///   ink_akteneinsicht Unterlagen aus der Akteneinsicht beim Inkassobüro
///   ws_dokument       Der eigene Widerspruch, sein Sendebericht, die Antwort
///
/// ⚠️ Die vier Namen stehen ebenso im Server (`vermieter_docs_upload.php`
/// und `_download.php`). Ein fünfter Typ muss an beiden Enden entstehen,
/// sonst antwortet der Upload mit „type unbekannt" und der Bildschirm
/// zeigt nur, dass nichts passiert ist.
const kVermieterDocTypen = <String>{
  'v_korr',
  'v_akteneinsicht',
  'ink_korr',
  'ink_akteneinsicht',
  'ws_dokument',
};

class VermieterDokumente extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  /// Einer der vier Werte aus [kVermieterDocTypen].
  final String typ;

  /// korr_id · vermieter_id · korr_id · aktenzeichen_id — je nach [typ].
  final int parentId;

  final MaterialColor farbe;
  final String titel;

  /// Erklärt, was in diese Ablage gehört. Ohne das ist zwischen den
  /// beiden Akteneinsicht-Ablagen von außen kein Unterschied zu sehen.
  final String? hinweis;

  final VoidCallback? onChanged;

  const VermieterDokumente({
    super.key,
    required this.apiService,
    required this.userId,
    required this.typ,
    required this.parentId,
    this.farbe = Colors.deepPurple,
    this.titel = 'Dokumente',
    this.hinweis,
    this.onChanged,
  });

  @override
  State<VermieterDokumente> createState() => _VermieterDokumenteState();
}

class _VermieterDokumenteState extends State<VermieterDokumente> {
  List<Map<String, dynamic>> _items = [];
  bool _geladen = false;
  String? _fehler;
  bool _laedtHoch = false;
  int _fertig = 0;
  int _gesamt = 0;

  /// Die beiden Inkasso-Ablagen liegen hinter einem eigenen Endpunkt.
  bool get _istInkasso => widget.typ.startsWith('ink_');

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void didUpdateWidget(VermieterDokumente alt) {
    super.didUpdateWidget(alt);
    // Wird dasselbe Widget für einen anderen Vorgang wiederverwendet,
    // stünde sonst die Liste des vorigen darin.
    if (alt.parentId != widget.parentId || alt.typ != widget.typ) _laden();
  }

  Future<void> _laden() async {
    Map<String, dynamic> res;
    try {
    switch (widget.typ) {
      case 'v_korr':
        res = await widget.apiService.listVermieterKorrDocs(widget.userId, widget.parentId);
      case 'v_akteneinsicht':
        res = await widget.apiService.listVermieterAkteneinsichtDocs(widget.userId, widget.parentId);
      case 'ink_korr':
        res = await widget.apiService.listVermieterInkassoKorrDocs(widget.parentId);
      case 'ws_dokument':
        res = await widget.apiService.listVermieterWiderspruchDocs(widget.parentId);
      default:
        res = await widget.apiService.listVermieterInkassoAkteneinsichtDocs(widget.parentId);
    }
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _fehler = null;
      _geladen = true;
    });
    } catch (e) {
      // ⚠️ Ohne diesen Zweig bliebe `_geladen` für immer false und die
      // Ladeanzeige drehte sich endlos — auf dem Telefon ohne Empfang ein
      // toter Bildschirm ohne ein Wort dazu.
      if (!mounted) return;
      setState(() { _fehler = e.toString(); _geladen = true; });
    }
  }

  Future<void> _hochladen() async {
    final r = await FilePickerHelper.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'odt', 'txt', 'eml'],
    );
    if (r == null || r.files.isEmpty) return;
    var dateien = r.files.where((f) => f.path != null).toList();
    if (!mounted) return;
    final melder = ScaffoldMessenger.of(context);
    if (dateien.length > 20) {
      melder.showSnackBar(SnackBar(
        content: Text('Max. 20 Dateien — ${dateien.length - 20} ausgelassen'),
        backgroundColor: Colors.orange,
      ));
      dateien = dateien.sublist(0, 20);
    }
    setState(() {
      _laedtHoch = true;
      _fertig = 0;
      _gesamt = dateien.length;
    });
    final fehler = <String>[];
    for (final f in dateien) {
      final res = await widget.apiService.uploadVermieterDoc(
        type: widget.typ,
        parentId: widget.parentId,
        filePath: f.path!,
        fileName: f.name,
      );
      if (res['success'] == true) {
        _fertig++;
      } else {
        fehler.add('${f.name}: ${res['message'] ?? '?'}');
      }
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    setState(() => _laedtHoch = false);
    melder.showSnackBar(SnackBar(
      content: Text(fehler.isEmpty
          ? '$_fertig/$_gesamt Datei(en) hochgeladen'
          : '$_fertig OK, ${fehler.length} fehlgeschlagen:\n${fehler.join("\n")}'),
      backgroundColor: fehler.isEmpty ? Colors.green : Colors.orange,
      duration: const Duration(seconds: 4),
    ));
    widget.onChanged?.call();
    _laden();
  }

  Future<void> _loeschen(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Datei löschen?'),
        content: const Text('Die Datei wird endgültig entfernt.'),
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
    final res = widget.typ == 'ws_dokument'
        ? await widget.apiService.deleteVermieterWiderspruchDoc(id)
        : _istInkasso
        ? (widget.typ == 'ink_korr'
            ? await widget.apiService.deleteVermieterInkassoKorrDoc(id)
            : await widget.apiService.deleteVermieterInkassoAkteneinsichtDoc(id))
        : (widget.typ == 'v_korr'
            ? await widget.apiService.deleteVermieterKorrDoc(widget.userId, id)
            : await widget.apiService.deleteVermieterAkteneinsichtDoc(widget.userId, id));
    if (res['success'] == true) {
      widget.onChanged?.call();
      _laden();
    } else if (mounted) {
      // Ein stilles Nichts ist von „gelöscht" nicht zu unterscheiden.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nicht gelöscht: ${res['message'] ?? 'unbekannter Grund'}'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _oeffnen(Map<String, dynamic> d, {bool speichern = false}) async {
    try {
      final resp = await widget.apiService.downloadVermieterDoc(
        type: widget.typ,
        id: d['id'] as int,
      );
      if (resp.statusCode != 200 || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Konnte nicht geladen werden (HTTP ${resp.statusCode})'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
      final name = (d['datei_name']?.toString() ?? 'dokument_${d['id']}')
          .replaceAll(RegExp(r'[<>:"|?*\\/]'), '_');
      if (speichern) {
        final ziel = await FilePickerHelper.saveBytes(
          bytes: resp.bodyBytes,
          fileName: name,
          dialogTitle: 'Dokument speichern',
        );
        if (ziel == null || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gespeichert: $ziel'), backgroundColor: Colors.green),
        );
      } else if (mounted) {
        await FileViewerDialog.showFromBytes(context, resp.bodyBytes, name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _groesse(Object? bytes) {
    final b = int.tryParse(bytes?.toString() ?? '') ?? 0;
    if (b <= 0) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  IconData _symbol(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png')) return Icons.image;
    if (n.endsWith('.eml')) return Icons.mail_outline;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.farbe;
    if (!_geladen) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_fehler != null) return LadeFehler(meldung: _fehler!, onErneut: _laden);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Icon(Icons.folder_open, size: 16, color: F.h(c, 700)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${widget.titel} (${_items.length})',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(c, 800))),
          ),
          ElevatedButton.icon(
            onPressed: _laedtHoch ? null : _hochladen,
            icon: _laedtHoch
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file, size: 14),
            label: Text(
              _laedtHoch ? (_gesamt > 0 ? '$_fertig / $_gesamt …' : 'Lädt…') : 'Hochladen',
              style: const TextStyle(fontSize: 11),
            ),
            style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white),
          ),
        ]),
        if (widget.hinweis != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: F.h(c, 50),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.shade100),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 15, color: c.shade400),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.hinweis!,
                    style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700), height: 1.35)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('Noch keine Dateien',
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500))),
            ),
          )
        else
          ..._items.map((d) {
            final name = d['datei_name']?.toString() ?? '';
            final notiz = d['notiz']?.toString() ?? '';
            final gr = _groesse(d['file_size']);
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                onTap: () => _oeffnen(d),
                leading: Icon(_symbol(name), color: c.shade400, size: 22),
                title: Text(name,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                subtitle: (gr.isEmpty && notiz.isEmpty)
                    ? null
                    : Text([if (gr.isNotEmpty) gr, if (notiz.isNotEmpty) notiz].join(' · '),
                        style: const TextStyle(fontSize: 10.5), maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: Icon(Icons.download, size: 18, color: c.shade300),
                    tooltip: 'Speichern unter…',
                    onPressed: () => _oeffnen(d, speichern: true),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                    tooltip: 'Löschen',
                    onPressed: () => _loeschen(d['id'] as int),
                  ),
                ]),
              ),
            );
          }),
      ],
    );
  }
}

/// Was statt der ewigen Ladeanzeige erscheint, wenn das Laden scheitert.
///
/// ⚠️ Der Anlass: keiner der fünf Lader im Vermieter-Modul hatte ein
/// try/catch. Schlug die Anfrage fehl — Telefon ohne Empfang genügt —,
/// blieb `_geladen` für immer false und der Bildschirm drehte still weiter.
/// Aufgefallen ist es, weil ein Test darauf zehn Minuten hängen blieb;
/// am Gerät hätte niemand gewusst, worauf er wartet.
class LadeFehler extends StatelessWidget {
  final String meldung;
  final VoidCallback onErneut;
  const LadeFehler({super.key, required this.meldung, required this.onErneut});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, size: 48, color: F.h(Colors.grey, 300)),
          const SizedBox(height: 12),
          Text('Konnte nicht geladen werden',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(meldung,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 500), height: 1.4)),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onErneut,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Erneut versuchen'),
          ),
        ]),
      ),
    );
  }
}

/// Breite für den Inhalt eines Dialogs.
///
/// ⚠️ Eine feste Breite in einem `AlertDialog` ist auf dem Telefon ein
/// Überlauf: 520 dp Inhalt passen nicht in 411 dp Bildschirm abzüglich
/// der Ränder, die der Dialog selbst schon nimmt. Flutter schneidet dann
/// rechts ab — und was abgeschnitten wird, sind die Knöpfe.
///
/// Deshalb nie mehr als da ist: der Wunsch, gedeckelt durch den Schirm.
double dialogBreite(BuildContext context, [double wunsch = 520]) {
  final da = MediaQuery.sizeOf(context).width - 80;
  return da < wunsch ? (da < 240 ? 240 : da) : wunsch;
}
