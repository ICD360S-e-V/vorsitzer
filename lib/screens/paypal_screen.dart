import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../widgets/korrespondenz_attachments_widget.dart';

class PayPalScreen extends StatefulWidget {
  final VoidCallback onBack;
  final ApiService apiService;

  const PayPalScreen({super.key, required this.onBack, required this.apiService});

  @override
  State<PayPalScreen> createState() => _PayPalScreenState();
}

class _PayPalScreenState extends State<PayPalScreen> {
  bool _loading = true;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _korr = [];
  bool _editing = false;
  bool _showPassword = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _notizController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _notizController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.paypalAction({'action': 'get'});
      if (res['success'] == true && res['data'] != null) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
        _emailController.text = _data['email']?.toString() ?? '';
        _passwordController.text = _data['passwort']?.toString() ?? '';
        _notizController.text = _data['notiz']?.toString() ?? '';
      }
      final kRes = await widget.apiService.paypalAction({'action': 'list_korr'});
      if (kRes['success'] == true && kRes['korrespondenz'] is List) {
        _korr = List<Map<String, dynamic>>.from((kRes['korrespondenz'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final res = await widget.apiService.paypalAction({
      'action': 'save',
      'email': _emailController.text.trim(),
      'passwort': _passwordController.text.trim(),
      'notiz': _notizController.text.trim(),
    });
    if (mounted) {
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
        );
        setState(() => _editing = false);
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack, tooltip: 'Zurück zu Banken'),
              const SizedBox(width: 8),
              Icon(Icons.account_balance_wallet, size: 32, color: Colors.blue.shade800),
              const SizedBox(width: 12),
              const Text('PayPal', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock, size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text('Verschlüsselt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : DefaultTabController(
                    length: 2,
                    child: Column(children: [
                      TabBar(
                        labelColor: Colors.blue.shade800,
                        unselectedLabelColor: Colors.grey.shade500,
                        indicatorColor: Colors.blue.shade800,
                        tabs: const [
                          Tab(icon: Icon(Icons.vpn_key, size: 16), text: 'Zugang Online'),
                          Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
                        ],
                      ),
                      Expanded(child: TabBarView(children: [
                        _buildZugangTab(),
                        _buildKorrespondenzTab(),
                      ])),
                    ]),
                  ),
          ),
        ],
      ),
    );
  }

  // ===== TAB 1: ZUGANG ONLINE =====
  Widget _buildZugangTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blue.shade700, Colors.blue.shade900]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet, size: 40, color: Colors.white),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PayPal Konto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                Text(
                  _data['email']?.toString().isNotEmpty == true ? _data['email'].toString() : 'Nicht konfiguriert',
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8)),
                ),
              ]),
              const Spacer(),
              if (!_editing)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  tooltip: 'Bearbeiten',
                  onPressed: () => setState(() => _editing = true),
                ),
            ]),
          ),
          const SizedBox(height: 24),
          if (_editing) _buildEditForm() else _buildReadonlyView(),
        ],
      ),
    );
  }

  Widget _buildReadonlyView() {
    final hasData = (_data['email']?.toString() ?? '').isNotEmpty;
    if (!hasData) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
        child: Column(children: [
          Icon(Icons.account_balance_wallet, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Kein PayPal-Konto hinterlegt', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => setState(() => _editing = true),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Konto hinzufügen'),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700),
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildDetailCard(Icons.email, 'E-Mail-Adresse', _data['email']?.toString() ?? '', Colors.blue, copyable: true),
      const SizedBox(height: 12),
      _buildPasswordCard(),
      if ((_data['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        _buildDetailCard(Icons.note, 'Notiz', _data['notiz']?.toString() ?? '', Colors.amber),
      ],
      if (_data['updated_at'] != null) ...[
        const SizedBox(height: 16),
        Text('Zuletzt aktualisiert: ${_data['updated_at']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    ]);
  }

  Widget _buildDetailCard(IconData icon, String label, String value, MaterialColor color, {bool copyable = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.shade200)),
      child: Row(children: [
        CircleAvatar(backgroundColor: color.shade100, radius: 20, child: Icon(icon, color: color.shade700, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: color.shade600)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color.shade900)),
        ])),
        if (copyable)
          IconButton(
            icon: Icon(Icons.copy, size: 18, color: color.shade400),
            tooltip: 'Kopieren',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopiert'), duration: Duration(seconds: 1)));
            },
          ),
      ]),
    );
  }

  Widget _buildPasswordCard() {
    final pw = _data['passwort']?.toString() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
      child: Row(children: [
        CircleAvatar(backgroundColor: Colors.red.shade100, radius: 20, child: Icon(Icons.lock, color: Colors.red.shade700, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Passwort', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
          const SizedBox(height: 2),
          Text(_showPassword ? pw : '••••••••••', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.red.shade900, fontFamily: _showPassword ? null : 'monospace')),
        ])),
        IconButton(
          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, size: 18, color: Colors.red.shade400),
          tooltip: _showPassword ? 'Verbergen' : 'Anzeigen',
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
        IconButton(
          icon: Icon(Icons.copy, size: 18, color: Colors.red.shade400),
          tooltip: 'Kopieren',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: pw));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwort kopiert'), duration: Duration(seconds: 1)));
          },
        ),
      ]),
    );
  }

  Widget _buildEditForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
        boxShadow: [BoxShadow(color: Colors.blue.shade50, blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PayPal-Konto bearbeiten', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
        const SizedBox(height: 16),
        TextField(controller: _emailController, keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'E-Mail-Adresse', hintText: 'verein@icd360s.de', isDense: true,
            prefixIcon: const Icon(Icons.email, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 14),
        TextField(controller: _passwordController, obscureText: !_showPassword,
          decoration: InputDecoration(labelText: 'Passwort', isDense: true,
            prefixIcon: const Icon(Icons.lock, size: 18),
            suffixIcon: IconButton(icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: () => setState(() => _showPassword = !_showPassword)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 14),
        TextField(controller: _notizController, maxLines: 3,
          decoration: InputDecoration(labelText: 'Notiz', hintText: 'Zusätzliche Informationen...', isDense: true,
            prefixIcon: const Icon(Icons.note, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 20),
        Row(children: [
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save, size: 18), label: const Text('Speichern'),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700)),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: () {
            _emailController.text = _data['email']?.toString() ?? '';
            _passwordController.text = _data['passwort']?.toString() ?? '';
            _notizController.text = _data['notiz']?.toString() ?? '';
            setState(() => _editing = false);
          }, child: const Text('Abbrechen')),
        ]),
      ]),
    );
  }

  static const _kategorieLabels = {'online': 'Online', 'email': 'E-Mail', 'fax': 'Fax', 'postalisch': 'Postalisch'};
  static const _kategorieIcons = {'online': Icons.language, 'email': Icons.email, 'fax': Icons.fax, 'postalisch': Icons.local_post_office};

  // ===== TAB 2: KORRESPONDENZ =====
  Widget _buildKorrespondenzTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.mail, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Text('Korrespondenz (${_korr.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue.shade800)),
        const Spacer(),
        FilledButton.icon(
          onPressed: _addKorrespondenz,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neu', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
        ),
      ])),
      Expanded(child: _korr.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mail_outline, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Korrespondenz vorhanden', style: TextStyle(color: Colors.grey.shade400)),
          ]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i];
            final isEin = k['richtung'] == 'eingehend';
            final color = isEin ? Colors.blue : Colors.green;
            final kat = k['kategorie']?.toString() ?? 'email';
            final katIcon = _kategorieIcons[kat] ?? Icons.email;
            final katLabel = _kategorieLabels[kat] ?? kat;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showKorrDetail(k, i),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: color.shade100, child: Icon(katIcon, color: color.shade700, size: 20)),
                  title: Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Row(children: [
                    Text('${k['datum'] ?? ''} • ${isEin ? 'Eingehend' : 'Ausgehend'}', style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                      child: Text(katLabel, style: TextStyle(fontSize: 10, color: Colors.grey.shade700))),
                  ]),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                    onPressed: () async {
                      await widget.apiService.paypalAction({'action': 'delete_korr', 'id': k['id']});
                      _load();
                    },
                  ),
                ),
              ),
            );
          })),
    ]);
  }

  void _addKorrespondenz() {
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    String richtung = 'ausgehend';
    String kategorie = 'email';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Row(children: [
        Icon(Icons.mail, size: 18, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        const Text('Neue Korrespondenz', style: TextStyle(fontSize: 15)),
      ]),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('Ausgehend'), avatar: const Icon(Icons.call_made, size: 16), selected: richtung == 'ausgehend',
            selectedColor: Colors.green.shade100, onSelected: (_) => setDlg(() => richtung = 'ausgehend')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Eingehend'), avatar: const Icon(Icons.call_received, size: 16), selected: richtung == 'eingehend',
            selectedColor: Colors.blue.shade100, onSelected: (_) => setDlg(() => richtung = 'eingehend')),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: _kategorieLabels.entries.map((e) => ChoiceChip(
          avatar: Icon(_kategorieIcons[e.key], size: 16),
          label: Text(e.value),
          selected: kategorie == e.key,
          selectedColor: Colors.blue.shade100,
          onSelected: (_) => setDlg(() => kategorie = e.key),
        )).toList()),
        const SizedBox(height: 12),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          final today = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
          await widget.apiService.paypalAction({
            'action': 'save_korr',
            'korr': {'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim(), 'datum': today, 'richtung': richtung, 'kategorie': kategorie},
          });
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  void _showKorrDetail(Map<String, dynamic> k, int index) {
    final isEin = k['richtung'] == 'eingehend';
    final color = isEin ? Colors.blue : Colors.green;
    final kat = k['kategorie']?.toString() ?? 'email';
    final katLabel = _kategorieLabels[kat] ?? kat;
    final katIcon = _kategorieIcons[kat] ?? Icons.email;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(katIcon, size: 20, color: color.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text(k['betreff']?.toString() ?? 'Korrespondenz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color.shade800))),
      ]),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(12)),
            child: Text(isEin ? 'Eingehend' : 'Ausgehend', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade800))),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(katIcon, size: 14, color: Colors.grey.shade700),
              const SizedBox(width: 4),
              Text(katLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            ])),
          const Spacer(),
          Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
        if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Text(k['notiz'].toString(), style: const TextStyle(fontSize: 13))),
        ],
        const SizedBox(height: 16),
        KorrAttachmentsWidget(apiService: widget.apiService, modul: 'paypal_korr', korrespondenzId: k['id'] is int ? k['id'] : int.tryParse(k['id'].toString()) ?? index),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }
}
