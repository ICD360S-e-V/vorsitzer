import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/preis_leser_service.dart';
import '../utils/app_farben.dart';
import '../utils/preis_link.dart';

/// Preisüberwachung: ein Link je Produkt, einmal am Tag nachgesehen.
///
/// Die Reiter kommen aus der Datenbank (`preis_kategorien` →
/// `preis_haendler`), nicht aus dieser Datei. Ein neuer Markt ist damit eine
/// Zeile und kein Release.
class PreiseScreen extends StatefulWidget {
  const PreiseScreen({super.key});

  @override
  State<PreiseScreen> createState() => _PreiseScreenState();
}

class _PreiseScreenState extends State<PreiseScreen> {
  final _api = ApiService();
  bool _laedt = true;
  String? _fehler;
  List<Map<String, dynamic>> _kategorien = [];
  List<Map<String, dynamic>> _haendler = [];
  List<Map<String, dynamic>> _produkte = [];

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
    try {
      final r = await _api.preiseAction({'action': 'list'});
      if (!mounted) return;
      if (r['success'] != true) {
        setState(() {
          _laedt = false;
          _fehler = (r['message'] as String?) ?? 'Konnte nicht geladen werden';
        });
        return;
      }
      setState(() {
        _kategorien = List<Map<String, dynamic>>.from(r['kategorien'] ?? []);
        _haendler = List<Map<String, dynamic>>.from(r['haendler'] ?? []);
        _produkte = List<Map<String, dynamic>>.from(r['produkte'] ?? []);
        _laedt = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _laedt = false;
        _fehler = 'Keine Verbindung: $e';
      });
    }
  }

  Future<void> _jetztPruefen() async {
    final n = await PreisLeserService().lauf();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n < 0
          ? 'Der Lauf konnte nicht starten'
          : n == 0
              ? 'Heute ist schon alles gelesen'
              : '$n Produkte gelesen'),
    ));
    await _laden();
  }

  @override
  Widget build(BuildContext context) {
    final kategorien = _kategorien.isEmpty
        ? [
            {'id': 0, 'name': 'Drogerie Markt'}
          ]
        : _kategorien;

    return DefaultTabController(
      length: kategorien.length,
      child: Scaffold(
        backgroundColor: F.hintergrund,
        appBar: AppBar(
          title: const Text('Preise'),
          backgroundColor: const Color(0xFF1a1a2e),
          foregroundColor: Colors.white,
          actions: [
            // Nur dort, wo ein Browser da ist. Auf dem Telefon gibt es keinen,
            // und ein Knopf, der nichts tun kann, ist schlimmer als keiner.
            if (PreisLeserService.verfuegbar)
              ValueListenableBuilder<String?>(
                valueListenable: PreisLeserService().fortschritt,
                builder: (_, stand, __) => stand != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(stand,
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Jetzt prüfen',
                        onPressed: _jetztPruefen,
                      ),
              ),
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Neu laden',
              onPressed: _laden,
            ),
          ],
          // Bei einer einzigen Kategorie wäre eine Leiste mit einem Reiter
          // nur Balken ohne Auswahl.
          bottom: kategorien.length > 1
              ? TabBar(
                  isScrollable: true,
                  indicatorColor: Colors.amber,
                  tabs: [for (final k in kategorien) Tab(text: '${k['name']}')],
                )
              : null,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _produktHinzufuegen,
          icon: const Icon(Icons.add_link),
          label: const Text('Produkt'),
        ),
        body: _laedt
            ? const Center(child: CircularProgressIndicator())
            : _fehler != null
                ? _Hinweis(text: _fehler!, icon: Icons.cloud_off, aktion: _laden)
                : TabBarView(
                    children: [
                      for (final k in kategorien) _KategorieAnsicht(
                        haendler: _haendler
                            .where((h) => '${h['kategorie_id']}' == '${k['id']}')
                            .toList(),
                        produkte: _produkte,
                        beiAenderung: _laden,
                        verlaufOeffnen: _verlaufZeigen,
                      ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _produktHinzufuegen() async {
    final zugefuegt = await showDialog<bool>(
      context: context,
      builder: (_) => const _LinkDialog(),
    );
    if (zugefuegt == true) await _laden();
  }

  Future<void> _verlaufZeigen(Map<String, dynamic> p) async {
    final r = await _api.preiseAction({'action': 'verlauf', 'produkt_id': p['id']});
    if (!mounted) return;
    final zeilen = List<Map<String, dynamic>>.from(r['verlauf'] ?? []);
    showModalBottomSheet(
      context: context,
      backgroundColor: F.flaeche,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${p['name'] ?? p['url']}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: F.textStark, fontSize: 16)),
            ),
            if (zeilen.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                // ⚠️ „Noch keine Änderung" ist etwas anderes als „keine Daten".
                // Der Verlauf trägt bewusst nur Sprünge.
                child: Text('Noch keine Preisänderung aufgezeichnet.',
                    style: TextStyle(color: F.textSchwach)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: zeilen.length,
                  itemBuilder: (_, i) {
                    final z = zeilen[i];
                    final vorher = z['vorher'] as num?;
                    final preis = z['preis'] as num;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        vorher == null
                            ? Icons.flag_outlined
                            : (preis < vorher ? Icons.south : Icons.north),
                        color: vorher == null
                            ? F.textSchwach
                            : (preis < vorher ? Colors.green : Colors.red),
                      ),
                      title: Text(
                        vorher == null
                            ? _euro(preis)
                            : '${_euro(vorher)}  →  ${_euro(preis)}',
                        style: TextStyle(color: F.textStark),
                      ),
                      subtitle: Text('${z['gemessen_am']}',
                          style: TextStyle(color: F.textLeise, fontSize: 12)),
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

String _euro(num? w) =>
    w == null ? '—' : '${w.toStringAsFixed(2).replaceAll('.', ',')} €';

class _KategorieAnsicht extends StatelessWidget {
  final List<Map<String, dynamic>> haendler;
  final List<Map<String, dynamic>> produkte;
  final Future<void> Function() beiAenderung;
  final Future<void> Function(Map<String, dynamic>) verlaufOeffnen;

  const _KategorieAnsicht({
    required this.haendler,
    required this.produkte,
    required this.beiAenderung,
    required this.verlaufOeffnen,
  });

  @override
  Widget build(BuildContext context) {
    if (haendler.isEmpty) {
      return const _Hinweis(text: 'Für diese Kategorie ist kein Markt hinterlegt.', icon: Icons.storefront);
    }
    return DefaultTabController(
      length: haendler.length,
      child: Column(
        children: [
          Material(
            color: F.flaeche,
            child: TabBar(
              isScrollable: haendler.length > 3,
              labelColor: F.textStark,
              unselectedLabelColor: F.textSchwach,
              indicatorColor: Colors.amber,
              tabs: [
                for (final h in haendler)
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${h['name']}'),
                        const SizedBox(width: 6),
                        _Zaehler(
                          n: produkte
                              .where((p) => '${p['haendler_id']}' == '${h['id']}')
                              .length,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final h in haendler)
                  _ProduktListe(
                    produkte: produkte
                        .where((p) => '${p['haendler_id']}' == '${h['id']}')
                        .toList(),
                    haendler: h,
                    beiAenderung: beiAenderung,
                    verlaufOeffnen: verlaufOeffnen,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Zaehler extends StatelessWidget {
  final int n;
  const _Zaehler({required this.n});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: F.flaecheGedaempft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$n', style: TextStyle(fontSize: 11, color: F.textSchwach)),
      );
}

class _ProduktListe extends StatelessWidget {
  final List<Map<String, dynamic>> produkte;
  final Map<String, dynamic> haendler;
  final Future<void> Function() beiAenderung;
  final Future<void> Function(Map<String, dynamic>) verlaufOeffnen;

  const _ProduktListe({
    required this.produkte,
    required this.haendler,
    required this.beiAenderung,
    required this.verlaufOeffnen,
  });

  @override
  Widget build(BuildContext context) {
    if (produkte.isEmpty) {
      return _Hinweis(
        icon: Icons.add_link,
        text: 'Noch kein Produkt bei ${haendler['name']}.\n\n'
            'Link von der Produktseite kopieren und unten auf „Produkt" tippen.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: produkte.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: F.randLeise),
      itemBuilder: (_, i) => _ProduktKachel(
        p: produkte[i],
        beiAenderung: beiAenderung,
        verlaufOeffnen: verlaufOeffnen,
      ),
    );
  }
}

class _ProduktKachel extends StatelessWidget {
  final Map<String, dynamic> p;
  final Future<void> Function() beiAenderung;
  final Future<void> Function(Map<String, dynamic>) verlaufOeffnen;

  const _ProduktKachel({
    required this.p,
    required this.beiAenderung,
    required this.verlaufOeffnen,
  });

  @override
  Widget build(BuildContext context) {
    final fehler = p['letzter_fehler'] as String?;
    final geprueft = p['zuletzt_geprueft'] as String?;
    return ListTile(
      onTap: () => verlaufOeffnen(p),
      title: Text(
        (p['name'] as String?)?.isNotEmpty == true ? '${p['name']}' : '${p['url']}',
        style: TextStyle(color: F.textStark, fontWeight: FontWeight.w500),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p['grundpreis'] != null)
            Text('${p['grundpreis']}',
                style: TextStyle(color: F.textLeise, fontSize: 12)),
          // ⚠️ Ein Fehler wird ausgeschrieben, nicht verschwiegen. Sonst steht
          // dort weiter der alte Preis und sieht aus wie „unverändert".
          if (fehler != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 14, color: Colors.orange),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('Nicht lesbar: $fehler',
                      style: const TextStyle(color: Colors.orange, fontSize: 12)),
                ),
              ]),
            )
          else if (geprueft != null)
            Text('geprüft: $geprueft',
                style: TextStyle(color: F.textLeise, fontSize: 12))
          else
            Text('noch nicht gelesen',
                style: TextStyle(color: F.textLeise, fontSize: 12)),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_euro(p['letzter_preis'] as num?),
              style: TextStyle(
                  color: F.textStark, fontWeight: FontWeight.bold, fontSize: 16)),
          if (p['verfuegbar'] == false)
            const Text('nicht lieferbar',
                style: TextStyle(color: Colors.orange, fontSize: 11)),
        ],
      ),
      onLongPress: () async {
        final weg = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: F.flaeche,
            title: Text('Nicht mehr überwachen?', style: TextStyle(color: F.textStark)),
            content: Text('${p['name'] ?? p['url']}\n\nDer Preisverlauf geht mit verloren.',
                style: TextStyle(color: F.textSchwach)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Entfernen', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (weg == true) {
          await ApiService().preiseAction({'action': 'delete', 'id': p['id']});
          await beiAenderung();
        }
      },
    );
  }
}

/// „Link einfügen" — und, wo ein Browser da ist, sofort nachsehen, was
/// dahintersteckt.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _feld = TextEditingController();
  bool _liest = false;
  bool _speichert = false;
  PreisLesung? _gelesen;
  String? _fehler;

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  Future<void> _lesen() async {
    final url = _feld.text.trim();
    if (preisHostAus(url).isEmpty) {
      setState(() => _fehler = 'Das ist kein Link');
      return;
    }
    setState(() {
      _liest = true;
      _fehler = null;
      _gelesen = null;
    });
    final l = await PreisLeserService().einmalLesen(url);
    if (!mounted) return;
    setState(() {
      _liest = false;
      _gelesen = l;
      _fehler = l == null ? 'Auf dieser Seite war kein Preis zu finden' : null;
    });
  }

  Future<void> _speichern() async {
    final url = _feld.text.trim();
    if (preisHostAus(url).isEmpty) {
      setState(() => _fehler = 'Das ist kein Link');
      return;
    }
    setState(() => _speichert = true);
    final r = await ApiService().preiseAction({
      'action': 'add',
      'url': url,
      ...?_gelesen?.alsBericht(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    if (r['success'] == true) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['bereits_vorhanden'] == true
            ? 'Wird bereits überwacht'
            : 'Aufgenommen bei ${r['haendler']}'),
      ));
    } else {
      setState(() => _fehler = (r['message'] as String?) ?? 'Konnte nicht gespeichert werden');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: F.flaeche,
      title: Text('Produkt beobachten', style: TextStyle(color: F.textStark)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _feld,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(color: F.textStark, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Link zur Produktseite',
                hintText: 'https://www.dm.de/p/d/…',
                filled: true,
                fillColor: F.flaecheGedaempft,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {
                _gelesen = null;
                _fehler = null;
              }),
            ),
            const SizedBox(height: 8),
            if (!PreisLeserService.verfuegbar)
              // ⚠️ Ehrlich sagen, was passiert: auf dem Telefon gibt es keinen
              // Browser, der die Seite vorab lesen könnte. Der Link wird
              // trotzdem angenommen — nur füllt ihn erst der nächste Lauf.
              Text(
                'Auf diesem Gerät lässt sich die Seite nicht vorab lesen.\n'
                'Name und Preis holt der nächste Lauf am Linux-Rechner.',
                style: TextStyle(color: F.textLeise, fontSize: 12),
              ),
            if (_liest)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Seite wird gelesen…'),
                ]),
              ),
            if (_gelesen != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: F.flaecheGedaempft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_gelesen!.name ?? 'ohne Namen',
                        style: TextStyle(color: F.textStark, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_euro(_gelesen!.preis),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (_gelesen!.gtin != null)
                      Text('EAN ${_gelesen!.gtin}',
                          style: TextStyle(color: F.textLeise, fontSize: 11)),
                  ],
                ),
              ),
            if (_fehler != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_fehler!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        if (PreisLeserService.verfuegbar)
          TextButton(
            onPressed: _liest ? null : _lesen,
            child: const Text('Nachsehen'),
          ),
        FilledButton(
          onPressed: _speichert ? null : _speichern,
          child: Text(_speichert ? '…' : 'Beobachten'),
        ),
      ],
    );
  }
}

class _Hinweis extends StatelessWidget {
  final String text;
  final IconData icon;
  final Future<void> Function()? aktion;
  const _Hinweis({required this.text, required this.icon, this.aktion});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: F.textLeise),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: F.textSchwach)),
              if (aktion != null) ...[
                const SizedBox(height: 12),
                TextButton(onPressed: aktion, child: const Text('Nochmal versuchen')),
              ],
            ],
          ),
        ),
      );
}
