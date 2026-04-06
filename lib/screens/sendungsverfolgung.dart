import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/clipboard_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

/// Self-contained Sendungsverfolgung (DHL Tracking) widget.
/// Extracted from deutschepost_screen.dart for cleaner architecture.
class SendungsverfolgungView extends StatefulWidget {
  final ApiService apiService;

  /// Called whenever the shipment count changes (for parent badge).
  final ValueChanged<int>? onCountChanged;

  /// Called whenever the API status changes (color + text for parent overview card).
  final void Function(Color statusColor, String statusText)? onApiStatusChanged;

  const SendungsverfolgungView({
    super.key,
    required this.apiService,
    this.onCountChanged,
    this.onApiStatusChanged,
  });

  @override
  State<SendungsverfolgungView> createState() => _SendungsverfolgungViewState();
}

class _SendungsverfolgungViewState extends State<SendungsverfolgungView> {
  List<Map<String, dynamic>> _shipments = [];
  bool _isLoading = true;

  // DHL API status
  String _apiStatus = 'yellow';
  String _apiStatusText = 'Prüfe...';
  bool _isCheckingApi = false;
  Timer? _apiCheckTimer;

  @override
  void initState() {
    super.initState();
    _loadShipments();
    _checkApiStatus();
    _apiCheckTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (mounted) _checkApiStatus();
    });
  }

  @override
  void dispose() {
    _apiCheckTimer?.cancel();
    super.dispose();
  }

  Color get _apiStatusColor {
    switch (_apiStatus) {
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.orange;
      case 'red':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _notifyApiStatus() {
    widget.onApiStatusChanged?.call(_apiStatusColor, _apiStatusText);
  }

  Future<void> _checkApiStatus() async {
    if (_isCheckingApi) return;
    if (!mounted) return;
    setState(() => _isCheckingApi = true);

    try {
      final result = await widget.apiService.trackDhlShipment('00340434161094042557');
      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          _apiStatus = 'green';
          _apiStatusText = 'API aktiv';
          _isCheckingApi = false;
        });
      } else {
        final msg = result['message'] as String? ?? '';
        if (msg.contains('Autorisierung') || msg.contains('401')) {
          setState(() {
            _apiStatus = 'yellow';
            _apiStatusText = 'Nicht autorisiert';
            _isCheckingApi = false;
          });
        } else {
          setState(() {
            _apiStatus = 'red';
            _apiStatusText = msg.isNotEmpty ? msg : 'API Fehler';
            _isCheckingApi = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _apiStatus = 'red';
          _apiStatusText = 'Verbindungsfehler';
          _isCheckingApi = false;
        });
      }
    }
    if (mounted) _notifyApiStatus();
  }

  Future<void> _loadShipments() async {
    setState(() => _isLoading = true);
    final result = await widget.apiService.getDhlShipments();
    if (mounted && result['success'] == true) {
      final shipments = List<Map<String, dynamic>>.from(result['data'] ?? []);
      setState(() {
        _shipments = shipments;
        _isLoading = false;
      });
      widget.onCountChanged?.call(shipments.length);
      _autoRefreshStale(shipments);
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _autoRefreshStale(List<Map<String, dynamic>> shipments) async {
    bool refreshed = false;
    for (final s in shipments) {
      if (!mounted) break;
      final lastChecked = s['last_checked'] as String?;
      if (_isStale(lastChecked)) {
        await widget.apiService.trackDhlShipment(s['tracking_number'] as String);
        refreshed = true;
      }
    }
    if (refreshed && mounted) {
      final result = await widget.apiService.getDhlShipments();
      if (mounted && result['success'] == true) {
        final updated = List<Map<String, dynamic>>.from(result['data'] ?? []);
        setState(() {
          _shipments = updated;
        });
        widget.onCountChanged?.call(updated.length);
      }
    }
  }

  bool _isStale(String? lastChecked) {
    if (lastChecked == null) return true;
    try {
      return DateTime.now().difference(DateTime.parse(lastChecked)).inMinutes >= 60;
    } catch (_) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildSendungsverfolgungCard();
  }

  // ============= SENDUNGSVERFOLGUNG CARD =============

  Widget _buildSendungsverfolgungCard() {
    final color = Colors.blue.shade700;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.track_changes, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sendungsverfolgung',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      // API Status indicator (clickable)
                      InkWell(
                        onTap: _isCheckingApi ? null : _checkApiStatus,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _apiStatusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isCheckingApi)
                                SizedBox(
                                  width: 10, height: 10,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: _apiStatusColor),
                                )
                              else
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _apiStatusColor,
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Text(
                                _apiStatusText,
                                style: TextStyle(fontSize: 10, color: _apiStatusColor, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_shipments.length}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.add_circle_outline, color: color),
                  onPressed: _showAddShipmentDialog,
                  tooltip: 'Sendung hinzufügen',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.settings, color: Colors.grey.shade600, size: 20),
                  onPressed: _showDhlSettingsDialog,
                  tooltip: 'DHL Portal Einstellungen',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
            const Divider(height: 24),
            // List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _shipments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.track_changes, size: 40, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text(
                                'Keine Sendungen',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _shipments.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final s = _shipments[index];
                            final status = s['last_status'] as String?;

                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(_statusIcon(status), color: _statusColor(status), size: 20),
                              title: Text(
                                s['beschreibung'] ?? s['tracking_number'] ?? '',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                s['tracking_number'] ?? '',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (s['last_status_text'] != null)
                                    Container(
                                      constraints: const BoxConstraints(maxWidth: 100),
                                      child: Text(
                                        _shortStatus(s['last_status_text']),
                                        style: TextStyle(fontSize: 10, color: _statusColor(status)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  IconButton(
                                    icon: Icon(Icons.refresh, size: 16, color: Colors.grey.shade400),
                                    onPressed: () => _trackShipment(s),
                                    tooltip: 'Status aktualisieren',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                  ),
                                ],
                              ),
                              onTap: () => _showShipmentDetails(s),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ============= HELPERS =============

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'delivered':
        return Icons.check_circle;
      case 'transit':
        return Icons.local_shipping;
      case 'failure':
        return Icons.error;
      default:
        return Icons.schedule;
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'delivered':
        return Colors.green;
      case 'transit':
        return Colors.blue;
      case 'failure':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _shortStatus(String? text) {
    if (text == null) return '';
    final parts = text.split(' - ');
    return parts.first;
  }

  // ============= DIALOGS =============

  Future<void> _showDhlSettingsDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoading = true;
    bool obscurePassword = true;

    // Load existing settings
    final settings = await widget.apiService.getDhlSettings();
    if (settings['success'] == true && settings['data'] != null) {
      emailController.text = settings['data']['email'] ?? '';
      passwordController.text = settings['data']['password'] ?? '';
    }
    isLoading = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.settings, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              const Text('DHL Portal Einstellungen', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Zugangsdaten für das DHL Developer Portal',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        decoration: InputDecoration(
                          labelText: 'E-Mail',
                          hintText: 'DHL Portal E-Mail',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'E-Mail kopieren',
                            onPressed: () {
                              if (emailController.text.trim().isNotEmpty) {
                                ClipboardHelper.copy(context, emailController.text.trim(), 'E-Mail');
                              }
                            },
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Passwort',
                          hintText: 'DHL Portal Passwort',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                tooltip: 'Passwort kopieren',
                                onPressed: () {
                                  if (passwordController.text.trim().isNotEmpty) {
                                    ClipboardHelper.copy(context, passwordController.text.trim(), 'Passwort');
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Open DHL Portal button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('DHL Developer Portal öffnen'),
                          onPressed: () {
                            launchUrl(Uri.parse('https://developer.dhl.com/user/login?destination=/node/102'));
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Speichern'),
              onPressed: () async {
                final email = emailController.text.trim();
                final password = passwordController.text.trim();
                if (email.isEmpty && password.isEmpty) {
                  Navigator.pop(ctx);
                  return;
                }
                final res = await widget.apiService.saveDhlSettings(
                  email: email,
                  password: password,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(res['success'] == true ? 'Einstellungen gespeichert' : 'Fehler beim Speichern'),
                      backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );

    emailController.dispose();
    passwordController.dispose();
  }

  Future<void> _showAddShipmentDialog() async {
    final numberController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.track_changes, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            const Text('Sendung hinzufügen'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numberController,
                decoration: const InputDecoration(
                  labelText: 'Sendungsnummer *',
                  hintText: 'z.B. 00340434161094042557',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung',
                  hintText: 'z.B. Brief an Notar',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (numberController.text.trim().isEmpty) return;
              final res = await widget.apiService.addDhlShipment(
                numberController.text.trim(),
                beschreibung: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
              );
              if (ctx.mounted) {
                Navigator.pop(ctx, res['success'] == true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
            child: const Text('Speichern', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      _loadShipments();
    }
  }

  Future<void> _trackShipment(Map<String, dynamic> shipment) async {
    final number = shipment['tracking_number'] as String;
    final result = await widget.apiService.trackDhlShipment(number);
    if (mounted) {
      if (result['success'] == true) {
        _loadShipments();
        final tracking = result['tracking'] as List?;
        if (tracking != null && tracking.isNotEmpty) {
          _showTrackingResult(tracking[0], shipment);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sendung nicht gefunden oder DHL API noch nicht freigeschaltet'), backgroundColor: Colors.orange),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Fehler beim Tracking'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showTrackingResult(Map<String, dynamic> tracking, Map<String, dynamic> shipment) {
    var events = List<Map<String, dynamic>>.from(tracking['events'] ?? []);

    // If no events but we have a status, create a pseudo-event from current status
    if (events.isEmpty && tracking['status'] != null) {
      events = [
        {
          'timestamp': tracking['timestamp'] ?? '',
          'statusCode': tracking['status'] ?? '',
          'status': tracking['statusText'] ?? '',
          'description': tracking['description'] ?? tracking['statusText'] ?? '',
          'location': tracking['location'] ?? '',
        },
      ];
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_statusIcon(tracking['status']), color: _statusColor(tracking['status'])),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                shipment['beschreibung'] ?? tracking['trackingNumber'] ?? '',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current status banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusColor(tracking['status']).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(_statusIcon(tracking['status']), color: _statusColor(tracking['status'])),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tracking['statusText'] ?? 'Unbekannt',
                            style: TextStyle(fontWeight: FontWeight.bold, color: _statusColor(tracking['status'])),
                          ),
                          if (tracking['description'] != null && tracking['description'].toString().isNotEmpty)
                            Text(tracking['description'], style: const TextStyle(fontSize: 12)),
                          if (tracking['location'] != null && tracking['location'].toString().isNotEmpty)
                            Text(tracking['location'], style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Sendungsnummer: ${tracking['trackingNumber']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (tracking['productName'] != null && tracking['productName'].toString().isNotEmpty)
                Text('Produkt: ${tracking['productName']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              const Text('Sendungsverlauf:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              // Events timeline
              Expanded(
                child: events.isEmpty
                    ? const Center(child: Text('Keine Ereignisse'))
                    : ListView.builder(
                        itemCount: events.length,
                        itemBuilder: (_, i) {
                          final e = events[i];
                          final ts = e['timestamp'] as String? ?? '';
                          final dateStr = ts.length >= 10 ? ts.substring(0, 10) : ts;
                          final timeStr = ts.length >= 16 ? ts.substring(11, 16) : '';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 70,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(dateStr, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                                      Text(timeStr, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  children: [
                                    Container(
                                      width: 10, height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: i == 0 ? _statusColor(e['statusCode']) : Colors.grey.shade300,
                                      ),
                                    ),
                                    if (i < events.length - 1)
                                      Container(width: 2, height: 30, color: Colors.grey.shade300),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(e['description'] ?? e['status'] ?? '', style: const TextStyle(fontSize: 12)),
                                      if (e['location'] != null && e['location'].toString().isNotEmpty)
                                        Text(e['location'], style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  void _showShipmentDetails(Map<String, dynamic> shipment) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.local_shipping, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                shipment['beschreibung'] ?? shipment['tracking_number'] ?? '',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Sendungsnummer', shipment['tracking_number'] ?? '-'),
              _detailRow('Beschreibung', shipment['beschreibung'] ?? '-'),
              _detailRow('Status', shipment['last_status_text'] ?? 'Noch nicht abgefragt'),
              _detailRow('Letzte Prüfung', shipment['last_checked'] ?? '-'),
              _detailRow('Erstellt', shipment['created_at'] ?? '-'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'track'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
            child: const Text('Status abfragen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'track') {
      _trackShipment(shipment);
    } else if (action == 'delete') {
      final id = shipment['id'] as int;
      final result = await widget.apiService.deleteDhlShipment(id);
      if (mounted && result['success'] == true) {
        _loadShipments();
      }
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
