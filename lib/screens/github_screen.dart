import 'package:flutter/material.dart';
import '../services/api_service.dart';

class GitHubScreen extends StatefulWidget {
  final VoidCallback onBack;
  final ApiService apiService;

  const GitHubScreen({super.key, required this.onBack, required this.apiService});

  @override
  State<GitHubScreen> createState() => _GitHubScreenState();
}

class _GitHubScreenState extends State<GitHubScreen> {
  bool _loading = true;
  bool _tokenConfigured = false;
  bool _webhookActive = false;
  String _org = '';
  List<Map<String, dynamic>> _repos = [];
  Map<int, List<Map<String, dynamic>>> _runs = {};
  final _tokenController = TextEditingController();
  final _orgController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _orgController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.githubAction({'action': 'get_config'});
      if (res['success'] == true && res['configured'] == true) {
        _tokenConfigured = true;
        _webhookActive = res['webhook_active'] == true;
        _org = res['org']?.toString() ?? '';
        _orgController.text = _org;
        await _loadRepos();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRepos() async {
    final res = await widget.apiService.githubAction({'action': 'list_repos'});
    if (res['success'] == true && res['repos'] is List) {
      _repos = List<Map<String, dynamic>>.from((res['repos'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      _repos.sort((a, b) => (b['updated_at']?.toString() ?? '').compareTo(a['updated_at']?.toString() ?? ''));
      for (final repo in _repos) {
        _loadRuns(repo['id'] as int? ?? 0, repo['full_name']?.toString() ?? '');
      }
    }
  }

  Future<void> _loadRuns(int repoId, String fullName) async {
    final res = await widget.apiService.githubAction({'action': 'list_runs', 'repo': fullName});
    if (res['success'] == true && res['runs'] is List) {
      if (mounted) {
        setState(() {
          _runs[repoId] = List<Map<String, dynamic>>.from((res['runs'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        });
      }
    }
  }

  Future<void> _saveConfig() async {
    final res = await widget.apiService.githubAction({
      'action': 'save_config',
      'token': _tokenController.text.trim(),
      'org': _orgController.text.trim(),
    });
    if (mounted) {
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
        _tokenController.clear();
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack, tooltip: 'Zurück'),
            const SizedBox(width: 8),
            Icon(Icons.code, size: 32, color: Colors.grey.shade800),
            const SizedBox(width: 12),
            const Text('GitHub', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            if (_org.isNotEmpty) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                child: Text(_org, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              ),
            ],
            const Spacer(),
            if (_tokenConfigured && _webhookActive) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_active, size: 14, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text('Webhook aktiv', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                ]),
              ),
              const SizedBox(width: 8),
            ],
            if (_tokenConfigured) ...[
              IconButton(icon: const Icon(Icons.refresh), tooltip: 'Aktualisieren', onPressed: _load),
              const SizedBox(width: 8),
              IconButton(icon: Icon(Icons.settings, color: Colors.grey.shade600), tooltip: 'Token ändern',
                onPressed: () => setState(() => _tokenConfigured = false)),
            ],
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_tokenConfigured ? _buildTokenSetup() : _buildRepoList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenSetup() {
    return Center(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300),
          boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 8)]),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.vpn_key, size: 24, color: Colors.grey.shade700),
            const SizedBox(width: 10),
            Text('GitHub Konfiguration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Personal Access Token (classic) benötigt:\n• repo (Full control of private repositories)\n• workflow (Update GitHub Action workflows)\n• read:org (Read org membership)',
                style: TextStyle(fontSize: 11, color: Colors.amber.shade900, height: 1.4),
              )),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(controller: _orgController,
            decoration: InputDecoration(labelText: 'Organisation', hintText: 'ICD360S-e-V', isDense: true,
              prefixIcon: const Icon(Icons.business, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          TextField(controller: _tokenController, obscureText: true,
            decoration: InputDecoration(labelText: 'Personal Access Token', hintText: 'ghp_...', isDense: true,
              prefixIcon: const Icon(Icons.vpn_key, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 20),
          Row(children: [
            FilledButton.icon(onPressed: _saveConfig, icon: const Icon(Icons.save, size: 18), label: const Text('Speichern'),
              style: FilledButton.styleFrom(backgroundColor: Colors.grey.shade800)),
            if (_org.isNotEmpty) ...[
              const SizedBox(width: 12),
              OutlinedButton(onPressed: () => setState(() => _tokenConfigured = true), child: const Text('Abbrechen')),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _buildRepoList() {
    if (_repos.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.code_off, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('Keine Repositories gefunden', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
      ]));
    }

    return ListView.builder(
      itemCount: _repos.length,
      itemBuilder: (_, i) {
        final repo = _repos[i];
        final repoId = repo['id'] as int? ?? 0;
        final runs = _runs[repoId] ?? [];
        final latestRun = runs.isNotEmpty ? runs.first : null;
        final conclusion = latestRun?['conclusion']?.toString() ?? '';
        final status = latestRun?['status']?.toString() ?? '';
        final isPrivate = repo['private'] == true;

        Color statusColor;
        IconData statusIcon;
        String statusText;
        if (latestRun == null) {
          statusColor = Colors.grey;
          statusIcon = Icons.remove_circle_outline;
          statusText = 'Keine Workflows';
        } else if (status == 'in_progress' || status == 'queued') {
          statusColor = Colors.orange;
          statusIcon = Icons.hourglass_top;
          statusText = status == 'queued' ? 'In Warteschlange' : 'Läuft...';
        } else if (conclusion == 'success') {
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
          statusText = 'Erfolgreich';
        } else if (conclusion == 'failure') {
          statusColor = Colors.red;
          statusIcon = Icons.error;
          statusText = 'Fehlgeschlagen';
        } else if (conclusion == 'cancelled') {
          statusColor = Colors.grey;
          statusIcon = Icons.cancel;
          statusText = 'Abgebrochen';
        } else {
          statusColor = Colors.grey;
          statusIcon = Icons.help_outline;
          statusText = conclusion.isNotEmpty ? conclusion : status;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CircleAvatar(backgroundColor: statusColor.withValues(alpha: 0.15), child: Icon(statusIcon, color: statusColor, size: 22)),
            title: Row(children: [
              Expanded(child: Text(repo['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              if (isPrivate)
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                  child: Text('Private', style: TextStyle(fontSize: 10, color: Colors.orange.shade800))),
            ]),
            subtitle: Row(children: [
              Icon(statusIcon, size: 12, color: statusColor),
              const SizedBox(width: 4),
              Text(statusText, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
              if (latestRun != null) ...[
                const SizedBox(width: 8),
                Text('• ${_formatDate(latestRun['created_at']?.toString() ?? '')}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
              if (repo['language'] != null) ...[
                const SizedBox(width: 8),
                Text('• ${repo['language']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ]),
            children: [
              if (runs.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text('Keine Workflow-Runs vorhanden', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)))
              else
                ...runs.take(5).map((run) => _buildRunTile(run)),
              if (runs.length > 5)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('... und ${runs.length - 5} weitere', style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRunTile(Map<String, dynamic> run) {
    final conclusion = run['conclusion']?.toString() ?? '';
    final status = run['status']?.toString() ?? '';
    Color color;
    IconData icon;
    if (status == 'in_progress' || status == 'queued') {
      color = Colors.orange;
      icon = Icons.hourglass_top;
    } else if (conclusion == 'success') {
      color = Colors.green;
      icon = Icons.check_circle_outline;
    } else if (conclusion == 'failure') {
      color = Colors.red;
      icon = Icons.error_outline;
    } else if (conclusion == 'cancelled') {
      color = Colors.grey;
      icon = Icons.cancel_outlined;
    } else {
      color = Colors.grey;
      icon = Icons.help_outline;
    }

    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18, color: color),
      title: Text(run['name']?.toString() ?? run['workflow_name']?.toString() ?? 'Workflow', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${run['head_branch'] ?? 'main'} • ${run['event'] ?? ''} • ${_formatDate(run['created_at']?.toString() ?? '')}',
        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(
          status == 'in_progress' ? 'Läuft' : (conclusion.isNotEmpty ? conclusion : status),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(d);
      if (diff.inMinutes < 1) return 'gerade eben';
      if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
      if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
      if (diff.inDays < 7) return 'vor ${diff.inDays} Tagen';
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    } catch (_) {
      return iso;
    }
  }
}
