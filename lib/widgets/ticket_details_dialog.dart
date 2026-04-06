import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/clipboard_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../services/ticket_service.dart';
import '../services/logger_service.dart';
import 'file_viewer_dialog.dart';

final _log = LoggerService();

/// Advanced Ticket Details Dialog for Admins
/// Features: Tabs (Details, Comments, History), File attachments, Chat-like UI
class TicketDetailsDialog extends StatefulWidget {
  final Ticket ticket;
  final String mitgliedernummer;
  final Function(int, String) onTicketAction;

  const TicketDetailsDialog({
    super.key,
    required this.ticket,
    required this.mitgliedernummer,
    required this.onTicketAction,
  });

  @override
  State<TicketDetailsDialog> createState() => _TicketDetailsDialogState();
}

class _TicketDetailsDialogState extends State<TicketDetailsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _ticketService = TicketService();
  final _commentController = TextEditingController();

  List<TicketComment> _comments = [];
  List<TicketAttachment> _attachments = [];
  TicketTranslation? _ticketTranslation;
  bool _isLoadingComments = true;
  bool _isSubmittingComment = false;
  bool _isInternal = false;
  DateTime? _scheduledDate;
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 9, minute: 0);
  // Track which comments show original text (toggle per comment)
  final Set<int> _showOriginalCommentIds = {};
  bool _showOriginalMessage = false;
  bool _showOriginalSubject = false;

  // Time tracking state
  List<TimeEntry> _timeEntries = [];
  TimeSummary? _timeSummary;
  TimeEntry? _runningEntry;
  bool _isLoadingTimeEntries = true;
  TimeCategory _selectedCategory = TimeCategory.arbeitszeit;
  Timer? _runningTimerTick;
  int _syncCounter = 0;

  // Aufgaben (tasks) state
  List<TicketAufgabe> _aufgaben = [];
  int _aufgabenOffen = 0;
  int _aufgabenErledigt = 0;
  bool _isLoadingAufgaben = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _scheduledDate = widget.ticket.scheduledDate;
    if (_scheduledDate != null) {
      _scheduledTime = TimeOfDay.fromDateTime(_scheduledDate!);
    }
    _loadComments();
    _loadTimeEntries();
    _loadAufgaben();
  }

  @override
  void dispose() {
    _runningTimerTick?.cancel();
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  // ==================== TIME TRACKING ====================

  Future<void> _loadTimeEntries() async {
    setState(() => _isLoadingTimeEntries = true);
    final result = await _ticketService.getTimeEntries(mitgliedernummer: widget.mitgliedernummer, ticketId: widget.ticket.id);
    if (mounted && result != null) {
      setState(() {
        _timeEntries = result.entries;
        _timeSummary = result.summary;
        _runningEntry = result.runningEntry;
        _isLoadingTimeEntries = false;
      });
      if (_runningEntry != null) {
        _startTimerTick();
      } else {
        _stopTimerTick();
      }
    } else if (mounted) {
      setState(() => _isLoadingTimeEntries = false);
    }
  }

  void _startTimerTick() {
    _runningTimerTick?.cancel();
    _syncCounter = 0;
    _runningTimerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _runningEntry != null) {
        _syncCounter++;
        if (_syncCounter >= 30) {
          _syncCounter = 0;
          _ticketService.syncTimer(mitgliedernummer: widget.mitgliedernummer);
        }
        setState(() {});
      }
    });
  }

  void _stopTimerTick() {
    _runningTimerTick?.cancel();
    _runningTimerTick = null;
  }

  Future<void> _startTimer() async {
    final entry = await _ticketService.startTimer(
      mitgliedernummer: widget.mitgliedernummer,
      ticketId: widget.ticket.id,
      category: _selectedCategory.name,
    );
    if (entry != null) {
      await _loadTimeEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Timer gestartet: ${_selectedCategory.display}'), backgroundColor: Colors.green),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timer konnte nicht gestartet werden. Möglicherweise läuft bereits ein Timer.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _stopTimer() async {
    final entry = await _ticketService.stopTimer(mitgliedernummer: widget.mitgliedernummer, ticketId: widget.ticket.id);
    if (entry != null) {
      _stopTimerTick();
      await _loadTimeEntries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Timer gestoppt: ${entry.durationDisplay}'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _deleteTimeEntry(TimeEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zeiterfassung löschen'),
        content: Text('${entry.category.display}: ${entry.durationDisplay} wirklich löschen?'),
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
      final success = await _ticketService.deleteTimeEntry(mitgliedernummer: widget.mitgliedernummer, timeEntryId: entry.id);
      if (success) await _loadTimeEntries();
    }
  }

  void _showManualTimeDialog() {
    final hoursCtrl = TextEditingController();
    final minutesCtrl = TextEditingController(text: '30');
    final noteCtrl = TextEditingController();
    var category = TimeCategory.arbeitszeit;
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Manuelle Zeiterfassung'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Kategorie', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: TimeCategory.values.map((cat) => ChoiceChip(
                    label: Text(cat.display),
                    selected: category == cat,
                    onSelected: (sel) { if (sel) setDialogState(() => category = cat); },
                    selectedColor: _timeCategoryColor(cat).withAlpha(60),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Dauer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(
                      controller: hoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Stunden', border: OutlineInputBorder()),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(
                      controller: minutesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minuten', border: OutlineInputBorder()),
                    )),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Datum', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setDialogState(() => selectedDate = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(DateFormat('dd.MM.yyyy').format(selectedDate)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Notiz (optional)', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () async {
                final hours = int.tryParse(hoursCtrl.text) ?? 0;
                final minutes = int.tryParse(minutesCtrl.text) ?? 0;
                final totalMinutes = hours * 60 + minutes;
                if (totalMinutes < 1) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mindestens 1 Minute erforderlich'), backgroundColor: Colors.red),
                    );
                  }
                  return;
                }
                final entry = await _ticketService.addManualTime(
                  mitgliedernummer: widget.mitgliedernummer,
                  ticketId: widget.ticket.id,
                  category: category.name,
                  durationMinutes: totalMinutes,
                  note: noteCtrl.text.isNotEmpty ? noteCtrl.text : null,
                  date: DateFormat('yyyy-MM-dd').format(selectedDate),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (entry != null) {
                  await _loadTimeEntries();
                  if (mounted) {
                    final h = totalMinutes ~/ 60;
                    final m = totalMinutes % 60;
                    final durationStr = h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Zeiterfassung gespeichert: $durationStr'), backgroundColor: Colors.green),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fehler beim Speichern der Zeiterfassung'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Color _timeCategoryColor(TimeCategory cat) {
    switch (cat) {
      case TimeCategory.fahrzeit:
        return Colors.blue;
      case TimeCategory.arbeitszeit:
        return Colors.green;
      case TimeCategory.wartezeit:
        return Colors.orange;
    }
  }

  IconData _timeCategoryIcon(TimeCategory cat) {
    switch (cat) {
      case TimeCategory.fahrzeit:
        return Icons.directions_car;
      case TimeCategory.arbeitszeit:
        return Icons.work;
      case TimeCategory.wartezeit:
        return Icons.hourglass_empty;
    }
  }

  Future<void> _loadComments() async {
    setState(() => _isLoadingComments = true);

    // Mark ticket as viewed when opening
    await _markTicketAsViewed();

    final result = await _ticketService.getComments(
      mitgliedernummer: widget.mitgliedernummer,
      ticketId: widget.ticket.id,
    );

    if (mounted && result != null) {
      setState(() {
        _comments = result.comments;
        _attachments = result.attachments;
        _ticketTranslation = result.ticketTranslation;
        _isLoadingComments = false;
      });
    }
  }

  Future<void> _markTicketAsViewed() async {
    try {
      await _ticketService.markTicketAsViewed(widget.ticket.id);
    } catch (e) {
      _log.debug('Failed to mark ticket as viewed: $e', tag: 'TICKET');
    }
  }


  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) {
      _log.warning('Submit comment: Text is empty', tag: 'TICKET');
      return;
    }

    _log.info('Submit comment: Starting (ticketId=${widget.ticket.id}, isInternal=$_isInternal, text length=${text.length})', tag: 'TICKET');

    setState(() => _isSubmittingComment = true);

    _log.debug('Submit comment: Calling API addComment()', tag: 'TICKET');

    final comment = await _ticketService.addComment(
      mitgliedernummer: widget.mitgliedernummer,
      ticketId: widget.ticket.id,
      comment: text,
      isInternal: _isInternal,
    );

    _log.info('Submit comment: API response received (comment is ${comment != null ? "NOT NULL" : "NULL"})', tag: 'TICKET');

    if (mounted) {
      setState(() => _isSubmittingComment = false);

      if (comment != null) {
        _log.info('Submit comment: SUCCESS - Adding comment to list (id=${comment.id})', tag: 'TICKET');
        setState(() {
          _comments.add(comment);
          _commentController.clear();
          _isInternal = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kommentar hinzugefügt'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        _log.error('Submit comment: FAILED - API returned null', tag: 'TICKET');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Hinzufügen des Kommentars'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAttachOptions() {
    final RenderBox button = context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        button.size.width - 200,
        button.size.height - 120,
        button.size.width,
        button.size.height,
      ),
      items: [
        const PopupMenuItem(
          value: 'file',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 20),
              SizedBox(width: 12),
              Text('Dateien auswählen'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'camera',
          child: Row(
            children: [
              Icon(Icons.camera_alt, size: 20),
              SizedBox(width: 12),
              Text('Foto aufnehmen'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'file') {
        _pickAndUploadFile();
      } else if (value == 'camera') {
        _captureAndUploadPhoto();
      }
    });
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'pdf', 'txt', 'zip'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    // Max 20 files at once
    if (result.files.length > 20) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximal 20 Dateien gleichzeitig erlaubt'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Check total size (max 100MB)
    final totalSize = result.files.fold<int>(0, (sum, f) => sum + f.size);
    if (totalSize > 100 * 1024 * 1024) {
      if (mounted) {
        final sizeMB = (totalSize / (1024 * 1024)).toStringAsFixed(1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gesamtgröße $sizeMB MB überschreitet das Limit von 100 MB'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Filter out files without path or too large individually
    final validFiles = result.files.where((f) => f.path != null).toList();
    if (validFiles.isEmpty) return;

    await _uploadMultipleFiles(validFiles);
  }

  Future<void> _uploadMultipleFiles(List<PlatformFile> files) async {
    if (!mounted) return;

    int uploaded = 0;
    int failed = 0;
    final total = files.length;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Dateien werden hochgeladen... ${uploaded + failed}/$total',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: total > 0 ? (uploaded + failed) / total : 0,
                ),
                if (uploaded > 0 || failed > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$uploaded erfolgreich${failed > 0 ? ', $failed fehlgeschlagen' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );

    for (final file in files) {
      final attachment = await _ticketService.uploadAttachment(
        mitgliedernummer: widget.mitgliedernummer,
        ticketId: widget.ticket.id,
        filePath: file.path!,
      );

      if (attachment != null) {
        uploaded++;
        if (mounted) setState(() => _attachments.add(attachment));
      } else {
        failed++;
      }

      // Update dialog - rebuild by popping and re-showing would be complex,
      // but the StatefulBuilder handles it via the outer setState
    }

    if (mounted) {
      Navigator.pop(context); // Close progress dialog

      if (failed == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$uploaded ${uploaded == 1 ? 'Datei' : 'Dateien'} erfolgreich hochgeladen'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$uploaded hochgeladen, $failed fehlgeschlagen'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _captureAndUploadPhoto() async {
    if (Platform.isMacOS) {
      await _captureWithMacOSCamera();
    } else {
      await _captureWithImagePicker();
    }
  }

  Future<void> _captureWithMacOSCamera() async {
    if (!mounted) return;

    // Show camera dialog with live preview
    final filePath = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _MacOSCameraDialog(),
    );

    if (filePath != null && filePath.isNotEmpty) {
      await _uploadFile(filePath);
    }
  }

  Future<void> _captureWithImagePicker() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null) return;
      await _uploadFile(photo.path);
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kamera nicht verfügbar: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadFile(String filePath) async {
    if (!mounted) return;

    // Show uploading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Datei wird hochgeladen...'),
          ],
        ),
      ),
    );

    final attachment = await _ticketService.uploadAttachment(
      mitgliedernummer: widget.mitgliedernummer,
      ticketId: widget.ticket.id,
      filePath: filePath,
    );

    if (mounted) {
      Navigator.pop(context); // Close upload dialog

      if (attachment != null) {
        setState(() => _attachments.add(attachment));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Datei "${attachment.originalFilename}" hochgeladen'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Hochladen der Datei'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      case 'waiting_documents':
        return Colors.brown;
      case 'done':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.fiber_new;
      case 'in_progress':
        return Icons.engineering;
      case 'waiting_member':
        return Icons.person_outline;
      case 'waiting_staff':
        return Icons.groups_outlined;
      case 'waiting_authority':
        return Icons.account_balance;
      case 'waiting_documents':
        return Icons.description;
      case 'done':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildStatusButton({
    required String label,
    required IconData icon,
    required Color color,
    required String action,
  }) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.pop(context);
        widget.onTicketAction(widget.ticket.id, action);
      },
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withAlpha(120)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std';
    if (diff.inDays < 7) return 'vor ${diff.inDays} Tag${diff.inDays > 1 ? 'en' : ''}';

    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 800,
        height: 700,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStatusColor(widget.ticket.status).withAlpha(30),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.confirmation_number, color: _getStatusColor(widget.ticket.status)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ticket #${widget.ticket.id}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getStatusColor(widget.ticket.status).withAlpha(100),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.ticket.statusDisplay,
                          style: TextStyle(
                            color: _getStatusColor(widget.ticket.status),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Subject with translation toggle
                  if (_ticketTranslation != null && _ticketTranslation!.subjectIsTranslated)
                    GestureDetector(
                      onTap: () => setState(() => _showOriginalSubject = !_showOriginalSubject),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _showOriginalSubject
                                  ? _ticketTranslation!.originalSubject!
                                  : _ticketTranslation!.subject,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: _showOriginalSubject ? 'Übersetzung anzeigen' : 'Original anzeigen',
                            child: Icon(Icons.translate, size: 16, color: Colors.blue.shade400),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      widget.ticket.subject,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: Colors.blue.shade700,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue.shade700,
              tabs: [
                const Tab(icon: Icon(Icons.info_outline), text: 'Details'),
                Tab(icon: const Icon(Icons.checklist), text: 'Aufgaben${_aufgabenOffen > 0 ? ' ($_aufgabenOffen)' : ''}'),
                const Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Kommentare'),
                const Tab(icon: Icon(Icons.folder_outlined), text: 'Dokumente'),
                const Tab(icon: Icon(Icons.timer_outlined), text: 'Zeiterfassung'),
                const Tab(icon: Icon(Icons.history), text: 'Verlauf'),
              ],
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildDetailsTab(),
                  _buildAufgabenTab(),
                  _buildCommentsTab(),
                  _buildDokumenteTab(),
                  _buildZeiterfassungTab(),
                  _buildHistoryTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasMemberPersonalData() {
    final t = widget.ticket;
    return (t.memberVorname != null && t.memberVorname!.isNotEmpty) ||
           (t.memberNachname != null && t.memberNachname!.isNotEmpty) ||
           (t.memberStrasse != null && t.memberStrasse!.isNotEmpty) ||
           (t.memberTelefon != null && t.memberTelefon!.isNotEmpty);
  }

  Widget _buildMemberPersonalDataCard() {
    final t = widget.ticket;
    final rows = <Widget>[];

    void addRow(IconData icon, String label, String? value) {
      if (value != null && value.isNotEmpty) {
        // Format geburtsdatum from YYYY-MM-DD to DD.MM.YYYY
        String displayValue = value;
        if (label == 'Geburtsdatum' && value.contains('-') && value.length == 10) {
          final parts = value.split('-');
          displayValue = '${parts[2]}.${parts[1]}.${parts[0]}';
        }
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(icon, size: 15, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
              Expanded(
                child: Text(displayValue, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ));
      }
    }

    addRow(Icons.person, 'Vorname', t.memberVorname);
    addRow(Icons.person, 'Nachname', t.memberNachname);
    addRow(Icons.cake, 'Geburtsdatum', t.memberGeburtsdatum);

    // Combine address
    final adresse = [t.memberStrasse, t.memberHausnummer].where((s) => s != null && s.isNotEmpty).join(' ');
    final plzOrt = [t.memberPlz, t.memberOrt].where((s) => s != null && s.isNotEmpty).join(' ');
    if (adresse.isNotEmpty) addRow(Icons.home, 'Adresse', adresse);
    if (plzOrt.isNotEmpty) addRow(Icons.location_on, 'PLZ / Ort', plzOrt);

    addRow(Icons.phone, 'Telefon', t.memberTelefon);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user, size: 16, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Text('Persönliche Daten', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade700)),
            ],
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Member Info
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                child: Icon(Icons.person, color: Colors.blue.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.ticket.memberName ?? 'Unbekannt',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      widget.ticket.memberNummer ?? '',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Priority badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getPriorityColor(widget.ticket.priority).withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Priorität: ${widget.ticket.priorityDisplay}',
                  style: TextStyle(
                    color: _getPriorityColor(widget.ticket.priority),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Member personal data (Stufe 1)
          if (_hasMemberPersonalData()) _buildMemberPersonalDataCard(),

          const SizedBox(height: 16),

          // Category
          if (widget.ticket.categoryName != null) ...[
            Row(
              children: [
                Icon(Icons.category, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  'Kategorie: ${widget.ticket.categoryName}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Original Message
          Row(
            children: [
              const Text(
                'Ursprüngliche Nachricht:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (_ticketTranslation != null && _ticketTranslation!.messageIsTranslated) ...[
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showOriginalMessage = !_showOriginalMessage),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.translate, size: 14, color: Colors.blue.shade600),
                        const SizedBox(width: 4),
                        Text(
                          _showOriginalMessage ? 'Übersetzung' : 'Original',
                          style: TextStyle(fontSize: 11, color: Colors.blue.shade600, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  (_ticketTranslation != null && _ticketTranslation!.messageIsTranslated)
                      ? (_showOriginalMessage
                          ? _ticketTranslation!.originalMessage!
                          : _ticketTranslation!.message)
                      : widget.ticket.message,
                  style: const TextStyle(fontSize: 14),
                ),
                if (_ticketTranslation != null && _ticketTranslation!.messageIsTranslated) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 12, color: Colors.blue.shade400),
                      const SizedBox(width: 4),
                      Text(
                        _showOriginalMessage ? 'Originaltext' : 'Automatisch übersetzt',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade400, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Dates
          _buildInfoRow(Icons.calendar_today, 'Erstellt', _formatDate(widget.ticket.createdAt)),
          if (widget.ticket.updatedAt != null)
            _buildInfoRow(Icons.update, 'Aktualisiert', _formatDate(widget.ticket.updatedAt!)),
          if (widget.ticket.adminName != null)
            _buildInfoRow(Icons.support_agent, 'Bearbeiter', widget.ticket.adminName!),
          if (widget.ticket.closedAt != null)
            _buildInfoRow(Icons.check_circle, 'Abgeschlossen', _formatDate(widget.ticket.closedAt!)),

          const SizedBox(height: 16),

          // Scheduled Date + Time picker
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Geplant für:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _scheduledDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            locale: const Locale('de', 'DE'),
                          );
                          if (picked != null) {
                            final dt = DateTime(picked.year, picked.month, picked.day, _scheduledTime.hour, _scheduledTime.minute);
                            final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
                            final result = await _ticketService.updateTicket(
                              mitgliedernummer: widget.mitgliedernummer,
                              ticketId: widget.ticket.id,
                              action: 'set_scheduled_date',
                              scheduledDate: dateStr,
                            );
                            if (result != null && mounted) {
                              setState(() => _scheduledDate = dt);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Ticket geplant für ${DateFormat('dd.MM.yyyy HH:mm').format(dt)}'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: Text(
                          _scheduledDate != null
                              ? DateFormat('dd.MM.yyyy').format(_scheduledDate!)
                              : 'Datum wählen',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _scheduledTime,
                          );
                          if (picked != null) {
                            final date = _scheduledDate ?? DateTime.now();
                            final dt = DateTime(date.year, date.month, date.day, picked.hour, picked.minute);
                            final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
                            final result = await _ticketService.updateTicket(
                              mitgliedernummer: widget.mitgliedernummer,
                              ticketId: widget.ticket.id,
                              action: 'set_scheduled_date',
                              scheduledDate: dateStr,
                            );
                            if (result != null && mounted) {
                              setState(() {
                                _scheduledTime = picked;
                                _scheduledDate = dt;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Uhrzeit geändert auf ${picked.format(context)}'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(
                          _scheduledTime.format(context),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Status change section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 18, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Status ändern',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Current status display
                Row(
                  children: [
                    const Text('Aktuell: ', style: TextStyle(fontSize: 13)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(widget.ticket.status).withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _getStatusColor(widget.ticket.status).withAlpha(120)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getStatusIcon(widget.ticket.status), size: 14, color: _getStatusColor(widget.ticket.status)),
                          const SizedBox(width: 6),
                          Text(
                            widget.ticket.statusDisplay,
                            style: TextStyle(
                              color: _getStatusColor(widget.ticket.status),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Status action buttons - show all except current status
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (widget.ticket.status == 'open')
                      _buildStatusButton(
                        label: 'Übernehmen',
                        icon: Icons.person_add,
                        color: Colors.blue,
                        action: 'assign',
                      ),
                    if (widget.ticket.status != 'in_progress')
                      _buildStatusButton(
                        label: 'In Bearbeitung',
                        icon: Icons.engineering,
                        color: Colors.purple,
                        action: 'set_in_progress',
                      ),
                    if (widget.ticket.status != 'waiting_member')
                      _buildStatusButton(
                        label: 'Warten auf Benutzer',
                        icon: Icons.person_outline,
                        color: Colors.blue,
                        action: 'set_waiting_member',
                      ),
                    if (widget.ticket.status != 'waiting_staff')
                      _buildStatusButton(
                        label: 'Warten auf Mitarbeiter',
                        icon: Icons.groups_outlined,
                        color: Colors.teal,
                        action: 'set_waiting_staff',
                      ),
                    if (widget.ticket.status != 'waiting_authority')
                      _buildStatusButton(
                        label: 'Warten auf Behörde',
                        icon: Icons.account_balance,
                        color: Colors.indigo,
                        action: 'set_waiting_authority',
                      ),
                    if (widget.ticket.status != 'waiting_documents')
                      _buildStatusButton(
                        label: 'Warten auf Unterlagen',
                        icon: Icons.description,
                        color: Colors.brown,
                        action: 'set_waiting_documents',
                      ),
                    if (widget.ticket.status != 'done')
                      _buildStatusButton(
                        label: 'Erledigt',
                        icon: Icons.check_circle,
                        color: Colors.green,
                        action: 'done',
                      ),
                    if (widget.ticket.status != 'open' && widget.ticket.status == 'done')
                      _buildStatusButton(
                        label: 'Wiedereröffnen',
                        icon: Icons.replay,
                        color: Colors.orange,
                        action: 'reopen',
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

  Widget _buildCommentsTab() {
    return Column(
      children: [
        // Comments list
        Expanded(
          child: _isLoadingComments
              ? const Center(child: CircularProgressIndicator())
              : _comments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Noch keine Kommentare',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Schreiben Sie den ersten Kommentar',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        return _buildCommentBubble(comment);
                      },
                    ),
        ),

        // Comment input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Kommentar schreiben...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      IconButton(
                        onPressed: _showAttachOptions,
                        icon: const Icon(Icons.attach_file),
                        tooltip: 'Datei anhängen',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        onPressed: _isSubmittingComment ? null : _submitComment,
                        icon: _isSubmittingComment
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                        tooltip: 'Senden',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _isInternal,
                onChanged: (val) => setState(() => _isInternal = val ?? false),
                title: const Text('Interner Kommentar', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  'Nur für Admins sichtbar',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== DOKUMENTE TAB ====================

  Widget _buildDokumenteTab() {
    return Column(
      children: [
        // Header with upload button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              Icon(Icons.folder, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Dokumente (${_attachments.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showAttachOptions,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Hochladen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),

        // Attachments list
        Expanded(
          child: _attachments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'Keine Dokumente vorhanden',
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Erlaubte Formate: PDF, JPEG, JPG, TXT, ZIP',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _attachments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final att = _attachments[index];
                    return _buildDocumentListItem(att);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDocumentListItem(TicketAttachment attachment) {
    final ext = attachment.originalFilename.split('.').last.toLowerCase();
    IconData fileIcon;
    Color iconColor;
    switch (ext) {
      case 'pdf':
        fileIcon = Icons.picture_as_pdf;
        iconColor = Colors.red;
        break;
      case 'jpg':
      case 'jpeg':
        fileIcon = Icons.image;
        iconColor = Colors.blue;
        break;
      case 'txt':
        fileIcon = Icons.description;
        iconColor = Colors.grey.shade700;
        break;
      case 'zip':
        fileIcon = Icons.folder_zip;
        iconColor = Colors.amber.shade700;
        break;
      default:
        fileIcon = Icons.insert_drive_file;
        iconColor = Colors.grey;
    }

    final sizeStr = attachment.filesize < 1024
        ? '${attachment.filesize} B'
        : attachment.filesize < 1024 * 1024
            ? '${(attachment.filesize / 1024).toStringAsFixed(1)} KB'
            : '${(attachment.filesize / (1024 * 1024)).toStringAsFixed(1)} MB';

    return InkWell(
      onTap: () => _openAttachment(attachment),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(fileIcon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.originalFilename,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      ext.toUpperCase(),
                      sizeStr,
                      DateFormat('dd.MM.yyyy HH:mm').format(attachment.createdAt),
                    ].join(' · '),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Icon(Icons.download, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachment(TicketAttachment attachment) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Datei wird heruntergeladen...'),
          ],
        ),
      ),
    );

    final filePath = await _ticketService.downloadAttachment(
      mitgliedernummer: widget.mitgliedernummer,
      attachmentId: attachment.id,
      originalFilename: attachment.originalFilename,
    );

    if (mounted) {
      Navigator.pop(context);

      if (filePath != null) {
        final handledInApp = await FileViewerDialog.show(
          context, filePath, attachment.originalFilename,
        );
        if (!handledInApp) {
          try {
            if (Platform.isMacOS) {
              await Process.run('open', [filePath]);
            } else if (Platform.isWindows) {
              await Process.run('cmd', ['/c', 'start', '', filePath]);
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Fehler beim Öffnen der Datei'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Herunterladen der Datei'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildCommentBubble(TicketComment comment) {
    final adminRoles = ['vorsitzer', 'schatzmeister', 'kassierer', 'mitgliedergrunder'];
    final isAdmin = adminRoles.contains(comment.userRole.toLowerCase());
    final isMember = !isAdmin; // Orice non-admin e membru

    // Avatar
    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor: isMember ? Colors.green : Colors.blue,
      child: Text(
        comment.userName.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );

    // Message content
    final messageContent = Flexible(
      child: Column(
        crossAxisAlignment: isMember ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Name + Timestamp
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMember) ...[
                Text(
                  comment.userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDate(comment.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ] else ...[
                Text(
                  _formatDate(comment.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  comment.userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Message bubble
          GestureDetector(
            onDoubleTap: () {
              final text = (comment.isTranslated && _showOriginalCommentIds.contains(comment.id))
                  ? comment.originalComment!
                  : comment.comment;
              ClipboardHelper.copy(context, text, 'Kommentar');
              // Note: ClipboardHelper already shows SnackBar
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kommentar kopiert'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            onTap: comment.isTranslated
                ? () => setState(() {
                      if (_showOriginalCommentIds.contains(comment.id)) {
                        _showOriginalCommentIds.remove(comment.id);
                      } else {
                        _showOriginalCommentIds.add(comment.id);
                      }
                    })
                : null,
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 400,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMember ? Colors.green.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isMember ? 4 : 16),
                  topRight: Radius.circular(isMember ? 16 : 4),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(16),
                ),
                border: Border.all(
                  color: isMember ? Colors.green.shade200 : Colors.blue.shade200,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (comment.isTranslated && _showOriginalCommentIds.contains(comment.id))
                        ? comment.originalComment!
                        : comment.comment,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  if (comment.isTranslated) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.translate, size: 12, color: Colors.blue.shade400),
                        const SizedBox(width: 4),
                        Text(
                          _showOriginalCommentIds.contains(comment.id)
                              ? 'Originaltext · Tippen für Übersetzung'
                              : 'Übersetzt · Tippen für Original',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue.shade400,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Internal comment badge
          if (comment.isInternal) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 12, color: Colors.orange.shade800),
                  const SizedBox(width: 4),
                  Text(
                    'Intern',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    // Main row layout - Chat style!
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMember ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isMember) avatar,
          if (isMember) const SizedBox(width: 12),
          messageContent,
          if (isAdmin) const SizedBox(width: 12),
          if (isAdmin) avatar,
        ],
      ),
    );
  }

  Widget _buildZeiterfassungTab() {
    if (_isLoadingTimeEntries) {
      return const Center(child: CircularProgressIndicator());
    }

    final summary = _timeSummary;
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return Column(
      children: [
        // Timer section + summary (fixed at top)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _runningEntry != null ? Colors.red.shade50 : Colors.grey.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category selector
              Row(
                children: [
                  Icon(Icons.timer, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text('Timer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey.shade700)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: TimeCategory.values.map((cat) => ChoiceChip(
                  avatar: Icon(_timeCategoryIcon(cat), size: 16, color: _selectedCategory == cat ? Colors.white : _timeCategoryColor(cat)),
                  label: Text(cat.display),
                  selected: _selectedCategory == cat,
                  selectedColor: _timeCategoryColor(cat),
                  labelStyle: TextStyle(color: _selectedCategory == cat ? Colors.white : null, fontSize: 12),
                  onSelected: _runningEntry != null ? null : (sel) {
                    if (sel) setState(() => _selectedCategory = cat);
                  },
                )).toList(),
              ),
              const SizedBox(height: 12),

              // Start/Stop button
              if (_runningEntry == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startTimer,
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: Text('Timer starten (${_selectedCategory.display})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _timeCategoryColor(_selectedCategory),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(_timeCategoryIcon(_runningEntry!.category), size: 20, color: _timeCategoryColor(_runningEntry!.category)),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_runningEntry!.category.display, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          Text(
                            _runningEntry!.durationDisplay,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _stopTimer,
                        icon: const Icon(Icons.stop, size: 20),
                        label: const Text('Stopp'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Summary cards
              if (summary != null)
                Row(
                  children: [
                    _buildSummaryCard(Icons.directions_car, 'Fahrzeit', summary.fahrzeitDisplay, Colors.blue),
                    const SizedBox(width: 8),
                    _buildSummaryCard(Icons.work, 'Arbeitszeit', summary.arbeitszeitDisplay, Colors.green),
                    const SizedBox(width: 8),
                    _buildSummaryCard(Icons.hourglass_empty, 'Wartezeit', summary.wartezeitDisplay, Colors.orange),
                    const SizedBox(width: 8),
                    _buildSummaryCard(Icons.functions, 'Gesamt', summary.gesamtDisplay, Colors.grey.shade700),
                  ],
                ),
            ],
          ),
        ),

        // Manual entry button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _showManualTimeDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Manuell hinzufügen', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadTimeEntries,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Aktualisieren',
              ),
            ],
          ),
        ),

        // Time entries list
        Expanded(
          child: _timeEntries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer_off, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('Noch keine Zeiteinträge', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _timeEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _timeEntries[index];
                    final color = _timeCategoryColor(entry.category);
                    final icon = _timeCategoryIcon(entry.category);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: color.withAlpha(80)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // Category icon
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(icon, size: 18, color: color),
                            ),
                            const SizedBox(width: 12),
                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(entry.category.display, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
                                      if (entry.isManual) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('Manuell', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                        ),
                                      ],
                                      if (entry.isRunning) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade100,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('Läuft', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  if (entry.isManual && entry.startedAt != null)
                                    Text(DateFormat('dd.MM.yyyy').format(entry.startedAt!), style: TextStyle(fontSize: 11, color: Colors.grey.shade600))
                                  else if (!entry.isManual && entry.startedAt != null)
                                    Text(
                                      '${dateFormat.format(entry.startedAt!)}${entry.stoppedAt != null ? ' – ${DateFormat('HH:mm').format(entry.stoppedAt!)}' : ''}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  if (entry.note != null && entry.note!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(entry.note!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ),
                                ],
                              ),
                            ),
                            // Duration
                            Text(
                              entry.durationDisplay,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace', color: entry.isRunning ? Colors.red : null),
                            ),
                            // Delete
                            if (!entry.isRunning)
                              IconButton(
                                onPressed: () => _deleteTimeEntry(entry),
                                icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade400),
                                tooltip: 'Löschen',
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: color.withAlpha(180))),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Aufgaben (Tasks) Tab
  // ============================================================

  Future<void> _loadAufgaben() async {
    setState(() => _isLoadingAufgaben = true);
    final result = await _ticketService.getAufgaben(
      mitgliedernummer: widget.mitgliedernummer,
      ticketId: widget.ticket.id,
    );
    if (mounted) {
      setState(() {
        if (result != null) {
          _aufgaben = result.aufgaben;
          _aufgabenOffen = result.offen;
          _aufgabenErledigt = result.erledigt;
        }
        _isLoadingAufgaben = false;
      });
    }
  }

  Future<void> _toggleAufgabe(TicketAufgabe aufgabe) async {
    final result = await _ticketService.toggleAufgabe(
      mitgliedernummer: widget.mitgliedernummer,
      aufgabeId: aufgabe.id,
    );
    if (result != null) {
      _loadAufgaben();
    }
  }

  Future<void> _deleteAufgabe(TicketAufgabe aufgabe) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufgabe löschen'),
        content: Text('Möchten Sie die Aufgabe "${aufgabe.title}" wirklich löschen?'),
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
      final ok = await _ticketService.deleteAufgabe(
        mitgliedernummer: widget.mitgliedernummer,
        aufgabeId: aufgabe.id,
      );
      if (ok) _loadAufgaben();
    }
  }

  void _showCreateAufgabeDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'mittel';
    DateTime? dueDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_task, color: Colors.teal.shade600),
              const SizedBox(width: 8),
              const Text('Neue Aufgabe'),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      hintText: 'Was muss erledigt werden?',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      hintText: 'Optionale Details...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    decoration: const InputDecoration(
                      labelText: 'Priorität',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'niedrig', child: Text('Niedrig')),
                      DropdownMenuItem(value: 'mittel', child: Text('Mittel')),
                      DropdownMenuItem(value: 'hoch', child: Text('Hoch')),
                      DropdownMenuItem(value: 'dringend', child: Text('Dringend')),
                    ],
                    onChanged: (v) => setDialogState(() => priority = v ?? 'mittel'),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: dueDate ?? DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('de'),
                      );
                      if (picked != null) setDialogState(() => dueDate = picked);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Fälligkeitsdatum',
                        border: const OutlineInputBorder(),
                        suffixIcon: dueDate != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setDialogState(() => dueDate = null),
                              )
                            : const Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        dueDate != null
                            ? DateFormat('dd.MM.yyyy').format(dueDate!)
                            : 'Kein Datum',
                        style: TextStyle(
                          color: dueDate != null ? null : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Erstellen'),
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final result = await _ticketService.createAufgabe(
                  mitgliedernummer: widget.mitgliedernummer,
                  ticketId: widget.ticket.id,
                  title: titleCtrl.text.trim(),
                  description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                  priority: priority,
                  dueDate: dueDate != null ? DateFormat('yyyy-MM-dd').format(dueDate!) : null,
                );
                if (result != null) _loadAufgaben();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAufgabeDialog(TicketAufgabe aufgabe) {
    final titleCtrl = TextEditingController(text: aufgabe.title);
    final descCtrl = TextEditingController(text: aufgabe.description ?? '');
    String priority = aufgabe.priority;
    DateTime? dueDate = aufgabe.dueDate != null ? DateTime.tryParse(aufgabe.dueDate!) : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.teal.shade600),
              const SizedBox(width: 8),
              const Text('Aufgabe bearbeiten'),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    decoration: const InputDecoration(
                      labelText: 'Priorität',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'niedrig', child: Text('Niedrig')),
                      DropdownMenuItem(value: 'mittel', child: Text('Mittel')),
                      DropdownMenuItem(value: 'hoch', child: Text('Hoch')),
                      DropdownMenuItem(value: 'dringend', child: Text('Dringend')),
                    ],
                    onChanged: (v) => setDialogState(() => priority = v ?? 'mittel'),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: dueDate ?? DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('de'),
                      );
                      if (picked != null) setDialogState(() => dueDate = picked);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Fälligkeitsdatum',
                        border: const OutlineInputBorder(),
                        suffixIcon: dueDate != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setDialogState(() => dueDate = null),
                              )
                            : const Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        dueDate != null
                            ? DateFormat('dd.MM.yyyy').format(dueDate!)
                            : 'Kein Datum',
                        style: TextStyle(
                          color: dueDate != null ? null : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Speichern'),
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await _ticketService.updateAufgabe(
                  mitgliedernummer: widget.mitgliedernummer,
                  aufgabeId: aufgabe.id,
                  title: titleCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  priority: priority,
                  dueDate: dueDate != null ? DateFormat('yyyy-MM-dd').format(dueDate!) : null,
                );
                _loadAufgaben();
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'dringend': return Colors.red.shade600;
      case 'hoch': return Colors.orange.shade600;
      case 'mittel': return Colors.blue.shade600;
      case 'niedrig': return Colors.grey.shade500;
      default: return Colors.blue.shade600;
    }
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case 'dringend': return 'Dringend';
      case 'hoch': return 'Hoch';
      case 'mittel': return 'Mittel';
      case 'niedrig': return 'Niedrig';
      default: return priority;
    }
  }

  IconData _priorityIcon(String priority) {
    switch (priority) {
      case 'dringend': return Icons.priority_high;
      case 'hoch': return Icons.arrow_upward;
      case 'mittel': return Icons.remove;
      case 'niedrig': return Icons.arrow_downward;
      default: return Icons.remove;
    }
  }

  Widget _buildAufgabenTab() {
    if (_isLoadingAufgaben) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Header with stats and add button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Icon(Icons.checklist, size: 20, color: Colors.teal.shade600),
              const SizedBox(width: 8),
              Text(
                '${_aufgaben.length} Aufgaben',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              if (_aufgabenOffen > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_aufgabenOffen offen',
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
              if (_aufgabenErledigt > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_aufgabenErledigt erledigt',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
              const Spacer(),
              // Progress indicator
              if (_aufgaben.isNotEmpty) ...[
                SizedBox(
                  width: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _aufgaben.isEmpty ? 0 : _aufgabenErledigt / _aufgaben.length,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(Colors.teal.shade400),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${(_aufgaben.isEmpty ? 0 : (_aufgabenErledigt / _aufgaben.length * 100)).toInt()}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 12),
              ],
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Aufgabe'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                onPressed: _showCreateAufgabeDialog,
              ),
            ],
          ),
        ),

        // Aufgaben list
        Expanded(
          child: _aufgaben.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.task_alt, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'Keine Aufgaben',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Erstellen Sie Aufgaben, um den Fortschritt zu verfolgen',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _aufgaben.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final aufgabe = _aufgaben[index];
                    final isOverdue = aufgabe.dueDate != null &&
                        !aufgabe.isErledigt &&
                        DateTime.tryParse(aufgabe.dueDate!)?.isBefore(DateTime.now()) == true;

                    return Card(
                      elevation: aufgabe.isErledigt ? 0 : 1,
                      color: aufgabe.isErledigt ? Colors.grey.shade50 : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isOverdue
                              ? Colors.red.shade300
                              : aufgabe.isErledigt
                                  ? Colors.grey.shade200
                                  : Colors.grey.shade300,
                          width: isOverdue ? 1.5 : 0.5,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _showEditAufgabeDialog(aufgabe),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Checkbox
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => _toggleAufgabe(aufgabe),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: aufgabe.isErledigt ? Colors.teal.shade400 : Colors.transparent,
                                      border: Border.all(
                                        color: aufgabe.isErledigt ? Colors.teal.shade400 : Colors.grey.shade400,
                                        width: 2,
                                      ),
                                    ),
                                    child: aufgabe.isErledigt
                                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title
                                    Text(
                                      aufgabe.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        decoration: aufgabe.isErledigt ? TextDecoration.lineThrough : null,
                                        color: aufgabe.isErledigt ? Colors.grey.shade500 : null,
                                      ),
                                    ),
                                    // Description
                                    if (aufgabe.description != null && aufgabe.description!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          aufgabe.description!,
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    // Meta row
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        // Priority chip
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: _priorityColor(aufgabe.priority).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(_priorityIcon(aufgabe.priority), size: 11, color: _priorityColor(aufgabe.priority)),
                                              const SizedBox(width: 3),
                                              Text(
                                                _priorityLabel(aufgabe.priority),
                                                style: TextStyle(fontSize: 10, color: _priorityColor(aufgabe.priority), fontWeight: FontWeight.w500),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Due date
                                        if (aufgabe.dueDate != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: isOverdue ? Colors.red.shade50 : Colors.grey.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.calendar_today,
                                                  size: 10,
                                                  color: isOverdue ? Colors.red.shade600 : Colors.grey.shade600,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  _formatDueDate(aufgabe.dueDate!),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isOverdue ? Colors.red.shade600 : Colors.grey.shade600,
                                                    fontWeight: isOverdue ? FontWeight.w600 : null,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        // Created by
                                        if (aufgabe.createdByName != null)
                                          Text(
                                            'von ${aufgabe.createdByName}',
                                            style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Delete button
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade400),
                                padding: EdgeInsets.zero,
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Bearbeiten'), dense: true, contentPadding: EdgeInsets.zero)),
                                  const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Löschen', style: TextStyle(color: Colors.red)), dense: true, contentPadding: EdgeInsets.zero)),
                                ],
                                onSelected: (action) {
                                  if (action == 'edit') _showEditAufgabeDialog(aufgabe);
                                  if (action == 'delete') _deleteAufgabe(aufgabe);
                                },
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

  String _formatDueDate(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Heute';
    if (d == tomorrow) return 'Morgen';
    if (d.isBefore(today)) return 'Überfällig (${DateFormat('dd.MM').format(date)})';
    return DateFormat('dd.MM.yyyy').format(date);
  }

  Widget _buildHistoryTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Verlauf wird geladen...',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Funktion wird bald verfügbar sein',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// macOS native camera dialog using camera_macos (AVFoundation)
/// Flow: Camera -> Crop -> Upload
class _MacOSCameraDialog extends StatefulWidget {
  const _MacOSCameraDialog();

  @override
  State<_MacOSCameraDialog> createState() => _MacOSCameraDialogState();
}

enum _CameraStep { camera, crop, preview }

class _MacOSCameraDialogState extends State<_MacOSCameraDialog> {
  CameraMacOSController? _cameraController;
  Uint8List? _capturedBytes;
  Uint8List? _croppedBytes;
  bool _isCapturing = false;
  bool _isCropping = false;
  String? _error;
  _CameraStep _step = _CameraStep.camera;
  final _cropController = CropController();

  @override
  void dispose() {
    _cameraController?.destroy();
    super.dispose();
  }

  Future<Uint8List> _convertToPng(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return byteData!.buffer.asUint8List();
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || _isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final file = await _cameraController!.takePicture();
      if (file != null && file.bytes != null) {
        // Convert to PNG for reliable crop_your_image compatibility
        // camera_macos may output TIFF/JPEG that the image package can't parse
        final pngBytes = await _convertToPng(file.bytes!);
        setState(() {
          _capturedBytes = pngBytes;
          _isCapturing = false;
          _step = _CameraStep.crop;
        });
      } else {
        setState(() {
          _error = 'Foto konnte nicht aufgenommen werden';
          _isCapturing = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Fehler: $e';
        _isCapturing = false;
      });
    }
  }

  void _onCropped(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        setState(() {
          _croppedBytes = croppedImage;
          _isCropping = false;
          _step = _CameraStep.preview;
        });
      case CropFailure(:final cause):
        setState(() {
          _error = 'Zuschnitt fehlgeschlagen: $cause';
          _isCropping = false;
        });
    }
  }

  void _doCrop() {
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  void _skipCrop() {
    // Use original photo without cropping
    setState(() {
      _croppedBytes = _capturedBytes;
      _step = _CameraStep.preview;
    });
  }

  Future<void> _uploadFinal() async {
    final bytes = _croppedBytes ?? _capturedBytes;
    if (bytes == null) return;

    // All camera photos are converted to PNG for crop compatibility
    const ext = 'png';
    final tempDir = await getTemporaryDirectory();
    final photoPath = '${tempDir.path}/camera_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(photoPath).writeAsBytes(bytes);

    if (mounted) {
      Navigator.pop(context, photoPath);
    }
  }

  void _retake() {
    setState(() {
      _capturedBytes = null;
      _croppedBytes = null;
      _error = null;
      _step = _CameraStep.camera;
    });
  }

  void _backToCrop() {
    setState(() {
      _croppedBytes = null;
      _step = _CameraStep.crop;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _step == _CameraStep.crop ? Icons.crop : Icons.camera_alt,
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _step == _CameraStep.camera
                  ? 'Foto aufnehmen'
                  : _step == _CameraStep.crop
                      ? 'Foto zuschneiden'
                      : 'Vorschau',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context, null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 440,
        child: _buildStepContent(),
      ),
      actions: _buildStepActions(),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _CameraStep.camera:
        return _buildCameraView();
      case _CameraStep.crop:
        return _buildCropView();
      case _CameraStep.preview:
        return _buildPreview();
    }
  }

  List<Widget> _buildStepActions() {
    switch (_step) {
      case _CameraStep.camera:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton.icon(
            icon: _isCapturing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.camera, size: 16),
            label: const Text('Aufnehmen'),
            onPressed: _isCapturing ? null : _takePicture,
          ),
        ];
      case _CameraStep.crop:
        return [
          TextButton(
            onPressed: _retake,
            child: const Text('Wiederholen'),
          ),
          TextButton(
            onPressed: _skipCrop,
            child: const Text('Überspringen'),
          ),
          ElevatedButton.icon(
            icon: _isCropping
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.crop, size: 16),
            label: const Text('Zuschneiden'),
            onPressed: _isCropping ? null : _doCrop,
          ),
        ];
      case _CameraStep.preview:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Verwerfen'),
          ),
          TextButton(
            onPressed: _backToCrop,
            child: const Text('Erneut zuschneiden'),
          ),
          TextButton(
            onPressed: _retake,
            child: const Text('Wiederholen'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.upload, size: 16),
            label: const Text('Hochladen'),
            onPressed: _uploadFinal,
          ),
        ];
    }
  }

  Widget _buildCameraView() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CameraMacOSView(
        deviceId: null,
        fit: BoxFit.contain,
        cameraMode: CameraMacOSMode.photo,
        pictureFormat: PictureFormat.jpg,
        onCameraInizialized: (controller) {
          setState(() => _cameraController = controller);
        },
        onCameraDestroyed: () {
          _cameraController = null;
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildCropView() {
    if (_capturedBytes == null) return const SizedBox.shrink();

    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Crop(
              image: _capturedBytes!,
              controller: _cropController,
              onCropped: _onCropped,
              progressIndicator: const Center(
                child: CircularProgressIndicator(),
              ),
              cornerDotBuilder: (size, edgeAlignment) => DotControl(
                color: Colors.blue.shade700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Bereich zum Zuschneiden auswählen',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final bytes = _croppedBytes ?? _capturedBytes;
    if (bytes == null) return const SizedBox.shrink();

    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Möchten Sie dieses Foto hochladen?',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      ],
    );
  }
}
