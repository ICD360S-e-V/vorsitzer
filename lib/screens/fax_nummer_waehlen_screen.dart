import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';

/// Was der Bildschirm zurückgibt: Nummer **und** Name.
///
/// Der Name allein wäre Beiwerk — er füllt aber das Feld „Empfänger (für den
/// Verlauf)", und ohne ihn stünde im Verlauf später nur eine Rufnummer. Ein
/// Jahr später ist „+49 731 1759175" keine Auskunft mehr.
class FaxZiel {
  final String nummer;
  final String name;
  const FaxZiel(this.nummer, this.name);
}

/// Die Kategoriezähler aus der Antwort.
///
/// ⚠️ PHP KENNT NUR EINEN ARRAY-TYP. `['arzt' => 53]` wird zu einem JSON-
/// **Objekt**, ein leeres Array aber zu einer JSON-**Liste** — nachgemessen an
/// der echten Antwort: `"kategorien":[]`, sobald die Suche nichts findet.
///
/// `as Map` darauf gibt nicht `null` zurück, sondern **wirft**. Im
/// Release-Build ist das eine graue Fläche ohne jede Meldung; genau so ist der
/// Speedtest-Bildschirm am 05.08.2026 ausgefallen. Deshalb eine eigene
/// Funktion, die beide Formen versteht — und ein Test darauf.
Map<String, int> faxKategorienAus(dynamic roh) {
  if (roh is Map) {
    return roh.map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0));
  }
  // Liste (also leer) oder gar nicht vorhanden: keine Kategorien.
  return const {};
}

/// Empfängerverzeichnis für das Fax — Nummern, die **Faxe annehmen**.
///
/// ⚠️ WARUM DAS NICHT DER TELEFONBILDSCHIRM IST
/// `SipgateKontakteScreen` sucht in den Sprachspalten und schließt Faxspalten
/// ausdrücklich aus („von einem Faxgerät ruft niemand an" — richtig, aber
/// dort). Der Knopf neben dem Faxfeld rief bis heute genau den auf und konnte
/// deshalb **nur Telefonnummern** in ein Faxfeld liefern.
///
/// Ein Fax an einen Sprachanschluss klingelt bei einem Menschen, der ein
/// Modempfeifen hört und auflegt: Minuten Wartezeit, Kosten, am Ende
/// „fehlgeschlagen" ohne erkennbaren Grund. Nachgemessen liegen **221
/// Faxnummern in 29 Tabellen**, und keine einzige war aus der App erreichbar.
///
/// ⚠️ Die eigene Faxnummer des Vereins ist serverseitig ausgeschlossen —
/// sie hier anzubieten hieße, sich selbst zu faxen.
///
/// ⚠️ GIBT EINE **LISTE** ZURÜCK, seit dem 24.08.2026. Vorher lieferte ein
/// Tipp genau ein Ziel und der Bildschirm schloss sich — wer denselben
/// Widerspruch an Jobcenter, Sozialamt und Anwalt faxen wollte, musste das
/// Verzeichnis dreimal öffnen und dreimal suchen, obwohl der Faxbildschirm
/// mehrere Ziele längst kann (`_weitereZiele`).
///
/// Der schnelle Weg bleibt schnell: ein Tipp auf die Zeile gibt weiterhin
/// sofort **eine** Nummer zurück. Das „+" daneben legt statt dessen in einen
/// Korb, der eine Suche überdauert — und erst der Korbknopf schließt.
class FaxNummerWaehlenScreen extends StatefulWidget {
  const FaxNummerWaehlenScreen({super.key});

  @override
  State<FaxNummerWaehlenScreen> createState() => _FaxNummerWaehlenScreenState();
}

class _FaxNummerWaehlenScreenState extends State<FaxNummerWaehlenScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _suche = TextEditingController();

  bool _lade = true;
  String _kategorie = '';
  List<Map<String, dynamic>> _kontakte = const [];
  Map<String, int> _kategorien = const {};
  int _gesamt = 0;

  /// Gesammelte Ziele. ⚠️ Lebt im Zustand und NICHT in der Liste: eine neue
  /// Suche lädt `_kontakte` komplett neu, und genau darum geht es — die drei
  /// Stellen eines Vorgangs stehen selten unter demselben Suchwort.
  final List<FaxZiel> _korb = [];

  /// Nur Ziffern, zum Vergleichen. `+49 731 1759175` und `0731 1759175`
  /// sind dieselbe Gegenstelle; zweimal gefaxt würde sie trotzdem.
  String _schluessel(String nummer) => nummer.replaceAll(RegExp(r'\D'), '');

  bool _imKorb(String nummer) {
    final k = _schluessel(nummer);
    return k.isNotEmpty && _korb.any((z) => _schluessel(z.nummer) == k);
  }

  void _korbUmschalten(String nummer, String name) {
    final k = _schluessel(nummer);
    if (k.isEmpty) return;
    setState(() {
      final drin = _korb.indexWhere((z) => _schluessel(z.nummer) == k);
      if (drin >= 0) {
        _korb.removeAt(drin);
      } else {
        _korb.add(FaxZiel(nummer, name));
      }
    });
  }

  /// ⚠️ Entprellt. Ohne das ginge je Tastendruck eine Anfrage über genau die
  /// Mobilfunkleitung, die an anderer Stelle dieses Projekts als zu langsam
  /// beanstandet wird — und die Antworten kämen in beliebiger Reihenfolge
  /// zurück, sodass die Liste zum vorletzten Buchstaben passt.
  Timer? _entprellen;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _entprellen?.cancel();
    _suche.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    setState(() => _lade = true);
    final r = await _api.sipgateFaxAction({
      'action': 'faxnummern',
      'suche': _suche.text.trim(),
      'kategorie': _kategorie,
      'limit': 400,
    }, timeout: const Duration(seconds: 30));
    if (!mounted) return;
    setState(() {
      _lade = false;
      if (r['success'] == true) {
        _kontakte = List<Map<String, dynamic>>.from(
            (r['kontakte'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e)));
        _gesamt = (r['gesamt'] as num?)?.toInt() ?? _kontakte.length;
        _kategorien = faxKategorienAus(r['kategorien']);
      } else {
        _kontakte = const [];
        _kategorien = const {};
        _gesamt = 0;
      }
    });
  }

  void _sucheGeaendert(String _) {
    _entprellen?.cancel();
    _entprellen = Timer(const Duration(milliseconds: 350), _laden);
  }

  IconData _symbol(String kategorie) => switch (kategorie) {
        'eigen' => Icons.person,
        'mitglied' => Icons.badge_outlined,
        'arzt' => Icons.medical_services_outlined,
        'klinik' => Icons.local_hospital_outlined,
        'apotheke' => Icons.local_pharmacy_outlined,
        'pflege' => Icons.volunteer_activism_outlined,
        'kasse' => Icons.health_and_safety_outlined,
        'behoerde' => Icons.account_balance_outlined,
        'gericht' => Icons.gavel_outlined,
        'polizei' => Icons.local_police_outlined,
        'versicherung' => Icons.shield_outlined,
        'bank' => Icons.account_balance_wallet_outlined,
        'arbeitgeber' => Icons.work_outline,
        'bildung' => Icons.school_outlined,
        'vermieter' => Icons.home_work_outlined,
        'dienstleister' => Icons.handyman_outlined,
        'verein' => Icons.groups_outlined,
        _ => Icons.print_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Faxnummer wählen'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _suche,
                  onChanged: _sucheGeaendert,
                  decoration: InputDecoration(
                    hintText: 'Name oder Nummer',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _suche.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Suche leeren',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _suche.clear();
                              _laden();
                            },
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _chip('', 'Alle', _gesamt),
                    for (final e in _kategorien.entries)
                      _chip(e.key, e.key, e.value),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _lade
          ? const Center(child: CircularProgressIndicator())
          : _kontakte.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _suche.text.trim().isEmpty
                          ? 'Keine Faxnummern in den Stammdaten.'
                          : 'Nichts gefunden zu „${_suche.text.trim()}".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: F.h(Colors.grey, 600)),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _kontakte.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final k = _kontakte[i];
                    final name = '${k['name'] ?? ''}';
                    final nummer = '${k['nummer'] ?? ''}';
                    final gesammelt = _imKorb(nummer);
                    return ListTile(
                      leading: Icon(_symbol('${k['kategorie'] ?? ''}')),
                      title: Text(name),
                      subtitle: Text(nummer),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (k['eigen'] == true)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            // ⚠️ Der Stern trug seine Bedeutung allein in der
                            // Form. Ein Bildschirmleser bekam gar nichts —
                            // und damit fehlte ausgerechnet der Hinweis, dass
                            // diese Nummer eine eigene ist.
                            child: Icon(Icons.star, size: 16,
                                semanticLabel: 'Eigene Nummer des Vereins'),
                          ),
                        IconButton(
                          // ⚠️ 44 dp Trefferfläche (WCAG 2.5.5) — in diesem
                          // Verein keine Feinheit.
                          constraints:
                              const BoxConstraints(minWidth: 44, minHeight: 44),
                          icon: Icon(
                              gesammelt
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                              size: 22),
                          color: gesammelt ? F.h(Colors.green, 700) : null,
                          tooltip: gesammelt
                              ? 'Aus der Auswahl nehmen'
                              : 'Zur Auswahl hinzufügen',
                          onPressed: () => _korbUmschalten(nummer, name),
                        ),
                      ]),
                      onTap: () => Navigator.pop(
                          context, <FaxZiel>[FaxZiel(nummer, name)]),
                    );
                  },
                ),
      // ⚠️ Steht nur da, wenn etwas im Korb ist. Eine dauerhaft sichtbare
      // Leiste mit „0 übernehmen" wäre ein Knopf, der nie etwas tut.
      bottomNavigationBar: _korb.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _korb.map((z) => z.name.isEmpty ? z.nummer : z.name)
                          .join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: Text(_korb.length == 1
                        ? '1 übernehmen'
                        : '${_korb.length} übernehmen'),
                    onPressed: () =>
                        Navigator.pop(context, List<FaxZiel>.from(_korb)),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _chip(String wert, String text, int anzahl) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text('$text ($anzahl)'),
          selected: _kategorie == wert,
          onSelected: (_) {
            setState(() => _kategorie = wert);
            _laden();
          },
        ),
      );
}
