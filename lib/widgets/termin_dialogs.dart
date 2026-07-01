import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/termin_service.dart';
import '../services/termin_weather_service.dart';
import '../services/ticket_service.dart';
import '../services/api_service.dart';
import '../models/user.dart';

// Create Termin Dialog
class CreateTerminDialog extends StatefulWidget {
  final TerminService terminService;
  final List<User> users;
  final List<Ticket> tickets;
  final VoidCallback onTerminCreated;

  const CreateTerminDialog({
    super.key,
    required this.terminService,
    required this.users,
    required this.tickets,
    required this.onTerminCreated,
  });

  @override
  State<CreateTerminDialog> createState() => _CreateTerminDialogState();
}

class _CreateTerminDialogState extends State<CreateTerminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _durationController = TextEditingController(text: '60');

  String _category = 'vorstandssitzung';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 18, minute: 0);
  Set<int> _selectedParticipants = {};
  int? _selectedTicketId;
  bool _brauchtMich = false;
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _createTermin() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens einen Teilnehmer auswählen'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validare ore permise: 08:00-17:00 (18:00 = Abendessen)
    final hour = _selectedTime.hour;
    final isValidTime = (hour >= 8 && hour <= 17);

    if (!isValidTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Termine sind nur möglich:\n08:00-17:00 Uhr\n(ab 18:00 Abendessen — keine Buchung)',
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    final terminDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    try {
      final result = await widget.terminService.createTermin(
        title: _titleController.text.trim(),
        category: _category,
        description: _descriptionController.text.trim(),
        terminDate: terminDate,
        durationMinutes: int.parse(_durationController.text),
        location: _locationController.text.trim(),
        participantIds: _selectedParticipants.toList(),
        ticketId: _selectedTicketId,
        brauchtMich: _brauchtMich,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Termin erfolgreich erstellt'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onTerminCreated();
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: ${result['message']}'),
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
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 700,
        height: 700,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    'Neuer Termin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: const InputDecoration(
                          labelText: 'Kategorie *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'vorstandssitzung', child: Text('Vorstandssitzung')),
                          DropdownMenuItem(value: 'mitgliederversammlung', child: Text('Mitgliederversammlung')),
                          DropdownMenuItem(value: 'schulung', child: Text('Schulung')),
                          DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges')),
                        ],
                        onChanged: (value) => setState(() => _category = value!),
                      ),
                      const SizedBox(height: 16),
                      // Title
                      TextFormField(
                        controller: _titleController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Titel *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.title),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Titel erforderlich' : null,
                      ),
                      const SizedBox(height: 16),
                      // Description
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Beschreibung',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      // Date and Time
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                  locale: const Locale('de', 'DE'),
                                );
                                if (date != null) setState(() => _selectedDate = date);
                              },
                              icon: const Icon(Icons.calendar_today),
                              label: Text(DateFormat('dd.MM.yyyy').format(_selectedDate)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: _selectedTime,
                                    );
                                    if (time != null) setState(() => _selectedTime = time);
                                  },
                                  icon: const Icon(Icons.access_time),
                                  label: Text(_selectedTime.format(context)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '08:00-17:00',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Duration and Location
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _durationController,
                              decoration: const InputDecoration(
                                labelText: 'Dauer (Min.)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.timer),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Erforderlich';
                                final num = int.tryParse(v);
                                if (num == null || num < 15 || num > 480) {
                                  return '15-480 Min.';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _locationController,
                              decoration: const InputDecoration(
                                labelText: 'Ort *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.location_on),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Ort erforderlich' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Participants
                      Text(
                        'Teilnehmer (${_selectedParticipants.length} ausgewählt) *',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedParticipants = widget.users.map((u) => u.id).toSet();
                              });
                            },
                            icon: const Icon(Icons.check_box),
                            label: const Text('Alle auswählen'),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _selectedParticipants.clear()),
                            icon: const Icon(Icons.check_box_outline_blank),
                            label: const Text('Keine'),
                          ),
                        ],
                      ),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView(
                          children: widget.users.map((user) {
                            final isSelected = _selectedParticipants.contains(user.id);
                            return CheckboxListTile(
                              value: isSelected,
                              title: Text('${user.name} (${user.mitgliedernummer})'),
                              subtitle: Text(user.role),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedParticipants.add(user.id);
                                  } else {
                                    _selectedParticipants.remove(user.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Linked Ticket (optional)
                      DropdownButtonFormField<int?>(
                        initialValue: _selectedTicketId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Verknüpftes Ticket (optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Kein Ticket')),
                          ...widget.tickets
                              .where((t) => t.status == 'open' || t.status == 'in_progress')
                              .map((ticket) => DropdownMenuItem(
                                    value: ticket.id,
                                    child: Text(
                                      '#${ticket.id} - ${ticket.subject}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )),
                        ],
                        onChanged: (value) => setState(() => _selectedTicketId = value),
                      ),
                      const SizedBox(height: 16),
                      // Braucht mich toggle
                      SwitchListTile(
                        value: _brauchtMich,
                        onChanged: (val) => setState(() => _brauchtMich = val),
                        title: const Text('Braucht mich', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Meine Anwesenheit ist erforderlich'),
                        secondary: Icon(
                          Icons.person_pin_circle,
                          color: _brauchtMich ? Colors.red.shade700 : Colors.grey,
                        ),
                        activeThumbColor: Colors.red.shade700,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isCreating ? null : _createTermin,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Termin erstellen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
}

// Edit Termin Dialog
class EditTerminDialog extends StatefulWidget {
  final Termin termin;
  final TerminService terminService;
  final List<User> users;
  final List<Ticket> tickets;
  final VoidCallback onTerminUpdated;
  final String currentMitgliedernummer;
  final TerminWeatherHint? weatherHint;

  const EditTerminDialog({
    super.key,
    required this.termin,
    required this.terminService,
    required this.users,
    required this.tickets,
    required this.onTerminUpdated,
    required this.currentMitgliedernummer,
    this.weatherHint,
  });

  @override
  State<EditTerminDialog> createState() => _EditTerminDialogState();
}

class _EditTerminDialogState extends State<EditTerminDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;
  late TextEditingController _durationController;

  late String _category;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late int? _selectedTicketId;
  late bool _brauchtMich;
  bool _isUpdating = false;
  bool _isDeleting = false;
  bool _isEditing = false;
  bool _isSendingReminder = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.termin.title);
    _descriptionController = TextEditingController(text: widget.termin.description);
    _locationController = TextEditingController(text: widget.termin.location);
    _durationController = TextEditingController(text: widget.termin.durationMinutes.toString());
    _category = widget.termin.category;
    _selectedDate = widget.termin.terminDate;
    _selectedTime = TimeOfDay.fromDateTime(widget.termin.terminDate);
    _selectedTicketId = widget.termin.ticketId;
    _brauchtMich = widget.termin.brauchtMich;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _updateTermin() async {
    if (!_formKey.currentState!.validate()) return;

    final hour = _selectedTime.hour;
    final isValidTime = (hour >= 8 && hour <= 17);
    if (!isValidTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Termine: 08:00-17:00 Uhr (ab 18:00 Abendessen)'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isUpdating = true);

    final terminDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute);

    try {
      final result = await widget.terminService.updateTermin(
        terminId: widget.termin.id,
        title: _titleController.text.trim(),
        category: _category,
        description: _descriptionController.text.trim(),
        terminDate: terminDate,
        durationMinutes: int.parse(_durationController.text),
        location: _locationController.text.trim(),
        ticketId: _selectedTicketId,
        brauchtMich: _brauchtMich,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Termin aktualisiert'), backgroundColor: Colors.green),
        );
        widget.onTerminUpdated();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${result['message']}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _deleteTermin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Termin löschen?'),
        content: Text('Möchten Sie "${widget.termin.title}" wirklich löschen?'),
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

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      final result = await widget.terminService.deleteTermin(widget.termin.id);

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Termin gelöscht'), backgroundColor: Colors.green),
        );
        widget.onTerminUpdated();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${result['message']}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _sendErinnerung() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.orange),
            SizedBox(width: 8),
            Text('Erinnerung senden?'),
          ],
        ),
        content: const Text(
          'Möchten Sie allen Teilnehmern eine Erinnerung für diesen Termin per Chat senden?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send),
            label: const Text('Senden'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSendingReminder = true);

    try {
      final apiService = ApiService();
      final termin = widget.termin;
      final dateStr = DateFormat('dd.MM.yyyy', 'de').format(termin.terminDate);
      final timeStr = DateFormat('HH:mm').format(termin.terminDate);
      final endTimeStr = DateFormat('HH:mm').format(termin.terminEndTime);
      final dauer = '${termin.durationMinutes} Minuten';

      // Get termin details to get participant list
      final details = await widget.terminService.getTerminDetails(termin.id);
      if (details['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: ${details['message'] ?? 'Teilnehmer konnten nicht geladen werden'}'), backgroundColor: Colors.red),
        );
        return;
      }

      final participants = details['participants'] as List? ?? [];
      if (participants.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Teilnehmer gefunden'), backgroundColor: Colors.orange),
        );
        return;
      }

      int sentCount = 0;
      int errorCount = 0;

      for (final p in participants) {
        final mitgliedernummer = p['mitgliedernummer']?.toString() ?? '';
        if (mitgliedernummer.isEmpty || mitgliedernummer == widget.currentMitgliedernummer) continue;

        // Look up user in widget.users for Verifizierung Stufe 1 data
        final userId = p['user_id'] is int ? p['user_id'] : int.tryParse(p['user_id']?.toString() ?? '');
        final user = widget.users.cast<User?>().firstWhere(
          (u) => u?.id == userId || u?.mitgliedernummer == mitgliedernummer,
          orElse: () => null,
        );

        final vorname = user?.vorname ?? p['name']?.toString().split(' ').first ?? '';
        final nachname = user?.nachname ?? '';
        final geschlecht = user?.geschlecht ?? '';

        // Anrede based on Geschlecht from Verifizierung Stufe 1
        String anrede;
        if (geschlecht == 'W') {
          anrede = 'Sehr geehrte Frau $vorname $nachname';
        } else if (geschlecht == 'M') {
          anrede = 'Sehr geehrter Herr $vorname $nachname';
        } else {
          anrede = 'Sehr geehrte(r) $vorname $nachname';
        }

        final beschreibung = termin.description.isNotEmpty ? termin.description : 'Keine weiteren Notizen';

        final message = '''$anrede,

hiermit möchten wir Sie an Ihren bevorstehenden Termin erinnern:

📅 Datum: $dateStr
🕐 Uhrzeit: $timeStr - $endTimeStr
⏱️ Dauer: ca. $dauer
📍 Ort: ${termin.location.isNotEmpty ? termin.location : 'Wird noch bekannt gegeben'}
📋 Betreff: ${termin.title}

📝 Notizen: $beschreibung

Bitte bestätigen Sie Ihre Teilnahme oder melden Sie sich rechtzeitig ab.

Mit freundlichen Grüßen,
ICD360S e.V. Vorstand''';

        try {
          // Start or find existing chat conversation
          final chatResult = await apiService.adminStartChat(
            widget.currentMitgliedernummer,
            mitgliedernummer,
          );

          if (chatResult['success'] == true) {
            final conversationId = chatResult['conversation_id'] ?? chatResult['id'];
            if (conversationId != null) {
              await apiService.sendChatMessage(
                conversationId,
                widget.currentMitgliedernummer,
                message,
                skipTranslation: true, // Termin-Erinnerung bleibt deutsch — NLLB würde Zahlen/Datum/Uhrzeit halluzinieren
              );
              sentCount++;
            } else {
              errorCount++;
            }
          } else {
            errorCount++;
          }
        } catch (_) {
          errorCount++;
        }
      }

      if (!mounted) return;

      if (sentCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erinnerung an $sentCount Teilnehmer gesendet${errorCount > 0 ? ' ($errorCount fehlgeschlagen)' : ''}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Erinnerungen gesendet'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSendingReminder = false);
    }
  }

  String get _categoryLabel {
    switch (_category) {
      case 'vorstandssitzung': return 'Vorstandssitzung';
      case 'mitgliederversammlung': return 'Mitgliederversammlung';
      case 'schulung': return 'Schulung';
      case 'sonstiges': return 'Sonstiges';
      default: return _category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final termin = widget.termin;
    final color = _brauchtMich ? Colors.red.shade700 : termin.categoryColor;
    final timeStr = '${DateFormat('HH:mm').format(termin.terminDate)} - ${DateFormat('HH:mm').format(termin.terminEndTime)}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 650,
        height: _isEditing ? 550 : null,
        child: Column(
          mainAxisSize: _isEditing ? MainAxisSize.max : MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(_isEditing ? Icons.edit : Icons.event, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    _isEditing ? 'Termin bearbeiten' : termin.title,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  )),
                  if (!_isEditing)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white),
                      tooltip: 'Bearbeiten',
                      onPressed: () => setState(() => _isEditing = true),
                    ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),

            if (!_isEditing) ...[
              // ── READ-ONLY VIEW ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    // Category chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text(_categoryLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                    ),
                    const SizedBox(height: 16),
                    // Date & Time
                    _readOnlyRow(Icons.calendar_today, 'Datum', DateFormat('EEEE, dd. MMMM yyyy', 'de').format(termin.terminDate)),
                    _readOnlyRow(Icons.access_time, 'Uhrzeit', timeStr),
                    _readOnlyRow(Icons.timer, 'Dauer', '${termin.durationMinutes} Minuten'),
                    if (termin.location.isNotEmpty)
                      _readOnlyRow(Icons.location_on, 'Ort', termin.location),
                    if (widget.weatherHint != null) _buildWeatherHintCard(widget.weatherHint!),
                    if (termin.description.isNotEmpty)
                      _readOnlyRow(Icons.notes, 'Beschreibung', termin.description),
                    if (termin.ticketSubject != null)
                      _readOnlyRow(Icons.confirmation_number, 'Ticket', termin.ticketSubject!),
                    if (termin.brauchtMich)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Icon(Icons.person_pin_circle, size: 16, color: Colors.red.shade700),
                          const SizedBox(width: 10),
                          SizedBox(width: 120, child: Text('Braucht mich', style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600))),
                          Text('Ja', style: TextStyle(fontSize: 13, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    // Participants
                    if (termin.totalParticipants != null && termin.totalParticipants! > 0) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Icon(Icons.group, size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 10),
                        Text('Teilnehmer', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        if (termin.confirmedCount != null && termin.confirmedCount! > 0)
                          _participantBadge('${termin.confirmedCount}', Colors.green, Icons.check_circle),
                        if (termin.pendingCount != null && termin.pendingCount! > 0)
                          _participantBadge('${termin.pendingCount}', Colors.orange, Icons.hourglass_empty),
                        if (termin.declinedCount != null && termin.declinedCount! > 0)
                          _participantBadge('${termin.declinedCount}', Colors.red, Icons.cancel),
                      ]),
                    ],
                    if (termin.createdByName != null) ...[
                      const SizedBox(height: 12),
                      _readOnlyRow(Icons.person, 'Erstellt von', termin.createdByName!),
                    ],

                    // ── Termin-Nachbearbeitung (nach Termin-Beginn) ──
                    _buildNachbearbeitungSection(),
                  ],
                ),
              ),
              ),
              // Footer with delete + erinnerung
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isDeleting ? null : _deleteTermin,
                      icon: _isDeleting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete, size: 18),
                      label: const Text('Löschen'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isSendingReminder ? null : _sendErinnerung,
                      icon: _isSendingReminder
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.notifications_active, size: 18),
                      label: const Text('Erinnerung'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Bearbeiten'),
                      style: OutlinedButton.styleFrom(foregroundColor: color),
                      onPressed: () => setState(() => _isEditing = true),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // ── EDIT MODE ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _category,
                          decoration: const InputDecoration(labelText: 'Kategorie', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'vorstandssitzung', child: Text('Vorstandssitzung')),
                            DropdownMenuItem(value: 'mitgliederversammlung', child: Text('Mitgliederversammlung')),
                            DropdownMenuItem(value: 'schulung', child: Text('Schulung')),
                            DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges')),
                          ],
                          onChanged: (value) => setState(() => _category = value!),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(controller: _titleController, autofocus: true, decoration: const InputDecoration(labelText: 'Titel', border: OutlineInputBorder()), validator: (v) => v?.trim().isEmpty ?? true ? 'Erforderlich' : null),
                        const SizedBox(height: 16),
                        TextFormField(controller: _descriptionController, decoration: const InputDecoration(labelText: 'Beschreibung', border: OutlineInputBorder()), maxLines: 2),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) setState(() => _selectedDate = d); }, icon: const Icon(Icons.calendar_today), label: Text(DateFormat('dd.MM.yyyy').format(_selectedDate)))),
                            const SizedBox(width: 12),
                            Expanded(child: OutlinedButton.icon(onPressed: () async { final t = await showTimePicker(context: context, initialTime: _selectedTime); if (t != null) setState(() => _selectedTime = t); }, icon: const Icon(Icons.access_time), label: Text(_selectedTime.format(context)))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: TextFormField(controller: _durationController, decoration: const InputDecoration(labelText: 'Dauer (Min.)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: TextFormField(controller: _locationController, decoration: const InputDecoration(labelText: 'Ort', border: OutlineInputBorder()))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          value: _brauchtMich,
                          onChanged: (val) => setState(() => _brauchtMich = val),
                          title: const Text('Braucht mich', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Meine Anwesenheit ist erforderlich'),
                          secondary: Icon(Icons.person_pin_circle, color: _brauchtMich ? Colors.red.shade700 : Colors.grey),
                          activeThumbColor: Colors.red.shade700,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
                child: Row(
                  children: [
                    ElevatedButton.icon(onPressed: _isDeleting || _isUpdating ? null : _deleteTermin, icon: const Icon(Icons.delete), label: const Text('Löschen'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white)),
                    const Spacer(),
                    TextButton(onPressed: () => setState(() => _isEditing = false), child: const Text('Abbrechen')),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(onPressed: _isUpdating || _isDeleting ? null : _updateTermin, icon: _isUpdating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check), label: const Text('Speichern'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _readOnlyRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  /// Prominent card summarising the pre-computed weather advisory for this
  /// Termin. Only shown in read-only view; a null hint means "no warning
  /// triggered" and the card doesn't render at all.
  Widget _buildWeatherHintCard(TerminWeatherHint hint) {
    final color = switch (hint.kind) {
      TerminWeatherKind.normal => Colors.blueGrey.shade600,
      TerminWeatherKind.rain => Colors.blue.shade700,
      TerminWeatherKind.snow => Colors.lightBlue.shade700,
      TerminWeatherKind.thunder => Colors.deepPurple.shade700,
      TerminWeatherKind.cold => Colors.indigo.shade700,
      TerminWeatherKind.hot => Colors.deepOrange.shade700,
      TerminWeatherKind.storm => Colors.brown.shade700,
      TerminWeatherKind.wind => Colors.teal.shade700,
    };
    final label = hint.hasWarning ? 'Wetter-Hinweis für diesen Termin' : 'Wetter-Prognose';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hint.emoji,
            // Per-widget emoji font fallback — matches weather_widget.dart's
            // _kEmojiFonts list. Keeps weather symbols colourful without
            // affecting kerning of surrounding text.
            style: const TextStyle(
              fontSize: 30,
              fontFamilyFallback: ['Segoe UI Emoji', 'Apple Color Emoji', 'Noto Color Emoji'],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint.title.split(' · ').first,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  hint.subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
                if (hint.recommendation.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '💡  ',
                        style: TextStyle(
                          fontSize: 13,
                          fontFamilyFallback: ['Segoe UI Emoji', 'Apple Color Emoji', 'Noto Color Emoji'],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          hint.recommendation,
                          style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade900),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Prognose: Open-Meteo · Stand ${DateFormat('HH:mm').format(hint.computedAt)}',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _participantBadge(String count, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(count, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  Termin-Nachbearbeitung (manuelles Tracking)
  //  Chips: ✓ Wahrgenommen | ✗ Nicht wahrg. | 📢 Feedback
  //  - Aktiviert nach termin.terminDate (= nach Termin-Beginn)
  //  - Wahrgenommen / nicht_wahrgenommen mutually exclusive
  //  - Feedback unabhängig (toggle, Bottom-Sheet für Text)
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildNachbearbeitungSection() {
    final termin = widget.termin;
    final started = DateTime.now().isAfter(termin.terminDate);
    final status = termin.feedbackStatus;
    final hasFeedback = termin.feedbackErhalten;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 1, color: Colors.grey.shade300),
        const SizedBox(height: 14),
        Row(children: [
          Icon(Icons.fact_check, size: 18, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          const Text('Termin-Nachbearbeitung', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          if (!started) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
              child: Text('erst nach Termin-Beginn verfügbar',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilterChip(
            avatar: Icon(Icons.check_circle,
              size: 18, color: status == 'wahrgenommen' ? Colors.white : Colors.green.shade700),
            label: const Text('Wahrgenommen'),
            selected: status == 'wahrgenommen',
            onSelected: started ? (sel) => _setStatus(sel ? 'wahrgenommen' : 'offen') : null,
            selectedColor: Colors.green.shade700,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              fontSize: 12,
              color: status == 'wahrgenommen' ? Colors.white : Colors.black87,
              fontWeight: status == 'wahrgenommen' ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          FilterChip(
            avatar: Icon(Icons.cancel,
              size: 18, color: status == 'nicht_wahrgenommen' ? Colors.white : Colors.red.shade700),
            label: const Text('Nicht wahrgenommen'),
            selected: status == 'nicht_wahrgenommen',
            onSelected: started ? (sel) => sel ? _selectGrundAndSet() : _setStatus('offen') : null,
            selectedColor: Colors.red.shade700,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              fontSize: 12,
              color: status == 'nicht_wahrgenommen' ? Colors.white : Colors.black87,
              fontWeight: status == 'nicht_wahrgenommen' ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          FilterChip(
            avatar: Icon(Icons.campaign,
              size: 18, color: hasFeedback ? Colors.white : Colors.orange.shade700),
            label: const Text('Feedback'),
            selected: hasFeedback,
            onSelected: started ? (_) => _openFeedbackSheet() : null,
            selectedColor: Colors.orange.shade700,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              fontSize: 12,
              color: hasFeedback ? Colors.white : Colors.black87,
              fontWeight: hasFeedback ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ]),

        // Details über gesetzten Status
        if (status == 'nicht_wahrgenommen' && termin.nichtWahrgenommenGrund != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline, size: 14, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Text('Grund: ${TerminService.nichtWahrgenommenGruende[termin.nichtWahrgenommenGrund] ?? termin.nichtWahrgenommenGrund}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade900)),
              ]),
              if ((termin.nichtWahrgenommenGrundText ?? '').isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4, left: 20),
                  child: Text(termin.nichtWahrgenommenGrundText!, style: TextStyle(fontSize: 11, color: Colors.red.shade800, fontStyle: FontStyle.italic))),
            ]),
          ),
        ],
        if (hasFeedback && (termin.feedbackText ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.campaign, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Text('Feedback eingegangen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade900)),
              ]),
              Padding(padding: const EdgeInsets.only(top: 4),
                child: Text(termin.feedbackText!, style: TextStyle(fontSize: 12, color: Colors.orange.shade900))),
            ]),
          ),
        ],
        if (termin.markiertAm != null) ...[
          const SizedBox(height: 8),
          Text('Markiert am ${DateFormat('dd.MM.yyyy HH:mm').format(termin.markiertAm!)}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }

  Future<void> _setStatus(String newStatus, {String? grund, String? grundText}) async {
    final res = await widget.terminService.setTerminStatus(
      terminId: widget.termin.id, feedbackStatus: newStatus, grund: grund, grundText: grundText,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newStatus == 'wahrgenommen' ? 'Als wahrgenommen markiert'
          : newStatus == 'nicht_wahrgenommen' ? 'Als nicht wahrgenommen markiert'
          : 'Status zurückgesetzt'),
        backgroundColor: Colors.green,
      ));
      widget.onTerminUpdated();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }

  Future<void> _selectGrundAndSet() async {
    String? selectedKey;
    final freitextC = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        title: Row(children: [
          Icon(Icons.cancel, color: Colors.red.shade700),
          const SizedBox(width: 8),
          const Text('Grund für Versäumnis', style: TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            RadioGroup<String>(
              groupValue: selectedKey,
              onChanged: (v) => setS(() => selectedKey = v),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: TerminService.nichtWahrgenommenGruende.entries.map((e) => RadioListTile<String>(
                value: e.key,
                title: Text(e.value, style: const TextStyle(fontSize: 12)),
                dense: true, contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
              )).toList()),
            ),
            if (selectedKey == 'sonstiges') ...[
              const SizedBox(height: 8),
              TextField(controller: freitextC, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Beschreibung *', border: OutlineInputBorder(), isDense: true)),
            ] else if (selectedKey != null) ...[
              const SizedBox(height: 8),
              TextField(controller: freitextC, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Zusätzliche Details (optional)', border: OutlineInputBorder(), isDense: true)),
            ],
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: selectedKey == null
                ? null
                : () {
                    if (selectedKey == 'sonstiges' && freitextC.text.trim().isEmpty) return;
                    Navigator.pop(ctx, {'grund': selectedKey!, 'grund_text': freitextC.text.trim()});
                  },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('Bestätigen'),
          ),
        ],
      )),
    );
    if (result == null) return;
    await _setStatus('nicht_wahrgenommen', grund: result['grund'], grundText: result['grund_text']);
  }

  Future<void> _openFeedbackSheet() async {
    final textC = TextEditingController(text: widget.termin.feedbackText ?? '');
    final dateC = TextEditingController(
      text: widget.termin.feedbackEingegangenAm != null
          ? DateFormat('dd.MM.yyyy').format(widget.termin.feedbackEingegangenAm!)
          : DateFormat('dd.MM.yyyy').format(DateTime.now()),
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.campaign, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Text('Feedback / Was wurde besprochen?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx, false)),
            ]),
            const SizedBox(height: 8),
            TextField(controller: textC, maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Feedback-Text',
                hintText: 'z.B. Diagnose, neue Medikation, nächste Termine, Bescheid…',
                border: OutlineInputBorder(),
              )),
            const SizedBox(height: 10),
            Row(children: [
              const Text('Rückmeldung eingegangen am: ', style: TextStyle(fontSize: 12)),
              SizedBox(width: 130, child: TextField(controller: dateC, readOnly: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () async {
                    final p = await showDatePicker(context: ctx, initialDate: DateTime.now(),
                      firstDate: DateTime(2020), lastDate: DateTime.now(), locale: const Locale('de'));
                    if (p != null) dateC.text = DateFormat('dd.MM.yyyy').format(p);
                  }),
                ),
                style: const TextStyle(fontSize: 12),
              )),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              if (widget.termin.feedbackErhalten)
                Expanded(child: OutlinedButton.icon(
                  onPressed: () async {
                    textC.clear();
                    Navigator.pop(ctx, true);
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Feedback löschen'),
                )),
              if (widget.termin.feedbackErhalten) const SizedBox(width: 8),
              Expanded(flex: 2, child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Speichern'),
              )),
            ]),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );

    if (saved != true) return;
    final res = await widget.terminService.setTerminFeedback(
      terminId: widget.termin.id,
      feedbackText: textC.text.trim(),
      eingegangenAm: dateC.text.trim(),
    );
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(textC.text.trim().isEmpty ? 'Feedback gelöscht' : 'Feedback gespeichert'),
        backgroundColor: Colors.green,
      ));
      widget.onTerminUpdated();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }
}
