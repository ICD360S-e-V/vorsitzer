import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../widgets/korrespondenz_message_dialog.dart';

/// OVH ▸ Korrespondenz — die Post des Rechenzentrums, in dem alles läuft.
///
/// Bei OVH ist der Server gemietet, auf dem die Anwendung, die Datenbank, der
/// Mailserver und TURN stehen, dazu die Ausweichadressen und der DDoS-Schutz.
/// Was von dort kommt, ist keine Maschinenmeldung mit Zahlen, sondern Prosa an
/// einen Menschen: eine Rechnung liegt bereit, ein Server wurde gekündigt, ein
/// Angriff wird abgewehrt, ein Dienst läuft ab. Genau die Briefe, die man ein
/// Jahr später wiederfinden muss.
///
/// ⚠️ **Deshalb gibt es hier KEINEN Auswertungs-Tab**, anders als bei DMARC und
/// TLS-RPT. Dort steckt in der Mail ein maschinenlesbarer Bericht, dessen
/// Zahlen sich summieren lassen. Hier stecken Sätze. Eine Tabelle mit „Zahlen"
/// aus OVH-Prosa wären erfundene Daten.
///
/// Zwei Tabs:
///
/// **Korrespondenz** ist das Archiv der Nachrichten, baugleich zu den anderen
/// Korrespondenz-Bereichen.
///
/// **Online-Konto** ist heute leer und ausdrücklich als „In Zukunft verfügbar"
/// beschriftet. ⚠️ Der Tab steht trotzdem schon da, weil er eine Frage
/// beantwortet: ob die Vertrags- und Rechnungsdaten anderswo liegen und man
/// sie nur nicht findet. Bei INWX gibt es dieses Fenster, hier noch nicht.
/// ⚠️ Und er enthält **keine einzige Zahl** — ein Platzhalter mit Beträgen
/// oder Laufzeiten sähe fertig aus, und niemand prüft eine Zahl nach, die
/// dasteht, als käme sie vom Anbieter.
///
/// Was an ovh@icd360s.de eingeht, landet hier von selbst (Cron, jede Minute).
/// Der Eintrag hängt danach nicht mehr an der Mail: Betreff, Absender und
/// Empfänger stehen verschlüsselt in unserer eigenen Zeile, die ganze Nachricht
/// als verschlüsselte `.eml` auf unserer Platte, und die Leseansicht fasst das
/// Postfach überhaupt nicht an.
///
/// ⚠️ Übernommen wird nach der ADRESSE, nicht nach der Absenderdomain — wie bei
/// ELSTER, INWX und TLS-RPT. Am 24.08.2026 nachgemessen: 16 der 22 Nachrichten
/// von services.ovhcloud.com tragen `ovh@icd360s.de`, die übrigen 6 gehen noch
/// an `icd@icd360s.de`, weil dort ein Teil der OVH-Kontaktadressen steht. Die
/// Antwort darauf ist, die Kontaktadresse im OVH-Kundencenter umzustellen — an
/// einer Stelle — und nicht, hier eine zweite Regel einzubauen, nach der Post
/// im Archiv landet, die nie an dessen eigene Adresse ging.
class OvhScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const OvhScreen({super.key, required this.apiService, required this.onBack});

  @override
  State<OvhScreen> createState() => _OvhScreenState();
}

/// PHP kennt nur einen Array-Typ: eine lückenlose Liste kodiert als `[]`,
/// dieselbe Struktur mit String-Schlüsseln als Objekt. Ein `as Map` auf einer
/// Liste wirft — genau daran blieb der Speedtest-Bildschirm am 05.08.2026 in
/// der Produktion grau hängen. Deshalb lesen diese Helfer beide Formen und
/// geben im Zweifel Leeres zurück, nie eine Ausnahme.
List<Map<String, dynamic>> ovhListe(dynamic roh) {
  if (roh is! List) return const [];
  return roh.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Map<String, dynamic> ovhMap(dynamic roh) {
  if (roh is Map) return Map<String, dynamic>.from(roh);
  return const {}; // eine Liste (auch die leere) ist hier keine Map
}

/// `2026-08-24 20:40:54` → `24.08.2026 20:40`. Unlesbares kommt unverändert
/// zurück, statt zu werfen: ein Datumsfeld ist kein Grund für einen grauen
/// Bildschirm.
String ovhZeit(String roh) {
  final t = roh.trim();
  if (t.length < 10) return t;
  final d = t.substring(0, 10).split('-');
  if (d.length != 3) return t;
  final tag = '${d[2]}.${d[1]}.${d[0]}';
  if (t.length >= 16) return '$tag ${t.substring(11, 16)}';
  return tag;
}

/// Die Beschriftung der beiden Tabs. Als Konstante, damit ein Test sie prüfen
/// kann, ohne sie abzuschreiben.
const List<String> kOvhTabs = ['Korrespondenz', 'Online-Konto'];

/// Was der Tab „Online-Konto" einmal zeigen soll.
///
/// ⚠️ **Keine Zahlen, nirgends.** Solange nichts abgerufen wird, darf hier
/// weder ein Betrag noch eine Laufzeit noch eine Kundennummer stehen — auch
/// nicht als Beispiel. Ein Platzhalter mit Zahlen sieht fertig aus, und
/// niemand prüft eine Zahl nach, die dasteht, als käme sie vom Anbieter. Ein
/// Test hält das fest.
const List<String> kOvhKontoGeplant = [
  'Kundennummer, Kontaktdaten und Service-PIN',
  'Gemietete Dienste mit Laufzeit und Verlängerungsart',
  'Rechnungen mit Download',
  'Guthaben und Zahlungsart',
  'Protokoll: wer wann was am Konto geändert hat',
];

/// Die Aufschrift, an der man den Tab sofort als noch nicht fertig erkennt.
const String kOvhKontoHinweis = 'In Zukunft verfügbar';

/// Erklärt, was hier liegt und was ausdrücklich nicht.
Future<void> ovhErklaerungZeigen(BuildContext kontext) {
  return showDialog<void>(
    context: kontext,
    builder: (c) => AlertDialog(
      title: Row(children: [
        Icon(Icons.dns_outlined, size: 22, color: F.h(Colors.blue, 800)),
        const SizedBox(width: 9),
        const Expanded(child: Text('Was ist OVH?', style: TextStyle(fontSize: 17))),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            _Absatz(
              'Kurz gesagt',
              'OVHcloud ist das Rechenzentrum, in dem der Server des Vereins '
              'steht. Nicht ein Dienst unter vielen: auf dieser einen Maschine '
              'laufen die App, die Datenbank, der Mailserver und die '
              'Telefonvermittlung für Videoanrufe.',
            ),
            _Absatz(
              'Was hier ankommt',
              'Rechnungen und Verlängerungen, Kündigungen einzelner Server, '
              'Wartungsankündigungen — und Meldungen des DDoS-Schutzes, wenn '
              'jemand die Adresse des Vereins angreift.\n\n'
              'Am 23.08.2026 stand hier zum ersten Mal so eine Meldung: '
              'Abwehr auf 135.125.189.10 aktiv, kurz darauf Entwarnung.',
            ),
            _Absatz(
              'Warum es archiviert wird',
              'Ein Postfach ist kein Archiv. Wer eine Mail löscht, löscht den '
              'Beleg mit. Hier bleibt der Eintrag: Betreff, Absender und die '
              'vollständige Originalnachricht liegen verschlüsselt in unserer '
              'eigenen Datenbank, und die Leseansicht holt sie von dort — sie '
              'fasst das Postfach überhaupt nicht an.',
            ),
            _Absatz(
              'Was übernommen wird',
              'Alles, was an ovh@icd360s.de geht. Entscheidend ist die '
              'ADRESSE, nicht der Absender.\n\n'
              'Ein Teil der Kontaktadressen im OVH-Kundencenter steht noch auf '
              'icd@icd360s.de; solche Post liegt weiterhin nur im Postfach. '
              'Das ist eine Einstellung bei OVH, kein Fehler hier.',
            ),
            _Absatz(
              'Was hier nicht steht',
              'Keine Auswertung, keine Statistik. Anders als bei DMARC und '
              'TLS-RPT steckt in einer OVH-Mail kein maschinenlesbarer Bericht, '
              'sondern ein Text für einen Menschen. Zahlen daraus zu bilden '
              'hiesse, sie zu erfinden.\n\n'
              'Rechnungen selbst hängen auch nicht an: OVH schickt einen Link '
              'ins Kundencenter, kein PDF.',
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Verstanden')),
      ],
    ),
  );
}

class _Absatz extends StatelessWidget {
  final String titel;
  final String text;
  const _Absatz(this.titel, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titel,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: F.h(Colors.blue, 800))),
        const SizedBox(height: 4),
        Text(text, style: TextStyle(fontSize: 13, height: 1.45, color: F.textSchwach)),
      ]),
    );
  }
}

class _OvhScreenState extends State<OvhScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade600 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
            tooltip: 'Zurück zu Partner',
          ),
          const SizedBox(width: 8),
          Icon(Icons.dns_outlined, size: 30, color: F.h(Colors.blue, 800)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('OVHcloud',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text('Rechenzentrum des Vereins',
                  style: TextStyle(fontSize: 12, color: F.textLeise)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Was ist OVH?',
            onPressed: () => ovhErklaerungZeigen(context),
          ),
        ]),
      ),
      TabBar(
        controller: _tabs,
        labelColor: F.h(Colors.blue, 800),
        indicatorColor: F.h(Colors.blue, 800),
        tabs: [
          Tab(icon: const Icon(Icons.mail_outline, size: 18), text: kOvhTabs[0]),
          Tab(icon: const Icon(Icons.account_circle_outlined, size: 18), text: kOvhTabs[1]),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _OvhMailTab(apiService: widget.apiService, melde: _melde),
            const _OvhKontoTab(),
          ],
        ),
      ),
    ]);
  }
}

// ═══════════════════ Tab 1: Korrespondenz ═══════════════════

/// Die Nachrichten, die an ovh@icd360s.de eingegangen sind.
class _OvhMailTab extends StatefulWidget {
  final ApiService apiService;
  final void Function(String, {bool fehler}) melde;

  const _OvhMailTab({required this.apiService, required this.melde});

  @override
  State<_OvhMailTab> createState() => _OvhMailTabState();
}

class _OvhMailTabState extends State<_OvhMailTab> with AutomaticKeepAliveClientMixin {
  static const String _modul = 'ovh';

  bool _laeuft = true;
  List<Map<String, dynamic>> _eintraege = [];

  /// Der Tab überlebt den Wechsel zum Nachbarn. Sonst lüde ein Blick auf das
  /// Online-Konto und zurück die ganze Liste neu — auf genau der Leitung, die
  /// wir anderswo als langsam beanstanden.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _laeuft = true);
    try {
      final r = await widget.apiService.getVereinKorrespondenz(modul: _modul);
      if (!mounted) return;
      if (r['success'] == true) {
        final d = r['data'];
        _eintraege = ovhListe(
            (d is Map ? d['korrespondenz'] : null) ?? r['korrespondenz']);
      } else {
        widget.melde(r['message']?.toString() ?? 'Korrespondenz nicht abrufbar',
            fehler: true);
      }
    } catch (e) {
      if (mounted) widget.melde('Fehler: $e', fehler: true);
    }
    if (mounted) setState(() => _laeuft = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          Expanded(
            child: Text(
              _laeuft
                  ? 'Wird geladen …'
                  : '${_eintraege.length} '
                      '${_eintraege.length == 1 ? "Nachricht" : "Nachrichten"} archiviert',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Neu laden',
            onPressed: _laden,
          ),
        ]),
      ),
      Expanded(
        child: _laeuft
            ? const Center(child: CircularProgressIndicator())
            : _eintraege.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.mail_outline, size: 48, color: F.h(Colors.grey, 300)),
                        const SizedBox(height: 10),
                        Text(
                          'Noch keine Nachricht.\n'
                          'E-Mails an ovh@icd360s.de werden automatisch übernommen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600)),
                        ),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _laden,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _eintraege.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _karte(_eintraege[i]),
                    ),
                  ),
      ),
    ]);
  }

  Widget _karte(Map<String, dynamic> k) {
    final betreff = (k['betreff'] ?? '').toString();
    final absender = (k['absender'] ?? '').toString();
    final empfaenger = (k['empfaenger'] ?? '').toString();
    final dateien = ovhListe(k['dateien']);
    final ausgang = (k['richtung'] ?? '').toString() == 'ausgang';

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(Colors.grey, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ausgang ? Icons.north_east : Icons.south_west,
                size: 15, color: F.h(Colors.blue, 700)),
            const SizedBox(width: 5),
            Text(ausgang ? 'AUSGANG' : 'EINGANG',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: F.h(Colors.blue, 800))),
          ]),
          Text(ovhZeit(k['datum']?.toString() ?? ''),
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          if ((k['quelle'] ?? '').toString() == 'mail')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: F.h(Colors.blue, 50), borderRadius: BorderRadius.circular(4)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.bolt, size: 10, color: F.h(Colors.blue, 400)),
                const SizedBox(width: 2),
                Text('automatisch',
                    style: TextStyle(fontSize: 9, color: F.h(Colors.blue, 700))),
              ]),
            ),
        ]),
        const SizedBox(height: 7),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (betreff.isNotEmpty)
                Text(betreff,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                [if (absender.isNotEmpty) absender, if (empfaenger.isNotEmpty) '→ $empfaenger']
                    .join(' '),
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 17, color: F.h(Colors.red, 400)),
            tooltip: 'Löschen',
            visualDensity: VisualDensity.compact,
            onPressed: () => _loeschen(k),
          ),
        ]),
        if (dateien.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final f in dateien) _dateiChip(f)]),
        ],
      ]),
    );
  }

  Widget _dateiChip(Map<String, dynamic> f) {
    final name = (f['original_name'] ?? 'Datei').toString();
    final eml = (f['rolle'] ?? '').toString() == 'eml';
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _oeffnen(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: eml ? F.h(Colors.blueGrey, 50) : F.h(Colors.grey, 50),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: eml ? F.h(Colors.blueGrey, 200) : F.h(Colors.grey, 200)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(eml ? Icons.mail_outline : Icons.attach_file,
              size: 15, color: eml ? F.h(Colors.blueGrey, 600) : F.h(Colors.grey, 600)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(eml ? 'Originalnachricht öffnen' : name,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }

  /// Eine archivierte Nachricht geht in den Mail-Leser. Eine `.eml` an den
  /// Dateibetrachter zu geben zeigt nichts — der kennt PDFs und Bilder.
  ///
  /// Alles andere wird heruntergeladen und dem System übergeben. OVH hängt
  /// heute nichts an, aber die Zeile muss stehen, bevor das erste Mal doch
  /// etwas mitkommt.
  Future<void> _oeffnen(Map<String, dynamic> f) async {
    final id = int.tryParse(f['id']?.toString() ?? '') ?? 0;
    if (id == 0) return;
    if ((f['rolle'] ?? '').toString() == 'eml') {
      await KorrespondenzMessageDialog.show(
        context, widget.apiService, id,
        loader: (fid) => widget.apiService.getKorrespondenzMessage(fid, modul: _modul),
      );
      return;
    }
    final r = await widget.apiService.downloadVereinKorrespondenzFile(id, modul: _modul);
    if (!mounted) return;
    if (r == null) {
      widget.melde('Datei konnte nicht geladen werden', fehler: true);
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final sauber = (f['original_name'] ?? 'anhang')
          .toString()
          .replaceAll(RegExp(r'[^\w.\-]'), '_');
      final datei = File('${dir.path}/$sauber');
      await datei.writeAsBytes(r.bodyBytes);
      final auf = await OpenFilex.open(datei.path);
      if (auf.type != ResultType.done) widget.melde('Gespeichert unter ${datei.path}');
    } catch (e) {
      widget.melde('Öffnen fehlgeschlagen: $e', fehler: true);
    }
  }

  Future<void> _loeschen(Map<String, dynamic> k) async {
    final id = int.tryParse(k['id']?.toString() ?? '') ?? 0;
    if (id == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eintrag löschen?', style: TextStyle(fontSize: 15)),
        content: Text(
          '„${k['betreff'] ?? ''}" wird mitsamt Originalnachricht und Anhang entfernt. '
          'Ist die Mail im Postfach schon gelöscht, ist das die letzte Kopie.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await widget.apiService.deleteVereinKorrespondenz(id, modul: _modul);
    if (!mounted) return;
    if (r['success'] == true) {
      widget.melde('Eintrag gelöscht');
      _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Löschen fehlgeschlagen', fehler: true);
    }
  }
}

// ═══════════════════ Tab 2: Online-Konto ═══════════════════

/// Platzhalter für das OVH-Kundenkonto — bewusst leer und ausdrücklich als
/// „noch nicht da" beschriftet.
///
/// ⚠️ **Hier steht keine einzige Zahl.** Ein Platzhalter, der schon einmal
/// Beträge, Laufzeiten oder einen Kontostand anzeigt, ist die schlechteste
/// Sorte Fehler: er sieht fertig aus, und niemand prüft eine Zahl nach, die
/// dasteht, als käme sie vom Anbieter. Erst wenn der Abruf wirklich läuft,
/// kommen Werte auf den Schirm.
///
/// Der Tab existiert trotzdem schon, weil er sagt, was es NICHT gibt: ohne ihn
/// bliebe die Frage offen, ob die Vertragsdaten anderswo stehen und man sie nur
/// nicht findet. Anders als bei INWX gibt es dieses Fenster hier noch nicht.
class _OvhKontoTab extends StatelessWidget {
  const _OvhKontoTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.account_circle_outlined, size: 52, color: F.h(Colors.grey, 300)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: F.h(Colors.amber, 50),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: F.h(Colors.amber, 200)),
              ),
              child: Text(kOvhKontoHinweis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: F.h(Colors.amber, 900))),
            ),
            const SizedBox(height: 16),
            const Text('Online-Konto',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              'Das Kundenkonto bei OVHcloud ist hier noch nicht angebunden. '
              'Was von dort kommt, steht bis dahin ausschliesslich im Tab '
              '„Korrespondenz" — also das, was OVH von sich aus schreibt.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: F.textSchwach),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: F.h(Colors.grey, 50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: F.h(Colors.grey, 200)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Vorgesehen ist',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: F.h(Colors.grey, 700))),
                const SizedBox(height: 8),
                for (final z in kOvhKontoGeplant)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Der Punkt sitzt sonst am oberen Rand der Zeile statt
                      // auf ihrer Mitte — auf der Randung gesehen, nicht im
                      // Code vermutet.
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Icon(Icons.circle, size: 5, color: F.h(Colors.grey, 400)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(z,
                            style: TextStyle(fontSize: 12.5, height: 1.35, color: F.textSchwach)),
                      ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            Text(
              'Dafür braucht es einen eigenen API-Schlüssel im OVH-Kundencenter. '
              'Solange der nicht eingerichtet ist, bleibt dieser Tab leer — '
              'geschätzte Zahlen wären hier schlimmer als gar keine.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: F.textLeise),
            ),
          ]),
        ),
      ),
    );
  }
}
