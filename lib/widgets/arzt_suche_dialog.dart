import 'package:flutter/material.dart';

import '../utils/app_farben.dart';
import '../utils/fachrichtung_map.dart';
import 'phone_link.dart';

/// Eine Abfrage auf einen Ärzte-Katalog.
///
/// `null` heisst „der Aufruf ist gescheitert", eine leere Liste heisst
/// „nichts gefunden". ⚠️ Beides als leere Liste zu behandeln war die zweite
/// Hälfte des Fehlers, der diese Datei ausgelöst hat: der Mensch sah „gibt es
/// nicht", wo in Wahrheit gar nicht gesucht worden war.
typedef ArztKatalogAbfrage = Future<List<Map<String, dynamic>>?> Function(String suche);

/// Macht aus einem `api_service`-Aufruf eine [ArztKatalogAbfrage].
///
/// [schluessel] ist der Feldname in der Antwort (`data` bei den
/// Praxis-Katalogen, `kliniken` bei `searchKliniken`), [abbilden] eine
/// optionale Umbenennung der Spalten (siehe `klinikAlsArzt`).
ArztKatalogAbfrage arztKatalog(
  Future<Map<String, dynamic>> Function(String suche) aufruf, {
  String schluessel = 'data',
  Map<String, dynamic> Function(Map<String, dynamic>)? abbilden,
}) {
  return (String suche) async {
    final res = await aufruf(suche);
    if (res['success'] != true || res[schluessel] == null) return null;
    final list = List<Map<String, dynamic>>.from(res[schluessel]);
    return abbilden == null ? list : list.map(abbilden).toList();
  };
}

/// Die Lupe „Arzt aus Datenbank auswählen" — EINMAL.
///
/// 🔴 SIE STAND SECHSMAL DA.
/// `gesundheit_tab_content`, Augenarzt, HNO, Rheumatologie, MD und Krankenhaus
/// trugen je eine eigene Fassung, die sich untereinander um zwei bis sieben
/// Zeilen unterschied: Titel, Platzhalter und der abgefragte Katalog. Genau so
/// entsteht der Fehler, der diese Datei ausgelöst hat — er wurde in einer
/// Kopie behoben und blieb in den anderen fünf stehen, ohne dass irgendetwas
/// fehlschlug.
class ArztSucheDialog {
  /// Öffnet die Lupe und ruft [onSelect] mit der gewählten Zeile auf.
  ///
  /// [fachrichtung] grenzt die Liste ein — in der Schreibweise der Oberfläche,
  /// [fachrichtungPasst] übersetzt auf die der Datenbank. **Leer heisst: nicht
  /// eingrenzen und keinen Schalter zeigen.**
  ///
  /// ⚠️ Hier gehört NUR ein echtes Fach hinein. Der alte Parameter war
  /// überladen: er entschied zugleich „ist das eine Klinik?" und diente als
  /// Filter, weshalb Angaben wie `'Klinik / Stationäre Behandlung'` oder
  /// `'Begutachtungsdienst der Kranken-/Pflegekassen (MD, ehem. MDK)'` als
  /// Fachrichtung gesucht worden wären — und nichts gefunden hätten. Welcher
  /// Katalog gefragt wird, entscheidet jetzt allein [katalog].
  static void oeffnen({
    required BuildContext context,
    required ArztKatalogAbfrage katalog,
    required void Function(Map<String, dynamic> arzt) onSelect,
    String fachrichtung = '',
    bool nurFachVoreinstellung = true,
    String titel = 'Arzt aus Datenbank auswählen',
    String platzhalter = 'Name, Praxis oder Ort suchen...',
    String? vorbelegteSuche,
    /// Weg aus einer leeren Liste: nimmt den aktuellen Suchtext entgegen und
    /// gibt die neu angelegte Zeile zurück, oder `null` bei Abbruch. Ist er
    /// gesetzt, erscheint ein Knopf — in der Leiste UND mitten in der leeren
    /// Liste, wo der Mensch tatsächlich feststeckt.
    Future<Map<String, dynamic>?> Function(String suchtext)? onAnlegen,
    String anlegenBeschriftung = 'Aufnehmen',
  }) {
    final searchController = TextEditingController(text: vorbelegteSuche ?? '');
    // `alle` ist alles, was der Katalog zur Sucheingabe hergibt; `results` ist
    // davon der angezeigte Teil. Beide Zahlen werden gebraucht: nur aus ihrem
    // Verhältnis lässt sich sagen, ob die Liste leer ist, WEIL gefiltert wurde.
    List<Map<String, dynamic>> alle = [];
    List<Map<String, dynamic>> results = [];
    bool isLoading = false;
    bool initialLoaded = false;
    bool fehler = false;
    final hatFach = fachrichtung.trim().isNotEmpty;
    bool nurFach = nurFachVoreinstellung && hatFach;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // ⚠️ Es wird NICHT serverseitig gefiltert, obwohl der Endpunkt es
            // könnte. Der Serverfilter ist exakte Gleichheit auf EINEN Wert und
            // findet damit von drei Schreibweisen desselben Fachs nur eine.
            // Hier liegen ohnehin alle Zeilen vor — bei der Grössenordnung
            // dieser Kataloge (Dutzende, nicht Zehntausende) ist die Auswahl im
            // Gerät die genauere und die ehrlichere: sie kann sagen, wie viele
            // Einträge der Filter weggenommen hat.
            void filtern() {
              results = nurFach
                  ? alle
                      .where((a) => fachrichtungPasst(
                          fachrichtung, a['fachrichtung']?.toString() ?? ''))
                      .toList()
                  : List<Map<String, dynamic>>.from(alle);
            }

            Future<void> doSearch() async {
              setDialogState(() { isLoading = true; fehler = false; });
              try {
                final liste = await katalog(searchController.text.trim());
                setDialogState(() {
                  alle = liste ?? [];
                  filtern();
                  fehler = liste == null;
                  isLoading = false;
                });
              } catch (e) {
                debugPrint('[AERZTE-DIALOG] Error: $e');
                setDialogState(() {
                  alle = [];
                  results = [];
                  fehler = true;
                  isLoading = false;
                });
              }
            }

            // Auto-load on first open only
            if (!initialLoaded) {
              initialLoaded = true;
              Future.microtask(() => doSearch());
            }

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.search, color: F.h(Colors.teal, 700)),
                  const SizedBox(width: 8),
                  // ⚠️ Ein Dialogtitel hat nur die Dialogbreite minus
                  // Innenabstand — auf einem 448-dp-Telefon rund 320 dp.
                  Expanded(
                    child: Text(titel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16)),
                  ),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: platzhalter,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search, color: Colors.teal),
                          onPressed: doSearch,
                        ),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => doSearch(),
                    ),
                    // ── Der Ausweg aus einer zu engen Liste ──
                    // ⚠️ Ohne ihn ist eine leere Liste eine Sackgasse: sie sagt
                    // weder, dass gefiltert wurde, noch wonach.
                    if (hatFach) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilterChip(
                              label: Text('Nur $fachrichtung',
                                  style: const TextStyle(fontSize: 11)),
                              selected: nurFach,
                              visualDensity: VisualDensity.compact,
                              onSelected: (v) => setDialogState(() {
                                nurFach = v;
                                filtern();
                              }),
                            ),
                            if (nurFach && alle.length != results.length)
                              Text('${alle.length - results.length} ausgeblendet',
                                  style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : results.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          fehler
                                              ? 'Die Datenbank hat nicht geantwortet'
                                              : 'Keine Ärzte gefunden',
                                          style: TextStyle(color: F.h(Colors.grey, 500)),
                                          textAlign: TextAlign.center,
                                        ),
                                        // Die GEMESSENE Auskunft statt einer
                                        // gepflegten Liste „Fächer ohne Eintrag":
                                        // eine solche Liste veraltet still, sobald
                                        // jemand eine Praxis anlegt.
                                        if (onAnlegen != null) ...[
                                          const SizedBox(height: 12),
                                          FilledButton.icon(
                                            icon: const Icon(Icons.add_business, size: 16),
                                            label: Text(anlegenBeschriftung),
                                            onPressed: () async {
                                              final neu = await onAnlegen(searchController.text.trim());
                                              if (neu == null) return;
                                              if (ctx.mounted) Navigator.of(ctx).pop();
                                              onSelect(neu);
                                            },
                                          ),
                                        ],
                                        if (!fehler && nurFach && alle.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Kein Eintrag mit der Fachrichtung „$fachrichtung" — '
                                            '${alle.length} andere sind vorhanden. '
                                            'Dafür oben den Filter abschalten.',
                                            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: results.length,
                                  itemBuilder: (ctx, i) {
                                    final arzt = results[i];
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: F.h(Colors.teal, 100),
                                          child: Icon(Icons.local_hospital, color: F.h(Colors.teal, 700), size: 20),
                                        ),
                                        title: Text(arzt['praxis_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${arzt['arzt_name'] ?? ''}${arzt['weitere_aerzte']?.isNotEmpty == true ? ', ${arzt['weitere_aerzte']}' : ''}',
                                                style: const TextStyle(fontSize: 12)),
                                            Text('${arzt['strasse'] ?? ''}, ${arzt['plz_ort'] ?? ''}',
                                                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                                            if (arzt['telefon']?.isNotEmpty == true)
                                              PhoneText(arzt['telefon']?.toString(), prefix: 'Tel: ', label: arzt['arzt_name']?.toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                                            if ((arzt['lanr']?.isNotEmpty == true) || (arzt['bsnr']?.isNotEmpty == true))
                                              Padding(
                                                padding: const EdgeInsets.only(top: 3),
                                                child: Wrap(spacing: 6, children: [
                                                  if (arzt['lanr']?.isNotEmpty == true)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(color: F.h(Colors.indigo, 50), borderRadius: BorderRadius.circular(4), border: Border.all(color: F.h(Colors.indigo, 200))),
                                                      child: Text('LANR: ${arzt['lanr']}', style: TextStyle(fontSize: 10, color: F.h(Colors.indigo, 700), fontWeight: FontWeight.w600)),
                                                    ),
                                                  if (arzt['bsnr']?.isNotEmpty == true)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(color: F.h(Colors.purple, 50), borderRadius: BorderRadius.circular(4), border: Border.all(color: F.h(Colors.purple, 200))),
                                                      child: Text('BSNR: ${arzt['bsnr']}', style: TextStyle(fontSize: 10, color: F.h(Colors.purple, 700), fontWeight: FontWeight.w600)),
                                                    ),
                                                ]),
                                              ),
                                          ],
                                        ),
                                        isThreeLine: true,
                                        onTap: () {
                                          Navigator.of(ctx).pop();
                                          onSelect(arzt);
                                        },
                                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (onAnlegen != null)
                  TextButton.icon(
                    icon: const Icon(Icons.add_business, size: 16),
                    label: Text(anlegenBeschriftung),
                    onPressed: () async {
                      final neu = await onAnlegen(searchController.text.trim());
                      if (neu == null) return;
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      onSelect(neu);
                    },
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Abbrechen'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
