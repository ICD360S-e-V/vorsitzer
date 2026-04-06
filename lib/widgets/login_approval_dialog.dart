import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

/// Shows a popup overlay when a member requests passwordless login.
/// Auto-polls every 5 seconds and updates on WebSocket events.
class LoginApprovalOverlay {
  static final LoginApprovalOverlay _instance = LoginApprovalOverlay._internal();
  factory LoginApprovalOverlay() => _instance;
  LoginApprovalOverlay._internal();

  OverlayEntry? _overlayEntry;
  final _pendingRequests = ValueNotifier<List<Map<String, dynamic>>>([]);
  Timer? _pollTimer;
  final _apiService = ApiService();
  bool _isPolling = false;

  int get pendingCount => _pendingRequests.value.length;
  ValueNotifier<List<Map<String, dynamic>>> get requests => _pendingRequests;

  /// Start polling for pending approvals
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchPending());
    _fetchPending();
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Called when WebSocket receives login_approval_request
  void onNewRequest(Map<String, dynamic> data) {
    // Show notification
    NotificationService().show(
      title: 'Login-Anfrage',
      body: '${data['member_name'] ?? data['mitgliedernummer']} möchte sich anmelden (${data['device_name'] ?? 'Unbekannt'})',
    );
    // Refresh immediately
    _fetchPending();
    // Show overlay if not visible
    if (_overlayEntry == null) {
      _showOverlayIfPending();
    }
  }

  Future<void> _fetchPending() async {
    if (_isPolling) return;
    _isPolling = true;
    try {
      final result = await _apiService.getPendingApprovals();
      if (result['success'] == true) {
        _pendingRequests.value = List<Map<String, dynamic>>.from(result['data'] ?? []);
      }
    } catch (_) {}
    _isPolling = false;
  }

  void _showOverlayIfPending() {
    // Overlay is triggered from dashboard when WebSocket event arrives
  }

  /// Show the approval dialog as a standard dialog
  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (_) => const _LoginApprovalDialogWidget(),
    );
  }
}

class _LoginApprovalDialogWidget extends StatefulWidget {
  const _LoginApprovalDialogWidget();

  @override
  State<_LoginApprovalDialogWidget> createState() => _LoginApprovalDialogWidgetState();
}

class _LoginApprovalDialogWidgetState extends State<_LoginApprovalDialogWidget> {
  final _overlay = LoginApprovalOverlay();
  Timer? _refreshTimer;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _overlay._fetchPending();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _overlay._fetchPending();
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // refresh countdown display
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleDecision(String requestToken, String decision) async {
    final result = await ApiService().approveLogin(requestToken, decision);
    if (mounted) {
      final success = result['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? (decision == 'approved' ? 'Login genehmigt' : 'Login abgelehnt')
            : (result['message'] ?? 'Fehler')),
        backgroundColor: success ? Colors.green : Colors.red,
      ));
      _overlay._fetchPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 500, height: 500,
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              const Icon(Icons.key, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              const Expanded(child: Text('Login-Anfragen', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          // Content
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: _overlay._pendingRequests,
              builder: (context, requests, _) {
                if (requests.isEmpty) {
                  return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade300),
                    const SizedBox(height: 12),
                    Text('Keine offenen Anfragen', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                  ]));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: requests.length,
                  itemBuilder: (_, i) => _buildRequestCard(requests[i]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final memberName = req['member_name'] ?? 'Unbekannt';
    final mitgliedernummer = req['mitgliedernummer'] ?? '';
    final deviceInfo = req['device_info'] is Map ? req['device_info'] as Map<String, dynamic> : <String, dynamic>{};
    final deviceName = deviceInfo['device_name'] ?? 'Unbekannt';
    final platform = deviceInfo['platform'] ?? '';
    final ip = req['ip_address'] ?? '?';
    final createdAt = DateTime.tryParse(req['created_at'] ?? '');
    final elapsed = createdAt != null ? DateTime.now().difference(createdAt) : Duration.zero;
    final remaining = Duration(seconds: 300) - elapsed;
    final isExpired = remaining.isNegative;
    final remainingStr = isExpired ? 'Abgelaufen' : '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isExpired ? Colors.grey.shade300 : Colors.amber.shade300, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Name + Timer
          Row(children: [
            Icon(Icons.person, color: Colors.blue.shade700, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('$memberName ($mitgliedernummer)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isExpired ? Colors.red.shade50 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isExpired ? Colors.red.shade200 : Colors.amber.shade200),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer, size: 14, color: isExpired ? Colors.red.shade700 : Colors.amber.shade700),
                const SizedBox(width: 4),
                Text(remainingStr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isExpired ? Colors.red.shade700 : Colors.amber.shade700)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          // Device info
          _infoRow(Icons.phone_android, 'Gerät', deviceName),
          _infoRow(Icons.computer, 'Plattform', platform),
          _infoRow(Icons.public, 'IP-Adresse', ip),
          if (createdAt != null)
            _infoRow(Icons.access_time, 'Zeitpunkt', '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}:${createdAt.second.toString().padLeft(2, '0')}'),
          const SizedBox(height: 12),
          // Buttons
          if (!isExpired)
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Genehmigen'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10)),
                onPressed: () => _handleDecision(req['request_token'], 'approved'),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Ablehnen'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10)),
                onPressed: () => _handleDecision(req['request_token'], 'denied'),
              )),
            ])
          else
            Center(child: Text('Anfrage abgelaufen', style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey.shade500), const SizedBox(width: 6),
      SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
    ]));
  }
}
