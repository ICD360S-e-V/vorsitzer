import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';

/// Der öffentliche Webauftritt icd360s.de: wer ihn liest und ob er sicher ist.
///
/// Die Zahlen stammen aus dem Zugriffsprotokoll des eigenen Servers — kein
/// Google Analytics, kein Matomo, kein Zählpixel. Das ist nicht nur eine
/// Frage der Haltung: ohne Skript und ohne Cookie im Browser greift § 25
/// TDDDG nicht, der Auftritt braucht also keinen Einwilligungsbanner.
///
/// ⚠️ Alle Listen werden über [webListe] gelesen. PHP kennt nur einen
/// Array-Typ; eine leere Struktur kommt als `[]`, eine gefüllte mit
/// Zeichenschlüsseln als Objekt. Ein `as List` auf einem Objekt wirft, und in
/// einem Release-Build ist das Ergebnis eine graue Fläche ohne jede Meldung —
/// genau so verschwand am 05.08.2026 der Speedtest-Bildschirm.
class WebsiteScreen extends StatefulWidget {
  const WebsiteScreen({super.key});

  @override
  State<WebsiteScreen> createState() => _WebsiteScreenState();
}

/// Liest eine Liste von Karten, egal in welcher der beiden Formen sie ankommt.
List<Map<String, dynamic>> webListe(dynamic roh) {
  if (roh is! List) return const [];
  return roh.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// Liest eine Karte; eine Liste (auch die leere) ist hier keine.
Map<String, dynamic> webKarte(dynamic roh) =>
    roh is Map ? Map<String, dynamic>.from(roh) : const {};

int webZahl(dynamic roh) {
  if (roh is int) return roh;
  if (roh is double) return roh.round();
  return int.tryParse('${roh ?? ''}') ?? 0;
}

double webKomma(dynamic roh) {
  if (roh is num) return roh.toDouble();
  return double.tryParse('${roh ?? ''}') ?? 0;
}

String webTausend(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String webBytes(int b) {
  if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
  if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} kB';
  return '$b B';
}

/// Landeskennungen als Flagge. Zwei Buchstaben werden zu zwei
/// Regional-Indikator-Zeichen — dieselbe Rechnung, die auch die Tabelle
/// `telefon_laender` auf dem Server benutzt.
String webFlagge(String iso) {
  if (iso.length != 2) return '';
  final gross = iso.toUpperCase();
  const basis = 0x1F1E6;
  final a = gross.codeUnitAt(0), b = gross.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCodes([basis + (a - 65), basis + (b - 65)]);
}

/// Farbe und Zeichen je Befundstufe. „info" ist bewusst neutral: eine
/// bewusst getroffene Entscheidung ist kein Mangel.
({Color farbe, IconData icon, String text}) webStand(String stand) =>
    switch (stand) {
      'ok' => (farbe: const Color(0xFF2E7D32), icon: Icons.check_circle, text: 'in Ordnung'),
      'warnung' => (farbe: const Color(0xFFEF6C00), icon: Icons.error_outline, text: 'Hinweis'),
      'fehler' => (farbe: const Color(0xFFC62828), icon: Icons.cancel, text: 'Fehler'),
      _ => (farbe: const Color(0xFF546E7A), icon: Icons.info_outline, text: 'zur Kenntnis'),
    };

class _WebsiteScreenState extends State<WebsiteScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  final _api = ApiService();

  int _tage = 30;
  bool _laedt = true;
  String? _fehler;

  Map<String, dynamic> _uebersicht = const {};
  Map<String, dynamic> _besucher = const {};
  Map<String, dynamic> _seiten = const {};
  Map<String, dynamic> _angriffe = const {};
  Map<String, dynamic> _sicherheit = const {};
  bool _prueftGerade = false;

  static const _zeitraeume = {7: '7 Tage', 30: '30 Tage', 90: '90 Tage', 365: '1 Jahr'};

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    try {
      // Vier Abfragen nebeneinander statt nacheinander: sie hängen nicht
      // voneinander ab, und über eine Mobilverbindung ist der Unterschied
      // zwischen 4×400 ms und 400 ms deutlich zu sehen.
      final antworten = await Future.wait([
        _api.websiteAction({'action': 'uebersicht', 'tage': _tage}),
        _api.websiteAction({'action': 'besucher', 'tage': _tage}),
        _api.websiteAction({'action': 'seiten', 'tage': _tage}),
        _api.websiteAction({'action': 'angriffe', 'tage': _tage}),
        _api.websiteAction({'action': 'sicherheit'}),
      ]);
      if (!mounted) return;
      if (antworten.first['success'] != true) {
        setState(() {
          _laedt = false;
          _fehler = antworten.first['message']?.toString() ??
              'Der Server hat die Übersicht nicht geliefert.';
        });
        return;
      }
      setState(() {
        _uebersicht = Map<String, dynamic>.from(antworten[0]);
        _besucher = Map<String, dynamic>.from(antworten[1]);
        _seiten = Map<String, dynamic>.from(antworten[2]);
        _angriffe = Map<String, dynamic>.from(antworten[3]);
        _sicherheit = Map<String, dynamic>.from(antworten[4]);
        _laedt = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _laedt = false;
        _fehler = 'Verbindung zum Server fehlgeschlagen: $e';
      });
    }
  }

  Future<void> _jetztPruefen() async {
    setState(() => _prueftGerade = true);
    try {
      final a = await _api.websiteAction({'action': 'pruefen'});
      if (!mounted) return;
      if (a['success'] == true) {
        setState(() => _sicherheit = Map<String, dynamic>.from(a));
        // Die Note oben in der Übersicht muss mitziehen, sonst stehen zwei
        // verschiedene Zahlen für dieselbe Sache auf demselben Bildschirm.
        final bericht = webKarte(a['bericht']);
        setState(() => _uebersicht = {
              ..._uebersicht,
              'sicherheit': {
                'note': bericht['note'],
                'geprueft': a['geprueft'],
              },
            });
      } else {
        _melden(a['message']?.toString() ?? 'Die Prüfung ist fehlgeschlagen.');
      }
    } catch (e) {
      if (mounted) _melden('Die Prüfung ist fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _prueftGerade = false);
    }
  }

  void _melden(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Website — icd360s.de'),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.date_range),
            tooltip: 'Zeitraum',
            initialValue: _tage,
            onSelected: (t) {
              setState(() => _tage = t);
              _laden();
            },
            itemBuilder: (_) => _zeitraeume.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Auftritt im Browser öffnen',
            onPressed: () => launchUrl(Uri.parse('https://icd360s.de/'),
                mode: LaunchMode.externalApplication),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu laden',
            onPressed: _laedt ? null : _laden,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.insights), text: 'Übersicht'),
            Tab(icon: Icon(Icons.people_outline), text: 'Besucher'),
            Tab(icon: Icon(Icons.article_outlined), text: 'Seiten'),
            Tab(icon: Icon(Icons.shield_outlined), text: 'Sicherheit'),
            Tab(icon: Icon(Icons.gpp_maybe_outlined), text: 'Angriffe'),
          ],
        ),
      ),
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : _fehler != null
              ? _fehlerFlaeche()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _tabUebersicht(),
                    _tabBesucher(),
                    _tabSeiten(),
                    _tabSicherheit(),
                    _tabAngriffe(),
                  ],
                ),
    );
  }

  Widget _fehlerFlaeche() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_fehler!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _laden,
                icon: const Icon(Icons.refresh),
                label: const Text('Noch einmal'),
              ),
            ],
          ),
        ),
      );

  // -------------------------------------------------------------------------
  // Bausteine
  // -------------------------------------------------------------------------

  Widget _karte({required String titel, String? unterzeile, required Widget kind,
      IconData? icon, Color? farbe}) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: farbe ?? Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(titel,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
            if (unterzeile != null) ...[
              const SizedBox(height: 4),
              Text(unterzeile,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 12),
            kind,
          ],
        ),
      ),
    );
  }

  /// Eine Zeile mit Balken. Der Balken ist relativ zum größten Wert der Liste,
  /// nicht zur Summe — bei einer Rangliste interessiert der Abstand zur Spitze.
  Widget _balken(String beschriftung, int wert, int hoechst,
      {String? zusatz, Color? farbe, String? flagge}) {
    final anteil = hoechst > 0 ? (wert / hoechst).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (flagge != null && flagge.isNotEmpty) ...[
                Text(flagge, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(beschriftung,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text(webTausend(wert),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: [])),
              if (zusatz != null) ...[
                const SizedBox(width: 6),
                Text(zusatz, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: anteil,
              minHeight: 6,
              backgroundColor: Colors.grey.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(
                  farbe ?? Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leer(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(text,
            style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
      );

  Widget _kennzahl(String zahl, String beschriftung, {Color? farbe, String? fussnote}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(zahl,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: farbe)),
        Text(beschriftung, style: const TextStyle(fontSize: 12)),
        if (fussnote != null)
          Text(fussnote, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Tab 1 — Übersicht
  // -------------------------------------------------------------------------

  Widget _tabUebersicht() {
    final verlauf = webListe(_uebersicht['verlauf']);
    final summe = webKarte(_uebersicht['summe']);
    final vergleich = webKarte(_uebersicht['vergleich']);
    final sicher = webKarte(_uebersicht['sicherheit']);
    final note = webKarte(sicher['note']);

    final aufrufe = webZahl(summe['aufrufe']);
    final vorher = webZahl(vergleich['aufrufe_vorher']);
    final trend = vorher > 0 ? ((aufrufe - vorher) / vorher * 100).round() : null;

    // Nur Tage zählen, die es im Zeitraum wirklich gibt — sonst behauptet der
    // Bildschirm bei fünf Tagen Daten einen Durchschnitt über dreißig.
    final rekonstruiert =
        verlauf.where((t) => '${t['quelle']}' != 'eigen').length;

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: 'Besuch im Zeitraum',
            unterzeile: 'letzte ${_zeitraeume[_tage] ?? '$_tage Tage'}'
                '${_uebersicht['daten_ab'] != null ? ' · Daten ab ${_datum(_uebersicht['daten_ab'])}' : ''}',
            icon: Icons.trending_up,
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 28,
                  runSpacing: 14,
                  children: [
                    _kennzahl(webTausend(aufrufe), 'Seitenaufrufe',
                        fussnote: trend == null
                            ? null
                            : '${trend >= 0 ? '+' : ''}$trend % zum Vorzeitraum'),
                    _kennzahl('${webKomma(_uebersicht['besucher_mittel'])}',
                        'Besucher je Tag',
                        fussnote: 'bester Tag: ${webZahl(_uebersicht['besucher_bester'])}'),
                    _kennzahl(webTausend(webZahl(summe['aufrufe_bot'])), 'davon Maschinen',
                        farbe: Colors.grey.shade600,
                        fussnote: 'Suchdienste, Vorschauen, Scanner'),
                    _kennzahl(webBytes(webZahl(summe['bytes'])), 'ausgeliefert'),
                  ],
                ),
                const SizedBox(height: 16),
                if (verlauf.isEmpty)
                  _leer('Für diesen Zeitraum liegen noch keine Zahlen vor.')
                else
                  _verlaufBalken(verlauf),
                const SizedBox(height: 10),
                Text(
                  '⚠️ Besucher lassen sich nicht über mehrere Tage zusammenzählen: '
                  'der Prüfwert, der sie unterscheidet, wird täglich neu gesalzen. '
                  'Deshalb steht hier der Schnitt je Tag und nicht eine Summe, die '
                  'jeden Wiederkehrer mehrfach zählte.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (rekonstruiert > 0)
            _karte(
              titel: 'Ein Teil der Tage ist rekonstruiert',
              icon: Icons.history_toggle_off,
              farbe: Colors.orange.shade700,
              kind: Text(
                '$rekonstruiert von ${verlauf.length} Tagen stammen aus dem '
                'gemeinsamen Protokoll der Zeit vor dem 15.08.2026. Dort fehlte die '
                'Angabe, welcher Name gemeint war, deshalb wurden nur eindeutig '
                'benannte Seiten gezählt.\n\n'
                '⚠️ Die Startseite fehlt in diesen Tagen. Sie mitzuzählen hätte '
                'geheißen, rund 450 tägliche Scanner-Anfragen auf die nackte '
                'Server-Adresse als Lesende auszuweisen — gemessen an Tagen, an '
                'denen der Auftritt dort noch gar nicht lag.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          _karte(
            titel: 'Sicherheit',
            unterzeile: sicher['geprueft'] != null
                ? 'zuletzt geprüft: ${_zeitpunkt(sicher['geprueft'])}'
                : 'noch nicht geprüft',
            icon: Icons.shield_outlined,
            farbe: _notenFarbe(note),
            kind: note.isEmpty
                ? _leer('Es liegt noch kein Befund vor.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _kennzahl('${webZahl(note['prozent'])} %',
                              '${note['stufe']}',
                              farbe: _notenFarbe(note)),
                          const SizedBox(width: 28),
                          _kennzahl('${webZahl(note['fehler'])}', 'Fehler',
                              farbe: webZahl(note['fehler']) > 0
                                  ? const Color(0xFFC62828)
                                  : null),
                          const SizedBox(width: 28),
                          _kennzahl('${webZahl(note['warnungen'])}', 'Hinweise',
                              farbe: webZahl(note['warnungen']) > 0
                                  ? const Color(0xFFEF6C00)
                                  : null),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('${webZahl(note['geprueft'])} Prüfungen',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _tabs.animateTo(3),
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('Zu den Einzelbefunden'),
                        ),
                      ),
                    ],
                  ),
          ),
          _karte(
            titel: 'Wie gezählt wird',
            icon: Icons.privacy_tip_outlined,
            kind: Text(
              '${_uebersicht['hinweis'] ?? ''}\n\n'
              'In der Datenbank steht keine IP-Adresse. An ihrer Stelle liegt ein '
              'Prüfwert aus Tagessalz, Adresse und Browserkennung; das Salz wird '
              'nach drei Tagen gelöscht. Danach ist der Wert auch mit der Datenbank '
              'in der Hand nicht mehr auf eine Person zurückzurechnen — die '
              'Tageszahl bleibt trotzdem richtig, weil sie zum Zeitpunkt der '
              'Zählung gebildet wurde.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Color? _notenFarbe(Map<String, dynamic> note) {
    if (note.isEmpty) return null;
    if (webZahl(note['fehler']) > 0) return const Color(0xFFC62828);
    final p = webZahl(note['prozent']);
    if (p >= 95) return const Color(0xFF2E7D32);
    if (p >= 85) return const Color(0xFF558B2F);
    return const Color(0xFFEF6C00);
  }

  Widget _verlaufBalken(List<Map<String, dynamic>> verlauf) {
    final hoechst = verlauf
        .map((t) => webZahl(t['aufrufe']))
        .fold<int>(1, (a, b) => a > b ? a : b);
    // Bei einem Jahr wären 365 Balken schmaler als ein Pixel — dann lieber
    // waagerecht scrollen als eine Fläche, die nichts mehr zeigt.
    return SizedBox(
      height: 130,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: verlauf.reversed.map((t) {
            final n = webZahl(t['aufrufe']);
            final bots = webZahl(t['aufrufe_bot']);
            final datum = '${t['datum']}';
            return Tooltip(
              message: '${_datum(datum)}\n$n Seitenaufrufe\n$bots Maschinen'
                  '\n${webZahl(t['besucher'])} Besucher',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('$n', style: const TextStyle(fontSize: 9)),
                    const SizedBox(height: 2),
                    Container(
                      width: 18,
                      height: (n / hoechst * 78).clamp(2.0, 78.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 26,
                      child: Text(
                        datum.length >= 10 ? datum.substring(8, 10) : '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text(
                        datum.length >= 7 ? datum.substring(5, 7) : '',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab 2 — Besucher
  // -------------------------------------------------------------------------

  Widget _tabBesucher() {
    final laender = webListe(_besucher['laender']);
    final netze = webListe(_besucher['netze']);
    final geraete = webListe(_besucher['geraete']);
    final sprachen = webListe(_besucher['sprachen']);
    final stunden = webListe(_besucher['stunden']);
    final technik = webListe(_besucher['technik']);

    const sprachNamen = {
      'de': 'Deutsch', 'en': 'Englisch', 'ro': 'Rumänisch',
      'ru': 'Russisch', 'uk': 'Ukrainisch',
    };
    const geraetNamen = {
      'handy': 'Handy', 'tablet': 'Tablet',
      'desktop': 'Rechner', 'unbekannt': 'unbekannt',
    };

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: 'Herkunft',
            unterzeile: 'Land laut lokaler IP-Datenbank (DB-IP Lite) — keine Abfrage nach außen',
            icon: Icons.public,
            kind: laender.isEmpty
                ? _leer('Noch keine Zugriffe mit zuordenbarem Land.')
                : Column(
                    children: laender.take(12).map((l) {
                      final hoechst = webZahl(laender.first['aufrufe']);
                      return _balken('${l['land']}', webZahl(l['aufrufe']), hoechst,
                          flagge: webFlagge('${l['land']}'),
                          zusatz: '${webZahl(l['besucher'])} Bes.');
                    }).toList(),
                  ),
          ),
          _karte(
            titel: 'Sprachfassung',
            unterzeile: 'welche der fünf Fassungen gelesen wird',
            icon: Icons.translate,
            kind: sprachen.isEmpty
                ? _leer('Noch keine Zugriffe.')
                : Column(
                    children: sprachen.map((s) {
                      final hoechst = webZahl(sprachen.first['aufrufe']);
                      final k = '${s['sprache']}';
                      return _balken(sprachNamen[k] ?? k, webZahl(s['aufrufe']), hoechst,
                          zusatz: '${webZahl(s['besucher'])} Bes.');
                    }).toList(),
                  ),
          ),
          _karte(
            titel: 'Geräte',
            unterzeile: 'aus der Browserkennung geschlossen — Tablets vor Handys geprüft, '
                'weil jedes Android-Tablet auch „android" meldet',
            icon: Icons.devices,
            kind: geraete.isEmpty
                ? _leer('Noch keine Zugriffe.')
                : Column(
                    children: geraete.map((g) {
                      final hoechst = webZahl(geraete.first['aufrufe']);
                      final k = '${g['geraet']}';
                      return _balken(geraetNamen[k] ?? k, webZahl(g['aufrufe']), hoechst);
                    }).toList(),
                  ),
          ),
          _karte(
            titel: 'Tageszeit',
            unterzeile: 'wann gelesen wird (Ortszeit des Servers)',
            icon: Icons.schedule,
            kind: stunden.isEmpty ? _leer('Noch keine Zugriffe.') : _stundenBild(stunden),
          ),
          _karte(
            titel: 'Netzbetreiber',
            unterzeile: 'trennt gewöhnliche Anschlüsse von Rechenzentren — '
                'letztere sind meist VPN oder Maschine',
            icon: Icons.router_outlined,
            kind: netze.isEmpty
                ? _leer('Noch keine Zugriffe mit zuordenbarem Netz.')
                : Column(
                    children: netze.take(12).map((n) {
                      final hoechst = webZahl(netze.first['aufrufe']);
                      return _balken('${n['netz']}', webZahl(n['aufrufe']), hoechst,
                          zusatz: '${webZahl(n['besucher'])} Bes.');
                    }).toList(),
                  ),
          ),
          _karte(
            titel: 'Technik der Verbindung',
            unterzeile: 'Verschlüsselung, Protokoll und Adressfamilie',
            icon: Icons.lock_outline,
            kind: technik.isEmpty
                ? _leer('Noch keine Zugriffe.')
                : Column(
                    children: technik.map((t) {
                      final hoechst = webZahl(technik.first['aufrufe']);
                      final beschriftung = [
                        '${t['tls']}'.isEmpty ? '—' : '${t['tls']}',
                        '${t['protokoll']}',
                        '${t['ip_art']}'.toUpperCase(),
                      ].join(' · ');
                      return _balken(beschriftung, webZahl(t['aufrufe']), hoechst);
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _stundenBild(List<Map<String, dynamic>> stunden) {
    // Der Server liefert nur Stunden, in denen etwas passiert ist. Die Lücken
    // müssen hier gefüllt werden, sonst rutschen die Balken zusammen und ein
    // stiller Vormittag sähe aus wie ein voller.
    final proStunde = List<int>.filled(24, 0);
    for (final s in stunden) {
      final h = webZahl(s['stunde']);
      if (h >= 0 && h < 24) proStunde[h] = webZahl(s['aufrufe']);
    }
    final hoechst = proStunde.fold<int>(1, (a, b) => a > b ? a : b);

    return Column(
      children: [
        SizedBox(
          height: 76,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(24, (h) {
              return Expanded(
                child: Tooltip(
                  message: '${h.toString().padLeft(2, '0')}:00 — ${proStunde[h]} Aufrufe',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: (proStunde[h] / hoechst * 68).clamp(2.0, 68.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: proStunde[h] == 0 ? 0.15 : 0.85),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final h in ['00', '06', '12', '18', '23'])
              Text(h, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Tab 3 — Seiten
  // -------------------------------------------------------------------------

  Widget _tabSeiten() {
    final seiten = webListe(_seiten['seiten']);
    final verweise = webListe(_seiten['verweise']);
    final fehlseiten = webListe(_seiten['fehlseiten']);
    final langsam = webListe(_seiten['langsam']);
    final bots = webListe(_seiten['bots']);

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: 'Meistgelesene Seiten',
            icon: Icons.article_outlined,
            kind: seiten.isEmpty
                ? _leer('Noch keine Seitenaufrufe im Zeitraum.')
                : Column(
                    children: seiten.take(20).map((s) {
                      final hoechst = webZahl(seiten.first['aufrufe']);
                      return _balken('${s['pfad']}', webZahl(s['aufrufe']), hoechst,
                          zusatz: '${webZahl(s['besucher'])} Bes.');
                    }).toList(),
                  ),
          ),
          _karte(
            titel: 'Woher die Leute kommen',
            unterzeile: 'nur der Name der verweisenden Seite — nie die volle Adresse, '
                'in der eine Suchanfrage stehen könnte',
            icon: Icons.link,
            kind: verweise.isEmpty
                ? _leer('Keine Verweise von außen. Alle Aufrufe kamen direkt — '
                    'über ein Lesezeichen, aus einer Nachricht oder getippt.')
                : Column(
                    children: verweise.map((v) {
                      final hoechst = webZahl(verweise.first['aufrufe']);
                      return _balken('${v['verweis']}', webZahl(v['aufrufe']), hoechst);
                    }).toList(),
                  ),
          ),
          _karte(
            titel: 'Nicht gefundene Seiten',
            unterzeile: 'ohne Angriffsmuster — was hier steht, sind meist eigene '
                'kaputte Verweise und damit Pflegefälle',
            icon: Icons.report_gmailerrorred,
            farbe: fehlseiten.isEmpty ? null : Colors.orange.shade700,
            kind: fehlseiten.isEmpty
                ? _leer('Kein Aufruf ins Leere. ')
                : Column(
                    children: fehlseiten.take(15).map((f) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.orange.withValues(alpha: 0.15),
                          child: Text('${f['status']}',
                              style: const TextStyle(fontSize: 11, color: Colors.orange)),
                        ),
                        title: Text('${f['pfad']}',
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text('${webZahl(f['treffer'])}× · zuletzt '
                            '${_zeitpunkt(f['zuletzt'])}',
                            style: const TextStyle(fontSize: 11)),
                      );
                    }).toList(),
                  ),
          ),
          _karte(
            titel: 'Langsamste Seiten',
            unterzeile: 'Antwortzeit des Servers, ohne Netz und ohne Browser',
            icon: Icons.hourglass_bottom,
            kind: langsam.isEmpty
                ? _leer('Noch zu wenige Messwerte. Für die rekonstruierten Tage gibt '
                    'es keine Zeiten — das alte Protokollformat hat sie nicht mitgeschrieben.')
                : Column(
                    children: langsam.map((l) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${l['pfad']}',
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${webZahl(l['aufrufe'])} Aufrufe · '
                            'Spitze ${webZahl(l['hoechst'])} ms',
                            style: const TextStyle(fontSize: 11)),
                        trailing: Text('${webZahl(l['mittel'])} ms',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    }).toList(),
                  ),
          ),
          _karte(
            titel: 'Maschinen',
            unterzeile: 'Suchdienste, Vorschaubilder in Messengern, KI-Sammler und Scanner. '
                'Sie zählen nirgends als Besucher.',
            icon: Icons.smart_toy_outlined,
            kind: bots.isEmpty
                ? _leer('Keine Maschine erkannt.')
                : Column(
                    children: bots.take(15).map((b) {
                      final hoechst = webZahl(bots.first['aufrufe']);
                      return _balken('${b['bot_name']}', webZahl(b['aufrufe']), hoechst,
                          farbe: Colors.blueGrey);
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab 4 — Sicherheit
  // -------------------------------------------------------------------------

  Widget _tabSicherheit() {
    final bericht = webKarte(_sicherheit['bericht']);
    final bloecke = webListe(bericht['bloecke']);
    final note = webKarte(bericht['note']);

    if (bloecke.isEmpty) {
      return ListView(children: [
        _karte(
          titel: 'Noch keine Prüfung',
          icon: Icons.shield_outlined,
          kind: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_sicherheit['meldung'] ?? 'Es liegt kein Befund vor.'}'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _prueftGerade ? null : _jetztPruefen,
                icon: _prueftGerade
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: const Text('Jetzt prüfen'),
              ),
            ],
          ),
        ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: 'Gesamtbefund',
            unterzeile: 'geprüft ${_zeitpunkt(_sicherheit['geprueft'])}'
                '${_sicherheit['frisch'] == true ? ' · soeben erhoben' : ''}',
            icon: Icons.verified_user_outlined,
            farbe: _notenFarbe(note),
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 28, runSpacing: 12, children: [
                  _kennzahl('${webZahl(note['prozent'])} %', '${note['stufe']}',
                      farbe: _notenFarbe(note)),
                  _kennzahl('${webZahl(note['fehler'])}', 'Fehler',
                      farbe: webZahl(note['fehler']) > 0 ? const Color(0xFFC62828) : null),
                  _kennzahl('${webZahl(note['warnungen'])}', 'Hinweise',
                      farbe: webZahl(note['warnungen']) > 0 ? const Color(0xFFEF6C00) : null),
                  _kennzahl('${webZahl(note['geprueft'])}', 'Prüfungen'),
                ]),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _prueftGerade ? null : _jetztPruefen,
                  icon: _prueftGerade
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(_prueftGerade ? 'wird geprüft …' : 'Jetzt neu prüfen'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gemessen wird der Auftritt von außen, nicht die Konfigurationsdatei. '
                  'Eine Kopfzeile, die dort steht, aber auf einer tieferen Ebene '
                  'verdrängt wird, fiele einer Dateiprüfung nicht auf.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          ...bloecke.map(_sicherheitsBlock),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sicherheitsBlock(Map<String, dynamic> block) {
    final pruefungen = webListe(block['pruefungen']);
    final fehler = pruefungen.where((p) => p['stand'] == 'fehler').length;
    final warnungen = pruefungen.where((p) => p['stand'] == 'warnung').length;
    final ok = pruefungen.where((p) => p['stand'] == 'ok').length;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: ExpansionTile(
        initiallyExpanded: fehler > 0,
        leading: Icon(
          fehler > 0
              ? Icons.cancel
              : warnungen > 0
                  ? Icons.error_outline
                  : Icons.check_circle,
          color: fehler > 0
              ? const Color(0xFFC62828)
              : warnungen > 0
                  ? const Color(0xFFEF6C00)
                  : const Color(0xFF2E7D32),
        ),
        title: Text('${block['titel']}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$ok in Ordnung'
            '${warnungen > 0 ? ' · $warnungen Hinweise' : ''}'
            '${fehler > 0 ? ' · $fehler Fehler' : ''}'
            '${block['stand'] != null ? ' · Stand ${_zeitpunkt(block['stand'])}' : ''}'),
        children: pruefungen.map(_pruefungsZeile).toList(),
      ),
    );
  }

  Widget _pruefungsZeile(Map<String, dynamic> p) {
    final s = webStand('${p['stand']}');
    final soll = '${p['soll'] ?? ''}';
    final hinweis = '${p['hinweis'] ?? ''}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(s.icon, size: 18, color: s.farbe),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['titel']}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text('${p['wert']}',
                    style: TextStyle(fontSize: 13, color: s.farbe)),
                if (soll.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(soll,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
                ],
                if (hinweis.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: s.farbe.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(6),
                      border: Border(left: BorderSide(color: s.farbe, width: 3)),
                    ),
                    child: Text(hinweis, style: const TextStyle(fontSize: 11.5)),
                  ),
                ],
                if (p['quelle'] == 'server')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('vom Server erhoben (braucht Systemrechte)',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab 5 — Angriffe
  // -------------------------------------------------------------------------

  Widget _tabAngriffe() {
    final muster = webListe(_angriffe['muster']);
    final herkunft = webListe(_angriffe['herkunft']);
    final verlauf = webListe(_angriffe['verlauf']);
    final erfolge = webListe(_angriffe['erfolge']);
    final gesamt = verlauf.fold<int>(0, (a, t) => a + webZahl(t['scans']));

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: erfolge.isEmpty ? 'Alle Versuche abgewiesen' : 'Es hat etwas geantwortet',
            unterzeile: '$gesamt Versuche im Zeitraum',
            icon: erfolge.isEmpty ? Icons.verified_user : Icons.gpp_bad,
            farbe: erfolge.isEmpty ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (erfolge.isEmpty)
                  Text(
                    'Kein Angriffspfad hat eine Antwort unter 400 bekommen. Das ist '
                    'der Zustand, der hier stehen soll.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  )
                else
                  ...erfolge.map((e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.warning, color: Color(0xFFC62828)),
                        title: Text('${e['pfad']}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text('HTTP ${e['status']} · ${webZahl(e['treffer'])}× · '
                            'zuletzt ${_zeitpunkt(e['zuletzt'])}',
                            style: const TextStyle(fontSize: 11)),
                      )),
                const SizedBox(height: 8),
                Text('${_angriffe['hinweis'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          _karte(
            titel: 'Wonach gesucht wird',
            unterzeile: 'Pfade, die es hier nie gab und die praktisch nur '
                'Angriffswerkzeuge abfragen',
            icon: Icons.travel_explore,
            kind: muster.isEmpty
                ? _leer('Im Zeitraum kein Versuch erfasst. Für die rekonstruierten Tage '
                    'ist das erwartbar: dort war nicht feststellbar, welcher Name gemeint '
                    'war, deshalb wurden Scans gar nicht erst gezählt.')
                : Column(
                    children: muster.take(20).map((m) {
                      final hoechst = webZahl(muster.first['versuche']);
                      return _balken('${m['pfad']}', webZahl(m['versuche']), hoechst,
                          farbe: Colors.red.shade400,
                          zusatz: '${webZahl(m['quellen'])} Quellen');
                    }).toList(),
                  ),
          ),
          _karte(
            titel: 'Woher',
            icon: Icons.travel_explore_outlined,
            kind: herkunft.isEmpty
                ? _leer('Keine Herkunft erfasst.')
                : Column(
                    children: herkunft.take(15).map((h) {
                      final hoechst = webZahl(herkunft.first['versuche']);
                      final land = '${h['land']}';
                      final netz = '${h['netz']}';
                      return _balken(netz.isEmpty ? (land.isEmpty ? '—' : land) : netz,
                          webZahl(h['versuche']), hoechst,
                          farbe: Colors.red.shade300, flagge: webFlagge(land));
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------

  String _datum(dynamic roh) {
    final s = '${roh ?? ''}';
    if (s.length < 10) return s;
    return '${s.substring(8, 10)}.${s.substring(5, 7)}.${s.substring(0, 4)}';
  }

  String _zeitpunkt(dynamic roh) {
    final s = '${roh ?? ''}';
    if (s.length < 16) return _datum(roh);
    return '${_datum(s)} ${s.substring(11, 16)}';
  }
}
