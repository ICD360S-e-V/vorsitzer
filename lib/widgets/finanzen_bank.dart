import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/clipboard_helper.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class FinanzenBankWidget extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> Function(String) getData;
  final Future<void> Function(String, Map<String, dynamic>) saveData;
  final Future<void> Function(String) loadData;
  final bool Function(String) isLoading;
  final bool Function(String) isSaving;
  final Future<void> Function(String, String, dynamic) autoSaveField;
  final List<Map<String, dynamic>> bankenDb;
  final User user;
  final Map<String, dynamic>? pkontoData;
  final Future<void> Function(String subject, String description)? onCreateTicket;

  const FinanzenBankWidget({
    super.key,
    required this.apiService,
    required this.getData,
    required this.saveData,
    required this.loadData,
    required this.isLoading,
    required this.isSaving,
    required this.autoSaveField,
    required this.bankenDb,
    required this.user,
    this.pkontoData,
    this.onCreateTicket,
  });

  @override
  State<FinanzenBankWidget> createState() => _FinanzenBankWidgetState();
}

class _FinanzenBankWidgetState extends State<FinanzenBankWidget> {
  static const String _type = 'finanzen_bank';

  // IBAN boxes: DE89 | 3704 | 0044 | 0532 | 0130 | 00
  final List<TextEditingController> _ibanControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _ibanFocusNodes = List.generate(6, (_) => FocusNode());
  static const List<int> _ibanMaxLengths = [4, 4, 4, 4, 4, 2]; // DE89, 3704, 0044, 0532, 0130, 00
  static const List<String> _ibanHints = ['DE89', '3704', '0044', '0532', '0130', '00'];
  static const List<String> _ibanLabels = ['Land+Prüf', 'BLZ', 'BLZ', 'Konto', 'Konto', 'Konto'];

  final _kontoInhaberController = TextEditingController();
  final _beraterNameController = TextEditingController();
  final _beraterTelefonController = TextEditingController();
  final _beraterEmailController = TextEditingController();
  final _kontoartController = TextEditingController();
  final _notizenController = TextEditingController();

  final _cardExpiryController = TextEditingController();
  final _gebuehrController = TextEditingController();

  Map<String, dynamic>? _selectedBank;
  bool _initialized = false;
  bool _ibanLocked = false;
  String _cardType = '';
  String _cardNetwork = ''; // visa, mastercard, maestro, vpay
  bool _hasNfc = false;
  bool _hasGirocard = false;

  @override
  void dispose() {
    for (final c in _ibanControllers) { c.dispose(); }
    for (final f in _ibanFocusNodes) { f.dispose(); }
    _cardExpiryController.dispose();
    _gebuehrController.dispose();
    _kontoInhaberController.dispose();
    _beraterNameController.dispose();
    _beraterTelefonController.dispose();
    _beraterEmailController.dispose();
    _kontoartController.dispose();
    _notizenController.dispose();
    super.dispose();
  }

  String _getFullIban() {
    return _ibanControllers.map((c) => c.text.trim()).join('').toUpperCase();
  }

  void _setIbanFromString(String iban) {
    final clean = iban.replaceAll(RegExp(r'\s'), '').toUpperCase();
    int pos = 0;
    for (int i = 0; i < 6; i++) {
      final end = pos + _ibanMaxLengths[i];
      _ibanControllers[i].text = end <= clean.length ? clean.substring(pos, end) : (pos < clean.length ? clean.substring(pos) : '');
      pos = end;
    }
  }

  void _autoSaveIban() {
    final full = _getFullIban();
    if (full.length >= 4) { // at least country code
      widget.autoSaveField(_type, 'iban', full);
    }
  }

  void _initFromData(Map<String, dynamic> data) {
    if (_initialized && data.isNotEmpty) return;
    if (data.isEmpty) return;
    _initialized = true;
    _setIbanFromString(data['iban']?.toString() ?? '');
    final savedInhaber = data['konto_inhaber']?.toString() ?? '';
    if (savedInhaber.isNotEmpty) {
      _kontoInhaberController.text = savedInhaber;
    } else {
      // Auto-fill from Verifizierung (vorname + nachname)
      final parts = [widget.user.vorname, widget.user.nachname]
          .where((s) => s != null && s.isNotEmpty)
          .join(' ');
      _kontoInhaberController.text = parts;
    }
    _beraterNameController.text = data['berater_name']?.toString() ?? '';
    _beraterTelefonController.text = data['berater_telefon']?.toString() ?? '';
    _beraterEmailController.text = data['berater_email']?.toString() ?? '';
    _kontoartController.text = data['kontoart']?.toString() ?? '';
    _notizenController.text = data['notizen']?.toString() ?? '';
    _cardType = data['card_type']?.toString() ?? '';
    _cardExpiryController.text = data['card_expiry']?.toString() ?? '';
    _cardNetwork = data['card_network']?.toString() ?? '';
    _hasNfc = data['has_nfc'] == true || data['has_nfc'] == 'true';
    _hasGirocard = data['has_girocard'] == true || data['has_girocard'] == 'true';
    _gebuehrController.text = data['kontofuehrung_gebuehr']?.toString() ?? '';
    // Lock IBAN if already saved
    final savedIban = data['iban']?.toString() ?? '';
    if (savedIban.length >= 22) _ibanLocked = true;
    // Restore selected bank from saved bank_id
    final savedBankId = data['bank_id']?.toString();
    if (savedBankId != null && widget.bankenDb.isNotEmpty) {
      for (final b in widget.bankenDb) {
        if (b['id'].toString() == savedBankId) {
          _selectedBank = b;
          break;
        }
      }
    }
  }

  /// Check if card is expiring within 2 months
  Map<String, dynamic>? _getCardExpiryStatus() {
    final expiry = _cardExpiryController.text;
    if (expiry.isEmpty || !expiry.contains('/')) return null;
    final parts = expiry.split('/');
    final month = int.tryParse(parts[0]);
    final year = int.tryParse(parts[1]);
    if (month == null || year == null) return null;
    final fullYear = year < 100 ? 2000 + year : year;
    // Last day of expiry month
    final expiryDate = DateTime(fullYear, month + 1, 0);
    final now = DateTime.now();
    final daysLeft = expiryDate.difference(now).inDays;
    if (daysLeft <= 0) {
      return {'status': 'expired', 'message': 'Bankkarte ist abgelaufen! Bitte bei der Bank neues Karten beantragen.'};
    }
    if (daysLeft <= 60) {
      return {'status': 'warning', 'message': 'Bankkarte läuft in $daysLeft Tagen ab ($expiry). Bitte rechtzeitig bei der Bank informieren.'};
    }
    return null;
  }

  String _formatIbanDisplay(String raw) {
    final clean = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(clean[i]);
    }
    return buffer.toString();
  }

  void _selectBank(Map<String, dynamic> bank) {
    setState(() {
      _selectedBank = bank;
      // Auto-fill Kontoführungsgebühr from DB
      final dbGebuehr = bank['kontofuehrung_gebuehr']?.toString() ?? '';
      if (dbGebuehr.isNotEmpty && _gebuehrController.text.isEmpty) {
        _gebuehrController.text = dbGebuehr;
      }
    });
    widget.autoSaveField(_type, 'bank_id', bank['id'].toString());
    widget.autoSaveField(_type, 'bank_name', bank['name']?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading(_type)) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = widget.getData(_type);
    _initFromData(data);

    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Material(
          color: Colors.teal.shade50,
          child: TabBar(
            labelColor: Colors.teal.shade800,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.teal.shade700,
            isScrollable: true,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _selectedBank != null ? Colors.green : Colors.red),
                const SizedBox(width: 4),
                const Icon(Icons.account_balance, size: 14),
                const SizedBox(width: 4),
                const Text('Zuständige Bank'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _getFullIban().length >= 22 ? Colors.green : Colors.red),
                const SizedBox(width: 4),
                const Icon(Icons.credit_card, size: 14),
                const SizedBox(width: 4),
                const Text('Stammdaten'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: _beraterNameController.text.isNotEmpty ? Colors.green : Colors.red),
                const SizedBox(width: 4),
                const Icon(Icons.support_agent, size: 14),
                const SizedBox(width: 4),
                const Text('Ansprechpartner'),
              ])),
              const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.description, size: 14),
                SizedBox(width: 4),
                Text('Kontoauszüge'),
              ])),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _buildZustaendigeBankTab(),
          _buildStammdatenTab(),
          _buildAnsprechpartnerTab(),
          _KontoauszuegeTab(apiService: widget.apiService, userId: widget.user.id),
        ])),
      ]),
    );
  }

  // ============ TAB 1: ZUSTÄNDIGE BANK ============
  Widget _buildZustaendigeBankTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance, size: 20, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Zuständige Bank',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: Text(_selectedBank == null ? 'Bank suchen' : 'Ändern', style: const TextStyle(fontSize: 12)),
            onPressed: _showBankSearchDialog,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.teal.shade700),
          ),
        ]),
        const SizedBox(height: 12),
        if (_selectedBank == null)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(children: [
              Icon(Icons.search, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Keine Bank ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('Tippen Sie auf "Bank suchen" um die zuständige Bank aus der Datenbank zu wählen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade300),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.account_balance, size: 22, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text(_selectedBank!['name']?.toString() ?? '',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: Colors.red.shade400),
                  tooltip: 'Bank entfernen',
                  onPressed: () {
                    setState(() => _selectedBank = null);
                    widget.autoSaveField(_type, 'bank_id', '');
                    widget.autoSaveField(_type, 'bank_name', '');
                  },
                ),
              ]),
              const SizedBox(height: 8),
              if ((_selectedBank!['strasse']?.toString() ?? '').isNotEmpty)
                _bankInfoRow(Icons.place, '${_selectedBank!['strasse']}, ${_selectedBank!['plz_ort']}'),
              if ((_selectedBank!['telefon']?.toString() ?? '').isNotEmpty)
                _bankInfoRow(Icons.phone, _selectedBank!['telefon'].toString()),
              if ((_selectedBank!['bic']?.toString() ?? '').isNotEmpty)
                _bankInfoRow(Icons.swap_horiz, 'BIC: ${_selectedBank!['bic']}'),
              if ((_selectedBank!['blz']?.toString() ?? '').isNotEmpty)
                _bankInfoRow(Icons.tag, 'BLZ: ${_selectedBank!['blz']}'),
              if ((_selectedBank!['website']?.toString() ?? '').isNotEmpty)
                _bankInfoRow(Icons.language, _selectedBank!['website'].toString()),
              if ((_selectedBank!['kontofuehrung_gebuehr']?.toString() ?? '').isNotEmpty)
                _bankInfoRow(Icons.euro, 'Kontoführung: ${_selectedBank!['kontofuehrung_gebuehr']} €/Monat'),
            ]),
          ),
      ]),
    );
  }

  void _showBankSearchDialog() {
    String q = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        final filtered = q.trim().isEmpty
            ? widget.bankenDb
            : widget.bankenDb.where((b) {
                final needle = q.toLowerCase();
                return (b['name']?.toString().toLowerCase() ?? '').contains(needle)
                    || (b['plz_ort']?.toString().toLowerCase() ?? '').contains(needle)
                    || (b['bic']?.toString().toLowerCase() ?? '').contains(needle)
                    || (b['blz']?.toString().toLowerCase() ?? '').contains(needle);
              }).toList();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(children: [
            Icon(Icons.search, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Text('Bank auswählen'),
          ]),
          content: SizedBox(
            width: 500, height: 500,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Name, PLZ, Ort, BIC oder BLZ...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setD(() => q = v),
              ),
              const SizedBox(height: 8),
              Expanded(child: filtered.isEmpty
                ? Center(child: Text('Keine Treffer', style: TextStyle(color: Colors.grey.shade500)))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final b = filtered[i];
                      return InkWell(
                        onTap: () { _selectBank(b); Navigator.pop(ctx); },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(children: [
                            Icon(Icons.account_balance, size: 20, color: Colors.teal.shade600),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(b['name']?.toString() ?? '',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
                              Text('${b['strasse'] ?? ''}, ${b['plz_ort'] ?? ''}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                              if ((b['bic']?.toString() ?? '').isNotEmpty)
                                Text('BIC: ${b['bic']} · BLZ: ${b['blz'] ?? '–'}',
                                  style: TextStyle(fontSize: 10, color: Colors.teal.shade400, fontStyle: FontStyle.italic)),
                            ])),
                          ]),
                        ),
                      );
                    },
                  ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
        );
      }),
    );
  }

  // ============ TAB 2: STAMMDATEN ============
  Widget _buildStammdatenTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // === CARD EXPIRY WARNING ===
          if (_getCardExpiryStatus() != null) ...[
            () {
              final status = _getCardExpiryStatus()!;
              final isExpired = status['status'] == 'expired';
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isExpired ? Colors.red.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isExpired ? Colors.red.shade400 : Colors.orange.shade400, width: 2),
                ),
                child: Row(
                  children: [
                    Icon(isExpired ? Icons.error : Icons.warning_amber, size: 22, color: isExpired ? Colors.red.shade700 : Colors.orange.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isExpired ? 'Bankkarte abgelaufen!' : 'Bankkarte läuft bald ab!',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isExpired ? Colors.red.shade800 : Colors.orange.shade800)),
                          const SizedBox(height: 2),
                          Text(status['message'].toString(), style: TextStyle(fontSize: 11, color: isExpired ? Colors.red.shade700 : Colors.orange.shade700)),
                        ],
                      ),
                    ),
                    if (widget.onCreateTicket != null)
                      ElevatedButton.icon(
                        onPressed: () {
                          final bankName = _selectedBank?['name']?.toString() ?? 'Bank';
                          widget.onCreateTicket!(
                            'Bankkarte erneuern – $bankName',
                            'Die Bankkarte von ${widget.user.vorname ?? ''} ${widget.user.nachname ?? ''} '
                            '(${widget.user.mitgliedernummer}) bei $bankName läuft am ${_cardExpiryController.text} ab.\n\n'
                            'Bitte bei der Bank informieren und neue Karte beantragen.',
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: const Text('Ticket erstellt'), backgroundColor: Colors.green.shade600, duration: const Duration(seconds: 2)),
                          );
                        },
                        icon: const Icon(Icons.confirmation_number, size: 14),
                        label: const Text('Ticket erstellen', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isExpired ? Colors.red.shade700 : Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                  ],
                ),
              );
            }(),
            const SizedBox(height: 12),
          ],


          // Kontoart dropdown
          DropdownButtonFormField<String>(
            initialValue: _kontoartController.text.isNotEmpty ? _kontoartController.text : null,
            decoration: InputDecoration(
              labelText: 'Kontoart',
              prefixIcon: Icon(Icons.category, size: 18, color: Colors.teal.shade600),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: const [
              DropdownMenuItem(value: 'Girokonto', child: Text('Girokonto', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'Girokonto Basis', child: Text('Girokonto Basis (Jedermann-Konto)', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'P-Konto', child: Text('P-Konto (Pfändungsschutzkonto)', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'Sparkonto', child: Text('Sparkonto', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'Tagesgeldkonto', child: Text('Tagesgeldkonto', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'Geschäftskonto', child: Text('Geschäftskonto', style: TextStyle(fontSize: 13))),
            ],
            onChanged: (val) {
              if (val == null) return;
              setState(() => _kontoartController.text = val);
              widget.autoSaveField(_type, 'kontoart', val);
            },
          ),
          const SizedBox(height: 12),

          // P-Konto Info Box
          if (_kontoartController.text == 'P-Konto') ...[
            _buildPKontoInfoBox(),
            const SizedBox(height: 12),
          ],

          // Kontoführungsgebühr
          TextFormField(
            controller: _gebuehrController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Kontoführungsgebühr (€ / Monat)',
              prefixIcon: Icon(Icons.euro, size: 18, color: Colors.orange.shade600),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              hintText: 'z.B. 3,50',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              helperText: _selectedBank != null && (_selectedBank!['kontofuehrung_gebuehr']?.toString() ?? '').isNotEmpty
                  ? 'Standard bei ${_selectedBank!['name']}: ${_selectedBank!['kontofuehrung_gebuehr']} €/Monat'
                  : null,
              helperStyle: TextStyle(fontSize: 10, color: Colors.orange.shade600),
            ),
            onFieldSubmitted: (v) => widget.autoSaveField(_type, 'kontofuehrung_gebuehr', v.trim()),
          ),
          const SizedBox(height: 12),

          // Kontoinhaber (read-only, aus Verifizierung)
          TextFormField(
            controller: _kontoInhaberController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Kontoinhaber',
              prefixIcon: const Icon(Icons.person, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.grey.shade100,
              helperText: 'Aus Verifizierung (Vorname + Nachname)',
              helperStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
          const SizedBox(height: 16),

          // IBAN section - 6 Kästen (locked after entry)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _ibanLocked ? Colors.green.shade300 : Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.credit_card, size: 16, color: _ibanLocked ? Colors.green.shade700 : Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text('IBAN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _ibanLocked ? Colors.green.shade800 : Colors.blue.shade800)),
                    if (_ibanLocked) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock, size: 13, color: Colors.green.shade600),
                    ],
                    const Spacer(),
                    if (_ibanLocked)
                      IconButton(
                        icon: Icon(Icons.edit, size: 16, color: Colors.orange.shade600),
                        tooltip: 'IBAN bearbeiten',
                        onPressed: () => setState(() => _ibanLocked = false),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                      ),
                    if (_getFullIban().length >= 4)
                      IconButton(
                        icon: Icon(Icons.copy, size: 16, color: Colors.blue.shade600),
                        tooltip: 'IBAN kopieren',
                        onPressed: () {
                          final full = _getFullIban();
                          ClipboardHelper.copy(context, full, 'IBAN');
                        },
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_ibanLocked) ...[
                  // Read-only display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Text(
                      _formatIbanDisplay(_getFullIban()),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        color: Colors.blue.shade900,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ] else ...[
                  // Editable boxes
                  Row(
                    children: List.generate(6, (i) {
                      final isFirst = i == 0;
                      return Expanded(
                        flex: _ibanMaxLengths[i] == 2 ? 2 : 3,
                        child: Padding(
                          padding: EdgeInsets.only(left: i > 0 ? 6 : 0),
                          child: TextFormField(
                            controller: _ibanControllers[i],
                            focusNode: _ibanFocusNodes[i],
                            textAlign: TextAlign.center,
                            textCapitalization: isFirst ? TextCapitalization.characters : TextCapitalization.none,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                              color: Colors.blue.shade900,
                              fontFamily: 'monospace',
                            ),
                            decoration: InputDecoration(
                              hintText: _ibanHints[i],
                              hintStyle: TextStyle(fontSize: 12, color: Colors.blue.shade200, letterSpacing: 2),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.blue.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(isFirst ? RegExp(r'[A-Za-z0-9]') : RegExp(r'[0-9]')),
                              LengthLimitingTextInputFormatter(_ibanMaxLengths[i]),
                            ],
                            onChanged: (v) {
                              if (v.length >= _ibanMaxLengths[i] && i < 5) {
                                _ibanFocusNodes[i + 1].requestFocus();
                              }
                              // Auto-lock when all 22 chars entered
                              final full = _getFullIban();
                              if (full.length >= 22) {
                                _autoSaveIban();
                                setState(() => _ibanLocked = true);
                              }
                              setState(() {});
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (int i = 0; i < 6; i++)
                        Expanded(
                          flex: _ibanMaxLengths[i] == 2 ? 2 : 3,
                          child: Padding(
                            padding: EdgeInsets.only(left: i > 0 ? 6 : 0),
                            child: Text(
                              _ibanLabels[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 9, color: Colors.blue.shade400),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // === BANKKARTE ===
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payment, size: 16, color: Colors.indigo.shade700),
                    const SizedBox(width: 6),
                    Text('Bankkarte', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                  ],
                ),
                const SizedBox(height: 10),
                // Card type chips
                Row(
                  children: [
                    Text('Kartentyp:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.credit_card, size: 13, color: _cardType == 'debit' ? Colors.white : Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text('Debitkarte', style: TextStyle(fontSize: 11, color: _cardType == 'debit' ? Colors.white : Colors.green.shade700)),
                      ]),
                      selected: _cardType == 'debit',
                      selectedColor: Colors.green.shade600,
                      backgroundColor: Colors.green.shade50,
                      side: BorderSide(color: _cardType == 'debit' ? Colors.green.shade600 : Colors.green.shade200),
                      onSelected: (_) {
                        setState(() => _cardType = _cardType == 'debit' ? '' : 'debit');
                        widget.autoSaveField(_type, 'card_type', _cardType);
                      },
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.credit_score, size: 13, color: _cardType == 'credit' ? Colors.white : Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text('Kreditkarte', style: TextStyle(fontSize: 11, color: _cardType == 'credit' ? Colors.white : Colors.blue.shade700)),
                      ]),
                      selected: _cardType == 'credit',
                      selectedColor: Colors.blue.shade600,
                      backgroundColor: Colors.blue.shade50,
                      side: BorderSide(color: _cardType == 'credit' ? Colors.blue.shade600 : Colors.blue.shade200),
                      onSelected: (_) {
                        setState(() => _cardType = _cardType == 'credit' ? '' : 'credit');
                        widget.autoSaveField(_type, 'card_type', _cardType);
                      },
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.style, size: 13, color: _cardType == 'beide' ? Colors.white : Colors.purple.shade700),
                        const SizedBox(width: 4),
                        Text('Beide', style: TextStyle(fontSize: 11, color: _cardType == 'beide' ? Colors.white : Colors.purple.shade700)),
                      ]),
                      selected: _cardType == 'beide',
                      selectedColor: Colors.purple.shade600,
                      backgroundColor: Colors.purple.shade50,
                      side: BorderSide(color: _cardType == 'beide' ? Colors.purple.shade600 : Colors.purple.shade200),
                      onSelected: (_) {
                        setState(() => _cardType = _cardType == 'beide' ? '' : 'beide');
                        widget.autoSaveField(_type, 'card_type', _cardType);
                      },
                    ),
                  ],
                ),
                // Kartennetzwerk
                if (_cardType.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Kartennetzwerk:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _networkChip('visa', 'Visa', 'assets/card_logos/visa.png', Colors.indigo),
                      const SizedBox(width: 8),
                      _networkChip('mastercard', 'Mastercard', 'assets/card_logos/mastercard.png', Colors.orange),
                      const SizedBox(width: 8),
                      _networkChip('vpay', 'V PAY', null, Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Info about selected network
                  if (_cardNetwork == 'visa')
                    _networkInfoBox(
                      color: Colors.indigo,
                      icon: Icons.public,
                      title: 'Visa',
                      info: 'Weltweit größtes Zahlungsnetzwerk. Akzeptiert in über 200 Ländern bei 80+ Mio. Händlern. Visa Debit & Visa Credit verfügbar. Kontaktloses Bezahlen (NFC) und Online-Zahlungen.',
                    ),
                  if (_cardNetwork == 'mastercard')
                    _networkInfoBox(
                      color: Colors.orange,
                      icon: Icons.public,
                      title: 'Mastercard',
                      info: 'Zweitgrößtes Zahlungsnetzwerk weltweit. Akzeptiert in 210+ Ländern. Mastercard Debit & Credit verfügbar. Bietet Mastercard Identity Check (3D Secure) für sichere Online-Zahlungen.',
                    ),
                  if (_cardNetwork == 'vpay')
                    _networkInfoBox(
                      color: Colors.blue,
                      icon: Icons.euro,
                      title: 'V PAY',
                      info: 'Europäisches Debitkartensystem von Visa. Nur in Europa akzeptiert (kein weltweiter Einsatz). Wird seit 2024 durch Visa Debit ersetzt. Bestehende V PAY-Karten funktionieren bis zum Ablauf.',
                    ),
                ],
                const SizedBox(height: 10),
                // Card expiry (MM/YY like on card)
                TextFormField(
                  controller: _cardExpiryController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Karte gültig bis',
                    prefixIcon: Icon(Icons.event, size: 18, color: Colors.indigo.shade600),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.edit, size: 16, color: Colors.indigo.shade600),
                      tooltip: 'Ablaufdatum ändern',
                      onPressed: () => _showMonthYearPicker(),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'MM/YY',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ),
                const SizedBox(height: 10),
                // NFC + Girocard
                Row(
                  children: [
                    // NFC
                    Expanded(
                      child: SwitchListTile(
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.contactless, size: 16, color: _hasNfc ? Colors.green.shade700 : Colors.grey.shade500),
                            const SizedBox(width: 6),
                            const Text('NFC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        subtitle: Text(
                          _hasNfc ? 'Kontaktlos bezahlen' : 'Kein NFC',
                          style: TextStyle(fontSize: 10, color: _hasNfc ? Colors.green.shade600 : Colors.grey.shade400),
                        ),
                        value: _hasNfc,
                        activeTrackColor: Colors.green.shade200,
                        activeThumbColor: Colors.green.shade700,
                        onChanged: (v) {
                          setState(() => _hasNfc = v);
                          widget.autoSaveField(_type, 'has_nfc', v);
                        },
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.grey.shade300),
                    // Girocard
                    Expanded(
                      child: SwitchListTile(
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.payment, size: 16, color: _hasGirocard ? Colors.blue.shade700 : Colors.grey.shade500),
                            const SizedBox(width: 6),
                            const Text('girocard', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        subtitle: Text(
                          _hasGirocard ? 'Deutsches Debitkartensystem' : 'Keine girocard',
                          style: TextStyle(fontSize: 10, color: _hasGirocard ? Colors.blue.shade600 : Colors.grey.shade400),
                        ),
                        value: _hasGirocard,
                        activeTrackColor: Colors.blue.shade200,
                        activeThumbColor: Colors.blue.shade700,
                        onChanged: (v) {
                          setState(() => _hasGirocard = v);
                          widget.autoSaveField(_type, 'has_girocard', v);
                        },
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ============ TAB 3: ANSPRECHPARTNER ============
  Widget _buildAnsprechpartnerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.support_agent, size: 20, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Text('Bankberater / Ansprechpartner',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildField(
              controller: _beraterNameController,
              label: 'Name',
              icon: Icons.person_outline,
              hint: 'Name des Bankberaters',
              onSave: (v) => widget.autoSaveField(_type, 'berater_name', v),
            ),
            const SizedBox(height: 8),
            _buildField(
              controller: _beraterTelefonController,
              label: 'Telefon',
              icon: Icons.phone,
              hint: 'Telefonnummer',
              onSave: (v) => widget.autoSaveField(_type, 'berater_telefon', v),
              keyboard: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            _buildField(
              controller: _beraterEmailController,
              label: 'E-Mail',
              icon: Icons.email,
              hint: 'E-Mail-Adresse',
              onSave: (v) => widget.autoSaveField(_type, 'berater_email', v),
              keyboard: TextInputType.emailAddress,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notizenController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Notizen',
            prefixIcon: const Icon(Icons.note, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            hintText: 'Zusätzliche Informationen...',
            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
          onChanged: (v) { setState(() {}); widget.autoSaveField(_type, 'notizen', v); },
        ),
      ]),
    );
  }

  Widget _networkChip(String value, String label, String? assetPath, MaterialColor color) {
    final isSelected = _cardNetwork == value;
    return GestureDetector(
      onTap: () {
        setState(() => _cardNetwork = _cardNetwork == value ? '' : value);
        widget.autoSaveField(_type, 'card_network', _cardNetwork);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.shade600 : color.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? color.shade600 : color.shade200, width: isSelected ? 2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (assetPath != null)
              Image.asset(assetPath, height: 16, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : color.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _networkInfoBox({required MaterialColor color, required IconData icon, required String title, required String info}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800)),
                const SizedBox(height: 2),
                Text(info, style: TextStyle(fontSize: 10, color: color.shade700, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMonthYearPicker() {
    // Parse existing value
    int selectedMonth = DateTime.now().month;
    int selectedYear = DateTime.now().year;
    final existing = _cardExpiryController.text;
    if (existing.contains('/')) {
      final parts = existing.split('/');
      selectedMonth = int.tryParse(parts[0]) ?? selectedMonth;
      final y = int.tryParse(parts[1]) ?? selectedYear;
      selectedYear = y < 100 ? 2000 + y : y;
    }

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.credit_card, size: 18, color: Colors.indigo.shade700),
            const SizedBox(width: 8),
            const Text('Karte gültig bis', style: TextStyle(fontSize: 15)),
          ]),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Month
              SizedBox(
                width: 80,
                child: DropdownButtonFormField<int>(
                  initialValue: selectedMonth,
                  decoration: InputDecoration(
                    labelText: 'Monat',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: List.generate(12, (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text((i + 1).toString().padLeft(2, '0'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  )),
                  onChanged: (v) => setDlgState(() => selectedMonth = v ?? selectedMonth),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('/', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
              ),
              // Year
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<int>(
                  initialValue: selectedYear,
                  decoration: InputDecoration(
                    labelText: 'Jahr',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: List.generate(20, (i) {
                    final y = DateTime.now().year + i;
                    return DropdownMenuItem(value: y, child: Text('$y', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));
                  }),
                  onChanged: (v) => setDlgState(() => selectedYear = v ?? selectedYear),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                final formatted = '${selectedMonth.toString().padLeft(2, '0')}/${selectedYear.toString().substring(2)}';
                setState(() => _cardExpiryController.text = formatted);
                widget.autoSaveField(_type, 'card_expiry', formatted);
                Navigator.pop(dlgCtx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade600, foregroundColor: Colors.white),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPKontoInfoBox() {
    final pk = widget.pkontoData;
    if (pk == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('P-Konto Daten werden geladen...', style: TextStyle(fontSize: 12)),
      );
    }
    final betrag = double.tryParse(pk['grundfreibetrag']?.toString() ?? '0') ?? 0;
    final erhoehung1 = double.tryParse(pk['erhoehung_1_person']?.toString() ?? '0') ?? 0;
    final erhoehung2_5 = double.tryParse(pk['erhoehung_2_5_person']?.toString() ?? '0') ?? 0;
    final von = pk['gueltig_von']?.toString() ?? '';
    final bis = pk['gueltig_bis']?.toString() ?? '';
    final quelle = pk['quelle']?.toString() ?? '';
    // Format dates DD.MM.YYYY
    String fmtDate(String d) {
      final parts = d.split('-');
      if (parts.length == 3) return '${parts[2]}.${parts[1]}.${parts[0]}';
      return d;
    }
    final zeitraum = '${fmtDate(von)} – ${fmtDate(bis)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, size: 20, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Text('P-Konto – Pfändungsschutz', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aktueller Freibetrag', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text('${betrag.toStringAsFixed(2).replaceAll('.', ',')} € / Monat',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.red.shade800)),
                const SizedBox(height: 4),
                Text('Gültig: $zeitraum', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.red.shade600)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Erhöhungen
          Text('Erhöhung bei Unterhaltspflichten:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
          const SizedBox(height: 6),
          _pkontoRow('1. unterhaltsberechtigte Person', '+${erhoehung1.toStringAsFixed(2).replaceAll('.', ',')} €'),
          _pkontoRow('2. – 5. Person (je)', '+${erhoehung2_5.toStringAsFixed(2).replaceAll('.', ',')} €'),
          const SizedBox(height: 8),
          // Beispielrechnung
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Beispiel: Alleinstehend + 1 Kind', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                const SizedBox(height: 3),
                Text('${betrag.toStringAsFixed(2).replaceAll('.', ',')} € + ${erhoehung1.toStringAsFixed(2).replaceAll('.', ',')} € = ${(betrag + erhoehung1).toStringAsFixed(2).replaceAll('.', ',')} € / Monat geschützt',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade900)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Quelle: $quelle · Aktualisierung jährlich zum 1. Juli (§ 899 ZPO)',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pkontoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(Icons.person_add, size: 13, color: Colors.red.shade400),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: Colors.red.shade700))),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade800)),
        ],
      ),
    );
  }

  Widget _bankInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.teal.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.teal.shade700))),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    required void Function(String) onSave,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
      ),
      onFieldSubmitted: (v) => onSave(v.trim()),
    );
  }
}

// ============================================================
// TAB 4: KONTOAUSZÜGE — period-based bank statement archive
// ============================================================

class _KontoauszuegeTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _KontoauszuegeTab({required this.apiService, required this.userId});

  @override
  State<_KontoauszuegeTab> createState() => _KontoauszuegeTabState();
}

class _KontoauszuegeTabState extends State<_KontoauszuegeTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await widget.apiService.listFinanzenKontoauszuege(widget.userId);
    if (!mounted) return;
    setState(() {
      _items = (r['success'] == true && r['data'] is List)
          ? (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
      _loaded = true;
    });
  }

  String _fmtDate(String iso) {
    // yyyy-mm-dd → dd.mm.yyyy
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
  }

  Future<void> _addDialog() async {
    DateTime? von;
    DateTime? bis;
    final notizC = TextEditingController();
    bool submitting = false;
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      String fmt(DateTime? d) => d == null ? '' : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Neuer Kontoauszug'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Zeitraum des Kontoauszugs auswählen:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () async {
                final p = await showDateRangePicker(
                  context: ctx2,
                  firstDate: DateTime(2015),
                  lastDate: DateTime(DateTime.now().year + 1),
                  initialDateRange: (von != null && bis != null) ? DateTimeRange(start: von!, end: bis!) : null,
                  locale: const Locale('de'),
                );
                if (p != null) setD(() { von = p.start; bis = p.end; });
              },
              icon: const Icon(Icons.date_range, size: 16),
              label: Text(von == null || bis == null ? 'Zeitraum wählen' : '${fmt(von)} – ${fmt(bis)}',
                style: const TextStyle(fontSize: 12)),
            )),
          ]),
          if (von != null && bis != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.teal.shade200)),
              child: Row(children: [
                Icon(Icons.check_circle, size: 14, color: Colors.teal.shade700),
                const SizedBox(width: 6),
                Expanded(child: Text('${bis!.difference(von!).inDays + 1} Tage',
                  style: TextStyle(fontSize: 12, color: Colors.teal.shade900, fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notizC,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Notiz (optional)',
              prefixIcon: const Icon(Icons.note, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Nach dem Speichern können Sie die PDFs zum Zeitraum hochladen.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: submitting ? null : () async {
              if (von == null || bis == null) return;
              setD(() => submitting = true);
              final vonIso = '${von!.year}-${von!.month.toString().padLeft(2, '0')}-${von!.day.toString().padLeft(2, '0')}';
              final bisIso = '${bis!.year}-${bis!.month.toString().padLeft(2, '0')}-${bis!.day.toString().padLeft(2, '0')}';
              await widget.apiService.saveFinanzenKontoauszug(widget.userId, vonIso, bisIso, notiz: notizC.text.trim().isEmpty ? null : notizC.text.trim());
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Speichern'),
          ),
        ],
      );
    }));
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.description, size: 20, color: Colors.teal.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text('Kontoauszüge (${_items.length})',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700))),
        ElevatedButton.icon(
          onPressed: _addDialog,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neuer Kontoauszug', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: _items.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.description_outlined, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Noch keine Kontoauszüge', style: TextStyle(color: Colors.grey.shade500)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final k = _items[i];
                final kid = int.tryParse(k['id']?.toString() ?? '');
                final von = k['von_datum']?.toString() ?? '';
                final bis = k['bis_datum']?.toString() ?? '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.date_range, size: 20, color: Colors.teal.shade700),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_fmtDate(von)} – ${_fmtDate(bis)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          if ((k['notiz']?.toString() ?? '').isNotEmpty)
                            Text(k['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ])),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          onPressed: () async {
                            if (kid != null) { await widget.apiService.deleteFinanzenKontoauszug(kid); await _load(); }
                          },
                        ),
                      ]),
                      if (kid != null) Padding(
                        padding: const EdgeInsets.only(top: 6, left: 28),
                        child: KorrAttachmentsWidget(
                          apiService: widget.apiService,
                          modul: 'finanzen_kontoauszug',
                          korrespondenzId: kid,
                        ),
                      ),
                    ]),
                  ),
                );
              },
            )),
    ]);
  }
}
