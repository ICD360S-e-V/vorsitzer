import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../utils/sprachen_options.dart';
import '../widgets/website_diagramme.dart';

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
/// „kontrast=hoch" → „Hoher Kontrast".
  ///
/// ⚠️ Der rohe Wert steht trotzdem als Zusatz daneben. Wer eine Einstellung
/// hier nicht wiederfindet, muss sehen können, wie sie in der Adresszeile
/// heißt — sonst ist nicht zu unterscheiden, ob sie niemand benutzt oder ob
/// nur die Übersetzung fehlt.
String webEinstellungName(String roh) {
  final teile = roh.split('=');
  if (teile.length != 2) return roh;
  final wert = switch (teile[1]) {
    'hoch' => 'hoch',
    'dunkel' => 'dunkel',
    'hell' => 'hell',
    'automatisch' => 'automatisch',
    'klein' => 'klein',
    'gross' => 'groß',
    'groesser' => 'noch größer',
    'weit' => 'weit',
    'weiter' => 'weiter',
    'stark' => 'stark',
    'aus' => 'aus',
    'normal' => 'normal',
    'serifenlos' => 'serifenlos',
    'leserlich' => 'leserlich',
    'dyslexie' => 'für Lese-Rechtschreib-Schwäche',
    final v => v,
  };
  return switch (teile[0]) {
    'thema' => 'Farbschema: $wert',
    'kontrast' => 'Kontrast: $wert',
    'schrift' => 'Schriftgröße: $wert',
    'schriftart' => 'Schriftart: $wert',
    'zeilen' => 'Zeilenabstand: $wert',
    'absatz' => 'Absatzabstand: $wert',
    'abstand' => 'Zeichenabstand: $wert',
    'fokus' => 'Fokusrahmen: $wert',
    'bewegung' => 'Bewegung: $wert',
    'sprache' => 'Sprache gewechselt zu ${teile[1].toUpperCase()}',
    _ => roh,
  };
}

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


/// Verteilt eine Liste `[{schluessel: …, wert: …}]` auf feste Fächer.
/// Der Server liefert nur Klassen, in denen etwas passiert ist — wer die
/// Lücken nicht füllt, zeichnet einen stillen Vormittag als vollen.
List<int> webFaecher(List<Map<String, dynamic>> zeilen, String schluessel,
    String wertFeld, int anzahl,
    {int versatz = 0}) {
  final faecher = List<int>.filled(anzahl, 0);
  for (final z in zeilen) {
    final i = webZahl(z[schluessel]) - versatz;
    if (i >= 0 && i < anzahl) faecher[i] = webZahl(z[wertFeld]);
  }
  return faecher;
}

class _WebsiteScreenState extends State<WebsiteScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 7, vsync: this);
  final _api = ApiService();

  int _tage = 30;
  bool _laedt = true;
  String? _fehler;

  /// Eigenes Zeitfenster für den Reiter „Besucher", in Stunden. Der Reiter
  /// soll von „letzte Stunde" bis „ein Jahr" reichen; die Tagesauflösung der
  /// übrigen Reiter genügt dafür nicht.
  int _besucherFenster = 720;
  bool _besucherLaedt = false;

  static const _besucherFenstern = <int, String>{
    1: '1 Std.',
    6: '6 Std.',
    12: '12 Std.',
    24: '1 Tag',
    168: '1 Woche',
    720: '1 Monat',
    8760: '1 Jahr',
  };

  Map<String, dynamic> _uebersicht = const {};
  Map<String, dynamic> _besucher = const {};
  Map<String, dynamic> _seiten = const {};
  Map<String, dynamic> _angriffe = const {};
  Map<String, dynamic> _sicherheit = const {};
  Map<String, dynamic> _tiefe = const {};
  Map<String, dynamic> _seo = const {};
  Map<String, dynamic> _sprachen = const {};
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
      // Nebeneinander statt nacheinander: die Abfragen hängen nicht
      // voneinander ab, und über eine Mobilverbindung ist der Unterschied
      // zwischen fünfmal 400 ms und einmal 400 ms deutlich zu sehen.
      final antworten = await Future.wait([
        _api.websiteAction({'action': 'uebersicht', 'tage': _tage}),
        _api.websiteAction(
            {'action': 'besucher', 'fenster_stunden': _besucherFenster}),
        _api.websiteAction({'action': 'seiten', 'tage': _tage}),
        _api.websiteAction({'action': 'angriffe', 'tage': _tage}),
        _api.websiteAction({'action': 'sicherheit'}),
        _api.websiteAction({'action': 'tiefe'}),
        _api.websiteAction({'action': 'seo'}),
        _api.websiteAction({'action': 'sprachen'}),
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
        _tiefe = Map<String, dynamic>.from(antworten[5]);
        _seo = Map<String, dynamic>.from(antworten[6]);
        _sprachen = Map<String, dynamic>.from(antworten[7]);
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

  /// Nur den Reiter „Besucher" nachladen — beim Wechsel des Zeitfensters
  /// wären vier weitere Abfragen umsonst.
  Future<void> _besucherLaden(int fenster) async {
    setState(() {
      _besucherFenster = fenster;
      _besucherLaedt = true;
    });
    try {
      final a = await _api
          .websiteAction({'action': 'besucher', 'fenster_stunden': fenster});
      if (!mounted) return;
      if (a['success'] == true) {
        setState(() => _besucher = Map<String, dynamic>.from(a));
      } else {
        _melden(a['message']?.toString() ?? 'Die Zahlen kamen nicht an.');
      }
    } catch (e) {
      if (mounted) _melden('Die Zahlen kamen nicht an: $e');
    } finally {
      if (mounted) setState(() => _besucherLaedt = false);
    }
  }

  Future<void> _jetztPruefen() async {
    setState(() => _prueftGerade = true);
    try {
      final a = await _api.websiteAction({'action': 'pruefen'});
      if (!mounted) return;
      if (a['success'] == true) {
        final bericht = webKarte(a['bericht']);
        setState(() {
          _sicherheit = Map<String, dynamic>.from(a);
          // Die Note oben in der Übersicht muss mitziehen, sonst stehen zwei
          // verschiedene Zahlen für dieselbe Sache auf demselben Bildschirm.
          _uebersicht = {
            ..._uebersicht,
            'sicherheit': {'note': bericht['note'], 'geprueft': a['geprueft']},
          };
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
            Tab(icon: Icon(Icons.speed_outlined), text: 'SEO'),
            Tab(icon: Icon(Icons.translate), text: 'Übersetzung'),
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
                    _tabSeo(),
                    _tabUebersetzung(),
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
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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

  /// Zwei Zahlen in einem Balken: Menschen und Maschinen nebeneinander.
  /// Ohne die Gegenzahl sieht eine Seite mit fünf Lesern und neunhundert
  /// Crawlern genauso aus wie eine mit fünf Lesern.
  Widget _balkenGeteilt(String beschriftung, int mensch, int maschine, int hoechst,
      {String? zusatz}) {
    final gesamt = mensch + maschine;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(beschriftung,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text('$mensch',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: kWebMensch)),
              Text(' / $maschine',
                  style: const TextStyle(fontSize: 12, color: kWebMaschine)),
              if (zusatz != null) ...[
                const SizedBox(width: 6),
                Text(zusatz, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (mensch > 0)
                    Expanded(flex: mensch, child: Container(color: kWebMensch)),
                  if (maschine > 0)
                    Expanded(flex: maschine, child: Container(color: kWebMaschine)),
                  if (gesamt < hoechst)
                    Expanded(
                      flex: hoechst - gesamt,
                      child: Container(color: Colors.grey.withValues(alpha: 0.14)),
                    ),
                ],
              ),
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


  static String _absichtName(String gruppe) => switch (gruppe) {
        'suchmaschine' => 'Suchdienste — bringen Leser',
        'ki' => 'KI-Sammler — nehmen Inhalte mit',
        'messung' => 'Mess- und Sicherheitsprojekte',
        'werkzeug' => 'Werkzeuge ohne erkennbare Absicht',
        _ => gruppe,
      };

  /// Der Satz unter „Maschinen nach Absicht" — er entsteht aus den Zahlen,
  /// statt fest im Text zu stehen.
  ///
  /// ⚠️ Für einen Verein ist das die eigentliche Auskunft: wenn die
  /// KI-Sammler häufiger vorbeikommen als die Suchdienste, wird der Auftritt
  /// eingesammelt, aber kaum indexiert — und indexiert werden ist das, was
  /// Mitglieder bringt.
  static String _absichtHinweis(List<Map<String, dynamic>> gruppen) {
    int hol(String g) => gruppen
        .where((e) => '${e['gruppe']}' == g)
        .map((e) => webZahl(e['aufrufe']))
        .fold(0, (a, b) => a + b);
    final ki = hol('ki');
    final such = hol('suchmaschine');
    if (such == 0 && ki == 0) return '';
    if (such == 0) {
      return '⚠️ Kein einziger Suchdienst im Zeitraum, aber $ki Abrufe durch '
          'KI-Sammler. Der Auftritt wird eingesammelt, aber nicht indexiert.';
    }
    if (ki > such) {
      return '⚠️ KI-Sammler kommen ${(ki / such).round()}-mal so oft wie '
          'Suchdienste ($ki gegen $such). Eingesammelt wird der Auftritt also '
          'gründlicher als indexiert — und indexiert werden ist das, was Leser '
          'bringt.';
    }
    return '';
  }

  /// Eine Zeile in „Was hier nicht steht, und warum".
  ///
  /// ⚠️ Diese Karte ist Absicht, nicht Verlegenheit. Wer eine Auswertung
  /// kennt, sucht als Erstes nach wiederkehrenden Besuchern — findet nichts
  /// und hält es für eine Lücke. Es ist aber die Entscheidung, die den
  /// Auftritt ohne Einwilligungsbanner auskommen lässt, und die gehört
  /// hingeschrieben statt verschwiegen.
  Widget _fehltZeile(String was, String warum) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(was,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(warum,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ),
          ],
        ),
      );

  /// Richtung gegenüber dem gleich langen Zeitraum davor.
  ///
  /// ⚠️ Gibt `null` zurück, wenn es keinen Vorzeitraum gibt — und das ist der
  /// Regelfall, solange die Aufzeichnung jünger ist als das gewählte Fenster.
  /// „±0 %" hinzuschreiben wäre eine Aussage über Tage, an denen gar nicht
  /// gezählt wurde. Der Aufrufer setzt dann seine eigene Fußnote oder keine.
  String? _gegenVorzeitraum(int jetzt, int vorher) {
    if (vorher <= 0) return null;
    final p = ((jetzt - vorher) / vorher * 100).round();
    return '${p >= 0 ? '+' : ''}$p % zum Vorzeitraum';
  }

  Widget _kennzahl(String zahl, String beschriftung, {Color? farbe, String? fussnote}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(zahl,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: farbe)),
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
    final zusammen = webListe(_uebersicht['zusammensetzung']);
    final antwortzeit = webKarte(_uebersicht['antwortzeit']);

    final aufrufe = webZahl(summe['aufrufe']);
    final vorher = webZahl(vergleich['aufrufe_vorher']);
    final trend = vorher > 0 ? ((aufrufe - vorher) / vorher * 100).round() : null;
    final rekonstruiert = verlauf.where((t) => '${t['quelle']}' != 'eigen').length;

    final tiefe = webKarte(_uebersicht['tiefe']);
    final dauer = webKarte(_uebersicht['dauer']);
    final ausstieg = webListe(_uebersicht['ausstieg']);
    final ziele = webListe(_uebersicht['ziele']);
    final trichter = webListe(_uebersicht['trichter']);
    final verweise = webListe(_uebersicht['verweise']);
    final zieleGrundlage = webZahl(_uebersicht['ziele_grundlage']);
    final direkt = webZahl(_uebersicht['verweise_direkt']);

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: 'Besuch im Zeitraum',
            unterzeile: 'letzte ${_zeitraeume[_tage] ?? '$_tage Tage'}'
                '${_uebersicht['daten_ab'] != null ? ' · Daten ab ${_datum(_uebersicht['daten_ab'])}' : ''}'
                '${_uebersicht['stand'] != null ? ' · Stand ${_zeitpunkt(_uebersicht['stand'])}' : ''}',
            icon: Icons.trending_up,
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 28,
                  runSpacing: 14,
                  children: [
                    _kennzahl(webTausend(aufrufe), 'Seitenaufrufe',
                        farbe: kWebMensch,
                        fussnote: trend == null
                            ? null
                            : '${trend >= 0 ? '+' : ''}$trend % zum Vorzeitraum'),
                    _kennzahl('${webKomma(_uebersicht['besucher_mittel'])}',
                        'Besucher je Tag',
                        fussnote: 'bester Tag: ${webZahl(_uebersicht['besucher_bester'])}'),
                    _kennzahl(webTausend(webZahl(summe['aufrufe_bot'])), 'Maschinen',
                        farbe: kWebMaschine,
                        fussnote: _gegenVorzeitraum(webZahl(summe['aufrufe_bot']),
                                webZahl(vergleich['bot_vorher'])) ??
                            'Suchdienste, Vorschauen'),
                    _kennzahl(webTausend(webZahl(summe['scans'])), 'Angriffsversuche',
                        farbe: webZahl(summe['scans']) > 0 ? kWebScan : null,
                        fussnote: _gegenVorzeitraum(webZahl(summe['scans']),
                            webZahl(vergleich['scans_vorher']))),
                    _kennzahl(webBytes(webZahl(summe['bytes'])), 'ausgeliefert',
                        fussnote: _gegenVorzeitraum(webZahl(summe['bytes']),
                            webZahl(vergleich['bytes_vorher']))),
                  ],
                ),
                const SizedBox(height: 18),
                if (verlauf.isEmpty)
                  _leer('Für diesen Zeitraum liegen noch keine Zahlen vor.')
                else
                  WebSaeulen(
                    reihenNamen: const ['Menschen', 'Maschinen', 'Angriffe'],
                    farben: const [kWebMensch, kWebMaschine, kWebScan],
                    punkte: [
                      for (final t in verlauf)
                        WebPunkt(
                          '${t['datum']}'.length >= 10
                              ? '${t['datum']}'.substring(8, 10)
                              : '',
                          [
                            webZahl(t['aufrufe']),
                            webZahl(t['aufrufe_bot']),
                            webZahl(t['scans']),
                          ],
                          unterBeschriftung: '${t['datum']}'.length >= 7
                              ? '${t['datum']}'.substring(5, 7)
                              : null,
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (webZahl(tiefe['besuche']) > 0)
            _karte(
              titel: 'Wie sie sich bewegen',
              unterzeile: 'Ein Besuch ist ein Mensch an einem Tag — über Tage '
                  'hinweg werden Besucher nicht verkettet.',
              icon: Icons.route_outlined,
              kind: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 28, runSpacing: 12, children: [
                    _kennzahl(webTausend(webZahl(tiefe['besuche'])), 'Besuche',
                        farbe: kWebMensch),
                    _kennzahl('${webKomma(tiefe['je_besuch'])}', 'Seiten je Besuch'),
                    _kennzahl(
                        webProzent(webZahl(tiefe['nur_eine']), webZahl(tiefe['besuche'])),
                        'nur eine Seite',
                        fussnote: '${webZahl(tiefe['nur_eine'])} von '
                            '${webZahl(tiefe['besuche'])}'),
                    _kennzahl('${webZahl(dauer['median_s'])} s', 'Verweildauer',
                        fussnote: 'Mittelwert der Mitte, aus '
                            '${webZahl(dauer['besuche'])} Besuchen'),
                    _kennzahl('${webZahl(tiefe['tiefster'])}', 'tiefster Besuch',
                        farbe: webZahl(tiefe['tiefster']) > 50 ? kWebMaschine : null),
                  ]),
                  const SizedBox(height: 10),
                  if (webZahl(tiefe['tiefster']) > 50)
                    Text(
                      '⚠️ Ein Besuch mit ${webZahl(tiefe['tiefster'])} Seiten bei '
                      '${webZahl(dauer['median_s'])} Sekunden Verweildauer ist kein '
                      'Mensch. Die Trennung nach Kennung erwischt Maschinen nicht, '
                      'die sich als Browser ausgeben — die Zahl „Menschen" oben ist '
                      'deshalb eher zu hoch als zu niedrig. Welche Netze dahinter '
                      'stecken, steht im Reiter „Besucher".',
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Die Verweildauer zählt nur Besuche mit mindestens zwei Seiten: '
                    'für eine einzelne Seite steht im Protokoll genau ein '
                    'Zeitstempel und kein Ende. Dieselbe Grenze haben auch Plausible '
                    'und Matomo — hier steht wenigstens daneben, worüber gerechnet '
                    'wurde.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          _karte(
            titel: 'Wer da war',
            unterzeile: 'Ein Zähler, der Crawler mitzählt, meldet vierhundert '
                'Besucher, von denen dreihundertachtzig keine sind.',
            icon: Icons.groups_outlined,
            kind: WebRing(
              mitte: webTausend(webZahl(summe['aufrufe'])),
              mitteUnten: 'Aufrufe\nvon Menschen',
              teile: [
                for (final z in zusammen)
                  (
                    name: webArtName('${z['art']}'),
                    wert: webZahl(z['aufrufe']),
                    farbe: webArtFarbe('${z['art']}')
                  ),
              ],
            ),
          ),
          if (webListe(_uebersicht['top_seiten']).isNotEmpty)
            _karte(
              titel: 'Meistgelesen',
              icon: Icons.article_outlined,
              kind: Column(
                children: [
                  for (final s in webListe(_uebersicht['top_seiten']))
                    _balken('${s['pfad']}', webZahl(s['aufrufe']),
                        webZahl(webListe(_uebersicht['top_seiten']).first['aufrufe']),
                        farbe: kWebMensch),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _tabs.animateTo(2),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Alle Seiten'),
                    ),
                  ),
                ],
              ),
            ),
          if (ausstieg.isNotEmpty)
            _karte(
              titel: 'Wo sie aufhören',
              unterzeile: 'Die letzte Seite eines Besuchs. Das Gegenstück zu den '
                  'Einstiegsseiten — und es sagt etwas anderes als die Rangliste '
                  'der meistgelesenen.',
              icon: Icons.logout_outlined,
              kind: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final a in ausstieg)
                    _balken(
                      '${a['pfad']}',
                      webZahl(a['besuche']),
                      webZahl(ausstieg.first['besuche']),
                      farbe: kWebMensch,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Ein hoher Wert ist nicht von sich aus schlecht: beim '
                    'Impressum oder bei der Satzung ist die Frage nach dem Lesen '
                    'beantwortet. Bei einer Seite, die weiterführen soll — '
                    'Mitglied werden, Spenden — ist er ein Hinweis.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          if (ziele.isNotEmpty)
            _karte(
              titel: 'Wonach sie kommen',
              unterzeile: 'Die Seiten, deren Aufruf dem Verein etwas bedeutet — '
                  'über alle Sprachfassungen zusammengezählt.',
              icon: Icons.flag_outlined,
              kind: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final z in ziele)
                    _balken(
                      '${z['name']}',
                      webZahl(z['aufrufe']),
                      ziele.map((e) => webZahl(e['aufrufe'])).fold(0, math.max),
                      zusatz: '${webKomma(z['anteil'])} % · ${z['pfad']}',
                      farbe: kWebMensch,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Anteil an $zieleGrundlage menschlichen Aufrufen im Zeitraum.\n\n'
                    '⚠️ Gezählt werden Aufrufe, nicht Personen. Besucher werden je '
                    'Tag neu gesalzen unterschieden — über mehrere Tage lassen sie '
                    'sich nicht zusammenfassen, und ein Prozentsatz „so viele '
                    'Besucher" wäre über einen Monat schlicht falsch.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          if (trichter.isNotEmpty)
            _karte(
              titel: 'Der Weg zum Antrag',
              unterzeile: 'Sechs Schritte. Wo abgebrochen wird, sieht man in '
                  'keiner Gesamtzahl.',
              icon: Icons.assignment_outlined,
              farbe: webZahl(trichter.first['aufrufe']) > 0 &&
                      webZahl(trichter.last['aufrufe']) == 0
                  ? Colors.orange.shade700
                  : null,
              kind: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in trichter)
                    _balken(
                      '${s['stufe']}. ${s['name']}',
                      webZahl(s['aufrufe']),
                      webZahl(trichter.first['aufrufe']),
                      zusatz: '${s['pfad']}',
                      farbe: webZahl(s['aufrufe']) > 0 ? kWebMensch : Colors.grey,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    webZahl(trichter.first['aufrufe']) > 0 &&
                            webZahl(trichter.last['aufrufe']) == 0
                        ? '⚠️ Der erste Schritt wird aufgerufen, der letzte nie. '
                            'Entweder bricht jeder ab, oder der Weg trägt nicht. '
                            'Der Auftritt hatte schon einmal einen Fehler, der '
                            'Anträge auf Schritt 1 zurückwarf — sichtbar war das '
                            'nirgends.\n\n'
                        : '',
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                  ),
                  Text(
                    'Die Schritte sind nicht dieselbe Person: über Tage hinweg '
                    'werden Besucher nicht verkettet, und das ist so gewollt. '
                    'Was hier steht, ist ein Verhältnis von Aufrufen — keine '
                    'Verfolgung eines Einzelnen.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          if (verweise.isNotEmpty)
            _karte(
              titel: 'Wer uns verlinkt',
              unterzeile: zieleGrundlage > 0
                  ? '${(direkt * 100 / zieleGrundlage).round()} % kommen ohne '
                      'Verweis — also über Lesezeichen, Eingabe oder Suchdienst.'
                  : null,
              icon: Icons.link_outlined,
              kind: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final v in verweise)
                    _balken(
                      '${v['woher']}',
                      webZahl(v['aufrufe']),
                      verweise.map((e) => webZahl(e['aufrufe'])).fold(0, math.max),
                      farbe: '${v['woher']}' == '(direkt)'
                          ? Colors.grey
                          : kWebMensch,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Für einen Verein, dessen Schwierigkeit das Gefundenwerden '
                    'ist, ist das die eigentliche Wachstumszahl. Ein Auftritt, den '
                    'niemand verlinkt, gilt auch keinem Suchdienst als wichtig.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(child: _anteilKarte('Sprachfassung', Icons.translate,
                  webListe(_uebersicht['sprachen']), 'sprache', _sprachName)),
              Expanded(child: _anteilKarte('Geräte', Icons.devices,
                  webListe(_uebersicht['geraete']), 'geraet', _geraetName)),
            ],
          ),
          if (webListe(_uebersicht['laender']).isNotEmpty)
            _karte(
              titel: 'Herkunft',
              icon: Icons.public,
              kind: Column(
                children: [
                  for (final l in webListe(_uebersicht['laender']))
                    _balken('${l['land']}', webZahl(l['aufrufe']),
                        webZahl(webListe(_uebersicht['laender']).first['aufrufe']),
                        flagge: webFlagge('${l['land']}'), farbe: kWebMensch),
                ],
              ),
            ),
          _karte(
            titel: 'Wie schnell der Server antwortet',
            unterzeile: 'Die einzige Zahl hier, die etwas über UNSERE Leistung sagt '
                'und nicht über die der Besucher. Ohne Netzweg gemessen.',
            icon: Icons.timer_outlined,
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 28, runSpacing: 12, children: [
                  // p50 zuerst: der Mittelwert verdeckt den Schwanz, die Spitze
                  // ist ein Einzelfall. Die Hälfte aller Aufrufe liegt darunter.
                  _kennzahl('${webZahl(antwortzeit['p50'])} ms', 'Hälfte darunter',
                      farbe: webZahl(antwortzeit['p50']) < 200 ? kWebMensch : null),
                  _kennzahl('${webZahl(antwortzeit['p95'])} ms', '95 % darunter',
                      farbe: webZahl(antwortzeit['p95']) < 500 ? kWebMensch : null),
                  _kennzahl('${webZahl(antwortzeit['hoechst'])} ms', 'Spitze'),
                  _kennzahl('${webZahl(antwortzeit['ueber_1s'])}', 'über 1 Sekunde',
                      farbe:
                          webZahl(antwortzeit['ueber_1s']) > 0 ? Colors.orange : null),
                  _kennzahl(webTausend(webZahl(summe['fehler_4xx'])), 'Fehler 4xx'),
                  _kennzahl(webTausend(webZahl(summe['fehler_5xx'])), 'Fehler 5xx',
                      farbe: webZahl(summe['fehler_5xx']) > 0 ? kWebScan : null),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Aus ${webTausend(webZahl(antwortzeit['gemessen']))} gemessenen '
                  'Aufrufen. ⚠️ Die aus dem alten gemeinsamen Protokoll '
                  'rekonstruierten Tage tragen keine Dauer und zählen hier nicht '
                  'mit — als „0 ms" gerechnet ergäben sie einen Median von null, '
                  'der nichts misst.',
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
                      Wrap(spacing: 28, runSpacing: 12, children: [
                        _kennzahl('${webZahl(note['prozent'])} %', '${note['stufe']}',
                            farbe: _notenFarbe(note)),
                        _kennzahl('${webZahl(note['fehler'])}', 'Fehler',
                            farbe: webZahl(note['fehler']) > 0 ? kWebScan : null),
                        _kennzahl('${webZahl(note['warnungen'])}', 'Hinweise',
                            farbe: webZahl(note['warnungen']) > 0
                                ? const Color(0xFFEF6C00)
                                : null),
                        _kennzahl('${webZahl(note['geprueft'])}', 'Prüfungen'),
                      ]),
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

  Widget _anteilKarte(String titel, IconData icon, List<Map<String, dynamic>> zeilen,
      String feld, String Function(String) name) {
    return _karte(
      titel: titel,
      icon: icon,
      kind: zeilen.isEmpty
          ? _leer('Noch nichts.')
          : WebAnteilsBalken(
              teile: [
                for (var i = 0; i < zeilen.length; i++)
                  (
                    name: name('${zeilen[i][feld]}'),
                    wert: webZahl(zeilen[i]['aufrufe']),
                    farbe: _palette[i % _palette.length],
                  ),
              ],
            ),
    );
  }

  static const _palette = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFFEF6C00),
    Color(0xFF6A1B9A), Color(0xFF00838F), Color(0xFFAD1457),
  ];

  static String _sprachName(String k) => const {
        'de': 'Deutsch', 'en': 'Englisch', 'ro': 'Rumänisch',
        'ru': 'Russisch', 'uk': 'Ukrainisch',
      }[k] ?? k;

  static String _geraetName(String k) => const {
        'handy': 'Handy', 'tablet': 'Tablet',
        'desktop': 'Rechner', 'unbekannt': 'unbekannt',
      }[k] ?? k;

  Color? _notenFarbe(Map<String, dynamic> note) {
    if (note.isEmpty) return null;
    if (webZahl(note['fehler']) > 0) return kWebScan;
    final p = webZahl(note['prozent']);
    if (p >= 95) return kWebMensch;
    if (p >= 85) return const Color(0xFF558B2F);
    return const Color(0xFFEF6C00);
  }

  // -------------------------------------------------------------------------
  // Tab 2 — Besucher
  // -------------------------------------------------------------------------

  Widget _tabBesucher() {
    final summe = webKarte(_besucher['summe']);
    final tiefe = webKarte(_besucher['tiefe']);
    final verlauf = webListe(_besucher['verlauf']);
    final exakt = _besucher['besucher_exakt'] == true;
    final klasse = webZahl(_besucher['klasse_sekunden']);

    return RefreshIndicator(
      onRefresh: () => _besucherLaden(_besucherFenster),
      child: ListView(
        children: [
          // --- Zeitfenster ---------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _besucherFenstern.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _besucherFenster == e.key,
                    onSelected: _besucherLaedt
                        ? null
                        : (an) {
                            if (an) _besucherLaden(e.key);
                          },
                  ),
                if (_besucherLaedt)
                  const Padding(
                    padding: EdgeInsets.only(left: 6, top: 8),
                    child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
          ),
          _karte(
            titel: 'Im gewählten Zeitfenster',
            unterzeile: 'seit ${_zeitpunkt(_besucher['von'])}'
                '${_besucher['stand'] != null ? ' · zuletzt eingelesen ${_zeitpunkt(_besucher['stand'])}' : ''}',
            icon: Icons.query_stats,
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 28, runSpacing: 14, children: [
                  _kennzahl(webTausend(webZahl(summe['aufrufe'])), 'Seitenaufrufe',
                      farbe: kWebMensch),
                  _kennzahl(webTausend(webZahl(summe['besucher'])),
                      exakt ? 'Besucher' : 'Besuchertage',
                      fussnote: exakt ? 'im Fenster eindeutig' : 'Wiederkehrer mehrfach'),
                  _kennzahl('${webKomma(tiefe['je_besuch'])}', 'Seiten je Besuch',
                      fussnote: 'tiefster: ${webZahl(tiefe['tiefster'])}'),
                  _kennzahl(
                      webZahl(tiefe['besuche']) > 0
                          ? '${(webZahl(tiefe['nur_eine']) / webZahl(tiefe['besuche']) * 100).round()} %'
                          : '—',
                      'nur eine Seite',
                      fussnote: '${webZahl(tiefe['nur_eine'])} von ${webZahl(tiefe['besuche'])}'),
                  _kennzahl(webTausend(webZahl(summe['maschinen'])), 'Maschinen',
                      farbe: kWebMaschine),
                ]),
                if (!exakt) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: const Border(
                          left: BorderSide(color: Color(0xFFEF6C00), width: 3)),
                    ),
                    child: const Text(
                      '⚠️ Das Fenster reicht über mehr als einen Kalendertag. Der '
                      'Prüfwert, der Besucher unterscheidet, wird täglich neu '
                      'gesalzen — genau damit er sich nicht über Tage verketten '
                      'lässt. Wer an drei Tagen kommt, erscheint deshalb als drei. '
                      'Die Zahl heißt hier bewusst „Besuchertage".',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _karte(
            titel: 'Verlauf',
            unterzeile: _klassenName(klasse),
            icon: Icons.show_chart,
            kind: verlauf.isEmpty
                ? _leer('Im gewählten Fenster wurde nichts aufgezeichnet.')
                : WebSaeulen(
                    reihenNamen: const ['Menschen', 'Maschinen'],
                    farben: const [kWebMensch, kWebMaschine],
                    punkte: [
                      for (final v in verlauf)
                        WebPunkt(
                          _klassenBeschriftung('${v['klasse']}', klasse),
                          [
                            webZahl(v['aufrufe']) - webZahl(v['maschinen']),
                            webZahl(v['maschinen']),
                          ],
                        ),
                    ],
                  ),
          ),
          _karte(
            titel: 'Menschen und Maschinen',
            icon: Icons.groups_outlined,
            kind: WebAnteilsBalken(
              teile: [
                for (final z in webListe(_besucher['zusammensetzung']))
                  (
                    name: webArtName('${z['art']}'),
                    wert: webZahl(z['aufrufe']),
                    farbe: webArtFarbe('${z['art']}')
                  ),
              ],
            ),
          ),
          _listenKarte('Herkunft', Icons.public, webListe(_besucher['laender']),
              'land', 'aufrufe',
              unterzeile: 'Land aus der lokalen IP-Datenbank (DB-IP Lite) — '
                  'keine Abfrage nach außen',
              flaggeAus: 'land', zusatzFeld: 'besucher', zusatzName: 'Bes.'),
          _listenKarte('Sprachfassung', Icons.translate,
              webListe(_besucher['sprachen']), 'sprache', 'aufrufe',
              beschriften: _sprachName, zusatzFeld: 'besucher', zusatzName: 'Bes.'),
          _listenKarte('Geräte', Icons.devices, webListe(_besucher['geraete']),
              'geraet', 'aufrufe',
              unterzeile: 'aus der Browserkennung geschlossen — Tablets vor Handys '
                  'geprüft, weil jedes Android-Tablet auch „android" meldet',
              beschriften: _geraetName),
          if (webListe(_besucher['wege']).isNotEmpty)
            _karte(
              titel: 'Häufigste Wege',
              unterzeile: 'Von welcher Seite auf welche. Die einzige Auswertung '
                  'hier, die Wege zeigt statt Ranglisten — „meistgelesen" sagt, '
                  'was gelesen wird, aber nicht, was danach kommt.',
              icon: Icons.alt_route_outlined,
              kind: Column(
                children: [
                  for (final w in webListe(_besucher['wege']))
                    _balken(
                      '${w['vorher']}  →  ${w['pfad']}',
                      webZahl(w['n']),
                      webZahl(webListe(_besucher['wege']).first['n']),
                      farbe: kWebMensch,
                    ),
                ],
              ),
            ),
          if (webListe(_besucher['tiefe_klassen']).isNotEmpty)
            _karte(
              titel: 'Wie viele Seiten je Besuch',
              unterzeile: 'Der Schnitt verdeckt die Form: bei gut vier Seiten im '
                  'Mittel kann trotzdem die Hälfte aller Besuche eine einzige '
                  'gesehen haben. Die Verteilung sagt es, der Schnitt nicht.',
              icon: Icons.bar_chart_outlined,
              kind: Column(
                children: [
                  for (final k in webListe(_besucher['tiefe_klassen']))
                    _balken(
                      '${k['klasse']}',
                      webZahl(k['besuche']),
                      webListe(_besucher['tiefe_klassen'])
                          .map((e) => webZahl(e['besuche']))
                          .fold(0, math.max),
                      farbe: kWebMensch,
                    ),
                ],
              ),
            ),
          if (webListe(_besucher['dauer_klassen']).isNotEmpty)
            _karte(
              titel: 'Wie lange sie bleiben',
              unterzeile: 'Nur Besuche mit mindestens zwei Seiten — für eine '
                  'einzelne steht im Protokoll ein Zeitstempel und kein Ende.',
              icon: Icons.hourglass_bottom_outlined,
              kind: Column(
                children: [
                  for (final k in webListe(_besucher['dauer_klassen']))
                    _balken(
                      '${k['klasse']}',
                      webZahl(k['besuche']),
                      webListe(_besucher['dauer_klassen'])
                          .map((e) => webZahl(e['besuche']))
                          .fold(0, math.max),
                      farbe: kWebMensch,
                    ),
                ],
              ),
            ),
          _listenKarte('Einstiegsseiten', Icons.login,
              webListe(_besucher['einstieg']), 'pfad', 'besuche',
              unterzeile: 'die erste Seite eines Besuchs — wo die Leute ankommen, '
                  'nicht wo sie enden'),
          if (_besucher['rhythmus_sinnvoll'] == true)
            _karte(
              titel: 'Tageszeit',
              unterzeile: 'wann gelesen wird (Ortszeit des Servers)',
              icon: Icons.schedule,
              kind: WebStunden(
                  proStunde: webFaecher(
                      webListe(_besucher['stunden']), 'stunde', 'aufrufe', 24)),
            ),
          if (webListe(_besucher['wochentage']).isNotEmpty)
            _karte(
              titel: 'Wochentag',
              icon: Icons.calendar_view_week,
              kind: WebWochentage(
                // ⚠️ MySQL zählt DAYOFWEEK ab 1 = Sonntag. Ohne die Drehung
                // stünde der Sonntag am Montagsplatz — ein Fehler, den man
                // nur bemerkt, wenn man die Zahlen kennt.
                proTag: () {
                  final roh = webFaecher(webListe(_besucher['wochentage']),
                      'tag', 'aufrufe', 8);
                  return [roh[2], roh[3], roh[4], roh[5], roh[6], roh[7], roh[1]];
                }(),
              ),
            ),
          _listenKarte('Netzbetreiber', Icons.router_outlined,
              webListe(_besucher['netze']), 'netz', 'aufrufe',
              unterzeile: 'trennt gewöhnliche Anschlüsse von Rechenzentren — '
                  'letztere sind meist VPN oder Maschine',
              zusatzFeld: 'besucher', zusatzName: 'Bes.'),
          Row(
            children: [
              Expanded(child: _anteilKarte('Adressfamilie', Icons.alt_route,
                  webListe(_besucher['ip_art']), 'ip_art', (s) => s.toUpperCase())),
              Expanded(child: _anteilKarte('Verschlüsselung', Icons.lock_outline,
                  webListe(_besucher['tls_art']), 'tls',
                  (s) => s.isEmpty ? 'ohne Angabe' : s)),
            ],
          ),
          _karte(
            titel: 'Wer die Einstellungen benutzt',
            unterzeile: 'Der Auftritt hat sechs Farbtöne, hohen Kontrast, vier '
                'Schriftgrößen, Zeilen- und Absatzabstand, Fokusrahmen und '
                '„Bewegung aus". Ob das je jemand benutzt, stand bisher nirgends.',
            icon: Icons.accessibility_new,
            farbe: webListe(_besucher['einstellungen']).isEmpty
                ? Colors.grey
                : kWebMensch,
            kind: webListe(_besucher['einstellungen']).isEmpty
                ? _leer('In diesem Zeitfenster hat niemand eine Einstellung '
                    'geändert. Das heißt nicht, dass sie niemand benutzt — wer '
                    'sie einmal gesetzt hat, behält sie im Browser und taucht '
                    'hier nie wieder auf.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in webListe(_besucher['einstellungen']))
                        _balken(
                          webEinstellungName('${e['einstellung']}'),
                          webZahl(e['aufrufe']),
                          webListe(_besucher['einstellungen'])
                              .map((x) => webZahl(x['aufrufe']))
                              .fold(0, math.max),
                          zusatz: '${e['einstellung']}',
                          farbe: '${e['einstellung']}'.startsWith('sprache=')
                              ? kWebMaschine
                              : kWebMensch,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Für diesen Verein ist das keine beliebige Zahl: nach § 1 '
                        'der Satzung besteht der Vorstand mehrheitlich aus '
                        'Menschen mit Behinderung. Ob die Arbeit an der '
                        'Barrierefreiheit jemanden erreicht, ist die Frage, die '
                        'dieser Auftritt beantworten können muss.\n\n'
                        '⚠️ Gezählt wird das UMSCHALTEN, nicht das Benutzen. Wer '
                        'einmal auf hohen Kontrast gestellt hat, behält ihn im '
                        'Browser und erscheint hier kein zweites Mal — die Zahl '
                        'ist also eine Untergrenze, nie eine Obergrenze.\n\n'
                        'Gespeichert wird nur das Paar aus bekanntem Namen und '
                        'bekanntem Wert, nie die ganze Adresszeile: im selben '
                        'Protokoll stehen Angriffsversuche, die Zugangsdaten '
                        'abzugreifen versuchen.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
          ),
          if (webListe(_besucher['fehlseiten']).isNotEmpty)
            _karte(
              titel: 'Fehlseiten mit Adresse',
              unterzeile: 'Nach Art getrennt: ein 404 von einer Maschine ist ein '
                  'Klopfen an verschlossene Türen und normal — ein 404 von einem '
                  'Menschen ist ein Fehler bei uns.',
              icon: Icons.report_gmailerrorred_outlined,
              farbe: webListe(_besucher['fehlseiten'])
                      .any((f) => webZahl(f['mensch']) > 0)
                  ? Colors.orange.shade700
                  : null,
              kind: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in webListe(_besucher['fehlseiten']))
                    _balken(
                      '${f['pfad']}',
                      webZahl(f['aufrufe']),
                      webZahl(webListe(_besucher['fehlseiten'])
                          .map((e) => webZahl(e['aufrufe']))
                          .fold(0, math.max)),
                      zusatz: webZahl(f['mensch']) > 0
                          ? '⚠️ ${webZahl(f['mensch'])} davon von Menschen'
                          : 'nur Maschinen',
                      farbe: webZahl(f['mensch']) > 0 ? kWebScan : Colors.grey,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Die Zählung je Antwortcode nennt nur die Summe. Welche '
                    'Adresse fehlt, stand bisher nirgends — eine kaputte '
                    'Verknüpfung im eigenen Auftritt war damit unsichtbar.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          if (webListe(_besucher['maschinen_absicht']).isNotEmpty)
            _karte(
              titel: 'Maschinen nach Absicht',
              unterzeile: 'Ein Suchdienst bringt Leser. Ein KI-Sammler nimmt '
                  'Inhalte mit. Das ist nicht dasselbe, und in einer Zahl '
                  'zusammengefasst sieht man den Unterschied nicht.',
              icon: Icons.psychology_outlined,
              kind: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final g in webListe(_besucher['maschinen_absicht']))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _balken(
                            _absichtName('${g['gruppe']}'),
                            webZahl(g['aufrufe']),
                            webListe(_besucher['maschinen_absicht'])
                                .map((e) => webZahl(e['aufrufe']))
                                .fold(0, math.max),
                            farbe: '${g['gruppe']}' == 'suchmaschine'
                                ? kWebMensch
                                : kWebMaschine,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 2),
                            child: Text(
                              webListe(g['namen'])
                                  .map((n) =>
                                      '${n['bot_name']} (${webZahl(n['aufrufe'])})')
                                  .join(' · '),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    _absichtHinweis(webListe(_besucher['maschinen_absicht'])),
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                  ),
                ],
              ),
            ),
          _listenKarte('Maschinen mit Namen', Icons.smart_toy_outlined,
              webListe(_besucher['maschinen']), 'bot_name', 'aufrufe',
              unterzeile: 'Suchdienste, Vorschaubilder in Messengern, KI-Sammler. '
                  'Sie zählen nirgends als Besucher.',
              farbe: kWebMaschine),
          _listenKarte('Antwortcodes', Icons.numbers,
              webListe(_besucher['status']), 'status', 'aufrufe'),
          if (webListe(_besucher['letzte']).isNotEmpty)
            _karte(
              titel: 'Die jüngsten Zugriffe',
              unterzeile: 'Alle drei Arten nebeneinander — erst daneben sieht '
                  'man, dass zwischen zwei gelesenen Seiten zwanzig '
                  'Klopfversuche liegen.',
              icon: Icons.bolt_outlined,
              kind: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final z in webListe(_besucher['letzte']))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: webArtFarbe('${z['art']}'),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(_zeitpunkt(z['zeit']),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                  color: Colors.grey.shade600)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${z['pfad']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${webFlagge('${z['land']}')} '
                            '${webZahl(z['status'])} · ${z['ip_art']}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '⚠️ Ohne Besucherschlüssel. Die Liste soll zeigen, WAS gerade '
                    'geschieht, nicht WER da ist — mit dem Schlüssel ließen sich '
                    'die Zeilen zu Sitzungen zusammensetzen, und genau das soll '
                    'dieser Aufbau nicht hergeben.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          _karte(
            titel: 'Was hier nicht steht, und warum',
            icon: Icons.help_outline,
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fehltZeile(
                  'Wiederkehrende Besucher, Besuchshäufigkeit',
                  'Der Prüfwert wird täglich neu gesalzen, damit sich niemand '
                  'über Tage verketten lässt. Auswertungen wie Matomo brauchen '
                  'dafür ein Cookie im Browser. Das ist kein Mangel, sondern '
                  'genau die Entscheidung, die diesen Auftritt ohne '
                  'Einwilligungsbanner auskommen lässt.',
                ),
                _fehltZeile(
                  'Bildschirmauflösung, Browser-Zusätze, Scrolltiefe',
                  'Dafür bräuchte es ein Skript im Browser. Gezählt wird hier '
                  'ausschließlich im Zugriffsprotokoll des Servers.',
                ),
                _fehltZeile(
                  'Das Klickprotokoll einzelner Sitzungen',
                  'Technisch ginge es innerhalb eines Tages — es macht aber aus '
                  'einer Statistik die Spur eines Einzelnen. Die Karte '
                  '„Häufigste Wege" liefert denselben Erkenntnisgewinn '
                  'zusammengefasst.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _klassenName(int sekunden) => switch (sekunden) {
        300 => 'je 5 Minuten',
        900 => 'je 15 Minuten',
        1800 => 'je halbe Stunde',
        3600 => 'je Stunde',
        21600 => 'je 6 Stunden',
        86400 => 'je Tag',
        604800 => 'je Woche',
        _ => 'je ${sekunden ~/ 60} Minuten',
      };

  String _klassenBeschriftung(String zeit, int klasse) {
    if (zeit.length < 16) return zeit;
    // Unter einem Tag interessiert die Uhrzeit, darüber das Datum.
    return klasse < 86400 ? zeit.substring(11, 16) : zeit.substring(8, 10);
  }

  /// Eine Rangliste als Karte — dieselbe Form für ein Dutzend Listen.
  Widget _listenKarte(String titel, IconData icon,
      List<Map<String, dynamic>> zeilen, String feld, String wertFeld,
      {String? unterzeile,
      String Function(String)? beschriften,
      String? flaggeAus,
      String? zusatzFeld,
      String? zusatzName,
      Color? farbe,
      int hoechstens = 15}) {
    return _karte(
      titel: titel,
      unterzeile: unterzeile,
      icon: icon,
      farbe: farbe,
      kind: zeilen.isEmpty
          ? _leer('Nichts im gewählten Zeitraum.')
          : Column(
              children: [
                for (final z in zeilen.take(hoechstens))
                  _balken(
                    beschriften != null
                        ? beschriften('${z[feld]}')
                        : ('${z[feld]}'.isEmpty ? '—' : '${z[feld]}'),
                    webZahl(z[wertFeld]),
                    webZahl(zeilen.first[wertFeld]),
                    farbe: farbe ?? kWebMensch,
                    flagge: flaggeAus != null ? webFlagge('${z[flaggeAus]}') : null,
                    zusatz: zusatzFeld != null
                        ? '${webZahl(z[zusatzFeld])} ${zusatzName ?? ''}'
                        : null,
                  ),
              ],
            ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab 3 — Seiten
  // -------------------------------------------------------------------------

  Widget _tabSeiten() {
    final seiten = webListe(_seiten['seiten']);
    final verlauf = webListe(_seiten['seiten_verlauf']);
    final suchmaschinen = webListe(_seiten['suchmaschinen']);
    final nichtGecrawlt = webListe(_seiten['nicht_gecrawlt']);
    final unbesucht = webListe(_seiten['unbesucht']);
    final gesamt = webZahl(_seiten['seiten_gesamt']);

    // Reihen für den Verlauf der Spitzenseiten: erst die Tage sammeln, dann
    // je Seite auffüllen. Ohne das gemeinsame Tagesraster lägen die Linien
    // gegeneinander verschoben.
    final tage = <String>{};
    for (final v in verlauf) {
      tage.add('${v['datum']}');
    }
    final tageSortiert = tage.toList()..sort();
    final proSeite = <String, Map<String, int>>{};
    for (final v in verlauf) {
      proSeite.putIfAbsent('${v['pfad']}', () => {})['${v['datum']}'] =
          webZahl(v['mensch']);
    }

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: 'Meistgelesene Seiten',
            unterzeile: 'grün = Menschen, blaugrau = Maschinen. Ohne die Gegenzahl '
                'sieht eine Seite mit fünf Lesern aus wie eine mit fünf Lesern und '
                'neunhundert Crawlern.',
            icon: Icons.article_outlined,
            kind: seiten.isEmpty
                ? _leer('Noch keine Seitenaufrufe im Zeitraum.')
                : Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: WebLegende(
                            farben: [kWebMensch, kWebMaschine],
                            namen: ['Menschen', 'Maschinen']),
                      ),
                      for (final s in seiten.take(20))
                        _balkenGeteilt(
                          '${s['pfad']}',
                          webZahl(s['mensch']),
                          webZahl(s['maschine']),
                          webZahl(seiten.first['aufrufe']),
                          zusatz: webZahl(s['dauer']) > 0
                              ? '${webZahl(s['dauer'])} ms'
                              : null,
                        ),
                    ],
                  ),
          ),
          if (proSeite.isNotEmpty && tageSortiert.length > 1)
            _karte(
              titel: 'Verlauf der fünf größten',
              unterzeile: 'nur Menschen — eine Rangliste sagt nicht, ob eine Seite '
                  'gerade entdeckt wird oder seit Wochen liegen bleibt',
              icon: Icons.stacked_line_chart,
              kind: WebLinien(
                namen: proSeite.keys.toList(),
                reihen: [
                  for (final pfad in proSeite.keys)
                    [for (final t in tageSortiert) proSeite[pfad]?[t] ?? 0],
                ],
                xBeschriftung: [_datum(tageSortiert.first), _datum(tageSortiert.last)],
              ),
            ),
          _karte(
            titel: 'Was die Suchmaschinen geholt haben',
            unterzeile: 'Der einzige Blick auf das eigene Erscheinen in der Suche, '
                'der ohne fremdes Konto auskommt — ohne Stichprobe, ohne fremde Deutung.',
            icon: Icons.travel_explore,
            kind: suchmaschinen.isEmpty
                ? _leer('Im Zeitraum hat keine Suchmaschine den Auftritt geholt. '
                    'Bei einem jungen Auftritt ist das normal; dauerhaft wäre es '
                    'ein Grund, die Adresse bei Google und Bing anzumelden.')
                : Column(
                    children: [
                      for (final s in suchmaschinen)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.search, size: 20),
                          title: Text('${s['bot_name']}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${webZahl(s['abrufe'])} Abrufe · '
                              '${webZahl(s['seiten'])} verschiedene Seiten'
                              '${webZahl(s['fehler']) > 0 ? ' · ${webZahl(s['fehler'])} Fehler' : ''}',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Text(_zeitpunkt(s['zuletzt']),
                              style: const TextStyle(fontSize: 10)),
                        ),
                    ],
                  ),
          ),
          _karte(
            titel: 'Seiten ohne Suchmaschinenbesuch',
            unterzeile: '$gesamt Seiten hat der Auftritt insgesamt',
            icon: Icons.visibility_off_outlined,
            farbe: nichtGecrawlt.isEmpty ? kWebMensch : Colors.orange.shade700,
            kind: nichtGecrawlt.isEmpty
                ? Text('Jede Seite wurde von mindestens einer Suchmaschine geholt.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${nichtGecrawlt.length} Seiten wurden im Zeitraum von keiner '
                        'Suchmaschine geholt. Was nicht geholt wird, kann nicht in '
                        'den Index — und was nicht im Index ist, findet niemand.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in nichtGecrawlt.take(30))
                            Chip(
                              label: Text('${s['pfad']}',
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
          if (unbesucht.isNotEmpty)
            _karte(
              titel: 'Seiten, die niemand geöffnet hat',
              icon: Icons.blur_off,
              kind: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in unbesucht)
                    Chip(
                      label: Text('${s['pfad']}', style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
          _listenKarte('Einstiegsseiten', Icons.login,
              webListe(_seiten['einstieg']), 'pfad', 'besuche',
              unterzeile: 'wo die Leute ankommen'),
          _karte(
            titel: 'Sprachfassungen',
            icon: Icons.translate,
            kind: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: WebLegende(
                      farben: [kWebMensch, kWebMaschine],
                      namen: ['Menschen', 'Maschinen']),
                ),
                for (final s in webListe(_seiten['sprach_seiten']))
                  _balkenGeteilt(
                    '${_sprachName('${s['sprache']}')} · ${webZahl(s['seiten'])} Seiten',
                    webZahl(s['mensch']),
                    webZahl(s['maschine']),
                    webListe(_seiten['sprach_seiten']).isEmpty
                        ? 1
                        : webZahl(webListe(_seiten['sprach_seiten']).first['mensch']) +
                            webZahl(webListe(_seiten['sprach_seiten']).first['maschine']),
                  ),
              ],
            ),
          ),
          _karte(
            titel: 'Antwortcodes',
            icon: Icons.numbers,
            kind: Column(
              children: [
                for (final s in webListe(_seiten['status_verteilung']))
                  _balken(
                    '${s['status']} — ${_statusName(webZahl(s['status']))}',
                    webZahl(s['gesamt']),
                    webZahl(webListe(_seiten['status_verteilung']).first['gesamt']),
                    farbe: webZahl(s['status']) >= 500
                        ? kWebScan
                        : webZahl(s['status']) >= 400
                            ? Colors.orange
                            : kWebMensch,
                  ),
              ],
            ),
          ),
          _listenKarte('Woher die Leute kommen', Icons.link,
              webListe(_seiten['verweise']), 'verweis', 'aufrufe',
              unterzeile: 'nur der Name der verweisenden Seite — nie die volle '
                  'Adresse, in der eine Suchanfrage stehen könnte'),
          _karte(
            titel: 'Nicht gefundene Seiten',
            unterzeile: 'ohne Angriffsmuster — was hier steht, sind meist eigene '
                'kaputte Verweise und damit Pflegefälle',
            icon: Icons.report_gmailerrorred,
            farbe: webListe(_seiten['fehlseiten']).isEmpty ? null : Colors.orange.shade700,
            kind: webListe(_seiten['fehlseiten']).isEmpty
                ? _leer('Kein Aufruf ins Leere.')
                : Column(
                    children: [
                      for (final f in webListe(_seiten['fehlseiten']).take(15))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.orange.withValues(alpha: 0.15),
                            child: Text('${f['status']}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.orange)),
                          ),
                          title: Text('${f['pfad']}',
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${webZahl(f['treffer'])}× · zuletzt ${_zeitpunkt(f['zuletzt'])}',
                              style: const TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
          ),
          _karte(
            titel: 'Langsamste Seiten',
            unterzeile: 'Antwortzeit des Servers, ohne Netz und ohne Browser',
            icon: Icons.hourglass_bottom,
            kind: webListe(_seiten['langsam']).isEmpty
                ? _leer('Noch zu wenige Messwerte. Für die rekonstruierten Tage gibt '
                    'es keine Zeiten — das alte Protokollformat hat sie nicht '
                    'mitgeschrieben.')
                : Column(
                    children: [
                      for (final l in webListe(_seiten['langsam']))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${l['pfad']}',
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${webZahl(l['aufrufe'])} Aufrufe · Spitze ${webZahl(l['hoechst'])} ms',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Text('${webZahl(l['mittel'])} ms',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
          ),
          _listenKarte('Alle Maschinen', Icons.smart_toy_outlined,
              webListe(_seiten['bots']), 'bot_name', 'aufrufe',
              farbe: kWebMaschine),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _statusName(int s) => switch (s) {
        200 => 'in Ordnung',
        204 => 'kein Inhalt',
        301 => 'dauerhaft umgeleitet',
        302 || 303 => 'umgeleitet',
        304 => 'unverändert',
        400 => 'fehlerhafte Anfrage',
        403 => 'abgewiesen',
        404 => 'nicht gefunden',
        405 => 'Methode nicht erlaubt',
        429 => 'zu viele Anfragen',
        500 => 'Serverfehler',
        502 => 'Gegenstelle antwortet nicht',
        503 => 'nicht verfügbar',
        504 => 'Zeitüberschreitung',
        _ => '—',
      };

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
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: const Text('Jetzt prüfen'),
              ),
            ],
          ),
        ),
      ]);
    }

    // Wie viele Befunde je Stufe — als Balken über allen Blöcken.
    var ok = 0, warn = 0, fehl = 0, info = 0;
    for (final b in bloecke) {
      for (final p in webListe(b['pruefungen'])) {
        switch ('${p['stand']}') {
          case 'ok':
            ok++;
          case 'warnung':
            warn++;
          case 'fehler':
            fehl++;
          default:
            info++;
        }
      }
    }

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: 'Wie viel geprüft wird',
            icon: Icons.checklist_rtl,
            kind: Builder(builder: (_) {
              // ⚠️ Die Summe wird HIER gerechnet, nicht auf dem Server.
              // Es sind zwei getrennte Berichte mit verschiedenem Takt — eine
              // gemeinsame Zahl gäbe es sonst nirgends, und der Bildschirm
              // ist die einzige Stelle, an der beide zusammenkommen.
              final stuendlich = bloecke.fold<int>(
                  0, (a, b) => a + webListe(b['pruefungen']).length);
              final taeglich = webListe(webKarte(_tiefe['bericht'])['bloecke'])
                  .fold<int>(0, (a, b) => a + webListe(b['pruefungen']).length);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 28, runSpacing: 12, children: [
                    _kennzahl('${stuendlich + taeglich}', 'Prüfungen insgesamt',
                        farbe: kWebMensch),
                    _kennzahl('$stuendlich', 'stündlich',
                        fussnote: '${bloecke.length} Blöcke, jede Stunde :33'),
                    _kennzahl('$taeglich', 'täglich',
                        fussnote:
                            '${webListe(webKarte(_tiefe['bericht'])['bloecke']).length}'
                            ' Blöcke, 04:47'),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    'Die stündliche Runde muss schnell bleiben und fragt den '
                    'Auftritt von außen ab. Die tägliche darf Minuten dauern: sie '
                    'lässt testssl gegen den eigenen Port laufen, holt jede Seite '
                    'einzeln und vergleicht Zertifikate und DNS mit gestern.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              );
            }),
          ),
          _karte(
            titel: 'Gesamtbefund',
            unterzeile: 'geprüft ${_zeitpunkt(_sicherheit['geprueft'])}'
                '${_sicherheit['frisch'] == true ? ' · soeben erhoben' : ''}',
            icon: Icons.verified_user_outlined,
            farbe: _notenFarbe(note),
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WebRing(
                  mitte: '${webZahl(note['prozent'])} %',
                  mitteUnten: '${note['stufe']}',
                  teile: [
                    (name: 'in Ordnung', wert: ok, farbe: kWebMensch),
                    (name: 'Hinweise', wert: warn, farbe: const Color(0xFFEF6C00)),
                    (name: 'Fehler', wert: fehl, farbe: kWebScan),
                    (name: 'zur Kenntnis', wert: info, farbe: const Color(0xFF90A4AE)),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _prueftGerade ? null : _jetztPruefen,
                  icon: _prueftGerade
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(_prueftGerade ? 'wird geprüft …' : 'Jetzt neu prüfen'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gemessen wird der Auftritt von außen, nicht die Konfigurationsdatei. '
                  'Eine Kopfzeile, die dort steht, aber auf einer tieferen Ebene '
                  'verdrängt wird, fiele einer Dateiprüfung nicht auf.\n\n'
                  '„Zur Kenntnis" zählt nicht in die Note: eine bewusst getroffene '
                  'Entscheidung ist kein Versäumnis.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          _tiefenKarte(),
          ...bloecke.map(_sicherheitsBlock),
          ..._tiefenBloecke(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Kopf der täglichen Tiefenprüfung.
  ///
  /// ⚠️ Sie wird NICHT auf Knopfdruck erhoben: testssl allein braucht Minuten,
  /// und jede Seite des Auftritts abzurufen ist ein Vielfaches davon. Deshalb
  /// steht hier immer, wie alt der Befund ist — ein alter Befund, der wie ein
  /// frischer aussieht, wäre schlimmer als gar keiner.
  Widget _tiefenKarte() {
    final bericht = webKarte(_tiefe['bericht']);
    if (bericht.isEmpty) {
      return _karte(
        titel: 'Tiefenprüfung',
        icon: Icons.biotech_outlined,
        kind: Text(
          '${_tiefe['meldung'] ?? 'Es liegt noch kein Befund vor.'}',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
      );
    }
    final note = webKarte(bericht['note']);
    final kopfnote = '${bericht['note_kopfzeilen'] ?? '—'}';

    return _karte(
      titel: 'Tiefenprüfung (täglich)',
      unterzeile: 'zuletzt ${_zeitpunkt(_tiefe['geprueft'])} · '
          '${webZahl(bericht['dauer_sekunden'])} s Laufzeit',
      icon: Icons.biotech_outlined,
      farbe: _notenFarbe(note),
      kind: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 28, runSpacing: 12, children: [
            _kennzahl(kopfnote, 'Kopfzeilen-Note',
                farbe: kopfnote.startsWith('A') ? kWebMensch : null,
                fussnote: '${webZahl(bericht['prozent_kopfzeilen'])} von 100'),
            _kennzahl('${webZahl(note['prozent'])} %', '${note['stufe']}',
                farbe: _notenFarbe(note)),
            _kennzahl('${webZahl(note['fehler'])}', 'Fehler',
                farbe: webZahl(note['fehler']) > 0 ? kWebScan : null),
            _kennzahl('${webZahl(note['warnungen'])}', 'Hinweise',
                farbe: webZahl(note['warnungen']) > 0 ? const Color(0xFFEF6C00) : null),
          ]),
          const SizedBox(height: 10),
          Text(
            'Läuft täglich um 04:47 und macht das, was für einen stündlichen Lauf '
            'zu teuer wäre: testssl.sh gegen den eigenen Port 443, jede Seite des '
            'Auftritts einzeln abrufen, jede Adresse aus der Sitemap, alle internen '
            'Verweise und rund sechzig Auslagepfade.\n\n'
            'Die Kopfzeilen-Note ist dieselbe Rechnung wie bei securityheaders.com, '
            'aber selbst gemacht — deren Schnittstelle wurde abgekündigt, und der '
            'eigene Name muss dafür nicht an einen Dritten gehen.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  List<Widget> _tiefenBloecke() {
    final bericht = webKarte(_tiefe['bericht']);
    return webListe(bericht['bloecke']).map(_sicherheitsBlock).toList();
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
              ? kWebScan
              : warnungen > 0
                  ? const Color(0xFFEF6C00)
                  : kWebMensch,
        ),
        title: Text('${block['titel']}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$ok in Ordnung'
                '${warnungen > 0 ? ' · $warnungen Hinweise' : ''}'
                '${fehler > 0 ? ' · $fehler Fehler' : ''}'
                '${block['stand'] != null ? ' · Stand ${_zeitpunkt(block['stand'])}' : ''}'),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: Row(
                  children: [
                    if (ok > 0) Expanded(flex: ok, child: Container(color: kWebMensch)),
                    if (warnungen > 0)
                      Expanded(flex: warnungen,
                          child: Container(color: const Color(0xFFEF6C00))),
                    if (fehler > 0)
                      Expanded(flex: fehler, child: Container(color: kWebScan)),
                    if (pruefungen.length - ok - warnungen - fehler > 0)
                      Expanded(
                          flex: pruefungen.length - ok - warnungen - fehler,
                          child: Container(color: const Color(0xFF90A4AE))),
                  ],
                ),
              ),
            ),
          ],
        ),
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
                Text('${p['wert']}', style: TextStyle(fontSize: 13, color: s.farbe)),
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
    final laender = webListe(_angriffe['laender']);
    final werkzeuge = webListe(_angriffe['werkzeuge']);
    final antworten = webListe(_angriffe['antworten']);
    final letzte = webListe(_angriffe['letzte']);
    final verlauf = webListe(_angriffe['verlauf']);
    final erfolge = webListe(_angriffe['erfolge']);
    final anteil = webKarte(_angriffe['anteil']);
    final gesamt = verlauf.fold<int>(0, (a, t) => a + webZahl(t['scans']));

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: erfolge.isEmpty ? 'Alle Versuche abgewiesen' : 'Es hat etwas geantwortet',
            unterzeile: '$gesamt Versuche im Zeitraum',
            icon: erfolge.isEmpty ? Icons.verified_user : Icons.gpp_bad,
            farbe: erfolge.isEmpty ? kWebMensch : kWebScan,
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
                        leading: const Icon(Icons.warning, color: kWebScan),
                        title: Text('${e['pfad']}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            'HTTP ${e['status']} · ${webZahl(e['treffer'])}× · '
                            'zuletzt ${_zeitpunkt(e['zuletzt'])}',
                            style: const TextStyle(fontSize: 11)),
                      )),
                if (_angriffe['fail2ban'] != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.block, size: 18, color: kWebMaschine),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('fail2ban: ${_angriffe['fail2ban']}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text('${_angriffe['hinweis'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          _karte(
            titel: 'Anteil am gesamten Verkehr',
            icon: Icons.pie_chart_outline,
            kind: WebRing(
              mitte: webTausend(webZahl(anteil['scan'])),
              mitteUnten: 'Versuche',
              teile: [
                (name: 'Menschen', wert: webZahl(anteil['mensch']), farbe: kWebMensch),
                (name: 'Maschinen', wert: webZahl(anteil['maschine']), farbe: kWebMaschine),
                (name: 'Angriffsversuche', wert: webZahl(anteil['scan']), farbe: kWebScan),
              ],
            ),
          ),
          if (verlauf.isNotEmpty)
            _karte(
              titel: 'Verlauf',
              icon: Icons.show_chart,
              kind: WebSaeulen(
                reihenNamen: const ['Angriffsversuche'],
                farben: const [kWebScan],
                punkte: [
                  for (final v in verlauf)
                    WebPunkt(
                      '${v['datum']}'.length >= 10 ? '${v['datum']}'.substring(8, 10) : '',
                      [webZahl(v['scans'])],
                      unterBeschriftung: '${v['datum']}'.length >= 7
                          ? '${v['datum']}'.substring(5, 7)
                          : null,
                    ),
                ],
              ),
            ),
          if (webListe(_angriffe['stunden']).isNotEmpty)
            _karte(
              titel: 'Tageszeit',
              unterzeile: 'Angriffswellen kommen in Schüben, nicht gleichmäßig',
              icon: Icons.schedule,
              kind: WebStunden(
                proStunde: webFaecher(
                    webListe(_angriffe['stunden']), 'stunde', 'versuche', 24),
                farbe: kWebScan,
                einheit: 'Versuche',
              ),
            ),
          _listenKarte('Wonach gesucht wird', Icons.travel_explore, muster,
              'pfad', 'versuche',
              unterzeile: 'Pfade, die es hier nie gab und die praktisch nur '
                  'Angriffswerkzeuge abfragen',
              farbe: kWebScan, zusatzFeld: 'quellen', zusatzName: 'Quellen',
              hoechstens: 20),
          _listenKarte('Womit', Icons.build_outlined, werkzeuge,
              'werkzeug', 'versuche',
              unterzeile: 'Die Kennung ist frei wählbar und damit keine Beweiskette — '
                  'die meisten Werkzeuge tragen ihren Namen aber offen.',
              farbe: kWebScan, zusatzFeld: 'pfade', zusatzName: 'Pfade'),
          _listenKarte('Herkunftsländer', Icons.public, laender, 'land', 'versuche',
              farbe: kWebScan, flaggeAus: 'land',
              zusatzFeld: 'quellen', zusatzName: 'Quellen'),
          _listenKarte('Netze', Icons.router_outlined, herkunft, 'netz', 'versuche',
              farbe: kWebScan),
          _karte(
            titel: 'Was der Server geantwortet hat',
            unterzeile: '403 und 404 sind der gewünschte Zustand',
            icon: Icons.numbers,
            kind: antworten.isEmpty
                ? _leer('Keine Versuche im Zeitraum.')
                : Column(
                    children: [
                      for (final a in antworten)
                        _balken(
                          '${a['status']} — ${_statusName(webZahl(a['status']))}',
                          webZahl(a['versuche']),
                          webZahl(antworten.first['versuche']),
                          farbe: webZahl(a['status']) < 400 ? kWebScan : kWebMensch,
                        ),
                    ],
                  ),
          ),
          _karte(
            titel: 'Die jüngsten Versuche',
            unterzeile: 'Eine Rangliste zeigt nicht, ob gerade jetzt etwas läuft.',
            icon: Icons.history,
            kind: letzte.isEmpty
                ? _leer('Keine Versuche im Zeitraum.')
                : Column(
                    children: [
                      for (final l in letzte.take(20))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Text(webFlagge('${l['land']}'),
                              style: const TextStyle(fontSize: 18)),
                          title: Text('${l['pfad']}',
                              style: const TextStyle(fontSize: 12.5),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${_zeitpunkt(l['zeit'])} · HTTP ${l['status']}'
                              '${'${l['netz']}'.isNotEmpty ? ' · ${l['netz']}' : ''}'
                              '${'${l['bot_name']}'.isNotEmpty ? ' · ${l['bot_name']}' : ''}',
                              style: const TextStyle(fontSize: 10.5),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab 6 — SEO und Ladeverhalten je Seite
  // -------------------------------------------------------------------------

  Widget _tabSeo() {
    final seiten = webListe(_seo['seiten']);
    final schnitt = webKarte(_seo['schnitt']);

    if (seiten.isEmpty) {
      return ListView(children: [
        _karte(
          titel: 'Noch keine Seitenbewertung',
          icon: Icons.speed_outlined,
          kind: Text('${_seo['meldung'] ?? 'Es liegen keine Karten vor.'}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: 'Alle Seiten im Schnitt',
            unterzeile: '${webZahl(_seo['anzahl'])} Seiten · erhoben '
                '${_zeitpunkt(_seo['geprueft'])}',
            icon: Icons.speed_outlined,
            farbe: webZahl(schnitt['note']) >= 90 ? kWebMensch : null,
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 28, runSpacing: 12, children: [
                  _kennzahl('${webZahl(schnitt['note'])}', 'von 100',
                      farbe: webZahl(schnitt['note']) >= 90 ? kWebMensch : null),
                  _kennzahl('${webZahl(schnitt['woerter'])}', 'Wörter je Seite'),
                  _kennzahl(webBytes(webZahl(schnitt['groesse_gz'])), 'auf der Leitung',
                      fussnote: 'komprimiert, wie nginx es sendet'),
                  _kennzahl('${webZahl(schnitt['antwort_ms'])} ms', 'Antwortzeit'),
                  _kennzahl('${webZahl(_seo['waisen'])}', 'Waisen',
                      farbe: webZahl(_seo['waisen']) > 0 ? const Color(0xFFEF6C00) : null,
                      fussnote: 'ohne internen Verweis'),
                ]),
                const SizedBox(height: 12),
                Text('${_seo['hinweis'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          _karte(
            titel: 'Jede Seite einzeln',
            unterzeile: 'die schwächste zuerst — antippen für die Einzelwerte',
            icon: Icons.list_alt,
            kind: Column(children: seiten.map(_seoZeile).toList()),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _seoZeile(Map<String, dynamic> s) {
    final note = webZahl(s['note']);
    final maengel = '${s['maengel'] ?? ''}';
    final farbe = note >= 95
        ? kWebMensch
        : note >= 85
            ? const Color(0xFF558B2F)
            : note >= 70
                ? const Color(0xFFEF6C00)
                : kWebScan;

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: farbe.withValues(alpha: 0.14),
        child: Text('$note',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: farbe)),
      ),
      title: Text('${s['pfad']}',
          style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          maengel.isEmpty ? 'ohne Beanstandung' : maengel,
          style: TextStyle(
              fontSize: 11,
              color: maengel.isEmpty ? Colors.grey.shade600 : farbe),
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      children: [
        _seoWert('Titel', '${s['titel']}',
            zusatz: '${webZahl(s['titel_laenge'])} Zeichen'),
        _seoWert('Überschrift h1', '${s['h1']}',
            zusatz: webZahl(s['h1_anzahl']) == 1
                ? null
                : '${webZahl(s['h1_anzahl'])}× vorhanden'),
        _seoPaare([
          ('Beschreibung', '${webZahl(s['beschreibung_laenge'])} Zeichen'),
          ('Wörter', '${webZahl(s['woerter'])}'),
          ('canonical', webZahl(s['canonical']) == 1 ? 'ja' : 'nein'),
          ('hreflang', '${webZahl(s['hreflang'])}'),
          ('in der Sitemap', webZahl(s['in_sitemap']) == 1 ? 'ja' : 'nein'),
          ('indexierbar', webZahl(s['noindex']) == 1 ? 'nein (noindex)' : 'ja'),
        ]),
        _seoPaare([
          ('Verweise hinein', '${webZahl(s['links_eingehend'])}'),
          ('Verweise intern', '${webZahl(s['links_intern'])}'),
          ('Verweise nach außen', '${webZahl(s['links_extern'])}'),
          ('Bilder', '${webZahl(s['bilder'])}'
              '${webZahl(s['bilder_ohne_alt']) > 0 ? ' (${webZahl(s['bilder_ohne_alt'])} ohne alt)' : ''}'),
        ]),
        _seoPaare([
          ('Größe roh', webBytes(webZahl(s['groesse']))),
          ('auf der Leitung', webBytes(webZahl(s['groesse_gz']))),
          ('Antwortzeit', '${webZahl(s['antwort_ms'])} ms'),
          ('blockierend im Kopf', '${webZahl(s['blockierend'])}'),
        ]),
      ],
    );
  }

  Widget _seoWert(String name, String wert, {String? zusatz}) {
    if (wert.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('$name  ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            if (zusatz != null)
              Text(zusatz, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
          Text(wert, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _seoPaare(List<(String, String)> paare) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        children: [
          for (final (name, wert) in paare)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                Text(wert, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab 7 — Übersetzung: welche Sprachen der Auftritt hat, und welche nicht
  // -------------------------------------------------------------------------

  Widget _tabUebersetzung() {
    // ⚠️ Die Liste der Sprachen kommt aus sprachen_options.dart — derselben,
    // die im Mitgliederpanel die Muttersprache anbietet. Eine zweite Liste
    // hier hieße, dass die beiden irgendwann auseinanderlaufen.
    final vorhanden = <String, Map<String, dynamic>>{
      for (final s in webListe(_sprachen['sprachen'])) '${s['code']}': s,
    };

    // Nur was begehbar ist, zählt als vorhanden: ein Wörterbuch allein macht
    // noch keine Sprachfassung.
    final begehbar = vorhanden.values.where((s) => s['begehbar'] == true).length;
    final nurWoerterbuch = vorhanden.values
        .where((s) => s['begehbar'] != true && s['woerterbuch'] == true)
        .length;

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        children: [
          _karte(
            titel: 'Sprachfassungen',
            unterzeile: '$begehbar von ${alleSprachen.length} Sprachen der Liste',
            icon: Icons.translate,
            farbe: kWebMensch,
            kind: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 28, runSpacing: 12, children: [
                  _kennzahl('$begehbar', 'begehbar', farbe: kWebMensch,
                      fussnote: 'Seiten unter /<code>/'),
                  if (nurWoerterbuch > 0)
                    _kennzahl('$nurWoerterbuch', 'nur Wörterbuch',
                        farbe: const Color(0xFFEF6C00),
                        fussnote: 'übersetzt, nicht ausgeliefert'),
                  _kennzahl('${webZahl(_sprachen['seiten_je_fassung'])}',
                      'Seiten je Fassung'),
                  _kennzahl(
                      '${_europaAnteil(vorhanden)} / '
                      '${sprachenNachKontinent(Kontinent.europa).length}',
                      'davon europäisch'),
                ]),
                const SizedBox(height: 10),
                Text('${_sprachen['hinweis'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          for (final k in Kontinent.values) _kontinentKarte(k, vorhanden),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  int _europaAnteil(Map<String, Map<String, dynamic>> vorhanden) =>
      sprachenNachKontinent(Kontinent.europa)
          .where((s) => vorhanden[s.code]?['begehbar'] == true)
          .length;

  Widget _kontinentKarte(Kontinent k, Map<String, Map<String, dynamic>> vorhanden) {
    final sprachen = sprachenNachKontinent(k);
    final da = sprachen.where((s) => vorhanden[s.code]?['begehbar'] == true).toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: ExpansionTile(
        // Europa aufgeklappt: dort stehen alle Fassungen, die es gibt.
        initiallyExpanded: k == Kontinent.europa,
        leading: CircleAvatar(
          radius: 17,
          backgroundColor: (da.isEmpty ? Colors.grey : kWebMensch)
              .withValues(alpha: 0.14),
          child: Text('${da.length}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: da.isEmpty ? Colors.grey.shade600 : kWebMensch)),
        ),
        title: Text(k.bezeichnung,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(da.isEmpty
            ? '${sprachen.length} Sprachen, keine davon auf dem Auftritt'
            : '${da.length} von ${sprachen.length}: '
                '${da.map((s) => s.bezeichnung).join(', ')}'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sprachen.map((s) => _sprachChip(s, vorhanden[s.code])).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sprachChip(Sprache s, Map<String, dynamic>? stand) {
    final begehbar = stand?['begehbar'] == true;
    final nurBuch = !begehbar && stand?['woerterbuch'] == true;
    final farbe = begehbar
        ? kWebMensch
        : nurBuch
            ? const Color(0xFFEF6C00)
            : Colors.grey;

    return Tooltip(
      message: begehbar
          ? '${s.bezeichnung} (${s.code}) — ${webZahl(stand?['seiten'])} Seiten, '
              '${webZahl(stand?['abdeckung'])} % der deutschen Fassung'
          : nurBuch
              ? '${s.bezeichnung} (${s.code}) — Wörterbuch vorhanden, aber keine '
                  'begehbaren Seiten'
              : '${s.bezeichnung} (${s.code}) — nicht vorhanden',
      child: Chip(
        avatar: Icon(
          begehbar
              ? Icons.check_circle
              : nurBuch
                  ? Icons.hourglass_bottom
                  : Icons.remove_circle_outline,
          size: 16,
          color: farbe,
        ),
        label: Text(
          begehbar
              ? '${s.bezeichnung} · ${webZahl(stand?['abdeckung'])} %'
              : s.bezeichnung,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: begehbar ? FontWeight.w600 : FontWeight.normal,
            color: begehbar ? null : Colors.grey.shade600,
          ),
        ),
        backgroundColor: begehbar ? farbe.withValues(alpha: 0.10) : null,
        side: BorderSide(
            color: begehbar ? farbe.withValues(alpha: 0.4) : Theme.of(context).dividerColor),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
