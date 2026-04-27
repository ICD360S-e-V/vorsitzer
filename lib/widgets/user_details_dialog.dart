import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/verwarnung_service.dart';
import '../services/dokumente_service.dart';
import '../services/ticket_service.dart';
import '../services/termin_service.dart';
import '../models/user.dart';
import '../utils/role_helpers.dart';
import '../screens/ordnungsmassnahmen_screen.dart';
import 'file_viewer_dialog.dart';
import 'ticket_details_dialog.dart';
import 'behorde_tab_content.dart';
import 'gesundheit_tab_content.dart';
import 'finanzen_tab_content.dart';
import 'freizeit_tab_content.dart';
import 'mitglieder_device.dart';
import 'member_devices_widget.dart';
import 'vertraege_content.dart';
import 'empfehlung.dart';
import '../utils/file_picker_helper.dart';

class UserDetailsDialog extends StatefulWidget {
  final User user;
  final ApiService apiService;
  final VoidCallback onUpdated;
  final String adminMitgliedernummer;

  const UserDetailsDialog({
    super.key,
    required this.user,
    required this.apiService,
    required this.onUpdated,
    required this.adminMitgliedernummer,
  });

  @override
  State<UserDetailsDialog> createState() => _UserDetailsDialogState();
}

class _UserDetailsDialogState extends State<UserDetailsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _devices = [];

  // Verwarnungen
  final _verwarnungService = VerwarnungService();
  List<Verwarnung> _verwarnungen = [];
  VerwarnungStats? _verwarnungStats;
  bool _isLoadingVerwarnungen = false;
  bool _isSubmittingWarning = false;
  final _sachverhaltVerwarnungController = TextEditingController();
  VerstossKategorie? _selectedVerstossKat;
  Massnahme? _selectedMassnahmeTyp;
  final _ordnungsgeldBetragController = TextEditingController(text: '50');
  DateTime _selectedDatum = DateTime.now();

  // Dokumente
  final _dokumenteService = DokumenteService();
  List<MemberDokument> _dokumente = [];
  bool _isLoadingDokumente = false;
  bool _isUploadingDokument = false;

  // Edit controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'vorsitzer';

  // Verifizierung
  List<Map<String, dynamic>> _verifizierungStages = [];
  bool _isLoadingVerifizierung = false;
  bool _isUpdatingVerifizierung = false;
  String? _verifizierungFinanzielleSituation;
  Map<String, String?> _verifizierungAcceptances = {};

  // Stufe 1 edit controllers
  final _stufe1VornameController = TextEditingController();
  final _stufe1NachnameController = TextEditingController();
  final _stufe1GeburtsdatumController = TextEditingController();
  final _stufe1GeburtsortController = TextEditingController();
  final _stufe1StrasseController = TextEditingController();
  final _stufe1HausnummerController = TextEditingController();
  final _stufe1PlzController = TextEditingController();
  final _stufe1OrtController = TextEditingController();
  final _stufe1TelefonController = TextEditingController();
  String _stufe1Geschlecht = 'M';
  String _stufe1Familienstand = '';
  String _stufe1Staatsangehoerigkeit = 'deutsch';
  List<Map<String, dynamic>> _staatsangehoerigkeitenListe = [];
  bool _isSavingStufe1 = false;

  // Befreiung
  List<Map<String, dynamic>> _befreiungen = [];
  bool _isBefreit = false;
  bool _isLoadingBefreiung = false;

  // Ermäßigung
  List<Map<String, dynamic>> _ermaessigungen = [];
  bool _isLoadingErmaessigung = false;

  // Notizen
  List<Map<String, dynamic>> _notizen = [];
  bool _isLoadingNotizen = false;
  final _notizController = TextEditingController();
  String _notizKategorie = 'allgemein';
  bool _notizWichtig = false;

  // Tickets
  final _ticketService = TicketService();
  List<Ticket> _memberTickets = [];
  bool _isLoadingTickets = false;
  UserTimeSummary? _userTimeSummary;
  bool _isLoadingTimeSummary = false;

  // Termine
  final _terminService = TerminService();
  List<Termin> _memberTermine = [];
  bool _isLoadingTermine = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 17, vsync: this);
    _nameController.text = widget.user.name;
    _emailController.text = widget.user.email;
    _selectedRole = widget.user.role;
    _verwarnungService.setToken(widget.apiService.token);
    _dokumenteService.setToken(widget.apiService.token);
    _terminService.setToken(widget.apiService.token);
    _initStufe1Controllers();
    _loadUserDetails();
    _loadVerwarnungen();
    _loadDokumente();
    _loadVerifizierung();
    _loadBefreiungen();
    _loadErmaessigungen();
    _loadNotizen();
    _loadMemberTickets();
    _loadUserTimeSummary();
    _loadMemberTermine();
  }

  void _initStufe1Controllers() {
    final user = widget.user;
    _stufe1VornameController.text = user.vorname ?? '';
    _stufe1NachnameController.text = user.nachname ?? '';
    // Convert YYYY-MM-DD to DD.MM.YYYY for display
    final geb = user.geburtsdatum ?? '';
    if (geb.contains('-') && geb.length == 10) {
      final parts = geb.split('-');
      _stufe1GeburtsdatumController.text = '${parts[2]}.${parts[1]}.${parts[0]}';
    } else {
      _stufe1GeburtsdatumController.text = geb;
    }
    _stufe1GeburtsortController.text = user.geburtsort ?? '';
    _stufe1StrasseController.text = user.strasse ?? '';
    _stufe1HausnummerController.text = user.hausnummer ?? '';
    _stufe1PlzController.text = user.plz ?? '';
    _stufe1OrtController.text = user.ort ?? '';
    _stufe1TelefonController.text = user.telefonMobil ?? '';
    final g = user.geschlecht ?? 'M';
    _stufe1Geschlecht = ['M', 'W', 'D'].contains(g) ? g : 'M';
    _stufe1Familienstand = user.familienstand ?? '';
    _stufe1Staatsangehoerigkeit = user.staatsangehoerigkeit ?? 'deutsch';
    // Load Staatsangehörigkeiten liste
    widget.apiService.getStaatsangehoerigkeiten().then((result) {
      if (mounted && result['success'] == true && result['data'] != null) {
        setState(() => _staatsangehoerigkeitenListe = List<Map<String, dynamic>>.from(result['data']));
      }
    });
  }

  Future<void> _saveStufe1Data() async {
    setState(() => _isSavingStufe1 = true);
    try {
      final vorname = _stufe1VornameController.text.trim();
      final nachname = _stufe1NachnameController.text.trim();
      // Convert DD.MM.YYYY to YYYY-MM-DD for server
      final gebRaw = _stufe1GeburtsdatumController.text.trim();
      String? geburtsdatum;
      if (gebRaw.contains('.') && gebRaw.length == 10) {
        final parts = gebRaw.split('.');
        geburtsdatum = '${parts[2]}-${parts[1]}-${parts[0]}';
      } else if (gebRaw.isNotEmpty) {
        geburtsdatum = gebRaw;
      }
      final geburtsort = _stufe1GeburtsortController.text.trim();
      final strasse = _stufe1StrasseController.text.trim();
      final hausnummer = _stufe1HausnummerController.text.trim();
      final plz = _stufe1PlzController.text.trim();
      final ort = _stufe1OrtController.text.trim();
      final telefon = _stufe1TelefonController.text.trim();
      final result = await widget.apiService.updateUser(
        userId: widget.user.id,
        vorname: vorname.isNotEmpty ? vorname : null,
        nachname: nachname.isNotEmpty ? nachname : null,
        geburtsdatum: geburtsdatum,
        geburtsort: geburtsort.isNotEmpty ? geburtsort : null,
        strasse: strasse.isNotEmpty ? strasse : null,
        hausnummer: hausnummer.isNotEmpty ? hausnummer : null,
        plz: plz.isNotEmpty ? plz : null,
        ort: ort.isNotEmpty ? ort : null,
        telefonMobil: telefon.isNotEmpty ? telefon : null,
        geschlecht: _stufe1Geschlecht,
        familienstand: _stufe1Familienstand.isNotEmpty ? _stufe1Familienstand : null,
        staatsangehoerigkeit: _stufe1Staatsangehoerigkeit.isNotEmpty ? _stufe1Staatsangehoerigkeit : null,
      );
      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Persönliche Daten gespeichert'), backgroundColor: Colors.green),
          );
          widget.onUpdated();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler beim Speichern'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingStufe1 = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _sachverhaltVerwarnungController.dispose();
    _ordnungsgeldBetragController.dispose();
    _notizController.dispose();
    _stufe1VornameController.dispose();
    _stufe1NachnameController.dispose();
    _stufe1GeburtsdatumController.dispose();
    _stufe1StrasseController.dispose();
    _stufe1HausnummerController.dispose();
    _stufe1PlzController.dispose();
    _stufe1OrtController.dispose();
    _stufe1TelefonController.dispose();
    super.dispose();
  }

  Future<void> _loadUserDetails() async {
    try {
      final result = await widget.apiService.getUserDetails(widget.user.id);

      if (result['success'] == true && mounted) {
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(result['sessions'] ?? []);
          _devices = List<Map<String, dynamic>>.from(result['devices'] ?? []);
          _isLoading = false;
        });
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fehler beim Laden: ${result['message'] ?? 'Unknown error'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verbindungsfehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveChanges() async {
    String? newName = _nameController.text.trim() != widget.user.name ? _nameController.text.trim() : null;
    String? newEmail = _emailController.text.trim() != widget.user.email ? _emailController.text.trim() : null;
    String? newPassword = _passwordController.text.isNotEmpty ? _passwordController.text : null;
    String? newRole = _selectedRole != widget.user.role ? _selectedRole : null;

    if (newName == null && newEmail == null && newPassword == null && newRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Änderungen')),
      );
      return;
    }

    try {
      final result = await widget.apiService.updateUser(
        userId: widget.user.id,
        name: newName,
        email: newEmail,
        password: newPassword,
        role: newRole,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Benutzer erfolgreich aktualisiert'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onUpdated();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Fehler beim Aktualisieren'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _revokeSession(int sessionId) async {
    try {
      final result = await widget.apiService.revokeSession(sessionId);

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sitzung widerrufen - Benutzer wurde abgemeldet'),
            backgroundColor: Colors.green,
          ),
        );
        _loadUserDetails(); // Reload sessions
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: ${result['message'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verbindungsfehler: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadVerwarnungen() async {
    setState(() => _isLoadingVerwarnungen = true);
    _verwarnungService.setToken(widget.apiService.token);
    final result = await _verwarnungService.getVerwarnungen(widget.user.id);
    if (mounted) {
      setState(() {
        if (result != null) {
          _verwarnungen = result.warnings;
          _verwarnungStats = result.stats;
        }
        _isLoadingVerwarnungen = false;
      });
    }
  }

  Future<void> _createVerwarnung() async {
    if (_selectedVerstossKat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Verstoß-Kategorie auswählen'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (_selectedMassnahmeTyp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Maßnahme auswählen'), backgroundColor: Colors.orange),
      );
      return;
    }
    final sachverhalt = _sachverhaltVerwarnungController.text.trim();
    if (sachverhalt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Sachverhalt beschreiben'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSubmittingWarning = true);
    _verwarnungService.setToken(widget.apiService.token);

    // Map Massnahme id to legacy typ for backend
    String typ;
    switch (_selectedMassnahmeTyp!.id) {
      case 'verwarnung':
        typ = 'ermahnung';
        break;
      case 'ordnungsgeld':
        typ = 'abmahnung';
        break;
      case 'ausschluss':
        typ = 'letzte_abmahnung';
        break;
      default:
        typ = 'ermahnung';
    }

    final grund = '${_selectedVerstossKat!.titel} (${_selectedVerstossKat!.paragraph})';

    final result = await _verwarnungService.createVerwarnung(
      userId: widget.user.id,
      typ: typ,
      grund: grund,
      beschreibung: sachverhalt,
      datum: DateFormat('yyyy-MM-dd').format(_selectedDatum),
    );

    if (!mounted) return;

    setState(() => _isSubmittingWarning = false);

    if (result != null) {
      // Generate PDF
      final ordnungsgeld = _selectedMassnahmeTyp!.id == 'ordnungsgeld'
          ? _ordnungsgeldBetragController.text.trim()
          : null;

      final pdfResult = await VerwarnungPdfGenerator.generate(
        userName: widget.user.name,
        mitgliedernummer: widget.user.mitgliedernummer,
        massnahmeId: _selectedMassnahmeTyp!.id,
        massnahmeTitel: _selectedMassnahmeTyp!.titel,
        verstossTitel: _selectedVerstossKat!.titel,
        verstossParagraph: _selectedVerstossKat!.paragraph,
        verstossBeschreibung: _selectedVerstossKat!.beschreibung,
        sachverhalt: sachverhalt,
        vorfallDatum: _selectedDatum,
        ordnungsgeldBetrag: ordnungsgeld,
      );

      if (pdfResult != null && mounted) {
        await VerwarnungPdfGenerator.saveAndPreview(
          context,
          pdfResult.bytes,
          pdfResult.fileName,
        );
      }

      _sachverhaltVerwarnungController.clear();
      setState(() {
        _selectedVerstossKat = null;
        _selectedMassnahmeTyp = null;
        _ordnungsgeldBetragController.text = '50';
        _selectedDatum = DateTime.now();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedMassnahmeTyp?.titel ?? 'Ordnungsmaßnahme'} für ${widget.user.name} erstellt'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadVerwarnungen();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Erstellen der Verwarnung'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteVerwarnung(Verwarnung v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Verwarnung löschen?'),
          ],
        ),
        content: Text('${v.typDisplay} vom ${DateFormat('dd.MM.yyyy').format(v.datum)} wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _verwarnungService.setToken(widget.apiService.token);
      final success = await _verwarnungService.deleteVerwarnung(v.id);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verwarnung gelöscht'), backgroundColor: Colors.green),
        );
        _loadVerwarnungen();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Löschen'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _generateVerwarnungPdf(Verwarnung v) async {
    final massnahmeId = VerwarnungPdfGenerator.typToMassnahmeId(v.typ);
    final massnahmeTitel = VerwarnungPdfGenerator.typToMassnahmeTitel(v.typ);

    // Try to find matching Verstoss from grund text
    String verstossTitel = v.grund;
    String verstossParagraph = '§6 Abs. 6 Satzung';
    String verstossBeschreibung = v.beschreibung ?? v.grund;

    for (final vk in VerwarnungPdfGenerator.verstossKategorien) {
      if (v.grund.contains(vk.titel) || v.grund.contains(vk.paragraph)) {
        verstossTitel = vk.titel;
        verstossParagraph = vk.paragraph;
        verstossBeschreibung = v.beschreibung ?? vk.beschreibung;
        break;
      }
    }

    final result = await VerwarnungPdfGenerator.generate(
      userName: widget.user.name,
      mitgliedernummer: widget.user.mitgliedernummer,
      massnahmeId: massnahmeId,
      massnahmeTitel: massnahmeTitel,
      verstossTitel: verstossTitel,
      verstossParagraph: verstossParagraph,
      verstossBeschreibung: verstossBeschreibung,
      sachverhalt: v.beschreibung ?? v.grund,
      vorfallDatum: v.datum,
    );

    if (result != null && mounted) {
      await VerwarnungPdfGenerator.saveAndPreview(
        context,
        result.bytes,
        result.fileName,
      );
    }
  }

  MaterialColor _getTypColor(String typ) {
    switch (typ) {
      case 'ermahnung':
        return Colors.amber;
      case 'abmahnung':
        return Colors.orange;
      case 'letzte_abmahnung':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypIcon(String typ) {
    switch (typ) {
      case 'ermahnung':
        return Icons.info_outline;
      case 'abmahnung':
        return Icons.warning_amber;
      case 'letzte_abmahnung':
        return Icons.gavel;
      default:
        return Icons.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: screenSize.width - 48,
        height: screenSize.height - 48,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.user.mitgliedernummer,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Tabs
            Container(
              color: Colors.grey.shade200,
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.blue.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.blue.shade700,
                isScrollable: true,
                tabs: const [
                  Tab(icon: Icon(Icons.account_circle), text: 'Konto'),
                  Tab(icon: Icon(Icons.devices), text: 'Geräte'),
                  Tab(icon: Icon(Icons.vpn_key), text: 'Aktivierung'),
                  Tab(icon: Icon(Icons.warning_amber), text: 'Verwarnungen'),
                  Tab(icon: Icon(Icons.folder_open), text: 'Dokumente'),
                  Tab(icon: Icon(Icons.card_membership), text: 'Mitgliedschaft'),
                  Tab(icon: Icon(Icons.verified_user), text: 'Verifizierung'),
                  Tab(icon: Icon(Icons.discount), text: 'Ermäßigung'),
                  Tab(icon: Icon(Icons.sticky_note_2), text: 'Notizen'),
                  Tab(icon: Icon(Icons.confirmation_number), text: 'Tickets'),
                  Tab(icon: Icon(Icons.calendar_month), text: 'Termine'),
                  Tab(icon: Icon(Icons.account_balance), text: 'Behörde'),
                  Tab(icon: Icon(Icons.local_hospital), text: 'Ärzte'),
                  Tab(icon: Icon(Icons.account_balance_wallet), text: 'Finanzen'),
                  Tab(icon: Icon(Icons.sports_esports), text: 'Freizeit'),
                  Tab(icon: Icon(Icons.receipt_long), text: 'Verträge'),
                  Tab(icon: Icon(Icons.thumb_up), text: 'Empfehlung'),
                ],
              ),
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildKontoTab(),
                  MitgliederDeviceWidget(
                    sessions: _sessions,
                    devices: _devices,
                    isLoading: _isLoading,
                    onRevokeSession: (id) => _confirmRevokeSession(id),
                  ),
                  widget.user.role == 'vorsitzer'
                      ? MemberDevicesSection(
                          apiService: widget.apiService,
                          userId: widget.user.id,
                          mitgliedernummer: widget.user.mitgliedernummer,
                          userName: widget.user.name,
                        )
                      : _buildNoActivationForMember(),
                  _buildVerwarnungenTab(),
                  _buildDokumenteTab(),
                  _buildMitgliedschaftTab(),
                  _buildVerifizierungTab(),
                  _buildErmaessigungTab(),
                  _buildNotizenTab(),
                  _buildTicketsTab(),
                  _buildTermineTab(),
                  _buildBehoerdeTab(),
                  _buildGesundheitTab(),
                  _buildFinanzenTab(),
                  _buildFreizeitTab(),
                  VertraegeContent(
                    apiService: widget.apiService,
                    userId: widget.user.id,
                  ),
                  EmpfehlungContent(
                    apiService: widget.apiService,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKontoTab() {
    final user = widget.user;
    final dateFormat = DateFormat('dd.MM.yyyy, HH:mm');

    // Determine if account is deactivated
    final bool isDeactivated = user.isSuspended || user.isGesperrt || user.isDeleted ||
        user.isGekuendigt || user.isAusgeschlossen || user.isVerstorben;

    // Full name
    String fullName = user.name;
    if (user.vorname != null && user.nachname != null) {
      fullName = [user.vorname, user.vorname2, user.nachname]
          .where((s) => s != null && s.isNotEmpty)
          .join(' ');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - Konto Status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDeactivated ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDeactivated ? Colors.red.shade200 : Colors.green.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isDeactivated ? Icons.block : Icons.check_circle,
                  color: isDeactivated ? Colors.red : Colors.green,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  isDeactivated ? 'Konto deaktiviert' : 'Konto aktiv',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDeactivated ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- Kontodaten Section ---
          Text(
            'Kontodaten',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),

          // Name (display + edit pencil)
          _kontoRow(
            icon: Icons.person,
            label: 'Name',
            value: fullName,
            onEdit: () => _showEditNameDialog(),
          ),
          const Divider(height: 1),

          // E-Mail (display + edit pencil)
          _kontoRow(
            icon: Icons.email,
            label: 'E-Mail',
            value: user.email,
            onEdit: () => _showEditEmailDialog(),
          ),
          const Divider(height: 1),

          // Rolle (display + edit pencil)
          _kontoRow(
            icon: Icons.badge,
            label: 'Rolle',
            value: getRoleText(user.role),
            valueColor: getRoleColor(user.role),
            onEdit: () => _showEditRoleDialog(),
          ),
          const Divider(height: 1),

          // Passwort (edit pencil)
          _kontoRow(
            icon: Icons.lock,
            label: 'Passwort',
            value: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
            onEdit: () => _showEditPasswordDialog(),
          ),
          const SizedBox(height: 24),

          // --- Registrierung Section ---
          Text(
            'Registrierung',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),

          // Registrierungsdatum
          _kontoRow(
            icon: Icons.calendar_today,
            label: 'Registriert am',
            value: user.createdAt != null
                ? dateFormat.format(user.createdAt!)
                : '–',
          ),
          const Divider(height: 1),

          // Letzter Login
          _kontoRow(
            icon: Icons.login,
            label: 'Letzter Login',
            value: user.lastLogin != null
                ? dateFormat.format(user.lastLogin!)
                : '–',
          ),

          // --- Deaktivierung Section (only if deactivated) ---
          if (isDeactivated) ...[
            const SizedBox(height: 24),
            Text(
              'Deaktivierung',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 12),

            // Deaktivierungsdatum
            _kontoRow(
              icon: Icons.event_busy,
              label: 'Deaktiviert am',
              value: user.deactivatedAt != null
                  ? dateFormat.format(user.deactivatedAt!)
                  : 'Nicht erfasst',
              valueColor: Colors.red.shade700,
            ),
            const Divider(height: 1),

            // Grund
            _kontoRow(
              icon: Icons.info_outline,
              label: 'Grund',
              value: user.deactivationReason ?? 'Kein Grund angegeben',
              valueColor: Colors.red.shade700,
            ),

            // 30-day auto-deactivation info
            if (user.deactivationReason != null &&
                user.deactivationReason!.contains('30 Tage')) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, color: Colors.amber.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dieses Konto wurde automatisch deaktiviert, da die Verifizierung '
                        'nicht innerhalb von 30 Tagen nach der Registrierung abgeschlossen wurde.',
                        style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _kontoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    VoidCallback? onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
          if (onEdit != null)
            IconButton(
              icon: Icon(Icons.edit, size: 18, color: Colors.blue.shade600),
              onPressed: onEdit,
              tooltip: '$label bearbeiten',
              splashRadius: 18,
            ),
        ],
      ),
    );
  }

  Future<void> _showEditNameDialog() async {
    _nameController.text = widget.user.name;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name bearbeiten'),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (result == true) _saveChanges();
  }

  Future<void> _showEditEmailDialog() async {
    _emailController.text = widget.user.email;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('E-Mail bearbeiten'),
        content: TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'E-Mail',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (result == true) _saveChanges();
  }

  Future<void> _showEditRoleDialog() async {
    String tempRole = _selectedRole;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Rolle bearbeiten'),
          content: DropdownButtonFormField<String>(
            initialValue: tempRole,
            decoration: const InputDecoration(
              labelText: 'Rolle',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge),
            ),
            items: const [
              DropdownMenuItem(value: 'vorsitzer', child: Text('Vorsitzer')),
              DropdownMenuItem(value: 'schatzmeister', child: Text('Schatzmeister')),
              DropdownMenuItem(value: 'kassierer', child: Text('Kassierer')),
              DropdownMenuItem(value: 'mitgliedergrunder', child: Text('Gründer')),
              DropdownMenuItem(value: 'mitglied', child: Text('Mitglied')),
            ],
            onChanged: (value) {
              if (value != null) setDialogState(() => tempRole = value);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                setState(() => _selectedRole = tempRole);
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (result == true) _saveChanges();
  }

  Future<void> _showEditPasswordDialog() async {
    _passwordController.clear();
    bool obscure = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Passwort ändern'),
            content: TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Neues Passwort',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setDialogState(() => obscure = !obscure),
                ),
                hintText: 'Mindestens 8 Zeichen',
              ),
              obscureText: obscure,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
              ElevatedButton(
                onPressed: () {
                  if (_passwordController.text.length < 8) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passwort muss mindestens 8 Zeichen lang sein'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      ),
    );
    if (result == true) _saveChanges();
  }

  Widget _buildNoActivationForMember() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_active, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Nur für Vorsitzer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              'Diese Admin-App ist ausschließlich für den Vorstand. '
              'Aktivierungscodes werden nur für Rolle „Vorsitzer" erstellt. '
              'Normale Mitglieder nutzen die separate Mitglieder-App.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerwarnungenTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          if (_verwarnungStats != null && _verwarnungStats!.total > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  _buildStatChip('Gesamt', _verwarnungStats!.total, Colors.grey),
                  const SizedBox(width: 8),
                  if (_verwarnungStats!.ermahnung > 0)
                    _buildStatChip('Ermahnung', _verwarnungStats!.ermahnung, Colors.amber),
                  if (_verwarnungStats!.ermahnung > 0) const SizedBox(width: 8),
                  if (_verwarnungStats!.abmahnung > 0)
                    _buildStatChip('Abmahnung', _verwarnungStats!.abmahnung, Colors.orange),
                  if (_verwarnungStats!.abmahnung > 0) const SizedBox(width: 8),
                  if (_verwarnungStats!.letzteAbmahnung > 0)
                    _buildStatChip('Letzte', _verwarnungStats!.letzteAbmahnung, Colors.red),
                ],
              ),
            ),

          // Create warning form
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gavel, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Text('Neue Ordnungsmaßnahme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 1. Verstoß-Kategorie
                  const Text('Verstoß:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: VerwarnungPdfGenerator.verstossKategorien.map((vk) {
                      final selected = _selectedVerstossKat?.id == vk.id;
                      return ChoiceChip(
                        label: Text(vk.titel, style: const TextStyle(fontSize: 11)),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedVerstossKat = vk),
                        selectedColor: (vk.color as MaterialColor?)?.shade100 ?? vk.color.withValues(alpha: 0.2),
                        avatar: selected ? Icon(vk.icon, size: 14, color: vk.color) : null,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  if (_selectedVerstossKat != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(_selectedVerstossKat!.icon, size: 16, color: _selectedVerstossKat!.color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_selectedVerstossKat!.paragraph} — ${_selectedVerstossKat!.beschreibung}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // 2. Sachverhalt
                  TextField(
                    controller: _sachverhaltVerwarnungController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Sachverhalt (was ist passiert?)',
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 48),
                        child: Icon(Icons.description),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. Maßnahme
                  const Text('Maßnahme (§6 Abs. 6):', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: VerwarnungPdfGenerator.massnahmen.map((m) {
                      final selected = _selectedMassnahmeTyp?.id == m.id;
                      return ChoiceChip(
                        label: Text(m.titel, style: const TextStyle(fontSize: 11)),
                        selected: selected,
                        onSelected: (_) => setState(() => _selectedMassnahmeTyp = m),
                        selectedColor: (m.color as MaterialColor?)?.shade100 ?? m.color.withValues(alpha: 0.2),
                        avatar: selected ? Icon(m.icon, size: 14, color: m.color) : null,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),

                  // Ordnungsgeld amount field
                  if (_selectedMassnahmeTyp?.id == 'ordnungsgeld') ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _ordnungsgeldBetragController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Betrag (max. 100 €)',
                          prefixIcon: const Icon(Icons.euro, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // 4. Date + Submit row
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDatum,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            locale: const Locale('de', 'DE'),
                          );
                          if (picked != null) setState(() => _selectedDatum = picked);
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(DateFormat('dd.MM.yyyy').format(_selectedDatum)),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _isSubmittingWarning ? null : _createVerwarnung,
                        icon: _isSubmittingWarning
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.gavel),
                        label: const Text('Maßnahme ausstellen + PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Existing warnings list
          Row(
            children: [
              Icon(Icons.list_alt, size: 20, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Text(
                'Verwarnungen (${_verwarnungen.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              if (_isLoadingVerwarnungen)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),

          if (_verwarnungen.isEmpty && !_isLoadingVerwarnungen)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade600),
                    const SizedBox(width: 12),
                    const Text('Keine Verwarnungen vorhanden'),
                  ],
                ),
              ),
            )
          else
            ..._verwarnungen.map((v) {
              final color = _getTypColor(v.typ);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: color.shade300, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_getTypIcon(v.typ), color: color.shade800, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    v.typDisplay,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade900),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('dd.MM.yyyy').format(v.datum),
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(v.grund, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (v.beschreibung != null && v.beschreibung!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(v.beschreibung!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Erstellt von: ${v.createdByName}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.picture_as_pdf, color: Colors.red.shade700, size: 20),
                        tooltip: 'PDF erstellen',
                        onPressed: () => _generateVerwarnungPdf(v),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
                        tooltip: 'Verwarnung löschen',
                        onPressed: () => _deleteVerwarnung(v),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ============= DOKUMENTE =============

  Future<void> _loadDokumente() async {
    setState(() => _isLoadingDokumente = true);
    _dokumenteService.setToken(widget.apiService.token);
    final result = await _dokumenteService.getDokumente(widget.user.id);
    if (mounted) {
      setState(() {
        _dokumente = result;
        _isLoadingDokumente = false;
      });
    }
  }

  Future<void> _uploadDokument({String kategorie = 'vereindokumente'}) async {
    final result = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'txt'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    // Validate: max 10 files
    if (result.files.length > 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 10 Dateien pro Upload'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Validate: max 100MB per file
    for (final f in result.files) {
      if (f.size > 100 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${f.name}" ist zu groß (max. 100 MB)'), backgroundColor: Colors.orange),
        );
        return;
      }
      if (f.path == null) return;
    }

    if (!mounted) return;

    // Show upload dialog with category-specific fields
    final nameController = TextEditingController();
    final beschreibungController = TextEditingController();
    String? selectedDokumentTyp;
    DateTime? selectedAblaufDatum;

    // Pre-fill name for single file
    if (result.files.length == 1) {
      final n = result.files.first.name;
      nameController.text = n.contains('.') ? n.substring(0, n.lastIndexOf('.')) : n;
    } else {
      nameController.text = '${result.files.length} Dokumente';
    }

    // Document types per category
    final vereinTypen = {
      'beitrittsantrag': 'Beitrittsantrag',
      'aufnahmebestaetigung': 'Aufnahmebestätigung',
      'kuendigung': 'Kündigung',
      'sonstiges': 'Sonstiges',
    };
    final behoerdeTypen = {
      'krankenkasse': 'Krankenkasse',
      'finanzamt': 'Finanzamt',
      'sozialversicherung': 'Sozialversicherung',
      'arbeitsamt': 'Arbeitsamt',
      'sonstiges': 'Sonstiges',
    };
    final typen = kategorie == 'vereindokumente' ? vereinTypen : behoerdeTypen;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                kategorie == 'vereindokumente' ? Icons.groups : Icons.account_balance,
                color: kategorie == 'vereindokumente' ? Colors.blue : Colors.teal,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(
                kategorie == 'vereindokumente' ? 'Vereindokument hochladen' : 'Behörde Unterlagen hochladen',
                style: const TextStyle(fontSize: 16),
              )),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // File list
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: result.files.map((f) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(_getFileIcon(f.extension ?? ''), size: 20, color: _getFileColor(f.extension ?? '')),
                            const SizedBox(width: 8),
                            Expanded(child: Text(f.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                            Text(_formatFilesize(f.size), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Encrypted badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text('AES-256 verschlüsselt', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (result.files.length == 1)
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Dokumentname',
                        prefixIcon: const Icon(Icons.description),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  if (result.files.length == 1) const SizedBox(height: 12),
                  // Document type dropdown
                  DropdownButtonFormField<String>(
                    key: ValueKey('doctyp_$selectedDokumentTyp'),
                    initialValue: selectedDokumentTyp,
                    decoration: InputDecoration(
                      labelText: 'Dokumenttyp',
                      prefixIcon: const Icon(Icons.category),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: typen.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => selectedDokumentTyp = val),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: beschreibungController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Beschreibung (optional)',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: Icon(Icons.notes),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  // Ablauf datum for Behörde documents
                  if (kategorie == 'behoerde') ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                          locale: const Locale('de', 'DE'),
                        );
                        if (picked != null) setDialogState(() => selectedAblaufDatum = picked);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Ablaufdatum',
                          prefixIcon: const Icon(Icons.event, color: Colors.red),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          suffixIcon: selectedAblaufDatum != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setDialogState(() => selectedAblaufDatum = null),
                                )
                              : null,
                        ),
                        child: Text(
                          selectedAblaufDatum != null
                              ? DateFormat('dd.MM.yyyy').format(selectedAblaufDatum!)
                              : 'Kein Ablaufdatum',
                          style: TextStyle(
                            color: selectedAblaufDatum != null ? Colors.black87 : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Dokumente mit Ablaufdatum werden nach Ablauf automatisch gelöscht.',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.upload),
              label: Text('${result.files.length} ${result.files.length == 1 ? "Datei" : "Dateien"} hochladen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kategorie == 'vereindokumente' ? Colors.blue.shade700 : Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isUploadingDokument = true);
    _dokumenteService.setToken(widget.apiService.token);

    final files = result.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
    final ablaufStr = selectedAblaufDatum != null ? DateFormat('yyyy-MM-dd').format(selectedAblaufDatum!) : null;

    if (files.length == 1) {
      final dokumentName = nameController.text.trim().isEmpty ? result.files.first.name : nameController.text.trim();
      final doc = await _dokumenteService.uploadDokument(
        userId: widget.user.id,
        dokumentName: dokumentName,
        file: files.first,
        beschreibung: beschreibungController.text.trim().isEmpty ? null : beschreibungController.text.trim(),
        kategorie: kategorie,
        dokumentTyp: selectedDokumentTyp,
        ablaufDatum: ablaufStr,
      );

      if (!mounted) return;
      setState(() => _isUploadingDokument = false);

      if (doc != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dokument "${doc.dokumentName}" hochgeladen'), backgroundColor: Colors.green),
        );
        _loadDokumente();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Hochladen'), backgroundColor: Colors.red),
        );
      }
    } else {
      final docs = await _dokumenteService.uploadMultipleDokumente(
        userId: widget.user.id,
        files: files,
        dokumentName: nameController.text.trim(),
        beschreibung: beschreibungController.text.trim().isEmpty ? null : beschreibungController.text.trim(),
        kategorie: kategorie,
        dokumentTyp: selectedDokumentTyp,
        ablaufDatum: ablaufStr,
      );

      if (!mounted) return;
      setState(() => _isUploadingDokument = false);

      if (docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${docs.length} Dokumente hochgeladen'), backgroundColor: Colors.green),
        );
        _loadDokumente();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Hochladen'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteDokument(MemberDokument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Dokument löschen?'),
          ],
        ),
        content: Text('"${doc.dokumentName}" (${doc.originalFilename}) wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _dokumenteService.setToken(widget.apiService.token);
      final success = await _dokumenteService.deleteDokument(doc.id);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dokument gelöscht'), backgroundColor: Colors.green),
        );
        _loadDokumente();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Löschen'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _viewDokument(MemberDokument doc) async {
    final ext = doc.fileExtension.toLowerCase();
    final viewable = ['pdf', 'jpg', 'jpeg', 'png'];
    if (!viewable.contains(ext)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vorschau nur für PDF und Bilder verfügbar'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Datei wird geladen...'),
          ],
        ),
      ),
    );

    _dokumenteService.setToken(widget.apiService.token);
    final data = await _dokumenteService.downloadDokument(doc.id);
    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Laden der Datei'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      final bytes = base64Decode(data['data']);
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${data['filename']}';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      await FileViewerDialog.show(context, filePath, data['filename']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Anzeigen: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadDokument(MemberDokument doc) async {
    _dokumenteService.setToken(widget.apiService.token);
    final data = await _dokumenteService.downloadDokument(doc.id);
    if (!mounted) return;

    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Herunterladen'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      final bytes = base64Decode(data['data']);
      final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final filePath = '${dir.path}/${data['filename']}';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gespeichert: ${data['filename']}'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Öffnen',
            textColor: Colors.white,
            onPressed: () {
              Process.run('open', [filePath]);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern: $e'), backgroundColor: Colors.red),
      );
    }
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
      case 'odt':
        return Icons.article;
      case 'xls':
      case 'xlsx':
      case 'ods':
        return Icons.table_chart;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Colors.red.shade700;
      case 'doc':
      case 'docx':
      case 'odt':
        return Colors.blue.shade700;
      case 'xls':
      case 'xlsx':
      case 'ods':
        return Colors.green.shade700;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.purple.shade700;
      case 'txt':
        return Colors.grey.shade700;
      default:
        return Colors.blueGrey.shade700;
    }
  }

  String _formatFilesize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildDokumenteTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Sub-tabs
          Container(
            color: Colors.grey.shade100,
            child: TabBar(
              labelColor: Colors.blue.shade800,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.blue.shade800,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.groups, size: 18),
                      const SizedBox(width: 6),
                      const Text('Vereindokumente'),
                      const SizedBox(width: 4),
                      _buildDocCountBadge(_dokumente.where((d) => d.kategorie == 'vereindokumente').length),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_balance, size: 18),
                      const SizedBox(width: 6),
                      const Text('Behörde Unterlagen'),
                      const SizedBox(width: 4),
                      _buildDocCountBadge(_dokumente.where((d) => d.kategorie == 'behoerde').length),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Sub-tab content
          Expanded(
            child: TabBarView(
              children: [
                _buildDokumenteSubTab('vereindokumente'),
                _buildDokumenteSubTab('behoerde'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: count > 0 ? Colors.blue.shade100 : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: count > 0 ? Colors.blue.shade800 : Colors.grey.shade600),
      ),
    );
  }

  Widget _buildDokumenteSubTab(String kategorie) {
    final docs = _dokumente.where((d) => d.kategorie == kategorie).toList();
    final isVerein = kategorie == 'vereindokumente';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Upload button
          Row(
            children: [
              Icon(
                isVerein ? Icons.groups : Icons.account_balance,
                size: 20,
                color: isVerein ? Colors.blue.shade700 : Colors.teal.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isVerein ? 'Vereindokumente (${docs.length})' : 'Behörde Unterlagen (${docs.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              if (_isLoadingDokumente)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isUploadingDokument ? null : () => _uploadDokument(kategorie: kategorie),
                icon: _isUploadingDokument
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file, size: 16),
                label: Text(docs.length < 10 ? 'Hochladen' : 'Hochladen', style: const TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isVerein ? Colors.blue.shade700 : Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Info box
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isVerein ? Colors.blue.shade50 : Colors.teal.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isVerein ? Colors.blue.shade100 : Colors.teal.shade100),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: isVerein ? Colors.blue.shade700 : Colors.teal.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isVerein
                        ? 'Beitrittsantrag, Aufnahmebestätigung, Kündigung usw. | PDF, JPG, PNG, TXT (max. 100 MB, 10 Dateien)'
                        : 'Krankenkasse, Finanzamt usw. | Dokumente mit Ablaufdatum werden automatisch gelöscht',
                    style: TextStyle(fontSize: 10, color: isVerein ? Colors.blue.shade700 : Colors.teal.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Documents list
          if (docs.isEmpty && !_isLoadingDokumente)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.folder_off, color: Colors.grey.shade500),
                    const SizedBox(width: 12),
                    Text(isVerein ? 'Keine Vereindokumente vorhanden' : 'Keine Behörde Unterlagen vorhanden'),
                  ],
                ),
              ),
            )
          else
            ...docs.map((doc) => _buildDokumentCard(doc)),
        ],
      ),
    );
  }

  Widget _buildDokumentCard(MemberDokument doc) {
    final ext = doc.fileExtension;
    final color = _getFileColor(ext.toLowerCase());
    final isBehoerde = doc.kategorie == 'behoerde';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: doc.isExpired ? Colors.red.shade300 : (doc.isExpiringSoon ? Colors.orange.shade300 : color.withValues(alpha: 0.3)),
          width: doc.isExpired || doc.isExpiringSoon ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // File icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  Icon(_getFileIcon(ext.toLowerCase()), color: color, size: 24),
                  if (doc.isEncrypted)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Icon(Icons.lock, size: 12, color: Colors.green.shade700),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.dokumentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(ext, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                      ),
                      const SizedBox(width: 6),
                      Text(doc.filesizeFormatted, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      const SizedBox(width: 6),
                      Text(DateFormat('dd.MM.yyyy').format(doc.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      if (doc.dokumentTyp != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isBehoerde ? Colors.teal.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _dokumentTypLabel(doc.dokumentTyp!),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isBehoerde ? Colors.teal.shade700 : Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Expiry info for Behörde docs
                  if (isBehoerde && doc.ablaufDatum != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          doc.isExpired ? Icons.error : (doc.isExpiringSoon ? Icons.warning : Icons.schedule),
                          size: 13,
                          color: doc.isExpired ? Colors.red : (doc.isExpiringSoon ? Colors.orange : Colors.grey),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          doc.isExpired
                              ? 'Abgelaufen am ${DateFormat('dd.MM.yyyy').format(doc.ablaufDatum!)}'
                              : 'Gültig bis ${DateFormat('dd.MM.yyyy').format(doc.ablaufDatum!)}${doc.isExpiringSoon ? ' (${doc.daysUntilExpiry} Tage)' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: doc.isExpired ? Colors.red : (doc.isExpiringSoon ? Colors.orange.shade700 : Colors.grey.shade600),
                            fontWeight: doc.isExpired || doc.isExpiringSoon ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (doc.beschreibung != null && doc.beschreibung!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(doc.beschreibung!, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                    ),
                  Text(
                    'Von: ${doc.uploadedByName}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            // Actions
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (['pdf', 'jpg', 'jpeg', 'png'].contains(doc.fileExtension.toLowerCase()))
                  IconButton(
                    icon: Icon(Icons.visibility, color: Colors.green.shade600, size: 18),
                    tooltip: 'Vorschau',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => _viewDokument(doc),
                  ),
                IconButton(
                  icon: Icon(Icons.download, color: Colors.blue.shade600, size: 18),
                  tooltip: 'Herunterladen',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () => _downloadDokument(doc),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
                  tooltip: 'Löschen',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () => _deleteDokument(doc),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dokumentTypLabel(String typ) {
    const labels = {
      'beitrittsantrag': 'Beitrittsantrag',
      'aufnahmebestaetigung': 'Aufnahme',
      'kuendigung': 'Kündigung',
      'krankenkasse': 'Krankenkasse',
      'finanzamt': 'Finanzamt',
      'sozialversicherung': 'Sozialvers.',
      'arbeitsamt': 'Arbeitsamt',
      'sonstiges': 'Sonstiges',
    };
    return labels[typ] ?? typ;
  }

  Widget _buildStatChip(String label, int count, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.shade800),
      ),
    );
  }

  Future<void> _confirmRevokeSession(int sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Sitzung widerrufen?'),
          ],
        ),
        content: const Text(
          'Der Benutzer wird von diesem Gerät abgemeldet und muss sich neu anmelden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Widerrufen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _revokeSession(sessionId);
    }
  }

  Widget _buildMitgliedschaftTab() {
    final user = widget.user;
    final dateFormat = DateFormat('dd.MM.yyyy');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status — editable
          _mitgliedschaftRow(
            icon: Icons.circle,
            iconColor: getStatusColor(user.status),
            label: 'Status',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: getStatusColor(user.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: getStatusColor(user.status).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    getStatusText(user.status),
                    style: TextStyle(
                      color: getStatusColor(user.status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showStatusChangeDialog(),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Status ändern', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),

          // Mitgliedernummer
          _mitgliedschaftRow(
            icon: Icons.badge,
            iconColor: Colors.blue,
            label: 'Mitgliedernummer',
            child: Text(
              user.mitgliedernummer,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 24),

          // Rolle
          _mitgliedschaftRow(
            icon: Icons.admin_panel_settings,
            iconColor: getRoleColor(user.role),
            label: 'Rolle',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: getRoleColor(user.role).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                getRoleText(user.role),
                style: TextStyle(
                  color: getRoleColor(user.role),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const Divider(height: 24),

          // Registriert am (App)
          _mitgliedschaftRow(
            icon: Icons.app_registration,
            iconColor: Colors.grey,
            label: 'Registriert am',
            child: Text(
              user.createdAt != null ? dateFormat.format(user.createdAt!) : 'Unbekannt',
              style: const TextStyle(fontSize: 15),
            ),
          ),
          const Divider(height: 24),

          // Letzter Login
          _mitgliedschaftRow(
            icon: Icons.login,
            iconColor: Colors.grey,
            label: 'Letzter Login',
            child: Text(
              user.lastLogin != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(user.lastLogin!)
                  : 'Noch nie',
              style: const TextStyle(fontSize: 15),
            ),
          ),
          const Divider(height: 24),

          // Mitglied seit (auto-set on activation, editable for retroactive)
          _mitgliedschaftRow(
            icon: Icons.card_membership,
            iconColor: Colors.green,
            label: 'Mitglied seit',
            child: Row(
              children: [
                Text(
                  user.mitgliedschaftDatum != null
                      ? dateFormat.format(user.mitgliedschaftDatum!)
                      : 'Noch nicht aktiviert',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: user.mitgliedschaftDatum != null ? Colors.green.shade700 : Colors.grey,
                    fontStyle: user.mitgliedschaftDatum == null ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_calendar, size: 20),
                  tooltip: 'Datum ändern (z.B. rückwirkend)',
                  onPressed: () => _pickMitgliedschaftDatum(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ========== BEFREIUNG SECTION ==========
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isBefreit ? Colors.green.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _isBefreit ? Colors.green.shade300 : Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isBefreit ? Icons.check_circle : Icons.info_outline,
                      color: _isBefreit ? Colors.green.shade700 : Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Beitragsbefreiung',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _isBefreit ? Colors.green.shade700 : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    if (_isBefreit)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('Befreit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Aktualisieren',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: _loadBefreiungen,
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton.icon(
                      onPressed: () => _showBefreiungUploadDialog(),
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('Bescheid hochladen', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ),
                if (_isLoadingBefreiung) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                ] else if (_befreiungen.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Keine Befreiung vorhanden. Bewilligungsbescheid vom Jobcenter oder Sozialamt hochladen.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  ..._befreiungen.map((bef) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildBefreiungCard(bef),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mitgliedschaftRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required Widget child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Future<void> _showStatusChangeDialog() async {
    String selectedStatus = widget.user.status;

    final newStatus = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.swap_horiz, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  const Text('Status ändern'),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.user.name} (${widget.user.mitgliedernummer})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('Aktueller Status: ', style: TextStyle(fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: getStatusColor(widget.user.status).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            getStatusText(widget.user.status),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: getStatusColor(widget.user.status),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Neuer Status:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...allStatuses.map((s) {
                      final value = s['value'] as String;
                      final label = s['label'] as String;
                      final desc = s['description'] as String;
                      final isSelected = selectedStatus == value;
                      final color = getStatusColor(value);
                      return InkWell(
                        onTap: () => setDialogState(() => selectedStatus = value),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? color.withValues(alpha: 0.1) : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected ? Border.all(color: color.withValues(alpha: 0.4)) : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                size: 20,
                                color: isSelected ? color : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.circle, size: 10, color: color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      desc,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton.icon(
                  onPressed: selectedStatus == widget.user.status
                      ? null
                      : () => Navigator.pop(ctx, selectedStatus),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Speichern'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (newStatus == null || newStatus == widget.user.status) return;

    try {
      final result = await widget.apiService.updateUserStatus(widget.user.id, newStatus);
      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Status geändert: ${getStatusText(newStatus)}'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onUpdated();
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickMitgliedschaftDatum() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.user.mitgliedschaftDatum ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('de', 'DE'),
    );

    if (picked == null || !mounted) return;

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(picked);
      final result = await widget.apiService.updateUser(
        userId: widget.user.id,
        mitgliedschaftDatum: dateStr,
      );

      if (result['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mitgliedschaftsdatum gespeichert'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onUpdated();
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Fehler'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unbekannt';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day.$month.$year $hour:$minute';
  }

  // ============= VERIFIZIERUNG =============

  Future<void> _loadVerifizierung() async {
    setState(() => _isLoadingVerifizierung = true);
    try {
      final result = await widget.apiService.getVerifizierung(widget.user.id);
      if (mounted && result['success'] == true) {
        setState(() {
          _verifizierungStages = List<Map<String, dynamic>>.from(result['stages'] ?? []);
          _verifizierungFinanzielleSituation = result['finanzielle_situation'] as String?;
          final acceptances = result['document_acceptances'] as Map<String, dynamic>?;
          _verifizierungAcceptances = {
            'satzung': acceptances?['satzung'] as String?,
            'datenschutz': acceptances?['datenschutz'] as String?,
            'widerrufsbelehrung': acceptances?['widerrufsbelehrung'] as String?,
          };
          _isLoadingVerifizierung = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingVerifizierung = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingVerifizierung = false);
    }
  }

  Future<void> _updateVerifizierungStatus(int stufe, String status, {String? notiz}) async {
    setState(() => _isUpdatingVerifizierung = true);
    try {
      final result = await widget.apiService.updateVerifizierung(
        userId: widget.user.id,
        stufe: stufe,
        status: status,
        notiz: notiz,
      );
      if (mounted) {
        setState(() => _isUpdatingVerifizierung = false);
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(status == 'geprueft' ? 'Stufe $stufe geprüft' : status == 'abgelehnt' ? 'Stufe $stufe abgelehnt' : 'Stufe $stufe zurückgesetzt'),
              backgroundColor: status == 'geprueft' ? Colors.green : status == 'abgelehnt' ? Colors.red : Colors.grey,
            ),
          );
          _loadVerifizierung();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdatingVerifizierung = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _stufeName(int stufe) {
    switch (stufe) {
      case 1: return 'Persönliche Daten';
      case 2: return 'Mitgliedsart';
      case 3: return 'Finanzielle Situation';
      case 4: return 'Zahlungsmethode';
      case 5: return 'Mitgliedschaftsbeginn';
      case 6: return 'Satzung';
      case 7: return 'Datenschutz';
      case 8: return 'Widerrufsbelehrung';
      default: return 'Stufe $stufe';
    }
  }

  IconData _stufeIcon(int stufe) {
    switch (stufe) {
      case 1: return Icons.person;
      case 2: return Icons.groups;
      case 3: return Icons.account_balance_wallet;
      case 4: return Icons.payment;
      case 5: return Icons.calendar_today;
      case 6: return Icons.gavel;
      case 7: return Icons.privacy_tip;
      case 8: return Icons.assignment_return;
      default: return Icons.check_circle;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'geprueft': return Colors.green;
      case 'ausgefuellt': return Colors.orange;
      case 'abgelehnt': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'geprueft': return 'Geprüft';
      case 'ausgefuellt': return 'Ausgefüllt';
      case 'abgelehnt': return 'Abgelehnt';
      default: return 'Offen';
    }
  }

  Widget _buildVerifizierungTab() {
    if (_isLoadingVerifizierung) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_verifizierungStages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Keine Verifizierungsdaten geladen',
              style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadVerifizierung,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut laden'),
            ),
          ],
        ),
      );
    }

    final geprueftCount = _verifizierungStages.where((s) => s['status'] == 'geprueft').length;
    final totalCount = _verifizierungStages.length;
    final allDone = totalCount > 0 && geprueftCount == totalCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: allDone ? Colors.green.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: allDone ? Colors.green.shade200 : Colors.blue.shade200,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      allDone ? Icons.check_circle : Icons.pending,
                      color: allDone ? Colors.green.shade700 : Colors.blue.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$geprueftCount/$totalCount Stufen geprüft',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: allDone ? Colors.green.shade700 : Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: totalCount > 0 ? geprueftCount / totalCount : 0,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      allDone ? Colors.green : Colors.blue,
                    ),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stages
          ..._verifizierungStages.map((stage) {
            final stufe = stage['stufe'] as int;
            final status = stage['status'] as String;
            return _buildStufeCard(stufe, status, stage);
          }),
        ],
      ),
    );
  }

  Widget _buildStufeCard(int stufe, String status, Map<String, dynamic> stage) {
    final color = _statusColor(status);
    final user = widget.user;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_stufeIcon(stufe), color: color, size: 24),
        ),
        title: Row(
          children: [
            Text(
              'Stufe $stufe: ${_stufeName(stufe)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _statusText(status),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
        subtitle: stage['geprueft_am'] != null
            ? Text(
                'Geprüft am ${_formatDate(stage['geprueft_am'])} von ${stage['geprueft_von_name'] ?? 'Unbekannt'}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stage-specific content
                if (stufe == 1) _buildStufe1Content(user),
                if (stufe == 2) _buildStufe2Content(user),
                if (stufe == 3) _buildStufe3Content(user),
                if (stufe == 4) _buildStufe4Content(user),
                if (stufe == 5) _buildStufe5MitgliedschaftContent(),
                if (stufe == 6) _buildStufe6Content(),
                if (stufe == 7) _buildStufe7Content(),
                if (stufe == 8) _buildStufe8Content(),

                // Notiz
                if (stage['notiz'] != null && stage['notiz'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.yellow.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.yellow.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.note, size: 16, color: Colors.yellow.shade800),
                        const SizedBox(width: 8),
                        Expanded(child: Text(stage['notiz'], style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status != 'offen')
                      TextButton.icon(
                        onPressed: _isUpdatingVerifizierung ? null : () => _updateVerifizierungStatus(stufe, 'offen'),
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Zurücksetzen'),
                        style: TextButton.styleFrom(foregroundColor: Colors.grey),
                      ),
                    const SizedBox(width: 8),
                    if (status != 'abgelehnt')
                      OutlinedButton.icon(
                        onPressed: _isUpdatingVerifizierung ? null : () => _showAblehnungDialog(stufe),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Ablehnen'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    const SizedBox(width: 8),
                    if (status != 'geprueft')
                      ElevatedButton.icon(
                        onPressed: _isUpdatingVerifizierung ? null : () => _updateVerifizierungStatus(stufe, 'geprueft'),
                        icon: _isUpdatingVerifizierung
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 18),
                        label: const Text('Geprüft'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStufe1Content(User user) {
    return Column(
      children: [
        _stufe1EditableRow('Vorname', _stufe1VornameController),
        _stufe1EditableRow('Nachname', _stufe1NachnameController),
        _stufe1DateRow('Geburtsdatum', _stufe1GeburtsdatumController),
        if (_stufe1GeburtsdatumController.text.isNotEmpty) _buildAlterRow(_stufe1GeburtsdatumController.text),
        _stufe1EditableRow('Geburtsort', _stufe1GeburtsortController),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                _stufe1Geschlecht.isNotEmpty ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 16,
                color: _stufe1Geschlecht.isNotEmpty ? Colors.green : Colors.red.shade300,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: Text('Geschlecht', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _stufe1Geschlecht,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'M', child: Text('M – männlich', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'W', child: Text('W – weiblich', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'D', child: Text('D – divers', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _stufe1Geschlecht = v ?? 'M'),
                ),
              ),
            ],
          ),
        ),
        // Familienstand
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                _stufe1Familienstand.isNotEmpty ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 16,
                color: _stufe1Familienstand.isNotEmpty ? Colors.green : Colors.red.shade300,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: Text('Familienstand', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _stufe1Familienstand.isEmpty ? null : _stufe1Familienstand,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    hintText: 'Auswahlen...',
                    hintStyle: const TextStyle(fontSize: 13),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ledig', child: Text('Ledig', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'verheiratet', child: Text('Verheiratet', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'eingetragene_lebenspartnerschaft', child: Text('Eingetragene Lebenspartnerschaft', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'geschieden', child: Text('Geschieden', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'verwitwet', child: Text('Verwitwet', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'getrennt_lebend', child: Text('Getrennt lebend', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'eheaehnliche_gemeinschaft', child: Text('Eheahnliche Gemeinschaft', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'unbekannt', child: Text('Unbekannt / Keine Angabe', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) => setState(() => _stufe1Familienstand = v ?? ''),
                ),
              ),
            ],
          ),
        ),
        // Staatsangehörigkeit
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                _stufe1Staatsangehoerigkeit.isNotEmpty ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 16,
                color: _stufe1Staatsangehoerigkeit.isNotEmpty ? Colors.green : Colors.red.shade300,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: Text('Staatsangehörigkeit', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
              Expanded(
                child: _staatsangehoerigkeitenListe.isEmpty
                    ? TextField(
                        controller: TextEditingController(text: _stufe1Staatsangehoerigkeit),
                        onChanged: (v) => _stufe1Staatsangehoerigkeit = v,
                        decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6))),
                        style: const TextStyle(fontSize: 13),
                      )
                    : Autocomplete<Map<String, dynamic>>(
                        initialValue: TextEditingValue(text: _stufe1Staatsangehoerigkeit),
                        optionsBuilder: (textEditingValue) {
                          if (textEditingValue.text.isEmpty) return _staatsangehoerigkeitenListe;
                          final q = textEditingValue.text.toLowerCase();
                          return _staatsangehoerigkeitenListe.where((s) =>
                            (s['bezeichnung'] ?? '').toString().toLowerCase().contains(q) ||
                            (s['land'] ?? '').toString().toLowerCase().contains(q));
                        },
                        displayStringForOption: (s) => s['bezeichnung'] ?? '',
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(alignment: Alignment.topLeft, child: Material(elevation: 4, borderRadius: BorderRadius.circular(8), child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 200, maxWidth: 350), child: ListView.builder(padding: EdgeInsets.zero, shrinkWrap: true, itemCount: options.length, itemBuilder: (ctx, i) {
                            final s = options.elementAt(i);
                            return ListTile(dense: true, title: Text(s['bezeichnung'] ?? '', style: const TextStyle(fontSize: 13)), subtitle: Text(s['land'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)), onTap: () => onSelected(s));
                          }))));
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(controller: controller, focusNode: focusNode, decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), hintText: 'Tippen...', hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400)), style: const TextStyle(fontSize: 13));
                        },
                        onSelected: (s) => setState(() => _stufe1Staatsangehoerigkeit = s['bezeichnung'] ?? ''),
                      ),
              ),
            ],
          ),
        ),
        _stufe1EditableRow('Strasse', _stufe1StrasseController),
        _stufe1EditableRow('Hausnummer', _stufe1HausnummerController),
        _stufe1EditableRow('PLZ', _stufe1PlzController),
        _stufe1EditableRow('Ort', _stufe1OrtController),
        _stufe1EditableRow('Telefonnummer', _stufe1TelefonController),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _isSavingStufe1 ? null : _saveStufe1Data,
            icon: _isSavingStufe1
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 18),
            label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stufe1DateRow(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            controller.text.trim().isNotEmpty ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 16,
            color: controller.text.trim().isNotEmpty ? Colors.green : Colors.red.shade300,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: controller,
                readOnly: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'TT.MM.JJJJ',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  suffixIcon: const Icon(Icons.calendar_today, size: 16),
                ),
                onTap: () async {
                  DateTime? initial;
                  try {
                    final parts = controller.text.split('.');
                    if (parts.length == 3) {
                      initial = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                    }
                  } catch (_) {}
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial ?? DateTime(1990, 1, 1),
                    firstDate: DateTime(1920),
                    lastDate: DateTime.now(),
                    locale: const Locale('de', 'DE'),
                  );
                  if (picked != null) {
                    controller.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                    setState(() {});
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlterRow(String geburtsdatumStr) {
    try {
      final parts = geburtsdatumStr.split('.');
      if (parts.length != 3) return const SizedBox.shrink();
      final birthDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      final now = DateTime.now();
      int age = now.year - birthDate.year;
      if (now.month < birthDate.month || (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
      // Days until next birthday
      var nextBirthday = DateTime(now.year, birthDate.month, birthDate.day);
      if (nextBirthday.isBefore(now) && !(nextBirthday.day == now.day && nextBirthday.month == now.month)) {
        nextBirthday = DateTime(now.year + 1, birthDate.month, birthDate.day);
      }
      final daysLeft = nextBirthday.difference(now).inDays;
      final isToday = daysLeft == 0;

      return Padding(
        padding: const EdgeInsets.only(left: 24, bottom: 4),
        child: Row(children: [
          Icon(Icons.cake, size: 16, color: isToday ? Colors.deepOrange : Colors.grey.shade500),
          const SizedBox(width: 6),
          Text('$age Jahre', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(width: 12),
          if (isToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(12)),
              child: const Text('🎂 Heute Geburtstag!', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
            )
          else
            Text('🎂 noch $daysLeft Tage', style: TextStyle(fontSize: 11, color: daysLeft <= 30 ? Colors.orange.shade700 : Colors.grey.shade500)),
        ]),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _stufe1EditableRow(String label, TextEditingController controller, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            controller.text.trim().isNotEmpty ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 16,
            color: controller.text.trim().isNotEmpty ? Colors.green : Colors.red.shade300,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: controller,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: hint ?? label,
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStufe2Content(User user) {
    final mitgliedsartLabels = {
      'ordentliches_mitglied': 'Ordentliches Mitglied',
      'foerdermitglied': 'Fördermitglied',
      'ehrenmitglied': 'Ehrenmitglied',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (user.mitgliedsart != null && user.mitgliedsart!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.groups, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  mitgliedsartLabels[user.mitgliedsart] ?? user.mitgliedsart!,
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Das Mitglied hat noch keine Mitgliedsart gewählt.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Stufe 3: Finanzielle Situation
  Widget _buildStufe3Content(User user) {
    final finanzLabels = {
      'buergergeld': 'Bürgergeld',
      'sozialamt': 'Sozialamt',
      'nein': 'Keine Sozialleistungen',
    };

    // Get finanzielle_situation from loaded verifizierung data
    final finSituation = _verifizierungFinanzielleSituation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (finSituation != null && finSituation.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: finSituation == 'nein' ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  finSituation == 'nein' ? Icons.check_circle : Icons.info_outline,
                  color: finSituation == 'nein' ? Colors.green.shade700 : Colors.orange.shade700,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  finanzLabels[finSituation] ?? finSituation,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: finSituation == 'nein' ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Das Mitglied hat noch keine Angabe zur finanziellen Situation gemacht.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Stufe 4: Zahlungsmethode
  Widget _buildStufe4Content(User user) {
    final zahlungsLabels = {
      'ueberweisung': 'Überweisung',
      'sepa_lastschrift': 'SEPA-Lastschrift',
      'dauerauftrag': 'Dauerauftrag',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (user.zahlungsmethode != null && user.zahlungsmethode!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.payment, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  zahlungsLabels[user.zahlungsmethode] ?? user.zahlungsmethode!,
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700),
                ),
              ],
            ),
          )
        else ...[
          Text('Keine Zahlungsmethode gewählt.', style: TextStyle(color: Colors.red.shade400, fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Zahlungsmethode auswählen',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: zahlungsLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (value) async {
              if (value == null) return;
              await widget.apiService.updateUser(userId: widget.user.id, zahlungsmethode: value);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Zahlungsmethode gespeichert'), backgroundColor: Colors.green),
                );
                widget.onUpdated();
              }
            },
          ),
        ],
      ],
    );
  }

  // Stufe 5: Mitgliedschaftsbeginn
  Widget _buildStufe5MitgliedschaftContent() {
    final finSituation = _verifizierungFinanzielleSituation;
    final isBeitragsfrei = finSituation == 'buergergeld' || finSituation == 'sozialamt';

    // Find mitgliedschaftsbeginn data from stages or user data
    // The data comes from the API response
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Das Mitglied hat gewählt, ab wann die Mitgliedschaft beginnen soll.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        if (isBeitragsfrei) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Beitragsbefreit (Ermäßigung) – 0 € retroaktiv',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Stufe 6: Satzung
  Widget _buildStufe6Content() {
    return _buildRedirectStufe(
      title: 'Satzung',
      description: 'Die Satzung des Vereins muss vom Mitglied gelesen und akzeptiert werden.',
      url: 'https://icd360sev.icd360s.de/satzung',
      buttonLabel: 'Satzung öffnen',
      icon: Icons.gavel,
      acceptanceDate: _verifizierungAcceptances['satzung'],
    );
  }

  // Stufe 7: Datenschutz
  Widget _buildStufe7Content() {
    return _buildRedirectStufe(
      title: 'Datenschutz',
      description: 'Die Datenschutzerklärung muss vom Mitglied gelesen und akzeptiert werden.',
      url: 'https://icd360sev.icd360s.de/datenschutz',
      buttonLabel: 'Datenschutz öffnen',
      icon: Icons.privacy_tip,
      acceptanceDate: _verifizierungAcceptances['datenschutz'],
    );
  }

  // Stufe 8: Widerrufsbelehrung
  Widget _buildStufe8Content() {
    return _buildRedirectStufe(
      title: 'Widerrufsbelehrung',
      description: 'Die Widerrufsbelehrung muss vom Mitglied gelesen und akzeptiert werden.',
      url: 'https://icd360sev.icd360s.de/widerrufsbelehrung',
      buttonLabel: 'Widerrufsbelehrung öffnen',
      icon: Icons.assignment_return,
      acceptanceDate: _verifizierungAcceptances['widerrufsbelehrung'],
    );
  }

  Widget _buildRedirectStufe({
    required String title,
    required String description,
    required String url,
    required String buttonLabel,
    required IconData icon,
    String? acceptanceDate,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (acceptanceDate != null && acceptanceDate.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bei Registrierung akzeptiert am ${_formatDate(acceptanceDate)}',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          )
        else
          Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          icon: Icon(icon, size: 18),
          label: Text(buttonLabel),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.blue.shade700),
        ),
      ],
    );
  }

  Future<void> _showAblehnungDialog(int stufe) async {
    final notizController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cancel, color: Colors.red),
            const SizedBox(width: 8),
            Text('Stufe $stufe ablehnen'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: notizController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Grund der Ablehnung (optional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.close),
            label: const Text('Ablehnen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final notiz = notizController.text.trim().isEmpty ? null : notizController.text.trim();
      _updateVerifizierungStatus(stufe, 'abgelehnt', notiz: notiz);
    }
  }

  // ========== BEFREIUNG ==========

  Future<void> _loadBefreiungen() async {
    setState(() => _isLoadingBefreiung = true);
    try {
      final result = await widget.apiService.getBefreiungen(widget.user.id);
      if (mounted && result['success'] == true) {
        setState(() {
          _befreiungen = List<Map<String, dynamic>>.from(result['befreiungen'] ?? []);
          _isBefreit = result['is_befreit'] == true;
          _isLoadingBefreiung = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingBefreiung = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingBefreiung = false);
    }
  }

  Widget _buildBefreiungCard(Map<String, dynamic> bef) {
    final status = bef['status'] as String? ?? 'eingereicht';
    final behoerde = bef['behoerde'] as String? ?? '';
    final gueltigVon = bef['gueltig_von'] as String?;
    final gueltigBis = bef['gueltig_bis'] as String?;
    final bescheidDatum = bef['bescheid_datum'] as String?;
    final notiz = bef['notiz'] as String?;
    final geprueftAm = bef['geprueft_am'] as String?;
    final geprueftVonName = bef['geprueft_von_name'] as String?;
    final originalFilename = bef['original_filename'] as String?;
    final filesize = bef['filesize'];
    final id = bef['id'] is int ? bef['id'] as int : int.tryParse(bef['id'].toString()) ?? 0;

    Color statusColor;
    IconData statusIcon;
    String statusText;
    switch (status) {
      case 'genehmigt':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Genehmigt';
        break;
      case 'abgelehnt':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Abgelehnt';
        break;
      case 'abgelaufen':
        statusColor = Colors.orange;
        statusIcon = Icons.timer_off;
        statusText = 'Abgelaufen';
        break;
      default:
        statusColor = Colors.blue;
        statusIcon = Icons.hourglass_top;
        statusText = 'Eingereicht';
    }

    final behoerdeLabel = behoerde == 'jobcenter' ? 'Jobcenter' : 'Sozialamt';
    final behoerdeColor = behoerde == 'jobcenter' ? Colors.indigo : Colors.teal;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: statusColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Behörde + Status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: behoerdeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: behoerdeColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance, size: 14, color: behoerdeColor),
                      const SizedBox(width: 4),
                      Text(behoerdeLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: behoerdeColor)),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Dates
            Row(
              children: [
                Expanded(
                  child: _befreiungInfoRow(Icons.date_range, 'Gültig von', gueltigVon != null ? _formatDate(gueltigVon) : '-'),
                ),
                Expanded(
                  child: _befreiungInfoRow(Icons.event, 'Gültig bis', gueltigBis != null ? _formatDate(gueltigBis) : '-'),
                ),
              ],
            ),
            if (bescheidDatum != null) ...[
              const SizedBox(height: 4),
              _befreiungInfoRow(Icons.description, 'Bescheid vom', _formatDate(bescheidDatum)),
            ],

            // File info
            if (originalFilename != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      originalFilename.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image,
                      size: 18,
                      color: originalFilename.toLowerCase().endsWith('.pdf') ? Colors.red : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(originalFilename, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          if (filesize != null)
                            Text(_formatFileSize(filesize), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.visibility, size: 18, color: Colors.green.shade600),
                      tooltip: 'Vorschau',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: () => _viewBefreiungDokument(id, originalFilename),
                    ),
                  ],
                ),
              ),
            ],

            // Notiz
            if (notiz != null && notiz.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.yellow.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.yellow.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.note, size: 14, color: Colors.yellow.shade800),
                    const SizedBox(width: 6),
                    Expanded(child: Text(notiz, style: const TextStyle(fontSize: 11))),
                  ],
                ),
              ),
            ],

            // Geprüft info
            if (geprueftAm != null) ...[
              const SizedBox(height: 6),
              Text(
                'Geprüft am ${_formatDate(geprueftAm)} von ${geprueftVonName ?? 'Unbekannt'}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ],

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Delete
                TextButton.icon(
                  onPressed: () => _deleteBefreiung(id),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Löschen', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
                ),
                const Spacer(),
                if (status != 'genehmigt' && status != 'abgelaufen')
                  TextButton.icon(
                    onPressed: () => _showBefreiungAblehnungDialog(id),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Ablehnen', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                if (status != 'genehmigt' && status != 'abgelaufen') ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _updateBefreiungStatus(id, 'genehmigt'),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Genehmigen', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
                if (status == 'abgelehnt' || status == 'abgelaufen')
                  TextButton.icon(
                    onPressed: () => _updateBefreiungStatus(id, 'eingereicht'),
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Zurücksetzen', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _befreiungInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  String _formatFileSize(dynamic size) {
    final bytes = size is int ? size : int.tryParse(size.toString()) ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _viewBefreiungDokument(int id, String filename) async {
    final ext = filename.toLowerCase().split('.').last;
    final viewable = ['pdf', 'jpg', 'jpeg', 'png'];
    if (!viewable.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vorschau nur für PDF und Bilder verfügbar'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await widget.apiService.downloadBefreiung(id);
      if (!mounted) return;
      Navigator.pop(context); // close loading

      if (result['success'] == true) {
        final bytes = base64Decode(result['data']);
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/${result['filename']}';
        await File(filePath).writeAsBytes(bytes);
        if (mounted) {
          await FileViewerDialog.show(context, filePath, result['filename']);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler beim Download'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateBefreiungStatus(int id, String status, {String? notiz}) async {
    try {
      final result = await widget.apiService.updateBefreiung(id: id, status: status, notiz: notiz);
      if (mounted) {
        if (result['success'] == true) {
          final labels = {'genehmigt': 'Befreiung genehmigt', 'abgelehnt': 'Befreiung abgelehnt', 'eingereicht': 'Status zurückgesetzt'};
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(labels[status] ?? 'Status aktualisiert'),
              backgroundColor: status == 'genehmigt' ? Colors.green : status == 'abgelehnt' ? Colors.red : Colors.grey,
            ),
          );
          _loadBefreiungen();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteBefreiung(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Befreiung löschen'),
          ],
        ),
        content: const Text('Soll diese Befreiung mit dem Dokument endgültig gelöscht werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete),
            label: const Text('Löschen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final result = await widget.apiService.deleteBefreiung(id);
        if (mounted) {
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Befreiung gelöscht'), backgroundColor: Colors.green),
            );
            _loadBefreiungen();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showBefreiungAblehnungDialog(int id) async {
    final notizController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red),
            SizedBox(width: 8),
            Text('Befreiung ablehnen'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: notizController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Grund der Ablehnung (optional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.close),
            label: const Text('Ablehnen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final notiz = notizController.text.trim().isEmpty ? null : notizController.text.trim();
      _updateBefreiungStatus(id, 'abgelehnt', notiz: notiz);
    }
  }

  Future<void> _showBefreiungUploadDialog() async {
    String selectedBehoerde = 'jobcenter';
    DateTime? bescheidDatum;
    DateTime? gueltigVon;
    DateTime? gueltigBis;
    String? selectedFilePath;
    String? selectedFileName;
    final notizController = TextEditingController();
    final dateFormat = DateFormat('dd.MM.yyyy');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.upload_file, color: Colors.teal),
              SizedBox(width: 8),
              Text('Bewilligungsbescheid'),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Behörde
                  const Text('Behörde *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBehoerde,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'jobcenter', child: Text('Jobcenter')),
                      DropdownMenuItem(value: 'sozialamt', child: Text('Sozialamt')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedBehoerde = val ?? 'jobcenter'),
                  ),
                  const SizedBox(height: 12),

                  // Bescheid Datum
                  const Text('Bescheid-Datum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: bescheidDatum ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        locale: const Locale('de'),
                      );
                      if (picked != null) setDialogState(() => bescheidDatum = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(bescheidDatum != null ? dateFormat.format(bescheidDatum!) : 'Datum wählen...')),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Gültig von
                  const Text('Gültig von *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: gueltigVon ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        locale: const Locale('de'),
                      );
                      if (picked != null) setDialogState(() => gueltigVon = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: gueltigVon == null ? Colors.red.shade300 : Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(gueltigVon != null ? dateFormat.format(gueltigVon!) : 'Startdatum wählen... *')),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Gültig bis
                  const Text('Gültig bis *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: gueltigBis ?? (gueltigVon != null ? gueltigVon!.add(const Duration(days: 365)) : DateTime.now().add(const Duration(days: 365))),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                        locale: const Locale('de'),
                      );
                      if (picked != null) setDialogState(() => gueltigBis = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: gueltigBis == null ? Colors.red.shade300 : Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(gueltigBis != null ? dateFormat.format(gueltigBis!) : 'Enddatum wählen... *')),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // File picker
                  const Text('Bewilligungsbescheid *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final result = await FilePickerHelper.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                        dialogTitle: 'Bewilligungsbescheid auswählen',
                      );
                      if (result != null && result.files.single.path != null) {
                        setDialogState(() {
                          selectedFilePath = result.files.single.path;
                          selectedFileName = result.files.single.name;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selectedFilePath == null ? Colors.red.shade300 : Colors.green.shade400,
                          style: selectedFilePath == null ? BorderStyle.solid : BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: selectedFilePath != null ? Colors.green.shade50 : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selectedFilePath != null ? Icons.check_circle : Icons.attach_file,
                            size: 18,
                            color: selectedFilePath != null ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedFileName ?? 'Datei auswählen (PDF, JPG, PNG)...',
                              style: TextStyle(
                                fontSize: 13,
                                color: selectedFilePath != null ? Colors.green.shade700 : Colors.grey.shade600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Notiz
                  const Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: notizController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Optionale Anmerkung...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              onPressed: (gueltigVon == null || gueltigBis == null || selectedFilePath == null)
                  ? null
                  : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.upload),
              label: const Text('Hochladen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && gueltigVon != null && gueltigBis != null && selectedFilePath != null) {
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        );
      }

      try {
        final result = await widget.apiService.uploadBefreiung(
          userId: widget.user.id,
          behoerde: selectedBehoerde,
          gueltigVon: DateFormat('yyyy-MM-dd').format(gueltigVon!),
          gueltigBis: DateFormat('yyyy-MM-dd').format(gueltigBis!),
          bescheidDatum: bescheidDatum != null ? DateFormat('yyyy-MM-dd').format(bescheidDatum!) : null,
          notiz: notizController.text.trim().isEmpty ? null : notizController.text.trim(),
          filePath: selectedFilePath!,
          fileName: selectedFileName!,
        );

        if (mounted) {
          Navigator.pop(context); // close loading
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bewilligungsbescheid hochgeladen'), backgroundColor: Colors.green),
            );
            _loadBefreiungen();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result['message'] ?? 'Fehler beim Hochladen'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ERMÄSSIGUNG TAB
  // ══════════════════════════════════════════════════════════════

  static const Map<String, String> _antragTypLabels = {
    'arbeitslosengeld': 'Arbeitslosengeld',
    'buergergeld': 'Bürgergeld',
    'sozialhilfe': 'Sozialhilfe',
    'grundsicherung': 'Grundsicherung',
    'wohngeld': 'Wohngeld',
    'bafog': 'BAföG',
    'ausbildungsbeihilfe': 'Ausbildungsbeihilfe',
    'kinderzuschlag': 'Kinderzuschlag',
    'rente': 'Rente',
    'sonstiges': 'Sonstiges',
  };

  static const Map<String, Color> _antragTypColors = {
    'arbeitslosengeld': Colors.indigo,
    'buergergeld': Colors.teal,
    'sozialhilfe': Colors.purple,
    'grundsicherung': Colors.brown,
    'wohngeld': Colors.cyan,
    'bafog': Colors.deepOrange,
    'ausbildungsbeihilfe': Colors.pink,
    'kinderzuschlag': Colors.green,
    'rente': Colors.blueGrey,
    'sonstiges': Colors.grey,
  };

  Future<void> _loadErmaessigungen() async {
    setState(() => _isLoadingErmaessigung = true);
    try {
      final result = await widget.apiService.getErmaessigungsantraege(userId: widget.user.id);
      if (mounted && result['success'] == true) {
        setState(() {
          _ermaessigungen = List<Map<String, dynamic>>.from(result['antraege'] ?? []);
          _isLoadingErmaessigung = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingErmaessigung = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingErmaessigung = false);
    }
  }

  Widget _buildErmaessigungTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.deepPurple.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.discount, color: Colors.deepPurple.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ermäßigungsanträge',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.deepPurple.shade700,
                        ),
                      ),
                    ),
                    if (_ermaessigungen.where((a) => a['status'] == 'eingereicht').isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_ermaessigungen.where((a) => a['status'] == 'eingereicht').length} offen',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Aktualisieren',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: _loadErmaessigungen,
                    ),
                  ],
                ),
                if (_isLoadingErmaessigung) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                ] else if (_ermaessigungen.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Keine Ermäßigungsanträge vorhanden.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  ..._ermaessigungen.map((antrag) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildErmaessigungCard(antrag),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErmaessigungCard(Map<String, dynamic> antrag) {
    final status = antrag['status'] as String? ?? 'eingereicht';
    final antragTyp = antrag['antrag_typ'] as String? ?? 'sonstiges';
    final gueltigVon = antrag['gueltig_von'] as String?;
    final gueltigBis = antrag['gueltig_bis'] as String?;
    final eingereichtAm = antrag['eingereicht_am'] as String?;
    final notiz = antrag['notiz'] as String?;
    final ablehnungsgrund = antrag['ablehnungsgrund'] as String?;
    final geprueftAm = antrag['geprueft_am'] as String?;
    final geprueftVonName = antrag['geprueft_von_name'] as String?;
    final originalFilename = antrag['original_filename'] as String?;
    final filesize = antrag['filesize'];
    final tageOffen = antrag['tage_offen'] is int ? antrag['tage_offen'] as int : int.tryParse(antrag['tage_offen']?.toString() ?? '0') ?? 0;
    final id = antrag['id'] is int ? antrag['id'] as int : int.tryParse(antrag['id'].toString()) ?? 0;

    // Checklist state
    final checkDokument = antrag['check_dokument_lesbar'] == true || antrag['check_dokument_lesbar'] == 1;
    final checkLeistungsart = antrag['check_leistungsart_erkennbar'] == true || antrag['check_leistungsart_erkennbar'] == 1;
    final checkAktuell = antrag['check_aktuell_12monate'] == true || antrag['check_aktuell_12monate'] == 1;
    final alleGeprueft = checkDokument && checkLeistungsart && checkAktuell;

    Color statusColor;
    IconData statusIcon;
    String statusText;
    switch (status) {
      case 'genehmigt':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Genehmigt';
        break;
      case 'abgelehnt':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Abgelehnt';
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top;
        statusText = 'Eingereicht';
    }

    final typLabel = _antragTypLabels[antragTyp] ?? antragTyp;
    final typColor = _antragTypColors[antragTyp] ?? Colors.grey;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: statusColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Leistungsart + Status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: typColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: typColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description, size: 14, color: typColor),
                      const SizedBox(width: 4),
                      Text(typLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: typColor)),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Dates & tage offen
            Row(
              children: [
                if (eingereichtAm != null)
                  Expanded(
                    child: _befreiungInfoRow(Icons.upload, 'Eingereicht', _formatDate(eingereichtAm)),
                  ),
                if (status == 'eingereicht')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tageOffen >= 12 ? Colors.red.shade50 : tageOffen >= 7 ? Colors.orange.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$tageOffen Tage offen',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: tageOffen >= 12 ? Colors.red : tageOffen >= 7 ? Colors.orange.shade800 : Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            if (gueltigVon != null || gueltigBis != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  if (gueltigVon != null)
                    Expanded(child: _befreiungInfoRow(Icons.date_range, 'Gültig von', _formatDate(gueltigVon))),
                  if (gueltigBis != null)
                    Expanded(child: _befreiungInfoRow(Icons.event, 'Gültig bis', _formatDate(gueltigBis))),
                ],
              ),
            ],

            // File info
            if (originalFilename != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      originalFilename.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image,
                      size: 18,
                      color: originalFilename.toLowerCase().endsWith('.pdf') ? Colors.red : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(originalFilename, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          if (filesize != null)
                            Text(_formatFileSize(filesize), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.visibility, size: 18, color: Colors.green.shade600),
                      tooltip: 'Vorschau',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: () => _viewErmaessigungDokument(id, originalFilename),
                    ),
                  ],
                ),
              ),
            ],

            // Checklist (only for eingereicht status)
            if (status == 'eingereicht') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Prüfung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                    const SizedBox(height: 4),
                    _buildCheckItem('Dokument lesbar', checkDokument, (val) {
                      _updateErmaessigungCheck(id, checkDokumentLesbar: val);
                    }),
                    _buildCheckItem('Leistungsart erkennbar', checkLeistungsart, (val) {
                      _updateErmaessigungCheck(id, checkLeistungsartErkennbar: val);
                    }),
                    _buildCheckItem('Aktuell (innerhalb 12 Monate)', checkAktuell, (val) {
                      _updateErmaessigungCheck(id, checkAktuell12Monate: val);
                    }),
                  ],
                ),
              ),
            ],

            // Show checklist status for processed items
            if (status != 'eingereicht') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(checkDokument ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: checkDokument ? Colors.green : Colors.grey),
                  const SizedBox(width: 4),
                  Text('Lesbar', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  Icon(checkLeistungsart ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: checkLeistungsart ? Colors.green : Colors.grey),
                  const SizedBox(width: 4),
                  Text('Leistungsart', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  Icon(checkAktuell ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: checkAktuell ? Colors.green : Colors.grey),
                  const SizedBox(width: 4),
                  Text('Aktuell', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ],

            // Ablehnungsgrund
            if (ablehnungsgrund != null && ablehnungsgrund.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ablehnungsgrund:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                          const SizedBox(height: 2),
                          Text(ablehnungsgrund, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Notiz
            if (notiz != null && notiz.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.yellow.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.yellow.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.note, size: 14, color: Colors.yellow.shade800),
                    const SizedBox(width: 6),
                    Expanded(child: Text(notiz, style: const TextStyle(fontSize: 11))),
                  ],
                ),
              ),
            ],

            // Geprüft info
            if (geprueftAm != null) ...[
              const SizedBox(height: 6),
              Text(
                'Geprüft am ${_formatDate(geprueftAm)} von ${geprueftVonName ?? 'Unbekannt'}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ],

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Delete
                TextButton.icon(
                  onPressed: () => _deleteErmaessigung(id),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Löschen', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
                ),
                const Spacer(),
                if (status == 'eingereicht') ...[
                  TextButton.icon(
                    onPressed: () => _showErmaessigungAblehnungDialog(id),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Ablehnen', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: alleGeprueft ? () => _updateErmaessigungStatus(id, 'genehmigt') : null,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Genehmigen', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
                if (status == 'abgelehnt')
                  TextButton.icon(
                    onPressed: () => _updateErmaessigungStatus(id, 'eingereicht'),
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Zurücksetzen', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckItem(String label, bool checked, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: checked ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 12, color: checked ? Colors.green.shade700 : Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Future<void> _updateErmaessigungCheck(int id, {bool? checkDokumentLesbar, bool? checkLeistungsartErkennbar, bool? checkAktuell12Monate}) async {
    try {
      final result = await widget.apiService.updateErmaessigung(
        id: id,
        checkDokumentLesbar: checkDokumentLesbar,
        checkLeistungsartErkennbar: checkLeistungsartErkennbar,
        checkAktuell12Monate: checkAktuell12Monate,
      );
      if (mounted && result['success'] == true) {
        _loadErmaessigungen();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateErmaessigungStatus(int id, String status) async {
    try {
      final result = await widget.apiService.updateErmaessigung(id: id, status: status);
      if (mounted) {
        if (result['success'] == true) {
          final labels = {'genehmigt': 'Ermäßigung genehmigt', 'abgelehnt': 'Ermäßigung abgelehnt', 'eingereicht': 'Status zurückgesetzt'};
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(labels[status] ?? 'Status aktualisiert'),
              backgroundColor: status == 'genehmigt' ? Colors.green : status == 'abgelehnt' ? Colors.red : Colors.grey,
            ),
          );
          _loadErmaessigungen();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteErmaessigung(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Antrag löschen'),
          ],
        ),
        content: const Text('Soll dieser Ermäßigungsantrag endgültig gelöscht werden?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete),
            label: const Text('Löschen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final result = await widget.apiService.deleteErmaessigung(id);
        if (mounted) {
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Antrag gelöscht'), backgroundColor: Colors.green),
            );
            _loadErmaessigungen();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _viewErmaessigungDokument(int id, String filename) async {
    final ext = filename.toLowerCase().split('.').last;
    final viewable = ['pdf', 'jpg', 'jpeg', 'png'];
    if (!viewable.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vorschau nur für PDF und Bilder verfügbar'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await widget.apiService.downloadErmaessigung(id);
      if (!mounted) return;
      Navigator.pop(context);

      if (result['success'] == true) {
        final bytes = base64Decode(result['data']);
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/${result['filename']}';
        await File(filePath).writeAsBytes(bytes);
        if (mounted) {
          await FileViewerDialog.show(context, filePath, result['filename']);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler beim Download'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showErmaessigungAblehnungDialog(int id) async {
    final grundController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red),
            SizedBox(width: 8),
            Text('Ermäßigung ablehnen'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bitte geben Sie den Grund der Ablehnung an (Pflichtfeld):',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: grundController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Ablehnungsgrund *',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () {
              if (grundController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Ablehnungsgrund ist Pflicht'), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.close),
            label: const Text('Ablehnen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirmed == true && grundController.text.trim().isNotEmpty) {
      try {
        final result = await widget.apiService.updateErmaessigung(
          id: id,
          status: 'abgelehnt',
          ablehnungsgrund: grundController.text.trim(),
        );
        if (mounted) {
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ermäßigung abgelehnt'), backgroundColor: Colors.red),
            );
            _loadErmaessigungen();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // NOTIZEN TAB
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadNotizen() async {
    setState(() => _isLoadingNotizen = true);
    try {
      final result = await widget.apiService.getNotizen(widget.user.id);
      if (mounted && result['success'] == true) {
        setState(() {
          _notizen = List<Map<String, dynamic>>.from(result['notizen'] ?? []);
          _isLoadingNotizen = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingNotizen = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingNotizen = false);
    }
  }

  Future<void> _createNotiz() async {
    final text = _notizController.text.trim();
    debugPrint('[NOTIZ] _createNotiz called, text="$text", kategorie=$_notizKategorie, wichtig=$_notizWichtig');
    if (text.isEmpty) {
      debugPrint('[NOTIZ] Text is empty, returning');
      return;
    }

    try {
      debugPrint('[NOTIZ] Sending to API: userId=${widget.user.id}');
      final result = await widget.apiService.createNotiz(
        userId: widget.user.id,
        notiz: text,
        kategorie: _notizKategorie,
        wichtig: _notizWichtig,
      );
      debugPrint('[NOTIZ] API response: $result');
      if (mounted) {
        if (result['success'] == true) {
          _notizController.clear();
          setState(() {
            _notizKategorie = 'allgemein';
            _notizWichtig = false;
          });
          _loadNotizen();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notiz gespeichert'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('[NOTIZ] Exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteNotiz(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notiz löschen'),
        content: const Text('Möchten Sie diese Notiz wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final result = await widget.apiService.deleteNotiz(id);
      if (mounted) {
        if (result['success'] == true) {
          _loadNotizen();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notiz gelöscht'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static const _kategorieLabels = {
    'allgemein': 'Allgemein',
    'verhalten': 'Verhalten',
    'zahlung': 'Zahlung',
    'kommunikation': 'Kommunikation',
    'sonstiges': 'Sonstiges',
  };

  static const _kategorieColors = {
    'allgemein': Colors.blueGrey,
    'verhalten': Colors.orange,
    'zahlung': Colors.green,
    'kommunikation': Colors.blue,
    'sonstiges': Colors.purple,
  };

  static const _kategorieIcons = {
    'allgemein': Icons.notes,
    'verhalten': Icons.person_outline,
    'zahlung': Icons.euro,
    'kommunikation': Icons.chat_bubble_outline,
    'sonstiges': Icons.more_horiz,
  };

  Widget _buildNotizenTab() {
    final df = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');

    return Column(
      children: [
        // Create new note
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            border: Border(bottom: BorderSide(color: Colors.amber.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Neue Notiz', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _notizController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Interne Notiz über dieses Mitglied...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(12),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // Kategorie dropdown
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _notizKategorie,
                      decoration: InputDecoration(
                        labelText: 'Kategorie',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      items: _kategorieLabels.entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Row(
                            children: [
                              Icon(_kategorieIcons[e.key], size: 16, color: _kategorieColors[e.key]),
                              const SizedBox(width: 6),
                              Text(e.value, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _notizKategorie = v ?? 'allgemein'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Wichtig toggle
                  FilterChip(
                    label: const Text('Wichtig', style: TextStyle(fontSize: 12)),
                    selected: _notizWichtig,
                    onSelected: (v) => setState(() => _notizWichtig = v),
                    selectedColor: Colors.red.shade100,
                    avatar: Icon(
                      _notizWichtig ? Icons.star : Icons.star_border,
                      size: 16,
                      color: _notizWichtig ? Colors.red.shade700 : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Submit button
                  ElevatedButton.icon(
                    onPressed: _createNotiz,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Hinzufügen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Notes list
        Expanded(
          child: _isLoadingNotizen
              ? const Center(child: CircularProgressIndicator())
              : _notizen.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sticky_note_2_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text('Keine Notizen vorhanden', style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _notizen.length,
                      itemBuilder: (ctx, i) {
                        final notiz = _notizen[i];
                        final kategorie = notiz['kategorie']?.toString() ?? 'allgemein';
                        final isWichtig = notiz['wichtig'] == true;
                        final color = _kategorieColors[kategorie] ?? Colors.blueGrey;
                        final icon = _kategorieIcons[kategorie] ?? Icons.notes;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: isWichtig ? 2 : 0.5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: isWichtig
                                ? BorderSide(color: Colors.red.shade300, width: 1.5)
                                : BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row
                                Row(
                                  children: [
                                    if (isWichtig) ...[
                                      Icon(Icons.star, size: 16, color: Colors.red.shade600),
                                      const SizedBox(width: 4),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(icon, size: 13, color: color),
                                          const SizedBox(width: 4),
                                          Text(
                                            _kategorieLabels[kategorie] ?? kategorie,
                                            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      notiz['created_at'] != null
                                          ? df.format(DateTime.tryParse(notiz['created_at']) ?? DateTime.now())
                                          : '',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () => _deleteNotiz(notiz['id'] is int ? notiz['id'] : int.parse(notiz['id'].toString())),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Note text
                                SelectableText(
                                  notiz['notiz']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 13, height: 1.4),
                                ),
                                const SizedBox(height: 6),
                                // Author
                                Text(
                                  'von ${notiz['erstellt_von_name'] ?? 'Unbekannt'} (${notiz['erstellt_von_nummer'] ?? ''})',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        // Footer with count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                '${_notizen.length} Notiz${_notizen.length == 1 ? '' : 'en'} — Nur für Admins sichtbar',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== TICKETS TAB ====================

  Future<void> _loadUserTimeSummary() async {
    setState(() => _isLoadingTimeSummary = true);
    try {
      final result = await _ticketService.getUserTimeSummary(
        mitgliedernummer: widget.adminMitgliedernummer,
        memberMitgliedernummer: widget.user.mitgliedernummer,
      );
      if (mounted) {
        setState(() {
          _userTimeSummary = result;
          _isLoadingTimeSummary = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingTimeSummary = false);
    }
  }

  Future<void> _loadMemberTickets() async {
    setState(() => _isLoadingTickets = true);
    try {
      // Use admin endpoint to get tickets translated in admin's language
      final result = await _ticketService.getAdminTickets(
        widget.adminMitgliedernummer,
        memberMitgliedernummer: widget.user.mitgliedernummer,
      );
      if (mounted) {
        setState(() {
          _memberTickets = result?.tickets ?? [];
          _isLoadingTickets = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingTickets = false);
    }
  }

  Color _ticketStatusColor(String status) {
    switch (status) {
      case 'open': return Colors.blue;
      case 'in_progress': return Colors.orange;
      case 'waiting_member': return Colors.amber.shade700;
      case 'waiting_staff': return Colors.purple;
      case 'waiting_authority': return Colors.teal;
      case 'done': return Colors.green;
      default: return Colors.grey;
    }
  }

  Color _ticketPriorityColor(String priority) {
    switch (priority) {
      case 'high': return Colors.red;
      case 'medium': return Colors.orange;
      case 'low': return Colors.green;
      default: return Colors.grey;
    }
  }

  Widget _buildTicketsTab() {
    final df = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');

    if (_isLoadingTickets) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_memberTickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.confirmation_number_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Tickets vorhanden', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    // Stats
    final openCount = _memberTickets.where((t) => t.status == 'open').length;
    final inProgressCount = _memberTickets.where((t) => t.status == 'in_progress' || t.status == 'waiting_member' || t.status == 'waiting_staff' || t.status == 'waiting_authority').length;
    final doneCount = _memberTickets.where((t) => t.status == 'done').length;

    return Column(
      children: [
        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border(bottom: BorderSide(color: Colors.blue.shade200)),
          ),
          child: Row(
            children: [
              Icon(Icons.confirmation_number, size: 18, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text('${_memberTickets.length} Tickets', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
              const Spacer(),
              _buildTicketStatChip('Offen', openCount, Colors.blue),
              const SizedBox(width: 8),
              _buildTicketStatChip('In Arbeit', inProgressCount, Colors.orange),
              const SizedBox(width: 8),
              _buildTicketStatChip('Erledigt', doneCount, Colors.green),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () {
                  _loadMemberTickets();
                  _loadUserTimeSummary();
                },
                tooltip: 'Aktualisieren',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        // Time summary
        if (_userTimeSummary != null && _userTimeSummary!.summary.gesamtSeconds > 0) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade50,
              border: Border(bottom: BorderSide(color: Colors.deepOrange.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer, size: 16, color: Colors.deepOrange.shade700),
                    const SizedBox(width: 6),
                    Text('Zeiterfassung', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.deepOrange.shade700)),
                    const Spacer(),
                    Text(
                      _userTimeSummary!.totalDisplay,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepOrange.shade800),
                    ),
                    const SizedBox(width: 4),
                    Text('gesamt', style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildTimeChip(Icons.directions_car, 'Fahrzeit', _userTimeSummary!.summary.fahrzeitDisplay, Colors.blue),
                    const SizedBox(width: 8),
                    _buildTimeChip(Icons.build, 'Arbeitszeit', _userTimeSummary!.summary.arbeitszeitDisplay, Colors.green),
                    const SizedBox(width: 8),
                    _buildTimeChip(Icons.hourglass_empty, 'Wartezeit', _userTimeSummary!.summary.wartezeitDisplay, Colors.orange),
                  ],
                ),
              ],
            ),
          ),
        ] else if (_isLoadingTimeSummary) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade50,
              border: Border(bottom: BorderSide(color: Colors.deepOrange.shade200)),
            ),
            child: const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        ],
        // Ticket list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _memberTickets.length,
            itemBuilder: (ctx, i) {
              final ticket = _memberTickets[i];
              final statusColor = _ticketStatusColor(ticket.status);
              final priorityColor = _ticketPriorityColor(ticket.priority);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => TicketDetailsDialog(
                        ticket: ticket,
                        mitgliedernummer: widget.adminMitgliedernummer,
                        onTicketAction: (ticketId, action) {
                          _loadMemberTickets();
                        },
                      ),
                    ).then((_) => _loadMemberTickets());
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: ID + Priority + Status
                        Row(
                          children: [
                            Text('#${ticket.id}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: priorityColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(ticket.priorityDisplay, style: TextStyle(fontSize: 11, color: priorityColor, fontWeight: FontWeight.w600)),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(ticket.statusDisplay, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Subject
                        Text(ticket.subject, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                        const SizedBox(height: 6),
                        // Footer: date + admin
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(df.format(ticket.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            if (ticket.adminName != null) ...[
                              const SizedBox(width: 12),
                              Icon(Icons.person, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(ticket.adminName!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            ],
                            if (ticket.categoryName != null) ...[
                              const SizedBox(width: 12),
                              Icon(Icons.category, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(ticket.categoryName!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTicketStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label: $count', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildTimeChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  // ==================== TERMINE TAB ====================

  Future<void> _loadMemberTermine() async {
    setState(() => _isLoadingTermine = true);
    try {
      final result = await _terminService.getAllTermine(participantId: widget.user.id);
      if (mounted && result['success'] == true) {
        final termineList = result['termine'] as List? ?? [];
        setState(() {
          _memberTermine = termineList.map((t) => Termin.fromJson(t)).toList();
          _isLoadingTermine = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingTermine = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingTermine = false);
    }
  }

  Widget _buildTermineTab() {
    final df = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
    final dateOnly = DateFormat('dd.MM.yyyy', 'de_DE');
    final timeOnly = DateFormat('HH:mm', 'de_DE');

    if (_isLoadingTermine) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_memberTermine.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Termine vorhanden', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    // Split into upcoming and past
    final now = DateTime.now();
    final upcoming = _memberTermine.where((t) => t.terminDate.isAfter(now)).toList();
    final past = _memberTermine.where((t) => !t.terminDate.isAfter(now)).toList();

    return Column(
      children: [
        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            border: Border(bottom: BorderSide(color: Colors.purple.shade200)),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_month, size: 18, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              Text('${_memberTermine.length} Termine', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.purple.shade700)),
              const Spacer(),
              _buildTicketStatChip('Anstehend', upcoming.length, Colors.blue),
              const SizedBox(width: 8),
              _buildTicketStatChip('Vergangen', past.length, Colors.grey),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loadMemberTermine,
                tooltip: 'Aktualisieren',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        // Termine list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (upcoming.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Anstehende Termine', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blue.shade700)),
                ),
                ...upcoming.map((t) => _buildTerminCard(t, df, dateOnly, timeOnly)),
                const SizedBox(height: 16),
              ],
              if (past.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Vergangene Termine', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade600)),
                ),
                ...past.map((t) => _buildTerminCard(t, df, dateOnly, timeOnly, isPast: true)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerminCard(Termin termin, DateFormat df, DateFormat dateOnly, DateFormat timeOnly, {bool isPast = false}) {
    final catColor = termin.categoryColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isPast ? 0 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isPast ? Colors.grey.shade200 : catColor.withValues(alpha: 0.3)),
      ),
      color: isPast ? Colors.grey.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Category + Status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(termin.categoryDisplay, style: TextStyle(fontSize: 11, color: catColor, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                if (termin.status == 'cancelled')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Abgesagt', style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Title
            Text(termin.title, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: isPast ? Colors.grey.shade600 : null)),
            if (termin.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(termin.description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            // Date + Time + Location
            Row(
              children: [
                Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(dateOnly.format(termin.terminDate), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                const SizedBox(width: 12),
                Icon(Icons.access_time, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text('${timeOnly.format(termin.terminDate)} - ${timeOnly.format(termin.terminEndTime)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (termin.location.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Flexible(child: Text(termin.location, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                ],
              ],
            ),
            // Participants + linked ticket
            if (termin.totalParticipants != null || termin.ticketSubject != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (termin.totalParticipants != null) ...[
                    Icon(Icons.group, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text('${termin.confirmedCount ?? 0}/${termin.totalParticipants} bestätigt', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                  if (termin.ticketSubject != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.confirmation_number, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Flexible(child: Text(termin.ticketSubject!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }


  // ============= BEHÖRDE TAB (extracted to behorde_tab_content.dart) =============

  Widget _buildBehoerdeTab() {
    return BehoerdeTabContent(
      user: widget.user,
      apiService: widget.apiService,
      ticketService: _ticketService,
      terminService: _terminService,
      adminMitgliedernummer: widget.adminMitgliedernummer,
    );
  }

  // ============= GESUNDHEIT TAB (extracted to gesundheit_tab_content.dart) =============

  Widget _buildGesundheitTab() {
    return GesundheitTabContent(
      user: widget.user,
      apiService: widget.apiService,
      ticketService: _ticketService,
      terminService: _terminService,
      adminMitgliedernummer: widget.adminMitgliedernummer,
    );
  }

  // ============= FINANZEN TAB (extracted to finanzen_tab_content.dart) =============

  Widget _buildFinanzenTab() {
    return FinanzenTabContent(
      user: widget.user,
      apiService: widget.apiService,
      ticketService: _ticketService,
      adminMitgliedernummer: widget.adminMitgliedernummer,
    );
  }

  Widget _buildFreizeitTab() {
    return FreizeitTabContent(
      user: widget.user,
      apiService: widget.apiService,
    );
  }
}
