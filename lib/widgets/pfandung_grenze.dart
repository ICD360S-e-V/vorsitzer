import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class PfandungGrenzeWidget extends StatefulWidget {
  final ApiService apiService;

  const PfandungGrenzeWidget({super.key, required this.apiService});

  @override
  State<PfandungGrenzeWidget> createState() => _PfandungGrenzeWidgetState();
}

class _PfandungGrenzeWidgetState extends State<PfandungGrenzeWidget> {
  List<Map<String, dynamic>> _perioden = [];
  Map<String, dynamic>? _aktuell;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.apiService.getPKontoFreibetrag();
      if (result['success'] == true) {
        setState(() {
          _aktuell = result['aktuell'] != null ? Map<String, dynamic>.from(result['aktuell'] as Map) : null;
          if (result['alle_perioden'] is List) {
            _perioden = (result['alle_perioden'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        });
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  String _fmtDate(String? d) {
    if (d == null || d.isEmpty) return '';
    final parsed = DateTime.tryParse(d);
    if (parsed == null) return d;
    return DateFormat('dd.MM.yyyy').format(parsed);
  }

  String _fmtEuro(dynamic val) {
    final d = double.tryParse(val?.toString() ?? '0') ?? 0;
    return d.toStringAsFixed(2).replaceAll('.', ',');
  }

  void _showAddEditDialog([Map<String, dynamic>? existing]) {
    final vonC = TextEditingController(text: existing?['gueltig_von']?.toString() ?? '');
    final bisC = TextEditingController(text: existing?['gueltig_bis']?.toString() ?? '');
    final betragC = TextEditingController(text: existing?['grundfreibetrag']?.toString() ?? '');
    final erh1C = TextEditingController(text: existing?['erhoehung_1_person']?.toString() ?? '');
    final erh25C = TextEditingController(text: existing?['erhoehung_2_5_person']?.toString() ?? '');
    final quelleC = TextEditingController(text: existing?['quelle']?.toString() ?? '');
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.shield, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Text(isEdit ? 'Periode bearbeiten' : 'Neue Periode hinzufügen', style: const TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gültig von
                TextFormField(
                  controller: vonC,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Gültig von *',
                    prefixIcon: Icon(Icons.calendar_today, size: 18, color: Colors.green.shade600),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.edit_calendar, size: 16),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dlgCtx,
                          initialDate: DateTime.tryParse(vonC.text) ?? DateTime(DateTime.now().year, 7, 1),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2099),
                          locale: const Locale('de'),
                        );
                        if (picked != null) vonC.text = DateFormat('yyyy-MM-dd').format(picked);
                      },
                    ),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    helperText: 'Normalerweise 01.07.YYYY',
                    helperStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 12),
                // Gültig bis
                TextFormField(
                  controller: bisC,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Gültig bis *',
                    prefixIcon: Icon(Icons.event, size: 18, color: Colors.red.shade600),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.edit_calendar, size: 16),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dlgCtx,
                          initialDate: DateTime.tryParse(bisC.text) ?? DateTime(DateTime.now().year + 1, 6, 30),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2099),
                          locale: const Locale('de'),
                        );
                        if (picked != null) bisC.text = DateFormat('yyyy-MM-dd').format(picked);
                      },
                    ),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    helperText: 'Normalerweise 30.06.YYYY',
                    helperStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 16),
                // Grundfreibetrag
                TextFormField(
                  controller: betragC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Grundfreibetrag (€) *',
                    prefixIcon: Icon(Icons.euro, size: 18, color: Colors.red.shade700),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. 1559.99',
                  ),
                ),
                const SizedBox(height: 12),
                // Erhöhung 1. Person
                TextFormField(
                  controller: erh1C,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Erhöhung 1. unterh. Person (€) *',
                    prefixIcon: Icon(Icons.person_add, size: 18, color: Colors.orange.shade700),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. 585.23',
                  ),
                ),
                const SizedBox(height: 12),
                // Erhöhung 2.-5. Person
                TextFormField(
                  controller: erh25C,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Erhöhung 2.–5. Person je (€) *',
                    prefixIcon: Icon(Icons.group_add, size: 18, color: Colors.blue.shade700),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. 326.04',
                  ),
                ),
                const SizedBox(height: 12),
                // Quelle
                TextFormField(
                  controller: quelleC,
                  decoration: InputDecoration(
                    labelText: 'Quelle (BGBl. Nr.)',
                    prefixIcon: Icon(Icons.source, size: 18, color: Colors.grey.shade600),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. BGBl. 2026 I Nr. XXX',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () async {
              if (vonC.text.isEmpty || bisC.text.isEmpty || betragC.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bitte alle Pflichtfelder ausfüllen'), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(dlgCtx);
              await _savePeriode(
                id: existing?['id'],
                von: vonC.text,
                bis: bisC.text,
                betrag: betragC.text,
                erh1: erh1C.text,
                erh25: erh25C.text,
                quelle: quelleC.text,
              );
            },
            icon: const Icon(Icons.save, size: 16),
            label: Text(isEdit ? 'Aktualisieren' : 'Hinzufügen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
          ),
        ],
      ),
    ).then((_) {
      vonC.dispose();
      bisC.dispose();
      betragC.dispose();
      erh1C.dispose();
      erh25C.dispose();
      quelleC.dispose();
    });
  }

  Future<void> _savePeriode({
    int? id,
    required String von,
    required String bis,
    required String betrag,
    required String erh1,
    required String erh25,
    required String quelle,
  }) async {
    try {
      final result = await widget.apiService.savePKontoPeriode(
        id: id,
        gueltigVon: von,
        gueltigBis: bis,
        grundfreibetrag: betrag,
        erhoehung1: erh1,
        erhoehung25: erh25,
        quelle: quelle,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Periode gespeichert'), backgroundColor: Colors.green.shade600, duration: const Duration(seconds: 1)),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${result['message'] ?? 'Unbekannt'}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _deletePeriode(Map<String, dynamic> p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Periode löschen?', style: TextStyle(fontSize: 15)),
        content: Text('${_fmtDate(p['gueltig_von']?.toString())} – ${_fmtDate(p['gueltig_bis']?.toString())} wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final result = await widget.apiService.deletePKontoPeriode(int.parse(p['id'].toString()));
                if (result['success'] == true) {
                  _loadData();
                }
              } catch (_) {}
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Check if we need a reminder to update Pfändungsgrenze
  /// Returns: null (ok), 'warning' (approaching 01.07), 'overdue' (past 01.07 without new period)
  Map<String, dynamic>? _getUpdateStatus() {
    final now = DateTime.now();
    final nextJuly1 = DateTime(now.month >= 7 ? now.year + 1 : now.year, 7, 1);
    final currentJuly1 = DateTime(now.month >= 7 ? now.year : now.year, 7, 1);
    final daysUntilJuly = nextJuly1.difference(now).inDays;

    // Check if there's a period covering next July
    final hasNextPeriod = _perioden.any((p) {
      final von = DateTime.tryParse(p['gueltig_von']?.toString() ?? '');
      return von != null && von.year == nextJuly1.year && von.month == 7;
    });

    // Check if current period is expired (past 30.06 without new one)
    if (_aktuell != null) {
      final bis = DateTime.tryParse(_aktuell!['gueltig_bis']?.toString() ?? '');
      if (bis != null && now.isAfter(bis)) {
        return {'status': 'overdue', 'message': 'Aktuelle Periode ist abgelaufen! Bitte neue Werte für ${currentJuly1.year}/${currentJuly1.year + 1} eintragen.'};
      }
    }

    // Warning 2 months before (from May 1st)
    if (daysUntilJuly <= 60 && !hasNextPeriod) {
      return {'status': 'warning', 'message': 'Noch $daysUntilJuly Tage bis 01.07.${nextJuly1.year}. Neue Pfändungsfreigrenzen eintragen, sobald im Bundesgesetzblatt veröffentlicht.'};
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final updateStatus = _getUpdateStatus();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Aufgabe / Erinnerung Banner
          if (updateStatus != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: updateStatus['status'] == 'overdue' ? Colors.red.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: updateStatus['status'] == 'overdue' ? Colors.red.shade400 : Colors.orange.shade400,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    updateStatus['status'] == 'overdue' ? Icons.error : Icons.warning_amber,
                    size: 24,
                    color: updateStatus['status'] == 'overdue' ? Colors.red.shade700 : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          updateStatus['status'] == 'overdue' ? 'Aufgabe: Pfändungsgrenze aktualisieren!' : 'Erinnerung: Pfändungsgrenze',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: updateStatus['status'] == 'overdue' ? Colors.red.shade800 : Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          updateStatus['message'].toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: updateStatus['status'] == 'overdue' ? Colors.red.shade700 : Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditDialog(),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Neue Periode', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: updateStatus['status'] == 'overdue' ? Colors.red.shade700 : Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.red.shade50, Colors.red.shade100]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.shield, size: 32, color: Colors.red.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pfändungsfreigrenzen (P-Konto)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                      Text('§ 899 ZPO – Jährliche Aktualisierung zum 1. Juli', style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddEditDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Neue Periode', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Aktuell gültig
          if (_aktuell != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text('Aktuell gültig', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_fmtDate(_aktuell!['gueltig_von']?.toString())} – ${_fmtDate(_aktuell!['gueltig_bis']?.toString())}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _statCard('Grundfreibetrag', '${_fmtEuro(_aktuell!['grundfreibetrag'])} €', Colors.red),
                      const SizedBox(width: 12),
                      _statCard('+1. Person', '${_fmtEuro(_aktuell!['erhoehung_1_person'])} €', Colors.orange),
                      const SizedBox(width: 12),
                      _statCard('+2.–5. Person', '${_fmtEuro(_aktuell!['erhoehung_2_5_person'])} €', Colors.blue),
                    ],
                  ),
                  if ((_aktuell!['quelle']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Quelle: ${_aktuell!['quelle']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Alle Perioden
          Text('Alle Perioden', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
          const SizedBox(height: 10),

          if (_perioden.isEmpty)
            const Text('Keine Perioden vorhanden', style: TextStyle(color: Colors.grey))
          else
            ..._perioden.map((p) {
              final isAktuell = _aktuell != null && p['id'].toString() == _aktuell!['id'].toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isAktuell ? Colors.green.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isAktuell ? Colors.green.shade300 : Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    if (isAktuell)
                      Icon(Icons.check_circle, size: 16, color: Colors.green.shade600)
                    else
                      Icon(Icons.history, size: 16, color: Colors.grey.shade400),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 180,
                      child: Text(
                        '${_fmtDate(p['gueltig_von']?.toString())} – ${_fmtDate(p['gueltig_bis']?.toString())}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isAktuell ? Colors.green.shade800 : Colors.grey.shade700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${_fmtEuro(p['grundfreibetrag'])} €', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                    const SizedBox(width: 12),
                    Text('+${_fmtEuro(p['erhoehung_1_person'])} €', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                    const SizedBox(width: 8),
                    Text('+${_fmtEuro(p['erhoehung_2_5_person'])} €', style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
                    const Spacer(),
                    if ((p['quelle']?.toString() ?? '').isNotEmpty)
                      Text(p['quelle'].toString(), style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.edit, size: 16, color: Colors.blue.shade600),
                      onPressed: () => _showAddEditDialog(p),
                      tooltip: 'Bearbeiten',
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                      onPressed: () => _deletePeriode(p),
                      tooltip: 'Löschen',
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, MaterialColor color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.shade200),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: color.shade600)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color.shade800)),
          ],
        ),
      ),
    );
  }
}
