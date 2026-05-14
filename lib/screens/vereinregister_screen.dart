import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class VereinregisterScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const VereinregisterScreen({
    super.key,
    required this.apiService,
    required this.onBack,
  });

  @override
  State<VereinregisterScreen> createState() => _VereinregisterScreenState();
}

class _VereinregisterScreenState extends State<VereinregisterScreen> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;

  // Vereineinstellungen data (from DB)
  Map<String, dynamic> _vereineinstellungen = {};
  bool _vereineinstellungenLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadVereineinstellungen();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.apiService.getVereinverwaltung(kategorie: 'behoerde');
      if (mounted && result['success'] == true) {
        final data = result['data'] as List?;
        if (data != null && data.isNotEmpty) {
          setState(() {
            _data = data[0];
            _isLoading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadVereineinstellungen() async {
    setState(() => _vereineinstellungenLoading = true);
    try {
      final result = await widget.apiService.getVereineinstellungen();
      if (result['success'] == true && mounted) {
        setState(() {
          _vereineinstellungen = Map<String, dynamic>.from(result['data'] ?? {});
          _vereineinstellungenLoading = false;
        });
      } else if (mounted) {
        setState(() => _vereineinstellungenLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _vereineinstellungenLoading = false);
    }
  }

  Future<void> _saveVereineinstellungen(Map<String, dynamic> data) async {
    final result = await widget.apiService.updateVereineinstellungen(data);
    if (result['success'] == true && mounted) {
      setState(() {
        _vereineinstellungen = Map<String, dynamic>.from(result['data'] ?? {});
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vereineinstellungen gespeichert'), backgroundColor: Colors.green),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Fehler beim Speichern'), backgroundColor: Colors.red),
      );
    }
  }

  void _showSettingsDialog() {
    final d = _vereineinstellungen;
    final nameCtrl = TextEditingController(text: (d['vereinsname'] ?? '').toString());
    final adresseCtrl = TextEditingController(text: (d['adresse'] ?? '').toString());
    final telefonFixCtrl = TextEditingController(text: (d['telefon_fix'] ?? '').toString());
    final faxCtrl = TextEditingController(text: (d['fax'] ?? '').toString());
    final mobilCtrl = TextEditingController(text: (d['mobil'] ?? '').toString());
    final emailCtrl = TextEditingController(text: (d['email'] ?? '').toString());
    final gruendungsdatumCtrl = TextEditingController(text: (d['gruendungsdatum'] ?? '').toString());
    final registernummerCtrl = TextEditingController(text: (d['registernummer'] ?? '').toString());
    final registergerichtCtrl = TextEditingController(text: (d['registergericht'] ?? '').toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.settings, color: Colors.indigo.shade700),
            const SizedBox(width: 10),
            const Text('Vereineinstellungen'),
          ],
        ),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                // Two-column layout
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left column
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: 'Vereinsname *',
                              prefixIcon: const Icon(Icons.business),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              hintText: 'z.B. ICD360S e.V.',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: adresseCtrl,
                            decoration: InputDecoration(
                              labelText: 'Adresse *',
                              prefixIcon: const Icon(Icons.location_on),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              hintText: 'Straße Nr., PLZ Ort',
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: gruendungsdatumCtrl,
                            decoration: InputDecoration(
                              labelText: 'Gründungsdatum',
                              prefixIcon: const Icon(Icons.calendar_month),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              hintText: 'z.B. 01.01.2025',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: registernummerCtrl,
                            decoration: InputDecoration(
                              labelText: 'Registernummer',
                              prefixIcon: const Icon(Icons.numbers),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              hintText: 'z.B. VR 201335',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: registergerichtCtrl,
                            decoration: InputDecoration(
                              labelText: 'Registergericht',
                              prefixIcon: const Icon(Icons.account_balance),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              hintText: 'z.B. Amtsgericht Memmingen, Bayern',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Right column
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: emailCtrl,
                            decoration: InputDecoration(
                              labelText: 'E-Mail',
                              prefixIcon: const Icon(Icons.email),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: telefonFixCtrl,
                            decoration: InputDecoration(
                              labelText: 'Telefon (Festnetz)',
                              prefixIcon: const Icon(Icons.phone),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: faxCtrl,
                            decoration: InputDecoration(
                              labelText: 'Fax',
                              prefixIcon: const Icon(Icons.fax),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: mobilCtrl,
                            decoration: InputDecoration(
                              labelText: 'Mobil',
                              prefixIcon: const Icon(Icons.phone_android),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _saveVereineinstellungen({
                'vereinsname': nameCtrl.text,
                'adresse': adresseCtrl.text,
                'telefon_fix': telefonFixCtrl.text,
                'fax': faxCtrl.text,
                'mobil': mobilCtrl.text,
                'email': emailCtrl.text,
                'gruendungsdatum': gruendungsdatumCtrl.text,
                'registernummer': registernummerCtrl.text,
                'registergericht': registergerichtCtrl.text,
              });
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Get values from DB (no fallback - values are stored in vereineinstellungen table)
  String get _vereinsname =>
      (_vereineinstellungen['vereinsname'] ?? '').toString().trim();

  String get _registernummer =>
      (_vereineinstellungen['registernummer'] ?? '').toString().trim();

  String get _registergericht =>
      (_vereineinstellungen['registergericht'] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 8),
              Icon(Icons.article, size: 32, color: Colors.indigo.shade700),
              const SizedBox(width: 12),
              const Text(
                'Vereinregister',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_data != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Text(
                    _registernummer,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // Content
          Expanded(
            child: _isLoading || _vereineinstellungenLoading
                ? const Center(child: CircularProgressIndicator())
                : _data == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.article, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              'Keine Vereinregister-Daten vorhanden',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final d = _data!;
    final ve = _vereineinstellungen;
    final hasVereinData = ve.isNotEmpty && (ve['vereinsname'] ?? '').toString().trim().isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Amtsgericht Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.account_balance, color: Colors.indigo, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d['name'] ?? '',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            if (d['name2'] != null)
                              Text(
                                d['name2'],
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  // Registration info
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.verified, color: Colors.indigo, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          _vereinsname,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Registernummer: $_registernummer',
                          style: TextStyle(fontSize: 15, color: Colors.indigo.shade700, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _registergericht,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Address
                  _buildInfoRow(Icons.location_on, 'Adresse', '${d['strasse']} ${d['hausnummer']}, ${d['plz']} ${d['ort']}'),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.phone, 'Telefon', d['telefon'] ?? '-'),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.fax, 'Fax', d['fax'] ?? '-'),
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.email, 'E-Mail', d['email'] ?? '-'),
                  const SizedBox(height: 16),
                  // Action button
                  if (d['website'] != null)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Website öffnen'),
                        onPressed: () => _openUrl(d['website']),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Vereinsdaten Card (from Vereineinstellungen)
          if (hasVereinData) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.business, color: Colors.teal, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Vereinsdaten',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit, size: 20, color: Colors.teal.shade700),
                          onPressed: _showSettingsDialog,
                          tooltip: 'Bearbeiten',
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    // Vereinsdaten fields
                    if ((ve['vereinsname'] ?? '').toString().trim().isNotEmpty)
                      _buildInfoRow(Icons.business, 'Name', ve['vereinsname'].toString()),
                    if ((ve['adresse'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(Icons.location_on, 'Adresse', ve['adresse'].toString()),
                    ],
                    if ((ve['telefon_fix'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(Icons.phone, 'Telefon', ve['telefon_fix'].toString()),
                    ],
                    if ((ve['fax'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(Icons.fax, 'Fax', ve['fax'].toString()),
                    ],
                    if ((ve['mobil'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(Icons.phone_android, 'Mobil', ve['mobil'].toString()),
                    ],
                    if ((ve['email'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(Icons.email, 'E-Mail', ve['email'].toString()),
                    ],
                    if ((ve['gruendungsdatum'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(Icons.calendar_month, 'Gründung', ve['gruendungsdatum'].toString()),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // Hint if no Vereinsdaten
          if (!hasVereinData) ...[
            const SizedBox(height: 20),
            Card(
              color: Colors.grey.shade50,
              child: InkWell(
                onTap: _showSettingsDialog,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, size: 32, color: Colors.grey.shade400),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vereinsdaten hinzufügen',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Name, Adresse, Kontaktdaten des Vereins eintragen',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
