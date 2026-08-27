import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../utils/arzt_quelle.dart';

/// Aufnehmen und Ergänzen eines Eintrags im Klinik-Katalog
/// (`kliniken_datenbank`).
///
/// 🔴 WARUM ES DAS GIBT
/// Der Krankenhaus-Reiter liest ausschliesslich aus diesem Katalog, und der war
/// bis zum 26.08.2026 nur lesbar: `kliniken_manage.php` kannte allein `search`.
/// Gespeichert sind 144 Abteilungen aus **sechs** Häusern, alle im Raum
/// Ulm/Neu-Ulm/Tübingen. Wer anderswo behandelt wurde — Stuttgart, Augsburg,
/// eine Reha — war schlicht nicht erfassbar: die Lupe fand nichts, und
/// anzulegen ging auch nichts.
///
/// ⚠️ Kein Löschen. Auf diese Einträge berufen sich Vollmachten und
/// Schweigepflichtentbindungen; der Endpunkt kennt die Aktion gar nicht.
class KlinikFormular {
  /// Legt eine Klinik an. Gibt die gespeicherte Zeile zurück, oder `null`.
  static Future<Map<String, dynamic>?> anlegen(
    BuildContext context,
    ApiService api, {
    String? vorbelegterName,
  }) =>
      _oeffnen(context, api, null, vorbelegterName);

  /// Ergänzt eine vorhandene Klinik. Gibt die gespeicherte Zeile zurück.
  static Future<Map<String, dynamic>?> bearbeiten(
    BuildContext context,
    ApiService api,
    Map<String, dynamic> klinik,
  ) =>
      _oeffnen(context, api, klinik, null);

  static Future<Map<String, dynamic>?> _oeffnen(
    BuildContext context,
    ApiService api,
    Map<String, dynamic>? vorhanden,
    String? vorbelegterName,
  ) async {
    final bearbeiten = vorhanden != null;
    // ⚠️ Im Katalog heisst die Abteilung `name` und das Haus `krankenhaus`.
    // Die Arzt-Widgets sehen davon `arzt_name` und `praxis_name` — das ist die
    // Abbildung aus `klinikAlsArzt`. Hier stehen die ECHTEN Spaltennamen, weil
    // genau sie an den Endpunkt gehen.
    String v(String feld, [String ersatz = '']) =>
        (vorhanden?[feld]?.toString() ?? ersatz);

    final felder = <String, TextEditingController>{
      'krankenhaus': TextEditingController(text: v('krankenhaus')),
      'name': TextEditingController(text: v('name', vorbelegterName ?? '')),
      'fachrichtung': TextEditingController(text: v('fachrichtung')),
      'strasse': TextEditingController(text: v('strasse')),
      'plz_ort': TextEditingController(text: v('plz_ort')),
      'telefon': TextEditingController(text: v('telefon')),
      'notaufnahme_telefon': TextEditingController(text: v('notaufnahme_telefon')),
      'fax': TextEditingController(text: v('fax')),
      'email': TextEditingController(text: v('email')),
      'website': TextEditingController(text: v('website')),
      'online_termin_url': TextEditingController(text: v('online_termin_url')),
      'lanr': TextEditingController(text: v('lanr')),
      'bsnr': TextEditingController(text: v('bsnr')),
      'sprechzeiten': TextEditingController(text: v('sprechzeiten')),
      'notizen': TextEditingController(text: v('notizen')),
    };

    const beschriftung = <String, String>{
      'krankenhaus': 'Haus / Klinikum',
      'name': 'Abteilung',
      'fachrichtung': 'Fachrichtung',
      'strasse': 'Strasse',
      'plz_ort': 'PLZ Ort',
      'telefon': 'Telefon',
      'notaufnahme_telefon': 'Notaufnahme',
      'fax': 'Fax',
      'email': 'E-Mail',
      'website': 'Website',
      'online_termin_url': 'Terminportal (URL)',
      'lanr': 'LANR',
      'bsnr': 'BSNR',
      'sprechzeiten': 'Sprechzeiten',
      'notizen': 'Notizen',
    };

    const mehrzeilig = {'sprechzeiten', 'notizen'};

    /// Neun Ziffern, oder leer. Dieselbe Regel wie im Endpunkt — hier nur,
    /// damit der Hinweis am Feld steht statt in einer Fehlermeldung nach dem
    /// Absenden.
    String? nummerPruefen(String? wert) {
      final w = (wert ?? '').trim();
      if (w.isEmpty) return null;
      return RegExp(r'^\d{9}$').hasMatch(w) ? null : 'genau neun Ziffern';
    }

    final formKey = GlobalKey<FormState>();
    bool laeuft = false;
    String? fehler;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Row(children: [
            Icon(bearbeiten ? Icons.edit_location_alt : Icons.add_business,
                size: 20, color: F.h(Colors.teal, 700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(bearbeiten ? 'Klinikdaten ergänzen' : 'Klinik aufnehmen',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16)),
            ),
          ]),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Der Eintrag steht danach für alle Mitglieder zur Auswahl.',
                      style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final e in felder.entries) ...[
                    TextFormField(
                      controller: e.value,
                      maxLines: mehrzeilig.contains(e.key) ? 3 : 1,
                      keyboardType: (e.key == 'lanr' || e.key == 'bsnr')
                          ? TextInputType.number
                          : TextInputType.text,
                      validator: (e.key == 'lanr' || e.key == 'bsnr')
                          ? nummerPruefen
                          : null,
                      decoration: InputDecoration(
                        labelText: beschriftung[e.key],
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (fehler != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(fehler!,
                          style: TextStyle(fontSize: 12, color: F.h(Colors.red, 700))),
                    ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: laeuft ? null : () => Navigator.pop(ctx),
                child: const Text('Abbrechen')),
            FilledButton(
              onPressed: laeuft
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      // Ohne einen der beiden Namen wäre der Eintrag in der
                      // Trefferliste namenlos.
                      if (felder['name']!.text.trim().isEmpty &&
                          felder['krankenhaus']!.text.trim().isEmpty) {
                        setS(() => fehler = 'Haus oder Abteilung muss einen Namen haben.');
                        return;
                      }
                      setS(() { laeuft = true; fehler = null; });
                      final daten = <String, dynamic>{
                        'action': bearbeiten ? 'update' : 'add',
                        if (bearbeiten) 'id': vorhanden['id'],
                        for (final e in felder.entries) e.key: e.value.text.trim(),
                      };
                      final res = await api.manageKlinik(daten);
                      if (!ctx.mounted) return;
                      if (res['success'] == true && res['klinik'] != null) {
                        // ⚠️ Mit der Herkunftsmarke zurückgeben: der Aufrufer
                        // legt die Zeile als `selected_arzt` ab, und ohne Marke
                        // frischt er sie später aus der falschen Tabelle auf.
                        Navigator.pop(ctx,
                            klinikAlsArzt(Map<String, dynamic>.from(res['klinik'] as Map)));
                      } else {
                        setS(() {
                          laeuft = false;
                          fehler = res['message']?.toString() ?? 'Speichern fehlgeschlagen.';
                        });
                      }
                    },
              child: Text(laeuft ? 'Speichert…' : 'Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}
