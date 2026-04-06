import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _serverInfo;
  Map<String, dynamic>? _prevServerInfo;
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadServerInfo();
    // Auto-refresh every 5 seconds for real-time CPU/RAM/Disk
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadServerInfo(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadServerInfo({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final response = await _apiService.getServerInfo();
      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _prevServerInfo = _serverInfo;
            _serverInfo = response;
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = response['message'] ?? 'Unbekannter Fehler';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatBytes(dynamic bytes) {
    final b = (bytes is int) ? bytes : int.tryParse(bytes.toString()) ?? 0;
    if (b <= 0) return '-';
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (b >= 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
    } else if (b >= 1024) {
      return '${(b / 1024).toStringAsFixed(0)} KB';
    }
    return '$b B';
  }

  String _formatKB(dynamic kb) {
    final k = (kb is int) ? kb : int.tryParse(kb.toString()) ?? 0;
    if (k <= 0) return '-';
    if (k >= 1024 * 1024) {
      return '${(k / (1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (k >= 1024) {
      return '${(k / 1024).toStringAsFixed(0)} MB';
    }
    return '$k KB';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dns, size: 28, color: Colors.blueGrey),
              const SizedBox(width: 12),
              const Text('Server', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              if (_serverInfo != null && !_isLoading)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'Live',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade600, fontWeight: FontWeight.bold),
                  ),
                ),
              const Spacer(),
              if (_serverInfo != null)
                Text(
                  _serverInfo!['server_time'] ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadServerInfo,
                tooltip: 'Aktualisieren',
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('Fehler: $_error', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _loadServerInfo, child: const Text('Erneut versuchen')),
                ],
              ),
            )
          else if (_serverInfo != null)
            Expanded(child: SingleChildScrollView(child: _buildServerCards())),
        ],
      ),
    );
  }

  Widget _buildServerCards() {
    final info = _serverInfo!;
    final osUpdates = info['os_updates_available'] ?? 0;
    final phpUpToDate = info['php_up_to_date'] == true;
    final dbUpToDate = info['db_up_to_date'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ============================================================
        // SYSTEM
        // ============================================================
        _buildCard('System', Icons.computer, Colors.blue, [
          _buildInfoRowWithStatus(
            'Betriebssystem',
            info['os_name'] ?? '-',
            osUpdates == 0,
            osUpdates > 0 ? '$osUpdates Updates verfügbar' : 'Aktuell',
          ),
          _buildInfoRow('Kernel', info['kernel'] ?? '-'),
          _buildInfoRow('Hostname', info['hostname'] ?? '-'),
          _buildInfoRow('Architektur', '${info['architecture'] ?? '-'} (${info['cpu_model'] ?? '-'})'),
          _buildInfoRow('Uptime', info['uptime'] ?? '-'),
        ]),
        const SizedBox(height: 16),

        // ============================================================
        // CPU & RAM (Real-time)
        // ============================================================
        _buildCard('CPU (Live)', Icons.developer_board, Colors.green, [
          _buildInfoRow('Modell', '${info['cpu_model'] ?? '-'}'),
          _buildInfoRow('Load Average', '${info['load_avg_1']}, ${info['load_avg_5']}, ${info['load_avg_15']}'),
          const SizedBox(height: 8),
          if (info['cpu_cores_usage'] != null)
            ...(info['cpu_cores_usage'] as List).map<Widget>((core) {
              final usage = (core['usage'] as num).toDouble();
              final color = usage > 90 ? Colors.red : (usage > 70 ? Colors.orange : Colors.green);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 65, child: Text('Kern ${core['core']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: usage / 100, backgroundColor: Colors.grey.shade200, color: color, minHeight: 14),
                      ),
                    ),
                    SizedBox(width: 55, child: Text('${usage.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
                  ],
                ),
              );
            }),
          if (info['top_cpu_processes'] != null) ...[
            const Divider(height: 20),
            const Text('Top 10 Prozesse (CPU)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...(info['top_cpu_processes'] as List).map<Widget>((proc) {
              final cpu = (proc['cpu'] as num).toDouble();
              final cmd = (proc['command'] ?? '').toString();
              final shortCmd = cmd.length > 40 ? cmd.substring(0, 40) : cmd;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 55, child: Text('$cpu%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cpu > 50 ? Colors.red : Colors.green.shade700))),
                    SizedBox(width: 65, child: Text(proc['user'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                    Expanded(child: Text(shortCmd, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              );
            }),
          ],
        ]),
        const SizedBox(height: 16),

        // RAM
        _buildCard('RAM (Live)', Icons.memory, Colors.deepPurple, [
          _buildInfoRow('Gesamt', _formatBytes(info['ram_total_bytes'])),
          const SizedBox(height: 8),
          _buildSegmentedBar(info),
          const SizedBox(height: 12),
          _buildLegendRow(Colors.red.shade400, 'Verwendet', _formatBytes(info['ram_used_bytes']), _ramUsedPercent(info)),
          _buildLegendRow(Colors.blue.shade300, 'Cache/Buffer', _formatBytes(info['ram_cache_bytes']), _ramCachePercent(info)),
          _buildLegendRow(Colors.green.shade300, 'Frei', _formatBytes(info['ram_free_bytes']), _ramFreePercent(info)),
          const Divider(height: 16),
          _buildInfoRow('Verfügbar (frei + cache)', _formatBytes(info['ram_available_bytes'])),
          if (info['top_mem_processes'] != null) ...[
            const Divider(height: 20),
            const Text('Top 10 Prozesse (RAM)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...(info['top_mem_processes'] as List).map<Widget>((proc) {
              final mem = (proc['mem'] as num).toDouble();
              final rssKb = (proc['rss_kb'] as num).toInt();
              final cmd = (proc['command'] ?? '').toString();
              final shortCmd = cmd.length > 35 ? cmd.substring(0, 35) : cmd;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 45, child: Text('$mem%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: mem > 20 ? Colors.red : Colors.deepPurple))),
                    SizedBox(width: 60, child: Text(_formatKB(rssKb), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                    SizedBox(width: 60, child: Text(proc['user'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                    Expanded(child: Text(shortCmd, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              );
            }),
          ],
        ]),
        const SizedBox(height: 16),

        // DISK
        _buildCard('Speicher (Live)', Icons.disc_full, Colors.brown, [
          _buildProgressRow(
            'Gesamt',
            (info['disk_percent'] ?? 0).toDouble(),
            '${_formatKB(info['disk_used_kb'])} / ${_formatKB(info['disk_total_kb'])}  (${info['disk_percent'] ?? 0}%)',
          ),
          _buildInfoRow('Frei', _formatKB(info['disk_free_kb'])),
          if (info['disk_io'] != null) ...[
            const Divider(height: 20),
            const Text('I/O (Live)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            _buildInfoRow('Lesen', '${info['disk_io']['read_kbs'] ?? 0} KB/s'),
            _buildInfoRow('Schreiben', '${info['disk_io']['write_kbs'] ?? 0} KB/s'),
            _buildProgressRow('Auslastung', (info['disk_io']['util'] ?? 0).toDouble(), '${info['disk_io']['util'] ?? 0}%'),
          ],
          const Divider(height: 20),
          const Text('Belegung nach Verzeichnis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          if (info['disk_breakdown'] != null)
            ...(info['disk_breakdown'] as List).map<Widget>((dir) {
              final sizeBytes = (dir['size_bytes'] as num).toInt();
              final totalKB = (info['disk_total_kb'] ?? 1) as num;
              final percent = (sizeBytes / (totalKB * 1024) * 100).clamp(0, 100).toDouble();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dir['path'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(dir['description'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(value: percent / 100, backgroundColor: Colors.grey.shade200, color: Colors.brown.shade300, minHeight: 10),
                      ),
                    ),
                    SizedBox(width: 80, child: Text(_formatBytes(sizeBytes), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ],
                ),
              );
            }),
        ]),
        const SizedBox(height: 16),

        // ============================================================
        // PHP
        // ============================================================
        _buildCard('PHP', Icons.code, Colors.indigo, [
          _buildInfoRowWithStatus(
            'Version',
            info['php_version'] ?? '-',
            phpUpToDate,
            phpUpToDate ? 'Aktuell' : 'Update verfügbar: ${info['php_latest_available']}',
          ),
          _buildInfoRow('SAPI', info['php_sapi'] ?? '-'),
          _buildInfoRow('Zend Engine', info['zend_version'] ?? '-'),
          const Divider(height: 20),
          const Text('Erweiterungen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          if (info['php_extensions'] != null)
            ...(info['php_extensions'] as List).map<Widget>((ext) {
              final loaded = ext['loaded'] == true;
              final required = ext['required'] == true;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      loaded ? Icons.check_circle : (required ? Icons.error : Icons.info_outline),
                      size: 16,
                      color: loaded ? Colors.green : (required ? Colors.red : Colors.orange),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: Text(ext['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    ),
                    Expanded(
                      child: Text(
                        ext['reason'] ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                    Text(
                      loaded ? 'Aktiv' : (required ? 'Fehlt!' : 'Optional'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: loaded ? Colors.green : (required ? Colors.red : Colors.orange),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ]),
        const SizedBox(height: 16),

        // ============================================================
        // DATABASE
        // ============================================================
        _buildCard('Datenbank (Live)', Icons.storage, Colors.orange, [
          _buildInfoRowWithStatus(
            'Version',
            info['db_version'] ?? '-',
            dbUpToDate,
            dbUpToDate ? 'Aktuell' : 'Update verfügbar: ${info['db_available_pkg']}',
          ),
          _buildInfoRow('Zeichensatz', info['db_charset'] ?? '-'),
          _buildInfoRow('Collation', info['db_collation'] ?? '-'),
          _buildInfoRow('Uptime', info['db_uptime'] ?? '-'),
          _buildInfoRow('Tabellen', '${info['db_tables'] ?? '-'}'),
          _buildInfoRow('Datenbankgröße', '${info['db_size_mb'] ?? '-'} MB'),
          const Divider(height: 20),
          const Text('Verbindungen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _buildProgressRow(
            'Verbindungen',
            _dbConnectionPercent(info),
            '${info['db_threads_connected'] ?? 0} aktiv / ${info['db_max_connections'] ?? 151} max  (Peak: ${info['db_max_used_connections'] ?? 0})',
          ),
          _buildInfoRow('Threads laufend', '${info['db_threads_running'] ?? 0}'),
          _buildInfoRow('Abgebrochene Verbindungen', '${info['db_aborted_connects'] ?? 0}'),
          const Divider(height: 20),
          const Text('Abfragen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _buildInfoRow('Abfragen gesamt', _withDelta('db_total_queries', _formatNumber(info['db_total_queries']))),
          _buildInfoRow('Abfragen/Sekunde', '${info['db_queries_per_sec'] ?? 0}'),
          _buildInfoRow('Langsame Abfragen', '${info['db_slow_queries'] ?? 0}'),
          _buildInfoRow('SELECT', _withDelta('db_com_select', _formatNumber(info['db_com_select']))),
          _buildInfoRow('INSERT', _withDelta('db_com_insert', _formatNumber(info['db_com_insert']))),
          _buildInfoRow('UPDATE', _withDelta('db_com_update', _formatNumber(info['db_com_update']))),
          _buildInfoRow('DELETE', _withDelta('db_com_delete', _formatNumber(info['db_com_delete']))),
          const Divider(height: 20),
          const Text('Datenverkehr', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _buildInfoRow('Empfangen', _withDelta('db_bytes_received', _formatBytes(info['db_bytes_received']))),
          _buildInfoRow('Gesendet', _withDelta('db_bytes_sent', _formatBytes(info['db_bytes_sent']))),
          const Divider(height: 20),
          const Text('InnoDB Buffer Pool', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _buildInfoRow('Größe', _formatBytes(info['db_bp_size_bytes'])),
          _buildProgressRow(
            'Auslastung',
            (info['db_bp_usage_percent'] ?? 0).toDouble(),
            '${info['db_bp_pages_data'] ?? 0} / ${info['db_bp_pages_total'] ?? 0} Seiten  (${info['db_bp_usage_percent'] ?? 0}%)',
          ),
          _buildInfoRow('Hit Rate', '${info['db_bp_hit_rate'] ?? 0}%'),
          _buildInfoRow('Freie Seiten', '${info['db_bp_pages_free'] ?? 0}'),
          const Divider(height: 20),
          const Text('Top 5 Tabellen (nach Größe)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          if (info['db_top_tables'] != null)
            ...(info['db_top_tables'] as List).map<Widget>((table) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.table_chart, size: 14, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(table['table_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    ),
                    Text('${table['table_rows'] ?? 0} Zeilen', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(width: 16),
                    Text('${table['size_mb'] ?? 0} MB', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 16),
                    Text(table['engine'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              );
            }),
        ]),
        const SizedBox(height: 16),

        // ============================================================
        // SERVICES
        // ============================================================
        if (info['services'] != null)
          _buildCard('Dienste (${(info['services'] as List).length})', Icons.miscellaneous_services, Colors.teal,
            (info['services'] as List).map<Widget>((service) {
              final isActive = service['status'] == 'active';
              final uptime = service['uptime'] ?? '';
              final version = (service['version'] ?? '').toString();
              final updateAvail = service['update_available'];
              final hasUpdate = updateAvail != null && updateAvail.toString().isNotEmpty;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        isActive ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color: isActive ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(service['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(service['description'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          if (version.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  Text('v$version', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600, fontWeight: FontWeight.w500)),
                                  if (hasUpdate)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.orange.shade300),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.arrow_upward, size: 10, color: Colors.orange.shade700),
                                          const SizedBox(width: 2),
                                          Text(
                                            '$updateAvail',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange.shade700),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check, size: 12, color: Colors.green.shade400),
                                        Text(' aktuell', style: TextStyle(fontSize: 10, color: Colors.green.shade400)),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isActive ? 'Aktiv' : 'Inaktiv',
                          style: TextStyle(
                            color: isActive ? Colors.green : Colors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (uptime.isNotEmpty)
                          Text(uptime, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _withDelta(String key, String formattedValue) {
    if (_prevServerInfo == null) return formattedValue;
    final curr = (_serverInfo?[key] ?? 0) as num;
    final prev = (_prevServerInfo?[key] ?? 0) as num;
    final diff = curr - prev;
    if (diff == 0) return formattedValue;
    final sign = diff > 0 ? '+' : '';
    return '$formattedValue  ($sign${_formatNumber(diff.toInt())})';
  }

  double _dbConnectionPercent(Map<String, dynamic> info) {
    final connected = (info['db_threads_connected'] ?? 0) as num;
    final max = (info['db_max_connections'] ?? 151) as num;
    if (max <= 0) return 0;
    return (connected / max * 100).clamp(0, 100).toDouble();
  }

  String _formatNumber(dynamic value) {
    final n = (value is int) ? value : int.tryParse(value.toString()) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  double _ramUsedPercent(Map<String, dynamic> info) {
    final total = (info['ram_total_bytes'] ?? 0) as num;
    final used = (info['ram_used_bytes'] ?? 0) as num;
    if (total <= 0) return 0;
    return (used / total * 100).clamp(0, 100).toDouble();
  }

  double _ramCachePercent(Map<String, dynamic> info) {
    final total = (info['ram_total_bytes'] ?? 0) as num;
    final cache = (info['ram_cache_bytes'] ?? 0) as num;
    if (total <= 0) return 0;
    return (cache / total * 100).clamp(0, 100).toDouble();
  }

  double _ramFreePercent(Map<String, dynamic> info) {
    final total = (info['ram_total_bytes'] ?? 0) as num;
    final free = (info['ram_free_bytes'] ?? 0) as num;
    if (total <= 0) return 0;
    return (free / total * 100).clamp(0, 100).toDouble();
  }

  Widget _buildSegmentedBar(Map<String, dynamic> info) {
    final total = (info['ram_total_bytes'] ?? 1) as num;
    final used = ((info['ram_used_bytes'] ?? 0) as num) / total;
    final cache = ((info['ram_cache_bytes'] ?? 0) as num) / total;
    final free = ((info['ram_free_bytes'] ?? 0) as num) / total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 20,
        child: Row(
          children: [
            Expanded(flex: (used * 1000).round(), child: Container(color: Colors.red.shade400)),
            Expanded(flex: (cache * 1000).round(), child: Container(color: Colors.blue.shade300)),
            Expanded(flex: (free * 1000).round(), child: Container(color: Colors.green.shade300)),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendRow(Color color, String label, String value, double percent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('(${percent.toStringAsFixed(1)}%)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildProgressRow(String label, double percent, String detail) {
    final clamped = percent.clamp(0.0, 100.0);
    final color = clamped > 90 ? Colors.red : (clamped > 70 ? Colors.orange : Colors.green);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
              ),
              Expanded(child: Text(detail, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clamped / 100,
              backgroundColor: Colors.grey.shade200,
              color: color,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRowWithStatus(String label, String value, bool isGood, String statusText) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
          ),
          Expanded(
            child: Row(
              children: [
                SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isGood ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isGood ? Colors.green.shade300 : Colors.orange.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isGood ? Icons.check_circle : Icons.warning,
                        size: 14,
                        color: isGood ? Colors.green.shade700 : Colors.orange.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isGood ? Colors.green.shade700 : Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String title, IconData icon, Color color, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
          ),
          Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
