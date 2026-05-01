import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import 'behoerden_screen.dart';
import 'jasmina_screen.dart';
import 'servdiscount_screen.dart';
import 'stifter_helfen_screen.dart';
import 'google_nonprofit_screen.dart';
import 'microsoft_nonprofit_screen.dart';
import 'vr_bank_screen.dart';
import 'gls_bank_screen.dart';
import 'ordnungsmassnahmen_screen.dart';
import 'vereinsinventar_screen.dart';
import 'deutschepost_screen.dart';
import '../widgets/eastern.dart';

class VereinverwaltungScreen extends StatefulWidget {
  final ApiService apiService;
  final List<User> users;
  final Color Function(String role) getRoleColor;
  final String Function(String role) getRoleText;

  const VereinverwaltungScreen({
    super.key,
    required this.apiService,
    required this.users,
    required this.getRoleColor,
    required this.getRoleText,
  });

  @override
  State<VereinverwaltungScreen> createState() => _VereinverwaltungScreenState();
}

class _VereinverwaltungScreenState extends State<VereinverwaltungScreen> {
  String _vereinSubview = 'overview';
  List<Map<String, dynamic>> _vereinData = [];
  bool _isLoading = true;

  // Platform Aufgaben counts
  int _stifterHelfenOpenAufgaben = 0;
  int _googleNonprofitOpenAufgaben = 0;
  int _microsoftNonprofitOpenAufgaben = 0;
  int _jasminaOpenAufgaben = 0;

  // Pauschalen data
  Map<String, dynamic>? _pauschalenData;
  bool _pauschalenLoading = false;

  @override
  void initState() {
    super.initState();
    _loadVereinData();
    _loadStifterHelfenAufgaben();
    _loadGoogleNonprofitAufgaben();
    _loadMicrosoftNonprofitAufgaben();
    _loadJasminaAufgaben();
    _loadPauschalen();
  }

  Future<void> _loadVereinData() async {
    try {
      final result = await widget.apiService.getVereinverwaltung();
      if (result['success'] == true && mounted) {
        setState(() {
          _vereinData = List<Map<String, dynamic>>.from(result['data'] ?? []);
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStifterHelfenAufgaben() async {
    try {
      final result = await widget.apiService.getPlatformAufgaben('stifter-helfen');
      if (result['success'] == true && mounted) {
        final aufgaben = List<Map<String, dynamic>>.from(result['aufgaben'] ?? []);
        final open = aufgaben.where((a) => a['erledigt'] != true && a['erledigt'] != 1).length;
        setState(() => _stifterHelfenOpenAufgaben = open);
      }
    } catch (_) {}
  }

  Future<void> _loadGoogleNonprofitAufgaben() async {
    try {
      final result = await widget.apiService.getPlatformAufgaben('google-nonprofit');
      if (result['success'] == true && mounted) {
        final aufgaben = List<Map<String, dynamic>>.from(result['aufgaben'] ?? []);
        final open = aufgaben.where((a) => a['erledigt'] != true && a['erledigt'] != 1).length;
        setState(() => _googleNonprofitOpenAufgaben = open);
      }
    } catch (_) {}
  }

  Future<void> _loadMicrosoftNonprofitAufgaben() async {
    try {
      final result = await widget.apiService.getPlatformAufgaben('microsoft-nonprofit');
      if (result['success'] == true && mounted) {
        final aufgaben = List<Map<String, dynamic>>.from(result['aufgaben'] ?? []);
        final open = aufgaben.where((a) => a['erledigt'] != true && a['erledigt'] != 1).length;
        setState(() => _microsoftNonprofitOpenAufgaben = open);
      }
    } catch (_) {}
  }

  Future<void> _loadPauschalen() async {
    setState(() => _pauschalenLoading = true);
    try {
      final result = await widget.apiService.getPauschalen();
      if (result['success'] == true && mounted) {
        setState(() {
          _pauschalenData = result;
          _pauschalenLoading = false;
        });
      } else if (mounted) {
        setState(() => _pauschalenLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _pauschalenLoading = false);
    }
  }

  Future<void> _loadJasminaAufgaben() async {
    try {
      final result = await widget.apiService.getPlatformAufgaben('jasmina');
      if (result['success'] == true && mounted) {
        final aufgaben = List<Map<String, dynamic>>.from(result['aufgaben'] ?? []);
        final open = aufgaben.where((a) => a['erledigt'] != true && a['erledigt'] != 1).length;
        setState(() => _jasminaOpenAufgaben = open);
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _getByKategorie(String kategorie) {
    return _vereinData.where((e) => e['kategorie'] == kategorie).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_vereinSubview == 'behoerden') {
      return BehoerdenScreen(
        apiService: widget.apiService,
        onBack: () => setState(() => _vereinSubview = 'overview'),
      );
    } else if (_vereinSubview == 'partner') {
      return _buildPartnerDetailView();
    } else if (_vereinSubview == 'notar') {
      return _buildNotarDetailView();
    } else if (_vereinSubview == 'banken') {
      return _buildBankenDetailView();
    } else if (_vereinSubview == 'vorstand') {
      return _buildVorstandDetailView();
    } else if (_vereinSubview == 'deutschepost') {
      return DeutschePostScreen(
        apiService: widget.apiService,
        onBack: () => setState(() => _vereinSubview = 'partner'),
      );
    } else if (_vereinSubview == 'stifter-helfen') {
      return StifterHelfenScreen(
        apiService: widget.apiService,
        onBack: () {
          _loadStifterHelfenAufgaben();
          setState(() => _vereinSubview = 'it-beschaffung');
        },
      );
    } else if (_vereinSubview == 'google-nonprofit') {
      return GoogleNonprofitScreen(
        apiService: widget.apiService,
        onBack: () {
          _loadGoogleNonprofitAufgaben();
          setState(() => _vereinSubview = 'it-beschaffung');
        },
      );
    } else if (_vereinSubview == 'microsoft-nonprofit') {
      return MicrosoftNonprofitScreen(
        apiService: widget.apiService,
        onBack: () {
          _loadMicrosoftNonprofitAufgaben();
          setState(() => _vereinSubview = 'it-beschaffung');
        },
      );
    } else if (_vereinSubview == 'hetzner') {
      return _buildHetznerDetailView();
    } else if (_vereinSubview == 'inwx') {
      return _buildInwxDetailView();
    } else if (_vereinSubview == 'volksbank') {
      return VrBankScreen(
        onBack: () => setState(() => _vereinSubview = 'banken'),
      );
    } else if (_vereinSubview == 'gls') {
      return GlsBankScreen(
        onBack: () => setState(() => _vereinSubview = 'banken'),
      );
    } else if (_vereinSubview == 'it-beschaffung') {
      return _buildITBeschaffungDetailView();
    } else if (_vereinSubview == 'stifter-helfen') {
      return _buildStifterHelfenDetailView();
    } else if (_vereinSubview == 'jasmina') {
      return JasminaScreen(
        apiService: widget.apiService,
        onBack: () {
          _loadJasminaAufgaben();
          setState(() => _vereinSubview = 'partner');
        },
      );
    } else if (_vereinSubview == 'servdiscount') {
      return ServdiscountScreen(
        apiService: widget.apiService,
        onBack: () => setState(() => _vereinSubview = 'partner'),
      );
    } else if (_vereinSubview == 'ordnungsmassnahmen') {
      return OrdnungsmassnahmenScreen(
        users: widget.users,
        onBack: () => setState(() => _vereinSubview = 'overview'),
      );
    } else if (_vereinSubview == 'inventar') {
      return VereinsinventarScreen(
        onBack: () => setState(() => _vereinSubview = 'overview'),
      );
    }

    // Default overview
    return SeasonalBackground(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header
          Row(
            children: [
              Icon(Icons.apartment, size: 32, color: Colors.blue.shade700),
              const SizedBox(width: 12),
              const Text(
                'Vereinverwaltung',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3-column grid
          Expanded(
            child: Column(
              children: [
                // Row 1
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildBehoerdenCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildPartnerCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildNotarCard()),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Row 2
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildBankenCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildVorstandCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildOrdnungsmassnahmenCard()),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Row 3
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildInventarCard()),
                      const SizedBox(width: 16),
                      Expanded(child: Container()),
                      const SizedBox(width: 16),
                      Expanded(child: Container()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ==================== CARD BUILDERS ====================

  Widget _buildBehoerdenCard() {
    return _buildClickableCard(
      icon: Icons.account_balance,
      title: 'Behörden & Register',
      color: Colors.blue,
      subtitle: 'Handelsregister, Vereinsregister, Netzwerk',
      onTap: () => setState(() => _vereinSubview = 'behoerden'),
    );
  }

  Widget _buildPartnerCard() {
    return _buildClickableCard(
      icon: Icons.handshake,
      title: 'Partner & Dienstleister',
      color: Colors.green,
      subtitle: 'Deutsche Post, Hetzner, INWX, IT-Beschaffung',
      onTap: () => setState(() => _vereinSubview = 'partner'),
    );
  }

  Widget _buildNotarCard() {
    return _buildClickableCard(
      icon: Icons.gavel,
      title: 'Notar',
      color: Colors.deepOrange,
      subtitle: 'Notarielle Dokumente, Termine, Rechnungen',
      onTap: () => setState(() => _vereinSubview = 'notar'),
    );
  }

  Widget _buildBankenCard() {
    return _buildClickableCard(
      icon: Icons.account_balance,
      title: 'Banken',
      color: Colors.amber,
      subtitle: 'VR Bank, GLS Bank',
      onTap: () => setState(() => _vereinSubview = 'banken'),
    );
  }

  Widget _buildVorstandCard() {
    return _buildClickableCard(
      icon: Icons.people,
      title: 'Vorstand',
      color: Colors.purple,
      subtitle: 'Vorsitzender, Schatzmeister, Kassierer',
      onTap: () => setState(() => _vereinSubview = 'vorstand'),
    );
  }

  Widget _buildOrdnungsmassnahmenCard() {
    return _buildClickableCard(
      icon: Icons.gavel,
      title: 'Ordnungsmaßnahmen',
      color: Colors.red,
      subtitle: 'Verwarnungen, Ordnungsgeld, Ausschluss (§6 Abs. 6)',
      onTap: () => setState(() => _vereinSubview = 'ordnungsmassnahmen'),
    );
  }

  Widget _buildInventarCard() {
    return _buildClickableCard(
      icon: Icons.inventory_2,
      title: 'Vereinsinventar',
      color: Colors.teal,
      subtitle: 'Gegenstände, Materialien, Entnahme & Rückgabe',
      onTap: () => setState(() => _vereinSubview = 'inventar'),
    );
  }

  // ==================== DETAIL VIEWS ====================

  Widget _buildPartnerDetailView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vereinSubview = 'overview'),
                tooltip: 'Zurück zur Übersicht',
              ),
              const SizedBox(width: 8),
              Icon(Icons.handshake, size: 32, color: Colors.green.shade700),
              const SizedBox(width: 12),
              const Text(
                'Partner & Dienstleister',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildDeutschePostCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildHetznerCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildInwxCard()),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildITBeschaffungCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildJasminaCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildServdiscountCard()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeutschePostCard() {
    return _buildClickableCard(
      icon: Icons.local_shipping,
      title: 'Deutsche Post',
      color: Colors.yellow.shade700,
      subtitle: 'Sendungsverfolgung, Porto, Abholung',
      onTap: () => setState(() => _vereinSubview = 'deutschepost'),
    );
  }

  Widget _buildHetznerCard() {
    return _buildClickableCard(
      icon: Icons.dns,
      title: 'Hetzner',
      color: Colors.red,
      subtitle: 'Server, Cloud, Rechnungen',
      onTap: () => setState(() => _vereinSubview = 'hetzner'),
    );
  }

  Widget _buildInwxCard() {
    return _buildClickableCard(
      icon: Icons.language,
      title: 'INWX',
      color: Colors.blueGrey,
      subtitle: 'Domain-Verwaltung, DNS, SSL',
      onTap: () => setState(() => _vereinSubview = 'inwx'),
    );
  }

  Widget _buildITBeschaffungCard() {
    return _buildClickableCard(
      icon: Icons.computer,
      title: 'IT-Beschaffungsplattform',
      color: Colors.deepPurple,
      subtitle: 'Stifter-helfen.de - Software-Spenden',
      onTap: () => setState(() => _vereinSubview = 'it-beschaffung'),
    );
  }

  Widget _buildNotarDetailView() {
    final notarEntries = _getByKategorie('notar');

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vereinSubview = 'overview'),
                tooltip: 'Zurück zur Übersicht',
              ),
              const SizedBox(width: 8),
              Icon(Icons.gavel, size: 32, color: Colors.deepOrange.shade700),
              const SizedBox(width: 12),
              const Text(
                'Notar',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : notarEntries.isEmpty
                    ? const Center(child: Text('Keine Notar-Daten vorhanden'))
                    : ListView.builder(
                        itemCount: notarEntries.length,
                        itemBuilder: (context, index) {
                          final n = notarEntries[index];
                          return _buildContactCard(
                            icon: Icons.gavel,
                            color: Colors.deepOrange,
                            name: n['name'] ?? '',
                            name2: n['name2'],
                            strasse: n['strasse'],
                            hausnummer: n['hausnummer'],
                            plz: n['plz'],
                            ort: n['ort'],
                            telefon: n['telefon'],
                            fax: n['fax'],
                            email: n['email'],
                            website: n['website'],
                            notizen: n['notizen'],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankenDetailView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vereinSubview = 'overview'),
                tooltip: 'Zurück zur Übersicht',
              ),
              const SizedBox(width: 8),
              Icon(Icons.account_balance, size: 32, color: Colors.amber.shade700),
              const SizedBox(width: 12),
              const Text(
                'Banken',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildVolksbankCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildGlsBankCard()),
                const SizedBox(width: 16),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolksbankCard() {
    return _buildClickableCard(
      icon: Icons.account_balance,
      title: 'VR Bank',
      color: Colors.blue,
      subtitle: 'Kontostand, Überweisungen, Lastschriften',
      onTap: () => setState(() => _vereinSubview = 'volksbank'),
    );
  }

  Widget _buildGlsBankCard() {
    return _buildClickableCard(
      icon: Icons.eco,
      title: 'GLS Bank',
      color: Colors.green,
      subtitle: 'Nachhaltige Bankgeschäfte',
      onTap: () => setState(() => _vereinSubview = 'gls'),
    );
  }

  Widget _buildVorstandDetailView() {
    final adminUsers = widget.users.where((u) =>
        ['vorsitzer', 'schatzmeister', 'kassierer', 'mitgliedergrunder'].contains(u.role)
    ).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vereinSubview = 'overview'),
                tooltip: 'Zurück zur Übersicht',
              ),
              const SizedBox(width: 8),
              Icon(Icons.people, size: 32, color: Colors.purple.shade700),
              const SizedBox(width: 12),
              const Text(
                'Vorstand',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Pauschalen Cards
          _buildPauschalenSection(),
          const SizedBox(height: 24),

          // Section header
          Text(
            'Vorstandsmitglieder',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: adminUsers.isEmpty
                ? const Center(child: Text('Keine Vorstandsmitglieder gefunden'))
                : ListView.builder(
                    itemCount: adminUsers.length,
                    itemBuilder: (context, index) {
                      final user = adminUsers[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: widget.getRoleColor(user.role),
                            child: Text(
                              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${widget.getRoleText(user.role)} (${user.mitgliedernummer})'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: user.isActive ? Colors.green.shade100 : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              user.isActive ? 'Aktiv' : user.status,
                              style: TextStyle(
                                fontSize: 12,
                                color: user.isActive ? Colors.green.shade800 : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPauschalenSection() {
    if (_pauschalenLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final pauschalen = _pauschalenData?['pauschalen'] as Map<String, dynamic>?;
    final jahr = _pauschalenData?['jahr'] ?? DateTime.now().year;
    final lastUpdated = _pauschalenData?['last_updated'] ?? '';

    // Fallback values if API fails
    final ehrenamt = pauschalen?['ehrenamtspauschale'];
    final uebungsleiter = pauschalen?['uebungsleiterpauschale'];

    final ehrenamtBetrag = ehrenamt?['aktueller_betrag'] ?? 840;
    final uebungsleiterBetrag = uebungsleiter?['aktueller_betrag'] ?? 3000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet, size: 20, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Text(
              'Steuerliche Freibeträge $jahr',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
            ),
            const Spacer(),
            if (lastUpdated.isNotEmpty)
              Text(
                'Stand: $lastUpdated',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.refresh, size: 18, color: Colors.grey.shade500),
              onPressed: _loadPauschalen,
              tooltip: 'Aktualisieren',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildPauschaleCard(
                title: 'Ehrenamtspauschale',
                paragraph: ehrenamt?['paragraph'] ?? '§ 3 Nr. 26a EStG',
                betrag: ehrenamtBetrag,
                color: Colors.teal,
                icon: Icons.volunteer_activism,
                description: ehrenamt?['description'] ?? 'Steuerfreier Freibetrag für ehrenamtliche Tätigkeiten',
                hinweise: List<String>.from(ehrenamt?['hinweise'] ?? []),
                history: List<Map<String, dynamic>>.from(ehrenamt?['history'] ?? []),
                quelle: ehrenamt?['quelle'] ?? '',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildPauschaleCard(
                title: 'Übungsleiterpauschale',
                paragraph: uebungsleiter?['paragraph'] ?? '§ 3 Nr. 26 EStG',
                betrag: uebungsleiterBetrag,
                color: Colors.indigo,
                icon: Icons.school,
                description: uebungsleiter?['description'] ?? 'Steuerfreier Freibetrag für Übungsleiter',
                hinweise: List<String>.from(uebungsleiter?['hinweise'] ?? []),
                history: List<Map<String, dynamic>>.from(uebungsleiter?['history'] ?? []),
                quelle: uebungsleiter?['quelle'] ?? '',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPauschaleCard({
    required String title,
    required String paragraph,
    required int betrag,
    required Color color,
    required IconData icon,
    required String description,
    required List<String> hinweise,
    required List<Map<String, dynamic>> history,
    required String quelle,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showPauschaleDetails(
          title: title,
          paragraph: paragraph,
          betrag: betrag,
          color: color,
          icon: icon,
          description: description,
          hinweise: hinweise,
          history: history,
          quelle: quelle,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.05), color.withValues(alpha: 0.15)],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 28, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          paragraph,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '${betrag.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} € / Jahr',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Steuerfrei',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPauschaleDetails({
    required String title,
    required String paragraph,
    required int betrag,
    required Color color,
    required IconData icon,
    required String description,
    required List<String> hinweise,
    required List<Map<String, dynamic>> history,
    required String quelle,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 20)),
                  Text(paragraph, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Current amount
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${betrag.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} € / Jahr',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
                      ),
                      const SizedBox(height: 4),
                      Text('Aktueller Freibetrag ${DateTime.now().year}',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Description
                Text(description, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 16),

                // Hinweise
                if (hinweise.isNotEmpty) ...[
                  const Text('Hinweise:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  ...hinweise.map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: color),
                        const SizedBox(width: 8),
                        Expanded(child: Text(h, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),
                ],

                // History
                if (history.isNotEmpty) ...[
                  const Text('Historische Entwicklung:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  ...history.take(8).map((h) {
                    final isCurrentYear = h['jahr'] == DateTime.now().year;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isCurrentYear ? color.withValues(alpha: 0.1) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: isCurrentYear ? Border.all(color: color.withValues(alpha: 0.3)) : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${h['jahr']}',
                            style: TextStyle(
                              fontWeight: isCurrentYear ? FontWeight.bold : FontWeight.normal,
                              color: isCurrentYear ? color : null,
                            ),
                          ),
                          Text(
                            '${h['betrag'].toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} €',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isCurrentYear ? color : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                // Source link
                if (quelle.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => _launchURL(quelle),
                    child: Row(
                      children: [
                        Icon(Icons.open_in_new, size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Quelle: gesetze-im-internet.de',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Widget _buildHetznerDetailView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vereinSubview = 'partner'),
                tooltip: 'Zurück zu Partner',
              ),
              const SizedBox(width: 8),
              Icon(Icons.dns, size: 32, color: Colors.red.shade700),
              const SizedBox(width: 12),
              const Text(
                'Hetzner',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _buildInfoCard(
              icon: Icons.cloud,
              title: 'Hetzner Services',
              color: Colors.red,
              items: [
                'Dedicated Server: 148.251.68.9 (Proxmox)',
                'Cloud Storage',
                'Backup Solutions',
                'Rechnungen & Verträge',
                'Support-Tickets',
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInwxDetailView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vereinSubview = 'partner'),
                tooltip: 'Zurück zu Partner',
              ),
              const SizedBox(width: 8),
              Icon(Icons.language, size: 32, color: Colors.blueGrey.shade700),
              const SizedBox(width: 12),
              const Text(
                'INWX',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _buildInfoCard(
              icon: Icons.dns,
              title: 'INWX Domain-Services',
              color: Colors.blueGrey,
              items: [
                'Domain: icd360s.de',
                'DNS-Verwaltung',
                'SSL-Zertifikate',
                'E-Mail-Weiterleitungen',
                'Nameserver-Einstellungen',
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildITBeschaffungDetailView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vereinSubview = 'partner'),
                tooltip: 'Zurück zu Partner',
              ),
              const SizedBox(width: 8),
              Icon(Icons.computer, size: 32, color: Colors.deepPurple.shade700),
              const SizedBox(width: 12),
              const Text(
                'IT-Beschaffungsplattform',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Stifter-helfen Card (clickable)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildStifterHelfenClickableCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildGoogleNonprofitClickableCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildMicrosoftNonprofitClickableCard()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStifterHelfenClickableCard() {
    return _buildClickableCard(
      icon: Icons.volunteer_activism,
      title: 'Stifter-helfen',
      color: Colors.deepPurple,
      subtitle: 'IT for Nonprofits - Software-Spenden',
      onTap: () => setState(() => _vereinSubview = 'stifter-helfen'),
      badge: _stifterHelfenOpenAufgaben > 0
          ? '$_stifterHelfenOpenAufgaben offene Aufgaben'
          : null,
      badgeColor: _stifterHelfenOpenAufgaben > 0 ? Colors.orange : null,
    );
  }

  Widget _buildGoogleNonprofitClickableCard() {
    return _buildClickableCard(
      icon: Icons.cloud,
      title: 'Google for Nonprofits',
      color: Colors.blue,
      subtitle: 'Workspace, Ad Grants, YouTube',
      onTap: () => setState(() => _vereinSubview = 'google-nonprofit'),
      badge: _googleNonprofitOpenAufgaben > 0
          ? '$_googleNonprofitOpenAufgaben offene Aufgaben'
          : null,
      badgeColor: _googleNonprofitOpenAufgaben > 0 ? Colors.orange : null,
    );
  }

  Widget _buildMicrosoftNonprofitClickableCard() {
    return _buildClickableCard(
      icon: Icons.window,
      title: 'Microsoft for Nonprofits',
      color: Colors.orange,
      subtitle: 'Microsoft 365, Azure, Dynamics',
      onTap: () => setState(() => _vereinSubview = 'microsoft-nonprofit'),
      badge: _microsoftNonprofitOpenAufgaben > 0
          ? '$_microsoftNonprofitOpenAufgaben offene Aufgaben'
          : null,
      badgeColor: _microsoftNonprofitOpenAufgaben > 0 ? Colors.orange : null,
    );
  }

  Widget _buildServdiscountCard() {
    return _buildClickableCard(
      icon: Icons.dns,
      title: 'servdiscount.com',
      color: Colors.orange,
      subtitle: 'myLoc managed IT AG — Dedicated Server',
      onTap: () => setState(() => _vereinSubview = 'servdiscount'),
    );
  }

  Widget _buildJasminaCard() {
    return _buildClickableCard(
      icon: Icons.business,
      title: 'Jasmina UG',
      color: Colors.teal,
      subtitle: 'Jasmina UG (haftungsbeschränkt)',
      onTap: () => setState(() => _vereinSubview = 'jasmina'),
      badge: _jasminaOpenAufgaben > 0
          ? '$_jasminaOpenAufgaben offene Aufgaben'
          : null,
      badgeColor: _jasminaOpenAufgaben > 0 ? Colors.orange : null,
    );
  }

  Widget _buildStifterHelfenDetailView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vereinSubview = 'it-beschaffung'),
                tooltip: 'Zurück zu IT-Beschaffung',
              ),
              const SizedBox(width: 8),
              Icon(Icons.volunteer_activism, size: 32, color: Colors.deepPurple.shade700),
              const SizedBox(width: 12),
              const Text(
                'Stifter-helfen.de',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(
                    icon: Icons.card_giftcard,
                    title: 'Software-Spenden für gemeinnützige Organisationen',
                    color: Colors.deepPurple,
                    items: [
                      'Microsoft 365 (bis zu 90% Rabatt)',
                      'Adobe Creative Cloud (65% Rabatt)',
                      'Dropbox Business',
                      'Zoom Pro/Business',
                      'Slack',
                      'Canva Pro',
                      'Asana Business',
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _launchURL('https://www.stifter-helfen.de'),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Stifter-helfen.de öffnen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HELPER WIDGETS ====================

  Widget _buildClickableCard({
    required IconData icon,
    required String title,
    required Color color,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              if (badge != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? Colors.orange).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: (badgeColor ?? Colors.orange).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.task_alt, size: 14, color: badgeColor ?? Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        badge,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: badgeColor ?? Colors.orange),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<String> items,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 32, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item, style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required Color color,
    required String name,
    String? name2,
    String? strasse,
    String? hausnummer,
    String? plz,
    String? ort,
    String? telefon,
    String? fax,
    String? email,
    String? website,
    String? notizen,
  }) {
    final address = [
      if (strasse != null) '$strasse${hausnummer != null ? ' $hausnummer' : ''}',
      if (plz != null || ort != null) '${plz ?? ''} ${ort ?? ''}'.trim(),
    ].where((s) => s.isNotEmpty).join(', ');

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 28, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (name2 != null && name2.isNotEmpty)
                        Text(name2, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (address.isNotEmpty)
              _buildContactRow(Icons.location_on, address),
            if (telefon != null && telefon.isNotEmpty)
              _buildContactRow(Icons.phone, telefon),
            if (fax != null && fax.isNotEmpty)
              _buildContactRow(Icons.fax, 'Fax: $fax'),
            if (email != null && email.isNotEmpty)
              _buildContactRow(Icons.email, email),
            if (website != null && website.isNotEmpty)
              InkWell(
                onTap: () => _launchURL(website),
                child: _buildContactRow(Icons.language, website, isLink: true),
              ),
            if (notizen != null && notizen.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notes, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(notizen, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String text, {bool isLink = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isLink ? Colors.blue : null,
                decoration: isLink ? TextDecoration.underline : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
