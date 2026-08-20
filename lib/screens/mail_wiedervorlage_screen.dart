import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Welche Nachricht soll geöffnet werden, nachdem der Bildschirm zugeht.
class MailFristZiel {
  final String box;
  final int uid;

  const MailFristZiel(this.box, this.uid);
}

/// Die offenen Wiedervorlagen.
///
/// ⚠️ Ohne diesen Bildschirm war die Wiedervorlage ein Nur-Schreib-Weg: man
/// konnte eine Frist setzen, und nichts hat sie je wieder gezeigt. Das ist
/// schlimmer als gar keine Funktion — man verlässt sich darauf.
class MailWiedervorlageScreen extends StatefulWidget {
  const MailWiedervorlageScreen({super.key});

  @override
  State<MailWiedervorlageScreen> createState() => _MailWiedervorlageScreenState();
}

class _MailWiedervorlageScreenState extends State<MailWiedervorlageScreen> {
  final _api = ApiService();

  List<Map<String, dynamic>> _fristen = const [];
  bool _laedt = true;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    final res = await _api.mailWiedervorlage('list');
    if (!mounted) return;
    setState(() {
      _laedt = false;
      if (res['success'] == true) {
        _uebernehmen(res);
      } else {
        _fehler = res['message']?.toString() ??
            'Die Wiedervorlagen konnten nicht geladen werden.';
      }
    });
  }

  void _uebernehmen(Map<String, dynamic> res) {
    _fristen = ((res['wiedervorlagen'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _abhaken(Map<String, dynamic> f) async {
    final res = await _api.mailWiedervorlage('erledigt', {'id': f['id']});
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() => _uebernehmen(res));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erledigt'),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message']?.toString() ?? 'Nicht möglich.'),
      ));
    }
  }

  Future<void> _loeschen(Map<String, dynamic> f) async {
    final res = await _api.mailWiedervorlage('loeschen', {'id': f['id']});
    if (!mounted) return;
    if (res['success'] == true) setState(() => _uebernehmen(res));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final faellig = _fristen.where((f) => f['faellig'] == true).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wiedervorlagen'),
        bottom: faellig == 0
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFB3261E),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '$faellig fällig',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: _laedt ? null : _laden,
          ),
        ],
      ),
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : _fehler != null
              ? _fehleransicht()
              : _fristen.isEmpty
                  ? _leeransicht(cs)
                  : RefreshIndicator(
                      onRefresh: _laden,
                      child: ListView.separated(
                        itemCount: _fristen.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _zeile(_fristen[i], cs),
                      ),
                    ),
    );
  }

  Widget _zeile(Map<String, dynamic> f, ColorScheme cs) {
    final istFaellig = f['faellig'] == true;
    final betreff = '${f['betreff'] ?? ''}'.trim();
    final notiz = '${f['notiz'] ?? ''}'.trim();
    final uid = (f['uid'] as num?)?.toInt() ?? 0;
    return ListTile(
      leading: Icon(
        istFaellig ? Icons.notification_important : Icons.schedule_outlined,
        color: istFaellig ? const Color(0xFFB3261E) : cs.onSurfaceVariant,
      ),
      title: Text(betreff.isEmpty ? '(kein Betreff)' : betreff,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: istFaellig ? FontWeight.w700 : FontWeight.normal)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_datumDeutsch('${f['faellig_am'] ?? ''}')} · ${f['box'] ?? ''}',
            style: TextStyle(
                fontSize: 12,
                color: istFaellig ? const Color(0xFFB3261E) : cs.onSurfaceVariant),
          ),
          if (notiz.isNotEmpty)
            Text(notiz,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline),
            tooltip: 'Erledigt',
            onPressed: () => _abhaken(f),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mehr',
            onSelected: (_) => _loeschen(f),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'del', child: Text('Löschen')),
            ],
          ),
        ],
      ),
      // Antippen führt zur Nachricht — der einzige Grund, warum die Frist
      // überhaupt an einer E-Mail hängt und nicht in einem Kalender steht.
      onTap: uid <= 0
          ? null
          : () => Navigator.pop(
              context, MailFristZiel('${f['box'] ?? 'INBOX'}', uid)),
    );
  }

  static String _datumDeutsch(String iso) {
    final t = iso.split('-');
    return t.length == 3 ? '${t[2]}.${t[1]}.${t[0]}' : iso;
  }

  Widget _leeransicht(ColorScheme cs) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_outlined, size: 52, color: cs.outline),
              const SizedBox(height: 12),
              const Text('Keine offenen Wiedervorlagen.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'In einer geöffneten Nachricht setzt der Uhr-Knopf eine Frist — '
                'für Widerspruch, Anhörung oder eine Auskunft nach der DSGVO.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );

  Widget _fehleransicht() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.redAccent),
              const SizedBox(height: 10),
              Text(_fehler!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _laden,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
}
