import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otp/otp.dart';
import '../utils/clipboard_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../widgets/file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';

class MicrosoftNonprofitScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const MicrosoftNonprofitScreen({
    super.key,
    required this.apiService,
    required this.onBack,
  });

  @override
  State<MicrosoftNonprofitScreen> createState() => _MicrosoftNonprofitScreenState();
}

class _MicrosoftNonprofitScreenState extends State<MicrosoftNonprofitScreen> {
  bool _isEditing = false;
  bool _passwordVisible = false;
  bool _isLoading = true;
  bool _isSaving = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _totpSecretController = TextEditingController();
  String _website = 'https://nonprofit.microsoft.com/';

  // 2FA / TOTP state
  String _currentTotpCode = '';
  int _totpSecondsRemaining = 30;
  String? _totpError;
  Timer? _totpTimer;

  // Korrespondenz state (Eingang / Ausgang tabs)
  static const String _platformId = 'microsoft-nonprofit';
  String _korrTab = 'eingang'; // 'eingang' | 'ausgang'
  List<Map<String, dynamic>> _korrEingang = [];
  List<Map<String, dynamic>> _korrAusgang = [];
  bool _korrLoading = false;
  final Set<int> _korrExpanded = <int>{};

  // Aufgaben
  List<Map<String, dynamic>> _aufgaben = [];

  // Notizen
  List<Map<String, dynamic>> _notizen = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadCredentials(),
      _loadAufgaben(),
      _loadNotizen(),
      _loadKorrespondenz(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadCredentials() async {
    try {
      final result = await widget.apiService.getPlatformCredentials('microsoft-nonprofit');
      if (result['success'] == true && result['credentials'] != null) {
        final creds = result['credentials'];
        _emailController.text = creds['email'] ?? '';
        _passwordController.text = creds['password'] ?? '';
        _totpSecretController.text = creds['totp_secret'] ?? '';
        _website = creds['website'] ?? 'https://nonprofit.microsoft.com/';
        _refreshTotpCode();
        _ensureTotpTimer();
      }
    } catch (_) {}
  }

  // ====================================================================
  // 2FA / TOTP — RFC 6238, 30s window, 6 digits, SHA-1, Base32 secret
  // ====================================================================

  /// Normalize a Base32 secret: strip whitespace, force uppercase. Spaces are
  /// commonly present when copy-pasting from setup screens (e.g. "JBSW Y3DP").
  String _normalizeSecret(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  /// Generate the current TOTP code using the package `otp` (Base32 → HMAC-SHA1).
  /// Returns null if the secret is invalid (not Base32).
  String? _generateTotp(String secret) {
    final clean = _normalizeSecret(secret);
    if (clean.isEmpty) return null;
    try {
      return OTP.generateTOTPCodeString(
        clean,
        DateTime.now().millisecondsSinceEpoch,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Recompute current code + remaining seconds in the 30s window.
  void _refreshTotpCode() {
    final secret = _totpSecretController.text;
    if (secret.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _currentTotpCode = '';
          _totpError = null;
          _totpSecondsRemaining = 30;
        });
      }
      return;
    }
    final code = _generateTotp(secret);
    final epochSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = 30 - (epochSec % 30);
    if (mounted) {
      setState(() {
        if (code == null) {
          _currentTotpCode = '';
          _totpError = 'Ungültiger Base32-Schlüssel';
        } else {
          _currentTotpCode = code;
          _totpError = null;
        }
        _totpSecondsRemaining = remaining;
      });
    }
  }

  /// Start the 1Hz refresh timer (idempotent — safe to call repeatedly).
  void _ensureTotpTimer() {
    _totpTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _refreshTotpCode());
  }

  Future<void> _loadAufgaben() async {
    try {
      final result = await widget.apiService.getPlatformAufgaben('microsoft-nonprofit');
      if (result['success'] == true && result['aufgaben'] != null) {
        _aufgaben = List<Map<String, dynamic>>.from(result['aufgaben']);
      }
    } catch (_) {}
  }

  Future<void> _loadNotizen() async {
    try {
      final result = await widget.apiService.getPlatformNotizen('microsoft-nonprofit');
      if (result['success'] == true && result['notizen'] != null) {
        _notizen = List<Map<String, dynamic>>.from(result['notizen']);
      }
    } catch (_) {}
  }

  Future<void> _saveCredentials() async {
    setState(() => _isSaving = true);
    try {
      final result = await widget.apiService.savePlatformCredentials(
        platform: 'microsoft-nonprofit',
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        website: _website,
        // Always send the TOTP secret (normalized) so the server stores
        // it consistently. Empty string = explicit clear.
        totpSecret: _normalizeSecret(_totpSecretController.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['success'] == true
                ? 'Zugangsdaten gespeichert (verschlüsselt)'
                : 'Fehler: ${result['message'] ?? 'Unbekannter Fehler'}'),
            backgroundColor: result['success'] == true ? Colors.green : Colors.red,
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
    if (mounted) setState(() => _isSaving = false);
  }

  void _copyToClipboard(String text, String label) {
    ClipboardHelper.copy(context, text, label);
  }

  Future<void> _openWebsite() async {
    final uri = Uri.parse(_website);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Website konnte nicht geöffnet werden'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== Aufgaben CRUD ====================

  Future<void> _showCreateAufgabeDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final titelController = TextEditingController();
    final beschreibungController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.add_task, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Text('Neue Aufgabe'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titelController,
                  decoration: const InputDecoration(
                    labelText: 'Titel *',
                    hintText: 'z.B. Microsoft 365 Lizenz beantragen',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: beschreibungController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Beschreibung (optional)',
                    hintText: 'Details zur Aufgabe...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                            locale: const Locale('de'),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Fällig am',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(DateFormat('dd.MM.yyyy').format(selectedDate)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setDialogState(() => selectedTime = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Uhrzeit',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.access_time, size: 18),
                          ),
                          child: Text('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (titelController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Bitte Titel eingeben'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Erstellen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final faelligAm = DateTime(
        selectedDate.year, selectedDate.month, selectedDate.day,
        selectedTime.hour, selectedTime.minute,
      );
      final faelligStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(faelligAm);

      final res = await widget.apiService.createPlatformAufgabe(
        platform: 'microsoft-nonprofit',
        titel: titelController.text.trim(),
        faelligAm: faelligStr,
        beschreibung: beschreibungController.text.trim().isEmpty ? null : beschreibungController.text.trim(),
      );

      if (mounted) {
        if (res['success'] == true) {
          await _loadAufgaben();
          setState(() {});
          messenger.showSnackBar(
            const SnackBar(content: Text('Aufgabe erstellt'), backgroundColor: Colors.green),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text('Fehler: ${res['message']}'), backgroundColor: Colors.red),
          );
        }
      }
    }
    titelController.dispose();
    beschreibungController.dispose();
  }

  Future<void> _toggleAufgabe(Map<String, dynamic> aufgabe) async {
    final newErledigt = !(aufgabe['erledigt'] as bool);
    final res = await widget.apiService.updatePlatformAufgabe({
      'id': aufgabe['id'],
      'erledigt': newErledigt ? 1 : 0,
    });
    if (res['success'] == true && mounted) {
      await _loadAufgaben();
      setState(() {});
    }
  }

  Future<void> _deleteAufgabe(int id) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufgabe löschen?'),
        content: const Text('Diese Aufgabe wird unwiderruflich gelöscht.'),
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
    if (confirmed == true) {
      final res = await widget.apiService.deletePlatformAufgabe(id);
      if (res['success'] == true && mounted) {
        await _loadAufgaben();
        setState(() {});
        messenger.showSnackBar(
          const SnackBar(content: Text('Aufgabe gelöscht'), backgroundColor: Colors.green),
        );
      }
    }
  }

  String _formatFaelligAm(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd.MM.yyyy, HH:mm').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  bool _isOverdue(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return dt.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  // ==================== Notizen CRUD ====================

  Future<void> _showCreateNotizDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final inhaltController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.note_add, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Text('Neue Notiz'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: inhaltController,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Notiz *',
              hintText: 'Notiz eingeben...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (inhaltController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Bitte Notiz eingeben'), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Erstellen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      final res = await widget.apiService.createPlatformNotiz(
        platform: 'microsoft-nonprofit',
        inhalt: inhaltController.text.trim(),
      );
      if (mounted) {
        if (res['success'] == true) {
          await _loadNotizen();
          setState(() {});
          messenger.showSnackBar(
            const SnackBar(content: Text('Notiz erstellt'), backgroundColor: Colors.green),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text('Fehler: ${res['message']}'), backgroundColor: Colors.red),
          );
        }
      }
    }
    inhaltController.dispose();
  }

  Future<void> _deleteNotiz(int id) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notiz löschen?'),
        content: const Text('Diese Notiz wird unwiderruflich gelöscht.'),
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
    if (confirmed == true) {
      final res = await widget.apiService.deletePlatformNotiz(id);
      if (res['success'] == true && mounted) {
        await _loadNotizen();
        setState(() {});
        messenger.showSnackBar(
          const SnackBar(content: Text('Notiz gelöscht'), backgroundColor: Colors.green),
        );
      }
    }
  }

  String _formatNotizDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd.MM.yyyy, HH:mm').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  // ==================== Build ====================

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
              Icon(Icons.window, size: 32, color: Colors.orange.shade800),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Microsoft for Nonprofits',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: _isSaving
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        _isEditing ? Icons.check_circle : Icons.settings,
                        color: _isEditing ? Colors.green : Colors.grey,
                      ),
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (_isEditing) {
                          await _saveCredentials();
                        }
                        setState(() => _isEditing = !_isEditing);
                      },
                tooltip: _isEditing ? 'Speichern' : 'Bearbeiten',
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Zugangsdaten Card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Microsoft-Produkte kostenlos oder vergünstigt für gemeinnützige Organisationen',
                                  style: TextStyle(fontSize: 16, color: Colors.grey, fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(height: 24),

                                // Website
                                Row(
                                  children: [
                                    const Icon(Icons.link, size: 20, color: Colors.grey),
                                    const SizedBox(width: 12),
                                    const Text('Website: ', style: TextStyle(fontWeight: FontWeight.w500)),
                                    Expanded(
                                      child: SelectableText(
                                        _website,
                                        style: const TextStyle(color: Colors.blue),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 18),
                                      onPressed: () => _copyToClipboard(_website, 'Website'),
                                      tooltip: 'Kopieren',
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.open_in_new, size: 18, color: Colors.blue.shade700),
                                      onPressed: _openWebsite,
                                      tooltip: 'Website öffnen',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Email
                                Row(
                                  children: [
                                    const Icon(Icons.email, size: 20, color: Colors.grey),
                                    const SizedBox(width: 12),
                                    const Text('E-Mail: ', style: TextStyle(fontWeight: FontWeight.w500)),
                                    Expanded(
                                      child: _isEditing
                                          ? TextField(
                                              controller: _emailController,
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                            )
                                          : SelectableText(
                                              _emailController.text.isEmpty ? '(nicht gesetzt)' : _emailController.text,
                                              style: TextStyle(
                                                color: _emailController.text.isEmpty ? Colors.grey : null,
                                                fontStyle: _emailController.text.isEmpty ? FontStyle.italic : null,
                                              ),
                                            ),
                                    ),
                                    if (_emailController.text.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 18),
                                        onPressed: () => _copyToClipboard(_emailController.text, 'E-Mail'),
                                        tooltip: 'Kopieren',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Password
                                Row(
                                  children: [
                                    const Icon(Icons.lock, size: 20, color: Colors.grey),
                                    const SizedBox(width: 12),
                                    const Text('Passwort: ', style: TextStyle(fontWeight: FontWeight.w500)),
                                    Expanded(
                                      child: _isEditing
                                          ? TextField(
                                              controller: _passwordController,
                                              obscureText: !_passwordVisible,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                border: const OutlineInputBorder(),
                                                suffixIcon: IconButton(
                                                  icon: Icon(_passwordVisible ? Icons.visibility_off : Icons.visibility, size: 18),
                                                  onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                                                ),
                                              ),
                                            )
                                          : SelectableText(
                                              _passwordController.text.isEmpty
                                                  ? '(nicht gesetzt)'
                                                  : _passwordVisible
                                                      ? _passwordController.text
                                                      : '\u2022' * 12,
                                              style: TextStyle(
                                                color: _passwordController.text.isEmpty ? Colors.grey : null,
                                                fontStyle: _passwordController.text.isEmpty ? FontStyle.italic : null,
                                              ),
                                            ),
                                    ),
                                    if (!_isEditing && _passwordController.text.isNotEmpty)
                                      IconButton(
                                        icon: Icon(_passwordVisible ? Icons.visibility_off : Icons.visibility, size: 18),
                                        onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                                        tooltip: _passwordVisible ? 'Verbergen' : 'Anzeigen',
                                      ),
                                    if (_passwordController.text.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 18),
                                        onPressed: () => _copyToClipboard(_passwordController.text, 'Passwort'),
                                        tooltip: 'Kopieren',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Encryption info
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.shield, size: 16, color: Colors.green.shade700),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Zugangsdaten werden AES-256 verschlüsselt in der Datenbank gespeichert',
                                        style: TextStyle(fontSize: 11, color: Colors.green.shade800),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ==================== 2FA / TOTP Card ====================
                        _build2FACard(),

                        const SizedBox(height: 16),

                        // ==================== Korrespondenz Card ====================
                        _buildKorrespondenzCard(),

                        const SizedBox(height: 16),

                        // ==================== Aufgaben Card ====================
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.task_alt, color: Colors.orange.shade700, size: 24),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Aufgaben',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                      ),
                                    ),
                                    if (_aufgaben.where((a) => !(a['erledigt'] as bool)).isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${_aufgaben.where((a) => !(a['erledigt'] as bool)).length} offen',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.add_circle, color: Colors.orange.shade700, size: 28),
                                      onPressed: _showCreateAufgabeDialog,
                                      tooltip: 'Neue Aufgabe',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Unterlagen und Fristen für Microsoft for Nonprofits',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(height: 16),

                                if (_aufgaben.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    alignment: Alignment.center,
                                    child: Column(
                                      children: [
                                        Icon(Icons.checklist, size: 48, color: Colors.grey.shade300),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Keine Aufgaben vorhanden',
                                          style: TextStyle(color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  ...List.generate(_aufgaben.length, (i) {
                                    final aufgabe = _aufgaben[i];
                                    final erledigt = aufgabe['erledigt'] as bool;
                                    final overdue = !erledigt && _isOverdue(aufgabe['faellig_am']);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: erledigt
                                            ? Colors.green.shade50
                                            : overdue
                                                ? Colors.red.shade50
                                                : Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: erledigt
                                              ? Colors.green.shade200
                                              : overdue
                                                  ? Colors.red.shade300
                                                  : Colors.orange.shade200,
                                        ),
                                      ),
                                      child: ListTile(
                                        leading: IconButton(
                                          icon: Icon(
                                            erledigt ? Icons.check_circle : Icons.radio_button_unchecked,
                                            color: erledigt ? Colors.green.shade700 : Colors.orange.shade600,
                                            size: 28,
                                          ),
                                          onPressed: () => _toggleAufgabe(aufgabe),
                                          tooltip: erledigt ? 'Als offen markieren' : 'Als erledigt markieren',
                                        ),
                                        title: Text(
                                          aufgabe['titel'],
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            decoration: erledigt ? TextDecoration.lineThrough : null,
                                            color: erledigt ? Colors.grey : null,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if ((aufgabe['beschreibung'] ?? '').isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Text(
                                                  aufgabe['beschreibung'],
                                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                                ),
                                              ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.schedule,
                                                  size: 14,
                                                  color: overdue ? Colors.red.shade700 : Colors.grey.shade600,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _formatFaelligAm(aufgabe['faellig_am']),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: overdue ? FontWeight.bold : null,
                                                    color: overdue ? Colors.red.shade700 : Colors.grey.shade600,
                                                  ),
                                                ),
                                                if (overdue) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.shade100,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'Überfällig',
                                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                                                    ),
                                                  ),
                                                ],
                                                if (erledigt && aufgabe['erledigt_am'] != null) ...[
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Erledigt: ${_formatFaelligAm(aufgabe['erledigt_am'])}',
                                                    style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                        trailing: IconButton(
                                          icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                                          onPressed: () => _deleteAufgabe(aufgabe['id'] as int),
                                          tooltip: 'Löschen',
                                        ),
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ==================== Notizen Card ====================
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.sticky_note_2, color: Colors.teal.shade700, size: 24),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Notizen',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                      ),
                                    ),
                                    if (_notizen.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${_notizen.length}',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.note_add, color: Colors.teal.shade700, size: 28),
                                      onPressed: _showCreateNotizDialog,
                                      tooltip: 'Neue Notiz',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Interne Notizen zu Microsoft for Nonprofits',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(height: 16),

                                if (_notizen.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    alignment: Alignment.center,
                                    child: Column(
                                      children: [
                                        Icon(Icons.sticky_note_2_outlined, size: 48, color: Colors.grey.shade300),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Keine Notizen vorhanden',
                                          style: TextStyle(color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  ...List.generate(_notizen.length, (i) {
                                    final notiz = _notizen[i];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.teal.shade200),
                                      ),
                                      child: ListTile(
                                        leading: Icon(Icons.note, color: Colors.teal.shade600, size: 24),
                                        title: Text(
                                          notiz['inhalt'],
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            _formatNotizDate(notiz['created_at']),
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                        ),
                                        trailing: IconButton(
                                          icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                                          onPressed: () => _deleteNotiz(notiz['id'] as int),
                                          tooltip: 'Löschen',
                                        ),
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Benefits Card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.card_giftcard, color: Colors.orange.shade800, size: 20),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Vorteile für Vereine',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    '\u2713 Microsoft 365 Business Premium kostenlos\n'
                                    '\u2713 Azure Credits (\$3.500/Jahr für Cloud-Dienste)\n'
                                    '\u2713 Dynamics 365 für Vereinsverwaltung\n'
                                    '\u2713 Power BI Pro für Datenanalyse\n'
                                    '\u2713 Windows Server & SQL Server Lizenzen',
                                    style: TextStyle(fontSize: 14, height: 1.8),
                                  ),
                                ],
                              ),
                            ),
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

  // ====================================================================
  // 2FA / TOTP Card
  // ====================================================================
  Widget _build2FACard() {
    final hasSecret = _totpSecretController.text.trim().isNotEmpty;
    final formattedCode = _currentTotpCode.length == 6
        ? '${_currentTotpCode.substring(0, 3)} ${_currentTotpCode.substring(3)}'
        : '------';
    final progress = _totpSecondsRemaining / 30.0;
    final urgentColor = _totpSecondsRemaining <= 5;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.indigo.shade700, size: 24),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Zwei-Faktor-Authentifizierung (2FA)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                if (hasSecret && !_isEditing && _currentTotpCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Aktiv',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'TOTP-Code (RFC 6238) wird alle 30 Sekunden neu generiert',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),

            if (_isEditing) ...[
              // ===== EDIT MODE =====
              TextField(
                controller: _totpSecretController,
                decoration: InputDecoration(
                  labelText: '2FA Schlüssel (Base32)',
                  hintText: 'z.B. JBSWY3DPEHPK3PXP',
                  helperText: 'Aus Microsoft Account-Einrichtung kopieren (Leerzeichen werden ignoriert)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.vpn_key),
                  suffixIcon: _totpSecretController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Löschen',
                          onPressed: () {
                            setState(() {
                              _totpSecretController.clear();
                              _currentTotpCode = '';
                              _totpError = null;
                            });
                          },
                        )
                      : null,
                ),
                style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5),
                onChanged: (_) => _refreshTotpCode(),
              ),
              if (_totpError != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text(_totpError!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                  ],
                ),
              ],
            ] else ...[
              // ===== READ MODE =====
              if (!hasSecret)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Kein 2FA-Schlüssel konfiguriert. Auf Bearbeiten klicken, um einen Schlüssel hinzuzufügen.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade200, width: 2),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Aktueller Code',
                                  style: TextStyle(fontSize: 12, color: Colors.indigo.shade700, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formattedCode,
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    letterSpacing: 4,
                                    color: _totpError != null
                                        ? Colors.red.shade700
                                        : (urgentColor ? Colors.orange.shade700 : Colors.indigo.shade900),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_currentTotpCode.isNotEmpty)
                            Column(
                              children: [
                                SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        value: progress,
                                        strokeWidth: 4,
                                        backgroundColor: Colors.indigo.shade100,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          urgentColor ? Colors.orange.shade700 : Colors.indigo.shade600,
                                        ),
                                      ),
                                      Text(
                                        '$_totpSecondsRemaining',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: urgentColor ? Colors.orange.shade700 : Colors.indigo.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('Sek.', style: TextStyle(fontSize: 10, color: Colors.indigo.shade700)),
                              ],
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 22),
                            color: Colors.indigo.shade700,
                            tooltip: 'Code kopieren',
                            onPressed: _currentTotpCode.isEmpty
                                ? null
                                : () => _copyToClipboard(_currentTotpCode, '2FA Code'),
                          ),
                        ],
                      ),
                    ),
                    if (_totpError != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Text(_totpError!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                        ],
                      ),
                    ],
                  ],
                ),
            ],
            const SizedBox(height: 12),

            // Encryption info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '2FA-Schlüssel wird AES-256 verschlüsselt in der Datenbank gespeichert',
                      style: TextStyle(fontSize: 11, color: Colors.green.shade800),
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

  // ====================================================================
  // Korrespondenz — Eingang / Ausgang persisted server-side
  // ====================================================================

  Future<void> _loadKorrespondenz() async {
    try {
      final results = await Future.wait([
        widget.apiService.getPlatformKorrespondenz(platform: _platformId, direction: 'eingang'),
        widget.apiService.getPlatformKorrespondenz(platform: _platformId, direction: 'ausgang'),
      ]);
      if (results[0]['success'] == true && results[0]['korrespondenz'] != null) {
        _korrEingang = List<Map<String, dynamic>>.from(results[0]['korrespondenz']);
      }
      if (results[1]['success'] == true && results[1]['korrespondenz'] != null) {
        _korrAusgang = List<Map<String, dynamic>>.from(results[1]['korrespondenz']);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _currentKorrList =>
      _korrTab == 'eingang' ? _korrEingang : _korrAusgang;

  Future<void> _showCreateKorrespondenzDialog() async {
    final betreffCtrl = TextEditingController();
    final inhaltCtrl = TextEditingController();
    final absenderCtrl = TextEditingController();
    final empfaengerCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    List<File> pickedFiles = [];
    bool saving = false;

    final isEingang = _korrTab == 'eingang';

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDState) => AlertDialog(
          title: Text(isEingang ? 'Neue Eingang-Mail' : 'Neue Ausgang-Mail'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date picker
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) {
                        setDState(() {
                          selectedDate = DateTime(picked.year, picked.month, picked.day,
                              selectedDate.hour, selectedDate.minute);
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Datum',
                        prefixIcon: Icon(Icons.calendar_today),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(DateFormat('dd.MM.yyyy').format(selectedDate)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: betreffCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Betreff *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.subject),
                    ),
                    maxLength: 500,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: isEingang ? absenderCtrl : empfaengerCtrl,
                    decoration: InputDecoration(
                      labelText: isEingang ? 'Absender' : 'Empfaenger',
                      hintText: isEingang ? 'z.B. nonprofit@microsoft.com' : 'z.B. support@microsoft.com',
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(isEingang ? Icons.mail : Icons.send),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: inhaltCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Inhalt',
                      hintText: 'Volltext der Nachricht (optional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 8,
                    minLines: 4,
                  ),
                  const SizedBox(height: 12),
                  // File picker
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.attach_file),
                        label: Text('Datei hinzufuegen (${pickedFiles.length})'),
                        onPressed: saving
                            ? null
                            : () async {
                                final files = await _pickFilesNative();
                                if (files.isNotEmpty) {
                                  setDState(() => pickedFiles.addAll(files));
                                }
                              },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'max 25 MB pro Datei',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  if (pickedFiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: pickedFiles.asMap().entries.map((e) {
                        final i = e.key;
                        final f = e.value;
                        final name = f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : 'datei';
                        return Chip(
                          label: Text(name, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: saving ? null : () => setDState(() => pickedFiles.removeAt(i)),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dctx, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(saving ? 'Speichern...' : 'Speichern'),
              onPressed: saving
                  ? null
                  : () async {
                      if (betreffCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(dctx).showSnackBar(
                          const SnackBar(content: Text('Betreff ist erforderlich')),
                        );
                        return;
                      }
                      setDState(() => saving = true);
                      final result = await widget.apiService.createPlatformKorrespondenz(
                        platform: _platformId,
                        direction: _korrTab,
                        betreff: betreffCtrl.text.trim(),
                        datum: selectedDate,
                        inhalt: inhaltCtrl.text.trim().isEmpty ? null : inhaltCtrl.text.trim(),
                        absender: isEingang ? absenderCtrl.text.trim() : null,
                        empfaenger: !isEingang ? empfaengerCtrl.text.trim() : null,
                        files: pickedFiles,
                      );
                      if (!dctx.mounted) return;
                      if (result['success'] == true) {
                        Navigator.pop(dctx, true);
                      } else {
                        setDState(() => saving = false);
                        ScaffoldMessenger.of(dctx).showSnackBar(
                          SnackBar(
                            content: Text('Fehler: ${result['message'] ?? 'Unbekannter Fehler'}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );

    betreffCtrl.dispose();
    inhaltCtrl.dispose();
    absenderCtrl.dispose();
    empfaengerCtrl.dispose();

    if (created == true) {
      await _loadKorrespondenz();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Korrespondenz gespeichert'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _deleteKorrespondenz(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Loeschen?'),
        content: const Text('Diese Korrespondenz und alle Anhaenge werden dauerhaft entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Abbrechen')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Loeschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await widget.apiService.deletePlatformKorrespondenz(id);
    if (!mounted) return;
    if (result['success'] == true) {
      await _loadKorrespondenz();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geloescht'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: ${result['message']}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openKorrespondenzAttachment(Map<String, dynamic> file) async {
    final fileId = file['id'] as int;
    final fileName = (file['datei_name'] as String?) ?? 'attachment';

    // Show a transient loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Text('Lade $fileName ...'),
        ]),
        duration: const Duration(seconds: 30),
      ),
    );

    final Uint8List? bytes = await widget.apiService.downloadPlatformKorrespondenzFile(fileId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datei konnte nicht geladen werden'), backgroundColor: Colors.red),
      );
      return;
    }

    final ext = fileName.toLowerCase().split('.').last;
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
    final isPdf = ext == 'pdf';

    if (isImage || isPdf) {
      // Both formats render directly from bytes via FileViewerDialog (PDF
      // uses PdfViewer.data, images use Image.memory).
      showDialog(
        context: context,
        builder: (_) => FileViewerDialog(fileBytes: bytes, fileName: fileName),
      );
    } else {
      // Other formats: best-effort hint, no in-app viewer.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ext.toUpperCase()} Format kann nicht direkt angezeigt werden'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _buildKorrespondenzCard() {
    final list = _currentKorrList;
    final isEingang = _korrTab == 'eingang';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.email, color: Colors.teal.shade700, size: 24),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Korrespondenz',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle, color: Colors.teal.shade700, size: 28),
                  onPressed: _showCreateKorrespondenzDialog,
                  tooltip: 'Neue ${isEingang ? "Eingang" : "Ausgang"}-Mail',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'E-Mails von / an Microsoft for Nonprofits speichern',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),

            // Tab toggle
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inbox, size: 18),
                        const SizedBox(width: 6),
                        Text('Eingang (${_korrEingang.length})'),
                      ],
                    ),
                    selected: _korrTab == 'eingang',
                    onSelected: (_) => setState(() => _korrTab = 'eingang'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send, size: 18),
                        const SizedBox(width: 6),
                        Text('Ausgang (${_korrAusgang.length})'),
                      ],
                    ),
                    selected: _korrTab == 'ausgang',
                    onSelected: (_) => setState(() => _korrTab = 'ausgang'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (list.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.email_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text(
                      'Keine ${isEingang ? "Eingang" : "Ausgang"}-Mails',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              )
            else
              ...list.map(_buildKorrespondenzItem),
          ],
        ),
      ),
    );
  }

  Widget _buildKorrespondenzItem(Map<String, dynamic> entry) {
    final id = entry['id'] as int;
    final betreff = (entry['betreff'] as String?) ?? '(ohne Betreff)';
    final inhalt = (entry['inhalt'] as String?) ?? '';
    final datumStr = (entry['datum'] as String?) ?? '';
    DateTime? datum;
    try { datum = DateTime.parse(datumStr); } catch (_) {}
    final dateLabel = datum != null ? DateFormat('dd.MM.yyyy HH:mm').format(datum) : datumStr;
    final partner = _korrTab == 'eingang'
        ? ((entry['absender'] as String?) ?? '')
        : ((entry['empfaenger'] as String?) ?? '');
    final files = List<Map<String, dynamic>>.from(entry['files'] ?? const []);
    final expanded = _korrExpanded.contains(id);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: Icon(
              _korrTab == 'eingang' ? Icons.inbox : Icons.send,
              color: Colors.teal.shade700,
            ),
            title: Text(
              betreff,
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (partner.isNotEmpty)
                  Text(
                    '${_korrTab == "eingang" ? "Von" : "An"}: $partner',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (files.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${files.length}'),
                      avatar: const Icon(Icons.attach_file, size: 14),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                IconButton(
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() {
                    if (expanded) {
                      _korrExpanded.remove(id);
                    } else {
                      _korrExpanded.add(id);
                    }
                  }),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red.shade400,
                  onPressed: () => _deleteKorrespondenz(id),
                  tooltip: 'Loeschen',
                ),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (inhalt.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: SelectableText(
                        inhalt,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (files.isNotEmpty) ...[
                    Text(
                      'Anhaenge:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: files.map((f) {
                        final name = (f['datei_name'] as String?) ?? 'datei';
                        final size = (f['datei_groesse'] as int?) ?? 0;
                        final sizeKb = size > 0 ? '${(size / 1024).toStringAsFixed(0)} KB' : '';
                        return ActionChip(
                          avatar: const Icon(Icons.insert_drive_file, size: 16),
                          label: Text('$name${sizeKb.isNotEmpty ? " · $sizeKb" : ""}',
                              style: const TextStyle(fontSize: 12)),
                          onPressed: () => _openKorrespondenzAttachment(f),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Pick one or more files using a platform-appropriate dialog.
  ///
  /// On **macOS** the standard `file_picker` plugin (NSOpenPanel) fails
  /// silently on unsigned / ad-hoc signed builds because the system refuses
  /// to grant the open-panel entitlement. We bypass this by calling
  /// `osascript -e 'choose file'` which invokes an AppleScript file dialog
  /// that works without ANY entitlement on non-sandboxed apps.
  ///
  /// On all other platforms we fall back to the regular `file_picker` plugin.
  Future<List<File>> _pickFilesNative() async {
    if (Platform.isMacOS) {
      return _pickFilesViaMacOSDialog();
    }
    // Non-macOS: use standard file_picker
    try {
      final res = await FilePickerHelper.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (res == null) return [];
      return res.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// macOS-only: show a native AppleScript file dialog via `osascript`.
  /// Returns the selected files as a list of `File` objects.
  Future<List<File>> _pickFilesViaMacOSDialog() async {
    try {
      final result = await Process.run('osascript', [
        '-e', 'set theFiles to choose file with prompt "Dateien auswählen" with multiple selections allowed',
        '-e', 'set filePaths to ""',
        '-e', 'repeat with f in theFiles',
        '-e', '  set filePaths to filePaths & POSIX path of f & linefeed',
        '-e', 'end repeat',
        '-e', 'return filePaths',
      ]);
      if (result.exitCode != 0) return []; // user cancelled or error
      final output = (result.stdout as String).trim();
      if (output.isEmpty) return [];
      return output
          .split('\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .map((p) => File(p))
          .where((f) => f.existsSync())
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    _totpTimer = null;
    _emailController.dispose();
    _passwordController.dispose();
    _totpSecretController.dispose();
    super.dispose();
  }
}
