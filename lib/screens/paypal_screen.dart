import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

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
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück zu Banken',
              ),
              const SizedBox(width: 8),
              Icon(Icons.account_balance_wallet, size: 32, color: Colors.blue.shade800),
              const SizedBox(width: 12),
              const Text('PayPal', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock, size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text('Verschlüsselt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildKontoTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildKontoTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PayPal logo area
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

          if (_editing) ...[
            _buildEditForm(),
          ] else ...[
            _buildReadonlyView(),
          ],
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
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
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
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kopiert'), duration: Duration(seconds: 1)),
              );
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
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Passwort kopiert'), duration: Duration(seconds: 1)),
            );
          },
        ),
      ]),
    );
  }

  Widget _buildEditForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
        boxShadow: [BoxShadow(color: Colors.blue.shade50, blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PayPal-Konto bearbeiten', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'E-Mail-Adresse',
            hintText: 'verein@icd360s.de',
            isDense: true,
            prefixIcon: const Icon(Icons.email, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: 'Passwort',
            isDense: true,
            prefixIcon: const Icon(Icons.lock, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, size: 18),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _notizController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Notiz',
            hintText: 'Zusätzliche Informationen...',
            isDense: true,
            prefixIcon: const Icon(Icons.note, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Speichern'),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () {
              _emailController.text = _data['email']?.toString() ?? '';
              _passwordController.text = _data['passwort']?.toString() ?? '';
              _notizController.text = _data['notiz']?.toString() ?? '';
              setState(() => _editing = false);
            },
            child: const Text('Abbrechen'),
          ),
        ]),
      ]),
    );
  }
}
