import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/clipboard_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/ticket_service.dart';
import '../models/user.dart';
import 'file_viewer_dialog.dart';
import 'lebenslauf.dart';
import '../utils/file_picker_helper.dart';

class ArbeitgeberBehoerdeContent extends StatefulWidget {
  final User user;
  final ApiService apiService;
  final List<Map<String, dynamic>> dbArbeitgeberListe;
  final TicketService? ticketService;
  final String? adminMitgliedernummer;

  const ArbeitgeberBehoerdeContent({
    super.key,
    required this.user,
    required this.apiService,
    required this.dbArbeitgeberListe,
    this.ticketService,
    this.adminMitgliedernummer,
  });

  @override
  State<ArbeitgeberBehoerdeContent> createState() => _ArbeitgeberBehoerdeContentState();
}

class _ArbeitgeberBehoerdeContentState extends State<ArbeitgeberBehoerdeContent> with TickerProviderStateMixin {
  Map<String, dynamic> _hausarztData = {};
  List<Map<String, dynamic>> _arbeitgeberFromDB = [];
  bool _dbLoaded = false;
  List<Map<String, dynamic>> _berufsbezeichnungen = [];
  String _selectedArbeitgeberId = '';
  late TabController _mainTabC;

  @override
  void initState() {
    super.initState();
    _mainTabC = TabController(length: 2, vsync: this);
    _loadHausarztData();
    _loadArbeitgeberFromDB();
    _loadBerufsbezeichnungen();
  }

  Future<void> _loadBerufsbezeichnungen() async {
    try {
      final result = await widget.apiService.getBerufsbezeichnungen();
      if (mounted && result['success'] == true && result['data'] != null) {
        setState(() => _berufsbezeichnungen = List<Map<String, dynamic>>.from(result['data']));
      }
    } catch (_) {}
  }

  Future<void> _loadArbeitgeberFromDB() async {
    try {
      final result = await widget.apiService.getBerufserfahrung(widget.user.id);
      if (mounted && result['success'] == true && result['data'] != null) {
        setState(() {
          _arbeitgeberFromDB = List<Map<String, dynamic>>.from(result['data']);
          _dbLoaded = true;
          // Convert DB fields to match existing widget format
          for (final ag in _arbeitgeberFromDB) {
            ag['position'] = ag['funktion'] ?? '';
            // Parse JSON fields
            if (ag['krankheit_meldungen'] is String) {
              try { ag['krankheit_meldungen'] = jsonDecode(ag['krankheit_meldungen']); } catch (_) {}
            }
            if (ag['lohnsteuerbescheinigungen'] is String) {
              try { ag['lohnsteuerbescheinigungen'] = jsonDecode(ag['lohnsteuerbescheinigungen']); } catch (_) {}
            }
            // Ensure aktuell is bool
            ag['aktuell'] = ag['aktuell'] == 1 || ag['aktuell'] == '1' || ag['aktuell'] == true;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _dbLoaded = true);
    }
  }

  Future<Map<String, dynamic>> _saveArbeitgeberToDB(Map<String, dynamic> ag) async {
    final data = Map<String, dynamic>.from(ag);
    data['funktion'] = data['position'] ?? data['funktion'] ?? '';
    data['aktuell'] = (data['aktuell'] == true || data['aktuell'] == 'true') ? 1 : 0;
    return await widget.apiService.saveBerufserfahrung(widget.user.id, data);
  }

  Future<void> _deleteArbeitgeberFromDB(int id) async {
    await widget.apiService.deleteBerufserfahrung(id, widget.user.id);
  }

  Future<void> _loadHausarztData() async {
    try {
      final result = await widget.apiService.getGesundheitData(widget.user.id, 'gesundheit_hausarzt');
      if (mounted) {
        setState(() {
          _hausarztData = (result['data'] != null) ? Map<String, dynamic>.from(result['data']) : {};
        });
      }
    } catch (_) {}
  }

  void _saveArbeitgeber(List<Map<String, dynamic>> arbeitgeber, String selectedArbeitgeberId) {
    // Save each entry to DB
    for (int i = 0; i < arbeitgeber.length; i++) {
      final ag = arbeitgeber[i];
      ag['sort_order'] = i;
      _saveArbeitgeberToDB(ag);
    }
    // DB is now the primary source — no more JSON blob sync
    setState(() {
      _arbeitgeberFromDB = List<Map<String, dynamic>>.from(arbeitgeber);
    });
  }

  /// Saves arbeitgeber data with the given list and selected ID
  void _saveWithData(List<Map<String, dynamic>> arbeitgeberListe, String selectedArbeitgeberId) {
    for (int i = 0; i < arbeitgeberListe.length; i++) {
      final ag = arbeitgeberListe[i];
      ag['sort_order'] = i;
      // Save ALL entries — PHP handles INSERT (id=0/null) vs UPDATE (id>0)
      _saveArbeitgeberToDB(ag).then((result) {
        // If this was a new entry (INSERT), store the returned ID so future
        // saves become UPDATEs instead of creating duplicates.
        if (ag['id'] == null && result['success'] == true && result['id'] != null) {
          ag['id'] = result['id'];
        }
      }).catchError((_) {});
    }
    // DB is now primary — no more JSON blob sync
    setState(() {
      _arbeitgeberFromDB = List<Map<String, dynamic>>.from(arbeitgeberListe);
    });
  }

  Widget _buildAgStandortCard(String label, Map<String, dynamic> ag, String prefix) {
    final strasse = ag['${prefix}_strasse'];
    final plz = ag['${prefix}_plz'];
    final ort = ag['${prefix}_ort'];
    final telefon = ag['${prefix}_telefon'];
    final email = ag['${prefix}_email'];
    final zeiten = ag['${prefix}_oeffnungszeiten'];
    if (strasse == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Expanded(child: Text('$strasse, $plz $ort', style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
          ]),
          if (telefon != null) ...[
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.phone, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(telefon, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ]),
          ],
          if (email != null) ...[
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.email, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(email, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ]),
          ],
          if (zeiten != null) ...[
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.access_time, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(child: Text(zeiten, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.indigo.shade400),
          const SizedBox(width: 6),
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo.shade700))),
        ],
      ),
    );
  }

  Widget _buildInfoField(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          SizedBox(width: 160, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
          Expanded(child: Text(value ?? '\u2013', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: value != null ? Colors.grey.shade800 : Colors.grey.shade400))),
        ],
      ),
    );
  }

  Widget _buildFristRow(String dauer, String frist) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(dauer, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
          Expanded(child: Text(frist, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700))),
        ],
      ),
    );
  }

  Widget _buildWarnField(String emoji, String label, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800))),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        ],
      ),
    );
  }

  void _showBerufserfahrungModal(BuildContext context, Map<String, dynamic> ag, int arbeitgeberIndex, {required List<Map<String, dynamic>> arbeitgeberListe, required String selectedArbeitgeberId}) {
    // If arbeitgeberIndex == -1 (from dropdown/fakeAg), find or create the entry in the list
    if (arbeitgeberIndex == -1) {
      final dbId = ag['arbeitgeber_db_id']?.toString();
      if (dbId != null) {
        final existingIdx = arbeitgeberListe.indexWhere((a) => a['arbeitgeber_db_id']?.toString() == dbId);
        if (existingIdx >= 0) {
          // Merge existing data into ag and use the existing entry
          final existing = arbeitgeberListe[existingIdx];
          for (final key in existing.keys) {
            if (!ag.containsKey(key) || ag[key] == null || ag[key] == '') {
              ag[key] = existing[key];
            }
          }
          arbeitgeberListe[existingIdx] = ag;
          arbeitgeberIndex = existingIdx;
        } else {
          // Add new entry to the list
          arbeitgeberListe.insert(0, ag);
          arbeitgeberIndex = 0;
        }
      }
    }
    final dokTypen = {
      'vertrag': ['arbeitsvertrag', 'vertragsaenderung'],
      'lohn': ['lohnabrechnung', 'lohnsteuerbescheinigung'],
      'krankheit': ['krankschreibung', 'urlaubsantrag'],
      'kuendigung': ['kuendigung', 'aufhebungsvertrag', 'arbeitszeugnis', 'abmahnung'],
      'sonstiges': ['sonstiges'],
    };
    final dokTypLabels = {
      'arbeitsvertrag': 'Arbeitsvertrag',
      'vertragsaenderung': 'Vertrags\u00E4nderung',
      'lohnabrechnung': 'Lohnabrechnung',
      'lohnsteuerbescheinigung': 'Lohnsteuerbescheinigung',
      'krankschreibung': 'Krankschreibung',
      'urlaubsantrag': 'Urlaubsantrag',
      'kuendigung': 'K\u00FCndigung',
      'aufhebungsvertrag': 'Aufhebungsvertrag',
      'arbeitszeugnis': 'Arbeitszeugnis',
      'abmahnung': 'Abmahnung',
      'sonstiges': 'Sonstiges',
    };

    showDialog(
      context: context,
      builder: (ctx) {
        List<Map<String, dynamic>> dokumente = [];
        bool docsLoading = true;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            // Load documents on first build
            if (docsLoading) {
              widget.apiService.getArbeitgeberDokumente(widget.user.id, arbeitgeberIndex).then((result) {
                if (ctx.mounted) {
                  setModalState(() {
                    docsLoading = false;
                    if (result['success'] == true && result['data'] != null) {
                      dokumente = List<Map<String, dynamic>>.from(result['data']);
                    }
                  });
                }
              }).catchError((e) {
                if (ctx.mounted) {
                  setModalState(() => docsLoading = false);
                }
              });
              // Prevent re-triggering
              docsLoading = false;
            }

            // Resolve DB employer details
            Map<String, dynamic>? dbAg;
            final dbId = ag['arbeitgeber_db_id'];
            if (dbId != null && widget.dbArbeitgeberListe.isNotEmpty) {
              dbAg = widget.dbArbeitgeberListe.cast<Map<String, dynamic>?>().firstWhere(
                (a) => a?['id'].toString() == dbId.toString(),
                orElse: () => null,
              );
            }

            // ── Shared document upload/list builder (used by Vertrag, Lohn, K\u00FCndigung, Sonstiges) ──
            Widget buildDokUploadAndList(BuildContext ctx, StateSetter setModalState, List<String> typen, List<Map<String, dynamic>> dokumente, int arbeitgeberIndex) {
              final filtered = dokumente.where((d) => typen.contains(d['dok_typ'])).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Upload button
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final picked = await FilePickerHelper.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
                        );
                        if (picked == null || picked.files.isEmpty) return;
                        final file = picked.files.first;
                        if (file.path == null) return;

                        // Pick which sub-type
                        String selectedTyp = typen.first;
                        if (typen.length > 1 && ctx.mounted) {
                          final chosen = await showDialog<String>(
                            context: ctx,
                            builder: (dlgCtx) => SimpleDialog(
                              title: const Text('Dokumenttyp w\u00E4hlen', style: TextStyle(fontSize: 15)),
                              children: typen.map((t) => SimpleDialogOption(
                                onPressed: () => Navigator.pop(dlgCtx, t),
                                child: Text(dokTypLabels[t] ?? t, style: const TextStyle(fontSize: 14)),
                              )).toList(),
                            ),
                          );
                          if (chosen == null) return;
                          selectedTyp = chosen;
                        }

                        final datum = DateFormat('yyyy-MM-dd').format(DateTime.now());
                        try {
                          final result = await widget.apiService.uploadArbeitgeberDokument(
                            userId: widget.user.id,
                            arbeitgeberIndex: arbeitgeberIndex,
                            dokTyp: selectedTyp,
                            dokDatum: datum,
                            dokTitel: file.name,
                            filePath: file.path!,
                            fileName: file.name,
                          );
                          if (result['success'] == true && ctx.mounted) {
                            // Reload docs
                            final reloaded = await widget.apiService.getArbeitgeberDokumente(widget.user.id, arbeitgeberIndex);
                            setModalState(() {
                              if (reloaded['success'] == true && reloaded['data'] != null) {
                                dokumente = List<Map<String, dynamic>>.from(reloaded['data']);
                              }
                            });
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.folder_open, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text('Keine Dokumente', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    )
                  else
                    ...filtered.map((doc) {
                      final docId = int.tryParse(doc['id'].toString()) ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.description, size: 20, color: Colors.indigo.shade400),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    doc['dok_titel'] ?? doc['dateiname'] ?? 'Dokument',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        dokTypLabels[doc['dok_typ']] ?? doc['dok_typ'] ?? '',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                      if (doc['dok_datum'] != null) ...[
                                        const SizedBox(width: 8),
                                        Text(doc['dok_datum'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.visibility, size: 18, color: Colors.blue.shade600),
                              tooltip: 'Ansehen',
                              onPressed: () async {
                                try {
                                  final response = await widget.apiService.downloadArbeitgeberDokument(docId);
                                  if (response.statusCode == 200 && ctx.mounted) {
                                    final dir = await getTemporaryDirectory();
                                    final fileName = doc['datei_name'] ?? doc['dateiname'] ?? 'dokument';
                                    final file = File('${dir.path}/$fileName');
                                    await file.writeAsBytes(response.bodyBytes);
                                    if (ctx.mounted) {
                                      final handled = await FileViewerDialog.show(ctx, file.path, fileName);
                                      if (!handled && ctx.mounted) {
                                        await OpenFilex.open(file.path);
                                      }
                                    }
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.download, size: 18, color: Colors.indigo.shade600),
                              tooltip: 'Herunterladen',
                              onPressed: () async {
                                try {
                                  final response = await widget.apiService.downloadArbeitgeberDokument(docId);
                                  if (response.statusCode == 200) {
                                    final dir = await getTemporaryDirectory();
                                    final fileName = doc['datei_name'] ?? doc['dateiname'] ?? 'dokument';
                                    final file = File('${dir.path}/$fileName');
                                    await file.writeAsBytes(response.bodyBytes);
                                    await OpenFilex.open(file.path);
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                              tooltip: 'L\u00F6schen',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: ctx,
                                  builder: (dlgCtx) => AlertDialog(
                                    title: const Text('Dokument l\u00F6schen?', style: TextStyle(fontSize: 15)),
                                    content: Text('${doc['dok_titel'] ?? doc['dateiname'] ?? 'Dokument'} wirklich l\u00F6schen?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Abbrechen')),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(dlgCtx, true),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                        child: const Text('L\u00F6schen'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                try {
                                  final result = await widget.apiService.deleteArbeitgeberDokument(docId);
                                  if (result['success'] == true && ctx.mounted) {
                                    final reloaded = await widget.apiService.getArbeitgeberDokumente(widget.user.id, arbeitgeberIndex);
                                    setModalState(() {
                                      if (reloaded['success'] == true && reloaded['data'] != null) {
                                        dokumente = List<Map<String, dynamic>>.from(reloaded['data']);
                                      }
                                    });
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              );
            }

            // ── Simple doc tab (used by Lohn, Sonstiges) ──
            Widget buildDokTab(String tabKey, List<String> typen) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: buildDokUploadAndList(ctx, setModalState, typen, dokumente, arbeitgeberIndex),
              );
            }

            // ── Vertrag edit dialog ──
            void showVertragEditDialog() {
              final vertragsbeginnC = TextEditingController(text: ag['vertragsbeginn']?.toString() ?? '');
              final unterschriftC = TextEditingController(text: ag['unterschriftsdatum']?.toString() ?? '');
              final probezeitC = TextEditingController(text: ag['probezeit']?.toString() ?? '');
              final arbeitszeitC = TextEditingController(text: ag['arbeitszeit_std']?.toString() ?? '');
              final gehaltC = TextEditingController(text: ag['grundgehalt']?.toString() ?? '');
              final urlaubC = TextEditingController(text: ag['urlaubstage']?.toString() ?? '');
              final fristC = TextEditingController(text: ag['kuendigungsfrist']?.toString() ?? '');
              String befristung = ag['befristung']?.toString() ?? 'unbefristet';

              Future<void> pickDate(BuildContext dlgCtx, TextEditingController ctrl) async {
                final picked = await showDatePicker(
                  context: dlgCtx,
                  initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2040),
                  locale: const Locale('de'),
                );
                if (picked != null) {
                  ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
                }
              }

              showDialog(
                context: ctx,
                builder: (dlgCtx) => StatefulBuilder(
                  builder: (dlgCtx, setDlgState) => AlertDialog(
                    title: Row(children: [
                      Icon(Icons.edit, size: 18, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      const Text('Vertragsdaten bearbeiten', style: TextStyle(fontSize: 15)),
                    ]),
                    content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: vertragsbeginnC,
                              readOnly: true,
                              onTap: () => pickDate(dlgCtx, vertragsbeginnC),
                              decoration: InputDecoration(labelText: 'Vertragsbeginn', prefixIcon: const Icon(Icons.calendar_today, size: 18), suffixIcon: const Icon(Icons.date_range, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: unterschriftC,
                              readOnly: true,
                              onTap: () => pickDate(dlgCtx, unterschriftC),
                              decoration: InputDecoration(labelText: 'Unterschriftsdatum', prefixIcon: const Icon(Icons.edit_calendar, size: 18), suffixIcon: const Icon(Icons.date_range, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: befristung,
                              decoration: InputDecoration(labelText: 'Befristung', prefixIcon: const Icon(Icons.timer, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              items: const [
                                DropdownMenuItem(value: 'unbefristet', child: Text('Unbefristet', style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 'befristet', child: Text('Befristet', style: TextStyle(fontSize: 13))),
                              ],
                              onChanged: (v) => setDlgState(() => befristung = v ?? 'unbefristet'),
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: probezeitC,
                              decoration: InputDecoration(labelText: 'Probezeit (z.B. 6 Monate)', prefixIcon: const Icon(Icons.hourglass_bottom, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: arbeitszeitC,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'Arbeitszeit Std./Woche', prefixIcon: const Icon(Icons.access_time, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: gehaltC,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'Grundgehalt brutto/Monat (€)', prefixIcon: const Icon(Icons.euro, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: urlaubC,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'Urlaubstage/Jahr', prefixIcon: const Icon(Icons.beach_access, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: fristC,
                              decoration: InputDecoration(labelText: 'Kündigungsfrist (z.B. 4 Wochen)', prefixIcon: const Icon(Icons.exit_to_app, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
                      ElevatedButton.icon(
                        onPressed: () {
                          setModalState(() {
                            ag['vertragsbeginn'] = vertragsbeginnC.text.isNotEmpty ? vertragsbeginnC.text : null;
                            ag['unterschriftsdatum'] = unterschriftC.text.isNotEmpty ? unterschriftC.text : null;
                            ag['befristung'] = befristung;
                            ag['probezeit'] = probezeitC.text.isNotEmpty ? probezeitC.text : null;
                            ag['arbeitszeit_std'] = arbeitszeitC.text.isNotEmpty ? arbeitszeitC.text : null;
                            ag['grundgehalt'] = gehaltC.text.isNotEmpty ? gehaltC.text : null;
                            ag['urlaubstage'] = urlaubC.text.isNotEmpty ? urlaubC.text : null;
                            ag['kuendigungsfrist'] = fristC.text.isNotEmpty ? fristC.text : null;
                          });
                          _saveWithData(arbeitgeberListe, selectedArbeitgeberId);
                          Navigator.pop(dlgCtx);
                        },
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Speichern'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ),
              );
            }

            // ── Tab 2: VERTRAG (enhanced) ──
            Widget buildVertragTab() {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Vertragsdaten info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.description, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              Text('Vertragsdaten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                              const Spacer(),
                              InkWell(
                                onTap: showVertragEditDialog,
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(6)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.edit, size: 13, color: Colors.blue.shade700),
                                    const SizedBox(width: 4),
                                    Text('Bearbeiten', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                                  ]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildInfoField(Icons.calendar_today, 'Vertragsbeginn', ag['vertragsbeginn']?.toString()),
                          _buildInfoField(Icons.edit_calendar, 'Unterschriftsdatum', ag['unterschriftsdatum']?.toString()),
                          _buildInfoField(Icons.timer, 'Befristung', ag['befristung']?.toString() ?? (ag['befristet'] == true ? 'befristet' : (ag['befristet'] == false ? 'unbefristet' : null))),
                          _buildInfoField(Icons.hourglass_bottom, 'Probezeit', ag['probezeit']?.toString()),
                          _buildInfoField(Icons.access_time, 'Arbeitszeit Std./Woche', ag['arbeitszeit_std']?.toString()),
                          _buildInfoField(Icons.euro, 'Grundgehalt brutto/Monat', ag['grundgehalt']?.toString()),
                          _buildInfoField(Icons.beach_access, 'Urlaubstage', ag['urlaubstage']?.toString()),
                          _buildInfoField(Icons.exit_to_app, 'K\u00FCndigungsfrist', ag['kuendigungsfrist']?.toString()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Gesetzliche K\u00FCndigungsfristen
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                      dense: true,
                      leading: Icon(Icons.gavel, size: 16, color: Colors.blue.shade600),
                      title: Text('Gesetzl. K\u00FCndigungsfristen (\u00A7622 BGB)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                      children: [
                        _buildFristRow('Probezeit (bis 6 Mon.)', '2 Wochen'),
                        _buildFristRow('0\u20132 Jahre', '4 Wochen zum 15./Monatsende'),
                        _buildFristRow('2 Jahre', '1 Monat zum Monatsende'),
                        _buildFristRow('5 Jahre', '2 Monate'),
                        _buildFristRow('8 Jahre', '3 Monate'),
                        _buildFristRow('10 Jahre', '4 Monate'),
                        _buildFristRow('12 Jahre', '5 Monate'),
                        _buildFristRow('15 Jahre', '6 Monate'),
                        _buildFristRow('20 Jahre', '7 Monate'),
                      ],
                    ),
                    const Divider(height: 24),
                    Text('Dokumente', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                    const SizedBox(height: 8),
                    buildDokUploadAndList(ctx, setModalState, dokTypen['vertrag']!, dokumente, arbeitgeberIndex),
                  ],
                ),
              );
            }

            // ── Tab 4: KRANKHEIT (read-only, Daten kommen vom Hausarzt) ──
            // Berechne wer zahlt basierend auf Vertragsbeginn und AU-Daten
            Map<String, dynamic> berechneEntgeltfortzahlung(Map<String, dynamic> km, List<dynamic> alleKrankmeldungen) {
              final vertragsbeginn = DateTime.tryParse(ag['vertragsbeginn']?.toString() ?? '');
              final auBeginn = DateTime.tryParse(km['au_beginn']?.toString() ?? '');
              final auEnde = DateTime.tryParse(km['au_ende']?.toString() ?? '');
              if (vertragsbeginn == null || auBeginn == null) {
                return {'status': 'unbekannt', 'text': 'Vertragsbeginn oder AU-Beginn fehlt', 'color': Colors.grey, 'icon': Icons.help_outline};
              }
              final tageImBetrieb = auBeginn.difference(vertragsbeginn).inDays;
              if (tageImBetrieb < 28) {
                return {
                  'status': 'krankenkasse_wartezeit',
                  'text': 'Wartezeit ($tageImBetrieb von 28 Tagen) \u2014 Krankenkasse zahlt Krankengeld',
                  'color': Colors.red,
                  'icon': Icons.hourglass_top,
                };
              }
              final auDauer = auEnde != null ? auEnde.difference(auBeginn).inDays + 1 : 0;
              int kumulativeTage = 0;
              for (final prev in alleKrankmeldungen) {
                if (prev is! Map<String, dynamic>) continue;
                final prevBeginn = DateTime.tryParse(prev['au_beginn']?.toString() ?? '');
                final prevEnde = DateTime.tryParse(prev['au_ende']?.toString() ?? '');
                if (prevBeginn == null || prevEnde == null) continue;
                if (prevBeginn.isBefore(auBeginn) || prevBeginn == auBeginn) {
                  if (prev['au_beginn'] == km['au_beginn'] && prev['au_ende'] == km['au_ende']) break;
                  kumulativeTage += prevEnde.difference(prevBeginn).inDays + 1;
                }
              }
              final gesamtTage = kumulativeTage + auDauer;
              if (gesamtTage <= 42) {
                return {
                  'status': 'arbeitgeber',
                  'text': 'Arbeitgeber zahlt Lohnfortzahlung (Tag $kumulativeTage\u2013$gesamtTage von 42)',
                  'color': Colors.green,
                  'icon': Icons.payments,
                };
              } else if (kumulativeTage < 42) {
                final agTage = 42 - kumulativeTage;
                return {
                  'status': 'gemischt',
                  'text': 'Arbeitgeber: erste $agTage Tage, dann Krankenkasse Krankengeld (~70%)',
                  'color': Colors.orange,
                  'icon': Icons.swap_horiz,
                };
              } else {
                return {
                  'status': 'krankenkasse',
                  'text': 'Krankenkasse zahlt Krankengeld (~70% brutto, max 90% netto)',
                  'color': Colors.red,
                  'icon': Icons.account_balance,
                };
              }
            }

            void showMeldungDialog(BuildContext ctx, String kmKey, Map<String, dynamic> meldung) {
              final datumC = TextEditingController(text: meldung['meldung_datum']?.toString() ?? '');
              String meldungArt = meldung['meldung_art']?.toString() ?? '';
              bool gemeldet = meldung['gemeldet'] == true;
              bool eauAbgerufen = meldung['eau_abgerufen'] == true;
              final eauDatumC = TextEditingController(text: meldung['eau_datum']?.toString() ?? '');
              final emailInhaltC = TextEditingController(text: meldung['email_inhalt']?.toString() ?? '');
              final anmerkungenC = TextEditingController(text: meldung['anmerkungen']?.toString() ?? '');

              Future<void> pickDate(BuildContext dlgCtx, TextEditingController ctrl) async {
                final picked = await showDatePicker(
                  context: dlgCtx,
                  initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2040),
                  locale: const Locale('de'),
                );
                if (picked != null) {
                  ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
                }
              }

              showDialog(
                context: ctx,
                builder: (dlgCtx) => StatefulBuilder(
                  builder: (dlgCtx, setDlgState) => AlertDialog(
                    title: Row(children: [
                      Icon(Icons.business, size: 18, color: Colors.indigo.shade700),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Meldung an Arbeitgeber', style: TextStyle(fontSize: 15))),
                    ]),
                    content: SizedBox(
                      width: 400,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Gemeldet?
                            SwitchListTile(
                              title: const Text('Arbeitgeber informiert?', style: TextStyle(fontSize: 13)),
                              value: gemeldet,
                              activeTrackColor: Colors.green.shade200,
                              activeThumbColor: Colors.green.shade700,
                              onChanged: (v) => setDlgState(() => gemeldet = v),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (gemeldet) ...[
                              const SizedBox(height: 12),
                              // Wie gemeldet
                              DropdownButtonFormField<String>(
                                initialValue: meldungArt.isNotEmpty ? meldungArt : null,
                                decoration: InputDecoration(labelText: 'Wie gemeldet?', prefixIcon: const Icon(Icons.send, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                items: const [
                                  DropdownMenuItem(value: 'email', child: Text('Per E-Mail', style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: 'telefon', child: Text('Per Telefon', style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: 'persoenlich', child: Text('Pers\u00F6nlich', style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: 'whatsapp', child: Text('Per WhatsApp/SMS', style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: 'brief', child: Text('Per Brief/Post', style: TextStyle(fontSize: 13))),
                                ],
                                onChanged: (v) => setDlgState(() => meldungArt = v ?? ''),
                              ),
                              const SizedBox(height: 12),
                              // Datum der Meldung
                              TextFormField(
                                controller: datumC,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Datum der Meldung',
                                  prefixIcon: const Icon(Icons.event, size: 18),
                                  suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => pickDate(dlgCtx, datumC).then((_) => setDlgState(() {}))),
                                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Email-Inhalt (Beweis)
                              TextFormField(
                                controller: emailInhaltC,
                                maxLines: 6,
                                decoration: InputDecoration(
                                  labelText: 'E-Mail / Nachricht Inhalt (Beweis)',
                                  hintText: 'Hier den Inhalt der E-Mail oder Nachricht einf\u00FCgen (Copy & Paste)...',
                                  hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                  prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 80), child: Icon(Icons.email, size: 18)),
                                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            // eAU abgerufen
                            SwitchListTile(
                              title: const Text('eAU vom AG abgerufen?', style: TextStyle(fontSize: 13)),
                              subtitle: const Text('Arbeitgeber hat eAU elektronisch bei Krankenkasse abgerufen', style: TextStyle(fontSize: 11)),
                              value: eauAbgerufen,
                              activeTrackColor: Colors.blue.shade200,
                              activeThumbColor: Colors.blue.shade700,
                              onChanged: (v) => setDlgState(() => eauAbgerufen = v),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (eauAbgerufen) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: eauDatumC,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'eAU-Abruf Datum',
                                  prefixIcon: const Icon(Icons.cloud_download, size: 18),
                                  suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => pickDate(dlgCtx, eauDatumC).then((_) => setDlgState(() {}))),
                                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: anmerkungenC,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Anmerkungen (optional)',
                                prefixIcon: const Icon(Icons.note, size: 18),
                                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
                      FilledButton.icon(
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Speichern'),
                        onPressed: () {
                          final meldungen = Map<String, dynamic>.from(ag['krankheit_meldungen'] is Map ? ag['krankheit_meldungen'] as Map : {});
                          meldungen[kmKey] = {
                            'gemeldet': gemeldet,
                            'meldung_art': meldungArt.isNotEmpty ? meldungArt : null,
                            'meldung_datum': datumC.text.isNotEmpty ? datumC.text : null,
                            'eau_abgerufen': eauAbgerufen,
                            'eau_datum': eauDatumC.text.isNotEmpty ? eauDatumC.text : null,
                            'email_inhalt': emailInhaltC.text.isNotEmpty ? emailInhaltC.text : null,
                            'anmerkungen': anmerkungenC.text.isNotEmpty ? anmerkungenC.text : null,
                          };
                          ag['krankheit_meldungen'] = meldungen;
                          Navigator.pop(dlgCtx);
                          _saveWithData(arbeitgeberListe, selectedArbeitgeberId);
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget buildKrankheitTab() {
              // Krankmeldungen kommen vom Hausarzt (gesundheit_hausarzt)
              final hausarztData = _hausarztData;
              final List<dynamic> krankheiten = hausarztData['krankmeldungen'] is List ? hausarztData['krankmeldungen'] as List : [];
              final String hausarztName = hausarztData['selected_arzt'] is Map ? (hausarztData['selected_arzt'] as Map)['name']?.toString() ?? '' : (hausarztData['behandelnder_arzt']?.toString() ?? '');
              final Map<String, dynamic> agMeldungen = ag['krankheit_meldungen'] is Map ? Map<String, dynamic>.from(ag['krankheit_meldungen'] as Map) : {};
              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info: Daten vom Hausarzt
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.link, size: 16, color: Colors.teal.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Krankmeldungen werden beim Hausarzt (\u00C4rzte \u2192 Hausarzt \u2192 Krankmeldungen) erfasst und hier automatisch angezeigt.',
                              style: TextStyle(fontSize: 11, color: Colors.teal.shade800, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // eAU info banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.yellow.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.yellow.shade600),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.yellow.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Seit 01.01.2023 gilt die eAU. Arbeitgeber ruft Krankschreibung bei Krankenkasse ab.',
                              style: TextStyle(fontSize: 11, color: Colors.yellow.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Entgeltfortzahlung info card - DYNAMISCH basierend auf Vertragsbeginn
                    Builder(builder: (ctx) {
                      final vertragsbeginn = DateTime.tryParse(ag['vertragsbeginn']?.toString() ?? '');
                      final tageImBetrieb = vertragsbeginn != null ? DateTime.now().difference(vertragsbeginn).inDays : null;
                      final inWartezeit = tageImBetrieb != null && tageImBetrieb < 28;
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: inWartezeit ? Colors.red.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: inWartezeit ? Colors.red.shade200 : Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.local_hospital, size: 16, color: inWartezeit ? Colors.red.shade700 : Colors.green.shade700),
                                const SizedBox(width: 6),
                                Expanded(child: Text('Entgeltfortzahlung (\u00A73 EFZG)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: inWartezeit ? Colors.red.shade800 : Colors.green.shade800))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (vertragsbeginn != null) ...[
                              _buildInfoField(Icons.work_history, 'Vertragsbeginn', DateFormat('dd.MM.yyyy').format(vertragsbeginn)),
                              _buildInfoField(Icons.timer, 'Besch\u00E4ftigungsdauer', '${tageImBetrieb ?? 0} Tage (${((tageImBetrieb ?? 0) / 30).toStringAsFixed(1)} Monate)'),
                              if (inWartezeit)
                                _buildWarnField('\u26A0\uFE0F', 'Wartezeit', 'Noch ${28 - tageImBetrieb} Tage bis Anspruch auf Lohnfortzahlung. Aktuell zahlt Krankenkasse.')
                              else
                                _buildInfoField(Icons.check_circle, 'Status', 'Anspruch auf Lohnfortzahlung (Wartezeit erf\u00FCllt)'),
                              const Divider(height: 16),
                            ] else ...[
                              _buildWarnField('\u26A0\uFE0F', 'Vertragsbeginn fehlt', 'Bitte im Tab "Vertrag" eintragen f\u00FCr korrekte Berechnung.'),
                              const Divider(height: 16),
                            ],
                            _buildInfoField(Icons.hourglass_top, 'Erste 4 Wochen (Wartezeit)', 'Krankenkasse zahlt Krankengeld (\u00A73 Abs.3 EFZG)'),
                            _buildInfoField(Icons.payments, 'Ab 5. Woche', 'Arbeitgeber zahlt 6 Wochen Lohnfortzahlung (100%)'),
                            _buildInfoField(Icons.account_balance, 'Nach 6 Wochen AG-Zahlung', 'Krankenkasse zahlt Krankengeld (~70% brutto)'),
                            _buildInfoField(Icons.notification_important, 'Meldepflicht', 'Sofort am 1. Krankheitstag'),
                            _buildInfoField(Icons.assignment, 'AU-Bescheinigung', 'Sp\u00E4testens am 4. Kalendertag'),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    // Krankmeldungen vom Hausarzt (read-only)
                    Row(
                      children: [
                        Icon(Icons.healing, size: 16, color: Colors.indigo.shade700),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Krankmeldungen vom Hausarzt (${krankheiten.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (krankheiten.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(Icons.healing, size: 40, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text('Keine Krankmeldungen vorhanden', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                              const SizedBox(height: 4),
                              Text('Krankmeldungen k\u00F6nnen unter \u00C4rzte \u2192 Hausarzt \u2192 Krankmeldungen erfasst werden', style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    else
                      ...krankheiten.asMap().entries.map((entry) {
                        final km = entry.value is Map<String, dynamic> ? entry.value as Map<String, dynamic> : <String, dynamic>{};
                        final isErstbescheinigung = km['erstbescheinigung'] == true || km['art'] == 'erst';
                        final isArbeitsunfall = km['arbeitsunfall'] == true;
                        final auBeginn = DateTime.tryParse(km['au_beginn']?.toString() ?? '');
                        final auEnde = DateTime.tryParse(km['au_ende']?.toString() ?? '');
                        final dauerTage = (auBeginn != null && auEnde != null) ? auEnde.difference(auBeginn).inDays + 1 : null;
                        final entgelt = berechneEntgeltfortzahlung(km, krankheiten);
                        final entgeltColor = entgelt['color'] as Color;
                        // AG-Meldung Daten (gespeichert beim Arbeitgeber)
                        final kmKey = km['au_beginn']?.toString() ?? 'km_${entry.key}';
                        final meldung = agMeldungen[kmKey] is Map ? Map<String, dynamic>.from(agMeldungen[kmKey] as Map) : <String, dynamic>{};
                        final istGemeldet = meldung['gemeldet'] == true;
                        final meldungArtLabel = {
                          'email': 'E-Mail', 'telefon': 'Telefon', 'persoenlich': 'Pers\u00F6nlich',
                          'whatsapp': 'WhatsApp/SMS', 'brief': 'Brief/Post',
                        }[meldung['meldung_art']?.toString() ?? ''] ?? meldung['meldung_art']?.toString();
                        final eauAbgerufen = meldung['eau_abgerufen'] == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isErstbescheinigung ? Colors.blue.shade200 : Colors.orange.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header: badges
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isErstbescheinigung ? Colors.blue.shade100 : Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isErstbescheinigung ? 'Erstbescheinigung' : 'Folgebescheinigung',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isErstbescheinigung ? Colors.blue.shade800 : Colors.orange.shade800),
                                    ),
                                  ),
                                  if (isArbeitsunfall) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                                      child: Text('Arbeitsunfall', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                                    ),
                                  ],
                                  if (dauerTage != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                                      child: Text('$dauerTage Tage', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Ausgestellt von Hausarzt
                              if (hausarztName.isNotEmpty)
                                _buildInfoField(Icons.person, 'Ausgestellt von', 'Dr. $hausarztName (Hausarzt)'),
                              _buildInfoField(Icons.event_note, 'Feststellungsdatum', km['feststellungsdatum']?.toString()),
                              _buildInfoField(Icons.play_arrow, 'AU-Beginn', km['au_beginn']?.toString()),
                              _buildInfoField(Icons.stop, 'Voraussichtl. Ende', km['au_ende']?.toString()),
                              if (km['diagnose'] != null && km['diagnose'].toString().isNotEmpty)
                                _buildInfoField(Icons.medical_information, 'Diagnose', km['diagnose'].toString()),
                              if (km['icd_code'] != null && km['icd_code'].toString().isNotEmpty)
                                _buildInfoField(Icons.code, 'ICD-Code', km['icd_code'].toString()),
                              // Entgeltfortzahlung status
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: entgeltColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: entgeltColor.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(entgelt['icon'] as IconData? ?? Icons.info, size: 14, color: entgeltColor),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(entgelt['text'] as String, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: entgeltColor))),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // ── Meldung an Arbeitgeber ──
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: istGemeldet ? Colors.green.shade50 : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: istGemeldet ? Colors.green.shade200 : Colors.red.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.business, size: 14, color: istGemeldet ? Colors.green.shade700 : Colors.red.shade700),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text('Meldung an Arbeitgeber', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: istGemeldet ? Colors.green.shade800 : Colors.red.shade800))),
                                        InkWell(
                                          onTap: () => showMeldungDialog(context, kmKey, meldung),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade50,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.indigo.shade200),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.edit, size: 12, color: Colors.indigo.shade600),
                                                const SizedBox(width: 4),
                                                Text('Bearbeiten', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.indigo.shade600)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (istGemeldet) ...[
                                      _buildInfoField(Icons.check_circle, 'Status', 'Arbeitgeber informiert'),
                                      if (meldungArtLabel != null)
                                        _buildInfoField(Icons.send, 'Gemeldet per', meldungArtLabel),
                                      if (meldung['meldung_datum'] != null)
                                        _buildInfoField(Icons.event, 'Meldung am', meldung['meldung_datum'].toString()),
                                    ] else ...[
                                      _buildInfoField(Icons.warning, 'Status', 'Noch nicht gemeldet!'),
                                    ],
                                    // eAU Status
                                    const Divider(height: 8),
                                    if (eauAbgerufen) ...[
                                      _buildInfoField(Icons.cloud_done, 'eAU', 'Vom Arbeitgeber elektronisch abgerufen'),
                                      if (meldung['eau_datum'] != null)
                                        _buildInfoField(Icons.cloud_download, 'eAU-Abruf am', meldung['eau_datum'].toString()),
                                    ] else ...[
                                      _buildInfoField(Icons.cloud_off, 'eAU', 'Noch nicht abgerufen'),
                                    ],
                                    if (meldung['email_inhalt'] != null && meldung['email_inhalt'].toString().isNotEmpty)
                                      ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        childrenPadding: const EdgeInsets.only(bottom: 4),
                                        dense: true,
                                        leading: Icon(Icons.email, size: 14, color: Colors.indigo.shade500),
                                        title: Text('E-Mail / Nachricht (Beweis)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.indigo.shade600)),
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade50,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.grey.shade200),
                                            ),
                                            child: SelectableText(
                                              meldung['email_inhalt'].toString(),
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontFamily: 'monospace'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (meldung['anmerkungen'] != null && meldung['anmerkungen'].toString().isNotEmpty)
                                      _buildInfoField(Icons.note, 'Anmerkungen', meldung['anmerkungen'].toString()),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    // Wiederholte Krankheit rules
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                      dense: true,
                      leading: Icon(Icons.replay, size: 16, color: Colors.orange.shade600),
                      title: Text('Wiederholte Krankheit \u2014 Regeln', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
                      children: [
                        _buildInfoField(Icons.sync, 'Gleiche Krankheit innerhalb 6 Mon.', 'Z\u00E4hler l\u00E4uft weiter'),
                        _buildInfoField(Icons.restart_alt, 'Gleiche Krankheit nach 6+ Mon. Pause ODER 12 Mon.', 'Reset'),
                        _buildInfoField(Icons.add_circle_outline, 'Andere Krankheit', 'Neue 6 Wochen'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // === Krankmeldung E-Mail Script Generator ===
                    Builder(builder: (_) {
                      String scriptTyp = 'erstmeldung';
                      final scriptC = TextEditingController();
                      final agEmail = ag['email']?.toString() ?? '';
                      final mitgliedName = widget.user.name;
                      final personalnr = ag['personalnummer']?.toString() ?? '';
                      final abteilung = ag['abteilung']?.toString() ?? '';
                      return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: StatefulBuilder(builder: (scriptCtx, setScriptState) {

                        // Get dates from Krankmeldungen
                        String fmtDe(String? isoDate) {
                          if (isoDate == null || isoDate.isEmpty) return '';
                          final d = DateTime.tryParse(isoDate);
                          if (d == null) return isoDate;
                          return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
                        }

                        // Find latest Krankmeldung
                        Map<String, dynamic>? latestKm;
                        Map<String, dynamic>? erstKm;
                        for (final k in krankheiten) {
                          final km = k is Map ? Map<String, dynamic>.from(k) : <String, dynamic>{};
                          if (erstKm == null || (km['erstbescheinigung'] == true || km['art'] == 'erst')) {
                            erstKm = km;
                          }
                          // Latest by au_ende
                          final ende = DateTime.tryParse(km['au_ende']?.toString() ?? '');
                          final latestEnde = DateTime.tryParse(latestKm?['au_ende']?.toString() ?? '');
                          if (ende != null && (latestEnde == null || ende.isAfter(latestEnde))) {
                            latestKm = km;
                          }
                        }

                        void generateScript() {
                          final sb = StringBuffer();
                          if (scriptTyp == 'erstmeldung') {
                            final auBeginn = fmtDe(erstKm?['au_beginn']?.toString());
                            final auEnde = fmtDe(erstKm?['au_ende']?.toString());
                            final datumStr = auEnde.isNotEmpty ? auEnde : '[DATUM]';
                            final abStr = auBeginn.isNotEmpty ? 'ab dem $auBeginn' : 'ab heute';
                            sb.writeln('Betreff: Krankmeldung \u2013 $mitgliedName${personalnr.isNotEmpty ? ' (Pers.-Nr. $personalnr)' : ''}');
                            sb.writeln();
                            sb.writeln('Sehr geehrte Damen und Herren,');
                            sb.writeln();
                            sb.writeln('hiermit teile ich Ihnen mit, dass ich $abStr leider arbeitsunf\u00E4hig erkrankt bin.');
                            sb.writeln('Voraussichtlich werde ich bis einschlie\u00DFlich $datumStr nicht arbeiten k\u00F6nnen.');
                            sb.writeln();
                            sb.writeln('Meine Arbeitsunf\u00E4higkeitsbescheinigung (AU) liegt meiner Krankenkasse elektronisch vor (eAU).');
                            sb.writeln('Sie k\u00F6nnen die eAU gem\u00E4\u00DF \u00A7 5b EntgFG direkt bei meiner Krankenkasse elektronisch abrufen.');
                            sb.writeln();
                            sb.writeln('Ich werde Sie \u00FCber den weiteren Verlauf informieren.');
                            sb.writeln();
                            sb.writeln('Mit freundlichen Gr\u00FC\u00DFen');
                            sb.writeln(mitgliedName);
                            if (personalnr.isNotEmpty) sb.writeln('Personalnummer: $personalnr');
                            if (abteilung.isNotEmpty) sb.writeln('Abteilung: $abteilung');
                          } else {
                            final auEnde = fmtDe(latestKm?['au_ende']?.toString());
                            final datumStr = auEnde.isNotEmpty ? auEnde : '[NEUES DATUM]';
                            sb.writeln('Betreff: Verl\u00E4ngerung der Krankmeldung \u2013 $mitgliedName${personalnr.isNotEmpty ? ' (Pers.-Nr. $personalnr)' : ''}');
                            sb.writeln();
                            sb.writeln('Sehr geehrte Damen und Herren,');
                            sb.writeln();
                            sb.writeln('hiermit teile ich Ihnen mit, dass sich meine Arbeitsunf\u00E4higkeit leider verl\u00E4ngert.');
                            sb.writeln('Voraussichtlich werde ich bis einschlie\u00DFlich $datumStr nicht arbeiten k\u00F6nnen.');
                            sb.writeln();
                            sb.writeln('Die Folgebescheinigung (eAU) wurde von meinem Arzt elektronisch an meine Krankenkasse \u00FCbermittelt.');
                            sb.writeln('Sie k\u00F6nnen die aktualisierte eAU bei meiner Krankenkasse abrufen.');
                            sb.writeln();
                            sb.writeln('Ich werde Sie weiterhin \u00FCber den Verlauf informieren.');
                            sb.writeln();
                            sb.writeln('Mit freundlichen Gr\u00FC\u00DFen');
                            sb.writeln(mitgliedName);
                            if (personalnr.isNotEmpty) sb.writeln('Personalnummer: $personalnr');
                            if (abteilung.isNotEmpty) sb.writeln('Abteilung: $abteilung');
                          }
                          setScriptState(() => scriptC.text = sb.toString());
                        }

                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(Icons.email, size: 18, color: Colors.teal.shade700),
                            const SizedBox(width: 6),
                            Text('Krankmeldung E-Mail generieren', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                          ]),
                          const SizedBox(height: 8),
                          // Info box
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              Expanded(child: Text(
                                'Seit 01.01.2023: eAU (elektronische AU) \u2013 der Arbeitgeber ruft die Krankschreibung direkt bei der Krankenkasse ab (\u00A7 5b EntgFG). Der Arbeitnehmer muss nur unverz\u00FCglich die Krankheit und voraussichtliche Dauer melden.',
                                style: TextStyle(fontSize: 10, color: Colors.blue.shade700),
                              )),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          // Type selection
                          Row(children: [
                            Expanded(child: InkWell(
                              onTap: () => setScriptState(() => scriptTyp = 'erstmeldung'),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: scriptTyp == 'erstmeldung' ? Colors.teal.shade600 : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.teal.shade300),
                                ),
                                child: Center(child: Text('Erstmeldung (Neu krank)',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                        color: scriptTyp == 'erstmeldung' ? Colors.white : Colors.teal.shade700))),
                              ),
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: InkWell(
                              onTap: () => setScriptState(() => scriptTyp = 'verlaengerung'),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: scriptTyp == 'verlaengerung' ? Colors.orange.shade600 : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.orange.shade300),
                                ),
                                child: Center(child: Text('Verl\u00E4ngerung (Folge-AU)',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                        color: scriptTyp == 'verlaengerung' ? Colors.white : Colors.orange.shade700))),
                              ),
                            )),
                          ]),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.auto_fix_high, size: 16, color: Colors.teal.shade600),
                              label: Text('Script generieren', style: TextStyle(fontSize: 12, color: Colors.teal.shade600)),
                              style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade300)),
                              onPressed: generateScript,
                            ),
                          ),
                          if (scriptC.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(border: Border.all(color: Colors.teal.shade200), borderRadius: BorderRadius.circular(8), color: Colors.white),
                              child: TextField(
                                controller: scriptC,
                                maxLines: 12,
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(10)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              if (agEmail.isNotEmpty)
                                TextButton.icon(
                                  icon: Icon(Icons.email, size: 14, color: Colors.blue.shade600),
                                  label: Text('E-Mail: $agEmail', style: TextStyle(fontSize: 10, color: Colors.blue.shade600)),
                                  onPressed: () {
                                    if (scriptCtx.mounted) ClipboardHelper.copy(scriptCtx, agEmail, 'E-Mail');
                                  },
                                ),
                              TextButton.icon(
                                icon: Icon(Icons.copy, size: 14, color: Colors.teal.shade600),
                                label: Text('Script kopieren', style: TextStyle(fontSize: 10, color: Colors.teal.shade600)),
                                onPressed: () {
                                  if (scriptCtx.mounted) ClipboardHelper.copy(scriptCtx, scriptC.text, 'Script');
                                },
                              ),
                            ]),
                          ],
                        ]);
                      }),
                    );
                    }),
                  ],
                ),
              );
            }

            // ── Berechnung letzter Arbeitstag nach §622 BGB ──
            DateTime lastDayOfMonth(int year, int month) {
              return DateTime(year, month + 1, 0);
            }

            String? berechneLetzerArbeitstag(String? zustellungStr, String fristVal) {
              if (zustellungStr == null || zustellungStr.isEmpty || fristVal.isEmpty) return null;
              final zustellung = DateTime.tryParse(zustellungStr);
              if (zustellung == null) return null;

              if (fristVal.startsWith('2 Wochen')) {
                // Probezeit: 2 Wochen ab Zugang, jeder Tag
                final ende = zustellung.add(const Duration(days: 14));
                return DateFormat('yyyy-MM-dd').format(ende);
              }

              if (fristVal.startsWith('4 Wochen')) {
                // 4 Wochen (28 Tage) zum 15. oder Monatsende
                final minEnde = zustellung.add(const Duration(days: 28));
                // Nächster 15. oder Monatsende nach minEnde
                DateTime kandidat;
                // Check 15. des gleichen Monats
                final tag15 = DateTime(minEnde.year, minEnde.month, 15);
                if (!tag15.isBefore(minEnde)) {
                  kandidat = tag15;
                } else {
                  // Check Monatsende des gleichen Monats
                  final monatsende = lastDayOfMonth(minEnde.year, minEnde.month);
                  if (!monatsende.isBefore(minEnde)) {
                    kandidat = monatsende;
                  } else {
                    // 15. des nächsten Monats
                    kandidat = DateTime(minEnde.year, minEnde.month + 1, 15);
                  }
                }
                return DateFormat('yyyy-MM-dd').format(kandidat);
              }

              // X Monate zum Monatsende
              int monate = 0;
              if (fristVal.startsWith('1 Monat')) {
                monate = 1;
              } else if (fristVal.startsWith('2 Monate')) {
                monate = 2;
              } else if (fristVal.startsWith('3 Monate')) {
                monate = 3;
              } else if (fristVal.startsWith('4 Monate')) {
                monate = 4;
              } else if (fristVal.startsWith('5 Monate')) {
                monate = 5;
              } else if (fristVal.startsWith('6 Monate')) {
                monate = 6;
              } else if (fristVal.startsWith('7 Monate')) {
                monate = 7;
              }

              if (monate > 0) {
                final minEnde = DateTime(zustellung.year, zustellung.month + monate, zustellung.day);
                final monatsende = lastDayOfMonth(minEnde.year, minEnde.month);
                if (!monatsende.isBefore(minEnde)) {
                  return DateFormat('yyyy-MM-dd').format(monatsende);
                }
                final nextMonatsende = lastDayOfMonth(minEnde.year, minEnde.month + 1);
                return DateFormat('yyyy-MM-dd').format(nextMonatsende);
              }

              return null;
            }

            // ── Kündigung edit dialog ──
            void showKuendigungEditDialog() {
              final parteiOptions = ['Arbeitnehmer', 'Arbeitgeber'];
              final artOptions = ['Ordentliche Kündigung', 'Außerordentliche (fristlose) Kündigung', 'Aufhebungsvertrag', 'Änderungskündigung'];
              String partei = ag['kuendigende_partei']?.toString() ?? '';
              String art = ag['kuendigungsart']?.toString() ?? '';
              final datumC = TextEditingController(text: ag['kuendigungsdatum']?.toString() ?? '');
              final zustellungC = TextEditingController(text: ag['zustellungsdatum']?.toString() ?? '');
              final letzterTagC = TextEditingController(text: ag['letzter_arbeitstag']?.toString() ?? '');
              String frist = ag['kuendigungsfrist_text']?.toString() ?? '';
              final grundC = TextEditingController(text: ag['kuendigungsgrund']?.toString() ?? '');
              final abfindungC = TextEditingController(text: ag['abfindung']?.toString() ?? '');
              final resturlaubC = TextEditingController(text: ag['resturlaub']?.toString() ?? '');
              bool freistellung = ag['freistellung'] == true;

              void autoBerechne() {
                final result = berechneLetzerArbeitstag(zustellungC.text, frist);
                if (result != null) {
                  letzterTagC.text = result;
                }
              }

              Future<void> pickDate(BuildContext dlgCtx, TextEditingController ctrl, {bool recalc = false}) async {
                final picked = await showDatePicker(
                  context: dlgCtx,
                  initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2040),
                  locale: const Locale('de'),
                );
                if (picked != null) {
                  ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
                  if (recalc) autoBerechne();
                }
              }

              showDialog(
                context: ctx,
                builder: (dlgCtx) => StatefulBuilder(
                  builder: (dlgCtx, setDlgState) => AlertDialog(
                    title: Row(children: [
                      Icon(Icons.edit, size: 18, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      const Text('Kündigungsdaten bearbeiten', style: TextStyle(fontSize: 15)),
                    ]),
                    content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: parteiOptions.contains(partei) ? partei : null,
                              decoration: InputDecoration(labelText: 'Kündigende Partei', prefixIcon: const Icon(Icons.person, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              items: parteiOptions.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (v) => setDlgState(() => partei = v ?? ''),
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: artOptions.contains(art) ? art : null,
                              decoration: InputDecoration(labelText: 'Kündigungsart', prefixIcon: const Icon(Icons.category, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              items: artOptions.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (v) => setDlgState(() => art = v ?? ''),
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: datumC,
                              readOnly: true,
                              onTap: () => pickDate(dlgCtx, datumC),
                              decoration: InputDecoration(labelText: 'Kündigungsdatum (erstellt)', prefixIcon: const Icon(Icons.edit_note, size: 18), suffixIcon: const Icon(Icons.date_range, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: zustellungC,
                              readOnly: true,
                              onTap: () => pickDate(dlgCtx, zustellungC, recalc: true),
                              decoration: InputDecoration(labelText: 'Zustellungsdatum (per Post erhalten)', prefixIcon: const Icon(Icons.local_post_office, size: 18), suffixIcon: const Icon(Icons.date_range, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: frist.isNotEmpty ? frist : null,
                              decoration: InputDecoration(labelText: 'Kündigungsfrist (§622 BGB)', prefixIcon: const Icon(Icons.timer_off, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              items: const [
                                DropdownMenuItem(value: '2 Wochen (Probezeit)', child: Text('2 Wochen (Probezeit)', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '4 Wochen zum 15. / Monatsende', child: Text('4 Wochen zum 15. / Monatsende', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '1 Monat zum Monatsende', child: Text('1 Monat zum Monatsende (ab 2 J.)', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '2 Monate zum Monatsende', child: Text('2 Monate zum Monatsende (ab 5 J.)', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '3 Monate zum Monatsende', child: Text('3 Monate zum Monatsende (ab 8 J.)', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '4 Monate zum Monatsende', child: Text('4 Monate zum Monatsende (ab 10 J.)', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '5 Monate zum Monatsende', child: Text('5 Monate zum Monatsende (ab 12 J.)', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '6 Monate zum Monatsende', child: Text('6 Monate zum Monatsende (ab 15 J.)', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '7 Monate zum Monatsende', child: Text('7 Monate zum Monatsende (ab 20 J.)', style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: (v) {
                                setDlgState(() {
                                  frist = v ?? '';
                                  autoBerechne();
                                });
                              },
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                              isExpanded: true,
                            ),
                            const SizedBox(height: 10),
                            // Letzter Arbeitstag — auto-berechnet
                            TextField(
                              controller: letzterTagC,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Letzter Arbeitstag (auto-berechnet)',
                                prefixIcon: const Icon(Icons.event_busy, size: 18),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                filled: true,
                                fillColor: letzterTagC.text.isNotEmpty ? Colors.green.shade50 : Colors.grey.shade100,
                                helperText: 'Wird automatisch aus Zustellungsdatum + Frist berechnet',
                                helperStyle: TextStyle(fontSize: 10, color: Colors.green.shade700),
                              ),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: grundC,
                              maxLines: 2,
                              decoration: InputDecoration(labelText: 'Kündigungsgrund (optional)', prefixIcon: const Icon(Icons.report, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            Row(children: [
                              Text('Freistellung', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                              const Spacer(),
                              Switch(
                                value: freistellung,
                                activeThumbColor: Colors.red.shade400,
                                onChanged: (v) => setDlgState(() => freistellung = v),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            TextField(
                              controller: abfindungC,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'Abfindung (€, optional)', prefixIcon: const Icon(Icons.payments, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: resturlaubC,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'Resturlaub (Tage, optional)', prefixIcon: const Icon(Icons.beach_access, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
                      ElevatedButton.icon(
                        onPressed: () {
                          setModalState(() {
                            ag['kuendigende_partei'] = partei.isNotEmpty ? partei : null;
                            ag['kuendigungsart'] = art.isNotEmpty ? art : null;
                            ag['kuendigungsdatum'] = datumC.text.isNotEmpty ? datumC.text : null;
                            ag['zustellungsdatum'] = zustellungC.text.isNotEmpty ? zustellungC.text : null;
                            ag['letzter_arbeitstag'] = letzterTagC.text.isNotEmpty ? letzterTagC.text : null;
                            ag['kuendigungsfrist_text'] = frist.isNotEmpty ? frist : null;
                            ag['kuendigungsgrund'] = grundC.text.isNotEmpty ? grundC.text : null;
                            ag['freistellung'] = freistellung;
                            ag['abfindung'] = abfindungC.text.isNotEmpty ? abfindungC.text : null;
                            ag['resturlaub'] = resturlaubC.text.isNotEmpty ? resturlaubC.text : null;
                          });
                          _saveWithData(arbeitgeberListe, selectedArbeitgeberId);
                          Navigator.pop(dlgCtx);
                        },
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Speichern'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ),
              );
            }

            // ── Tab 5: KÜNDIGUNG (enhanced) ──
            Widget buildKuendigungTab() {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Kündigungsdaten info card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.exit_to_app, size: 16, color: Colors.red.shade700),
                              const SizedBox(width: 6),
                              Text('Kündigungsdaten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                              const Spacer(),
                              InkWell(
                                onTap: showKuendigungEditDialog,
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.edit, size: 13, color: Colors.red.shade700),
                                    const SizedBox(width: 4),
                                    Text('Bearbeiten', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                                  ]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildInfoField(Icons.person, 'K\u00FCndigende Partei', ag['kuendigende_partei']?.toString()),
                          _buildInfoField(Icons.category, 'K\u00FCndigungsart', ag['kuendigungsart']?.toString()),
                          _buildInfoField(Icons.edit_note, 'K\u00FCndigungsdatum erstellt', ag['kuendigungsdatum']?.toString()),
                          _buildInfoField(Icons.local_post_office, 'Zustellungsdatum per Post', ag['zustellungsdatum']?.toString()),
                          _buildInfoField(Icons.event_busy, 'Letzter Arbeitstag gilt ab', ag['letzter_arbeitstag']?.toString()),
                          _buildInfoField(Icons.timer_off, 'K\u00FCndigungsfrist', ag['kuendigungsfrist_text']?.toString() ?? ag['kuendigungsfrist']?.toString()),
                          if (ag['kuendigungsgrund'] != null)
                            _buildInfoField(Icons.report, 'K\u00FCndigungsgrund', ag['kuendigungsgrund'].toString()),
                          if (ag['freistellung'] == true)
                            _buildInfoField(Icons.free_breakfast, 'Freistellung', 'Ja'),
                          if (ag['abfindung'] != null)
                            _buildInfoField(Icons.payments, 'Abfindung', ag['abfindung'].toString()),
                          if (ag['resturlaub'] != null)
                            _buildInfoField(Icons.beach_access, 'Resturlaub', ag['resturlaub'].toString()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Krankheit in Kuendigungsfrist? (auto-check) ──
                    Builder(builder: (ctx2) {
                      final hausarztKm = _hausarztData['krankmeldungen'] is List ? _hausarztData['krankmeldungen'] as List : [];
                      final zustellung = DateTime.tryParse(ag['zustellungsdatum']?.toString() ?? '');
                      final letzterTag = DateTime.tryParse(ag['letzter_arbeitstag']?.toString() ?? '');
                      bool krankInFrist = false;
                      Map<String, dynamic>? aktiveKm;
                      if (zustellung != null && letzterTag != null) {
                        for (final k in hausarztKm) {
                          if (k is! Map<String, dynamic>) continue;
                          final auBeginn = DateTime.tryParse(k['au_beginn']?.toString() ?? '');
                          final auEnde = DateTime.tryParse(k['au_ende']?.toString() ?? '');
                          if (auBeginn == null || auEnde == null) continue;
                          // Check overlap with Kuendigungsfrist
                          if (auBeginn.isBefore(letzterTag) && auEnde.isAfter(zustellung)) {
                            krankInFrist = true;
                            aktiveKm = k;
                            break;
                          }
                        }
                      }
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: krankInFrist ? Colors.red.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: krankInFrist ? Colors.red.shade300 : Colors.green.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.healing, size: 14, color: krankInFrist ? Colors.red.shade700 : Colors.green.shade700),
                              const SizedBox(width: 6),
                              Expanded(child: Text('Krankheit in K\u00FCndigungsfrist?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: krankInFrist ? Colors.red.shade800 : Colors.green.shade800))),
                            ]),
                            const SizedBox(height: 4),
                            if (zustellung == null || letzterTag == null)
                              Text('K\u00FCndigungsdaten fehlen \u2014 bitte zuerst Zustellungsdatum + Letzter Arbeitstag eintragen.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))
                            else if (krankInFrist && aktiveKm != null) ...[
                              _buildInfoField(Icons.warning, 'Status', 'KRANK w\u00E4hrend K\u00FCndigungsfrist!'),
                              _buildInfoField(Icons.play_arrow, 'AU-Beginn', aktiveKm['au_beginn']?.toString()),
                              _buildInfoField(Icons.stop, 'AU-Ende', aktiveKm['au_ende']?.toString()),
                              if (aktiveKm['diagnose'] != null)
                                _buildInfoField(Icons.medical_information, 'Diagnose', aktiveKm['diagnose'].toString()),
                              const SizedBox(height: 4),
                              Text('Wichtig: K\u00FCndigung w\u00E4hrend Krankheit ist grunds\u00E4tzlich m\u00F6glich, aber K\u00FCndigungsfrist verl\u00E4ngert sich NICHT automatisch.', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.red.shade600)),
                            ] else
                              Text('Keine aktive Krankmeldung in der K\u00FCndigungsfrist gefunden.', style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    // ── Meldungen bei Kuendigung (editierbar) ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.checklist, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Text('Pflichtmeldungen bei K\u00FCndigung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                // Edit dialog for Pflichtmeldungen
                                bool kkGemeldet = ag['kk_kuendigung_gemeldet'] == true;
                                final kkDatumC = TextEditingController(text: ag['kk_kuendigung_datum']?.toString() ?? '');
                                bool afaGemeldet = ag['afa_gemeldet'] == true;
                                final afaDatumC = TextEditingController(text: ag['afa_meldung_datum']?.toString() ?? '');
                                final afaNummerC = TextEditingController(text: ag['afa_kundennummer']?.toString() ?? '');

                                showDialog(
                                  context: ctx,
                                  builder: (dlgCtx) => StatefulBuilder(
                                    builder: (dlgCtx, setDlgState) => AlertDialog(
                                      title: Row(children: [
                                        Icon(Icons.checklist, size: 18, color: Colors.blue.shade700),
                                        const SizedBox(width: 8),
                                        const Expanded(child: Text('Pflichtmeldungen bearbeiten', style: TextStyle(fontSize: 15))),
                                      ]),
                                      content: SizedBox(
                                        width: 400,
                                        child: SingleChildScrollView(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Krankenkasse
                                              SwitchListTile(
                                                title: const Text('Krankenkasse informiert?', style: TextStyle(fontSize: 13)),
                                                subtitle: const Text('K\u00FCndigung der Krankenkasse gemeldet', style: TextStyle(fontSize: 11)),
                                                value: kkGemeldet,
                                                activeTrackColor: Colors.green.shade200,
                                                activeThumbColor: Colors.green.shade700,
                                                onChanged: (v) => setDlgState(() => kkGemeldet = v),
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              if (kkGemeldet) ...[
                                                const SizedBox(height: 8),
                                                TextFormField(
                                                  controller: kkDatumC,
                                                  readOnly: true,
                                                  decoration: InputDecoration(
                                                    labelText: 'Datum Meldung Krankenkasse',
                                                    prefixIcon: const Icon(Icons.event, size: 18),
                                                    suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () async {
                                                      final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(kkDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                                      if (picked != null) { kkDatumC.text = DateFormat('yyyy-MM-dd').format(picked); setDlgState(() {}); }
                                                    }),
                                                    isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 16),
                                              const Divider(),
                                              const SizedBox(height: 8),
                                              // Agentur fuer Arbeit
                                              SwitchListTile(
                                                title: const Text('Arbeitssuchend gemeldet?', style: TextStyle(fontSize: 13)),
                                                subtitle: const Text('Bei Agentur f\u00FCr Arbeit als arbeitssuchend gemeldet', style: TextStyle(fontSize: 11)),
                                                value: afaGemeldet,
                                                activeTrackColor: Colors.green.shade200,
                                                activeThumbColor: Colors.green.shade700,
                                                onChanged: (v) => setDlgState(() => afaGemeldet = v),
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              if (afaGemeldet) ...[
                                                const SizedBox(height: 8),
                                                TextFormField(
                                                  controller: afaDatumC,
                                                  readOnly: true,
                                                  decoration: InputDecoration(
                                                    labelText: 'Datum Meldung Arbeitsagentur',
                                                    prefixIcon: const Icon(Icons.event, size: 18),
                                                    suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () async {
                                                      final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(afaDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                                      if (picked != null) { afaDatumC.text = DateFormat('yyyy-MM-dd').format(picked); setDlgState(() {}); }
                                                    }),
                                                    isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                TextFormField(
                                                  controller: afaNummerC,
                                                  decoration: InputDecoration(
                                                    labelText: 'Kundennummer Arbeitsagentur',
                                                    prefixIcon: const Icon(Icons.numbers, size: 18),
                                                    isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
                                        FilledButton.icon(
                                          icon: const Icon(Icons.save, size: 16),
                                          label: const Text('Speichern'),
                                          onPressed: () {
                                            ag['kk_kuendigung_gemeldet'] = kkGemeldet;
                                            ag['kk_kuendigung_datum'] = kkDatumC.text.isNotEmpty ? kkDatumC.text : null;
                                            ag['afa_gemeldet'] = afaGemeldet;
                                            ag['afa_meldung_datum'] = afaDatumC.text.isNotEmpty ? afaDatumC.text : null;
                                            ag['afa_kundennummer'] = afaNummerC.text.isNotEmpty ? afaNummerC.text : null;
                                            Navigator.pop(dlgCtx);
                                            _saveWithData(arbeitgeberListe, selectedArbeitgeberId);
                                            setModalState(() {});
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(6)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.edit, size: 12, color: Colors.blue.shade700),
                                  const SizedBox(width: 4),
                                  Text('Bearbeiten', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                                ]),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          // Krankenkasse status
                          Row(children: [
                            Icon(ag['kk_kuendigung_gemeldet'] == true ? Icons.check_circle : Icons.cancel, size: 14, color: ag['kk_kuendigung_gemeldet'] == true ? Colors.green.shade700 : Colors.red.shade700),
                            const SizedBox(width: 6),
                            Expanded(child: Text('Krankenkasse informiert', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ag['kk_kuendigung_gemeldet'] == true ? Colors.green.shade800 : Colors.red.shade800))),
                            if (ag['kk_kuendigung_datum'] != null)
                              Text(ag['kk_kuendigung_datum'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          ]),
                          const SizedBox(height: 6),
                          // Arbeitsagentur status
                          Row(children: [
                            Icon(ag['afa_gemeldet'] == true ? Icons.check_circle : Icons.cancel, size: 14, color: ag['afa_gemeldet'] == true ? Colors.green.shade700 : Colors.red.shade700),
                            const SizedBox(width: 6),
                            Expanded(child: Text('Arbeitssuchend gemeldet (Agentur f\u00FCr Arbeit)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ag['afa_gemeldet'] == true ? Colors.green.shade800 : Colors.red.shade800))),
                            if (ag['afa_meldung_datum'] != null)
                              Text(ag['afa_meldung_datum'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          ]),
                          if (ag['afa_kundennummer'] != null && ag['afa_kundennummer'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _buildInfoField(Icons.numbers, 'Kundennr. Arbeitsagentur', ag['afa_kundennummer'].toString()),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Wichtige Fristen & Hinweise
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber, size: 16, color: Colors.orange.shade800),
                              const SizedBox(width: 6),
                              Text('Wichtige Fristen & Hinweise', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildWarnField('\u2696\uFE0F', 'K\u00FCndigungsschutzklage', '3 Wochen ab Zustellung (\u00A74 KSchG)'),
                          _buildWarnField('\uD83D\uDCCB', 'Arbeitssuchend melden', '3 Tage bei Agentur f\u00FCr Arbeit'),
                          _buildWarnField('\u23F3', 'Sperrzeit', '12 Wochen ALG-Sperre bei Eigenk\u00FCndigung'),
                          _buildWarnField('\u270D\uFE0F', 'Schriftform', 'NUR schriftlich g\u00FCltig (\u00A7623 BGB)'),
                          _buildWarnField('\uD83D\uDCDC', 'Arbeitszeugnis', 'Anspruch auf qualifiziertes Zeugnis'),
                        ],
                      ),
                    ),
                    const Divider(height: 24),
                    Text('Dokumente', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                    const SizedBox(height: 8),
                    buildDokUploadAndList(ctx, setModalState, dokTypen['kuendigung']!, dokumente, arbeitgeberIndex),
                  ],
                ),
              );
            }

            return DefaultTabController(
              length: 7,
              child: AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.work_history, color: Colors.indigo.shade700, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ag['firma'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          if (ag['position'] != null)
                            Text(ag['position'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 650,
                  height: 500,
                  child: Column(
                    children: [
                      TabBar(
                        isScrollable: true,
                        labelColor: Colors.indigo.shade700,
                        unselectedLabelColor: Colors.grey.shade600,
                        indicatorColor: Colors.indigo,
                        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(fontSize: 12),
                        tabs: const [
                          Tab(text: 'Firmendaten'),
                          Tab(text: 'Vertrag'),
                          Tab(text: 'Lohn'),
                          Tab(text: 'Krankheit'),
                          Tab(text: 'K\u00FCndigung'),
                          Tab(text: 'Vorfall'),
                          Tab(text: 'Sonstiges'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Tab 1: Firmendaten
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (dbAg != null) ...[
                                    Text('Aus Firmendatenbank', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                                    const SizedBox(height: 8),
                                    if (dbAg['rechtsform'] != null || dbAg['branche'] != null)
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (dbAg['rechtsform'] != null)
                                            Chip(label: Text(dbAg['rechtsform'], style: const TextStyle(fontSize: 11)), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                                          if (dbAg['branche'] != null)
                                            Chip(label: Text(dbAg['branche'], style: const TextStyle(fontSize: 11)), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                                        ],
                                      ),
                                    const SizedBox(height: 8),
                                    _buildDetailRow(Icons.business, 'Firma', dbAg['firma_name'] ?? ''),
                                    if (dbAg['firma_kurz'] != null)
                                      _buildDetailRow(Icons.short_text, 'Kurzname', dbAg['firma_kurz']),
                                    // Standorte
                                    if (dbAg['hauptzentrale_ort'] != null)
                                      _buildAgStandortCard('Zentrale', dbAg, 'hauptzentrale'),
                                    if (dbAg['niederlassung_ort'] != null)
                                      _buildAgStandortCard('Niederlassung', dbAg, 'niederlassung'),
                                    if (dbAg['zweigstelle_ort'] != null)
                                      _buildAgStandortCard('Zweigstelle', dbAg, 'zweigstelle'),
                                  ] else ...[
                                    _buildDetailRow(Icons.business, 'Firma', ag['firma'] ?? ''),
                                    _buildDetailRow(Icons.badge, 'Position', ag['position'] ?? ''),
                                    if (ag['ort']?.toString().isNotEmpty == true)
                                      _buildDetailRow(Icons.location_on, 'Ort', ag['ort']),
                                    if (ag['beschreibung']?.toString().isNotEmpty == true)
                                      _buildDetailRow(Icons.description, 'Beschreibung', ag['beschreibung']),
                                  ],
                                ],
                              ),
                            ),
                            // Tab 2: Vertrag (enhanced)
                            buildVertragTab(),
                            // Tab 3: Lohn
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Lohnabrechnungen upload
                                  buildDokUploadAndList(ctx, setModalState, ['lohnabrechnung'], dokumente, arbeitgeberIndex),
                                  const SizedBox(height: 16),
                                  // Lohnsteuerbescheinigung
                                  _buildLohnsteuerSection(ctx, setModalState, ag, arbeitgeberIndex, dokumente, buildDokUploadAndList),
                                ],
                              ),
                            ),
                            // Tab 4: Krankheit (enhanced)
                            buildKrankheitTab(),
                            // Tab 5: K\u00FCndigung (enhanced)
                            buildKuendigungTab(),
                            // Tab 6: Vorfall
                            _buildVorfallTab(ag, <String, dynamic>{}, setModalState),
                            // Tab 7: Sonstiges
                            buildDokTab('sonstiges', dokTypen['sonstiges']!),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schlie\u00DFen')),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  @override
  void dispose() { _mainTabC.dispose(); super.dispose(); }

  Widget build(BuildContext context) {
    if (!_dbLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(children: [
      TabBar(controller: _mainTabC, labelColor: Colors.indigo.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.indigo, tabs: const [
        Tab(text: 'Zuständiger Arbeitgeber'),
        Tab(text: 'Stellen'),
      ]),
      Expanded(child: TabBarView(controller: _mainTabC, children: [
        _buildZustaendigerTab(),
        _buildStellenTab(),
      ])),
    ]);
  }

  Widget _buildZustaendigerTab() {
    return StatefulBuilder(builder: (ctx, setLocal) {
      final vollzeit = _arbeitgeberFromDB.where((a) => a['aktuell'] == true && (a['art']?.toString() ?? 'vollzeit') == 'vollzeit').toList();
      final teilzeit = _arbeitgeberFromDB.where((a) => a['aktuell'] == true && a['art']?.toString() == 'teilzeit').toList();
      final minijobs = _arbeitgeberFromDB.where((a) => a['aktuell'] == true && a['art']?.toString() == 'minijob').toList();

      Widget section(String label, IconData icon, MaterialColor color, List<Map<String, dynamic>> list, String artKey) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20, color: color.shade700),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800)),
            const Spacer(),
            IconButton(icon: Icon(Icons.search, color: color.shade600), tooltip: '$label auswählen', onPressed: () => _openArbeitgeberSearch(artKey, setLocal)),
          ]),
          const SizedBox(height: 6),
          if (list.isEmpty)
            Container(padding: const EdgeInsets.all(16), width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 32, color: Colors.grey.shade300),
                const SizedBox(height: 6),
                Text('Kein $label ausgewählt', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              ])))
          else ...list.map((ag) => _agCard(ag, label, color)),
          const SizedBox(height: 16),
        ]);
      }

      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        section('Vollzeit', Icons.work, Colors.indigo, vollzeit, 'vollzeit'),
        section('Teilzeit', Icons.timelapse, Colors.teal, teilzeit, 'teilzeit'),
        section('Minijob', Icons.work_outline, Colors.orange, minijobs, 'minijob'),
      ]));
    });
  }

  Widget _agCard(Map<String, dynamic> ag, String label, MaterialColor color) {
    final dbAg = ag['arbeitgeber_db_id'] != null ? widget.dbArbeitgeberListe.cast<Map<String, dynamic>?>().firstWhere((d) => d?['id'].toString() == ag['arbeitgeber_db_id'].toString(), orElse: () => null) : null;
    final firma = ag['firma']?.toString() ?? dbAg?['firma_name']?.toString() ?? '';
    final branche = dbAg?['branche']?.toString() ?? '';
    final hauptOrt = dbAg?['hauptzentrale_ort']?.toString() ?? '';
    final telefon = dbAg?['telefon']?.toString() ?? dbAg?['hauptzentrale_telefon']?.toString() ?? '';
    final email = dbAg?['email']?.toString() ?? dbAg?['hauptzentrale_email']?.toString() ?? '';
    final website = dbAg?['website']?.toString() ?? '';
    final adresse = dbAg != null ? '${dbAg['hauptzentrale_strasse'] ?? ''}, ${dbAg['hauptzentrale_plz'] ?? ''} ${dbAg['hauptzentrale_ort'] ?? ''}'.trim() : '';

    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.shade200)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () { final idx = _arbeitgeberFromDB.indexOf(ag); if (idx >= 0) _showBerufserfahrungModal(context, ag, idx, arbeitgeberListe: _arbeitgeberFromDB, selectedArbeitgeberId: _selectedArbeitgeberId); },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(12)),
              child: Icon(label == 'Minijob' ? Icons.work_outline : (label == 'Teilzeit' ? Icons.timelapse : Icons.work), color: color.shade700, size: 26)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(firma, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800)),
              if ((ag['position']?.toString() ?? '').isNotEmpty) Text(ag['position'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ])),
            Icon(Icons.chevron_right, color: color.shade400),
          ]),
          if (adresse.isNotEmpty || telefon.isNotEmpty || branche.isNotEmpty) ...[
            const Divider(height: 16),
            if (branche.isNotEmpty) _detailRow(Icons.category, branche, color),
            if (adresse.isNotEmpty) _detailRow(Icons.location_on, adresse, color),
            if ((ag['ort']?.toString() ?? '').isNotEmpty && adresse.isEmpty) _detailRow(Icons.location_on, ag['ort'].toString(), color),
            if (telefon.isNotEmpty) _detailRow(Icons.phone, telefon, color),
            if (email.isNotEmpty) _detailRow(Icons.email, email, color),
            if (website.isNotEmpty) _detailRow(Icons.language, website, color),
          ],
        ]),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, MaterialColor color) =>
    Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [Icon(icon, size: 14, color: color.shade400), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 12)))]));

  void _openArbeitgeberSearch(String art, StateSetter setLocal) {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> filtered = List.from(widget.dbArbeitgeberListe);
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
      void filter(String q) {
        if (q.isEmpty) { setDlg(() => filtered = List.from(widget.dbArbeitgeberListe)); return; }
        final l = q.toLowerCase();
        setDlg(() => filtered = widget.dbArbeitgeberListe.where((s) => (s['firma_name']?.toString() ?? '').toLowerCase().contains(l) || (s['hauptzentrale_ort']?.toString() ?? '').toLowerCase().contains(l) || (s['branche']?.toString() ?? '').toLowerCase().contains(l)).toList());
      }
      return AlertDialog(
        title: Row(children: [Icon(Icons.search, color: Colors.indigo.shade700), const SizedBox(width: 8), Text('Arbeitgeber auswählen ($art)', style: const TextStyle(fontSize: 16))]),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(controller: searchC, autofocus: true, decoration: InputDecoration(hintText: 'Filter...', prefixIcon: const Icon(Icons.search), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onChanged: filter),
          const SizedBox(height: 12),
          Expanded(child: filtered.isEmpty ? Center(child: Text('Keine Arbeitgeber gefunden', style: TextStyle(color: Colors.grey.shade400)))
            : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) { final s = filtered[i];
                return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.indigo.shade100, child: Icon(Icons.business, color: Colors.indigo.shade700, size: 20)),
                  title: Text(s['firma_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('${s['branche'] ?? ''} · ${s['hauptzentrale_ort'] ?? ''}', style: const TextStyle(fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final result = await _saveArbeitgeberToDB({
                      'firma': s['firma_name'], 'position': '', 'ort': s['hauptzentrale_ort'] ?? '',
                      'aktuell': true, 'art': art, 'arbeitgeber_db_id': s['id'],
                      'von_monat': DateTime.now().month.toString().padLeft(2, '0'), 'von_jahr': DateTime.now().year.toString(),
                    });
                    await _loadArbeitgeberFromDB();
                    setLocal(() {});
                  },
                )); })),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))]);
    }));
  }

  Widget _buildStellenTab() {
    // DB is now the primary source
    List<Map<String, dynamic>> arbeitgeber = List<Map<String, dynamic>>.from(_arbeitgeberFromDB);
    String selectedArbeitgeberId = _selectedArbeitgeberId;

    return StatefulBuilder(
      builder: (context, setLocalState) {

        // Find selected DB employer
        Map<String, dynamic>? selectedDbAg;
        if (selectedArbeitgeberId.isNotEmpty) {
          selectedDbAg = widget.dbArbeitgeberListe.cast<Map<String, dynamic>?>().firstWhere(
            (ag) => ag?['id'].toString() == selectedArbeitgeberId,
            orElse: () => null,
          );
        }

        void saveArbeitgeber() {
          _saveArbeitgeber(arbeitgeber, selectedArbeitgeberId);
        }

        void showArbeitgeberDialog({Map<String, dynamic>? existing, int? index, String defaultArt = 'vollzeit'}) {
          final firmaController = TextEditingController(text: existing?['firma'] ?? '');
          final positionController = TextEditingController(text: existing?['position'] ?? '');
          final ortController = TextEditingController(text: existing?['ort'] ?? '');
          final beschreibungController = TextEditingController(text: existing?['beschreibung'] ?? '');
          final aufgabe1Controller = TextEditingController(text: existing?['aufgabe1'] ?? '');
          final aufgabe2Controller = TextEditingController(text: existing?['aufgabe2'] ?? '');
          final aufgabe3Controller = TextEditingController(text: existing?['aufgabe3'] ?? '');
          String art = existing?['art']?.toString() ?? defaultArt;
          String vonMonat = existing?['von_monat']?.toString() ?? '';
          String vonJahr = existing?['von_jahr']?.toString() ?? '';
          String bisMonat = existing?['bis_monat']?.toString() ?? '';
          String bisJahr = existing?['bis_jahr']?.toString() ?? '';
          bool aktuell = existing?['aktuell'] == true || existing?['aktuell'] == 'true';
          int? selectedDbId = existing?['arbeitgeber_db_id'] != null ? int.tryParse(existing!['arbeitgeber_db_id'].toString()) : null;

          final monate = {
            '': '\u2013', '01': 'Jan', '02': 'Feb', '03': 'M\u00E4r', '04': 'Apr',
            '05': 'Mai', '06': 'Jun', '07': 'Jul', '08': 'Aug',
            '09': 'Sep', '10': 'Okt', '11': 'Nov', '12': 'Dez',
          };
          final jahre = List.generate(40, (i) => (DateTime.now().year - i).toString());

          showDialog(
            context: context,
            builder: (ctx) => StatefulBuilder(
              builder: (ctx, setDialogState) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.factory, color: Colors.indigo.shade700, size: 22),
                    const SizedBox(width: 8),
                    Text(existing != null ? 'Arbeitgeber bearbeiten' : 'Neuer Arbeitgeber', style: const TextStyle(fontSize: 16)),
                  ],
                ),
                content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Beschäftigungsart
                        Text('Beschäftigungsart:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, children: [
                          for (final a in [('vollzeit', 'Vollzeit', Icons.work), ('minijob', 'Minijob', Icons.work_outline), ('teilzeit', 'Teilzeit', Icons.timelapse), ('werkstudent', 'Werkstudent', Icons.school), ('ausbildung', 'Ausbildung', Icons.menu_book), ('praktikum', 'Praktikum', Icons.explore)])
                            ChoiceChip(
                              avatar: Icon(a.$3, size: 14, color: art == a.$1 ? Colors.white : Colors.grey.shade700),
                              label: Text(a.$2, style: TextStyle(fontSize: 11, color: art == a.$1 ? Colors.white : Colors.black87)),
                              selected: art == a.$1,
                              selectedColor: art == 'minijob' ? Colors.orange.shade600 : Colors.indigo.shade600,
                              onSelected: (_) => setDialogState(() => art = a.$1),
                            ),
                        ]),
                        const SizedBox(height: 16),
                        // Firma aus Datenbank ausw\u00E4hlen
                        if (widget.dbArbeitgeberListe.isNotEmpty) ...[
                          Text('Aus Firmendatenbank w\u00E4hlen:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
                          const SizedBox(height: 6),
                          Autocomplete<Map<String, dynamic>>(
                            initialValue: TextEditingValue(text: firmaController.text),
                            optionsBuilder: (textEditingValue) {
                              if (textEditingValue.text.isEmpty) return widget.dbArbeitgeberListe;
                              final query = textEditingValue.text.toLowerCase();
                              return widget.dbArbeitgeberListe.where((ag) {
                                final name = (ag['firma_name'] ?? '').toString().toLowerCase();
                                final kurz = (ag['firma_kurz'] ?? '').toString().toLowerCase();
                                return name.contains(query) || kurz.contains(query);
                              });
                            },
                            displayStringForOption: (ag) => ag['firma_name'] ?? '',
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(8),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 250, maxWidth: 480),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (ctx, i) {
                                        final ag = options.elementAt(i);
                                        final ort = ag['zweigstelle_ort'] ?? ag['niederlassung_ort'] ?? ag['hauptzentrale_ort'] ?? '';
                                        return ListTile(
                                          dense: true,
                                          leading: Icon(Icons.business, size: 18, color: Colors.indigo.shade400),
                                          title: Text(ag['firma_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                          subtitle: Text(
                                            '${ag['branche'] ?? ''}${ort.isNotEmpty ? ' \u00B7 $ort' : ''}',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                          onTap: () => onSelected(ag),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                            fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                onEditingComplete: onEditingComplete,
                                decoration: InputDecoration(
                                  labelText: 'Firma / Unternehmen *',
                                  hintText: 'Tippen zum Suchen...',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  suffixIcon: controller.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            controller.clear();
                                            setDialogState(() {
                                              firmaController.text = '';
                                              selectedDbId = null;
                                            });
                                          },
                                        )
                                      : null,
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                style: const TextStyle(fontSize: 14),
                                onChanged: (val) {
                                  firmaController.text = val;
                                  if (selectedDbId != null) {
                                    setDialogState(() => selectedDbId = null);
                                  }
                                },
                              );
                            },
                            onSelected: (ag) {
                              setDialogState(() {
                                firmaController.text = ag['firma_name'] ?? '';
                                selectedDbId = int.tryParse(ag['id'].toString());
                                final autoOrt = ag['zweigstelle_ort'] ?? ag['niederlassung_ort'] ?? ag['hauptzentrale_ort'] ?? '';
                                if (autoOrt.isNotEmpty && ortController.text.isEmpty) {
                                  ortController.text = autoOrt;
                                }
                              });
                            },
                          ),
                          if (selectedDbId != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
                                  const SizedBox(width: 4),
                                  Text('Aus Datenbank ausgew\u00E4hlt', style: TextStyle(fontSize: 11, color: Colors.green.shade600)),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                        ] else ...[
                          TextField(
                            controller: firmaController,
                            decoration: InputDecoration(
                              labelText: 'Firma / Unternehmen *',
                              prefixIcon: const Icon(Icons.business, size: 20),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Autocomplete<Map<String, dynamic>>(
                          initialValue: TextEditingValue(text: positionController.text),
                          optionsBuilder: (textEditingValue) {
                            if (_berufsbezeichnungen.isEmpty) return [];
                            if (textEditingValue.text.isEmpty) return _berufsbezeichnungen;
                            final query = textEditingValue.text.toLowerCase();
                            return _berufsbezeichnungen.where((b) =>
                              (b['bezeichnung'] ?? '').toString().toLowerCase().contains(query) ||
                              (b['kategorie'] ?? '').toString().toLowerCase().contains(query));
                          },
                          displayStringForOption: (b) => b['bezeichnung'] ?? '',
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(8),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 250, maxWidth: 480),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (ctx, i) {
                                      final b = options.elementAt(i);
                                      return ListTile(
                                        dense: true,
                                        leading: Icon(Icons.badge, size: 18, color: Colors.amber.shade700),
                                        title: Text(b['bezeichnung'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                        subtitle: Text(b['kategorie'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                        onTap: () => onSelected(b),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            positionController.text = controller.text;
                            controller.addListener(() => positionController.text = controller.text);
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: 'Position / Berufsbezeichnung *',
                                prefixIcon: const Icon(Icons.badge, size: 20),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                hintText: 'Tippen zum Suchen...',
                                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                              ),
                              style: const TextStyle(fontSize: 14),
                            );
                          },
                          onSelected: (b) {
                            positionController.text = b['bezeichnung'] ?? '';
                            if ((b['aufgabe1'] ?? '').toString().isNotEmpty) aufgabe1Controller.text = b['aufgabe1'];
                            if ((b['aufgabe2'] ?? '').toString().isNotEmpty) aufgabe2Controller.text = b['aufgabe2'];
                            if ((b['aufgabe3'] ?? '').toString().isNotEmpty) aufgabe3Controller.text = b['aufgabe3'];
                            setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: ortController,
                          decoration: InputDecoration(
                            labelText: 'Ort / Stadt',
                            prefixIcon: const Icon(Icons.location_city, size: 20),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        Text('Besch\u00E4ftigt von', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: monate.containsKey(vonMonat) ? vonMonat : '',
                                decoration: InputDecoration(labelText: 'Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                items: monate.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                                onChanged: (v) => setDialogState(() => vonMonat = v ?? ''),
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: jahre.contains(vonJahr) ? vonJahr : null,
                                decoration: InputDecoration(labelText: 'Jahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                items: jahre.map((y) => DropdownMenuItem(value: y, child: Text(y, style: const TextStyle(fontSize: 13)))).toList(),
                                onChanged: (v) => setDialogState(() => vonJahr = v ?? ''),
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text('Besch\u00E4ftigt bis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                            const Spacer(),
                            Text('Aktuell', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            const SizedBox(width: 4),
                            Switch(
                              value: aktuell,
                              activeTrackColor: Colors.green.shade200,
                              onChanged: (v) => setDialogState(() => aktuell = v),
                            ),
                          ],
                        ),
                        if (!aktuell) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: monate.containsKey(bisMonat) ? bisMonat : '',
                                  decoration: InputDecoration(labelText: 'Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                  items: monate.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                                  onChanged: (v) => setDialogState(() => bisMonat = v ?? ''),
                                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: jahre.contains(bisJahr) ? bisJahr : null,
                                  decoration: InputDecoration(labelText: 'Jahr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                  items: jahre.map((y) => DropdownMenuItem(value: y, child: Text(y, style: const TextStyle(fontSize: 13)))).toList(),
                                  onChanged: (v) => setDialogState(() => bisJahr = v ?? ''),
                                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text('Tätigkeiten / Aufgaben', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: aufgabe1Controller,
                          decoration: InputDecoration(
                            labelText: 'Aufgabe 1',
                            prefixIcon: const Icon(Icons.task_alt, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: aufgabe2Controller,
                          decoration: InputDecoration(
                            labelText: 'Aufgabe 2',
                            prefixIcon: const Icon(Icons.task_alt, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: aufgabe3Controller,
                          decoration: InputDecoration(
                            labelText: 'Aufgabe 3',
                            prefixIcon: const Icon(Icons.task_alt, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (firmaController.text.trim().isEmpty || positionController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Firma und Position sind Pflichtfelder'), backgroundColor: Colors.red),
                        );
                        return;
                      }
                      final entry = {
                        if (existing?['id'] != null) 'id': existing!['id'],
                        'firma': firmaController.text.trim(),
                        'art': art,
                        'position': positionController.text.trim(),
                        'funktion': positionController.text.trim(),
                        'ort': ortController.text.trim(),
                        'von_monat': vonMonat,
                        'von_jahr': vonJahr,
                        'bis_monat': bisMonat,
                        'bis_jahr': bisJahr,
                        'aktuell': aktuell,
                        'beschreibung': beschreibungController.text.trim(),
                        'aufgabe1': aufgabe1Controller.text.trim(),
                        'aufgabe2': aufgabe2Controller.text.trim(),
                        'aufgabe3': aufgabe3Controller.text.trim(),
                        if (selectedDbId != null) 'arbeitgeber_db_id': selectedDbId,
                      };
                      // Save to DB and get ID
                      try {
                        final result = await widget.apiService.saveBerufserfahrung(widget.user.id, entry);
                        if (result['success'] == true && result['id'] != null) {
                          entry['id'] = result['id'];
                        }
                      } catch (_) {}
                      if (!ctx.mounted) return;
                      setLocalState(() {
                        if (index != null) {
                          // Preserve existing fields not in dialog
                          final old = arbeitgeber[index];
                          for (final k in old.keys) {
                            if (!entry.containsKey(k)) entry[k] = old[k];
                          }
                          arbeitgeber[index] = entry;
                        } else {
                          arbeitgeber.insert(0, entry);
                        }
                      });
                      _loadArbeitgeberFromDB(); // Reload from DB
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Speichern'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          );
        }

        String zeitraum(Map<String, dynamic> ag) {
          final vm = ag['von_monat']?.toString() ?? '';
          final vj = ag['von_jahr']?.toString() ?? '';
          final von = vm.isNotEmpty && vj.isNotEmpty ? '$vm/$vj' : vj;
          if (ag['aktuell'] == true || ag['aktuell'] == 'true') return '$von \u2013 heute';
          final bm = ag['bis_monat']?.toString() ?? '';
          final bj = ag['bis_jahr']?.toString() ?? '';
          final bis = bm.isNotEmpty && bj.isNotEmpty ? '$bm/$bj' : bj;
          return '$von \u2013 $bis';
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ══════════════════════════════════════
              // ── MINDESTLOHN & IGZ TARIF ──
              // ══════════════════════════════════════
              Builder(builder: (context) {
                final jahr = DateTime.now().year;
                // Gesetzlicher Mindestlohn Deutschland (pro Stunde)
                const mindestlohnTabelle = {
                  2015: 8.50, 2016: 8.50, 2017: 8.84, 2018: 8.84,
                  2019: 9.19, 2020: 9.35, 2021: 9.60, 2022: 12.00,
                  2023: 12.00, 2024: 12.41, 2025: 12.82, 2026: 12.82,
                };
                // iGZ/BAP Tarifvertrag Zeitarbeit -- Entgeltgruppe 1 (Einsteiger, West)
                const igzTabelle = {
                  2020: 10.15, 2021: 10.45, 2022: 10.88, 2023: 13.00,
                  2024: 13.50, 2025: 14.00, 2026: 14.00,
                };
                // iGZ Entgeltgruppen 2-9 (2025/2026 West)
                const igzGruppen = {
                  'EG 1': 14.00, 'EG 2': 14.53,
                  'EG 3': 15.28, 'EG 4': 16.44,
                  'EG 5': 18.34, 'EG 6': 19.38,
                  'EG 7': 21.14, 'EG 8': 23.33,
                  'EG 9': 26.39,
                };
                final mindestlohn = mindestlohnTabelle[jahr] ?? mindestlohnTabelle.values.last;
                final igzEg1 = igzTabelle[jahr] ?? igzTabelle.values.last;

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.amber.shade50, Colors.orange.shade50], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.euro, color: Colors.amber.shade800, size: 20),
                          const SizedBox(width: 6),
                          Text('Lohn-\u00DCbersicht $jahr', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Mindestlohn row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade300)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.gavel, size: 14, color: Colors.green.shade700),
                                const SizedBox(width: 4),
                                Text('Mindestlohn', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('${mindestlohn.toStringAsFixed(2)} \u20AC / Std.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                          const Spacer(),
                          Text('(gesetzlich, brutto)', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // IGZ row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.indigo.shade300)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.groups, size: 14, color: Colors.indigo.shade700),
                                const SizedBox(width: 4),
                                Text('iGZ/BAP Tarif', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo.shade800)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('ab ${igzEg1.toStringAsFixed(2)} \u20AC / Std.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                          const Spacer(),
                          Text('(EG 1, Zeitarbeit West)', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // IGZ Entgeltgruppen expandable
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 4),
                        dense: true,
                        title: Text('Alle iGZ Entgeltgruppen $jahr (West)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
                        leading: Icon(Icons.table_chart, size: 16, color: Colors.indigo.shade400),
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: igzGruppen.entries.map((e) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.indigo.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Text(e.key, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.indigo.shade600)),
                                    Text('${e.value.toStringAsFixed(2)} \u20AC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              // ══════════════════════════════════════
              // ── AKTUELLER ARBEITGEBER AUSW\u00C4HLEN ──
              // ══════════════════════════════════════
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.blue.shade50, Colors.blue.shade100], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.business, color: Colors.blue.shade700, size: 22),
                        const SizedBox(width: 8),
                        Text('Aktueller Arbeitgeber', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('ag_dd_${selectedArbeitgeberId}_${widget.dbArbeitgeberListe.length}'),
                      initialValue: selectedArbeitgeberId.isNotEmpty && widget.dbArbeitgeberListe.any((ag) => ag['id'].toString() == selectedArbeitgeberId)
                          ? selectedArbeitgeberId
                          : (selectedArbeitgeberId.isEmpty ? null : ''),
                      decoration: InputDecoration(
                        labelText: 'Arbeitgeber ausw\u00E4hlen',
                        prefixIcon: const Icon(Icons.factory, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: [
                        const DropdownMenuItem<String>(value: '', child: Text('\u2013 Kein Arbeitgeber \u2013', style: TextStyle(fontSize: 13, color: Colors.grey))),
                        ...widget.dbArbeitgeberListe.map((ag) {
                          final name = ag['firma_kurz'] ?? ag['firma_name'] ?? '';
                          final ort = ag['zweigstelle_ort'] ?? ag['niederlassung_ort'] ?? ag['hauptzentrale_ort'] ?? '';
                          return DropdownMenuItem<String>(
                            value: ag['id'].toString(),
                            child: Text('$name${ort.isNotEmpty ? ' ($ort)' : ''}', style: const TextStyle(fontSize: 13)),
                          );
                        }),
                      ],
                      onChanged: (v) {
                        setLocalState(() {
                          selectedArbeitgeberId = v ?? '';
                        });
                        saveArbeitgeber();
                      },
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    // Show selected employer card
                    if (selectedDbAg != null) ...[
                      const SizedBox(height: 12),
                      Builder(builder: (context) {
                        final ag = selectedDbAg!;
                        return InkWell(
                          onTap: () {
                            final fakeAg = {
                              'firma': ag['firma_name'] ?? '',
                              'position': '',
                              'ort': ag['zweigstelle_ort'] ?? ag['hauptzentrale_ort'] ?? '',
                              'arbeitgeber_db_id': ag['id'],
                              'aktuell': true,
                            };
                            _showBerufserfahrungModal(context, fakeAg, -1, arbeitgeberListe: arbeitgeber, selectedArbeitgeberId: selectedArbeitgeberId);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.verified, size: 18, color: Colors.indigo.shade600),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(ag['firma_name'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                                      if (ag['branche'] != null)
                                        Text(ag['branche'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      if (ag['zweigstelle_ort'] != null)
                                        Text('Zust\u00E4ndig: Zweigstelle ${ag['zweigstelle_ort']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.open_in_new, size: 16, color: Colors.indigo.shade400),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ══════════════════════════════════════
              // ── BERUFSERFAHRUNG ──
              // ══════════════════════════════════════

              Builder(builder: (_) {
                final vollzeitList = arbeitgeber.where((a) => (a['art']?.toString() ?? 'vollzeit') != 'minijob').toList();
                final minijobList = arbeitgeber.where((a) => a['art']?.toString() == 'minijob').toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── VOLLZEIT SECTION ──
              Row(
                children: [
                  Icon(Icons.work, color: Colors.indigo.shade700, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Arbeitgeber — Vollzeit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
                  ElevatedButton.icon(
                    onPressed: () => LebenslaufGenerator.showLebenslaufDialog(context, widget.apiService, widget.user.id),
                    icon: const Icon(Icons.description, size: 16),
                    label: const Text('Lebenslauf', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => showArbeitgeberDialog(defaultArt: 'vollzeit'),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Hinzufügen', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (vollzeitList.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                  child: Column(children: [
                    Icon(Icons.work_off, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 6),
                    Text('Kein Vollzeit-Arbeitgeber eingetragen', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ]),
                )
              else
                ...vollzeitList.asMap().entries.map((entry) {
                  final ag = entry.value;
                  final i = arbeitgeber.indexOf(ag);
                  final isAktuell = ag['aktuell'] == true || ag['aktuell'] == 'true';
                  return InkWell(
                    onTap: () => _showBerufserfahrungModal(context, ag, i, arbeitgeberListe: arbeitgeber, selectedArbeitgeberId: selectedArbeitgeberId),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isAktuell ? Colors.green.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isAktuell ? Colors.green.shade300 : Colors.grey.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Timeline dot + line
                          Column(
                            children: [
                              Container(
                                width: 12, height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isAktuell ? Colors.green : Colors.indigo.shade300,
                                  border: Border.all(color: isAktuell ? Colors.green.shade700 : Colors.indigo, width: 2),
                                ),
                              ),
                              if (i < arbeitgeber.length - 1)
                                Container(width: 2, height: 40, color: Colors.grey.shade300),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(zeitraum(ag), style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(ag['firma'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    ),
                                    if (ag['arbeitgeber_db_id'] != null)
                                      Container(
                                        margin: const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(10)),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.verified, size: 10, color: Colors.indigo.shade600),
                                            const SizedBox(width: 2),
                                            Text('DB', style: TextStyle(fontSize: 9, color: Colors.indigo.shade700, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    if (isAktuell)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(10)),
                                        child: const Text('Aktuell', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                                if (ag['ort']?.toString().isNotEmpty == true) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.location_on, size: 12, color: Colors.grey.shade500),
                                      const SizedBox(width: 2),
                                      Text(ag['ort'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Action buttons
                          Column(
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, size: 16, color: Colors.indigo.shade400),
                                onPressed: () => showArbeitgeberDialog(existing: ag, index: i),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Bearbeiten',
                              ),
                              const SizedBox(height: 4),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                                onPressed: () async {
                                  final agId = int.tryParse(ag['id']?.toString() ?? '');
                                  if (agId != null) await _deleteArbeitgeberFromDB(agId);
                                  setLocalState(() => arbeitgeber.removeAt(i));
                                  saveArbeitgeber();
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'L\u00F6schen',
                              ),
                              if (i > 0) ...[
                                const SizedBox(height: 4),
                                IconButton(
                                  icon: Icon(Icons.arrow_upward, size: 16, color: Colors.grey.shade500),
                                  onPressed: () {
                                    setLocalState(() {
                                      final item = arbeitgeber.removeAt(i);
                                      arbeitgeber.insert(i - 1, item);
                                    });
                                    saveArbeitgeber();
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Nach oben',
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),

              // ── MINIJOB SECTION ──
              Row(
                children: [
                  Icon(Icons.work_outline, color: Colors.orange.shade700, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Arbeitgeber — Minijob', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade700))),
                  ElevatedButton.icon(
                    onPressed: () => showArbeitgeberDialog(defaultArt: 'minijob'),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Minijob hinzufügen', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (minijobList.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
                  child: Column(children: [
                    Icon(Icons.work_outline, size: 40, color: Colors.orange.shade300),
                    const SizedBox(height: 6),
                    Text('Kein Minijob eingetragen', style: TextStyle(fontSize: 13, color: Colors.orange.shade400)),
                  ]),
                )
              else
                ...minijobList.asMap().entries.map((entry) {
                  final ag = entry.value;
                  final i = arbeitgeber.indexOf(ag);
                  final isAktuell = ag['aktuell'] == true || ag['aktuell'] == 'true';
                  return InkWell(
                    onTap: () => _showBerufserfahrungModal(context, ag, i, arbeitgeberListe: arbeitgeber, selectedArbeitgeberId: selectedArbeitgeberId),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isAktuell ? Colors.orange.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isAktuell ? Colors.orange.shade300 : Colors.grey.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(children: [
                            Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isAktuell ? Colors.orange : Colors.orange.shade300,
                                border: Border.all(color: isAktuell ? Colors.orange.shade700 : Colors.orange, width: 2),
                              ),
                            ),
                          ]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                                    child: Text('MINIJOB', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                                  ),
                                  const SizedBox(width: 6),
                                  if (isAktuell)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(6)),
                                      child: Text('AKTUELL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                                    ),
                                ]),
                                const SizedBox(height: 4),
                                Text(ag['firma']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                                if ((ag['position']?.toString() ?? '').isNotEmpty)
                                  Text(ag['position'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                Row(children: [
                                  Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${ag['von_monat'] ?? ''}/${ag['von_jahr'] ?? ''} – ${isAktuell ? 'heute' : '${ag['bis_monat'] ?? ''}/${ag['bis_jahr'] ?? ''}'}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                          Column(children: [
                            IconButton(
                              icon: Icon(Icons.edit, size: 16, color: Colors.orange.shade400),
                              onPressed: () => showArbeitgeberDialog(existing: ag, index: i, defaultArt: 'minijob'),
                              padding: EdgeInsets.zero, constraints: const BoxConstraints(), tooltip: 'Bearbeiten',
                            ),
                            const SizedBox(height: 4),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                              onPressed: () async {
                                final agId = int.tryParse(ag['id']?.toString() ?? '');
                                if (agId != null) await _deleteArbeitgeberFromDB(agId);
                                setLocalState(() => arbeitgeber.removeAt(i));
                                saveArbeitgeber();
                              },
                              padding: EdgeInsets.zero, constraints: const BoxConstraints(), tooltip: 'Löschen',
                            ),
                          ]),
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),

                ]); // end Column inside Builder
              }), // end Builder

              // ══════════════════════════════════════
              // ── QUALIFIKATIONEN (Führerschein, Sprachen, Schulabschluss) ──
              // ══════════════════════════════════════
              _QualifikationenSection(apiService: widget.apiService, userId: widget.user.id),
            ],
          ),
        );
      },
    );
  }

  /// Lohnsteuerbescheinigung section — tracks per year, reminder if missing after Feb
  Widget _buildLohnsteuerSection(BuildContext ctx, StateSetter setModalState, Map<String, dynamic> ag, int arbeitgeberIndex, List<Map<String, dynamic>> dokumente, Widget Function(BuildContext, StateSetter, List<String>, List<Map<String, dynamic>>, int) buildDokUploadAndList) {
    List<Map<String, dynamic>> bescheinigungen = [];
    final raw = ag['lohnsteuerbescheinigungen'];
    if (raw is List) {
      bescheinigungen = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    final now = DateTime.now();
    final lastYear = now.year - 1;
    final hasLastYear = bescheinigungen.any((b) => b['jahr']?.toString() == lastYear.toString());
    final isOverdue = !hasLastYear && now.isAfter(DateTime(now.year, 3, 1));

    void save() {
      ag['lohnsteuerbescheinigungen'] = List<Map<String, dynamic>>.from(bescheinigungen);
      // Save to DB
      _saveArbeitgeberToDB(ag);
    }

    void showAddDialog() {
      final jahrC = TextEditingController(text: lastYear.toString());
      final erhaltenAmC = TextEditingController();
      final notizenC = TextEditingController();

      showDialog(
        context: ctx,
        builder: (dlgCtx) => AlertDialog(
          title: Row(children: [
            Icon(Icons.description, size: 18, color: Colors.purple.shade700),
            const SizedBox(width: 8),
            const Text('Lohnsteuerbescheinigung hinzufügen', style: TextStyle(fontSize: 14)),
          ]),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: jahrC,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Jahr *',
                    prefixIcon: Icon(Icons.calendar_today, size: 18, color: Colors.purple.shade600),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. $lastYear',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: erhaltenAmC,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Erhalten am',
                    prefixIcon: Icon(Icons.event, size: 18, color: Colors.green.shade600),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.edit_calendar, size: 16),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dlgCtx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2099),
                          locale: const Locale('de'),
                        );
                        if (picked != null) {
                          erhaltenAmC.text = DateFormat('dd.MM.yyyy').format(picked);
                        }
                      },
                    ),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    helperText: 'Leer lassen wenn noch nicht erhalten',
                    helperStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 12),
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
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              onPressed: () {
                if (jahrC.text.trim().isEmpty) return;
                Navigator.pop(dlgCtx);
                setModalState(() {
                  bescheinigungen.add({
                    'jahr': jahrC.text.trim(),
                    'erhalten': erhaltenAmC.text.isNotEmpty,
                    'erhalten_am': erhaltenAmC.text.trim(),
                    'notizen': notizenC.text.trim(),
                  });
                  bescheinigungen.sort((a, b) => (int.tryParse(b['jahr'].toString()) ?? 0).compareTo(int.tryParse(a['jahr'].toString()) ?? 0));
                });
                save();
              },
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Hinzufügen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }

    void showDetailDialog(int index) {
      final b = bescheinigungen[index];
      List<Map<String, dynamic>> detailDoks = List<Map<String, dynamic>>.from(dokumente);
      bool detailDoksLoaded = false;
      showDialog(
        context: ctx,
        builder: (dlgCtx) => StatefulBuilder(
          builder: (dlgCtx, setDlgState) {
            // Load docs from server once
            if (!detailDoksLoaded) {
              detailDoksLoaded = true;
              widget.apiService.getArbeitgeberDokumente(widget.user.id, arbeitgeberIndex).then((result) {
                if (result['dokumente'] is List && dlgCtx.mounted) {
                  setDlgState(() {
                    detailDoks = List<Map<String, dynamic>>.from(
                      (result['dokumente'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
                    );
                  });
                }
              });
            }
            final erhalten = b['erhalten'] == true || b['erhalten'] == 'true';
            return AlertDialog(
              title: Row(children: [
                Icon(Icons.description, size: 18, color: Colors.purple.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text('Lohnsteuerbescheinigung ${b['jahr']}', style: const TextStyle(fontSize: 14))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: erhalten ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(erhalten ? 'Erhalten' : 'Ausstehend',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: erhalten ? Colors.green.shade800 : Colors.orange.shade800)),
                ),
              ]),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info
                      if ((b['erhalten_am']?.toString() ?? '').isNotEmpty)
                        _lsInfoRow(Icons.event, 'Erhalten am', b['erhalten_am'].toString()),
                      if ((b['notizen']?.toString() ?? '').isNotEmpty)
                        _lsInfoRow(Icons.note, 'Notizen', b['notizen'].toString()),
                      const SizedBox(height: 12),

                      // Mark as received
                      if (!erhalten) ...[
                        ElevatedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dlgCtx,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2099),
                              locale: const Locale('de'),
                            );
                            if (picked != null) {
                              setDlgState(() {
                                b['erhalten'] = true;
                                b['erhalten_am'] = DateFormat('dd.MM.yyyy').format(picked);
                              });
                              setModalState(() {});
                              save();
                            }
                          },
                          icon: Icon(Icons.check_circle, size: 16, color: Colors.green.shade100),
                          label: const Text('Als erhalten markieren', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Document upload
                      Text('Dokument hochladen:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                      const SizedBox(height: 8),
                      // Bereits hochgeladene Lohnsteuerbescheinigungen
                      ...detailDoks.where((d) => d['dok_typ'] == 'lohnsteuerbescheinigung').map((d) {
                        final docId = int.tryParse(d['id']?.toString() ?? '');
                        final fileName = d['dok_titel']?.toString() ?? d['original_name']?.toString() ?? 'Dokument';
                        final ext = fileName.split('.').last.toLowerCase();
                        final isImage = ['jpg', 'jpeg', 'png'].contains(ext);
                        final isPdf = ext == 'pdf';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isPdf ? Icons.picture_as_pdf : (isImage ? Icons.image : Icons.insert_drive_file),
                                size: 18,
                                color: isPdf ? Colors.red.shade600 : (isImage ? Colors.blue.shade600 : Colors.purple.shade600),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(fileName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                                    Text(d['dok_datum']?.toString() ?? '', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                                  ],
                                ),
                              ),
                              // View button
                              if (docId != null)
                                IconButton(
                                  icon: Icon(Icons.visibility, size: 16, color: Colors.blue.shade600),
                                  tooltip: 'Ansehen',
                                  onPressed: () async {
                                    try {
                                      final response = await widget.apiService.downloadArbeitgeberDokument(docId);
                                      if (response.statusCode == 200 && dlgCtx.mounted) {
                                        final bytes = response.bodyBytes;
                                        if (isImage) {
                                          showDialog(
                                            context: dlgCtx,
                                            barrierDismissible: true,
                                            builder: (imgCtx) {
                                              final transformController = TransformationController();
                                              return StatefulBuilder(
                                                builder: (imgCtx, setImgState) {
                                                  return Dialog(
                                                    insetPadding: const EdgeInsets.all(20),
                                                    child: Column(
                                                      children: [
                                                        // Header bar
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                          decoration: BoxDecoration(
                                                            color: Colors.grey.shade900,
                                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              Icon(Icons.image, size: 18, color: Colors.blue.shade300),
                                                              const SizedBox(width: 8),
                                                              Expanded(child: Text(fileName, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                                                              // Zoom controls
                                                              IconButton(
                                                                icon: const Icon(Icons.zoom_out, size: 20, color: Colors.white70),
                                                                tooltip: 'Verkleinern',
                                                                onPressed: () {
                                                                  final current = transformController.value.clone();
                                                                  final scale = current.getMaxScaleOnAxis();
                                                                  if (scale > 0.5) {
                                                                    transformController.value = Matrix4.diagonal3Values(scale * 0.75, scale * 0.75, 1.0);
                                                                  }
                                                                },
                                                              ),
                                                              IconButton(
                                                                icon: const Icon(Icons.fit_screen, size: 20, color: Colors.white70),
                                                                tooltip: 'Zurücksetzen',
                                                                onPressed: () => transformController.value = Matrix4.identity(),
                                                              ),
                                                              IconButton(
                                                                icon: const Icon(Icons.zoom_in, size: 20, color: Colors.white70),
                                                                tooltip: 'Vergrößern',
                                                                onPressed: () {
                                                                  final current = transformController.value.clone();
                                                                  final scale = current.getMaxScaleOnAxis();
                                                                  if (scale < 5.0) {
                                                                    transformController.value = Matrix4.diagonal3Values(scale * 1.5, scale * 1.5, 1.0);
                                                                  }
                                                                },
                                                              ),
                                                              const SizedBox(width: 8),
                                                              IconButton(
                                                                icon: const Icon(Icons.close, size: 20, color: Colors.white),
                                                                tooltip: 'Schließen',
                                                                onPressed: () => Navigator.pop(imgCtx),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        // Image viewer
                                                        Expanded(
                                                          child: Container(
                                                            color: Colors.black87,
                                                            child: ClipRect(
                                                              child: InteractiveViewer(
                                                                transformationController: transformController,
                                                                constrained: false,
                                                                minScale: 0.3,
                                                                maxScale: 5.0,
                                                                boundaryMargin: const EdgeInsets.all(double.infinity),
                                                                child: Image.memory(bytes),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        } else if (isPdf) {
                                          final tempDir = await getTemporaryDirectory();
                                          final tempFile = File('${tempDir.path}/lsb_preview_$docId.pdf');
                                          await tempFile.writeAsBytes(bytes);
                                          if (dlgCtx.mounted) {
                                            showDialog(
                                              context: dlgCtx,
                                              builder: (_) => FileViewerDialog(filePath: tempFile.path, fileName: fileName),
                                            );
                                          }
                                        }
                                      }
                                    } catch (e) {
                                      if (dlgCtx.mounted) {
                                        ScaffoldMessenger.of(dlgCtx).showSnackBar(
                                          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                                        );
                                      }
                                    }
                                  },
                                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                  padding: EdgeInsets.zero,
                                ),
                              // Delete button
                              if (docId != null)
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade500),
                                  tooltip: 'Löschen',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: dlgCtx,
                                      builder: (cCtx) => AlertDialog(
                                        title: const Text('Dokument löschen?', style: TextStyle(fontSize: 15)),
                                        content: Text(fileName),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(cCtx, false), child: const Text('Abbrechen')),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(cCtx, true),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await widget.apiService.deleteArbeitgeberDokument(docId);
                                      final reloaded = await widget.apiService.getArbeitgeberDokumente(widget.user.id, arbeitgeberIndex);
                                      final newDoks = List<Map<String, dynamic>>.from(
                                        (reloaded['dokumente'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
                                      );
                                      setDlgState(() => detailDoks = newDoks);
                                      dokumente.clear();
                                      dokumente.addAll(newDoks);
                                      setModalState(() {});
                                    }
                                  },
                                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 6),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final picked = await FilePickerHelper.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                          );
                          if (picked == null || picked.files.isEmpty) return;
                          final file = picked.files.first;
                          if (file.path == null) return;
                          final datum = DateFormat('yyyy-MM-dd').format(DateTime.now());
                          try {
                            final result = await widget.apiService.uploadArbeitgeberDokument(
                              userId: widget.user.id,
                              arbeitgeberIndex: arbeitgeberIndex,
                              dokTyp: 'lohnsteuerbescheinigung',
                              dokDatum: datum,
                              dokTitel: 'Lohnsteuerbescheinigung ${b['jahr']} - ${file.name}',
                              filePath: file.path!,
                              fileName: file.name,
                            );
                            debugPrint('Upload result: $result');
                            if (result['success'] == true && dlgCtx.mounted) {
                              final reloaded = await widget.apiService.getArbeitgeberDokumente(widget.user.id, arbeitgeberIndex);
                              final newDoks = List<Map<String, dynamic>>.from(
                                (reloaded['dokumente'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
                              );
                              setDlgState(() {
                                detailDoks = newDoks;
                              });
                              // Also update parent list
                              dokumente.clear();
                              dokumente.addAll(newDoks);
                              setModalState(() {});
                              if (dlgCtx.mounted) {
                                ScaffoldMessenger.of(dlgCtx).showSnackBar(
                                  SnackBar(content: const Text('Dokument hochgeladen'), backgroundColor: Colors.green.shade600, duration: const Duration(seconds: 2)),
                                );
                              }
                            } else if (dlgCtx.mounted) {
                              ScaffoldMessenger.of(dlgCtx).showSnackBar(
                                SnackBar(content: Text('Upload fehlgeschlagen: ${result['message'] ?? result}'), backgroundColor: Colors.red),
                              );
                            }
                          } catch (e) {
                            if (dlgCtx.mounted) {
                              ScaffoldMessenger.of(dlgCtx).showSnackBar(
                                SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('Datei auswählen (PDF, JPG, PNG)', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dlgCtx);
                    // Delete
                    showDialog(
                      context: ctx,
                      builder: (delCtx) => AlertDialog(
                        title: const Text('Löschen?', style: TextStyle(fontSize: 15)),
                        content: Text('Lohnsteuerbescheinigung ${b['jahr']} löschen?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(delCtx), child: const Text('Abbrechen')),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(delCtx);
                              setModalState(() => bescheinigungen.removeAt(index));
                              save();
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text('Löschen', style: TextStyle(color: Colors.red.shade600)),
                ),
                ElevatedButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Schließen')),
              ],
            );
          },
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOverdue ? Colors.red.shade300 : Colors.purple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description, size: 16, color: Colors.purple.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text('Lohnsteuerbescheinigung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade800))),
              ElevatedButton.icon(
                onPressed: showAddDialog,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Hinzufügen', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Jährlich vom Arbeitgeber (Frist: Ende Februar des Folgejahres)',
            style: TextStyle(fontSize: 10, color: Colors.purple.shade500),
          ),

          // Overdue warning
          if (isOverdue) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('$lastYear fehlt! Bitte beim Arbeitgeber anfordern.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red.shade800)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // List
          if (bescheinigungen.isEmpty)
            Text('Keine Bescheinigungen erfasst', style: TextStyle(fontSize: 11, color: Colors.grey.shade500))
          else
            ...bescheinigungen.asMap().entries.map((entry) {
              final i = entry.key;
              final b = entry.value;
              final erhalten = b['erhalten'] == true || b['erhalten'] == 'true';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => showDetailDialog(i),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: erhalten ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: erhalten ? Colors.green.shade300 : Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(erhalten ? Icons.check_circle : Icons.hourglass_top, size: 16, color: erhalten ? Colors.green.shade700 : Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text('${b['jahr']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: erhalten ? Colors.green.shade800 : Colors.orange.shade800)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            erhalten ? 'Erhalten am ${b['erhalten_am'] ?? ''}' : 'Ausstehend',
                            style: TextStyle(fontSize: 11, color: erhalten ? Colors.green.shade700 : Colors.orange.shade700),
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _lsInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildVorfallTab(Map<String, dynamic> ag, Map<String, dynamic> data, StateSetter setDlg) {
    List<Map<String, dynamic>> vorfaelle = [];
    const typLabels = {'abmahnung': 'Abmahnung', 'unfall': 'Arbeitsunfall', 'mobbing': 'Mobbing / Diskriminierung', 'lohn': 'Lohnstreit', 'ueberstunden': 'Überstunden-Streit', 'vertrag': 'Vertragsverstoß (AG)', 'datenschutz': 'Datenschutzverstoß', 'zeugnis': 'Zeugnis-Streit', 'kuendigungsschutz': 'Kündigungsschutzklage', 'sonstiges': 'Sonstiges'};
    const statusLabels = {'offen': 'Offen', 'in_bearbeitung': 'In Bearbeitung', 'eskaliert': 'Eskaliert', 'geloest': 'Gelöst', 'abgeschlossen': 'Abgeschlossen'};
    const statusColors = {'offen': Colors.orange, 'in_bearbeitung': Colors.blue, 'eskaliert': Colors.red, 'geloest': Colors.green, 'abgeschlossen': Colors.grey};
    void addVorfall(StateSetter setLocal) {
      String typ = 'sonstiges'; String status = 'offen';
      final datumC = TextEditingController(); final titelC = TextEditingController(); final notizC = TextEditingController();
      showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setV) => AlertDialog(
        title: const Text('Neuer Vorfall', style: TextStyle(fontSize: 15)),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(value: typ, decoration: InputDecoration(labelText: 'Typ', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: typLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setV(() => typ = v ?? typ)),
          const SizedBox(height: 10),
          TextField(controller: titelC, decoration: InputDecoration(labelText: 'Titel', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}'; }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setV(() => status = v ?? status)),
          const SizedBox(height: 10),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () async { Navigator.pop(ctx);
            final stelleId = ag['id'] is int ? ag['id'] : int.tryParse(ag['id']?.toString() ?? '') ?? 0;
            await widget.apiService.arbeitgeberAction(widget.user.id, {'action': 'save_vorfall', 'stelle_id': stelleId, 'vorfall': {'typ': typ, 'titel': titelC.text.trim(), 'datum': datumC.text.trim(), 'status': status, 'notiz': notizC.text.trim()}});
            final res = await widget.apiService.getArbeitgeberStelleDetail(widget.user.id, stelleId);
            if (res['success'] == true) vorfaelle = (res['vorfaelle'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
            setLocal(() {});
          }, style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white), child: const Text('Hinzufügen'))],
      )));
    }
    return StatefulBuilder(builder: (ctx, setLocal) {
      final stelleId = ag['id'] is int ? ag['id'] : int.tryParse(ag['id']?.toString() ?? '') ?? 0;
      if (vorfaelle.isEmpty && stelleId > 0) {
        widget.apiService.getArbeitgeberStelleDetail(widget.user.id, stelleId).then((res) {
          if (res['success'] == true) { vorfaelle = (res['vorfaelle'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []; setLocal(() {}); }
        }).catchError((_) {});
      }
      return Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: Row(children: [
          Icon(Icons.report_problem, color: Colors.indigo.shade700, size: 18), const SizedBox(width: 6),
          Text('Vorfälle (${vorfaelle.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo.shade800)),
          const Spacer(),
          FilledButton.icon(onPressed: () => addVorfall(setLocal), icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero)),
        ])),
        Expanded(child: vorfaelle.isEmpty ? Center(child: Text('Keine Vorfälle', style: TextStyle(color: Colors.grey.shade400)))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 8), itemCount: vorfaelle.length, itemBuilder: (_, i) {
              final v = vorfaelle[i]; final st = v['status']?.toString() ?? 'offen'; final stColor = (statusColors[st] ?? Colors.grey);
              return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(dense: true,
                leading: Icon(Icons.report_problem, color: stColor.shade600, size: 20),
                title: Text(v['titel']?.toString() ?? (typLabels[v['typ']] ?? ''), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                subtitle: Text('${typLabels[v['typ']] ?? ''} · ${v['datum'] ?? ''}', style: const TextStyle(fontSize: 10)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: stColor.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Text(statusLabels[st] ?? st, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: stColor.shade800))),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), onPressed: () async {
                    await widget.apiService.arbeitgeberAction(widget.user.id, {'action': 'delete_vorfall', 'id': v['id']});
                    vorfaelle.removeAt(i); setLocal(() {});
                  }),
                ]),
              ));
            })),
      ]);
    });
  }
}

// ══════════════════════════════════════════════════
// ── Qualifikationen Section (Führerschein, Sprachen, Schulabschluss)
// ══════════════════════════════════════════════════
class _QualifikationenSection extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _QualifikationenSection({required this.apiService, required this.userId});
  @override
  State<_QualifikationenSection> createState() => _QualifikationenSectionState();
}

class _QualifikationenSectionState extends State<_QualifikationenSection> {
  List<Map<String, dynamic>> _fuehrerschein = [];
  List<Map<String, dynamic>> _sprachen = [];
  List<Map<String, dynamic>> _fsKlassen = [];
  List<Map<String, dynamic>> _sprachenDB = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.apiService.getUserQualifikationen(widget.userId),
        widget.apiService.getFuehrerscheinklassen(),
        widget.apiService.getSprachen(),
        Future.value({'success': true, 'data': []}),
      ]);
      if (mounted) {
        setState(() {
          _loaded = true;
          if (results[0]['success'] == true) {
            _fuehrerschein = List<Map<String, dynamic>>.from(results[0]['fuehrerschein'] ?? []);
            _sprachen = List<Map<String, dynamic>>.from(results[0]['sprachen'] ?? []);
          }
          if (results[1]['success'] == true) _fsKlassen = List<Map<String, dynamic>>.from(results[1]['data'] ?? []);
          if (results[2]['success'] == true) _sprachenDB = List<Map<String, dynamic>>.from(results[2]['data'] ?? []);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _reload() async {
    try {
      final result = await widget.apiService.getUserQualifikationen(widget.userId);
      if (mounted && result['success'] == true) {
        setState(() {
          _fuehrerschein = List<Map<String, dynamic>>.from(result['fuehrerschein'] ?? []);
          _sprachen = List<Map<String, dynamic>>.from(result['sprachen'] ?? []);
        });
      }
    } catch (_) {}
  }

  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Row(children: [
      Icon(icon, size: 20, color: color), const SizedBox(width: 8),
      Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
      Expanded(child: Divider(color: color.withValues(alpha: 0.3), thickness: 1)),
    ]));
  }

  Widget _chip(String label, {Color? color, VoidCallback? onDelete}) {
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.1) ?? Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color?.withValues(alpha: 0.4) ?? Colors.indigo.shade200),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color ?? Colors.indigo.shade700)),
        if (onDelete != null) ...[
          const SizedBox(width: 4),
          InkWell(onTap: onDelete, child: Icon(Icons.close, size: 14, color: Colors.red.shade400)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── FÜHRERSCHEIN ──
        _sectionHeader(Icons.directions_car, 'Führerschein', Colors.blue.shade700),
        Wrap(
          children: [
            ..._fuehrerschein.map((fs) {
              final klasse = fs['klasse'] ?? '';
              final id = int.tryParse(fs['id'].toString()) ?? 0;
              return _chip('Klasse $klasse', color: Colors.blue, onDelete: () async {
                await widget.apiService.deleteUserQualifikation(widget.userId, 'fuehrerschein', id);
                _reload();
              });
            }),
            InkWell(
              onTap: () => _showAddFuehrerschein(),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.shade300, style: BorderStyle.solid), color: Colors.blue.shade50),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 14, color: Colors.blue.shade700), const SizedBox(width: 4), Text('Hinzufügen', style: TextStyle(fontSize: 12, color: Colors.blue.shade700))]),
              ),
            ),
          ],
        ),

        // ── SPRACHEN ──
        _sectionHeader(Icons.language, 'Sprachen', Colors.green.shade700),
        Wrap(
          children: [
            ..._sprachen.map((sp) {
              final sprache = sp['sprache'] ?? '';
              final niveau = sp['niveau'] ?? '';
              final id = int.tryParse(sp['id'].toString()) ?? 0;
              return _chip('$sprache ($niveau)', color: Colors.green, onDelete: () async {
                await widget.apiService.deleteUserQualifikation(widget.userId, 'sprachen', id);
                _reload();
              });
            }),
            InkWell(
              onTap: () => _showAddSprache(),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green.shade300), color: Colors.green.shade50),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 14, color: Colors.green.shade700), const SizedBox(width: 4), Text('Hinzufügen', style: TextStyle(fontSize: 12, color: Colors.green.shade700))]),
              ),
            ),
          ],
        ),

        // Schulbildung ist in Behörde-Tab
      ],
    );
  }

  void _showAddFuehrerschein() {
    String selectedKlasse = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Führerscheinklasse hinzufügen', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 350,
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: _fsKlassen.map((fs) {
                final klasse = fs['klasse'] ?? '';
                final beschreibung = fs['beschreibung'] ?? '';
                final isSelected = selectedKlasse == klasse;
                final alreadyHas = _fuehrerschein.any((f) => f['klasse'] == klasse);
                return InkWell(
                  onTap: alreadyHas ? null : () => setDlg(() => selectedKlasse = klasse),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: alreadyHas ? Colors.grey.shade200 : isSelected ? Colors.blue.shade100 : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSelected ? Colors.blue : alreadyHas ? Colors.grey.shade300 : Colors.grey.shade300),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(klasse, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: alreadyHas ? Colors.grey : Colors.black87)),
                      Text(beschreibung, style: TextStyle(fontSize: 10, color: alreadyHas ? Colors.grey : Colors.grey.shade600)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: selectedKlasse.isEmpty ? null : () async {
                await widget.apiService.addUserQualifikation(widget.userId, 'fuehrerschein', {'klasse': selectedKlasse});
                if (ctx.mounted) Navigator.pop(ctx);
                _reload();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSprache() {
    String selectedSprache = '';
    String niveau = 'Grundkenntnisse';
    final niveaus = ['Grundkenntnisse', 'Gut', 'Sehr gut', 'Fließend', 'Muttersprache'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Sprache hinzufügen', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Autocomplete<Map<String, dynamic>>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return _sprachenDB;
                  final q = textEditingValue.text.toLowerCase();
                  return _sprachenDB.where((s) => (s['sprache'] ?? '').toString().toLowerCase().contains(q));
                },
                displayStringForOption: (s) => s['sprache'] ?? '',
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller, focusNode: focusNode,
                    decoration: InputDecoration(labelText: 'Sprache', prefixIcon: const Icon(Icons.language, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    style: const TextStyle(fontSize: 14),
                  );
                },
                onSelected: (s) => setDlg(() => selectedSprache = s['sprache'] ?? ''),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: niveau,
                decoration: InputDecoration(labelText: 'Niveau', prefixIcon: const Icon(Icons.signal_cellular_alt, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                items: niveaus.map((n) => DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setDlg(() => niveau = v ?? 'Grundkenntnisse'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () async {
                if (selectedSprache.isEmpty) return;
                await widget.apiService.addUserQualifikation(widget.userId, 'sprachen', {'sprache': selectedSprache, 'niveau': niveau});
                if (ctx.mounted) Navigator.pop(ctx);
                _reload();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

}
