import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../services/weather_service.dart' show WeatherAlert;

final _log = LoggerService();

/// Vorsitzer-Tool: targeted Wetter-Broadcast an Members.
///
/// Pro Members-Adresse (PLZ + Ort) wird die DWD-Warn-Liste von Bright Sky
/// abgefragt. Members ohne aktive Warnung tauchen gar nicht auf. Der
/// Vorsitzer kann die vorformulierte Nachricht anpassen und pro Person
/// entscheiden, wer sie kriegt — anschließend geht die Meldung als
/// dringlicher Chat-Full-Screen-Alert raus.
///
/// Kein Cloud-/SMS-Gateway nötig; nutzt den bestehenden Chat-Kanal.
class SturmwarnungBroadcastDialog extends StatefulWidget {
  final ApiService apiService;
  final List<User> users;
  final String adminMitgliedernummer;

  const SturmwarnungBroadcastDialog({
    super.key,
    required this.apiService,
    required this.users,
    required this.adminMitgliedernummer,
  });

  @override
  State<SturmwarnungBroadcastDialog> createState() =>
      _SturmwarnungBroadcastDialogState();
}

class _SturmwarnungBroadcastDialogState
    extends State<SturmwarnungBroadcastDialog> {
  bool _loading = true;
  String? _error;
  final Map<int, bool> _selected = {};    // user.id → include in broadcast
  final Map<int, WeatherAlert> _byUserId = {};
  final Map<String, List<WeatherAlert>> _alertsByLocation = {};
  final _messageController = TextEditingController();
  bool _sending = false;
  int _sentCount = 0;
  int _failedCount = 0;

  static const _spKeyGeoPrefix = 'sturm_broadcast_geo_v1_';

  @override
  void initState() {
    super.initState();
    _messageController.text =
        '⚠️ Wetter-Warnung an unserer Adresse\n\n'
        '$AUTO_HEADLINE_PLACEHOLDER\n\n'
        'Bitte auf Wettermeldungen achten, bei Bedarf Termine verschieben. '
        'Sag Bescheid, wenn du Hilfe brauchst.\n\n'
        '— ICD360S e.V.';
    _load();
  }

  // Marker that gets replaced with the actual DWD headline per recipient.
  static const AUTO_HEADLINE_PLACEHOLDER = '{{WARNUNG_HEADLINE}}';

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Distinct location keys — PLZ + Ort. We iterate them (not every user)
      // so 30 Members in Ulm cost exactly one Bright-Sky call.
      final byLoc = <String, List<User>>{};
      for (final u in widget.users) {
        if (u.status != 'aktiv' && u.status != 'active') continue;
        final loc = _locationKey(u);
        if (loc == null) continue;
        byLoc.putIfAbsent(loc, () => []).add(u);
      }
      for (final entry in byLoc.entries) {
        final coords = await _geocode(entry.key);
        if (coords == null) continue;
        final alerts = await _fetchAlerts(coords.$1, coords.$2);
        if (alerts.isEmpty) continue;
        _alertsByLocation[entry.key] = alerts;
        // Use the most severe alert as the per-user "reason".
        final worst = _worst(alerts);
        for (final u in entry.value) {
          _byUserId[u.id] = worst;
          _selected[u.id] = true; // default: all included, Vorsitzer opt-out
        }
      }
    } catch (e) {
      _error = 'Konnte Warnungen nicht laden: $e';
      _log.error('Sturm broadcast load failed: $e', tag: 'STURM');
    }
    if (mounted) setState(() { _loading = false; });
  }

  /// PLZ + Ort combined key. Falls back to Ort alone when PLZ is missing.
  String? _locationKey(User u) {
    final ort = (u.ort ?? '').trim();
    if (ort.isEmpty) return null;
    final plz = (u.plz ?? '').trim();
    return plz.isEmpty ? ort : '$plz $ort';
  }

  Future<(double, double)?> _geocode(String key) async {
    final sp = await SharedPreferences.getInstance();
    final cached = sp.getString('$_spKeyGeoPrefix$key');
    if (cached != null) {
      final parts = cached.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0]);
        final lon = double.tryParse(parts[1]);
        if (lat != null && lon != null) return (lat, lon);
      }
    }
    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeComponent(key)}&count=1&language=de&format=json',
      );
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body);
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final lat = (results[0]['latitude'] as num).toDouble();
      final lon = (results[0]['longitude'] as num).toDouble();
      await sp.setString('$_spKeyGeoPrefix$key', '$lat,$lon');
      return (lat, lon);
    } catch (_) {
      return null;
    }
  }

  Future<List<WeatherAlert>> _fetchAlerts(double lat, double lon) async {
    try {
      final r = await http
          .get(Uri.parse('https://api.brightsky.dev/alerts?lat=$lat&lon=$lon'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return const [];
      final data = jsonDecode(r.body);
      final list = (data['alerts'] as List?) ?? const [];
      return list.map<WeatherAlert>((a) {
        return WeatherAlert(
          headline: (a['headline_de'] ?? a['headline'] ?? '') as String,
          description: (a['description_de'] ?? a['description'] ?? '') as String,
          severity: (a['severity'] as String?) ?? 'minor',
          event: (a['event_de'] ?? a['event'] ?? '') as String,
          instruction: a['instruction_de'] as String?,
          onset: a['onset'] != null ? DateTime.tryParse(a['onset']) : null,
          expires: a['expires'] != null ? DateTime.tryParse(a['expires']) : null,
        );
      }).where((a) => a.isRelevant).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Order: extreme > severe > moderate > minor.
  WeatherAlert _worst(List<WeatherAlert> alerts) {
    const rank = {'extreme': 4, 'severe': 3, 'moderate': 2, 'minor': 1};
    alerts.sort((a, b) => (rank[b.severity] ?? 0) - (rank[a.severity] ?? 0));
    return alerts.first;
  }

  Color _severityColor(String sev) {
    switch (sev) {
      case 'extreme':  return Colors.red.shade800;
      case 'severe':   return Colors.orange.shade700;
      case 'moderate': return Colors.amber.shade700;
      default:         return Colors.yellow.shade700;
    }
  }

  Future<void> _broadcast() async {
    final template = _messageController.text.trim();
    if (template.isEmpty) return;
    final targets = _byUserId.entries
        .where((e) => _selected[e.key] ?? false)
        .toList();
    if (targets.isEmpty) return;
    setState(() { _sending = true; _sentCount = 0; _failedCount = 0; });
    for (final entry in targets) {
      final userId = entry.key;
      final alert = entry.value;
      final user = widget.users.firstWhere((u) => u.id == userId);
      // Personalise the message with the DWD headline for this exact recipient.
      final text = template.replaceAll(AUTO_HEADLINE_PLACEHOLDER, alert.headline);
      try {
        final start = await widget.apiService.adminStartChat(
          widget.adminMitgliedernummer,
          user.mitgliedernummer,
        );
        if (start['success'] != true) {
          _failedCount++;
          _log.error('Sturm broadcast: adminStart failed for '
              '${user.mitgliedernummer}: ${start['message']}', tag: 'STURM');
          continue;
        }
        final convId = start['conversation_id'] as int?;
        if (convId == null) { _failedCount++; continue; }
        final sendR = await widget.apiService.sendChatMessage(
          convId,
          widget.adminMitgliedernummer,
          text,
          urgent: true,
          skipTranslation: false,
        );
        if (sendR['success'] == true) {
          _sentCount++;
        } else {
          _failedCount++;
        }
      } catch (e) {
        _failedCount++;
        _log.error('Sturm broadcast: send failed for '
            '${user.mitgliedernummer}: $e', tag: 'STURM');
      }
      if (mounted) setState(() {});
    }
    setState(() { _sending = false; });
  }

  @override
  Widget build(BuildContext context) {
    final locsWithAlerts = _alertsByLocation.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Warnungen für alle Mitglied-Adressen prüfen …'),
                  ],
                ),
              )
            else if (_error != null)
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
            else if (_byUserId.isEmpty)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 42, color: Colors.green),
                    SizedBox(height: 10),
                    Text(
                      'Keine aktiven DWD-Warnungen an den Adressen '
                      'unserer Mitglieder.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summaryBar(),
                      const SizedBox(height: 10),
                      for (final loc in locsWithAlerts)
                        _buildLocationBlock(loc.key, loc.value),
                      const SizedBox(height: 12),
                      Text('Nachricht',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text(
                        '$AUTO_HEADLINE_PLACEHOLDER wird pro Empfänger durch '
                        'die konkrete DWD-Warnung ersetzt.',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _messageController,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.white, size: 26),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Wetter-Warnung an Mitglieder',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text('DWD-Warnungen gezielt pro Adresse',
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
    );
  }

  Widget _summaryBar() {
    final selected = _selected.values.where((v) => v).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.groups, size: 18, color: Colors.orange.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_byUserId.length} Mitglied${_byUserId.length == 1 ? "" : "er"} '
              'an ${_alertsByLocation.length} Orten mit aktiver Warnung',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade900),
            ),
          ),
          Text('$selected ausgewählt',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildLocationBlock(String location, List<WeatherAlert> alerts) {
    final worst = _worst(alerts);
    final affectedUsers =
        _byUserId.entries.where((e) => _locationKey(widget.users.firstWhere((u) => u.id == e.key)) == location).toList();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.place, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 4),
            Text(location,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _severityColor(worst.severity),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                worst.severityLabel,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(worst.event,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text(worst.headline,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
          const Divider(height: 12),
          for (final entry in affectedUsers)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected[entry.key] ?? false,
              onChanged: (v) => setState(() => _selected[entry.key] = v ?? false),
              title: Builder(builder: (_) {
                final user = widget.users.firstWhere((u) => u.id == entry.key);
                return Text(
                  '${user.mitgliedernummer} · ${user.name}',
                  style: const TextStyle(fontSize: 12),
                );
              }),
              subtitle: Builder(builder: (_) {
                final user = widget.users.firstWhere((u) => u.id == entry.key);
                final phone = user.telefonMobil ?? user.telefonFix ?? '';
                return Text(
                  phone.isEmpty ? 'Kein Telefon hinterlegt' : phone,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final selected = _selected.values.where((v) => v).length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          if (_sending) ...[
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Sende … $_sentCount OK · $_failedCount fehlgeschlagen',
                style: const TextStyle(fontSize: 12)),
          ] else if (_sentCount > 0 || _failedCount > 0) ...[
            Icon(
                _failedCount == 0
                    ? Icons.check_circle
                    : Icons.error_outline,
                size: 18,
                color: _failedCount == 0 ? Colors.green : Colors.orange),
            const SizedBox(width: 6),
            Text('$_sentCount gesendet · $_failedCount fehlgeschlagen',
                style: const TextStyle(fontSize: 12)),
          ],
          const Spacer(),
          TextButton(
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: _sending || selected == 0 ? null : _broadcast,
            label: Text('Als dringend an $selected senden'),
          ),
        ],
      ),
    );
  }
}
