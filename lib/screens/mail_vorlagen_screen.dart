import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/mail_vorlage.dart';

/// Textbausteine verwalten und einen davon auswählen.
///
/// Wird aus dem Verfassen-Bildschirm geöffnet und gibt die gewählte Vorlage
/// zurück; von dort aus kann man sie auch nur pflegen und ohne Auswahl wieder
/// verlassen.
class MailVorlagenScreen extends StatefulWidget {
  const MailVorlagenScreen({super.key});

  @override
  State<MailVorlagenScreen> createState() => _MailVorlagenScreenState();
}

class _MailVorlagenScreenState extends State<MailVorlagenScreen> {
  final _api = ApiService();

  List<MailVorlage> _vorlagen = const [];
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
    final res = await _api.mailVorlagen('list');
    if (!mounted) return;
    setState(() {
      _laedt = false;
      if (res['success'] == true) {
        _uebernehmen(res);
      } else {
        _fehler = res['message']?.toString() ?? 'Die Vorlagen konnten nicht geladen werden.';
      }
    });
  }

  void _uebernehmen(Map<String, dynamic> res) {
    _vorlagen = ((res['vorlagen'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => MailVorlage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  void _melde(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _bearbeiten([MailVorlage? vorhanden]) async {
    final ergebnis = await showDialog<MailVorlage>(
      context: context,
      builder: (_) => _VorlagenDialog(vorlage: vorhanden),
    );
    if (ergebnis == null || !mounted) return;

    final res = await _api.mailVorlagen('save', {
      if (ergebnis.id > 0) 'id': ergebnis.id,
      'titel': ergebnis.titel,
      'betreff': ergebnis.betreff,
      'text': ergebnis.text,
    });
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() => _uebernehmen(res));
      _melde('Vorlage gespeichert');
    } else {
      _melde(res['message']?.toString() ?? 'Speichern fehlgeschlagen.');
    }
  }

  Future<void> _loeschen(MailVorlage v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vorlage löschen?'),
        content: Text('„${v.titel}" wird entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.mailVorlagen('delete', {'id': v.id});
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() => _uebernehmen(res));
      _melde('Vorlage gelöscht');
    } else {
      _melde(res['message']?.toString() ?? 'Löschen fehlgeschlagen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Textbausteine'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neue Vorlage',
            onPressed: () => _bearbeiten(),
          ),
        ],
      ),
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : _fehler != null
              ? _fehleransicht(cs)
              : _vorlagen.isEmpty
                  ? _leeransicht(cs)
                  : ListView.separated(
                      itemCount: _vorlagen.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _zeile(_vorlagen[i], cs),
                    ),
    );
  }

  Widget _zeile(MailVorlage v, ColorScheme cs) {
    final vorschau = v.text.trim().split('\n').first;
    return ListTile(
      leading: const Icon(Icons.article_outlined),
      title: Text(v.titel, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (v.betreff.isNotEmpty)
            Text('Betreff: ${v.betreff}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text(vorschau,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Aktionen',
        onSelected: (w) => w == 'edit' ? _bearbeiten(v) : _loeschen(v),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
          PopupMenuItem(value: 'delete', child: Text('Löschen')),
        ],
      ),
      // Antippen wählt aus — das ist der häufige Weg. Pflegen geht über das
      // Menü rechts, damit ein Fehlgriff nichts überschreibt.
      onTap: () => Navigator.pop(context, v),
    );
  }

  Widget _leeransicht(ColorScheme cs) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.article_outlined, size: 52, color: cs.outline),
              const SizedBox(height: 12),
              const Text('Noch keine Textbausteine.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'Briefe, die immer wieder gleich anfangen — Widerspruch, '
                'Anfrage an eine Praxis, Anschreiben zu einer Vollmacht.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _bearbeiten(),
                icon: const Icon(Icons.add),
                label: const Text('Erste Vorlage anlegen'),
              ),
            ],
          ),
        ),
      );

  Widget _fehleransicht(ColorScheme cs) => Center(
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

/// Anlegen und Bearbeiten einer Vorlage.
class _VorlagenDialog extends StatefulWidget {
  final MailVorlage? vorlage;

  const _VorlagenDialog({this.vorlage});

  @override
  State<_VorlagenDialog> createState() => _VorlagenDialogState();
}

class _VorlagenDialogState extends State<_VorlagenDialog> {
  late final TextEditingController _titel;
  late final TextEditingController _betreff;
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _titel = TextEditingController(text: widget.vorlage?.titel ?? '');
    _betreff = TextEditingController(text: widget.vorlage?.betreff ?? '');
    _text = TextEditingController(text: widget.vorlage?.text ?? '');
  }

  @override
  void dispose() {
    _titel.dispose();
    _betreff.dispose();
    _text.dispose();
    super.dispose();
  }

  void _platzhalterEinfuegen(String schluessel) {
    final stelle = _text.selection.isValid ? _text.selection.start : _text.text.length;
    final marke = '{$schluessel}';
    final neu = _text.text.substring(0, stelle) + marke + _text.text.substring(stelle);
    setState(() {
      _text.text = neu;
      _text.selection = TextSelection.collapsed(offset: stelle + marke.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.vorlage == null ? 'Neue Vorlage' : 'Vorlage bearbeiten'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titel,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Titel',
                  helperText: 'Wonach Sie die Vorlage später suchen',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _betreff,
                decoration: const InputDecoration(
                  labelText: 'Betreff (optional)',
                  helperText: 'Wird nur gesetzt, wenn der Betreff noch leer ist',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                minLines: 6,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text('Platzhalter',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in kMailPlatzhalter)
                    Tooltip(
                      message: p.beschreibung,
                      child: ActionChip(
                        label: Text('{${p.schluessel}}',
                            style: const TextStyle(fontSize: 12)),
                        onPressed: () => _platzhalterEinfuegen(p.schluessel),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Beim Einfügen werden nur Platzhalter ersetzt, für die ein Wert '
                'vorliegt. Alles andere bleibt stehen und fällt beim Lesen auf — '
                'besser als eine Lücke, die niemand mehr sieht.',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () {
            final titel = _titel.text.trim();
            if (titel.isEmpty || _text.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Titel und Text werden beide gebraucht.'),
              ));
              return;
            }
            Navigator.pop(
              context,
              MailVorlage(
                id: widget.vorlage?.id ?? 0,
                titel: titel,
                betreff: _betreff.text.trim(),
                text: _text.text,
              ),
            );
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
