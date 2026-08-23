import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/termin_service.dart';
import '../services/ticket_service.dart';
import '../utils/app_farben.dart';
import '../utils/terminanfrage_vorlagen.dart';
import 'terminanfrage_versand_dialog.dart';

/// Der Termin-Tab einer einzelnen Heilmittelverordnung: Anfrage · Bestätigt ·
/// Absage.
///
/// WARUM EIGENE DATEI
/// `gesundheit_tab_content.dart` hat 19.000 Zeilen. Hier liegt der Teil, der
/// sich allein aufbauen und damit auch allein ANSEHEN lässt — das ist keine
/// Ordnungsliebe: Layoutfehler zeigt weder `flutter analyze` noch der
/// Testlauf, nur ein gerendertes Bild.
class HeilmittelTerminTab extends StatefulWidget {
  /// Der Arzt-Tab, in dem die Verordnung hängt (z. B. `gesundheit_hausarzt`).
  final String arztTyp;

  /// Die Verordnung selbst. Wird IN PLACE geändert — der umgebende Dialog und
  /// der Verlauf-Tab halten dieselbe Map, und `speichern` schreibt genau sie
  /// zurück. Eine Kopie hier hieße: der Termin steht auf dem Schirm und ist
  /// nach dem Schließen weg.
  final Map<String, dynamic> verordnung;

  /// Schreibt die Verordnung zurück (`doSave(r, fromStatus: true)`).
  final VoidCallback speichern;

  final User user;
  final ApiService apiService;
  final TicketService ticketService;
  final TerminService terminService;

  const HeilmittelTerminTab({
    super.key,
    required this.arztTyp,
    required this.verordnung,
    required this.speichern,
    required this.user,
    required this.apiService,
    required this.ticketService,
    required this.terminService,
  });

  @override
  State<HeilmittelTerminTab> createState() => _HeilmittelTerminTabState();
}

class _HeilmittelTerminTabState extends State<HeilmittelTerminTab> {
  /// Der Termin-Tab einer einzelnen Heilmittelverordnung.
  ///
  /// WARUM HIER UND NICHT IM TERMIN-TAB DES ARZTES
  /// Der Arzt-Tab fragt einen Termin BEIM ARZT an. Hier geht es um die
  /// Behandlungstermine in der Physiotherapie-Praxis, die auf DIESER
  /// Verordnung stehen — anderer Empfänger, anderer Anlass, andere Frist
  /// (die Verordnung läuft ab). Beides in eine Liste zu werfen hieße, im
  /// Zweifel die Anfrage an den Hausarzt zu schicken statt an die Praxis.
  ///
  /// 🔴 DER EMPFÄNGER KOMMT AUS DEM VERLAUF-TAB, NICHT AUS `selected_arzt`.
  /// `selected_arzt` ist der Hausarzt, der die Verordnung ausgestellt hat.
  /// Eine Terminanfrage dorthin wäre an den Falschen adressiert — und zwar
  /// ohne dass irgendetwas fehlschlägt: die Mail ginge sauber raus, an die
  /// falsche Praxis. Deshalb ausschließlich `r['physio_praxis_*']`.
  ///
  /// ⚠️ Versand und Brieftext macht [zeigeTerminanfrageVersand] — derselbe
  /// Dialog wie in allen sechs Ärzte-Tabs, mit E-Mail als Text und Fax als
  /// PDF aus einer Quelle. Hier wird NICHTS davon nachgebaut; ein zweiter
  /// Brieftext liefe ab dem ersten Tag auseinander.
  @override
  Widget build(BuildContext context) {
    final type = widget.arztTyp;
    final r = widget.verordnung;
    final persist = widget.speichern;
    return StatefulBuilder(builder: (tCtx, setTermin) {
      // Bestand direkt an `r`, nicht an einer Kopie: der Versand-Dialog
      // schreibt asynchron zurück, während dieser Baum schon neu gebaut wurde.
      if (r['termin_anfragen'] is! List) r['termin_anfragen'] = [];
      final List<dynamic> anfragen = r['termin_anfragen'] as List;

      final praxisName = (r['physio_praxis_name']?.toString() ?? '').trim();
      final praxisEmail = (r['physio_praxis_email']?.toString() ?? '').trim();
      final praxisFax = (r['physio_praxis_fax']?.toString() ?? '').trim();
      final bereich = (r['bereich']?.toString() ?? 'Physiotherapie').trim();

      List<Map<String, dynamic>> mitStatus(String s) => anfragen
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => (e['status']?.toString() ?? 'offen') == s)
          .toList();

      // ── Praxis-Kopf: wer der Empfänger ist und welche Wege offen sind ──
      //
      // ⚠️ Steht hier nichts, sagt der Kasten WARUM. Ein ausgegrauter Knopf
      // ohne Begründung sieht nach Defekt aus; die Ursache ist aber fast immer
      // „im Verlauf ist noch keine Praxis gewählt".
      Widget praxisKopf() => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: praxisName.isEmpty ? F.h(Colors.amber, 50) : F.h(Colors.indigo, 50),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: praxisName.isEmpty ? F.h(Colors.amber, 300) : F.h(Colors.indigo, 100)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.local_hospital, size: 15, color: praxisName.isEmpty ? F.h(Colors.amber, 800) : F.h(Colors.indigo, 700)),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  praxisName.isEmpty ? 'Keine Praxis im Verlauf ausgewählt' : praxisName,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: praxisName.isEmpty ? F.h(Colors.amber, 900) : F.h(Colors.indigo, 800)),
                  overflow: TextOverflow.ellipsis,
                )),
              ]),
              const SizedBox(height: 6),
              if (praxisName.isEmpty)
                Text('Bitte im Tab „Verlauf" die Physiotherapie-Praxis auswählen — von dort kommen Anschrift, E-Mail und Fax.',
                    style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: F.h(Colors.amber, 900)))
              else
                Wrap(spacing: 8, runSpacing: 4, children: [
                  _kanalChip(Icons.email, 'E-Mail', praxisEmail),
                  _kanalChip(Icons.fax, 'Fax', praxisFax),
                ]),
              if (praxisName.isNotEmpty && praxisEmail.isEmpty && praxisFax.isEmpty) ...[
                const SizedBox(height: 6),
                Text('Diese Praxis hat in der Ärzte-Datenbank weder E-Mail noch Fax. '
                     'Ohne einen der beiden Wege kann von hier nichts rausgehen.',
                    style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: F.h(Colors.amber, 900))),
              ],
            ]),
          );

      // ── Neue Anfrage: bauen, rausschicken, danach erst ablegen ──
      //
      // ⚠️ Die Zeile entsteht ERST im `onGesendet`-Rückruf, also nur nach
      // erfolgreichem Versand. Eine Anfrage, die eine Versendung behauptet,
      // die nie stattfand, ist schlimmer als gar keine Zeile — dieselbe Regel
      // wie im Arzt-Tab.
      Future<void> neueAnfrage() async {
        if (praxisEmail.isEmpty && praxisFax.isEmpty) return;

        // 🔴 Der Grund IST das Rezept.
        //
        // Vorher wurde hier nur `arztTyp` durchgereicht, und der gemeinsame
        // Dialog löste damit `arztFachFuer('gesundheit_hausarzt')` auf. In der
        // Anfrage an eine PHYSIOTHERAPIE-Praxis stand dann „zur
        // hausärztlichen Erstvorstellung", zur Auswahl „Erkältung / Husten /
        // Fieber" und „Blutbild / Laborkontrolle" — Dinge, die eine
        // Heilmittelpraxis weder darf noch tut. Ein Fach für Heilmittel gibt
        // es in `kArztFaecher` gar nicht; es war keine falsche Wahl, sondern
        // eine fehlende. Mit `rezept` schaltet der Dialog auf die
        // Verordnung um: Heilmittel, Menge, Frequenz, Dringlichkeit,
        // Hausbesuch, Indikation, Diagnose.
        final basis = terminanfrageDatenBauen(
          arztTyp: type,
          rezept: HeilmittelVerordnung.ausZeile(r),
          user: widget.user,
          // Der Verlauf speichert die Praxis unter eigenen Schlüsseln; hier
          // werden sie auf die Form gebracht, die der gemeinsame Dialog kennt.
          arzt: {
            'praxis_name': praxisName,
            'arzt_name': r['therapeut']?.toString() ?? '',
            'strasse': r['physio_praxis_strasse']?.toString() ?? '',
            'plz_ort': r['physio_praxis_plz_ort']?.toString() ?? '',
            'email': praxisEmail,
            'fax': praxisFax,
          },
          // ⚠️ Die Historie sind die Sitzungen DIESER Verordnung, nicht die
          // Arzttermine: davon hängt ab, ob der Brief sich als Erstanfrage
          // oder als Folgeanfrage liest.
          termine: (r['sitzungen'] is List)
              ? (r['sitzungen'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : const <Map<String, dynamic>>[],
        );

        await zeigeTerminanfrageVersand(
          tCtx,
          api: widget.apiService,
          arztTitel: praxisName.isEmpty ? bereich : praxisName,
          basis: basis,
          onGesendet: (e) async {
            anfragen.insert(0, {
              'uid': const Uuid().v4(),
              'status': 'offen',
              'methode': e.methode,
              'empfaenger': e.empfaenger,
              'betreff': e.betreff,
              'text': e.text,
              'praxis_name': praxisName,
              'sitzung_id': e.sitzungId,
              'message_id': e.messageId,
              'gesendet_am': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
            });
            r['termin_anfragen'] = anfragen;
            persist();

            // Der Vorgang gehört auch in die Korrespondenz der Verordnung —
            // sonst steht der Schriftwechsel an zwei Orten und der Tab
            // „Korrespondenz" behauptet, es sei nie etwas rausgegangen.
            if (r['korrespondenz'] is! List) r['korrespondenz'] = [];
            (r['korrespondenz'] as List).insert(0, {
              'richtung': 'ausgang',
              'methode': e.methode == 'fax' ? 'fax' : 'email',
              'datum': DateFormat('dd.MM.yyyy').format(DateTime.now()),
              'betreff': e.betreff,
              'inhalt': e.text,
              'erstellt_am': DateTime.now().millisecondsSinceEpoch,
            });
            persist();

            try {
              await widget.ticketService.createTicket(
                mitgliedernummer: widget.user.mitgliedernummer,
                subject: 'Heilmittel-Terminanfrage: $bereich — ${widget.user.name}',
                message: [
                  'Praxis: ${praxisName.isEmpty ? '(ohne Namen)' : praxisName}',
                  'Patient: ${widget.user.name} (${widget.user.mitgliedernummer})',
                  'Versandt per ${e.methode == 'fax' ? 'Fax' : 'E-Mail'} an ${e.empfaenger}',
                  if (e.sitzungId.isNotEmpty) 'sipgate-Sitzung: ${e.sitzungId}',
                  '',
                  e.betreff,
                ].join('\n'),
                priority: 'medium',
                systemTicket: true,
                scheduledDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
              );
            } catch (err) {
              debugPrint('[Heilmittel-Termin] Ticket create error: $err');
            }

            if (tCtx.mounted) setTermin(() {});
          },
        );
        if (tCtx.mounted) setTermin(() {});
      }

      // ── Bestätigen: Datum + Uhrzeit, dann Sitzung im Verlauf anlegen ──
      //
      // 🔴 EIN BESTÄTIGTER TERMIN IST EINE SITZUNG.
      // Der Verlauf-Tab führt die Behandlungstermine samt Status
      // (wahrgenommen / verschoben / …) und zählt sie gegen die verordnete
      // Menge. Würde hier eine zweite, eigene Liste geführt, zählte der
      // Verlauf zu wenig und die Verordnung liefe ab, obwohl die Termine
      // stehen. Deshalb wird beim Bestätigen in `r['sitzungen']` geschrieben,
      // genau wie es der Knopf „Sitzung" dort tut.
      Future<void> bestaetigen(Map<String, dynamic> a) async {
        final dC = TextEditingController();
        final zC = TextEditingController(text: '14:00');
        final ok = await showDialog<bool>(
          context: tCtx,
          builder: (bCtx) => StatefulBuilder(builder: (bCtx, setB) => AlertDialog(
            title: Row(children: [
              Icon(Icons.event_available, size: 18, color: F.h(Colors.green, 700)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Termin bestätigt', style: TextStyle(fontSize: 15))),
            ]),
            content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Welchen Termin hat die Praxis zugesagt?',
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextFormField(
                  controller: dC, readOnly: true,
                  decoration: InputDecoration(labelText: 'Datum *', isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 16), onPressed: () async {
                      final p = await showDatePicker(context: bCtx, initialDate: DateTime.now(),
                        firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de'));
                      if (p != null) setB(() => dC.text = DateFormat('yyyy-MM-dd').format(p));
                    })))),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: TextFormField(controller: zC,
                  decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
              ]),
              const SizedBox(height: 10),
              Text('Der Termin wird als Sitzung in den Verlauf übernommen und in die '
                   'Terminverwaltung eingetragen.',
                  style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: F.h(Colors.grey, 600))),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(bCtx, false), child: const Text('Abbrechen')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: F.h(Colors.green, 700)),
                onPressed: () {
                  if (dC.text.isEmpty) {
                    ScaffoldMessenger.of(bCtx).showSnackBar(const SnackBar(
                      content: Text('Bitte Datum wählen'), backgroundColor: Colors.red));
                    return;
                  }
                  Navigator.pop(bCtx, true);
                },
                child: const Text('Übernehmen')),
            ],
          )),
        );
        if (ok != true) return;

        if (r['sitzungen'] is! List) r['sitzungen'] = [];
        final sitzungen = r['sitzungen'] as List;
        final nr = sitzungen.length + 1;
        final sitzung = <String, dynamic>{
          'nr': '$nr',
          'datum': dC.text,
          'zeit': zC.text.trim(),
          'notizen': r['therapeut']?.toString() ?? '',
          'onorat': false,
          'tv_created': true,
          // Rückweg zur Anfrage: sonst lässt sich später nicht mehr sagen,
          // welche Anfrage zu diesem Termin geführt hat.
          'aus_anfrage': a['uid'],
        };
        sitzungen.add(sitzung);

        try {
          final teile = zC.text.trim().split(':');
          final h = int.tryParse(teile.isNotEmpty ? teile[0] : '14') ?? 14;
          final m = teile.length > 1 ? (int.tryParse(teile[1]) ?? 0) : 0;
          final praxisOrt = [
            r['physio_praxis_strasse']?.toString() ?? '',
            r['physio_praxis_plz_ort']?.toString() ?? '',
          ].where((s) => s.isNotEmpty).join(', ');
          widget.terminService.setToken(widget.apiService.token ?? '');
          widget.terminService.createTermin(
            title: '$bereich Sitzung $nr${praxisName.isNotEmpty ? ' - $praxisName' : ''}',
            category: 'sonstiges',
            description: [
              if ((r['therapeut']?.toString() ?? '').isNotEmpty) 'Therapeut/in: ${r['therapeut']}',
              if (praxisOrt.isNotEmpty) 'Ort: $praxisOrt',
              'Mitglied: ${widget.user.vorname ?? ''} ${widget.user.nachname ?? ''} (${widget.user.mitgliedernummer})',
            ].join('\n'),
            terminDate: DateTime.parse(dC.text).add(Duration(hours: h, minutes: m)),
            durationMinutes: 30,
            location: praxisOrt.isNotEmpty ? praxisOrt : praxisName,
            participantIds: [widget.user.id],
          ).then((res) {
            if (res.containsKey('termin')) sitzung['termin_id'] = res['termin']['id'];
          });
        } catch (err) {
          debugPrint('[Heilmittel-Termin] Terminverwaltung: $err');
        }

        _anfrageStatusSetzen(anfragen, a['uid']?.toString() ?? '', {
          'status': 'bestaetigt',
          'termin_datum': dC.text,
          'termin_zeit': zC.text.trim(),
          'bestaetigt_am': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'sitzung_nr': '$nr',
        });
        r['termin_anfragen'] = anfragen;
        persist();
        if (tCtx.mounted) setTermin(() {});
      }

      // ── Absage: wer abgesagt hat, und warum ──
      //
      // ⚠️ „Wer" ist keine Kosmetik: sagt die PRAXIS ab, muss ein neuer Termin
      // her und die Verordnung läuft weiter; sagt das MITGLIED mehrfach ab,
      // ist das ein Fall für die Mitwirkungspflicht. Ein gemeinsames
      // „abgesagt" verwischt genau diesen Unterschied.
      Future<void> absagen(Map<String, dynamic> a) async {
        String von = 'praxis';
        final gC = TextEditingController();
        final ok = await showDialog<bool>(
          context: tCtx,
          builder: (aCtx) => StatefulBuilder(builder: (aCtx, setA) => AlertDialog(
            title: Row(children: [
              Icon(Icons.event_busy, size: 18, color: F.h(Colors.red, 700)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Absage festhalten', style: TextStyle(fontSize: 15))),
            ]),
            content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Wer hat abgesagt?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700))),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final o in const [('praxis', 'Die Praxis'), ('mitglied', 'Das Mitglied')])
                  ChoiceChip(
                    label: Text(o.$2, style: TextStyle(fontSize: 11, color: von == o.$1 ? Colors.white : F.h(Colors.red, 700))),
                    selected: von == o.$1,
                    selectedColor: F.h(Colors.red, 600),
                    backgroundColor: F.h(Colors.red, 50),
                    side: BorderSide(color: von == o.$1 ? F.h(Colors.red, 600) : F.h(Colors.red, 200)),
                    onSelected: (_) => setA(() => von = o.$1),
                  ),
              ]),
              const SizedBox(height: 12),
              TextFormField(controller: gC, maxLines: 2,
                decoration: InputDecoration(labelText: 'Grund (optional)', isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(aCtx, false), child: const Text('Abbrechen')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: F.h(Colors.red, 600)),
                onPressed: () => Navigator.pop(aCtx, true),
                child: const Text('Festhalten')),
            ],
          )),
        );
        if (ok != true) return;
        _anfrageStatusSetzen(anfragen, a['uid']?.toString() ?? '', {
          'status': 'absage',
          'absage_von': von,
          'absage_grund': gC.text.trim(),
          'abgesagt_am': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        });
        r['termin_anfragen'] = anfragen;
        persist();
        if (tCtx.mounted) setTermin(() {});
      }

      Widget liste(String status, IconData leer, String leerText, List<Widget> Function(Map<String, dynamic>) aktionen) {
        final rows = mitStatus(status);
        if (rows.isEmpty) {
          return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(leer, size: 34, color: F.h(Colors.grey, 300)),
            const SizedBox(height: 8),
            Text(leerText, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 400)), textAlign: TextAlign.center),
          ])));
        }
        return Column(children: rows.map((a) => _anfrageKarte(a, aktionen(a))).toList());
      }

      return DefaultTabController(length: 3, child: Column(children: [
        TabBar(
          labelColor: F.h(Colors.teal, 700),
          unselectedLabelColor: F.h(Colors.grey, 500),
          indicatorColor: F.h(Colors.teal, 700),
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          tabs: [
            Tab(icon: const Icon(Icons.send, size: 15), text: 'Anfrage (${mitStatus('offen').length})'),
            Tab(icon: const Icon(Icons.event_available, size: 15), text: 'Bestätigt (${mitStatus('bestaetigt').length})'),
            Tab(icon: const Icon(Icons.event_busy, size: 15), text: 'Absage (${mitStatus('absage').length})'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          // ── Anfrage ──
          SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            praxisKopf(),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Neue Terminanfrage', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(backgroundColor: F.h(Colors.orange, 600)),
              // Aus statt versteckt: der Kasten darüber sagt, was fehlt.
              onPressed: (praxisEmail.isEmpty && praxisFax.isEmpty) ? null : neueAnfrage,
            )),
            const SizedBox(height: 12),
            liste('offen', Icons.mark_email_unread, 'Noch keine Anfrage versandt',
              (a) => [
                TextButton.icon(
                  icon: Icon(Icons.event_available, size: 14, color: F.h(Colors.green, 700)),
                  label: Text('Bestätigt', style: TextStyle(fontSize: 11, color: F.h(Colors.green, 700))),
                  onPressed: () => bestaetigen(a)),
                TextButton.icon(
                  icon: Icon(Icons.event_busy, size: 14, color: F.h(Colors.red, 700)),
                  label: Text('Absage', style: TextStyle(fontSize: 11, color: F.h(Colors.red, 700))),
                  onPressed: () => absagen(a)),
              ]),
          ])),

          // ── Bestätigt ──
          SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            liste('bestaetigt', Icons.event_available, 'Noch kein Termin bestätigt',
              (a) => [
                TextButton.icon(
                  icon: Icon(Icons.event_busy, size: 14, color: F.h(Colors.red, 700)),
                  label: Text('Doch abgesagt', style: TextStyle(fontSize: 11, color: F.h(Colors.red, 700))),
                  onPressed: () => absagen(a)),
              ]),
          ])),

          // ── Absage ──
          SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            liste('absage', Icons.event_busy, 'Keine Absagen', (a) => const []),
          ])),
        ])),
      ]));
    });
  }

  /// Setzt Felder einer Anfrage anhand ihrer `uid`.
  ///
  /// ⚠️ Über die `uid`, NICHT über den Listenindex: die drei Unter-Tabs zeigen
  /// je eine gefilterte Sicht, deren Index mit der Gesamtliste nichts zu tun
  /// hat. Ein Index von dort träfe die falsche Zeile.
  void _anfrageStatusSetzen(List<dynamic> anfragen, String uid, Map<String, dynamic> felder) {
    if (uid.isEmpty) return;
    for (var i = 0; i < anfragen.length; i++) {
      final e = anfragen[i];
      if (e is Map && e['uid']?.toString() == uid) {
        anfragen[i] = {...Map<String, dynamic>.from(e), ...felder};
        return;
      }
    }
  }

  Widget _kanalChip(IconData ikone, String label, String wert) {
    final da = wert.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: da ? F.h(Colors.blue, 50) : F.h(Colors.grey, 100),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: da ? F.h(Colors.blue, 200) : F.h(Colors.grey, 300)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ikone, size: 12, color: da ? F.h(Colors.blue, 700) : F.h(Colors.grey, 500)),
        const SizedBox(width: 4),
        Text(da ? wert : '$label fehlt',
            style: TextStyle(fontSize: 10, color: da ? F.h(Colors.blue, 900) : F.h(Colors.grey, 600))),
      ]),
    );
  }

  Widget _anfrageKarte(Map<String, dynamic> a, List<Widget> aktionen) {
    final istFax = a['methode']?.toString() == 'fax';
    final status = a['status']?.toString() ?? 'offen';
    final farbe = status == 'bestaetigt'
        ? Colors.green
        : status == 'absage'
            ? Colors.red
            : Colors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: F.h(farbe, 50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: F.h(farbe, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(istFax ? Icons.fax : Icons.email, size: 14, color: F.h(farbe, 700)),
          const SizedBox(width: 4),
          Text(istFax ? 'Fax' : 'E-Mail', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: F.h(farbe, 700))),
          const SizedBox(width: 8),
          Expanded(child: Text(a['empfaenger']?.toString() ?? '',
              style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)), overflow: TextOverflow.ellipsis)),
          Text(_deutschesDatum(a['gesendet_am']?.toString() ?? ''), style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 500))),
        ]),
        if ((a['betreff']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(a['betreff'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
        if (status == 'bestaetigt') ...[
          const SizedBox(height: 4),
          Text('Termin: ${_deutschesDatum(a['termin_datum']?.toString() ?? '')}'
               '${(a['termin_zeit']?.toString() ?? '').isEmpty ? '' : ' um ${a['termin_zeit']} Uhr'}'
               '${(a['sitzung_nr']?.toString() ?? '').isEmpty ? '' : ' · Sitzung ${a['sitzung_nr']} im Verlauf'}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: F.h(Colors.green, 800))),
        ],
        if (status == 'absage') ...[
          const SizedBox(height: 4),
          Text('Abgesagt von ${a['absage_von'] == 'mitglied' ? 'dem Mitglied' : 'der Praxis'}'
               '${(a['abgesagt_am']?.toString() ?? '').isEmpty ? '' : ' am ${_deutschesDatum(a['abgesagt_am'].toString())}'}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: F.h(Colors.red, 800))),
          if ((a['absage_grund']?.toString() ?? '').isNotEmpty)
            Text(a['absage_grund'].toString(), style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
        ],
        // ⚠️ „an sipgate übergeben" ist NICHT „zugestellt" — die Zustellung
        // verfolgt ein Cron nach. Deshalb steht hier die Sitzungsnummer und
        // keine Erfolgsmeldung.
        if ((a['sitzung_id']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text('sipgate-Sitzung ${a['sitzung_id']} — an sipgate übergeben, Zustellung wird nachverfolgt',
              style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: F.h(Colors.grey, 600))),
        ],
        if (aktionen.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: aktionen),
        ],
      ]),
    );
  }

  /// `2026-08-23` → `23.08.2026`, `2026-08-23 09:40` → `23.08.2026 09:40`.
  /// Alles, was nicht so aussieht, bleibt unangetastet.
  ///
  /// ⚠️ Gespeichert wird ISO, angezeigt wird deutsch. Andersherum liesse sich
  /// die Liste nicht mehr sortieren — und gemischt stand auf dem Schirm
  /// „2026-08-23" direkt neben „02.09.2026", was beim Lesen kurz wie zwei
  /// verschiedene Angaben wirkt. Gefunden wurde das erst am gerenderten Bild.
  String _deutschesDatum(String roh) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(.*)$').firstMatch(roh);
    return m == null
        ? roh
        : '${m.group(3)}.${m.group(2)}.${m.group(1)}${m.group(4)}';
  }

}
