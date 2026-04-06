import 'package:flutter/material.dart';
import '../utils/clipboard_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class StifterHelfenScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const StifterHelfenScreen({
    super.key,
    required this.apiService,
    required this.onBack,
  });

  @override
  State<StifterHelfenScreen> createState() => _StifterHelfenScreenState();
}

class _StifterHelfenScreenState extends State<StifterHelfenScreen> {
  bool _isEditing = false;
  bool _passwordVisible = false;
  bool _isLoading = true;
  bool _isSaving = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _website = 'https://www.stifter-helfen.de';

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
    await Future.wait([_loadCredentials(), _loadAufgaben(), _loadNotizen()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadCredentials() async {
    try {
      final result = await widget.apiService.getPlatformCredentials('stifter-helfen');
      if (result['success'] == true && result['credentials'] != null) {
        final creds = result['credentials'];
        _emailController.text = creds['email'] ?? '';
        _passwordController.text = creds['password'] ?? '';
        _website = creds['website'] ?? 'https://www.stifter-helfen.de';
      }
    } catch (_) {}
  }

  Future<void> _loadAufgaben() async {
    try {
      final result = await widget.apiService.getPlatformAufgaben('stifter-helfen');
      if (result['success'] == true && result['aufgaben'] != null) {
        _aufgaben = List<Map<String, dynamic>>.from(result['aufgaben']);
      }
    } catch (_) {}
  }

  Future<void> _loadNotizen() async {
    try {
      final result = await widget.apiService.getPlatformNotizen('stifter-helfen');
      if (result['success'] == true && result['notizen'] != null) {
        _notizen = List<Map<String, dynamic>>.from(result['notizen']);
      }
    } catch (_) {}
  }

  Future<void> _saveCredentials() async {
    setState(() => _isSaving = true);
    try {
      final result = await widget.apiService.savePlatformCredentials(
        platform: 'stifter-helfen',
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        website: _website,
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
                    hintText: 'z.B. Gemeinnützigkeitsnachweis einreichen',
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
                // Date + Time
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
        platform: 'stifter-helfen',
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
        platform: 'stifter-helfen',
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
              Icon(Icons.volunteer_activism, size: 32, color: Colors.deepPurple.shade700),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Stifter-helfen / IT for Nonprofits',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              // Gear icon / Save
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
                                  'IT-Spendenplattform für gemeinnützige Organisationen',
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
                                    // Counter badge
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
                                  'Unterlagen und Fristen für stifter-helfen.de',
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
                                  'Interne Notizen zu stifter-helfen.de',
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
                                color: Colors.deepPurple.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.deepPurple.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.card_giftcard, color: Colors.deepPurple.shade700, size: 20),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Vorteile für Vereine',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    '\u2713 Software-Spenden (Microsoft Office, Adobe, etc.)\n'
                                    '\u2713 Bis zu 90% Rabatt für gemeinnützige Organisationen\n'
                                    '\u2713 Hardware-Vermittlung (gebrauchte Laptops, PCs)\n'
                                    '\u2713 IT-Beratung und Support\n'
                                    '\u2713 Cloud-Services (Microsoft 365, Google Workspace)',
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
