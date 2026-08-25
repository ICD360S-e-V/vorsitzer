import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';

/// Ein einzelner Vorschlag aus einem hochgeladenen Laborbefund.
///
/// ⚠️ [uebernehmbar] und [vorbelegt] sind zwei verschiedene Dinge. Ein Wert
/// kann übernehmbar sein und trotzdem nicht angehakt: dann hat der Server
/// etwas gemeldet, das ein Mensch ansehen sollte — eine Warnung, oder ein
/// Feld, das schon einen anderen Wert trägt.
class BlutVorschlag {
  final String key;
  final String label;
  final String einheit;
  final String? wert;
  final String quellzeile;
  final String? warnung;
  final bool umgerechnet;
  final String? geleseneEinheit;
  final bool bestaetigt;
  final bool qualitativ;
  final String bisher;

  bool gewaehlt;

  BlutVorschlag({
    required this.key,
    required this.label,
    required this.einheit,
    required this.wert,
    required this.quellzeile,
    required this.warnung,
    required this.umgerechnet,
    required this.geleseneEinheit,
    required this.bestaetigt,
    required this.qualitativ,
    required this.bisher,
    required this.gewaehlt,
  });

  bool get uebernehmbar => wert != null && wert!.isNotEmpty;
  bool get ueberschreibt => bisher.isNotEmpty && bisher != wert;
}

/// Serverantwort in Vorschläge übersetzen.
///
/// Bewusst als freie Funktion und nicht im Widget: so ist die Entscheidung
/// „was wird vorangehakt" prüfbar, ohne eine Oberfläche zu bauen.
///
/// ⚠️ Die Antwort wird defensiv gelesen. `api/admin/gesundheit_blut_ocr.php`
/// liefert Listen über `array_values()`, aber ein PHP-Array ohne Lücken wird
/// zur JSON-Liste und eines mit Lücken zum Objekt — ein `as List` wäre genau
/// die Falle, die den Speedtest-Schirm grau gemacht hat.
List<BlutVorschlag> blutVorschlaegeAufbereiten(
  dynamic rohWerte,
  Map<String, String> aktuelleWerte,
) {
  if (rohWerte is! List) return const [];
  final liste = <BlutVorschlag>[];

  for (final eintrag in rohWerte) {
    if (eintrag is! Map) continue;
    final key = eintrag['key']?.toString() ?? '';
    if (key.isEmpty) continue;

    final rohWert = eintrag['wert'];
    final wert = (rohWert == null || rohWert.toString().trim().isEmpty)
        ? null
        : rohWert.toString().trim();
    final warnung = eintrag['warnung']?.toString().trim();
    final bisher = (aktuelleWerte[key] ?? '').trim();
    final bestaetigt = eintrag['bestaetigt'] == true;

    final v = BlutVorschlag(
      key: key,
      label: eintrag['label']?.toString() ?? key,
      einheit: eintrag['einheit']?.toString() ?? '',
      wert: wert,
      quellzeile: eintrag['zeile']?.toString() ?? '',
      warnung: (warnung == null || warnung.isEmpty) ? null : warnung,
      umgerechnet: eintrag['umgerechnet'] == true,
      geleseneEinheit: eintrag['gelesene_einheit']?.toString(),
      bestaetigt: bestaetigt,
      qualitativ: eintrag['qualitativ'] == true,
      bisher: bisher,
      gewaehlt: false,
    );

    // Vorangehakt wird nur, was nichts zu prüfen hinterlässt: ein Wert, den
    // beide Lesungen tragen, ohne Warnung, in ein leeres Feld.
    v.gewaehlt = v.uebernehmbar &&
        v.warnung == null &&
        bestaetigt &&
        bisher.isEmpty;

    liste.add(v);
  }

  liste.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return liste;
}

/// Knopf „Werte aus Dokument lesen" samt Vorschlagsdialog.
///
/// ⚠️ Der Knopf schreibt nichts selbst. Er liefert die gewählten Werte an
/// [onUebernehmen]; gespeichert wird über den Weg, den der Dialog ohnehin
/// benutzt. Zwei Schreiber auf denselben verschlüsselten Datensatz würden
/// sich gegenseitig überschreiben, solange der Dialog offen ist.
class BlutwerteUebernahmeKnopf extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String gesundheitType;
  final String analyseId;

  /// Aktueller Stand der Eingabefelder, key -> Text. Entscheidet, was als
  /// „überschreibt" markiert und deshalb nicht vorangehakt wird.
  final Map<String, String> Function() aktuelleWerte;

  /// numerisch, qualitativ — getrennt, weil das Formular sie getrennt hält.
  final void Function(Map<String, String> numerisch, Map<String, String> qualitativ)
      onUebernehmen;

  const BlutwerteUebernahmeKnopf({
    super.key,
    required this.apiService,
    required this.userId,
    required this.gesundheitType,
    required this.analyseId,
    required this.aktuelleWerte,
    required this.onUebernehmen,
  });

  @override
  State<BlutwerteUebernahmeKnopf> createState() => _BlutwerteUebernahmeKnopfState();
}

class _BlutwerteUebernahmeKnopfState extends State<BlutwerteUebernahmeKnopf> {
  bool _laeuft = false;

  Future<void> _lesen() async {
    if (_laeuft) return;
    setState(() => _laeuft = true);
    try {
      final antwort = await widget.apiService.gesundheitBlutOcr(
        userId: widget.userId,
        gesundheitType: widget.gesundheitType,
        analyseId: widget.analyseId,
      );
      if (!mounted) return;

      if (antwort['success'] != true) {
        _melden(antwort['message']?.toString() ?? 'Der Befund liess sich nicht lesen',
            Colors.orange);
        return;
      }

      final vorschlaege =
          blutVorschlaegeAufbereiten(antwort['werte'], widget.aktuelleWerte());
      final ohneFeld = antwort['ohne_feld'] is List
          ? (antwort['ohne_feld'] as List).whereType<Map>().toList()
          : const <Map>[];
      final dokumente = antwort['dokumente'] is List
          ? (antwort['dokumente'] as List).whereType<Map>().toList()
          : const <Map>[];

      if (vorschlaege.isEmpty) {
        final fehler = dokumente
            .map((d) => d['fehler']?.toString())
            .where((f) => f != null && f.isNotEmpty)
            .join(' · ');
        _melden(
          fehler.isNotEmpty
              ? 'Kein Wert gefunden — $fehler'
              : 'Im Dokument war kein bekannter Laborwert zu finden.',
          Colors.orange,
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (_) => _VorschlagDialog(
          vorschlaege: vorschlaege,
          ohneFeld: ohneFeld,
          dokumente: dokumente,
          onUebernehmen: widget.onUebernehmen,
        ),
      );
    } catch (e) {
      if (mounted) _melden('Fehler beim Lesen: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  void _melden(String text, Color farbe) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: farbe, duration: const Duration(seconds: 5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: F.h(Colors.teal, 50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: F.h(Colors.teal, 200)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high, size: 20, color: F.h(Colors.teal, 700)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Werte aus dem Befund lesen',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: F.h(Colors.teal, 800))),
                Text('Liest das hochgeladene Dokument und schlägt Werte vor — nichts wird ohne Bestätigung eingetragen.',
                    style: TextStyle(fontSize: 10.5, color: F.h(Colors.teal, 600))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _laeuft ? null : _lesen,
            icon: _laeuft
                ? const SizedBox(
                    width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.document_scanner, size: 15),
            label: Text(_laeuft ? 'Wird gelesen …' : 'Lesen',
                style: const TextStyle(fontSize: 11.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: F.h(Colors.teal, 600),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _VorschlagDialog extends StatefulWidget {
  final List<BlutVorschlag> vorschlaege;
  final List<Map> ohneFeld;
  final List<Map> dokumente;
  final void Function(Map<String, String>, Map<String, String>) onUebernehmen;

  const _VorschlagDialog({
    required this.vorschlaege,
    required this.ohneFeld,
    required this.dokumente,
    required this.onUebernehmen,
  });

  @override
  State<_VorschlagDialog> createState() => _VorschlagDialogState();
}

class _VorschlagDialogState extends State<_VorschlagDialog> {
  int get _gewaehlt => widget.vorschlaege.where((v) => v.gewaehlt).length;

  void _uebernehmen() {
    final numerisch = <String, String>{};
    final qualitativ = <String, String>{};
    for (final v in widget.vorschlaege) {
      if (!v.gewaehlt || !v.uebernehmbar) continue;
      (v.qualitativ ? qualitativ : numerisch)[v.key] = v.wert!;
    }
    widget.onUebernehmen(numerisch, qualitativ);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final quellen = widget.dokumente
        .map((d) => d['quelle']?.toString())
        .whereType<String>()
        .toSet();
    final ausOcr = quellen.any((q) => q.contains('ocr'));

    return AlertDialog(
      backgroundColor: F.flaeche,
      title: Row(
        children: [
          Icon(Icons.auto_fix_high, size: 20, color: F.h(Colors.teal, 700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Werte aus dem Befund',
                style: TextStyle(fontSize: 16, color: F.textStark)),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: ausOcr ? F.h(Colors.amber, 50) : F.h(Colors.green, 50),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                ausOcr
                    ? 'Aus einem Scan gelesen. Bitte jeden Wert gegen die Quellzeile prüfen — eine falsch erkannte Ziffer sieht im Feld aus wie jede andere.'
                    : 'Direkt aus der Textebene des PDF gelesen, ohne Zeichenerkennung.',
                style: TextStyle(
                    fontSize: 11,
                    color: ausOcr ? F.h(Colors.amber, 900) : F.h(Colors.green, 900)),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final v in widget.vorschlaege) _zeile(v),
                    if (widget.ohneFeld.isNotEmpty) _ohneFeldBlock(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _gewaehlt == 0 ? null : _uebernehmen,
          style: ElevatedButton.styleFrom(
            backgroundColor: F.h(Colors.teal, 600),
            foregroundColor: Colors.white,
          ),
          child: Text(_gewaehlt == 0
              ? 'Nichts ausgewählt'
              : '$_gewaehlt Wert${_gewaehlt == 1 ? '' : 'e'} übernehmen'),
        ),
      ],
    );
  }

  Widget _zeile(BlutVorschlag v) {
    final aus = !v.uebernehmbar;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: aus ? F.flaecheGedaempft : F.flaeche,
        border: Border.all(color: F.randLeise),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Checkbox(
              value: v.gewaehlt,
              onChanged: aus ? null : (b) => setState(() => v.gewaehlt = b ?? false),
              visualDensity: VisualDensity.compact,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(v.label,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: F.textStark)),
                    ),
                    Text(
                      aus ? '—' : '${v.wert} ${v.einheit}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: aus ? F.textLeise : F.h(Colors.teal, 800)),
                    ),
                  ],
                ),
                if (v.umgerechnet && v.geleseneEinheit != null)
                  Text('umgerechnet aus ${v.geleseneEinheit}',
                      style: TextStyle(fontSize: 10, color: F.textSchwach)),
                if (v.ueberschreibt)
                  Text('überschreibt den vorhandenen Wert ${v.bisher}',
                      style: TextStyle(fontSize: 10, color: F.h(Colors.orange, 800))),
                if (v.warnung != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(v.warnung!,
                        style: TextStyle(fontSize: 10, color: F.h(Colors.red, 700))),
                  ),
                if (v.quellzeile.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      v.quellzeile,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9.5, fontFamily: 'monospace', color: F.textLeise),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ohneFeldBlock() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: F.flaecheGedaempft,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Im Befund erkannt, aber es gibt kein Feld dafür',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: F.textStark)),
          const SizedBox(height: 3),
          Text(
            widget.ohneFeld
                .map((o) => o['name']?.toString() ?? o['key']?.toString() ?? '')
                .where((n) => n.isNotEmpty)
                .join(' · '),
            style: TextStyle(fontSize: 10.5, color: F.textSchwach),
          ),
        ],
      ),
    );
  }
}
