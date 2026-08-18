import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/mail_adressbuch.dart';

/// Das Adressbuch für das Empfängerfeld — dasselbe Bedienmuster wie die
/// Kontaktliste am Telefon, nur eine Spalte weiter.
///
/// ⚠️ WARUM DIE LISTE NICHT GEPFLEGT WIRD, SONDERN ENTSTEHT
/// 401 Adressen stehen bereits in den Stammdaten: Mitglieder, Praxen,
/// Kliniken, Apotheken, Ämter, Gerichte, Kassen, Versicherungen. Eine zweite,
/// gepflegte Adressliste daneben wäre binnen Wochen ein Stand von gestern —
/// genau der Fehler, der bei `arzt_telefon` schon einmal dieselbe Praxis
/// dreissigmal in unterschiedlichen Ständen hinterlassen hat. Der Server sucht
/// deshalb live (gemessen 37 ms über rund fünfzig Tabellen), und gespeichert
/// wird nur, was nirgends sonst steht.
///
/// ⚠️ WER KEINE ADRESSE HAT, STEHT HIER NICHT — auch nicht mit Rufnummer. Eine
/// Zeile ohne Adresse wäre in einem Empfängerfeld nichts, was man anklicken
/// könnte, und ein Tipp darauf sähe aus wie ein Fehler.
///
/// ⚠️ MEHRFACHAUSWAHL, anders als am Telefon. Ein Anruf hat genau ein Ziel,
/// eine E-Mail hat oft mehrere — und wer für jeden Empfänger einmal hin und
/// zurück muss, tippt die Adressen beim dritten Mal lieber ab.
class MailKontakteScreen extends StatefulWidget {
  const MailKontakteScreen({super.key, this.feldName = 'An'});

  /// Für welches Feld gesucht wird — steht im Titel und auf dem Knopf.
  ///
  /// ⚠️ Ohne diese Angabe wäre nach zwei Griffen nicht mehr klar, ob die
  /// Auswahl gleich bei „An", „Cc" oder „Bcc" landet. Bei Bcc ist das keine
  /// Kleinigkeit: dort entscheidet es darüber, ob die Empfänger einander sehen.
  final String feldName;

  @override
  State<MailKontakteScreen> createState() => _MailKontakteScreenState();
}

class _MailKontakteScreenState extends State<MailKontakteScreen> {
  final TextEditingController _suche = TextEditingController();
  Timer? _tippPause;

  bool _laedt = true;
  String? _fehler;
  String _kategorie = '';
  List<MailKontakt> _kontakte = const [];
  Map<String, int> _kategorien = const {};
  int _gesamt = 0;

  /// Die Auswahl lebt **unabhängig von der geladenen Liste**.
  ///
  /// ⚠️ Sonst verliert man mit dem nächsten Suchbegriff, was man gerade
  /// angehakt hat — und merkt es erst im Empfängerfeld. Adresse (klein
  /// geschrieben) → Anzeigename, damit die Merkchips einen Namen tragen.
  final Map<String, MailKontakt> _gewaehlt = {};

  /// Nur die jüngste Antwort zählt. Wer schnell tippt, löst mehrere Abfragen
  /// aus; käme die zu „Apo" nach der zu „Apothek", stünde plötzlich wieder die
  /// längere Liste da und man hielte die Suche für kaputt.
  int _abfrage = 0;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _tippPause?.cancel();
    _suche.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    final meine = ++_abfrage;
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    try {
      final a = await ApiService().mailKontakteAction({
        'action': 'kontakte',
        'suche': _suche.text.trim(),
        'kategorie': _kategorie,
        'limit': 300,
      });
      if (!mounted || meine != _abfrage) return;
      setState(() {
        _laedt = false;
        if (a['success'] != true) {
          _fehler = '${a['message'] ?? 'Das Adressbuch konnte nicht geladen werden'}';
          return;
        }
        // Flach, kein `data`, und `kategorien` kann Liste ODER Objekt sein —
        // beides hängt an einer Stelle, die dafür Tests hat.
        final gelesen = mailKontakteAusAntwort(a);
        _kontakte = gelesen.kontakte;
        _kategorien = gelesen.kategorien;
        _gesamt = gelesen.gesamt;
      });
    } catch (e) {
      if (!mounted || meine != _abfrage) return;
      setState(() {
        _laedt = false;
        _fehler = 'Das Adressbuch konnte nicht geladen werden: $e';
      });
    }
  }

  void _sucheGeaendert(String _) {
    // Nicht bei jedem Buchstaben zum Server: die Suche läuft über rund fünfzig
    // Tabellen, und getippt wird schneller als geantwortet.
    _tippPause?.cancel();
    _tippPause = Timer(const Duration(milliseconds: 350), _laden);
    setState(() {});
  }

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade700 : null,
      duration: Duration(seconds: fehler ? 6 : 3),
    ));
  }

  void _umschalten(MailKontakt k) {
    setState(() {
      final schluessel = k.email.toLowerCase();
      if (_gewaehlt.remove(schluessel) == null) _gewaehlt[schluessel] = k;
    });
  }

  void _uebernehmen() {
    // Die Schreibweise aus dem Bestand, nicht der kleingeschriebene Schlüssel.
    Navigator.pop(context, _gewaehlt.values.map((k) => k.email).toList());
  }

  // ── Eigene Kontakte ────────────────────────────────────────────────────────

  Future<void> _bearbeiten([MailKontakt? vorhanden]) async {
    final name = TextEditingController(text: vorhanden?.name ?? '');
    final adresse = TextEditingController(text: vorhanden?.email ?? '');
    final notiz = TextEditingController(text: vorhanden?.notiz ?? '');

    final speichern = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(vorhanden == null ? 'Kontakt anlegen' : 'Kontakt ändern'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Frau Merkle, Wohngeldstelle',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: adresse,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-Mail-Adresse',
                  hintText: 'poststelle@amt.de',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notiz,
                decoration: const InputDecoration(
                  labelText: 'Notiz (freiwillig)',
                  hintText: 'zuständig für Wohngeld, antwortet Di + Do',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Praxen, Ämter und Mitglieder stehen schon in den Stammdaten und '
                'werden dort gepflegt. Hier gehört hin, was sonst nirgends steht.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Speichern')),
        ],
      ),
    );

    if (speichern != true) return;
    final a = await ApiService().mailKontakteAction({
      'action': 'kontakt_save',
      if (vorhanden?.id != null) 'id': vorhanden!.id,
      'name': name.text,
      'email': adresse.text,
    });
    if (a['success'] == true) {
      _melde(vorhanden == null ? 'Kontakt angelegt' : 'Kontakt geändert');
      await _laden();
    } else {
      // Die Meldung kommt wörtlich vom Server — dort stehen die Gründe, die
      // hier niemand nachbilden sollte („Das ist keine vollstaendige
      // E-Mail-Adresse", „Diesen Kontakt gibt es schon").
      _melde('${a['message'] ?? 'Speichern fehlgeschlagen'}', fehler: true);
    }
  }

  Future<void> _loeschen(MailKontakt k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Kontakt löschen?'),
        content: Text('„${k.name}" wird aus den eigenen Kontakten entfernt.\n\n'
            'Trägt der Eintrag auch eine Rufnummer, verschwindet er damit '
            'ebenso aus der Kontaktliste des Telefons — es ist derselbe '
            'Kontakt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final a = await ApiService()
        .mailKontakteAction({'action': 'kontakt_delete', 'id': k.id});
    if (a['success'] == true) {
      setState(() => _gewaehlt.remove(k.email.toLowerCase()));
      _melde('Kontakt gelöscht');
      await _laden();
    } else {
      _melde('${a['message'] ?? 'Löschen fehlgeschlagen'}', fehler: true);
    }
  }

  // ── Aufbau ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('Adressbuch — ${widget.feldName}'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu laden',
            onPressed: _laden,
          ),
        ],
      ),
      floatingActionButton: _gewaehlt.isNotEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _bearbeiten(),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Eigener Kontakt'),
            ),
      bottomNavigationBar: _gewaehlt.isEmpty ? null : _fussleiste(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _suche,
              onChanged: _sucheGeaendert,
              decoration: InputDecoration(
                hintText: 'Name oder Adresse',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: const OutlineInputBorder(),
                suffixIcon: _suche.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _suche.clear();
                          _laden();
                        },
                      ),
              ),
            ),
          ),
          if (_kategorien.isNotEmpty) _kategorieleiste(),
          Expanded(child: _liste()),
        ],
      ),
    );
  }

  Widget _kategorieleiste() {
    // ⚠️ Die Zahlen kommen vom Server und gelten für die aktuelle SUCHE, nicht
    // für die gewählte Kategorie — sonst stünde nach dem ersten Klick überall 0
    // und die Leiste wäre eine Sackgasse.
    final eintraege = _kategorien.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text('Alle ($_gesamtAlle)'),
              selected: _kategorie == '',
              onSelected: (_) {
                setState(() => _kategorie = '');
                _laden();
              },
            ),
          ),
          for (final e in eintraege)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text('${mailKategorieName(e.key)} (${e.value})'),
                selected: _kategorie == e.key,
                onSelected: (_) {
                  setState(() => _kategorie = _kategorie == e.key ? '' : e.key);
                  _laden();
                },
              ),
            ),
        ],
      ),
    );
  }

  int get _gesamtAlle => _kategorien.values.fold(0, (a, b) => a + b);

  /// Was ausgewählt ist, bleibt sichtbar — auch wenn die Liste darunter längst
  /// etwas anderes zeigt.
  Widget _fussleiste() {
    final gewaehlt = _gewaehlt.values.toList();
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              // Bei vielen Empfängern soll die Leiste den Bildschirm nicht
              // auffressen; ab hier wird gescrollt.
              constraints: const BoxConstraints(maxHeight: 108),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    for (final k in gewaehlt)
                      InputChip(
                        label: Text(k.name, overflow: TextOverflow.ellipsis),
                        onDeleted: () => _umschalten(k),
                        tooltip: k.email,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _uebernehmen,
              icon: const Icon(Icons.check),
              label: Text(gewaehlt.length == 1
                  ? 'Eine Adresse in „${widget.feldName}" übernehmen'
                  : '${gewaehlt.length} Adressen in „${widget.feldName}" übernehmen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liste() {
    if (_laedt && _kontakte.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_fehler != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade500),
              const SizedBox(height: 10),
              Text(_fehler!, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: _laden, child: const Text('Nochmal versuchen')),
            ],
          ),
        ),
      );
    }
    if (_kontakte.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _suche.text.trim().isEmpty
                ? 'Noch keine Adressen.'
                : 'Nichts gefunden zu „${_suche.text.trim()}".',
            style: TextStyle(color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Der Server liefert mehr, als der Bildschirm zeigt, wenn es viele sind —
    // das steht dann auch da, statt still abgeschnitten zu werden.
    final gekuerzt = _gesamt > _kontakte.length;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 90),
      itemCount: _kontakte.length + (gekuerzt ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i >= _kontakte.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            child: Text(
              'Es gibt $_gesamt Treffer; angezeigt werden ${_kontakte.length}. '
              'Suchen grenzt ein.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          );
        }
        final k = _kontakte[i];
        final an = _gewaehlt.containsKey(k.email.toLowerCase());
        return CheckboxListTile(
          value: an,
          onChanged: (_) => _umschalten(k),
          controlAffinity: ListTileControlAffinity.leading,
          dense: false,
          title: Text(k.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k.email,
                  style: TextStyle(fontSize: 12.5, color: Colors.blue.shade800)),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (k.eigen)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.push_pin, size: 11),
                    ),
                  Flexible(
                    child: Text(
                      k.notiz.isEmpty
                          ? mailKategorieName(k.kategorie)
                          : '${mailKategorieName(k.kategorie)} · ${k.notiz}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Ändern und Löschen gibt es nur bei eigenen Einträgen: die Stammdaten
          // haben ihre eigenen Bildschirme, und eine Praxis aus dem Adressbuch
          // heraus zu löschen wäre eine Katastrophe, die aussieht wie ein
          // aufgeräumtes Telefonbuch.
          secondary: !k.eigen
              ? null
              : PopupMenuButton<String>(
                  tooltip: 'Eigener Kontakt',
                  onSelected: (w) =>
                      w == 'aendern' ? _bearbeiten(k) : _loeschen(k),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'aendern', child: Text('Ändern')),
                    PopupMenuItem(value: 'loeschen', child: Text('Löschen')),
                  ],
                ),
        );
      },
    );
  }
}
