import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otp/otp.dart';
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
  final Map<int, List<Map<String, dynamic>>> _runs = {};
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Gespeichert'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)));
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
            child: DefaultTabController(
              length: 2,
              child: Column(children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: TabBar(
                    labelColor: Colors.grey.shade800,
                    unselectedLabelColor: Colors.grey.shade500,
                    indicatorColor: Colors.grey.shade800,
                    tabs: const [
                      Tab(icon: Icon(Icons.play_circle_outline, size: 18), text: 'Runner'),
                      Tab(icon: Icon(Icons.account_circle_outlined, size: 18), text: 'Konto Online'),
                    ],
                  ),
                ),
                Expanded(child: TabBarView(children: [
                  // Tab 1: Runner — existing token-setup / repo-list flow.
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : !_tokenConfigured ? _buildTokenSetup() : _buildRepoList(),
                  // Tab 2: Konto Online — email/password/TOTP, server-side
                  // encrypted at rest with the same ev()/dv() helpers the rest
                  // of /api/vereinverwaltung/*.php uses.
                  _KontoOnlineTab(apiService: widget.apiService),
                ])),
              ]),
            ),
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

        final (statusColor, statusIcon, statusText) = _getRunStatus(status, conclusion, latestRun == null);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => _showRepoDetailModal(repo),
            leading: CircleAvatar(backgroundColor: statusColor.withValues(alpha: 0.15), child: Icon(statusIcon, color: statusColor, size: 22)),
            title: Row(children: [
              Expanded(child: Text(repo['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              if (isPrivate)
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
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
            trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ),
        );
      },
    );
  }

  (Color, IconData, String) _getRunStatus(String status, String conclusion, bool noRun) {
    if (noRun) return (Colors.grey, Icons.remove_circle_outline, 'Keine Workflows');
    if (status == 'in_progress' || status == 'queued') return (Colors.orange, Icons.hourglass_top, status == 'queued' ? 'In Warteschlange' : 'Läuft...');
    if (conclusion == 'success') return (Colors.green, Icons.check_circle, 'Erfolgreich');
    if (conclusion == 'failure') return (Colors.red, Icons.error, 'Fehlgeschlagen');
    if (conclusion == 'cancelled') return (Colors.grey, Icons.cancel, 'Abgebrochen');
    return (Colors.grey, Icons.help_outline, conclusion.isNotEmpty ? conclusion : status);
  }

  void _showRepoDetailModal(Map<String, dynamic> repo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: MediaQuery.of(ctx).size.width * 0.85,
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: _RepoDetailModal(apiService: widget.apiService, repo: repo, runs: _runs[repo['id'] as int? ?? 0] ?? []),
          ),
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

// ===== REPO DETAIL MODAL =====
class _RepoDetailModal extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> repo;
  final List<Map<String, dynamic>> runs;

  const _RepoDetailModal({required this.apiService, required this.repo, required this.runs});

  @override
  State<_RepoDetailModal> createState() => _RepoDetailModalState();
}

class _RepoDetailModalState extends State<_RepoDetailModal> {
  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _pulls = [];
  List<Map<String, dynamic>> _releases = [];
  bool _loadingIssues = true;
  bool _loadingPulls = true;
  bool _loadingReleases = true;

  String get _fullName => widget.repo['full_name']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    _loadIssues();
    _loadPulls();
    _loadReleases();
  }

  Future<void> _loadIssues() async {
    try {
      final res = await widget.apiService.githubAction({'action': 'list_issues', 'repo': _fullName});
      if (res['success'] == true && res['issues'] is List) {
        _issues = List<Map<String, dynamic>>.from((res['issues'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingIssues = false);
  }

  Future<void> _loadPulls() async {
    try {
      final res = await widget.apiService.githubAction({'action': 'list_pulls', 'repo': _fullName});
      if (res['success'] == true && res['pulls'] is List) {
        _pulls = List<Map<String, dynamic>>.from((res['pulls'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingPulls = false);
  }

  Future<void> _loadReleases() async {
    try {
      final res = await widget.apiService.githubAction({'action': 'list_releases', 'repo': _fullName});
      if (res['success'] == true && res['releases'] is List) {
        _releases = List<Map<String, dynamic>>.from((res['releases'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingReleases = false);
  }

  @override
  Widget build(BuildContext context) {
    final isPrivate = widget.repo['private'] == true;
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.grey.shade800, Colors.grey.shade900]),
          ),
          child: Row(children: [
            const Icon(Icons.code, size: 24, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.repo['name']?.toString() ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              if ((widget.repo['description']?.toString() ?? '').isNotEmpty)
                Text(widget.repo['description'].toString(), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            if (isPrivate)
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text('Private', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800))),
            if (widget.repo['language'] != null) ...[
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(widget.repo['language'].toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white))),
            ],
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        TabBar(
          labelColor: Colors.grey.shade800,
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: Colors.grey.shade800,
          tabs: [
            Tab(icon: const Icon(Icons.play_circle_outline, size: 16), text: 'Actions (${widget.runs.length})'),
            Tab(icon: const Icon(Icons.bug_report, size: 16), text: 'Issues (${_loadingIssues ? '...' : _issues.length})'),
            Tab(icon: const Icon(Icons.merge, size: 16), text: 'PRs (${_loadingPulls ? '...' : _pulls.length})'),
            Tab(icon: const Icon(Icons.new_releases, size: 16), text: 'Releases (${_loadingReleases ? '...' : _releases.length})'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildActionsTab(),
          _buildIssuesTab(),
          _buildPullsTab(),
          _buildReleasesTab(),
        ])),
      ]),
    );
  }

  // ===== ACTIONS TAB =====
  Widget _buildActionsTab() {
    if (widget.runs.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.play_circle_outline, size: 40, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Text('Keine Workflow-Runs', style: TextStyle(color: Colors.grey.shade400)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: widget.runs.length,
      itemBuilder: (_, i) {
        final run = widget.runs[i];
        final conclusion = run['conclusion']?.toString() ?? '';
        final status = run['status']?.toString() ?? '';
        Color color;
        IconData icon;
        if (status == 'in_progress' || status == 'queued') { color = Colors.orange; icon = Icons.hourglass_top; }
        else if (conclusion == 'success') { color = Colors.green; icon = Icons.check_circle; }
        else if (conclusion == 'failure') { color = Colors.red; icon = Icons.error; }
        else if (conclusion == 'cancelled') { color = Colors.grey; icon = Icons.cancel; }
        else { color = Colors.grey; icon = Icons.help_outline; }

        return Card(child: ListTile(
          onTap: () => _showRunDetail(run),
          leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 20)),
          title: Text(run['name']?.toString() ?? 'Workflow', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: Text('${run['head_branch'] ?? 'main'} • ${run['event'] ?? ''} • #${run['run_number'] ?? ''} • ${_fmt(run['created_at']?.toString() ?? '')}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(status == 'in_progress' ? 'Läuft' : (conclusion.isNotEmpty ? conclusion : status),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          ),
        ));
      },
    );
  }

  void _showRunDetail(Map<String, dynamic> run) {
    final runId = run['id']?.toString() ?? '';
    showDialog(context: context, builder: (ctx) => _RunDetailDialog(apiService: widget.apiService, repo: _fullName, runId: runId, run: run));
  }

  // ===== ISSUES TAB =====
  Widget _buildIssuesTab() {
    if (_loadingIssues) return const Center(child: CircularProgressIndicator());
    if (_issues.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bug_report, size: 40, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Text('Keine offenen Issues', style: TextStyle(color: Colors.grey.shade400)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _issues.length,
      itemBuilder: (_, i) {
        final issue = _issues[i];
        final labels = (issue['labels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final isOpen = issue['state'] == 'open';
        return Card(child: ListTile(
          onTap: () => _showIssueDetail(issue),
          leading: CircleAvatar(
            backgroundColor: isOpen ? Colors.green.shade50 : Colors.purple.shade50,
            child: Icon(isOpen ? Icons.error_outline : Icons.check_circle_outline, color: isOpen ? Colors.green.shade700 : Colors.purple.shade700, size: 20),
          ),
          title: Row(children: [
            Text('#${issue['number']} ', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
            Expanded(child: Text(issue['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
          ]),
          subtitle: Row(children: [
            Text('${issue['user'] ?? ''} • ${_fmt(issue['created_at']?.toString() ?? '')}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            if ((issue['comments'] as int? ?? 0) > 0) ...[
              const SizedBox(width: 8),
              Icon(Icons.comment, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Text('${issue['comments']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
            const SizedBox(width: 8),
            ...labels.take(3).map((l) => Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: _hexColor(l['color']?.toString() ?? 'cccccc').withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
              child: Text(l['name']?.toString() ?? '', style: TextStyle(fontSize: 9, color: _hexColor(l['color']?.toString() ?? '333333'))),
            )),
          ]),
        ));
      },
    );
  }

  void _showIssueDetail(Map<String, dynamic> issue) {
    final labels = (issue['labels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final isOpen = issue['state'] == 'open';
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(isOpen ? Icons.error_outline : Icons.check_circle_outline, color: isOpen ? Colors.green.shade700 : Colors.purple.shade700, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('#${issue['number']} ${issue['title'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
      ]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: isOpen ? Colors.green.shade100 : Colors.purple.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text(isOpen ? 'Open' : 'Closed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isOpen ? Colors.green.shade800 : Colors.purple.shade800))),
          const SizedBox(width: 8),
          Text('von ${issue['user'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Spacer(),
          Text(_fmt(issue['created_at']?.toString() ?? ''), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4, children: labels.map((l) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _hexColor(l['color']?.toString() ?? 'cccccc').withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
            child: Text(l['name']?.toString() ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _hexColor(l['color']?.toString() ?? '333333'))),
          )).toList()),
        ],
        if ((issue['body']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Text(issue['body'].toString(), style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  // ===== PULL REQUESTS TAB =====
  Widget _buildPullsTab() {
    if (_loadingPulls) return const Center(child: CircularProgressIndicator());
    if (_pulls.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.merge, size: 40, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Text('Keine offenen Pull Requests', style: TextStyle(color: Colors.grey.shade400)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pulls.length,
      itemBuilder: (_, i) {
        final pr = _pulls[i];
        final isDraft = pr['draft'] == true;
        final isOpen = pr['state'] == 'open';
        final color = isDraft ? Colors.grey : (isOpen ? Colors.green : Colors.purple);
        return Card(child: ListTile(
          onTap: () => _showPrDetail(pr),
          leading: CircleAvatar(
            backgroundColor: color.shade50,
            child: Icon(isDraft ? Icons.edit_note : (isOpen ? Icons.merge : Icons.check_circle), color: color.shade700, size: 20),
          ),
          title: Row(children: [
            Text('#${pr['number']} ', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
            Expanded(child: Text(pr['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
            if (isDraft) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
              child: Text('Draft', style: TextStyle(fontSize: 10, color: Colors.grey.shade700))),
          ]),
          subtitle: Row(children: [
            Text('${pr['user'] ?? ''} • ${pr['head_branch'] ?? ''} → ${pr['base_branch'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            if ((pr['comments'] as int? ?? 0) + (pr['review_comments'] as int? ?? 0) > 0) ...[
              const SizedBox(width: 8),
              Icon(Icons.comment, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Text('${(pr['comments'] as int? ?? 0) + (pr['review_comments'] as int? ?? 0)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ]),
        ));
      },
    );
  }

  void _showPrDetail(Map<String, dynamic> pr) {
    final isDraft = pr['draft'] == true;
    final isOpen = pr['state'] == 'open';
    final labels = (pr['labels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(isDraft ? Icons.edit_note : Icons.merge, size: 20, color: isOpen ? Colors.green.shade700 : Colors.purple.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text('#${pr['number']} ${pr['title'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
      ]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: isOpen ? Colors.green.shade100 : Colors.purple.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text(isDraft ? 'Draft' : (isOpen ? 'Open' : 'Merged'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isOpen ? Colors.green.shade800 : Colors.purple.shade800))),
          const SizedBox(width: 8),
          Text('von ${pr['user'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Spacer(),
          Text(_fmt(pr['created_at']?.toString() ?? ''), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(Icons.merge, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Text('${pr['head_branch'] ?? ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
            Text(' → ', style: TextStyle(fontSize: 12, color: Colors.blue.shade600)),
            Text('${pr['base_branch'] ?? ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
          ])),
        const SizedBox(height: 10),
        Row(children: [
          _prStat(Icons.commit, '${pr['commits'] ?? 0} Commits', Colors.blue),
          const SizedBox(width: 12),
          _prStat(Icons.add, '+${pr['additions'] ?? 0}', Colors.green),
          const SizedBox(width: 8),
          _prStat(Icons.remove, '-${pr['deletions'] ?? 0}', Colors.red),
          const SizedBox(width: 12),
          _prStat(Icons.insert_drive_file, '${pr['changed_files'] ?? 0} Dateien', Colors.orange),
        ]),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4, children: labels.map((l) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _hexColor(l['color']?.toString() ?? 'cccccc').withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
            child: Text(l['name']?.toString() ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _hexColor(l['color']?.toString() ?? '333333'))),
          )).toList()),
        ],
        if ((pr['body']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Text(pr['body'].toString(), style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  Widget _prStat(IconData icon, String text, MaterialColor color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color.shade600),
      const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade700)),
    ]);
  }

  // ===== RELEASES TAB =====
  Widget _buildReleasesTab() {
    if (_loadingReleases) return const Center(child: CircularProgressIndicator());
    if (_releases.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.new_releases, size: 40, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Text('Keine Releases', style: TextStyle(color: Colors.grey.shade400)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _releases.length,
      itemBuilder: (_, i) {
        final rel = _releases[i];
        final isDraft = rel['draft'] == true;
        final isPre = rel['prerelease'] == true;
        final assets = (rel['assets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final totalDownloads = assets.fold<int>(0, (sum, a) => sum + (a['download_count'] as int? ?? 0));
        return Card(child: ListTile(
          onTap: () => _showReleaseDetail(rel),
          leading: CircleAvatar(
            backgroundColor: isDraft ? Colors.grey.shade100 : (isPre ? Colors.orange.shade50 : Colors.blue.shade50),
            child: Icon(Icons.local_offer, color: isDraft ? Colors.grey.shade600 : (isPre ? Colors.orange.shade700 : Colors.blue.shade700), size: 20),
          ),
          title: Row(children: [
            Text(rel['tag_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace')),
            const SizedBox(width: 8),
            if (rel['name']?.toString() != rel['tag_name']?.toString() && (rel['name']?.toString() ?? '').isNotEmpty)
              Expanded(child: Text(rel['name'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis))
            else
              const Spacer(),
            if (isDraft) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
              child: Text('Draft', style: TextStyle(fontSize: 10, color: Colors.grey.shade700))),
            if (isPre) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
              child: Text('Pre-release', style: TextStyle(fontSize: 10, color: Colors.orange.shade800))),
          ]),
          subtitle: Row(children: [
            Text('${rel['author'] ?? ''} • ${_fmt(rel['published_at']?.toString() ?? rel['created_at']?.toString() ?? '')}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            if (assets.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.inventory_2, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Text('${assets.length} Assets', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
            if (totalDownloads > 0) ...[
              const SizedBox(width: 8),
              Icon(Icons.download, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Text('$totalDownloads', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ]),
        ));
      },
    );
  }

  void _showReleaseDetail(Map<String, dynamic> rel) {
    final assets = (rel['assets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(Icons.local_offer, size: 20, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text('${rel['tag_name'] ?? ''} ${rel['name'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
      ]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('von ${rel['author'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Spacer(),
          Text(_fmt(rel['published_at']?.toString() ?? ''), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
        if ((rel['body']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Release Notes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Text(rel['body'].toString(), style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
        if (assets.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Assets (${assets.length})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          ...assets.map((a) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
            child: Row(children: [
              Icon(Icons.insert_drive_file, size: 16, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade800)),
                Text('${_formatBytes(a['size'] as int? ?? 0)} • ${a['download_count'] ?? 0} Downloads', style: TextStyle(fontSize: 10, color: Colors.blue.shade600)),
              ])),
            ]),
          )),
        ],
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  Color _hexColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    return Colors.grey;
  }

  String _fmt(String iso) {
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

// ===== RUN DETAIL DIALOG =====
class _RunDetailDialog extends StatefulWidget {
  final ApiService apiService;
  final String repo;
  final String runId;
  final Map<String, dynamic> run;

  const _RunDetailDialog({required this.apiService, required this.repo, required this.runId, required this.run});

  @override
  State<_RunDetailDialog> createState() => _RunDetailDialogState();
}

class _RunDetailDialogState extends State<_RunDetailDialog> {
  bool _loading = true;
  Map<String, dynamic>? _runDetail;
  List<Map<String, dynamic>> _jobs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.githubAction({'action': 'get_run_jobs', 'repo': widget.repo, 'run_id': widget.runId});
      if (res['success'] == true) {
        _jobs = (res['jobs'] is List) ? List<Map<String, dynamic>>.from((res['jobs'] as List).map((e) => Map<String, dynamic>.from(e as Map))) : [];
        if (res['run'] != null) _runDetail = Map<String, dynamic>.from(res['run'] as Map);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final conclusion = (_runDetail?['conclusion'] ?? widget.run['conclusion'] ?? '').toString();
    final status = (_runDetail?['status'] ?? widget.run['status'] ?? '').toString();
    Color mainColor;
    IconData mainIcon;
    if (status == 'in_progress' || status == 'queued') { mainColor = Colors.orange; mainIcon = Icons.hourglass_top; }
    else if (conclusion == 'success') { mainColor = Colors.green; mainIcon = Icons.check_circle; }
    else if (conclusion == 'failure') { mainColor = Colors.red; mainIcon = Icons.error; }
    else if (conclusion == 'cancelled') { mainColor = Colors.grey; mainIcon = Icons.cancel; }
    else { mainColor = Colors.grey; mainIcon = Icons.help_outline; }

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: mainColor.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(children: [
          Icon(mainIcon, size: 24, color: mainColor),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.run['name']?.toString() ?? 'Workflow', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: mainColor)),
            Text('Run #${_runDetail?['run_number'] ?? widget.run['run_number'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: mainColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
            child: Text(status == 'in_progress' ? 'Läuft' : (conclusion.isNotEmpty ? conclusion : status),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: mainColor)),
          ),
        ]),
      ),
      content: SizedBox(
        width: 580,
        height: 500,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildRunInfoSection(),
                const SizedBox(height: 16),
                Text('Jobs (${_jobs.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                const SizedBox(height: 8),
                ..._jobs.map(_buildJobCard),
              ])),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
    );
  }

  Widget _buildRunInfoSection() {
    final detail = _runDetail ?? widget.run;
    final duration = _calcDuration(detail['run_started_at']?.toString() ?? detail['created_at']?.toString() ?? '', detail['updated_at']?.toString() ?? '');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Wrap(spacing: 16, runSpacing: 8, children: [
        _infoChip(Icons.commit, 'Commit', detail['head_sha']?.toString() ?? ''),
        _infoChip(Icons.account_tree, 'Branch', detail['head_branch']?.toString() ?? ''),
        _infoChip(Icons.flash_on, 'Event', detail['event']?.toString() ?? ''),
        _infoChip(Icons.person, 'Triggered by', detail['triggering_actor']?.toString() ?? ''),
        if (detail['run_attempt'] != null && (detail['run_attempt'] as int? ?? 1) > 1)
          _infoChip(Icons.replay, 'Attempt', '#${detail['run_attempt']}'),
        if (duration.isNotEmpty)
          _infoChip(Icons.timer, 'Dauer', duration),
      ]),
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: Colors.grey.shade600),
      const SizedBox(width: 4),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
    ]);
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final conclusion = job['conclusion']?.toString() ?? '';
    final status = job['status']?.toString() ?? '';
    Color color;
    IconData icon;
    if (status == 'in_progress' || status == 'queued') { color = Colors.orange; icon = Icons.hourglass_top; }
    else if (conclusion == 'success') { color = Colors.green; icon = Icons.check_circle; }
    else if (conclusion == 'failure') { color = Colors.red; icon = Icons.error; }
    else if (conclusion == 'cancelled' || conclusion == 'skipped') { color = Colors.grey; icon = Icons.cancel; }
    else { color = Colors.grey; icon = Icons.help_outline; }

    final steps = (job['steps'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final duration = _calcDuration(job['started_at']?.toString() ?? '', job['completed_at']?.toString() ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 20),
        title: Row(children: [
          Expanded(child: Text(job['name']?.toString() ?? 'Job', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          if (duration.isNotEmpty)
            Text(duration, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
        subtitle: Text(
          status == 'in_progress' ? 'Läuft...' : conclusion,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
        children: steps.map((step) {
          final sConclusion = step['conclusion']?.toString() ?? '';
          final sStatus = step['status']?.toString() ?? '';
          Color sColor;
          IconData sIcon;
          if (sStatus == 'in_progress') { sColor = Colors.orange; sIcon = Icons.hourglass_top; }
          else if (sConclusion == 'success') { sColor = Colors.green; sIcon = Icons.check_circle_outline; }
          else if (sConclusion == 'failure') { sColor = Colors.red; sIcon = Icons.error_outline; }
          else if (sConclusion == 'skipped') { sColor = Colors.grey; sIcon = Icons.skip_next; }
          else { sColor = Colors.grey; sIcon = Icons.circle_outlined; }

          final sDuration = _calcDuration(step['started_at']?.toString() ?? '', step['completed_at']?.toString() ?? '');

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Row(children: [
              Icon(sIcon, size: 14, color: sColor),
              const SizedBox(width: 8),
              Expanded(child: Text(step['name']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade800))),
              if (sDuration.isNotEmpty)
                Text(sDuration, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ]),
          );
        }).toList(),
      ),
    );
  }

  String _calcDuration(String start, String end) {
    if (start.isEmpty || end.isEmpty) return '';
    try {
      final s = DateTime.parse(start);
      final e = DateTime.parse(end);
      final diff = e.difference(s);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ${diff.inSeconds % 60}s';
      return '${diff.inHours}h ${diff.inMinutes % 60}m';
    } catch (_) {
      return '';
    }
  }
}

// ===== KONTO ONLINE TAB =====
// Stores GitHub account email / password / TOTP shared secret encrypted at rest
// (server side, AES-256-CBC via /api/vereinverwaltung/github_manage.php ev()/dv()).
// Live-renders the current 6-digit TOTP code from the secret using RFC 6238 via
// the otp package, refreshing every second so the user can read off the code
// when GitHub asks for 2FA without leaving the app.
class _KontoOnlineTab extends StatefulWidget {
  final ApiService apiService;
  const _KontoOnlineTab({required this.apiService});

  @override
  State<_KontoOnlineTab> createState() => _KontoOnlineTabState();
}

class _KontoOnlineTabState extends State<_KontoOnlineTab> {
  final _emailC = TextEditingController();
  final _passwordC = TextEditingController();
  final _totpSecretC = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _showPassword = false;
  bool _showSecret = false;
  Timer? _ticker;
  String _currentCode = '';
  int _secondsRemaining = 30;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refreshTotp());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _emailC.dispose();
    _passwordC.dispose();
    _totpSecretC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.githubAction({'action': 'get_konto'});
      if (res['success'] == true && mounted) {
        _emailC.text = res['email']?.toString() ?? '';
        _passwordC.text = res['password']?.toString() ?? '';
        _totpSecretC.text = res['totp_secret']?.toString() ?? '';
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
      _refreshTotp();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final res = await widget.apiService.githubAction({
        'action': 'save_konto',
        'email': _emailC.text.trim(),
        'password': _passwordC.text,
        'totp_secret': _totpSecretC.text.trim().replaceAll(' ', '').toUpperCase(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message']?.toString() ?? (res['success'] == true ? 'Gespeichert' : 'Fehler')),
          backgroundColor: res['success'] == true ? Colors.green.shade600 : Colors.red.shade600,
          duration: const Duration(seconds: 2),
        ));
        _refreshTotp();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
    if (mounted) setState(() => _saving = false);
  }

  void _refreshTotp() {
    final secret = _totpSecretC.text.trim().replaceAll(' ', '').toUpperCase();
    if (secret.isEmpty) {
      if (mounted && (_currentCode.isNotEmpty || _secondsRemaining != 30)) {
        setState(() { _currentCode = ''; _secondsRemaining = 30; });
      }
      return;
    }
    try {
      final code = OTP.generateTOTPCodeString(
        secret,
        DateTime.now().millisecondsSinceEpoch,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      final remaining = 30 - (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 30;
      if (mounted) setState(() { _currentCode = code; _secondsRemaining = remaining; });
    } catch (_) {
      if (mounted) setState(() { _currentCode = ''; _secondsRemaining = 30; });
    }
  }

  void _copyCode() {
    if (_currentCode.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _currentCode));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Code kopiert'),
      duration: Duration(seconds: 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Center(
        child: Container(
          width: 540,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.lock_outline, size: 22, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Text('Konto Online', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
              const Spacer(),
              Tooltip(
                message: 'Server-seitig AES-256 verschlüsselt; nie im Klartext gespeichert',
                child: Icon(Icons.shield, size: 18, color: Colors.green.shade600),
              ),
            ]),
            const SizedBox(height: 16),

            // ── Credentials ────────────────────────────────────────────
            TextField(
              controller: _emailC,
              decoration: InputDecoration(
                labelText: 'E-Mail',
                isDense: true,
                prefixIcon: const Icon(Icons.mail_outline, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordC,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Passwort',
                isDense: true,
                prefixIcon: const Icon(Icons.password, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, size: 18),
                  tooltip: _showPassword ? 'Verbergen' : 'Anzeigen',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),

            // ── 2FA TOTP ──────────────────────────────────────────────
            const SizedBox(height: 18),
            Row(children: [
              Icon(Icons.phone_android, size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Text('2FA Token', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
              const Spacer(),
              Text('Base32 secret aus GitHub 2FA-Setup', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _totpSecretC,
              obscureText: !_showSecret,
              onChanged: (_) => _refreshTotp(),
              decoration: InputDecoration(
                labelText: 'TOTP Secret (Base32)',
                hintText: 'JBSWY3DPEHPK3PXP',
                isDense: true,
                prefixIcon: const Icon(Icons.vpn_key, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(_showSecret ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setState(() => _showSecret = !_showSecret),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),

            // ── Live TOTP code display ─────────────────────────────────
            const SizedBox(height: 14),
            if (_currentCode.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'TOTP Secret eingeben, um den 6-stelligen Code zu generieren',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  )),
                ]),
              )
            else
              InkWell(
                onTap: _copyCode,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.indigo.shade50, Colors.blue.shade50]),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Aktueller Code', style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        _currentCode.replaceAllMapped(RegExp(r'(\d{3})(\d{3})'), (m) => '${m[1]} ${m[2]}'),
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.indigo.shade800, letterSpacing: 4, fontFamily: 'monospace'),
                      ),
                    ]),
                    const Spacer(),
                    Column(children: [
                      SizedBox(
                        width: 38, height: 38,
                        child: Stack(alignment: Alignment.center, children: [
                          CircularProgressIndicator(
                            value: _secondsRemaining / 30.0,
                            strokeWidth: 3,
                            color: _secondsRemaining <= 5 ? Colors.red.shade400 : Colors.indigo.shade400,
                            backgroundColor: Colors.grey.shade200,
                          ),
                          Text('${_secondsRemaining}s', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      Icon(Icons.content_copy, size: 14, color: Colors.indigo.shade500),
                    ]),
                  ]),
                ),
              ),

            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 18),
                label: const Text('Speichern'),
                style: FilledButton.styleFrom(backgroundColor: Colors.grey.shade800),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
