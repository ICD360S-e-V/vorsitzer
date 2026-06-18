import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../widgets/korrespondenz_attachments_widget.dart';

class SimpleFaxScreen extends StatefulWidget {
  final VoidCallback onBack;
  final ApiService apiService;

  const SimpleFaxScreen({super.key, required this.onBack, required this.apiService});

  @override
  State<SimpleFaxScreen> createState() => _SimpleFaxScreenState();
}

class _SimpleFaxScreenState extends State<SimpleFaxScreen> {
  bool _loading = true;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _kontoauszug = [];
  List<Map<String, dynamic>> _rechnungen = [];
  List<Map<String, dynamic>> _mail2fax = [];
  Map<String, dynamic> _notifySettings = {};
  Map<String, dynamic> _verifizierung = {};
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
    _topupBetragController.dispose();
    _gutscheinController.dispose();
    _newEmailController.dispose();
    _newEmailRepController.dispose();
    _mail2faxNewController.dispose();
    _faxEmpfangsEmailController.dispose();
    _newAbsenderController.dispose();
    _newAbsenderRepController.dispose();
    _aktPwController.dispose();
    _neuPwController.dispose();
    _neuPwRepController.dispose();
    _delKontoPwController.dispose();
    _delBoxPwController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.simplefaxAction({'action': 'get'});
      if (res['success'] == true && res['data'] != null) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
        _emailController.text = _data['email']?.toString() ?? '';
        _passwordController.text = _data['passwort']?.toString() ?? '';
        _notizController.text = _data['notiz']?.toString() ?? '';
      }
      final kRes = await widget.apiService.simplefaxAction({'action': 'list_korr'});
      if (kRes['success'] == true && kRes['korrespondenz'] is List) {
        _korr = List<Map<String, dynamic>>.from((kRes['korrespondenz'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
      final aRes = await widget.apiService.simplefaxAction({'action': 'list_adressbuch'});
      if (aRes['success'] == true && aRes['kontakte'] is List) {
        _kontakte
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from((aRes['kontakte'] as List).map((e) => Map<String, dynamic>.from(e as Map))));
      }
      final auszRes = await widget.apiService.simplefaxAction({'action': 'list_kontoauszug'});
      if (auszRes['success'] == true && auszRes['auszug'] is List) {
        _kontoauszug = List<Map<String, dynamic>>.from((auszRes['auszug'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
      final rRes = await widget.apiService.simplefaxAction({'action': 'list_rechnungen'});
      if (rRes['success'] == true && rRes['rechnungen'] is List) {
        _rechnungen = List<Map<String, dynamic>>.from((rRes['rechnungen'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
      final mRes = await widget.apiService.simplefaxAction({'action': 'list_mail2fax'});
      if (mRes['success'] == true && mRes['mail2fax'] is List) {
        _mail2fax = List<Map<String, dynamic>>.from((mRes['mail2fax'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
      final nRes = await widget.apiService.simplefaxAction({'action': 'get_notify_settings'});
      if (nRes['success'] == true && nRes['notify_settings'] is Map) {
        _notifySettings = Map<String, dynamic>.from(nRes['notify_settings'] as Map);
      }
      final vRes = await widget.apiService.simplefaxAction({'action': 'get_verifizierung'});
      if (vRes['success'] == true && vRes['verifizierung'] is Map) {
        _verifizierung = Map<String, dynamic>.from(vRes['verifizierung'] as Map);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final res = await widget.apiService.simplefaxAction({
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
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack, tooltip: 'Zurück zu Partner'),
              const SizedBox(width: 8),
              Icon(Icons.fax, size: 32, color: Colors.orange.shade800),
              const SizedBox(width: 12),
              const Text('SimpleFax', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock, size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text('Verschlüsselt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : DefaultTabController(
                    length: 8,
                    child: Column(children: [
                      TabBar(
                        isScrollable: true,
                        labelColor: Colors.orange.shade800,
                        unselectedLabelColor: Colors.grey.shade500,
                        indicatorColor: Colors.orange.shade800,
                        tabs: const [
                          Tab(icon: Icon(Icons.vpn_key, size: 16), text: 'Zugang Online'),
                          Tab(icon: Icon(Icons.push_pin, size: 16), text: 'Pinnwand'),
                          Tab(icon: Icon(Icons.outbox, size: 16), text: 'Versandbox'),
                          Tab(icon: Icon(Icons.contacts, size: 16), text: 'Adressbuch'),
                          Tab(icon: Icon(Icons.euro, size: 16), text: 'Preise'),
                          Tab(icon: Icon(Icons.manage_accounts, size: 16), text: 'Kontoeinstellungen'),
                          Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
                          Tab(icon: Icon(Icons.verified_user, size: 16), text: 'Verifizierung'),
                        ],
                      ),
                      Expanded(child: TabBarView(children: [
                        _buildZugangTab(),
                        _buildPinnwandTab(),
                        _buildVersandboxTab(),
                        _buildAdressbuchTab(),
                        _buildPreiseTab(),
                        _buildKontoeinstellungenTab(),
                        _buildKorrespondenzTab(),
                        _buildVerifizierungTab(),
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
              gradient: LinearGradient(colors: [Colors.orange.shade700, Colors.orange.shade900]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.fax, size: 40, color: Colors.white),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SimpleFax Konto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
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
          Icon(Icons.fax, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Kein SimpleFax-Konto hinterlegt', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => setState(() => _editing = true),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Konto hinzufügen'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildDetailCard(Icons.email, 'E-Mail-Adresse', _data['email']?.toString() ?? '', Colors.orange, copyable: true),
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
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [BoxShadow(color: Colors.orange.shade50, blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SimpleFax-Konto bearbeiten', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700)),
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

  Widget _buildPlaceholderTab(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 64, color: Colors.orange.shade200),
        const SizedBox(height: 16),
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          child: Text('In Bearbeitung', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ),
      ]),
    );
  }

  // ===== TAB 2: PINNWAND =====
  String get _faxNummerRaw => _data['fax_nummer']?.toString() ?? '';
  String get _kundennummer => _data['kundennummer']?.toString() ?? '';
  String get _faxNummer {
    final raw = _faxNummerRaw;
    if (raw.length < 6) return raw;
    return '${raw.substring(0, 5)} ${raw.substring(5)}';
  }

  Widget _buildPinnwandTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.green.shade600, Colors.green.shade800], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.green.shade100, blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.fax, size: 28, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Ihre Faxnummer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 2),
                Row(children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('Aktiv und empfangsbereit', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
                ]),
              ])),
            ]),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _faxNummer,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5, fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white, size: 20),
                  tooltip: 'Kopieren',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _faxNummerRaw));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faxnummer kopiert'), duration: Duration(seconds: 1)));
                  },
                ),
              ]),
            ),
          ]),
        ),
        if (_kundennummer.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blueGrey.shade200),
            ),
            child: Row(children: [
              Icon(Icons.badge, size: 24, color: Colors.blueGrey.shade700),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Kundennummer', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700)),
                const SizedBox(height: 2),
                Text(_kundennummer, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900, fontFamily: 'monospace', letterSpacing: 1.2)),
              ]),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.copy, size: 18, color: Colors.blueGrey.shade400),
                tooltip: 'Kopieren',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _kundennummer));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kundennummer kopiert'), duration: Duration(seconds: 1)));
                },
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  // ===== TAB 3: VERSANDBOX =====
  Widget _buildVersandboxTab() {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Icon(Icons.fax, size: 18, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Text('Ihre Faxnummer: ', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            Text(_faxNummerRaw, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontFamily: 'monospace')),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.copy, size: 16, color: Colors.orange.shade400),
              tooltip: 'Kopieren',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _faxNummerRaw));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopiert'), duration: Duration(seconds: 1)));
              },
            ),
          ]),
        ),
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: TabBar(
            labelColor: Colors.orange.shade800,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: Colors.orange.shade800,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(icon: Icon(Icons.inbox, size: 14), text: 'Posteingang'),
              Tab(icon: Icon(Icons.send, size: 14), text: 'Postausgang'),
              Tab(icon: Icon(Icons.archive, size: 14), text: 'Archiv'),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _buildFaxTable('eingang'),
          _buildFaxTable('ausgang'),
          _buildFaxTable('archiv'),
        ])),
      ]),
    );
  }

  final Map<String, List<Map<String, dynamic>>> _faxe = {'eingang': [], 'ausgang': [], 'archiv': []};

  Future<void> _loadFaxe(String typ) async {
    final res = await widget.apiService.simplefaxAction({'action': 'list_faxe', 'typ': typ});
    if (mounted && res['success'] == true && res['faxe'] is List) {
      setState(() {
        _faxe[typ] = List<Map<String, dynamic>>.from((res['faxe'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      });
    }
  }

  Widget _buildFaxTable(String typ) {
    final rows = _faxe[typ] ?? [];
    if (rows.isEmpty) _loadFaxe(typ);
    final empfaengerLabel = typ == 'eingang' ? 'Absender' : 'Empfänger';
    return Stack(children: [
      Column(children: [
        Container(
          color: Colors.orange.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            _faxCol('Fax-ID', 90),
            _faxCol('Datum', 90),
            _faxCol('Uhrzeit', 70),
            _faxColExpanded(empfaengerLabel),
            _faxCol('Seiten', 50),
            _faxCol('Status', 70),
            _faxCol('Aktionen', 80),
          ]),
        ),
        Expanded(child: rows.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(typ == 'eingang' ? Icons.inbox : (typ == 'ausgang' ? Icons.send : Icons.archive), size: 40, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(typ == 'eingang' ? 'Keine eingehenden Faxe' : (typ == 'ausgang' ? 'Keine ausgehenden Faxe' : 'Archiv leer'),
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
            ]))
          : ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (_, i) {
                final r = rows[i];
                final datum = r['datum']?.toString() ?? '';
                final datumDe = datum.length >= 10 ? '${datum.substring(8,10)}.${datum.substring(5,7)}.${datum.substring(0,4)}' : datum;
                final uhr = (r['uhrzeit']?.toString() ?? '').padRight(5).substring(0, 5);
                return InkWell(
                  onTap: () => _showFaxDetailDialog(r, typ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      SizedBox(width: 90, child: Text('#${r['fax_id'] ?? ''}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                      _faxCell(datumDe, 90),
                      _faxCell(uhr, 70),
                      Expanded(child: Text(r['empfaenger']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                      _faxCell('${r['seiten'] ?? 1}', 50),
                      SizedBox(width: 70, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: (r['status']?.toString() == 'OK' ? Colors.green : Colors.grey).shade100, borderRadius: BorderRadius.circular(4)),
                        child: Text(r['status']?.toString() ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: (r['status']?.toString() == 'OK' ? Colors.green : Colors.grey).shade800), textAlign: TextAlign.center),
                      )),
                      SizedBox(width: 80, child: Row(children: [
                        IconButton(icon: Icon(Icons.visibility, size: 16, color: Colors.blue.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Anzeigen', onPressed: () => _showFaxDetailDialog(r, typ)),
                        IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Löschen', onPressed: () async {
                            await widget.apiService.simplefaxAction({'action': 'delete_fax', 'id': r['id']});
                            _loadFaxe(typ);
                          }),
                      ])),
                    ]),
                  ),
                );
              },
            )),
      ]),
      Positioned(
        right: 16, bottom: 16,
        child: FloatingActionButton.small(
          heroTag: 'add_fax_$typ',
          onPressed: () => _showFaxAddDialog(typ),
          backgroundColor: Colors.orange.shade700,
          tooltip: typ == 'eingang' ? 'Neues eingehendes Fax' : (typ == 'ausgang' ? 'Neues ausgehendes Fax' : 'Neues Archiv-Fax'),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    ]);
  }

  Widget _faxCol(String label, double w) => SizedBox(width: w, child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)));
  Widget _faxColExpanded(String label) => Expanded(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)));
  Widget _faxCell(String txt, double w) => SizedBox(width: w, child: Text(txt, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis));

  void _showFaxDetailDialog(Map<String, dynamic> r, String typ) {
    final datum = r['datum']?.toString() ?? '';
    final datumDe = datum.length >= 10 ? '${datum.substring(8,10)}.${datum.substring(5,7)}.${datum.substring(0,4)}' : datum;
    final faxId = r['id'] is int ? r['id'] as int : int.tryParse(r['id']?.toString() ?? '') ?? 0;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(Icons.fax, color: Colors.orange.shade700, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('FAX #${r['fax_id'] ?? ''}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontFamily: 'monospace'))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: (r['status']?.toString() == 'OK' ? Colors.green : Colors.grey).shade100, borderRadius: BorderRadius.circular(6)),
          child: Text(r['status']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: (r['status']?.toString() == 'OK' ? Colors.green : Colors.grey).shade800)),
        ),
      ]),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _faxDetailRow(Icons.calendar_today, 'Datum', '$datumDe ${(r['uhrzeit']?.toString() ?? '').substring(0, (r['uhrzeit']?.toString().length ?? 0).clamp(0, 5))}'),
        _faxDetailRow(typ == 'eingang' ? Icons.phone_callback : Icons.phone_forwarded, typ == 'eingang' ? 'Absender' : 'Empfänger', r['empfaenger']?.toString() ?? ''),
        _faxDetailRow(Icons.description, 'Seiten', '${r['seiten'] ?? 1}'),
        _faxDetailRow(Icons.label_outline, 'Typ', typ == 'eingang' ? 'Posteingang' : (typ == 'ausgang' ? 'Postausgang' : 'Archiv')),
        const SizedBox(height: 16),
        Divider(color: Colors.grey.shade200),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.picture_as_pdf, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 6),
          Text('Sendebericht & Dokumente', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: KorrAttachmentsWidget(
            apiService: widget.apiService,
            modul: 'simplefax_fax',
            korrespondenzId: faxId,
          ),
        ),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  Widget _faxDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.orange.shade600),
        const SizedBox(width: 10),
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'))),
      ]),
    );
  }

  void _showFaxAddDialog(String typ) {
    final faxIdC = TextEditingController();
    final empfaengerC = TextEditingController();
    final seitenC = TextEditingController(text: '1');
    final statusC = TextEditingController(text: 'OK');
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Row(children: [
        Icon(Icons.add_circle, color: Colors.orange.shade700, size: 20),
        const SizedBox(width: 8),
        Text('Neues Fax — ${typ == 'eingang' ? 'Posteingang' : (typ == 'ausgang' ? 'Postausgang' : 'Archiv')}', style: const TextStyle(fontSize: 15)),
      ]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _kontaktField(faxIdC, 'Fax-ID (z.B. 16728811)', Icons.tag, kbd: TextInputType.number),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text('${selectedDate.day.toString().padLeft(2, '0')}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.year}'),
            onPressed: () async {
              final picked = await showDatePicker(context: ctx, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (picked != null) setDlg(() => selectedDate = picked);
            },
          )),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.access_time, size: 16),
            label: Text('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
            onPressed: () async {
              final picked = await showTimePicker(context: ctx, initialTime: selectedTime);
              if (picked != null) setDlg(() => selectedTime = picked);
            },
          )),
        ]),
        const SizedBox(height: 10),
        _kontaktField(empfaengerC, typ == 'eingang' ? 'Absender (Fax-Nummer)' : 'Empfänger (Fax-Nummer)', Icons.fax, kbd: TextInputType.phone),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(width: 110, child: _kontaktField(seitenC, 'Seiten', Icons.description, kbd: TextInputType.number)),
          const SizedBox(width: 10),
          Expanded(child: _kontaktField(statusC, 'Status', Icons.check_circle_outline)),
        ]),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton.icon(
          onPressed: () async {
            final datum = '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
            final uhr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00';
            await widget.apiService.simplefaxAction({
              'action': 'save_fax',
              'fax': {
                'fax_id': faxIdC.text.trim(), 'typ': typ, 'datum': datum, 'uhrzeit': uhr,
                'seiten': int.tryParse(seitenC.text.trim()) ?? 1,
                'empfaenger': empfaengerC.text.trim(), 'status': statusC.text.trim(),
              },
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _loadFaxe(typ);
          },
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
        ),
      ],
    )));
  }

  // ===== TAB 4: ADRESSBUCH =====
  final List<Map<String, dynamic>> _kontakte = [];

  Widget _buildAdressbuchTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.contacts, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 8),
          Text('Adressbuch (${_kontakte.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange.shade800)),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _showKontaktDialog(null),
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text('Neuer Kontakt', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          ),
        ]),
      ),
      Expanded(child: _kontakte.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.contacts_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Kontakte vorhanden', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showKontaktDialog(null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Ersten Kontakt anlegen'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade700),
            ),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _kontakte.length,
            itemBuilder: (_, i) {
              final k = _kontakte[i];
              final name = '${k['vorname'] ?? ''} ${k['nachname'] ?? ''}'.trim();
              final firma = k['firma']?.toString() ?? '';
              final telefon = k['telefon']?.toString() ?? '';
              final fax = k['fax']?.toString() ?? '';
              final mobil = k['mobil']?.toString() ?? '';
              final anschriftZeile = [k['anschrift'], '${k['plz'] ?? ''} ${k['ort'] ?? ''}'.trim(), k['land']]
                  .where((e) => e != null && e.toString().isNotEmpty).join(', ');
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showKontaktDetail(i),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange.shade100,
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name.isEmpty ? '(ohne Namen)' : name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        if (firma.isNotEmpty) Text(firma, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        if (anschriftZeile.isNotEmpty) Text(anschriftZeile, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 12, runSpacing: 2, children: [
                          if (telefon.isNotEmpty) _kontaktBadge(Icons.phone, telefon, Colors.blue),
                          if (fax.isNotEmpty) _kontaktBadge(Icons.fax, fax, Colors.orange),
                          if (mobil.isNotEmpty) _kontaktBadge(Icons.smartphone, mobil, Colors.green),
                        ]),
                      ])),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                        onSelected: (v) async {
                          if (v == 'details') _showKontaktDetail(i);
                          if (v == 'edit') _showKontaktDialog(i);
                          if (v == 'del') {
                            await widget.apiService.simplefaxAction({'action': 'delete_adressbuch', 'id': k['id']});
                            _load();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'details', child: Row(children: [Icon(Icons.visibility, size: 16), SizedBox(width: 8), Text('Details')])),
                          PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Bearbeiten')])),
                          PopupMenuItem(value: 'del', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Löschen', style: TextStyle(color: Colors.red))])),
                        ],
                      ),
                    ]),
                  ),
                ),
              );
            },
          )),
    ]);
  }

  Widget _kontaktBadge(IconData icon, String txt, MaterialColor color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color.shade600),
      const SizedBox(width: 3),
      Text(txt, style: TextStyle(fontSize: 11, color: color.shade800)),
    ]);
  }

  void _showKontaktDetail(int i) {
    final k = _kontakte[i];
    final name = '${k['vorname'] ?? ''} ${k['nachname'] ?? ''}'.trim();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        CircleAvatar(backgroundColor: Colors.orange.shade100, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold))),
        const SizedBox(width: 12),
        Expanded(child: Text(name.isEmpty ? 'Details' : name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      ]),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _detailRow(Icons.business, 'Firma', k['firma']),
        _detailRow(Icons.home, 'Anschrift', [k['anschrift'], '${k['plz'] ?? ''} ${k['ort'] ?? ''}'.trim(), k['land']].where((e) => e != null && e.toString().isNotEmpty).join('\n')),
        _detailRow(Icons.phone, 'Telefon', k['telefon']),
        _detailRow(Icons.fax, 'Fax', k['fax']),
        _detailRow(Icons.smartphone, 'Mobil', k['mobil']),
      ]))),
      actions: [
        TextButton.icon(onPressed: () async {
          Navigator.pop(ctx);
          await widget.apiService.simplefaxAction({'action': 'delete_adressbuch', 'id': k['id']});
          _load();
        }, icon: const Icon(Icons.delete, size: 16, color: Colors.red), label: const Text('Löschen', style: TextStyle(color: Colors.red))),
        TextButton.icon(onPressed: () { Navigator.pop(ctx); _showKontaktDialog(i); }, icon: const Icon(Icons.edit, size: 16), label: const Text('Bearbeiten')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
      ],
    ));
  }

  Widget _detailRow(IconData icon, String label, dynamic value) {
    final v = value?.toString() ?? '';
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.orange.shade700),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ])),
      ]),
    );
  }

  void _showKontaktDialog(int? idx) {
    final isEdit = idx != null;
    final existing = isEdit ? _kontakte[idx] : <String, dynamic>{};
    final vorname = TextEditingController(text: existing['vorname']?.toString() ?? '');
    final nachname = TextEditingController(text: existing['nachname']?.toString() ?? '');
    final firma = TextEditingController(text: existing['firma']?.toString() ?? '');
    final anschrift = TextEditingController(text: existing['anschrift']?.toString() ?? '');
    final plz = TextEditingController(text: existing['plz']?.toString() ?? '');
    final ort = TextEditingController(text: existing['ort']?.toString() ?? '');
    final land = TextEditingController(text: existing['land']?.toString() ?? 'Deutschland');
    final telefon = TextEditingController(text: existing['telefon']?.toString() ?? '');
    final fax = TextEditingController(text: existing['fax']?.toString() ?? '');
    final mobil = TextEditingController(text: existing['mobil']?.toString() ?? '');

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(isEdit ? Icons.edit : Icons.person_add, size: 20, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        Text(isEdit ? 'Kontakt bearbeiten' : 'Neuer Kontakt', style: const TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: _kontaktField(vorname, 'Vorname', Icons.person)),
          const SizedBox(width: 10),
          Expanded(child: _kontaktField(nachname, 'Nachname', Icons.person_outline)),
        ]),
        const SizedBox(height: 10),
        _kontaktField(firma, 'Firma', Icons.business),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Row(children: [
          Icon(Icons.home, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text('Anschrift', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        ])),
        _kontaktField(anschrift, 'Straße und Hausnummer', Icons.location_on),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(width: 120, child: _kontaktField(plz, 'PLZ', Icons.markunread_mailbox)),
          const SizedBox(width: 10),
          Expanded(child: _kontaktField(ort, 'Ort', Icons.location_city)),
        ]),
        const SizedBox(height: 10),
        _kontaktField(land, 'Land', Icons.flag),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Row(children: [
          Icon(Icons.contact_phone, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text('Kontakt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        ])),
        _kontaktField(telefon, 'Telefon', Icons.phone, kbd: TextInputType.phone),
        const SizedBox(height: 10),
        _kontaktField(fax, 'Fax', Icons.fax, kbd: TextInputType.phone),
        const SizedBox(height: 10),
        _kontaktField(mobil, 'Mobil', Icons.smartphone, kbd: TextInputType.phone),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton.icon(
          onPressed: () async {
            final kontakt = <String, dynamic>{
              'vorname': vorname.text.trim(), 'nachname': nachname.text.trim(), 'firma': firma.text.trim(),
              'anschrift': anschrift.text.trim(), 'plz': plz.text.trim(), 'ort': ort.text.trim(), 'land': land.text.trim(),
              'telefon': telefon.text.trim(), 'fax': fax.text.trim(), 'mobil': mobil.text.trim(),
            };
            if (isEdit) kontakt['id'] = existing['id'];
            await widget.apiService.simplefaxAction({'action': 'save_adressbuch', 'kontakt': kontakt});
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
        ),
      ],
    ));
  }

  Widget _kontaktField(TextEditingController c, String label, IconData icon, {TextInputType? kbd}) {
    return TextField(
      controller: c,
      keyboardType: kbd,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ===== TAB 5: PREISE =====
  Widget _buildPreiseTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.euro, color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 8),
          Text('Preisübersicht', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
        ]),
        const SizedBox(height: 4),
        Text('Faxversand pro Seite • Empfang kostenlos • Prepaid ohne Grundgebühr',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 16),

        Row(children: [
          Expanded(child: _preisTier(Colors.green, Icons.home, 'Deutschland', 'Festnetz', '7', 'ct / Seite')),
          const SizedBox(width: 10),
          Expanded(child: _preisTier(Colors.blue, Icons.public, 'Europa', 'EU-Länder', 'ab 9', 'ct / Seite')),
          const SizedBox(width: 10),
          Expanded(child: _preisTier(Colors.red, Icons.travel_explore, 'Welt', 'Übrige Länder', 'bis 19', 'ct / Seite')),
        ]),
        const SizedBox(height: 20),

        Row(children: [
          Icon(Icons.map, color: Colors.orange.shade700, size: 18),
          const SizedBox(width: 6),
          Text('Preise nach Kontinent', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
        ]),
        const SizedBox(height: 12),

        LayoutBuilder(builder: (ctx, cons) {
          final cols = cons.maxWidth > 700 ? 3 : 2;
          final w = (cons.maxWidth - (cols - 1) * 10) / cols;
          final items = [
            _kontinentCard(w, Colors.blue, Icons.public, 'Europa', 'ab 9 ct', ['Deutschland: 7 ct', 'Österreich, Schweiz', 'Frankreich, Italien', 'Spanien, Polen, NL']),
            _kontinentCard(w, Colors.indigo, Icons.flag, 'Nordamerika', 'ab 9 ct', ['USA, Kanada', 'Mexiko']),
            _kontinentCard(w, Colors.teal, Icons.terrain, 'Südamerika', 'ab 12 ct', ['Brasilien, Argentinien', 'Chile, Kolumbien', 'Peru']),
            _kontinentCard(w, Colors.deepOrange, Icons.temple_buddhist, 'Asien', 'ab 12 ct', ['Japan, China', 'Indien, Türkei', 'Israel, VAE']),
            _kontinentCard(w, Colors.brown, Icons.landscape, 'Afrika', 'ab 15 ct', ['Südafrika, Ägypten', 'Marokko, Tunesien', 'Kenia, Nigeria']),
            _kontinentCard(w, Colors.purple, Icons.water, 'Ozeanien', 'ab 12 ct', ['Australien', 'Neuseeland']),
          ];
          return Wrap(spacing: 10, runSpacing: 10, children: items);
        }),

        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade200)),
          child: Row(children: [
            Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Genauer Preis pro Zielnummer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
              const SizedBox(height: 2),
              Text('Auf simple-fax.de/preisliste die Ziel-Faxnummer eingeben — der centgenau Preis wird angezeigt. Mobilfunk-Faxnummern sind durchgehend teurer als Festnetz.',
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900)),
            ])),
          ]),
        ),

        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _serviceFact(Icons.savings, 'Grundgebühr', '0,00 €', Colors.green)),
          const SizedBox(width: 10),
          Expanded(child: _serviceFact(Icons.inbox, 'Empfang', 'kostenlos', Colors.blue)),
          const SizedBox(width: 10),
          Expanded(child: _serviceFact(Icons.account_balance_wallet, 'Aufladung', '5 – 50 €', Colors.orange)),
        ]),
      ]),
    );
  }

  Widget _preisTier(MaterialColor color, IconData icon, String region, String sub, String preis, String einheit) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.shade500, color.shade700], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: color.shade100, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(region, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
        const SizedBox(height: 8),
        Text(preis, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(einheit, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11)),
      ]),
    );
  }

  Widget _kontinentCard(double w, MaterialColor color, IconData icon, String name, String ab, List<String> beispiele) {
    return SizedBox(
      width: w,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.shade200),
          boxShadow: [BoxShadow(color: color.shade50, blurRadius: 4)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 14, backgroundColor: color.shade100, child: Icon(icon, size: 14, color: color.shade700)),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade900))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade300)),
              child: Text(ab, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800)),
            ),
          ]),
          const SizedBox(height: 8),
          ...beispiele.map((b) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              Container(width: 4, height: 4, decoration: BoxDecoration(color: color.shade400, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(b, style: TextStyle(fontSize: 11, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _serviceFact(IconData icon, String label, String value, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade100)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color.shade700, size: 18),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: color.shade700)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade900)),
      ]),
    );
  }

  // ===== TAB 8: VERIFIZIERUNG =====
  static const Map<String, Map<String, dynamic>> _verifStatusMap = {
    'nicht_verifiziert': {'label': 'Nicht verifiziert', 'color': Colors.grey, 'icon': Icons.help_outline},
    'in_pruefung': {'label': 'In Prüfung', 'color': Colors.orange, 'icon': Icons.hourglass_top},
    'verifiziert': {'label': 'Verifiziert', 'color': Colors.green, 'icon': Icons.verified},
    'abgelehnt': {'label': 'Abgelehnt', 'color': Colors.red, 'icon': Icons.cancel},
  };

  static const Map<String, Map<String, dynamic>> _verifMethodeMap = {
    'handelsregister': {'label': 'Handelsregister-Auszug (Verein/Firma)', 'icon': Icons.business, 'hint': 'Für Vereine: Vereinsregister-Auszug (VR-Nummer)'},
    'adressnachweis': {'label': 'Adressnachweis (Privatperson)', 'icon': Icons.home, 'hint': 'Meldebescheinigung, Mietvertrag, etc.'},
    'ausweis': {'label': 'Personalausweis / Reisepass', 'icon': Icons.badge, 'hint': 'Vorder- und Rückseite'},
    'sonstiges': {'label': 'Sonstiges Dokument', 'icon': Icons.description, 'hint': 'Andere offizielle Nachweise'},
  };

  Widget _buildVerifizierungTab() {
    final statusKey = _verifizierung['status']?.toString() ?? 'nicht_verifiziert';
    final status = _verifStatusMap[statusKey] ?? _verifStatusMap['nicht_verifiziert']!;
    final methodeKey = _verifizierung['methode']?.toString() ?? 'handelsregister';
    final methode = _verifMethodeMap[methodeKey] ?? _verifMethodeMap['handelsregister']!;
    final datum = _verifizierung['datum']?.toString() ?? '';
    final notiz = _verifizierung['notiz']?.toString() ?? '';
    final statusColor = status['color'] as MaterialColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.verified_user, color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 8),
          Text('Konto-Verifizierung', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
              const SizedBox(width: 3),
              Text('AES-256', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
            ]),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _showVerifizierungDialog,
            icon: const Icon(Icons.edit, size: 14),
            label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade700, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Status der Konto-Verifizierung bei SimpleFax', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 20),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [statusColor.shade500, statusColor.shade700], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: statusColor.shade100, blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              child: Icon(status['icon'] as IconData, size: 32, color: Colors.white)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Verifizierungsstatus', style: TextStyle(color: Colors.white, fontSize: 13)),
              const SizedBox(height: 4),
              Text(status['label'] as String, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              if (datum.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Eingereicht am: $datum', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
              ],
            ])),
          ]),
        ),

        const SizedBox(height: 20),
        Text('Verifizierungsmethode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
          child: Row(children: [
            Icon(methode['icon'] as IconData, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(methode['label'] as String, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
              const SizedBox(height: 2),
              Text(methode['hint'] as String, style: TextStyle(fontSize: 11, color: Colors.blue.shade800)),
            ])),
          ]),
        ),

        if (notiz.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Notiz', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
            child: Text(notiz, style: const TextStyle(fontSize: 13)),
          ),
        ],

        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade200)),
          child: Row(children: [
            Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hinweis für Vereine', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
              const SizedBox(height: 2),
              Text(
                'ICD360S e.V. wird als Verein verifiziert. Lade hier den aktuellen Vereinsregister-Auszug (Handelsregister äquivalent) hoch — VR-Nummer + Bestätigung des Vorstands.',
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
              ),
            ])),
          ]),
        ),

        const SizedBox(height: 20),
        Row(children: [
          Icon(Icons.attach_file, size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Text('Verifizierungsdokumente', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade100)),
          child: KorrAttachmentsWidget(
            apiService: widget.apiService,
            modul: 'simplefax_verifizierung',
            korrespondenzId: 1,
          ),
        ),
      ]),
    );
  }

  void _showVerifizierungDialog() {
    String statusSel = _verifizierung['status']?.toString().isNotEmpty == true
        ? _verifizierung['status'].toString()
        : 'nicht_verifiziert';
    String methodeSel = _verifizierung['methode']?.toString().isNotEmpty == true
        ? _verifizierung['methode'].toString()
        : 'handelsregister';
    final datumC = TextEditingController(text: _verifizierung['datum']?.toString() ?? '');
    final notizC = TextEditingController(text: _verifizierung['notiz']?.toString() ?? '');

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Row(children: [
        Icon(Icons.edit, size: 20, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        const Text('Verifizierung bearbeiten', style: TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: _verifStatusMap.entries.map((e) {
          final c = e.value['color'] as MaterialColor;
          return ChoiceChip(
            avatar: Icon(e.value['icon'] as IconData, size: 14, color: c.shade700),
            label: Text(e.value['label'] as String, style: const TextStyle(fontSize: 11)),
            selected: statusSel == e.key,
            selectedColor: c.shade100,
            onSelected: (_) => setDlg(() => statusSel = e.key),
          );
        }).toList()),
        const SizedBox(height: 14),
        Text('Methode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        RadioGroup<String>(
          groupValue: methodeSel,
          onChanged: (v) => setDlg(() => methodeSel = v ?? methodeSel),
          child: Column(children: _verifMethodeMap.entries.map((e) => RadioListTile<String>(
            dense: true,
            value: e.key,
            title: Row(children: [
              Icon(e.value['icon'] as IconData, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(e.value['label'] as String, style: const TextStyle(fontSize: 12)),
            ]),
            subtitle: Text(e.value['hint'] as String, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            contentPadding: EdgeInsets.zero,
          )).toList()),
        ),
        const SizedBox(height: 10),
        TextField(controller: datumC,
          decoration: InputDecoration(labelText: 'Eingereicht am (TT.MM.JJJJ)', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 3,
          decoration: InputDecoration(labelText: 'Notiz', hintText: 'Bemerkungen zur Verifizierung...', isDense: true, prefixIcon: const Icon(Icons.note, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton.icon(
          onPressed: () async {
            final res = await widget.apiService.simplefaxAction({
              'action': 'save_verifizierung',
              'status': statusSel,
              'methode': methodeSel,
              'datum': datumC.text.trim(),
              'notiz': notizC.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(res['success'] == true ? 'Gespeichert' : (res['message']?.toString() ?? 'Fehler')),
                backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                duration: const Duration(seconds: 1),
              ));
            }
            _load();
          },
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
        ),
      ],
    )));
  }

  // ===== TAB 6: KONTOEINSTELLUNGEN =====
  String _kontoSection = 'persoenliche_daten';

  static const List<Map<String, dynamic>> _kontoMenu = [
    {'id': 'persoenliche_daten', 'icon': Icons.person, 'label': 'Persönliche Daten'},
    {'id': 'kontostand', 'icon': Icons.account_balance, 'label': 'Kontostand'},
    {'id': 'guthaben_kaufen', 'icon': Icons.shopping_cart, 'label': 'Guthaben kaufen'},
    {'id': 'rechnungen', 'icon': Icons.receipt_long, 'label': 'Rechnungen'},
    {'id': 'gutschein', 'icon': Icons.redeem, 'label': 'Gutschein einlösen'},
    {'id': 'email_adressen', 'icon': Icons.alternate_email, 'label': 'E-Mail Adressen bearbeiten'},
    {'id': 'faxnummer_einst', 'icon': Icons.fax, 'label': 'Faxnummer Einstellungen'},
    {'id': 'fax_absender', 'icon': Icons.edit_note, 'label': 'Fax Absender bearbeiten'},
    {'id': 'passwort', 'icon': Icons.lock, 'label': 'Passwort ändern'},
    {'id': 'konto_loeschen', 'icon': Icons.delete_forever, 'label': 'Kundenkonto löschen', 'danger': true},
    {'id': 'versandbox_leeren', 'icon': Icons.delete_sweep, 'label': 'Versandbox leeren'},
    {'id': 'email_benachr', 'icon': Icons.notifications, 'label': 'E-Mail-Benachrichtigungen'},
  ];

  Widget _buildKontoeinstellungenTab() {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 260,
        decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(right: BorderSide(color: Colors.grey.shade300))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Icon(Icons.manage_accounts, size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text('Kontoeinstellungen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
              ]),
            ),
            ..._kontoMenu.map((m) {
              final isSel = _kontoSection == m['id'];
              final danger = m['danger'] == true;
              final color = danger ? Colors.red : Colors.orange;
              return InkWell(
                onTap: () => setState(() => _kontoSection = m['id'] as String),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSel ? color.shade50 : Colors.transparent,
                    border: Border(left: BorderSide(color: isSel ? color.shade700 : Colors.transparent, width: 3)),
                  ),
                  child: Row(children: [
                    Icon(m['icon'] as IconData, size: 16, color: isSel ? color.shade700 : (danger ? Colors.red.shade400 : Colors.grey.shade600)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m['label'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? color.shade800 : (danger ? Colors.red.shade400 : Colors.grey.shade800),
                      ))),
                    if (isSel) Icon(Icons.chevron_right, size: 14, color: color.shade700),
                  ]),
                ),
              );
            }),
          ]),
        ),
      ),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _buildKontoContent(),
      )),
    ]);
  }

  Widget _buildKontoContent() {
    switch (_kontoSection) {
      case 'persoenliche_daten': return _buildPersoenlicheDaten();
      case 'kontostand': return _buildKontostand();
      case 'guthaben_kaufen': return _buildGuthabenKaufen();
      case 'rechnungen': return _buildRechnungen();
      case 'gutschein': return _buildGutschein();
      case 'email_adressen': return _buildEmailAdressen();
      case 'faxnummer_einst': return _buildFaxnummerEinstellungen();
      case 'fax_absender': return _buildFaxAbsender();
      case 'passwort': return _buildPasswortAendern();
      case 'konto_loeschen': return _buildKontoLoeschen();
      case 'versandbox_leeren': return _buildVersandboxLeeren();
      case 'email_benachr': return _buildEmailBenachrichtigungen();
      default:
        final m = _kontoMenu.firstWhere((e) => e['id'] == _kontoSection, orElse: () => _kontoMenu.first);
        return _buildPlaceholderTab(m['icon'] as IconData, m['label'] as String, 'In Bearbeitung');
    }
  }

  Widget _kontoSectionTitle(IconData icon, String title, String subtitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: Colors.orange.shade700, size: 22),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
            const SizedBox(width: 3),
            Text('AES-256', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
          ]),
        ),
      ]),
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
      const SizedBox(height: 16),
    ]);
  }

  // ===== KONTOSTAND =====
  Widget _buildKontostand() {
    final stand = double.tryParse(_data['kontostand']?.toString() ?? '0') ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.account_balance, 'Kontostand', 'Aktuelles Guthaben und Auflademöglichkeiten'),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.green.shade600, Colors.green.shade800]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.green.shade100, blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.savings, size: 32, color: Colors.white)),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ihr Kontostand', style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 4),
            Text('${stand.toStringAsFixed(2).replaceAll('.', ',')} €',
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          ]),
        ]),
      ),
      const SizedBox(height: 20),
      Text('Laden Sie Ihr Konto jetzt auf:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _topupBtn(Icons.account_balance_wallet, 'PayPal', Colors.blue, () => setState(() => _kontoSection = 'guthaben_kaufen')),
        _topupBtn(Icons.swap_horiz, 'Sofortüberweisung', Colors.deepPurple, () => setState(() => _kontoSection = 'guthaben_kaufen')),
        _topupBtn(Icons.credit_card, 'Kreditkarte', Colors.indigo, () => setState(() => _kontoSection = 'guthaben_kaufen')),
        _topupBtn(Icons.account_balance, 'Lastschrift', Colors.teal, () => setState(() => _kontoSection = 'guthaben_kaufen')),
      ]),
      const SizedBox(height: 24),
      Row(children: [
        Icon(Icons.list_alt, size: 18, color: Colors.orange.shade700),
        const SizedBox(width: 6),
        Text('Kontoauszug', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
      ]),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Container(
            color: Colors.orange.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              SizedBox(width: 90, child: Text('Datum', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
              SizedBox(width: 60, child: Text('Uhrzeit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
              Expanded(child: Text('Verwendungszweck', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
              SizedBox(width: 80, child: Text('Preis', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
            ]),
          ),
          if (_kontoauszug.isEmpty) Padding(padding: const EdgeInsets.all(20),
            child: Text('Keine Einträge', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)))
          else ..._kontoauszug.map((r) {
            final preis = double.tryParse(r['preis']?.toString() ?? '0') ?? 0;
            final isPositive = preis >= 0;
            final typ = r['typ']?.toString() ?? 'fax';
            final color = typ == 'aufladung' ? Colors.blue : (typ == 'gutschrift' ? Colors.green : (isPositive ? Colors.green : Colors.red));
            final datum = r['datum']?.toString() ?? '';
            String datumDe = datum;
            if (datum.length >= 10) {
              datumDe = '${datum.substring(8,10)}.${datum.substring(5,7)}.${datum.substring(0,4)}';
            }
            final uhr = (r['uhrzeit']?.toString() ?? '').padRight(5).substring(0, 5);
            return Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                SizedBox(width: 90, child: Text(datumDe, style: const TextStyle(fontSize: 12))),
                SizedBox(width: 60, child: Text(uhr, style: const TextStyle(fontSize: 12))),
                Expanded(child: Text(r['verwendungszweck']?.toString() ?? '', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                SizedBox(width: 80, child: Text(
                  '${isPositive ? '+' : ''}${preis.toStringAsFixed(2).replaceAll('.', ',')} €',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade700),
                )),
              ]),
            );
          }),
        ]),
      ),
    ]);
  }

  Widget _topupBtn(IconData icon, String label, MaterialColor color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade200)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color.shade700),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color.shade800)),
        ]),
      ),
    );
  }

  // ===== GUTHABEN KAUFEN =====
  String _topupMethod = 'paypal';
  final _topupBetragController = TextEditingController(text: '10.00');

  Widget _buildGuthabenKaufen() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.shopping_cart, 'Guthaben kaufen', 'Laden Sie jetzt Ihr Konto auf'),
      Row(children: [
        _methodChip('paypal', Icons.account_balance_wallet, 'PayPal', Colors.blue),
        const SizedBox(width: 10),
        _methodChip('kreditkarte', Icons.credit_card, 'Kreditkarte', Colors.indigo),
        const SizedBox(width: 10),
        _methodChip('lastschrift', Icons.account_balance, 'Lastschrift', Colors.teal),
      ]),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade100)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_methodIcon(_topupMethod), size: 36, color: _methodColor(_topupMethod).shade700),
            const SizedBox(width: 12),
            Text(_methodLabel(_topupMethod), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _methodColor(_topupMethod).shade900)),
          ]),
          const SizedBox(height: 10),
          Text(_methodHint(_topupMethod), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 14),
          SizedBox(width: 220, child: TextField(
            controller: _topupBetragController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Betrag (€)', helperText: 'Endsumme, inkl. MwSt.',
              isDense: true,
              prefixIcon: const Icon(Icons.euro, size: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          )),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _kaufenGuthaben,
            icon: const Icon(Icons.shopping_cart, size: 16),
            label: const Text('Guthaben kaufen'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          ),
          const SizedBox(height: 12),
          Text(
            'Es gelten die AGB von simple-fax.de. Verbraucher haben ein 14-tägiges Widerrufsrecht.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
        ]),
      ),
    ]);
  }

  Widget _methodChip(String id, IconData icon, String label, MaterialColor color) {
    final sel = _topupMethod == id;
    return InkWell(
      onTap: () => setState(() => _topupMethod = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? color.shade100 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? color.shade400 : Colors.grey.shade300, width: sel ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: sel ? color.shade700 : Colors.grey.shade500),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.bold : FontWeight.normal, color: sel ? color.shade800 : Colors.grey.shade700)),
        ]),
      ),
    );
  }

  IconData _methodIcon(String m) => m == 'paypal' ? Icons.account_balance_wallet : (m == 'kreditkarte' ? Icons.credit_card : Icons.account_balance);
  String _methodLabel(String m) => m == 'paypal' ? 'PayPal' : (m == 'kreditkarte' ? 'Kreditkarte' : 'Lastschrift');
  MaterialColor _methodColor(String m) => m == 'paypal' ? Colors.blue : (m == 'kreditkarte' ? Colors.indigo : Colors.teal);
  String _methodHint(String m) {
    switch (m) {
      case 'paypal': return 'Hier können Sie Ihr Konto per PayPal aufladen. Sie werden zu PayPal.de weitergeleitet.';
      case 'kreditkarte': return 'Hier können Sie Ihr Konto per Kreditkarte (Visa, Mastercard) aufladen.';
      case 'lastschrift': return 'Hier können Sie Ihr Konto per SEPA-Lastschrift aufladen.';
      default: return '';
    }
  }

  Future<void> _kaufenGuthaben() async {
    final betrag = _topupBetragController.text.trim();
    final parsed = double.tryParse(betrag.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ungültiger Betrag'), backgroundColor: Colors.red));
      return;
    }
    final label = 'Aufladung via ${_methodLabel(_topupMethod)}';
    final now = DateTime.now();
    final datum = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final uhr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    await widget.apiService.simplefaxAction({
      'action': 'save_kontoauszug',
      'auszug': {'datum': datum, 'uhrzeit': uhr, 'typ': 'aufladung', 'verwendungszweck': label, 'preis': parsed.toStringAsFixed(2)},
    });
    final newStand = (double.tryParse(_data['kontostand']?.toString() ?? '0') ?? 0) + parsed;
    await widget.apiService.simplefaxAction({'action': 'save_kontostand', 'kontostand': newStand.toStringAsFixed(2)});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${parsed.toStringAsFixed(2)} € aufgeladen'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)));
      setState(() => _kontoSection = 'kontostand');
    }
    _load();
  }

  // ===== RECHNUNGEN =====
  Widget _buildRechnungen() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.receipt_long, 'Rechnungen', 'Alle Rechnungen für Ihre Kontoaufladungen'),
      if (_rechnungen.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          alignment: Alignment.center,
          child: Column(children: [
            Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Rechnungen vorhanden', style: TextStyle(color: Colors.grey.shade400)),
          ]),
        )
      else
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Container(
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                SizedBox(width: 110, child: Text('Datum', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
                Expanded(child: Text('Rechnungsnummer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
                SizedBox(width: 90, child: Text('Betrag', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
                const SizedBox(width: 40),
              ]),
            ),
            ..._rechnungen.map((r) {
              final betrag = double.tryParse(r['betrag']?.toString() ?? '0') ?? 0;
              final datum = r['datum']?.toString() ?? '';
              String datumDe = datum;
              if (datum.length >= 10) datumDe = '${datum.substring(8,10)}.${datum.substring(5,7)}.${datum.substring(0,4)}';
              return Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  SizedBox(width: 110, child: Text(datumDe, style: const TextStyle(fontSize: 13))),
                  Expanded(child: Text(r['nummer']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontFamily: 'monospace'))),
                  SizedBox(width: 90, child: Text('${betrag.toStringAsFixed(2).replaceAll('.', ',')} €', textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
                  IconButton(icon: Icon(Icons.download, size: 16, color: Colors.orange.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    tooltip: 'Rechnung als PDF', onPressed: () {}),
                ]),
              );
            }),
          ]),
        ),
    ]);
  }

  // ===== GUTSCHEIN =====
  final _gutscheinController = TextEditingController();
  Widget _buildGutschein() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.redeem, 'Gutschein einlösen', 'Geben Sie Ihren Gutschein-Code ein, um Guthaben zu erhalten'),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.card_giftcard, color: Colors.amber.shade700, size: 32),
            const SizedBox(width: 12),
            const Text('Gutschein-Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 14),
          SizedBox(width: 360, child: TextField(
            controller: _gutscheinController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Gutschein-Code',
              hintText: 'XXXX-XXXX-XXXX',
              isDense: true,
              prefixIcon: const Icon(Icons.confirmation_number, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          )),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              final code = _gutscheinController.text.trim();
              if (code.isEmpty) return;
              final now = DateTime.now();
              await widget.apiService.simplefaxAction({
                'action': 'save_kontoauszug',
                'auszug': {
                  'datum': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                  'uhrzeit': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00',
                  'typ': 'gutschrift', 'verwendungszweck': 'Gutschein eingelöst: $code', 'preis': '0.00',
                },
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Code "$code" eingereicht'), backgroundColor: Colors.green));
                _gutscheinController.clear();
              }
              _load();
            },
            icon: const Icon(Icons.redeem, size: 16),
            label: const Text('Gutschein einlösen'),
            style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
          ),
        ]),
      ),
    ]);
  }

  // ===== E-MAIL ADRESSEN =====
  final _newEmailController = TextEditingController();
  final _newEmailRepController = TextEditingController();
  final _mail2faxNewController = TextEditingController();

  Widget _buildEmailAdressen() {
    final primEmail = _data['primaere_email']?.toString() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.alternate_email, 'E-Mail Adressen bearbeiten', ''),
      Text('Primäre E-Mail Adresse ändern', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 140, child: Text('Primäre E-Mail', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
            Text(primEmail.isEmpty ? '—' : primEmail, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _newEmailController, keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Neue E-Mail', isDense: true, prefixIcon: const Icon(Icons.email, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextField(controller: _newEmailRepController, keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Neue E-Mail (Wdh.)', isDense: true, prefixIcon: const Icon(Icons.email, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              if (_newEmailController.text.trim() != _newEmailRepController.text.trim()) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-Mails stimmen nicht überein'), backgroundColor: Colors.red));
                return;
              }
              if (_newEmailController.text.trim().isEmpty) return;
              await widget.apiService.simplefaxAction({'action': 'save_primaere_email', 'primaere_email': _newEmailController.text.trim()});
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geändert'), backgroundColor: Colors.green));
              _newEmailController.clear();
              _newEmailRepController.clear();
              _load();
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Änderung durchführen'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          ),
        ]),
      ),
      const SizedBox(height: 24),
      Text('Mail2Fax Adressen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
      const SizedBox(height: 4),
      Text('E-Mails von diesen Adressen werden automatisch als Fax versendet', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      const SizedBox(height: 10),
      ..._mail2fax.map((m) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          dense: true,
          leading: Icon(Icons.email, size: 18, color: Colors.orange.shade600),
          title: Text(m['email']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
            onPressed: () async {
              await widget.apiService.simplefaxAction({'action': 'delete_mail2fax', 'id': m['id']});
              _load();
            },
          ),
        ),
      )),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: _mail2faxNewController, keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'E-Mail hinzufügen', isDense: true, prefixIcon: const Icon(Icons.add, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: () async {
            final em = _mail2faxNewController.text.trim();
            if (em.isEmpty) return;
            await widget.apiService.simplefaxAction({'action': 'save_mail2fax', 'email': em});
            _mail2faxNewController.clear();
            _load();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Hinzufügen'),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
        ),
      ]),
    ]);
  }

  // ===== FAXNUMMER EINSTELLUNGEN =====
  final _faxEmpfangsEmailController = TextEditingController();
  Widget _buildFaxnummerEinstellungen() {
    final primEmail = _data['primaere_email']?.toString() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.fax, 'Faxnummer Einstellungen', 'E-Mail für Faxempfang ändern'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 160, child: Text('Ihre Faxnummer', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
            Text(_faxNummerRaw, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontFamily: 'monospace')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(width: 160, child: Text('Aktuelle E-Mail', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
            Text(primEmail.isEmpty ? '—' : primEmail, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _faxEmpfangsEmailController, keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Neue E-Mailadresse', isDense: true, prefixIcon: const Icon(Icons.email, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              final em = _faxEmpfangsEmailController.text.trim();
              if (em.isEmpty) return;
              await widget.apiService.simplefaxAction({'action': 'save_primaere_email', 'primaere_email': em});
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geändert'), backgroundColor: Colors.green));
              _faxEmpfangsEmailController.clear();
              _load();
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Änderung durchführen'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          ),
        ]),
      ),
    ]);
  }

  // ===== FAX ABSENDER =====
  final _newAbsenderController = TextEditingController();
  final _newAbsenderRepController = TextEditingController();
  Widget _buildFaxAbsender() {
    final akt = _data['fax_absender']?.toString() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.edit_note, 'Fax Absender ändern', 'Diese Bezeichnung erscheint als Absender auf Ihren Faxen'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 180, child: Text('Aktueller Absender', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
            Text(akt.isEmpty ? '—' : akt, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _newAbsenderController,
            decoration: InputDecoration(labelText: 'Neuer Absender', isDense: true, prefixIcon: const Icon(Icons.edit, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextField(controller: _newAbsenderRepController,
            decoration: InputDecoration(labelText: 'Neuer Absender (Wdh.)', isDense: true, prefixIcon: const Icon(Icons.edit, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              if (_newAbsenderController.text.trim() != _newAbsenderRepController.text.trim()) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eingaben stimmen nicht überein'), backgroundColor: Colors.red));
                return;
              }
              await widget.apiService.simplefaxAction({'action': 'save_fax_absender', 'fax_absender': _newAbsenderController.text.trim()});
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geändert'), backgroundColor: Colors.green));
              _newAbsenderController.clear();
              _newAbsenderRepController.clear();
              _load();
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Änderung durchführen'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          ),
        ]),
      ),
    ]);
  }

  // ===== PASSWORT ÄNDERN =====
  final _aktPwController = TextEditingController();
  final _neuPwController = TextEditingController();
  final _neuPwRepController = TextEditingController();
  Widget _buildPasswortAendern() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.lock, 'Passwort ändern', 'Aus Sicherheitsgründen das aktuelle Passwort bestätigen'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _aktPwController, obscureText: true,
            decoration: InputDecoration(labelText: 'Aktuelles Passwort', isDense: true, prefixIcon: const Icon(Icons.lock_outline, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextField(controller: _neuPwController, obscureText: true,
            decoration: InputDecoration(labelText: 'Neues Passwort', isDense: true, prefixIcon: const Icon(Icons.lock, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextField(controller: _neuPwRepController, obscureText: true,
            decoration: InputDecoration(labelText: 'Neues Passwort (Wdh.)', isDense: true, prefixIcon: const Icon(Icons.lock, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              if (_neuPwController.text != _neuPwRepController.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Neue Passwörter stimmen nicht überein'), backgroundColor: Colors.red));
                return;
              }
              if (_neuPwController.text.isEmpty) return;
              final res = await widget.apiService.simplefaxAction({'action': 'change_passwort', 'current': _aktPwController.text, 'new': _neuPwController.text});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(res['success'] == true ? 'Passwort geändert' : (res['message']?.toString() ?? 'Fehler')),
                  backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                ));
                if (res['success'] == true) {
                  _aktPwController.clear();
                  _neuPwController.clear();
                  _neuPwRepController.clear();
                  _load();
                }
              }
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Passwort ändern'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          ),
        ]),
      ),
    ]);
  }

  // ===== KUNDENKONTO LÖSCHEN =====
  final _delKontoPwController = TextEditingController();
  Widget _buildKontoLoeschen() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.delete_forever, 'Kundenkonto löschen', ''),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.warning, color: Colors.red.shade700, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Damit Sie Ihr Nutzerkonto löschen können, müssen Sie Ihr Passwort eingeben. Sollten Sie Ihr Passwort vergessen haben, nutzen Sie bitte die "Passwort vergessen"-Funktion oder wenden sich an den Kundenservice.',
              style: TextStyle(fontSize: 12, color: Colors.red.shade900),
            )),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _delKontoPwController, obscureText: true,
            decoration: InputDecoration(labelText: 'Passwort', isDense: true, prefixIcon: const Icon(Icons.lock, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kontolöschung über simple-fax.de Web-Interface bestätigen'), backgroundColor: Colors.orange, duration: Duration(seconds: 3)));
            },
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('Konto löschen'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          ),
        ]),
      ),
    ]);
  }

  // ===== VERSANDBOX LEEREN =====
  final _delBoxPwController = TextEditingController();
  Widget _buildVersandboxLeeren() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.delete_sweep, 'Versandbox leeren', ''),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Geben Sie Ihr Passwort ein, um alle Einträge aus der Versandbox zu löschen.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            )),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _delBoxPwController, obscureText: true,
            decoration: InputDecoration(labelText: 'Passwort', isDense: true, prefixIcon: const Icon(Icons.lock, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Versandbox-Leerung über simple-fax.de Web-Interface'), backgroundColor: Colors.orange, duration: Duration(seconds: 3)));
            },
            icon: const Icon(Icons.delete_sweep, size: 16),
            label: const Text('Versandbox leeren'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
          ),
        ]),
      ),
    ]);
  }

  // ===== E-MAIL-BENACHRICHTIGUNGEN =====
  static const List<Map<String, String>> _notifyKeys = [
    {'id': 'status_send', 'label': 'Ich möchte per E-Mail über den Status versendeter Faxe informiert werden.'},
    {'id': 'send_pdf', 'label': 'Übertragungsbericht als PDF-Anhang', 'sub': '1'},
    {'id': 'send_link', 'label': 'Übertragungsbericht als sicheren Link', 'sub': '1'},
    {'id': 'status_recv', 'label': 'Ich möchte per E-Mail über eingehende Faxe informiert werden.'},
    {'id': 'recv_pdf', 'label': 'Empfangenes Fax als PDF-Anhang', 'sub': '1'},
    {'id': 'recv_link', 'label': 'Empfangenes Fax als sicheren Link', 'sub': '1'},
    {'id': 'guthaben_warn', 'label': 'Ich möchte Guthabenwarnungen per E-Mail erhalten'},
    {'id': 'news', 'label': 'Ich möchte über Ankündigungen, besondere Aktionen und Systemausfälle per E-Mail informiert werden'},
  ];

  Widget _buildEmailBenachrichtigungen() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kontoSectionTitle(Icons.notifications, 'E-Mail-Benachrichtigungen', 'Hier können Sie festlegen, welche E-Mails Sie von simple-fax.de erhalten wollen'),
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
        child: Column(children: _notifyKeys.map((k) {
          final id = k['id']!;
          final sub = k['sub'] == '1';
          final checked = _notifySettings[id] == true;
          return Padding(
            padding: EdgeInsets.only(left: sub ? 32 : 0),
            child: CheckboxListTile(
              dense: true,
              activeColor: Colors.orange.shade700,
              controlAffinity: ListTileControlAffinity.leading,
              value: checked,
              onChanged: (v) async {
                setState(() => _notifySettings[id] = v ?? false);
                await widget.apiService.simplefaxAction({'action': 'save_notify_settings', 'notify_settings': _notifySettings});
              },
              title: Text(k['label']!, style: TextStyle(fontSize: 12, fontWeight: sub ? FontWeight.normal : FontWeight.w600)),
            ),
          );
        }).toList()),
      ),
    ]);
  }

  String _pd(String key) {
    final v = _data[key]?.toString() ?? '';
    return v.isEmpty ? '—' : v;
  }

  Widget _buildPersoenlicheDaten() {
    final anschriftFull = [
      _data['anschrift']?.toString() ?? '',
      '${_data['plz'] ?? ''} ${_data['ort'] ?? ''}'.trim(),
      _data['land']?.toString() ?? '',
    ].where((s) => s.isNotEmpty).join('\n');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.person, color: Colors.orange.shade700, size: 22),
        const SizedBox(width: 8),
        Text('Persönliche Daten', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock, size: 10, color: Colors.orange.shade700),
            const SizedBox(width: 3),
            Text('AES-256', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
          ]),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _showPersDatenDialog,
          icon: const Icon(Icons.edit, size: 14),
          label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade700, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
        ),
      ]),
      const SizedBox(height: 4),
      Text('Diese Daten erscheinen auf Faxsendungen und Rechnungen — verschlüsselt gespeichert',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      const SizedBox(height: 20),

      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade100),
          boxShadow: [BoxShadow(color: Colors.orange.shade50, blurRadius: 6)],
        ),
        child: Column(children: [
          _persoenlichRow(Icons.business, 'Firma', _pd('firma'), isFirst: true),
          _persoenlichRow(Icons.person, 'Vorname', _pd('vorname')),
          _persoenlichRow(Icons.person_outline, 'Nachname', _pd('nachname')),
          _persoenlichRow(Icons.home, 'Anschrift', anschriftFull.isEmpty ? '—' : anschriftFull, multiline: true),
          _persoenlichRow(Icons.phone, 'Festnetz', _pd('festnetz')),
          _persoenlichRow(Icons.smartphone, 'Mobil', _pd('mobil'), isLast: true),
        ]),
      ),
    ]);
  }

  void _showPersDatenDialog() {
    final firma = TextEditingController(text: _data['firma']?.toString() ?? '');
    final vorname = TextEditingController(text: _data['vorname']?.toString() ?? '');
    final nachname = TextEditingController(text: _data['nachname']?.toString() ?? '');
    final anschrift = TextEditingController(text: _data['anschrift']?.toString() ?? '');
    final plz = TextEditingController(text: _data['plz']?.toString() ?? '');
    final ort = TextEditingController(text: _data['ort']?.toString() ?? '');
    final land = TextEditingController(text: _data['land']?.toString().isNotEmpty == true ? _data['land'].toString() : 'Deutschland');
    final festnetz = TextEditingController(text: _data['festnetz']?.toString() ?? '');
    final mobil = TextEditingController(text: _data['mobil']?.toString() ?? '');
    final faxNum = TextEditingController(text: _data['fax_nummer']?.toString() ?? '');
    final kundennr = TextEditingController(text: _data['kundennummer']?.toString() ?? '');

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(Icons.edit, size: 20, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        const Text('Persönliche Daten bearbeiten', style: TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _kontaktField(firma, 'Firma', Icons.business),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _kontaktField(vorname, 'Vorname', Icons.person)),
          const SizedBox(width: 10),
          Expanded(child: _kontaktField(nachname, 'Nachname', Icons.person_outline)),
        ]),
        const SizedBox(height: 16),
        _sectionLabel(Icons.home, 'Anschrift'),
        _kontaktField(anschrift, 'Straße und Hausnummer', Icons.location_on),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(width: 120, child: _kontaktField(plz, 'PLZ', Icons.markunread_mailbox)),
          const SizedBox(width: 10),
          Expanded(child: _kontaktField(ort, 'Ort', Icons.location_city)),
        ]),
        const SizedBox(height: 10),
        _kontaktField(land, 'Land', Icons.flag),
        const SizedBox(height: 16),
        _sectionLabel(Icons.contact_phone, 'Kontakt'),
        _kontaktField(faxNum, 'Faxnummer (SimpleFax)', Icons.fax, kbd: TextInputType.phone),
        const SizedBox(height: 10),
        _kontaktField(kundennr, 'Kundennummer (SimpleFax)', Icons.badge, kbd: TextInputType.number),
        const SizedBox(height: 10),
        _kontaktField(festnetz, 'Festnetz', Icons.phone, kbd: TextInputType.phone),
        const SizedBox(height: 10),
        _kontaktField(mobil, 'Mobil', Icons.smartphone, kbd: TextInputType.phone),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton.icon(
          onPressed: () async {
            final res = await widget.apiService.simplefaxAction({
              'action': 'save_persdaten',
              'firma': firma.text.trim(),
              'vorname': vorname.text.trim(),
              'nachname': nachname.text.trim(),
              'anschrift': anschrift.text.trim(),
              'plz': plz.text.trim(),
              'ort': ort.text.trim(),
              'land': land.text.trim(),
              'festnetz': festnetz.text.trim(),
              'mobil': mobil.text.trim(),
              'fax_nummer': faxNum.text.trim(),
              'kundennummer': kundennr.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              if (res['success'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verschlüsselt gespeichert'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red));
              }
            }
            _load();
          },
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
        ),
      ],
    ));
  }

  Widget _sectionLabel(IconData icon, String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      ]),
    );
  }

  Widget _persoenlichRow(IconData icon, String label, String value, {bool isFirst = false, bool isLast = false, bool multiline = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
        Icon(icon, size: 18, color: Colors.orange.shade600),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: value == '—' ? Colors.grey.shade400 : Colors.grey.shade900)),
        ),
      ]),
    );
  }

  static const _kategorieLabels = {'online': 'Online', 'email': 'E-Mail', 'fax': 'Fax', 'postalisch': 'Postalisch'};
  static const _kategorieIcons = {'online': Icons.language, 'email': Icons.email, 'fax': Icons.fax, 'postalisch': Icons.local_post_office};

  // ===== TAB 7: KORRESPONDENZ =====
  Widget _buildKorrespondenzTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.mail, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        Text('Korrespondenz (${_korr.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange.shade800)),
        const Spacer(),
        FilledButton.icon(
          onPressed: _addKorrespondenz,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neu', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
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
            final color = isEin ? Colors.orange : Colors.green;
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
                      await widget.apiService.simplefaxAction({'action': 'delete_korr', 'id': k['id']});
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
        Icon(Icons.mail, size: 18, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        const Text('Neue Korrespondenz', style: TextStyle(fontSize: 15)),
      ]),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('Ausgehend'), avatar: const Icon(Icons.call_made, size: 16), selected: richtung == 'ausgehend',
            selectedColor: Colors.green.shade100, onSelected: (_) => setDlg(() => richtung = 'ausgehend')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Eingehend'), avatar: const Icon(Icons.call_received, size: 16), selected: richtung == 'eingehend',
            selectedColor: Colors.orange.shade100, onSelected: (_) => setDlg(() => richtung = 'eingehend')),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: _kategorieLabels.entries.map((e) => ChoiceChip(
          avatar: Icon(_kategorieIcons[e.key], size: 16),
          label: Text(e.value),
          selected: kategorie == e.key,
          selectedColor: Colors.orange.shade100,
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
          await widget.apiService.simplefaxAction({
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
    final color = isEin ? Colors.orange : Colors.green;
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
        KorrAttachmentsWidget(apiService: widget.apiService, modul: 'simplefax_korr', korrespondenzId: k['id'] is int ? k['id'] : int.tryParse(k['id'].toString()) ?? index),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }
}
