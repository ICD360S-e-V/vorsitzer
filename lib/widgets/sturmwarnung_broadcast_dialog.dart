import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/weather_auto_broadcast_service.dart';

/// Global registration slot: the dashboard populates this once at startup
/// so any widget can call `openSturmwarnungBroadcast(context)` without
/// threading callbacks through the whole widget tree.
class SturmwarnungBroadcastContext {
  ApiService? apiService;
  List<User> users = const [];
  String adminMitgliedernummer = '';
  static final SturmwarnungBroadcastContext instance =
      SturmwarnungBroadcastContext._();
  SturmwarnungBroadcastContext._();
}

/// Open the log/status viewer. The actual sending is fully automated by
/// [WeatherAutoBroadcastService] — the dialog is read-only history plus
/// a "jetzt prüfen"-Button so the Vorsitzer can trigger a sweep on demand.
Future<void> openSturmwarnungBroadcast(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const SturmwarnungBroadcastDialog(),
  );
}

/// Read-only view of the auto-broadcast log — what went out to which member,
/// which severity, when. Plus a "jetzt prüfen"-Button.
class SturmwarnungBroadcastDialog extends StatefulWidget {
  const SturmwarnungBroadcastDialog({super.key});

  @override
  State<SturmwarnungBroadcastDialog> createState() =>
      _SturmwarnungBroadcastDialogState();
}

class _SturmwarnungBroadcastDialogState
    extends State<SturmwarnungBroadcastDialog> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await WeatherAutoBroadcastService.instance.refreshNow();
    if (mounted) setState(() => _refreshing = false);
  }

  Color _sevColor(String sev) {
    switch (sev) {
      case 'extreme':  return Colors.red.shade800;
      case 'severe':   return Colors.orange.shade700;
      case 'moderate': return Colors.amber.shade700;
      default:         return Colors.yellow.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = WeatherAutoBroadcastService.instance.log;
    final df = DateFormat('dd.MM. HH:mm', 'de_DE');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Automatische Wetter-Warnungen',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        Text(
                            'DWD-Meldungen werden automatisch als '
                            'dringende Chat-Nachricht an betroffene '
                            'Mitglieder gesendet',
                            style: TextStyle(color: Colors.white70, fontSize: 11)),
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    icon: _refreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(_refreshing ? 'Prüfe …' : 'Jetzt prüfen'),
                    onPressed: _refreshing ? null : _refresh,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${log.length} Einträge im Log · Sweep alle 30 Min',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: log.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(30),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text(
                              'Noch keine automatischen Wetter-Warnungen '
                              'verschickt.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: log.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = log[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            e.sent
                                ? Icons.check_circle
                                : Icons.error_outline,
                            color: e.sent ? Colors.green : Colors.red,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                  child: Text(
                                      '${e.userMitgliedernummer} · ${e.userName}',
                                      style:
                                          const TextStyle(fontSize: 13))),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _sevColor(e.alertSeverity),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  e.alertSeverity.toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 8,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(e.alertEvent,
                                  style: const TextStyle(fontSize: 11)),
                              if (e.failureReason != null)
                                Text('Fehler: ${e.failureReason}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.red.shade700)),
                            ],
                          ),
                          trailing: Text(
                            df.format(e.at),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
