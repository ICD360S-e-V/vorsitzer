import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../services/ticket_service.dart';

/// Shows the tickets list dialog
void showTicketsDialog(BuildContext context, String mitgliedernummer) {
  showDialog(
    context: context,
    builder: (context) => _TicketsListDialog(mitgliedernummer: mitgliedernummer),
  );
}

/// Shows the new ticket creation dialog
Future<bool> showNewTicketDialog(BuildContext context, String mitgliedernummer) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _NewTicketDialog(mitgliedernummer: mitgliedernummer),
  );
  return result ?? false;
}

/// Tickets List Dialog
class _TicketsListDialog extends StatefulWidget {
  final String mitgliedernummer;

  const _TicketsListDialog({required this.mitgliedernummer});

  @override
  State<_TicketsListDialog> createState() => _TicketsListDialogState();
}

class _TicketsListDialogState extends State<_TicketsListDialog> {
  final _ticketService = TicketService();
  List<Ticket> _tickets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() => _isLoading = true);
    final tickets = await _ticketService.getTickets(widget.mitgliedernummer);
    if (mounted) {
      setState(() {
        _tickets = tickets;
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.orange;
      case 'in_progress':
        return Colors.purple;
      case 'waiting_member':
        return Colors.blue;
      case 'waiting_staff':
        return Colors.teal;
      case 'waiting_authority':
        return Colors.indigo;
      case 'done':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.confirmation_number, color: Color(0xFF4a90d9)),
          SizedBox(width: 12),
          Text('Meine Tickets'),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _tickets.isEmpty
                ? _buildEmptyState()
                : _buildTicketsList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            Navigator.pop(context);
            final created = await showNewTicketDialog(context, widget.mitgliedernummer);
            if (created && context.mounted) {
              // Reopen tickets dialog to show new ticket
              showTicketsDialog(context, widget.mitgliedernummer);
            }
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Neues Ticket'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4a90d9),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Keine offenen Tickets',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Haben Sie eine Frage oder ein Problem?\nErstellen Sie ein neues Ticket.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsList() {
    return ListView.builder(
      itemCount: _tickets.length,
      itemBuilder: (context, index) {
        final ticket = _tickets[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    ticket.subject,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(ticket.status).withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getStatusColor(ticket.status)),
                  ),
                  child: Text(
                    ticket.statusDisplay,
                    style: TextStyle(
                      fontSize: 11,
                      color: _getStatusColor(ticket.status),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  ticket.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(ticket.createdAt),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: _getPriorityColor(ticket.priority).withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ticket.priorityDisplay,
                        style: TextStyle(
                          fontSize: 10,
                          color: _getPriorityColor(ticket.priority),
                        ),
                      ),
                    ),
                    if (ticket.adminName != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.person, size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        ticket.adminName!,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            onTap: () => _showTicketDetails(ticket),
          ),
        );
      },
    );
  }

  void _showTicketDetails(Ticket ticket) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.confirmation_number, color: _getStatusColor(ticket.status)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                ticket.subject,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(ticket.status).withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _getStatusColor(ticket.status)),
                    ),
                    child: Text(
                      ticket.statusDisplay,
                      style: TextStyle(
                        color: _getStatusColor(ticket.status),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getPriorityColor(ticket.priority).withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Priorität: ${ticket.priorityDisplay}',
                      style: TextStyle(
                        color: _getPriorityColor(ticket.priority),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Nachricht:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(ticket.message),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Erstellt: ${_formatDate(ticket.createdAt)}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
              if (ticket.adminName != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.support_agent, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      'Bearbeiter: ${ticket.adminName}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ],
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
}

/// New Ticket Dialog
class _NewTicketDialog extends StatefulWidget {
  final String mitgliedernummer;

  const _NewTicketDialog({required this.mitgliedernummer});

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _ticketService = TicketService();
  String _priority = 'medium';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitTicket() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();

    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Betreff und Nachricht ausfüllen'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await _ticketService.createTicket(
      mitgliedernummer: widget.mitgliedernummer,
      subject: subject,
      message: message,
      priority: _priority,
    );

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (result.containsKey('ticket')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ticket wurde erstellt'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Fehler beim Erstellen des Tickets'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.add_circle, color: Color(0xFF4a90d9)),
          SizedBox(width: 12),
          Text('Neues Ticket erstellen'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: 'Betreff',
                prefixIcon: const Icon(Icons.subject),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Nachricht',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 60),
                  child: Icon(Icons.message),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Priorität: '),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Niedrig'),
                  selected: _priority == 'low',
                  onSelected: (_) => setState(() => _priority = 'low'),
                  selectedColor: Colors.green.shade100,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Mittel'),
                  selected: _priority == 'medium',
                  onSelected: (_) => setState(() => _priority = 'medium'),
                  selectedColor: Colors.orange.shade100,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Hoch'),
                  selected: _priority == 'high',
                  onSelected: (_) => setState(() => _priority = 'high'),
                  selectedColor: Colors.red.shade100,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitTicket,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4a90d9),
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Absenden'),
        ),
      ],
    );
  }
}

/// Shows the admin create ticket dialog (create ticket on behalf of a member)
Future<bool> showAdminCreateTicketDialog(
  BuildContext context,
  String adminMitgliedernummer,
  List<User> users,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _AdminCreateTicketDialog(
      adminMitgliedernummer: adminMitgliedernummer,
      users: users,
    ),
  );
  return result ?? false;
}

/// Admin Create Ticket Dialog - create ticket on behalf of a member
class _AdminCreateTicketDialog extends StatefulWidget {
  final String adminMitgliedernummer;
  final List<User> users;

  const _AdminCreateTicketDialog({
    required this.adminMitgliedernummer,
    required this.users,
  });

  @override
  State<_AdminCreateTicketDialog> createState() => _AdminCreateTicketDialogState();
}

class _AdminCreateTicketDialogState extends State<_AdminCreateTicketDialog> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _searchController = TextEditingController();
  final _ticketService = TicketService();
  String _priority = 'medium';
  bool _isSubmitting = false;
  User? _selectedMember;
  DateTime _scheduledDate = _nextWeekday(DateTime.now());
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 9, minute: 0);

  /// Returns the date itself if Mon-Fri, otherwise next Monday
  static DateTime _nextWeekday(DateTime d) {
    if (d.weekday == DateTime.saturday) return d.add(const Duration(days: 2));
    if (d.weekday == DateTime.sunday) return d.add(const Duration(days: 1));
    return d;
  }
  String _searchQuery = '';

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<User> get _filteredMembers {
    final members = widget.users.toList();

    if (_searchQuery.isEmpty) return members;

    final query = _searchQuery.toLowerCase();
    return members.where((u) {
      return u.name.toLowerCase().contains(query) ||
          u.mitgliedernummer.toLowerCase().contains(query) ||
          u.email.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _pickScheduledDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('de', 'DE'),
      selectableDayPredicate: (date) => date.weekday <= 5, // Mon-Fri only
    );
    if (picked != null) {
      setState(() => _scheduledDate = picked);
    }
  }

  Future<void> _pickScheduledTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime,
    );
    if (picked != null) {
      setState(() => _scheduledTime = picked);
    }
  }

  Future<void> _submitTicket() async {
    if (_selectedMember == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte wählen Sie ein Mitglied aus'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();

    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Betreff und Nachricht ausfüllen'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final scheduledDateTime = DateTime(
      _scheduledDate.year, _scheduledDate.month, _scheduledDate.day,
      _scheduledTime.hour, _scheduledTime.minute,
    );

    final result = await _ticketService.createTicketForMember(
      adminMitgliedernummer: widget.adminMitgliedernummer,
      memberMitgliedernummer: _selectedMember!.mitgliedernummer,
      subject: subject,
      message: message,
      priority: _priority,
      scheduledDate: DateFormat('yyyy-MM-dd HH:mm:ss').format(scheduledDateTime),
    );

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (result.containsKey('ticket')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticket für ${_selectedMember!.name} wurde erstellt'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Fehler beim Erstellen des Tickets'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'vorsitzer':
        return Colors.purple;
      case 'schatzmeister':
        return Colors.blue;
      case 'kassierer':
        return Colors.teal;
      case 'mitgliedergrunder':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.add_circle, color: Color(0xFF4a90d9)),
          SizedBox(width: 12),
          Text('Ticket für Mitglied erstellen'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Member picker
              const Text(
                'Mitglied auswählen:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (_selectedMember != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedMember!.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${_selectedMember!.mitgliedernummer} • ${_selectedMember!.email}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _selectedMember = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                )
              else ...[
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Name oder Mitgliedernummer suchen...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _filteredMembers.isEmpty
                      ? Center(
                          child: Text(
                            'Keine Mitglieder gefunden',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredMembers.length,
                          itemBuilder: (context, index) {
                            final member = _filteredMembers[index];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor: _getRoleColor(member.role).withAlpha(40),
                                child: Text(
                                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _getRoleColor(member.role),
                                  ),
                                ),
                              ),
                              title: Text(
                                member.name,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                member.mitgliedernummer,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedMember = member;
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
              const SizedBox(height: 16),

              // Subject
              TextField(
                controller: _subjectController,
                decoration: InputDecoration(
                  labelText: 'Betreff',
                  prefixIcon: const Icon(Icons.subject),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),

              // Message
              TextField(
                controller: _messageController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Nachricht',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 60),
                    child: Icon(Icons.message),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),

              // Priority
              Row(
                children: [
                  const Text('Priorität: '),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Niedrig'),
                    selected: _priority == 'low',
                    onSelected: (_) => setState(() => _priority = 'low'),
                    selectedColor: Colors.green.shade100,
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Mittel'),
                    selected: _priority == 'medium',
                    onSelected: (_) => setState(() => _priority = 'medium'),
                    selectedColor: Colors.orange.shade100,
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Hoch'),
                    selected: _priority == 'high',
                    onSelected: (_) => setState(() => _priority = 'high'),
                    selectedColor: Colors.red.shade100,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Scheduled date + time (mandatory)
              const Text(
                'Geplanter Termin: *',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickScheduledDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('dd.MM.yyyy').format(_scheduledDate)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickScheduledTime,
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(_scheduledTime.format(context)),
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
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitTicket,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4a90d9),
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Ticket erstellen'),
        ),
      ],
    );
  }
}
