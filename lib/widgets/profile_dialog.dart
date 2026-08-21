import 'dart:convert';
import 'package:flutter/material.dart';
import 'phone_link.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import '../services/logger_service.dart';
import '../services/verwarnung_service.dart';
import '../services/dokumente_service.dart';
import '../utils/role_helpers.dart';
import '../utils/sprach_flaggen.dart';
import '../utils/sprachen_options.dart';
import 'visitenkarte.dart';
import '../utils/app_farben.dart';

class ProfileDialog extends StatefulWidget {
  final String userName;
  final String mitgliedernummer;
  final String email;
  final String role;
  final int? userId;
  final ApiService apiService;
  final Function(String) onEmailChanged;

  const ProfileDialog({
    super.key,
    required this.userName,
    required this.mitgliedernummer,
    required this.email,
    required this.role,
    this.userId,
    required this.apiService,
    required this.onEmailChanged,
  });

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> with SingleTickerProviderStateMixin {
  bool _isChangingPassword = false;
  bool _isChangingEmail = false;
  bool _isChangingPhone = false;
  bool _isLoading = false;
  bool _isLoadingSessions = true;
  List<dynamic> _sessions = [];

  late TabController _tabController;

  // Password change controllers
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Email change controllers
  final _newEmailController = TextEditingController();
  final _emailPasswordController = TextEditingController();

  // Phone controllers
  final _countryCodeController = TextEditingController(text: '+49');
  final _phoneNumberController = TextEditingController();
  String _currentPhone = '—';


  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscureEmailPassword = true;

  // Verwarnungen (read-only)
  final _verwarnungService = VerwarnungService();
  List<Verwarnung> _verwarnungen = [];
  VerwarnungStats? _verwarnungStats;
  bool _isLoadingVerwarnungen = false;

  // Dokumente (read-only)
  final _dokumenteService = DokumenteService();
  List<MemberDokument> _dokumente = [];
  bool _isLoadingDokumente = false;

  // Mitgliedschaft data
  Map<String, dynamic>? _profileData;

  // Verifizierung
  List<Map<String, dynamic>> _verifizierungStages = [];
  bool _isLoadingVerifizierung = false;

  // Stufe 1 - Persönliche Daten controllers
  final _vornameController = TextEditingController();
  final _vorname2Controller = TextEditingController();
  final _nachnameController = TextEditingController();
  final _strasseController = TextEditingController();
  final _hausnummerController = TextEditingController();
  final _plzController = TextEditingController();
  final _ortController = TextEditingController();
  final _bundeslandController = TextEditingController();
  final _landController = TextEditingController();
  final _telefonMobilController = TextEditingController();
  final _telefonFixController = TextEditingController();
  final _geburtsortController = TextEditingController();
  final _staatsangehoerigkeitController = TextEditingController();
  final _muttersprachController = TextEditingController();
  DateTime? _selectedGeburtsdatum;
  String _selectedGeschlechtStufe1 = 'M';
  bool _isSavingStufe1 = false;

  // Stufe 3 - Zahlungsmethode + Zahlungstag
  String? _selectedZahlungsmethode;
  int? _selectedZahlungstag;
  bool _isSavingStufe3 = false;

  /// Gesprochene Sprachen (`users.languages`, ISO-639-1-Codes).
  ///
  /// ⚠️ Die Spalte gibt es seit Langem und `update_profile.php` schreibt sie
  /// auch — es gab nur nirgends eine Eingabemöglichkeit, und `get_profile.php`
  /// gab sie nicht zurück. Sie war damit beschreibbar und unlesbar zugleich,
  /// weshalb sie bei allen 61 Konten leer stand. Ohne diesen Editor bliebe die
  /// Sprachzeile der Visitenkarte für immer leer.
  List<String> _languages = [];
  bool _isSavingSprachen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _verwarnungService.setToken(widget.apiService.token);
    _dokumenteService.setToken(widget.apiService.token);
    _loadSessions();
    _loadProfileData();
    if (widget.userId != null) {
      _loadVerwarnungen();
      _loadDokumente();
      _loadVerifizierung();
    }
  }

  Future<void> _loadProfileData() async {
    try {
      final result = await widget.apiService.getProfile(widget.mitgliedernummer);
      if (result['success'] == true && mounted) {
        _profileData = result;
        // Populate Stufe 1 controllers
        _vornameController.text = result['vorname']?.toString() ?? '';
        _vorname2Controller.text = result['vorname2']?.toString() ?? '';
        final g = result['geschlecht']?.toString() ?? 'M';
        _selectedGeschlechtStufe1 = ['M', 'W', 'D'].contains(g) ? g : 'M';
        _nachnameController.text = result['nachname']?.toString() ?? '';
        _strasseController.text = result['strasse']?.toString() ?? '';
        _hausnummerController.text = result['hausnummer']?.toString() ?? '';
        _plzController.text = result['plz']?.toString() ?? '';
        _ortController.text = result['ort']?.toString() ?? '';
        _bundeslandController.text = result['bundesland']?.toString() ?? '';
        _landController.text = result['land']?.toString() ?? '';
        _telefonMobilController.text = result['telefon_mobil']?.toString() ?? '';
        _telefonFixController.text = result['telefon_fix']?.toString() ?? '';
        _geburtsortController.text = result['geburtsort']?.toString() ?? '';
        _staatsangehoerigkeitController.text = result['staatsangehoerigkeit']?.toString() ?? '';
        _muttersprachController.text = result['muttersprache']?.toString() ?? '';
        _selectedGeburtsdatum = result['geburtsdatum'] != null ? DateTime.tryParse(result['geburtsdatum'].toString()) : null;
        _selectedZahlungsmethode = result['zahlungsmethode']?.toString();
        _selectedZahlungstag = result['zahlungstag'] != null ? int.tryParse(result['zahlungstag'].toString()) : null;
        // Sprachen: der Server liefert seit 2026-08-13 immer eine Liste, ältere
        // Fassungen gar nichts. Beides landet hier als leere Liste.
        final rohSprachen = result['languages'];
        _languages = rohSprachen is List
            ? rohSprachen
                .map((e) => e.toString().trim().toLowerCase())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];
        // Load phone
        if (result['telefon_mobil'] != null && result['telefon_mobil'].toString().isNotEmpty) {
          final phoneStr = result['telefon_mobil'].toString();
          _currentPhone = phoneStr;
          final parts = phoneStr.split(' ');
          if (parts.isNotEmpty) {
            _countryCodeController.text = parts[0];
            if (parts.length > 1) {
              _phoneNumberController.text = parts.sublist(1).join(' ');
            }
          }
        }


      }
    } catch (e) {
      LoggerService().error('Error loading profile data: $e', tag: 'ProfileDialog');
    }
  }

  Future<void> _loadSessions() async {
    LoggerService().debug('Loading sessions...', tag: 'ProfileDialog');
    setState(() => _isLoadingSessions = true);
    try {
      LoggerService().debug('Calling getMySessions()...', tag: 'ProfileDialog');
      final result = await widget.apiService.getMySessions();
      LoggerService().debug('Got result: $result', tag: 'ProfileDialog');

      if (result['success'] == true && mounted) {
        final sessions = result['sessions'] ?? [];
        LoggerService().info('Success! Got ${sessions.length} sessions', tag: 'ProfileDialog');
        setState(() {
          _sessions = sessions;
          _isLoadingSessions = false;
        });
      } else {
        LoggerService().warning('API returned success=false or no sessions', tag: 'ProfileDialog');
        LoggerService().warning('Result: $result', tag: 'ProfileDialog');
        if (mounted) {
          setState(() {
            _sessions = [];
            _isLoadingSessions = false;
          });
        }
      }
    } catch (e, stackTrace) {
      LoggerService().error('Error loading sessions: $e', tag: 'ProfileDialog');
      LoggerService().error('Stack trace: $stackTrace', tag: 'ProfileDialog');
      if (mounted) {
        setState(() => _isLoadingSessions = false);
      }
    }
  }

  // ============= VERWARNUNGEN =============

  Future<void> _loadVerwarnungen() async {
    if (widget.userId == null) return;
    setState(() => _isLoadingVerwarnungen = true);
    final result = await _verwarnungService.getVerwarnungen(widget.userId!);
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

  // ============= DOKUMENTE =============

  Future<void> _loadDokumente() async {
    if (widget.userId == null) return;
    setState(() => _isLoadingDokumente = true);
    final result = await _dokumenteService.getDokumente(widget.userId!);
    if (mounted) {
      setState(() {
        _dokumente = result;
        _isLoadingDokumente = false;
      });
    }
  }

  Future<void> _downloadDokument(MemberDokument doc) async {
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
      final saved = await FilePickerHelper.saveBytes(
        bytes: bytes,
        fileName: (data['filename'] ?? 'dokument').toString(),
        dialogTitle: 'Dokument speichern',
      );
      if (saved == null) return; // abgebrochen

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gespeichert: $saved'),
          backgroundColor: Colors.green,
          // `Process.run('open', …)` stand hier vorher fest verdrahtet — das
          // gibt es nur auf macOS. OpenFilex kennt jede Plattform, und auf
          // Mobil gibt es ohnehin keinen Pfad zum Öffnen.
          action: FilePickerHelper.savesToRealPath
              ? SnackBarAction(
                  label: 'Öffnen',
                  textColor: Colors.white,
                  onPressed: () => OpenFilex.open(saved),
                )
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichern: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ============= VERIFIZIERUNG =============

  Future<void> _loadVerifizierung() async {
    if (widget.userId == null) return;
    setState(() => _isLoadingVerifizierung = true);
    try {
      final result = await widget.apiService.getVerifizierung(widget.userId!);
      if (mounted && result['success'] == true) {
        setState(() {
          _verifizierungStages = List<Map<String, dynamic>>.from(result['stages'] ?? []);
          _isLoadingVerifizierung = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingVerifizierung = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingVerifizierung = false);
    }
  }

  Future<void> _saveStufe1() async {
    if (widget.userId == null) return;
    setState(() => _isSavingStufe1 = true);
    try {
      // Update personal data via profile endpoint
      await widget.apiService.updateProfile(
        mitgliedernummer: widget.mitgliedernummer,
        vorname: _vornameController.text,
        nachname: _nachnameController.text,
        strasse: _strasseController.text,
        hausnummer: _hausnummerController.text,
        plz: _plzController.text,
        ort: _ortController.text,
        telefonMobil: _telefonMobilController.text,
        geburtsdatum: _selectedGeburtsdatum != null
            ? '${_selectedGeburtsdatum!.year}-${_selectedGeburtsdatum!.month.toString().padLeft(2, '0')}-${_selectedGeburtsdatum!.day.toString().padLeft(2, '0')}'
            : null,
        geschlecht: _selectedGeschlechtStufe1,
      );
      if (mounted) {
        setState(() => _isSavingStufe1 = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Persönliche Daten gespeichert'), backgroundColor: Colors.green),
        );
        _loadProfileData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingStufe1 = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveStufe3({String? zahlungsmethode, int? zahlungstag}) async {
    if (widget.userId == null) return;
    setState(() => _isSavingStufe3 = true);
    try {
      await widget.apiService.updateUser(
        userId: widget.userId!,
        zahlungsmethode: zahlungsmethode,
        zahlungstag: zahlungstag,
      );
      if (mounted) {
        setState(() {
          if (zahlungsmethode != null) _selectedZahlungsmethode = zahlungsmethode;
          if (zahlungstag != null) _selectedZahlungstag = zahlungstag;
          _isSavingStufe3 = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zahlungsdaten gespeichert'), backgroundColor: Colors.green),
        );
        _loadProfileData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingStufe3 = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _savePhone() async {
    final phone = '${_countryCodeController.text} ${_phoneNumberController.text}'.trim();

    if (_phoneNumberController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Telefonnummer eingeben'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await widget.apiService.updateProfile(
        mitgliedernummer: widget.mitgliedernummer,
        telefonMobil: phone,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          _currentPhone = phone;
          _isChangingPhone = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Telefonnummer gespeichert'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Fehler beim Speichern'),
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _revokeSession(int sessionId, String deviceName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gerät abmelden'),
        content: Text('Möchten Sie das Gerät "$deviceName" wirklich abmelden?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final result = await widget.apiService.revokeMySession(sessionId);
      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gerät erfolgreich abgemeldet'),
            backgroundColor: Colors.green,
          ),
        );
        _loadSessions(); // Reload sessions
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Fehler beim Abmelden'),
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

  @override
  void dispose() {
    _tabController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newEmailController.dispose();
    _emailPasswordController.dispose();
    _countryCodeController.dispose();
    _phoneNumberController.dispose();
    _vornameController.dispose();
    _vorname2Controller.dispose();
    _nachnameController.dispose();
    _strasseController.dispose();
    _hausnummerController.dispose();
    _plzController.dispose();
    _ortController.dispose();
    _bundeslandController.dispose();
    _landController.dispose();
    _telefonMobilController.dispose();
    _telefonFixController.dispose();
    _geburtsortController.dispose();
    _staatsangehoerigkeitController.dispose();
    _muttersprachController.dispose();
    super.dispose();
  }

  String _getRoleText(String role) {
    switch (role) {
      case 'vorsitzer':
        return 'Vorsitzer';
      case 'schatzmeister':
        return 'Schatzmeister';
      case 'kassierer':
        return 'Kassierer';
      case 'mitgliedergrunder':
        return 'Gründer';
      default:
        return role;
    }
  }

  Future<void> _changePassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwörter stimmen nicht überein'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_newPasswordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwort muss mindestens 8 Zeichen lang sein'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await widget.apiService.changePassword(
        widget.mitgliedernummer,
        _currentPasswordController.text,
        _newPasswordController.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Passwort erfolgreich geändert'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isChangingPassword = false;
          _currentPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Fehler beim Ändern des Passworts'),
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changeEmail() async {
    if (_newEmailController.text.isEmpty || !_newEmailController.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte geben Sie eine gültige E-Mail-Adresse ein'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await widget.apiService.changeEmail(
        widget.mitgliedernummer,
        _newEmailController.text,
        _emailPasswordController.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        widget.onEmailChanged(_newEmailController.text);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('E-Mail erfolgreich geändert'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isChangingEmail = false;
          _newEmailController.clear();
          _emailPasswordController.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Fehler beim Ändern der E-Mail'),
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 950,
        height: 700,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFF4a90d9),
                    child: Icon(Icons.person, size: 36, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _getRoleText(widget.role),
                          style: TextStyle(
                            fontSize: 14,
                            color: F.h(Colors.purple, 700),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // TabBar
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF4a90d9),
              unselectedLabelColor: F.h(Colors.grey, 500),
              indicatorColor: const Color(0xFF4a90d9),
              isScrollable: true,
              tabs: const [
                Tab(icon: Icon(Icons.person), text: 'Profil'),
                Tab(icon: Icon(Icons.devices), text: 'Meine Geräte'),
                Tab(icon: Icon(Icons.card_membership), text: 'Visitenkarte'),
                Tab(icon: Icon(Icons.warning_amber), text: 'Verwarnungen'),
                Tab(icon: Icon(Icons.folder_open), text: 'Dokumente'),
                Tab(icon: Icon(Icons.groups), text: 'Mitgliedschaft'),
                Tab(icon: Icon(Icons.verified_user), text: 'Verifizierung'),
              ],
            ),

            // TabBarView
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildProfileTab(),
                  _buildDevicesTab(),
                  Visitenkarte(
                    mitgliedernummer: widget.mitgliedernummer,
                    apiService: widget.apiService,
                  ),
                  _buildVerwarnungenTab(),
                  _buildDokumenteTab(),
                  _buildMitgliedschaftTab(),
                  _buildVerifizierungTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Info
          _buildInfoRow(Icons.badge, 'Benutzernummer', widget.mitgliedernummer),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.email, 'E-Mail', widget.email),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.phone, 'Telefon', _currentPhone),
          const SizedBox(height: 12),
          _buildSprachenRow(),
          const SizedBox(height: 24),

          // Change Phone Button/Form
          if (!_isChangingPhone)
            OutlinedButton.icon(
              onPressed: () => setState(() => _isChangingPhone = true),
              icon: const Icon(Icons.phone),
              label: const Text('Telefonnummer hinzufügen'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            )
          else
            _buildChangePhoneForm(),

          const SizedBox(height: 12),

          // Change Email Button/Form
          if (!_isChangingEmail)
            OutlinedButton.icon(
              onPressed: () => setState(() => _isChangingEmail = true),
              icon: const Icon(Icons.email),
              label: const Text('E-Mail ändern'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            )
          else
            _buildChangeEmailForm(),

          const SizedBox(height: 12),

          // Change Password Button/Form
          if (!_isChangingPassword)
            OutlinedButton.icon(
              onPressed: () => setState(() => _isChangingPassword = true),
              icon: const Icon(Icons.lock),
              label: const Text('Passwort ändern'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            )
          else
            _buildChangePasswordForm(),
        ],
      ),
    );
  }

  Widget _buildDevicesTab() {
    if (_isLoadingSessions) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_other, size: 64, color: F.h(Colors.grey, 400)),
            const SizedBox(height: 16),
            Text(
              'Keine aktiven Geräte',
              style: TextStyle(fontSize: 16, color: F.h(Colors.grey, 600)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final isCurrentSession = session['is_current'] == true;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isCurrentSession ? Colors.green : F.h(Colors.grey, 300),
              child: Icon(
                _getDeviceIcon(session['platform'] ?? ''),
                color: Colors.white,
              ),
            ),
            title: Text(
              session['device_name'] ?? 'Unbekanntes Gerät',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                // IP + Reputation
                Row(
                  children: [
                    Icon(Icons.public, size: 14, color: F.h(Colors.grey, 500)),
                    const SizedBox(width: 4),
                    Text('IP: ${session['ip_address'] ?? 'N/A'}'),
                    const SizedBox(width: 6),
                    _buildIpReputationBadge(session['ip_reputation']),
                  ],
                ),
                // Platform
                Row(
                  children: [
                    Icon(Icons.phone_android, size: 14, color: F.h(Colors.grey, 500)),
                    const SizedBox(width: 4),
                    Text('${session['platform'] ?? 'Unbekannt'}'),
                  ],
                ),
                // Provider
                if (session['ip_provider'] != null && session['ip_provider']['provider'] != null)
                  Row(
                    children: [
                      Icon(_getConnectionTypeIcon(session['ip_provider']['connection_type']),
                          size: 14, color: _getConnectionTypeColor(session['ip_provider']['connection_type'])),
                      const SizedBox(width: 4),
                      Text(
                        '${session['ip_provider']['provider']}${session['ip_provider']['connection_type'] != null ? ' (${session['ip_provider']['connection_type']})' : ''}',
                        style: TextStyle(color: _getConnectionTypeColor(session['ip_provider']['connection_type'])),
                      ),
                    ],
                  ),
                // Blacklist warning
                if (session['ip_reputation'] != null && session['ip_reputation']['clean'] == false)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: F.h(Colors.red, 50),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: F.h(Colors.red, 200)),
                    ),
                    child: Text(
                      'Blacklisted: ${(session['ip_reputation']['blacklists'] as List?)?.join(', ') ?? ''}',
                      style: TextStyle(fontSize: 11, color: F.h(Colors.red, 700)),
                    ),
                  ),
                Text('Zuletzt aktiv: ${_formatLastSeen(session['last_used'])}'),
                if (isCurrentSession)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Aktuelles Gerät',
                      style: TextStyle(
                        color: F.h(Colors.green, 700),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: !isCurrentSession
                ? IconButton(
                    icon: const Icon(Icons.logout, color: Colors.red),
                    tooltip: 'Gerät abmelden',
                    onPressed: () => _revokeSession(
                      session['id'],
                      session['device_name'] ?? 'Unbekanntes Gerät',
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  // ============= VERWARNUNGEN TAB (read-only) =============

  Widget _buildVerwarnungenTab() {
    if (widget.userId == null) {
      return _buildNoDataTab(Icons.warning_amber, 'Verwarnungen nicht verfügbar');
    }

    if (_isLoadingVerwarnungen) {
      return const Center(child: CircularProgressIndicator());
    }

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

          // Header
          Row(
            children: [
              Icon(Icons.list_alt, size: 20, color: F.h(Colors.grey, 700)),
              const SizedBox(width: 8),
              Text(
                'Meine Verwarnungen (${_verwarnungen.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_verwarnungen.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: F.h(Colors.green, 600)),
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
                                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(v.grund, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (v.beschreibung != null && v.beschreibung!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(v.beschreibung!, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Erstellt von: ${v.createdByName}',
                              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500)),
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
    );
  }

  // ============= DOKUMENTE TAB (read-only with download) =============

  Widget _buildDokumenteTab() {
    if (widget.userId == null) {
      return _buildNoDataTab(Icons.folder_open, 'Dokumente nicht verfügbar');
    }

    if (_isLoadingDokumente) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.folder_open, size: 20, color: F.h(Colors.blue, 700)),
              const SizedBox(width: 8),
              Text(
                'Meine Dokumente (${_dokumente.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              if (_isLoadingDokumente)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 12),

          // Documents list
          if (_dokumente.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.folder_off, color: F.h(Colors.grey, 500)),
                    const SizedBox(width: 12),
                    const Text('Keine Dokumente vorhanden'),
                  ],
                ),
              ),
            )
          else
            ..._dokumente.map((doc) {
              final ext = doc.fileExtension;
              final color = _getFileColor(ext.toLowerCase());
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // File icon
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_getFileIcon(ext.toLowerCase()), color: color, size: 28),
                      ),
                      const SizedBox(width: 12),
                      // File info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(doc.dokumentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(ext, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                                ),
                                const SizedBox(width: 8),
                                Text(doc.filesizeFormatted, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('dd.MM.yyyy').format(doc.createdAt),
                                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
                                ),
                              ],
                            ),
                            if (doc.beschreibung != null && doc.beschreibung!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(doc.beschreibung!, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
                              ),
                            Text(
                              'Hochgeladen von: ${doc.uploadedByName}',
                              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500)),
                            ),
                          ],
                        ),
                      ),
                      // Download only
                      IconButton(
                        icon: Icon(Icons.download, color: F.h(Colors.blue, 600), size: 20),
                        tooltip: 'Herunterladen',
                        onPressed: () => _downloadDokument(doc),
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

  // ============= MITGLIEDSCHAFT TAB (read-only) =============

  Widget _buildMitgliedschaftTab() {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final data = _profileData;

    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final status = data['status'] ?? 'active';
    final role = data['role'] ?? widget.role;
    final mitgliedernummer = widget.mitgliedernummer;
    final createdAt = data['created_at'] != null ? DateTime.tryParse(data['created_at'].toString()) : null;
    final lastLogin = data['last_login'] != null ? DateTime.tryParse(data['last_login'].toString()) : null;
    final mitgliedschaftDatum = data['mitgliedschaft_datum'] != null ? DateTime.tryParse(data['mitgliedschaft_datum'].toString()) : null;
    final mitgliedsart = data['mitgliedsart'];
    final zahlungsmethode = data['zahlungsmethode'];

    final mitgliedsartLabels = {
      'ordentlich': 'Ordentliches Mitglied',
      'foerdermitglied': 'Fördermitglied',
      'ehrenmitglied': 'Ehrenmitglied',
    };

    final zahlungsLabels = {
      'ueberweisung': 'Überweisung',
      'sepa_lastschrift': 'SEPA-Lastschrift',
      'dauerauftrag': 'Dauerauftrag',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status
          _mitgliedschaftRow(
            icon: Icons.circle,
            iconColor: getStatusColor(status),
            label: 'Status',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: getStatusColor(status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: getStatusColor(status).withValues(alpha: 0.3)),
              ),
              child: Text(
                getStatusText(status),
                style: TextStyle(
                  color: getStatusColor(status),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const Divider(height: 24),

          // Mitgliedernummer
          _mitgliedschaftRow(
            icon: Icons.badge,
            iconColor: Colors.blue,
            label: 'Mitgliedernummer',
            child: Text(
              mitgliedernummer,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 24),

          // Rolle
          _mitgliedschaftRow(
            icon: Icons.admin_panel_settings,
            iconColor: getRoleColor(role),
            label: 'Rolle',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: getRoleColor(role).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                getRoleText(role),
                style: TextStyle(
                  color: getRoleColor(role),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const Divider(height: 24),

          // Mitgliedsart
          _mitgliedschaftRow(
            icon: Icons.groups,
            iconColor: Colors.indigo,
            label: 'Mitgliedsart',
            child: Text(
              mitgliedsart != null && mitgliedsart.toString().isNotEmpty
                  ? (mitgliedsartLabels[mitgliedsart] ?? mitgliedsart.toString())
                  : 'Nicht festgelegt',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: mitgliedsart != null ? Colors.indigo : F.h(Colors.grey, 500),
                fontStyle: mitgliedsart == null ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          const Divider(height: 24),

          // Zahlungsmethode
          _mitgliedschaftRow(
            icon: Icons.payment,
            iconColor: Colors.green,
            label: 'Zahlungsmethode',
            child: Text(
              zahlungsmethode != null && zahlungsmethode.toString().isNotEmpty
                  ? (zahlungsLabels[zahlungsmethode] ?? zahlungsmethode.toString())
                  : 'Nicht festgelegt',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: zahlungsmethode != null ? F.h(Colors.green, 700) : F.h(Colors.grey, 500),
                fontStyle: zahlungsmethode == null ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          const Divider(height: 24),

          // Registriert am
          _mitgliedschaftRow(
            icon: Icons.app_registration,
            iconColor: F.h(Colors.grey, 500),
            label: 'Registriert am',
            child: Text(
              createdAt != null ? dateFormat.format(createdAt) : 'Unbekannt',
              style: const TextStyle(fontSize: 15),
            ),
          ),
          const Divider(height: 24),

          // Letzter Login
          _mitgliedschaftRow(
            icon: Icons.login,
            iconColor: F.h(Colors.grey, 500),
            label: 'Letzter Login',
            child: Text(
              lastLogin != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(lastLogin)
                  : 'Noch nie',
              style: const TextStyle(fontSize: 15),
            ),
          ),
          const Divider(height: 24),

          // Mitglied seit
          _mitgliedschaftRow(
            icon: Icons.card_membership,
            iconColor: Colors.green,
            label: 'Mitglied seit',
            child: Text(
              mitgliedschaftDatum != null
                  ? dateFormat.format(mitgliedschaftDatum)
                  : 'Noch nicht aktiviert',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: mitgliedschaftDatum != null ? F.h(Colors.green, 700) : F.h(Colors.grey, 500),
                fontStyle: mitgliedschaftDatum == null ? FontStyle.italic : FontStyle.normal,
              ),
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
              color: F.h(Colors.grey, 600),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  // ============= VERIFIZIERUNG TAB (read-only) =============

  Widget _buildVerifizierungTab() {
    if (widget.userId == null) {
      return _buildNoDataTab(Icons.verified_user, 'Verifizierung nicht verfügbar');
    }

    if (_isLoadingVerifizierung) {
      return const Center(child: CircularProgressIndicator());
    }

    // Vorsitzer only needs Stufe 1 (Persönliche Daten) and Stufe 3 (Zahlungsmethode)
    final relevantStages = _verifizierungStages
        .where((s) => s['stufe'] == 1 || s['stufe'] == 3)
        .toList();
    final geprueftCount = relevantStages.where((s) => s['status'] == 'geprueft').length;
    final totalCount = relevantStages.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: geprueftCount == totalCount ? F.h(Colors.green, 50) : F.h(Colors.blue, 50),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: geprueftCount == totalCount ? F.h(Colors.green, 200) : F.h(Colors.blue, 200),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      geprueftCount == totalCount ? Icons.check_circle : Icons.pending,
                      color: geprueftCount == totalCount ? F.h(Colors.green, 700) : F.h(Colors.blue, 700),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$geprueftCount/$totalCount Stufen geprüft',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: geprueftCount == totalCount ? F.h(Colors.green, 700) : F.h(Colors.blue, 700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: totalCount > 0 ? geprueftCount / totalCount : 0,
                    backgroundColor: F.h(Colors.grey, 300),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      geprueftCount == totalCount ? Colors.green : Colors.blue,
                    ),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Editable stages for Vorsitzer
          ...relevantStages.map((stage) {
            final stufe = stage['stufe'] as int;
            final status = stage['status'] as String;
            return _buildStufeCardEditable(stufe, status, stage);
          }),
        ],
      ),
    );
  }

  Widget _buildStufeCardEditable(int stufe, String status, Map<String, dynamic> stage) {
    final color = _verifizierungStatusColor(status);
    final isGeprueft = status == 'geprueft';

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
          child: Icon(
            isGeprueft ? Icons.check_circle : _stufeIcon(stufe),
            color: color,
            size: 24,
          ),
        ),
        title: Row(
          children: [
            Text(
              'Stufe $stufe: ${_stufeName(stufe)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isGeprueft ? F.h(Colors.green, 700) : null,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _verifizierungStatusText(status),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
        subtitle: stage['geprueft_am'] != null
            ? Text(
                'Geprüft am ${_formatDate(stage['geprueft_am'])} von ${stage['geprueft_von_name'] ?? 'Unbekannt'}',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isGeprueft) ...[
                  // Read-only display for verified stages
                  if (stufe == 1) _buildStufe1ReadOnlyContent(),
                  if (stufe == 3) _buildStufe3ReadOnlyContent(),
                  const SizedBox(height: 12),
                  // Hint: changes require live chat
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: F.h(Colors.orange, 50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: F.h(Colors.orange, 200)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: F.h(Colors.orange, 700)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Änderungen nach Verifizierung nur über Live-Chat mit Nachweisdokumenten möglich.',
                            style: TextStyle(fontSize: 12, color: F.h(Colors.orange, 800)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Editable content for unverified stages
                  if (stufe == 1) _buildStufe1EditContent(),
                  if (stufe == 3) _buildStufe3EditContent(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStufe1ReadOnlyContent() {
    final geburtsdatumStr = _selectedGeburtsdatum != null
        ? '${_selectedGeburtsdatum!.day.toString().padLeft(2, '0')}.${_selectedGeburtsdatum!.month.toString().padLeft(2, '0')}.${_selectedGeburtsdatum!.year}'
        : '';
    final fields = [
      ['Vorname', _vornameController.text],
      ['Nachname', _nachnameController.text],
      ['Geburtsdatum', geburtsdatumStr],
      ['Straße', _strasseController.text],
      ['Hausnummer', _hausnummerController.text],
      ['PLZ', _plzController.text],
      ['Ort', _ortController.text],
      ['Telefonnummer', _telefonMobilController.text],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields.where((f) => f[1].isNotEmpty).map((f) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  f[0],
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
                ),
              ),
              Expanded(
                child: Text(
                  f[1],
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: F.h(Colors.green, 800)),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStufe3ReadOnlyContent() {
    final zahlungsLabels = {
      'ueberweisung': 'Überweisung',
      'sepa_lastschrift': 'SEPA-Lastschrift',
      'dauerauftrag': 'Dauerauftrag',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedZahlungsmethode != null && _selectedZahlungsmethode!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text('Zahlungsmethode', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
                ),
                Icon(Icons.payment, size: 16, color: F.h(Colors.green, 700)),
                const SizedBox(width: 6),
                Text(
                  zahlungsLabels[_selectedZahlungsmethode] ?? _selectedZahlungsmethode!,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: F.h(Colors.green, 800)),
                ),
              ],
            ),
          ),
        if (_selectedZahlungstag != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text('Zahlungstag', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
                ),
                Icon(Icons.calendar_today, size: 16, color: F.h(Colors.green, 700)),
                const SizedBox(width: 6),
                Text(
                  '$_selectedZahlungstag. des Monats',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: F.h(Colors.green, 800)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStufe1EditContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _stufeTextField(_vornameController, 'Vorname'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _stufeTextField(_nachnameController, 'Nachname'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Geburtsdatum picker
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedGeburtsdatum ?? DateTime(1990),
              firstDate: DateTime(1920),
              lastDate: DateTime.now(),
              locale: const Locale('de'),
            );
            if (picked != null) {
              setState(() => _selectedGeburtsdatum = picked);
            }
          },
          child: AbsorbPointer(
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Geburtsdatum',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                prefixIcon: const Icon(Icons.cake, size: 18),
              ),
              style: const TextStyle(fontSize: 13),
              controller: TextEditingController(
                text: _selectedGeburtsdatum != null
                    ? '${_selectedGeburtsdatum!.day.toString().padLeft(2, '0')}.${_selectedGeburtsdatum!.month.toString().padLeft(2, '0')}.${_selectedGeburtsdatum!.year}'
                    : '',
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // Ohne `isExpanded` richtet sich ein Dropdown nach seinem
          // breitesten Eintrag, nicht nach dem Feld. Ein langer Name
          // sprengte damit die Zeile — gemessen 241 dp in
          // ordnungsmassnahmen_screen. Als Formularfeld soll es
          // ohnehin die volle Breite haben.
          isExpanded: true,
          initialValue: _selectedGeschlechtStufe1,
          decoration: InputDecoration(
            labelText: 'Geschlecht',
            prefixIcon: const Icon(Icons.wc, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'M', child: Text('M – männlich')),
            DropdownMenuItem(value: 'W', child: Text('W – weiblich')),
            DropdownMenuItem(value: 'D', child: Text('D – divers')),
          ],
          onChanged: (v) => setState(() => _selectedGeschlechtStufe1 = v ?? 'M'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _stufeTextField(_strasseController, 'Straße'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _stufeTextField(_hausnummerController, 'Nr.'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _stufeTextField(_plzController, 'PLZ'),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _stufeTextField(_ortController, 'Ort'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _stufeTextField(_telefonMobilController, 'Telefonnummer'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _isSavingStufe1 ? null : _saveStufe1,
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

  Widget _stufeTextField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _buildStufe3EditContent() {
    final zahlungsLabels = {
      'ueberweisung': 'Überweisung',
      'sepa_lastschrift': 'SEPA-Lastschrift',
      'dauerauftrag': 'Dauerauftrag',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Zahlungsmethode
        if (_selectedZahlungsmethode != null && _selectedZahlungsmethode!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: F.h(Colors.green, 50),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.payment, color: F.h(Colors.green, 700), size: 20),
                const SizedBox(width: 8),
                Text(
                  zahlungsLabels[_selectedZahlungsmethode] ?? _selectedZahlungsmethode!,
                  style: TextStyle(fontWeight: FontWeight.bold, color: F.h(Colors.green, 700)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selectedZahlungsmethode = null),
                  child: const Text('Ändern', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          )
        else ...[
          Text('Keine Zahlungsmethode gewählt.', style: TextStyle(color: Colors.red.shade400, fontStyle: FontStyle.italic, fontSize: 13)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Zahlungsmethode auswählen',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: zahlungsLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: _isSavingStufe3 ? null : (value) {
              if (value != null) _saveStufe3(zahlungsmethode: value);
            },
          ),
        ],

        const SizedBox(height: 12),

        // Zahlungstag
        Text(
          'Zahlungstag (monatliche Erinnerung)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700)),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _selectedZahlungstag,
                decoration: InputDecoration(
                  labelText: 'Tag des Monats',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixIcon: const Icon(Icons.calendar_today, size: 18),
                ),
                items: List.generate(31, (i) => i + 1)
                    .map((day) => DropdownMenuItem(value: day, child: Text('$day.')))
                    .toList(),
                onChanged: _isSavingStufe3 ? null : (value) {
                  if (value != null) _saveStufe3(zahlungstag: value);
                },
              ),
            ),
          ],
        ),
        if (_selectedZahlungstag != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Sie werden jeden $_selectedZahlungstag. des Monats an die Überweisung erinnert.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.blue, 600), fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  // ============= HELPER WIDGETS & METHODS =============

  Widget _buildNoDataTab(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: F.h(Colors.grey, 400)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: F.h(Colors.grey, 600)),
          ),
        ],
      ),
    );
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

  IconData _getDeviceIcon(String platform) {
    final platformLower = platform.toLowerCase();
    if (platformLower.contains('windows')) return Icons.computer;
    if (platformLower.contains('android')) return Icons.phone_android;
    if (platformLower.contains('ios') || platformLower.contains('iphone')) return Icons.phone_iphone;
    if (platformLower.contains('mac')) return Icons.laptop_mac;
    if (platformLower.contains('linux')) return Icons.laptop;
    return Icons.devices;
  }

  String _formatLastSeen(dynamic lastSeen) {
    if (lastSeen == null) return 'Nie';
    try {
      final date = DateTime.parse(lastSeen.toString());
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inSeconds < 60) return 'Gerade eben';
      if (difference.inMinutes < 60) return 'vor ${difference.inMinutes} Min.';
      if (difference.inHours < 24) return 'vor ${difference.inHours} Std.';
      if (difference.inDays < 7) return 'vor ${difference.inDays} Tagen';
      return '${date.day}.${date.month}.${date.year}';
    } catch (e) {
      return lastSeen.toString();
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

  Widget _buildIpReputationBadge(dynamic reputation) {
    if (reputation == null) return const SizedBox.shrink();
    final isClean = reputation['clean'] == true;
    return Tooltip(
      message: isClean
          ? 'IP sauber - nicht gelistet'
          : 'Blacklisted: ${(reputation['blacklists'] as List?)?.join(', ') ?? ''}',
      child: Icon(
        isClean ? Icons.verified_user : Icons.warning,
        size: 16,
        color: isClean ? Colors.green : Colors.red,
      ),
    );
  }

  IconData _getConnectionTypeIcon(String? type) {
    switch (type) {
      case 'Mobilfunk': return Icons.cell_tower;
      case 'DSL': return Icons.router;
      case 'Kabel': return Icons.cable;
      case 'Server':
      case 'Cloud': return Icons.cloud;
      default: return Icons.wifi;
    }
  }

  Color _getConnectionTypeColor(String? type) {
    switch (type) {
      case 'Mobilfunk': return Colors.orange;
      case 'DSL': return Colors.blue;
      case 'Kabel': return Colors.green;
      case 'Server':
      case 'Cloud': return Colors.purple;
      default: return Colors.grey;
    }
  }

  // Verwarnungen helpers
  MaterialColor _getTypColor(String typ) {
    switch (typ) {
      case 'ermahnung': return Colors.amber;
      case 'abmahnung': return Colors.orange;
      case 'letzte_abmahnung': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getTypIcon(String typ) {
    switch (typ) {
      case 'ermahnung': return Icons.info_outline;
      case 'abmahnung': return Icons.warning_amber;
      case 'letzte_abmahnung': return Icons.gavel;
      default: return Icons.warning;
    }
  }

  // Dokumente helpers
  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
      case 'odt': return Icons.article;
      case 'xls':
      case 'xlsx':
      case 'ods': return Icons.table_chart;
      case 'jpg':
      case 'jpeg':
      case 'png': return Icons.image;
      case 'txt': return Icons.text_snippet;
      default: return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf': return Colors.red.shade700;
      case 'doc':
      case 'docx':
      case 'odt': return Colors.blue.shade700;
      case 'xls':
      case 'xlsx':
      case 'ods': return Colors.green.shade700;
      case 'jpg':
      case 'jpeg':
      case 'png': return Colors.purple.shade700;
      case 'txt': return Colors.grey.shade700;
      default: return Colors.blueGrey.shade700;
    }
  }

  // Verifizierung helpers
  String _stufeName(int stufe) {
    switch (stufe) {
      case 1: return 'Persönliche Daten';
      case 2: return 'Mitgliedsart';
      case 3: return 'Zahlungsmethode';
      case 4: return 'Satzung';
      case 5: return 'Datenschutz';
      case 6: return 'Widerrufsbelehrung';
      default: return 'Stufe $stufe';
    }
  }

  IconData _stufeIcon(int stufe) {
    switch (stufe) {
      case 1: return Icons.person;
      case 2: return Icons.groups;
      case 3: return Icons.payment;
      case 4: return Icons.gavel;
      case 5: return Icons.privacy_tip;
      case 6: return Icons.assignment_return;
      default: return Icons.check_circle;
    }
  }

  Color _verifizierungStatusColor(String status) {
    switch (status) {
      case 'geprueft': return Colors.green;
      case 'abgelehnt': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _verifizierungStatusText(String status) {
    switch (status) {
      case 'geprueft': return 'Geprüft';
      case 'abgelehnt': return 'Abgelehnt';
      default: return 'Offen';
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: F.h(Colors.grey, 600), size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
            ),
            phoneAwareText(icon, value,
              label: label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  /// Zeile „Gesprochene Sprachen" im Profil-Tab — Anzeige plus Stift.
  ///
  /// ⚠️ Bewusst hier und nicht im Verifizierungs-Tab: welche Sprachen jemand
  /// spricht, ist keine zu prüfende Identitätsangabe wie Geburtsdatum oder
  /// Staatsangehörigkeit. Läge sie in Stufe 1, wäre sie nach `status =
  /// 'geprueft'` gesperrt — dieselbe Falle, die schon bei der App-Sprache
  /// aufgetreten ist. Sprachkenntnisse ändern sich, Geburtsdaten nicht.
  Widget _buildSprachenRow() {
    final anzeigen = sprachAnzeigen(_languages);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.translate, color: F.h(Colors.grey, 600), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gesprochene Sprachen',
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
              ),
              const SizedBox(height: 4),
              if (anzeigen.isEmpty)
                Text(
                  'Noch keine hinterlegt',
                  style: TextStyle(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: F.h(Colors.grey, 500),
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in anzeigen)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        label: Text(
                          // Flagge nur als Beiwerk — das Kürzel und der Name
                          // tragen die Information, siehe sprach_flaggen.dart.
                          s.flagge != null
                              ? '${s.flagge}  ${s.bezeichnung}'
                              : s.bezeichnung,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        IconButton(
          icon: _isSavingSprachen
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.edit, size: 20),
          tooltip: 'Sprachen bearbeiten',
          onPressed: _isSavingSprachen ? null : _openSprachenDialog,
        ),
      ],
    );
  }

  Future<void> _openSprachenDialog() async {
    final auswahl = await showDialog<List<String>>(
      context: context,
      builder: (_) => _SprachenAuswahlDialog(vorauswahl: _languages),
    );
    if (auswahl == null || !mounted) return;

    setState(() => _isSavingSprachen = true);
    try {
      // Nur `languages` senden. update_profile.php schreibt ausschließlich die
      // Felder, die im Request stehen — ein Vollbild-Update würde hier die
      // Adressfelder mit dem überschreiben, was der Dialog gerade geladen hat.
      final r = await widget.apiService.updateProfile(
        mitgliedernummer: widget.mitgliedernummer,
        languages: auswahl,
      );
      if (!mounted) return;
      if (r['success'] == true) {
        setState(() {
          _languages = auswahl;
          _isSavingSprachen = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sprachen gespeichert')),
        );
      } else {
        setState(() => _isSavingSprachen = false);
        // ⚠️ Der Grund muss auf den Schirm. Ein stiller Fehlschlag sähe für den
        // Nutzer genauso aus wie „ich habe daneben getippt" — dieselbe Falle
        // wie zuletzt bei den Chat-Reaktionen.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nicht gespeichert: ${r['message'] ?? 'unbekannter Fehler'}',
            ),
          ),
        );
      }
    } catch (e) {
      LoggerService().error('Sprachen speichern: $e', tag: 'ProfileDialog');
      if (!mounted) return;
      setState(() => _isSavingSprachen = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nicht gespeichert: $e')),
      );
    }
  }

  Widget _buildChangeEmailForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: F.h(Colors.grey, 100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'E-Mail ändern',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() {
                  _isChangingEmail = false;
                  _newEmailController.clear();
                  _emailPasswordController.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newEmailController,
            decoration: InputDecoration(
              labelText: 'Neue E-Mail-Adresse',
              prefixIcon: const Icon(Icons.email),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: F.flaeche,
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailPasswordController,
            obscureText: _obscureEmailPassword,
            decoration: InputDecoration(
              labelText: 'Aktuelles Passwort',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_obscureEmailPassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureEmailPassword = !_obscureEmailPassword),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: F.flaeche,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _changeEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a90d9),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('E-Mail speichern'),
          ),
        ],
      ),
    );
  }

  Widget _buildChangePasswordForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: F.h(Colors.grey, 100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Passwort ändern',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() {
                  _isChangingPassword = false;
                  _currentPasswordController.clear();
                  _newPasswordController.clear();
                  _confirmPasswordController.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currentPasswordController,
            obscureText: _obscureCurrentPassword,
            decoration: InputDecoration(
              labelText: 'Aktuelles Passwort',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureCurrentPassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureCurrentPassword = !_obscureCurrentPassword),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: F.flaeche,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPasswordController,
            obscureText: _obscureNewPassword,
            decoration: InputDecoration(
              labelText: 'Neues Passwort',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_obscureNewPassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: F.flaeche,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Passwort bestätigen',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: F.flaeche,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a90d9),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Passwort speichern'),
          ),
        ],
      ),
    );
  }

  Widget _buildChangePhoneForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: F.h(Colors.grey, 100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Telefonnummer',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() {
                  _isChangingPhone = false;
                  _countryCodeController.text = '+49';
                  _phoneNumberController.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Country Code
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _countryCodeController,
                  decoration: InputDecoration(
                    labelText: 'Code',
                    prefixIcon: const Icon(Icons.flag, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: F.flaeche,
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 12),
              // Phone Number
              Expanded(
                child: TextField(
                  controller: _phoneNumberController,
                  decoration: InputDecoration(
                    labelText: 'Telefonnummer',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: F.flaeche,
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _savePhone,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a90d9),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Speichern'),
          ),
        ],
      ),
    );
  }

}

/// Auswahl der gesprochenen Sprachen.
///
/// ⚠️ Angeboten werden genau die 28 Codes aus [appSprachCodes], nicht die 170
/// aus [alleSprachen]. Grund ist nicht Bequemlichkeit: `users.languages` ist
/// zwar ein freies TEXT-Feld, aber alles, was der Verein mit einer Sprache
/// anfangen kann — Chatübersetzung, SMS-Vorlagen, Briefe — hängt an dieser
/// Liste von 28. Eine Sprache anzubieten, für die es nichts davon gibt, würde
/// eine Fähigkeit versprechen, die das Programm nicht hat.
///
/// Die häufigen Vereinssprachen stehen oben, der Rest alphabetisch — bei 28
/// Einträgen ist Scrollen sonst der Regelfall statt der Ausnahme.
class _SprachenAuswahlDialog extends StatefulWidget {
  final List<String> vorauswahl;

  const _SprachenAuswahlDialog({required this.vorauswahl});

  @override
  State<_SprachenAuswahlDialog> createState() => _SprachenAuswahlDialogState();
}

class _SprachenAuswahlDialogState extends State<_SprachenAuswahlDialog> {
  late final Set<String> _gewaehlt = {...widget.vorauswahl};

  /// Die im Verein häufigen Sprachen zuerst, danach alphabetisch nach dem
  /// deutschen Namen.
  static final List<String> _sortiert = () {
    const oben = ['de', 'ro', 'ru', 'uk', 'en', 'tr', 'ar'];
    final rest = appSprachCodes.where((c) => !oben.contains(c)).toList()
      ..sort((a, b) => appSprachBezeichnung(a).compareTo(appSprachBezeichnung(b)));
    return [...oben, ...rest];
  }();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gesprochene Sprachen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Erscheint auf der Visitenkarte. Die Reihenfolge dort ist die '
              'Reihenfolge der Auswahl hier.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final code in _sortiert) _chip(code),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          // Aus der Menge wieder eine Liste in stabiler Reihenfolge machen:
          // `Set` garantiert in Dart zwar Einfügereihenfolge, aber die
          // Vorauswahl kam bereits sortiert an — hier zählt die Reihenfolge
          // der Liste oben, damit die Karte reproduzierbar aussieht.
          onPressed: () => Navigator.pop(
            context,
            _sortiert.where(_gewaehlt.contains).toList(),
          ),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }

  Widget _chip(String code) {
    final a = sprachAnzeige(code);
    final aktiv = _gewaehlt.contains(code);
    return FilterChip(
      selected: aktiv,
      // 44 dp Trefferfläche (WCAG 2.5.5) — in einem Verein, dessen Vorstand
      // mehrheitlich aus Menschen mit Behinderung besteht, keine Feinheit.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      label: Text(a.flagge != null ? '${a.flagge}  ${a.bezeichnung}' : a.bezeichnung),
      onSelected: (an) => setState(() {
        if (an) {
          _gewaehlt.add(code);
        } else {
          _gewaehlt.remove(code);
        }
      }),
    );
  }
}
