import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/phone_call_service.dart';
import '../services/sipgate_service.dart';

/// Das Telefonbuch des Vereins — und die eigenen Einträge daneben.
///
/// ⚠️ WARUM DIE LISTE NICHT GEPFLEGT WIRD, SONDERN ENTSTEHT
/// 517 Rufnummern stehen bereits in den Stammdaten: Mitglieder, Praxen,
/// Kliniken, Apotheken, Ämter, Gerichte, Kassen. Eine zweite, gepflegte
/// Kontaktliste daneben wäre binnen Wochen ein Stand von gestern — genau der
/// Fehler, der bei `arzt_telefon` schon einmal dieselbe Praxis dreissigmal in
/// unterschiedlichen Ständen hinterlassen hat. Der Server sucht deshalb live
/// (18 ms über alle Tabellen), und gespeichert wird nur, was nirgends sonst
/// steht: die Durchwahl einer Sachbearbeiterin, das Handy des Hausmeisters.
///
/// Angetippt wird ein Kontakt, um seine Nummer ins Wählfeld zu holen — gewählt
/// wird auf dem vorigen Bildschirm. So bleibt die Entscheidung „jetzt anrufen"
/// dort, wo auch der Notrufhinweis und der Konferenzknopf stehen.
class SipgateKontakteScreen extends StatefulWidget {
  const SipgateKontakteScreen({super.key, this.zurueckgeben = true});

  /// Gibt die Nummer an den vorigen Bildschirm zurück, statt selbst zu wählen.
  ///
  /// ⚠️ Auf dem Rechner gibt es kein Wählfeld — dort ist dieser Bildschirm Teil
  /// des Bedienpults, und eine zurückgegebene Nummer fiele ins Leere. Deshalb
  /// wählt er dort selbst, über denselben Weg wie ein Klick auf eine Rufnummer
  /// in einer Behördenkarte: der Auftrag geht ans Tablet.
  final bool zurueckgeben;

  @override
  State<SipgateKontakteScreen> createState() => _SipgateKontakteScreenState();
}

class _SipgateKontakteScreenState extends State<SipgateKontakteScreen> {
  final TextEditingController _suche = TextEditingController();
  Timer? _tippPause;

  bool _laedt = true;
  String? _fehler;
  String _kategorie = '';
  List<Map<String, dynamic>> _kontakte = const [];
  Map<String, int> _kategorien = const {};
  int _gesamt = 0;

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
      final a = await ApiService().sipgateAction({
        'action': 'kontakte',
        'suche': _suche.text.trim(),
        'kategorie': _kategorie,
        'limit': 300,
      });
      if (!mounted || meine != _abfrage) return;
      setState(() {
        _laedt = false;
        if (a['success'] != true) {
          _fehler = '${a['message'] ?? 'Die Kontakte konnten nicht geladen werden'}';
          return;
        }
        // Flach, kein `data`, und `kategorien` kann Liste ODER Objekt sein —
        // beides hängt an einer Stelle, die dafür Tests hat.
        final gelesen = SipgateService.kontakteAusAntwort(a);
        _kontakte = gelesen.kontakte;
        _kategorien = gelesen.kategorien;
        _gesamt = gelesen.gesamt;
      });
    } catch (e) {
      if (!mounted || meine != _abfrage) return;
      setState(() {
        _laedt = false;
        _fehler = 'Die Kontakte konnten nicht geladen werden: $e';
      });
    }
  }

  void _sucheGeaendert(String _) {
    // Nicht bei jedem Buchstaben zum Server: die Suche läuft über fünfzig
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

  // ── Eigene Kontakte ────────────────────────────────────────────────────────

  Future<void> _bearbeiten([Map<String, dynamic>? vorhanden]) async {
    final name = TextEditingController(text: '${vorhanden?['name'] ?? ''}');
    final nummer = TextEditingController(text: '${vorhanden?['nummer'] ?? ''}');
    final notiz = TextEditingController(text: '${vorhanden?['notiz'] ?? ''}');

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
                controller: nummer,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Rufnummer',
                  hintText: '0731 970 49-214',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notiz,
                decoration: const InputDecoration(
                  labelText: 'Notiz (freiwillig)',
                  hintText: 'Durchwahl, erreichbar Di + Do',
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
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Speichern')),
        ],
      ),
    );

    if (speichern != true) return;
    final a = await ApiService().sipgateAction({
      'action': 'kontakt_save',
      if (vorhanden?['id'] != null) 'id': vorhanden!['id'],
      'name': name.text,
      'nummer': nummer.text,
      'notiz': notiz.text,
    });
    if (a['success'] == true) {
      _melde(vorhanden == null ? 'Kontakt angelegt' : 'Kontakt geändert');
      await _laden();
    } else {
      // Die Meldung kommt wörtlich vom Server — dort stehen die Gründe, die
      // hier niemand nachbilden sollte („Notrufnummern gehen nicht über
      // sipgate", „Diesen Kontakt gibt es schon").
      _melde('${a['message'] ?? 'Speichern fehlgeschlagen'}', fehler: true);
    }
  }

  /// Auf dem Rechner: Auftrag ans Telefon — aber erst nach einer Rückfrage.
  ///
  /// ⚠️ Eine Liste, die beim Antippen sofort wählt, ruft irgendwann das Gericht
  /// an, weil jemand die Zeile darunter treffen wollte. Ein Anruf lässt sich
  /// nicht zurücknehmen, also steht hier eine Frage mit Namen UND Nummer.
  Future<void> _fernwaehlen(Map<String, dynamic> k) async {
    final name = '${k['name'] ?? ''}';
    final nummer = '${k['nummer'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Anrufen?'),
        content: Text('$name\n${SipgateService.anruferAnzeige(nummer)}\n\n'
            'Der Auftrag geht an das Telefon, das die Fernwahl übernimmt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            icon: const Icon(Icons.call, size: 18),
            label: const Text('Anrufen'),
            onPressed: () => Navigator.pop(d, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await PhoneCallService.call(context, nummer, label: name);
  }

  Future<void> _loeschen(Map<String, dynamic> k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Kontakt löschen?'),
        content: Text('„${k['name']}" wird aus den eigenen Kontakten entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final a = await ApiService().sipgateAction({'action': 'kontakt_delete', 'id': k['id']});
    if (a['success'] == true) {
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
        title: const Text('Kontakte'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _bearbeiten(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Eigener Kontakt'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _suche,
              onChanged: _sucheGeaendert,
              decoration: InputDecoration(
                hintText: 'Name oder Rufnummer',
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
                label: Text('${SipgateService.kategorieName(e.key)} (${e.value})'),
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
              OutlinedButton(onPressed: _laden, child: const Text('Nochmal versuchen')),
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
                ? 'Noch keine Kontakte.'
                : 'Nichts gefunden zu „${_suche.text.trim()}".',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }

    // Der Server liefert mehr, als der Bildschirm zeigt, wenn es viele sind —
    // das steht dann auch da, statt still abgeschnitten zu werden.
    final gekuerzt = _gesamt > _kontakte.length;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
      itemCount: _kontakte.length + (gekuerzt ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i >= _kontakte.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              'Es gibt $_gesamt Treffer; angezeigt werden ${_kontakte.length}. '
              'Suchen grenzt ein.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          );
        }
        return _zeile(_kontakte[i]);
      },
    );
  }

  Widget _zeile(Map<String, dynamic> k) {
    final eigen = k['eigen'] == true;
    final name = '${k['name'] ?? ''}';
    final nummer = '${k['nummer'] ?? ''}';
    final notiz = '${k['notiz'] ?? ''}';
    final kategorie = '${k['kategorie'] ?? ''}';

    return ListTile(
      dense: true,
      tileColor: Colors.white,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: eigen ? Colors.indigo.shade50 : Colors.grey.shade200,
        child: Icon(
          _symbol(kategorie),
          size: 18,
          color: eigen ? Colors.indigo.shade700 : Colors.grey.shade700,
        ),
      ),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        [
          // Die Nummer gehört sichtbar dazu: unter einem Namen wie „Amtsgericht
          // Ulm" liegen mehrere Anschlüsse, und man will vor dem Wählen sehen,
          // welchen man erwischt.
          SipgateService.anruferAnzeige(nummer),
          if (notiz.isNotEmpty) notiz,
          SipgateService.kategorieName(kategorie),
        ].join(' · '),
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eigen)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade700),
              onSelected: (w) => w == 'aendern' ? _bearbeiten(k) : _loeschen(k),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'aendern', child: Text('Ändern')),
                PopupMenuItem(value: 'loeschen', child: Text('Löschen')),
              ],
            ),
          IconButton(
            icon: Icon(Icons.call, color: Colors.green.shade700),
            tooltip: widget.zurueckgeben ? 'Nummer übernehmen' : 'Anrufen',
            onPressed: () => _waehlen(k),
          ),
        ],
      ),
      onTap: () => _waehlen(k),
    );
  }

  void _waehlen(Map<String, dynamic> k) {
    if (widget.zurueckgeben) {
      Navigator.pop(context, '${k['nummer'] ?? ''}');
    } else {
      _fernwaehlen(k);
    }
  }

  IconData _symbol(String kategorie) => switch (kategorie) {
        'eigen' => Icons.person,
        'mitglied' => Icons.badge_outlined,
        'arzt' => Icons.medical_services_outlined,
        'klinik' => Icons.local_hospital_outlined,
        'apotheke' => Icons.local_pharmacy_outlined,
        'sanitaetshaus' => Icons.accessible_outlined,
        'pflege' => Icons.volunteer_activism_outlined,
        'kasse' => Icons.health_and_safety_outlined,
        'behoerde' => Icons.account_balance_outlined,
        'gericht' => Icons.gavel_outlined,
        'polizei' => Icons.local_police_outlined,
        'rettung' => Icons.emergency_outlined,
        'bank' => Icons.account_balance_wallet_outlined,
        'versicherung' => Icons.shield_outlined,
        'vermieter' => Icons.home_work_outlined,
        'arbeitgeber' => Icons.work_outline,
        'bildung' => Icons.school_outlined,
        'dienstleister' => Icons.handyman_outlined,
        'verein' => Icons.groups_outlined,
        _ => Icons.contact_phone_outlined,
      };
}
