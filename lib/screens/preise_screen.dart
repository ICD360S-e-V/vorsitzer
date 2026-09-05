import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/preis_leser_service.dart';
import '../utils/app_farben.dart';
import '../utils/preis_karte.dart';
import '../utils/preis_link.dart';

/// Preisüberwachung: ein Produkt ist eine KARTE, die je Markt einen Link
/// trägt. Einmal am Tag werden alle Links nachgesehen; die Karte zeigt die
/// Preise nebeneinander und wo es billiger ist.
///
/// ⚠️ Die Karte zeigt IMMER alle Märkte der Kategorie, auch die ohne Link —
/// sonst sieht man nicht, wo noch einer fehlt, und vergleicht ahnungslos zwei
/// von drei.
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
  List<Map<String, dynamic>> _artikel = [];

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
        _artikel = List<Map<String, dynamic>>.from(r['artikel'] ?? []);
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
              : '$n Links gelesen'),
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
          bottom: kategorien.length > 1
              ? TabBar(
                  isScrollable: true,
                  indicatorColor: Colors.amber,
                  tabs: [for (final k in kategorien) Tab(text: '${k['name']}')],
                )
              : null,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _linkHinzufuegen(null, null),
          icon: const Icon(Icons.add),
          label: const Text('Produkt'),
        ),
        body: _laedt
            ? const Center(child: CircularProgressIndicator())
            : _fehler != null
                ? _Hinweis(text: _fehler!, icon: Icons.cloud_off, aktion: _laden)
                : TabBarView(
                    children: [
                      for (final k in kategorien)
                        _Kartenliste(
                          artikel: _artikel
                              .where((a) => '${a['kategorie_id']}' == '${k['id']}')
                              .toList(),
                          haendler: _haendler
                              .where((h) => '${h['kategorie_id']}' == '${k['id']}')
                              .toList(),
                          linkHinzufuegen: _linkHinzufuegen,
                          neuLaden: _laden,
                          verlaufOeffnen: _verlaufZeigen,
                          umbenennen: _umbenennen,
                          zusammenfuehren: _zusammenfuehren,
                        ),
                    ],
                  ),
      ),
    );
  }

  /// `artikelId == null` legt eine neue Karte an. `markt` ist der Markt, dessen
  /// leere Zeile angetippt wurde — nur als Hinweis im Dialog, entschieden wird
  /// am Host des Links.
  Future<void> _linkHinzufuegen(int? artikelId, Map<String, dynamic>? markt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _LinkDialog(artikelId: artikelId, erwarteterMarkt: markt),
    );
    if (ok == true) await _laden();
  }

  Future<void> _umbenennen(Map<String, dynamic> a) async {
    final feld = TextEditingController(text: '${a['name']}');
    final neu = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: F.flaeche,
        title: Text('Produkt benennen', style: TextStyle(color: F.textStark)),
        content: TextField(
          controller: feld,
          autofocus: true,
          style: TextStyle(color: F.textStark),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(c, feld.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    feld.dispose();
    if (neu == null || neu.isEmpty) return;
    await _api.preiseAction(
        {'action': 'artikel_umbenennen', 'artikel_id': a['id'], 'name': neu});
    await _laden();
  }

  /// Zwei Karten, die dasselbe Produkt meinen, zu einer machen.
  Future<void> _zusammenfuehren(Map<String, dynamic> quelle) async {
    final andere = _artikel.where((a) => a['id'] != quelle['id']).toList();
    if (andere.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Es gibt keine zweite Karte')));
      return;
    }
    final ziel = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => SimpleDialog(
        backgroundColor: F.flaeche,
        title: Text('„${quelle['name']}" hinzufügen zu…',
            style: TextStyle(color: F.textStark, fontSize: 16)),
        children: [
          for (final a in andere)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, a),
              child: Text('${a['name']}', style: TextStyle(color: F.textStark)),
            ),
        ],
      ),
    );
    if (ziel == null) return;
    final r = await _api.preiseAction({
      'action': 'artikel_zusammenfuehren',
      'ziel_id': ziel['id'],
      'quelle_id': quelle['id'],
    });
    if (!mounted) return;
    if (r['success'] != true) {
      // ⚠️ Der Grund muss auf den Schirm: „beide haben einen dm-Link" ist die
      // eine Frage, die der Mensch klären muss, und stillschweigend passiert
      // sonst gar nichts.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((r['message'] as String?) ?? 'Ging nicht'),
        backgroundColor: Colors.orange.shade800,
      ));
      return;
    }
    await _laden();
  }

  Future<void> _verlaufZeigen(Map<String, dynamic> link) async {
    final r = await _api.preiseAction({'action': 'verlauf', 'produkt_id': link['id']});
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
              child: Text('${link['haendler_name']} — Preisverlauf',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: F.textStark, fontSize: 16)),
            ),
            if (zeilen.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                // ⚠️ „Noch keine Änderung" ist etwas anderes als „keine Daten".
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
                            ? euro(preis)
                            : '${euro(vorher)}  →  ${euro(preis)}',
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

class _Kartenliste extends StatelessWidget {
  final List<Map<String, dynamic>> artikel;
  final List<Map<String, dynamic>> haendler;
  final Future<void> Function(int?, Map<String, dynamic>?) linkHinzufuegen;
  final Future<void> Function() neuLaden;
  final Future<void> Function(Map<String, dynamic>) verlaufOeffnen;
  final Future<void> Function(Map<String, dynamic>) umbenennen;
  final Future<void> Function(Map<String, dynamic>) zusammenfuehren;

  const _Kartenliste({
    required this.artikel,
    required this.haendler,
    required this.linkHinzufuegen,
    required this.neuLaden,
    required this.verlaufOeffnen,
    required this.umbenennen,
    required this.zusammenfuehren,
  });

  @override
  Widget build(BuildContext context) {
    if (artikel.isEmpty) {
      return const _Hinweis(
        icon: Icons.storefront_outlined,
        text: 'Noch kein Produkt.\n\n'
            'Link von einer Produktseite kopieren und unten auf „Produkt" tippen.\n'
            'Danach kannst du auf dieselbe Karte die Links der anderen Märkte legen.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
      itemCount: artikel.length,
      itemBuilder: (_, i) => _ProduktKarte(
        artikel: artikel[i],
        haendler: haendler,
        linkHinzufuegen: linkHinzufuegen,
        neuLaden: neuLaden,
        verlaufOeffnen: verlaufOeffnen,
        umbenennen: umbenennen,
        zusammenfuehren: zusammenfuehren,
      ),
    );
  }
}

class _ProduktKarte extends StatelessWidget {
  final Map<String, dynamic> artikel;
  final List<Map<String, dynamic>> haendler;
  final Future<void> Function(int?, Map<String, dynamic>?) linkHinzufuegen;
  final Future<void> Function() neuLaden;
  final Future<void> Function(Map<String, dynamic>) verlaufOeffnen;
  final Future<void> Function(Map<String, dynamic>) umbenennen;
  final Future<void> Function(Map<String, dynamic>) zusammenfuehren;

  const _ProduktKarte({
    required this.artikel,
    required this.haendler,
    required this.linkHinzufuegen,
    required this.neuLaden,
    required this.verlaufOeffnen,
    required this.umbenennen,
    required this.zusammenfuehren,
  });

  @override
  Widget build(BuildContext context) {
    final links = List<Map<String, dynamic>>.from(artikel['links'] ?? []);
    final spanne = preisSpanne(links);
    final alter = aeltesteLesung(links);

    return Card(
      color: F.flaeche,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text('${artikel['name']}',
                style: TextStyle(color: F.textStark, fontWeight: FontWeight.w600)),
            subtitle: spanne != null && spanne.vergleichbar
                ? Text(
                    'Unterschied ${euro(spanne.differenz)} '
                    '(${prozentText(spanne.prozent)})',
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w600, fontSize: 13),
                  )
                : Text(
                    links.isEmpty
                        ? 'noch kein Link'
                        : (spanne == null
                            ? 'noch kein Preis gelesen'
                            : 'nur ein Markt — kein Vergleich'),
                    style: TextStyle(color: F.textLeise, fontSize: 12),
                  ),
            trailing: PopupMenuButton<String>(
              onSelected: (w) async {
                // ⚠️ Früh zurück, damit vor dem Dialog kein `await` steht:
                // sonst benutzt die Klasse einen BuildContext über eine
                // asynchrone Lücke hinweg, und ein StatelessWidget hat kein
                // `mounted`, mit dem sich das prüfen liesse.
                if (w == 'umbenennen') {
                  await umbenennen(artikel);
                  return;
                }
                if (w == 'zusammen') {
                  await zusammenfuehren(artikel);
                  return;
                }
                if (w == 'loeschen') {
                  final weg = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: F.flaeche,
                      title: Text('Produkt entfernen?',
                          style: TextStyle(color: F.textStark)),
                      content: Text(
                          '${artikel['name']}\n\nAlle Links und der Preisverlauf gehen mit verloren.',
                          style: TextStyle(color: F.textSchwach)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Abbrechen')),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Entfernen',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (weg == true) {
                    await ApiService().preiseAction(
                        {'action': 'artikel_loeschen', 'artikel_id': artikel['id']});
                    await neuLaden();
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'umbenennen', child: Text('Umbenennen')),
                PopupMenuItem(value: 'zusammen', child: Text('Mit anderer Karte vereinen')),
                PopupMenuItem(value: 'loeschen', child: Text('Entfernen')),
              ],
            ),
          ),
          // ⚠️ ALLE Märkte, auch die ohne Link — sonst sieht man nicht, wo
          // noch einer fehlt, und vergleicht ahnungslos zwei von drei.
          _MarktReihe(
            haendler: haendler,
            links: links,
            artikelId: artikel['id'] as int,
            linkHinzufuegen: linkHinzufuegen,
            neuLaden: neuLaden,
            verlaufOeffnen: verlaufOeffnen,
          ),
          // ⚠️ Vergleicht man zwei Preise aus verschiedenen Tagen, ist die
          // Aussage über vorgestern. Also hinschreiben, nicht verschweigen.
          if (alter != null && alter.inHours >= 36)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(children: [
                const Icon(Icons.schedule, size: 14, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Älteste Lesung ist ${alter.inDays} Tage alt — der Vergleich '
                    'ist entsprechend alt.',
                    style: const TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Die Märkte nebeneinander — eine Spalte je Markt.
///
/// ⚠️ Bei bis zu vier Märkten teilen sie sich die Breite gleichmässig. Darüber
/// wird die Reihe waagerecht scrollbar, statt sie enger zu quetschen: eine
/// Row mit sechs Expanded-Kindern bricht auf einem 411-dp-Telefon in einen
/// Überlauf, und Flutter malt dann den gelb-schwarzen Balken über die Preise.
/// Die Märkte kommen aus der Datenbank, also ist „mehr als drei" kein
/// hypothetischer Fall.
class _MarktReihe extends StatelessWidget {
  final List<Map<String, dynamic>> haendler;
  final List<Map<String, dynamic>> links;
  final int artikelId;
  final Future<void> Function(int?, Map<String, dynamic>?) linkHinzufuegen;
  final Future<void> Function() neuLaden;
  final Future<void> Function(Map<String, dynamic>) verlaufOeffnen;

  const _MarktReihe({
    required this.haendler,
    required this.links,
    required this.artikelId,
    required this.linkHinzufuegen,
    required this.neuLaden,
    required this.verlaufOeffnen,
  });

  static const _breiteBeiVielen = 108.0;

  Map<String, dynamic>? _linkVon(Map<String, dynamic> h) =>
      links.cast<Map<String, dynamic>?>().firstWhere(
            (l) => '${l?['haendler_id']}' == '${h['id']}',
            orElse: () => null,
          );

  @override
  Widget build(BuildContext context) {
    final spalten = [
      for (final h in haendler)
        _MarktSpalte(
          markt: h,
          link: _linkVon(h),
          alleLinks: links,
          artikelId: artikelId,
          linkHinzufuegen: linkHinzufuegen,
          neuLaden: neuLaden,
          verlaufOeffnen: verlaufOeffnen,
        ),
    ];

    if (haendler.length <= 4) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < spalten.length; i++) ...[
                if (i > 0)
                  VerticalDivider(width: 1, thickness: 1, color: F.randLeise),
                Expanded(child: spalten[i]),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        itemCount: spalten.length,
        separatorBuilder: (_, __) =>
            VerticalDivider(width: 1, thickness: 1, color: F.randLeise),
        itemBuilder: (_, i) =>
            SizedBox(width: _breiteBeiVielen, child: spalten[i]),
      ),
    );
  }
}

/// Ein Markt in der Reihe: Name oben, Preis darunter.
class _MarktSpalte extends StatelessWidget {
  final Map<String, dynamic> markt;
  final Map<String, dynamic>? link;
  final List<Map<String, dynamic>> alleLinks;
  final int artikelId;
  final Future<void> Function(int?, Map<String, dynamic>?) linkHinzufuegen;
  final Future<void> Function() neuLaden;
  final Future<void> Function(Map<String, dynamic>) verlaufOeffnen;

  const _MarktSpalte({
    required this.markt,
    required this.link,
    required this.alleLinks,
    required this.artikelId,
    required this.linkHinzufuegen,
    required this.neuLaden,
    required this.verlaufOeffnen,
  });

  @override
  Widget build(BuildContext context) {
    // ⚠️ Der Marktname wird bei Bedarf verkleinert statt abgeschnitten:
    // „Rossmann" neben „dm" darf nicht zu „Rossma…" werden, sonst steht in
    // der Spalte ein Name, den man erst raten muss.
    final name = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text('${markt['name']}',
          maxLines: 1,
          style: TextStyle(color: F.textSchwach, fontSize: 12)),
    );

    if (link == null) {
      return InkWell(
        onTap: () => linkHinzufuegen(artikelId, markt),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              name,
              const SizedBox(height: 4),
              Icon(Icons.add_circle_outline, size: 18, color: F.textLeise),
            ],
          ),
        ),
      );
    }

    final l = link!;
    final billig = istGuenstigster(l, alleLinks);
    final fehler = l['letzter_fehler'] as String?;

    return InkWell(
      onTap: () => verlaufOeffnen(l),
      onLongPress: () async {
        final weg = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            backgroundColor: F.flaeche,
            title: Text('Link entfernen?', style: TextStyle(color: F.textStark)),
            content: Text('${markt['name']}\n${l['url']}',
                style: TextStyle(color: F.textSchwach, fontSize: 12)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Abbrechen')),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Entfernen', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (weg == true) {
          await ApiService().preiseAction({'action': 'link_loeschen', 'id': l['id']});
          await neuLaden();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: billig ? Colors.green.withValues(alpha: 0.09) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            name,
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (billig)
                    const Padding(
                      padding: EdgeInsets.only(right: 3),
                      child: Icon(Icons.check, size: 14, color: Colors.green),
                    ),
                  Text(
                    euro(l['letzter_preis'] as num?),
                    style: TextStyle(
                      color: billig ? Colors.green.shade700 : F.textStark,
                      fontWeight: billig ? FontWeight.bold : FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            // ⚠️ Ein Fehler bekommt ein eigenes Zeichen. Sonst steht in der
            // Spalte weiter der alte Preis und sieht aus wie „unverändert".
            if (fehler != null)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.error_outline, size: 13, color: Colors.orange),
              )
            else if (l['zuletzt_geprueft'] == null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('ungelesen',
                    style: TextStyle(color: F.textLeise, fontSize: 9)),
              )
            else if (l['grundpreis'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${l['grundpreis']}',
                      maxLines: 1,
                      style: TextStyle(color: F.textLeise, fontSize: 9)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// „Link einfügen" — entweder als neue Karte, oder auf eine bestehende.
class _LinkDialog extends StatefulWidget {
  final int? artikelId;
  final Map<String, dynamic>? erwarteterMarkt;
  const _LinkDialog({this.artikelId, this.erwarteterMarkt});

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _feld = TextEditingController();
  final _nameFeld = TextEditingController();
  bool _liest = false;
  bool _speichert = false;
  PreisLesung? _gelesen;
  String? _fehler;
  String? _warnung;

  @override
  void dispose() {
    _feld.dispose();
    _nameFeld.dispose();
    super.dispose();
  }

  /// ⚠️ Der Markt wird am Host entschieden, nicht daran, welche Zeile
  /// angetippt wurde. Passt beides nicht zusammen, sagen wir es sofort —
  /// sonst kommt vom Server ein 409, den niemand erwartet hat.
  void _hostPruefen() {
    final erw = widget.erwarteterMarkt?['host'] as String?;
    final ist = preisHostAus(_feld.text.trim());
    setState(() {
      _warnung = (erw != null && ist.isNotEmpty && ist != erw)
          ? 'Dieser Link gehört zu $ist, die Zeile ist aber '
              '${widget.erwarteterMarkt?['name']}.'
          : null;
    });
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
      if (l?.name != null && _nameFeld.text.isEmpty) _nameFeld.text = l!.name!;
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
      if (widget.artikelId != null) 'artikel_id': widget.artikelId,
      if (widget.artikelId == null && _nameFeld.text.trim().isNotEmpty)
        'artikel_name': _nameFeld.text.trim(),
      ...?_gelesen?.alsBericht(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    if (r['success'] == true) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['bereits_vorhanden'] == true
            ? 'Dieser Link wird bereits überwacht'
            : 'Aufgenommen bei ${r['haendler']}'),
      ));
    } else {
      setState(() =>
          _fehler = (r['message'] as String?) ?? 'Konnte nicht gespeichert werden');
    }
  }

  @override
  Widget build(BuildContext context) {
    final neu = widget.artikelId == null;
    return AlertDialog(
      backgroundColor: F.flaeche,
      title: Text(
        neu ? 'Neues Produkt' : '${widget.erwarteterMarkt?['name'] ?? 'Markt'} hinzufügen',
        style: TextStyle(color: F.textStark),
      ),
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
                hintText: widget.erwarteterMarkt != null
                    ? 'https://${widget.erwarteterMarkt!['host']}/…'
                    : 'https://www.dm.de/p/d/…',
                filled: true,
                fillColor: F.flaecheGedaempft,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                _gelesen = null;
                _fehler = null;
                _hostPruefen();
              },
            ),
            if (neu) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _nameFeld,
                style: TextStyle(color: F.textStark, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Name des Produkts',
                  // ⚠️ Der Name ist die Klammer über die Märkte hinweg: die
                  // drei Läden nennen dasselbe Ding verschieden.
                  helperText: 'Frei wählbar — unter diesem Namen stehen alle Märkte',
                  helperMaxLines: 2,
                  filled: true,
                  fillColor: F.flaecheGedaempft,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_warnung != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_warnung!,
                    style: const TextStyle(color: Colors.orange, fontSize: 12)),
              ),
            if (!PreisLeserService.verfuegbar)
              Text(
                'Auf diesem Gerät lässt sich die Seite nicht vorab lesen.\n'
                'Name und Preis holt der nächste Lauf am Linux-Rechner.',
                style: TextStyle(color: F.textLeise, fontSize: 12),
              ),
            if (_liest)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
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
                        style: TextStyle(
                            color: F.textStark, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(euro(_gelesen!.preis),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    if (_gelesen!.gtin != null)
                      Text('EAN ${_gelesen!.gtin}',
                          style: TextStyle(color: F.textLeise, fontSize: 11)),
                  ],
                ),
              ),
            if (_fehler != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_fehler!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen')),
        if (PreisLeserService.verfuegbar)
          TextButton(
            onPressed: _liest ? null : _lesen,
            child: const Text('Nachsehen'),
          ),
        FilledButton(
          onPressed: _speichert ? null : _speichern,
          child: Text(_speichert ? '…' : 'Speichern'),
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
