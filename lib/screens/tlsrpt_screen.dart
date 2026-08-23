import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../widgets/korrespondenz_message_dialog.dart';

/// TLS-RPT ▸ Reporting — ob fremde Server verschlüsselt zu uns liefern konnten.
///
/// ⚠️ **Das ist NICHT die zweite Hälfte von DMARC, sondern die Gegenrichtung.**
/// DMARC meldet, was ANGEBLICH VON uns kam und ob es echt war. TLS-RPT
/// (RFC 8460) meldet, ob ein fremder Mailserver eine verschlüsselte Verbindung
/// ZU uns aufbauen konnte — unter der MTA-STS-Richtlinie, die wir
/// veröffentlichen. Die Zahlen zählen SITZUNGEN, nicht Nachrichten, und dürfen
/// nie mit den DMARC-Zahlen in einer Summe landen.
///
/// Warum das hier besonders zählt: unsere Richtlinie steht auf `enforce`, und
/// wir veröffentlichen DANE/TLSA. Wird ein Zertifikat getauscht, ohne den
/// TLSA-Eintrag mitzuziehen, fällt ein Absender nicht auf unverschlüsselt
/// zurück — er liefert **gar nicht mehr**. In unseren eigenen Logs steht davon
/// nichts, weil die Verbindung nie so weit kommt. Diese Berichte sind der
/// einzige Kanal, über den wir davon je erführen.
///
/// Zwei Ansichten:
///
/// **E-Mails** ist das Archiv der Nachrichten, baugleich zu den anderen
/// Korrespondenz-Bereichen. Was an tls-rpt@icd360s.de eingeht, landet hier von
/// selbst (Cron, jede Minute). Der Eintrag hängt danach nicht mehr an der Mail.
///
/// **Berichte** ist der Inhalt: erfolgreiche und fehlgeschlagene Sitzungen, die
/// in Kraft befindliche Richtlinie, und im Fehlerfall die Art des Fehlers —
/// denn die sagt, WAS zu reparieren ist.
class TlsrptScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const TlsrptScreen({super.key, required this.apiService, required this.onBack});

  @override
  State<TlsrptScreen> createState() => _TlsrptScreenState();
}

/// PHP kennt nur einen Array-Typ: eine lückenlose Liste kodiert als `[]`,
/// dieselbe Struktur mit String-Schlüsseln als Objekt. Ein `as Map` auf einer
/// Liste wirft — genau daran blieb der Speedtest-Bildschirm am 05.08.2026 in
/// der Produktion grau hängen. Deshalb lesen diese Helfer beide Formen und
/// geben im Zweifel Leeres zurück, nie eine Ausnahme.
List<Map<String, dynamic>> tlsrptListe(dynamic roh) {
  if (roh is! List) return const [];
  return roh.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Map<String, dynamic> tlsrptMap(dynamic roh) {
  if (roh is Map) return Map<String, dynamic>.from(roh);
  return const {}; // eine Liste (auch die leere) ist hier keine Map
}

/// Erklärt, was TLS-RPT ist — und vor allem, wieso es etwas anderes ist als
/// DMARC. Die beiden sehen sich zum Verwechseln ähnlich: beide werden per
/// DNS-Eintrag bestellt, beide kommen täglich per Mail, beide von denselben
/// Anbietern. Sie beantworten trotzdem verschiedene Fragen.
Future<void> tlsrptErklaerungZeigen(BuildContext kontext) {
  return showDialog<void>(
    context: kontext,
    builder: (c) => AlertDialog(
      title: Row(children: [
        Icon(Icons.lock_outline, size: 22, color: F.h(Colors.indigo, 700)),
        const SizedBox(width: 9),
        const Expanded(child: Text('Was ist TLS-RPT?', style: TextStyle(fontSize: 17))),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            _Absatz(
              'Kurz gesagt',
              'Wenn ein fremder Mailserver uns eine Nachricht schickt, soll die '
              'Leitung dabei verschlüsselt sein. Wir schreiben öffentlich vor, '
              'dass das so sein MUSS. TLS-RPT ist der tägliche Bericht darüber, '
              'ob es geklappt hat.',
            ),
            _Absatz(
              'Der Unterschied zu DMARC',
              'Die beiden sehen sich ähnlich — beide bestellt man über einen '
              'DNS-Eintrag, beide kommen täglich per Mail, meist von denselben '
              'Anbietern. Sie schauen aber in entgegengesetzte Richtungen:\n\n'
              'DMARC: „Diese Post behauptet, von euch zu kommen — ist sie '
              'echt?" Es geht um Post, die VON uns kommt, und schützt unseren '
              'Namen.\n\n'
              'TLS-RPT: „Ich wollte euch Post bringen — war der Weg dorthin '
              'verschlüsselt?" Es geht um Post, die ZU uns kommt, und schützt '
              'den Inhalt unterwegs.\n\n'
              'Eine Nachricht kann DMARC bestehen und trotzdem unverschlüsselt '
              'unterwegs gewesen sein, und umgekehrt. Die Zahlen der beiden '
              'Schirme gehören deshalb nie in dieselbe Summe.',
            ),
            _Absatz(
              'Warum das für den Verein zählt',
              'An unsere Adressen geht, was Mitglieder uns schicken: Bescheide '
              'von Behörden, ärztliche Unterlagen, Vollmachten. Ohne '
              'Verschlüsselung auf der Leitung kann das unterwegs mitgelesen '
              'werden — nicht theoretisch, sondern von jedem, der irgendwo '
              'zwischen den beiden Servern sitzt.',
            ),
            _Absatz(
              'Was wir eingestellt haben',
              'MTA-STS im Modus „enforce": ein Absender, der unsere Richtlinie '
              'kennt, MUSS verschlüsselt liefern. Kann er es nicht, liefert er '
              'gar nicht — er fällt nicht heimlich auf Klartext zurück.\n\n'
              'Dazu DANE/TLSA: unser Zertifikat ist im DNS festgenagelt.',
            ),
            _Absatz(
              'Warum genau das gefährlich werden kann',
              '„Enforce" hat eine Kehrseite. Wird unser Mailzertifikat '
              'getauscht und der TLSA-Eintrag nicht mitgezogen, oder passt die '
              'Richtlinie nicht mehr zum Mailserver, dann lehnt der Absender '
              'ab — und zwar still. In unseren eigenen Logs steht davon nichts, '
              'weil die Verbindung nie so weit kommt. Wir würden nur merken, '
              'dass keine Post mehr ankommt, und nicht wissen, warum.\n\n'
              'Diese Berichte sind der einzige Kanal, der uns das sagen würde. '
              'Deshalb stehen sie hier und nicht im Papierkorb.',
            ),
            _Absatz(
              'Wie man die Zahlen liest',
              'Gezählt werden SITZUNGEN, nicht Nachrichten: eine Verbindung '
              'kann mehrere Nachrichten tragen, und ein Anbieter fasst '
              'zusammen.\n\n'
              'Steht bei „fehlgeschlagen" etwas, sagt die Art des Fehlers, was '
              'zu tun ist — ein abgelaufenes Zertifikat ist etwas anderes als '
              'eine Richtlinie, die nicht mehr zum Mailserver passt, und beides '
              'etwas anderes als ein Absender, dem STARTTLS gar nicht erst '
              'angeboten wurde.',
            ),
            _Absatz(
              'Was hier nicht steht',
              'Berichte kommen nur von Anbietern, die welche schicken — '
              'gemessen ist das bei uns bisher ausschliesslich Google. Ein '
              'kleiner Behördenserver, der uns nicht verschlüsselt erreichen '
              'kann, taucht hier gar nicht auf.\n\n'
              'Und es geht nur um die LEITUNG. Eine Nachricht, die '
              'verschlüsselt ankommt, liegt danach im Postfach wie jede '
              'andere; TLS sagt nichts über den Inhalt und nichts darüber, wer '
              'sie geschrieben hat.',
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
                fontSize: 13, fontWeight: FontWeight.w700, color: F.h(Colors.indigo, 700))),
        const SizedBox(height: 4),
        Text(text, style: TextStyle(fontSize: 13, height: 1.45, color: F.textSchwach)),
      ]),
    );
  }
}

class _TlsrptScreenState extends State<TlsrptScreen>
    with SingleTickerProviderStateMixin {
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
          Icon(Icons.lock_outline, size: 30, color: F.h(Colors.indigo, 700)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TLS-RPT Reporting',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text('Verschlüsselung auf dem Weg zu uns',
                  style: TextStyle(fontSize: 12, color: F.textLeise)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Was ist TLS-RPT?',
            onPressed: () => tlsrptErklaerungZeigen(context),
          ),
        ]),
      ),
      TabBar(
        controller: _tabs,
        labelColor: F.h(Colors.indigo, 700),
        indicatorColor: F.h(Colors.indigo, 700),
        tabs: const [
          Tab(icon: Icon(Icons.mail_outline, size: 18), text: 'E-Mails'),
          Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Berichte'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _TlsrptMailTab(apiService: widget.apiService, melde: _melde),
            _TlsrptBerichteTab(apiService: widget.apiService, melde: _melde),
          ],
        ),
      ),
    ]);
  }
}

// ═══════════════════ Tab 1: E-Mails ═══════════════════

/// Die Nachrichten, die an tls-rpt@icd360s.de eingegangen sind.
///
/// ⚠️ Hier gibt es bewusst kein „Erfassen". In den anderen Korrespondenz-
/// Bereichen ist der Knopf für das, was nicht per Mail kommt — ein Anruf beim
/// Support, ein Brief. TLS-Berichte erzeugt kein Mensch; ein Eingabeformular
/// wäre hier nur eine Möglichkeit, die Statistik zu verfälschen. Der
/// Endpunkt kann es weiterhin, falls es je gebraucht wird.
class _TlsrptMailTab extends StatefulWidget {
  final ApiService apiService;
  final void Function(String, {bool fehler}) melde;

  const _TlsrptMailTab({required this.apiService, required this.melde});

  @override
  State<_TlsrptMailTab> createState() => _TlsrptMailTabState();
}

class _TlsrptMailTabState extends State<_TlsrptMailTab>
    with AutomaticKeepAliveClientMixin {
  static const String _modul = 'tlsrpt';

  bool _laeuft = true;
  List<Map<String, dynamic>> _eintraege = [];

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
        _eintraege = tlsrptListe(
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
                          'E-Mails an tls-rpt@icd360s.de werden automatisch übernommen.',
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
    final dateien = tlsrptListe(k['dateien']);

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
            Icon(Icons.south_west, size: 15, color: F.h(Colors.indigo, 600)),
            const SizedBox(width: 5),
            Text('EINGANG',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: F.h(Colors.indigo, 700))),
          ]),
          Text(tlsrptZeit(k['datum']?.toString() ?? ''),
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
          Icon(eml ? Icons.mail_outline : Icons.folder_zip_outlined,
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

  /// Eine archivierte Nachricht geht in den Mail-Leser. Eine .eml an den
  /// Dateibetrachter zu geben zeigt nichts — der kennt PDFs und Bilder.
  ///
  /// ⚠️ Der Anhang eines Berichts ist ein ZIP oder ein .xml.gz, das der
  /// Betrachter genauso wenig kennt. Er wird deshalb heruntergeladen und dem
  /// System übergeben; wer den Inhalt lesen will, geht in den Tab „Berichte" —
  /// dort steht er ausgewertet.
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
      final sauber = (f['original_name'] ?? 'bericht')
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
          'Ist die Mail im Postfach schon gelöscht, ist das die letzte Kopie.\n\n'
          'Die ausgewerteten Zahlen im Tab „Berichte" bleiben erhalten.',
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
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Löschen fehlgeschlagen', fehler: true);
    }
  }
}

// ═══════════════════ Tab 2: Berichte ═══════════════════

class _TlsrptBerichteTab extends StatefulWidget {
  final ApiService apiService;
  final void Function(String, {bool fehler}) melde;

  const _TlsrptBerichteTab({required this.apiService, required this.melde});

  @override
  State<_TlsrptBerichteTab> createState() => _TlsrptBerichteTabState();
}

class _TlsrptBerichteTabState extends State<_TlsrptBerichteTab>
    with AutomaticKeepAliveClientMixin {
  bool _laeuft = true;
  int _tage = 30;
  Map<String, dynamic> _uebersicht = const {};
  List<Map<String, dynamic>> _fehler = const [];
  List<Map<String, dynamic>> _berichte = const [];

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
      final r = await widget.apiService.getTlsrptBerichte(tage: _tage);
      if (!mounted) return;
      if (r['success'] == true) {
        final d = r['data'] is Map ? Map<String, dynamic>.from(r['data']) : r;
        _uebersicht = tlsrptMap(d['uebersicht'] ?? r['uebersicht']);
        _fehler = tlsrptListe(d['fehler'] ?? r['fehler']);
        _berichte = tlsrptListe(d['berichte'] ?? r['berichte']);
      } else {
        widget.melde(r['message']?.toString() ?? 'Berichte nicht abrufbar', fehler: true);
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final t in const [7, 30, 90, 365]) ...[
                  ChoiceChip(
                    label: Text(t == 365 ? '1 Jahr' : '$t Tage',
                        style: const TextStyle(fontSize: 12)),
                    selected: _tage == t,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      setState(() => _tage = t);
                      _laden();
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
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
            : RefreshIndicator(
                onRefresh: _laden,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _uebersichtKarte(),
                    const SizedBox(height: 18),
                    _abschnitt('Fehlgeschlagene Sitzungen', Icons.error_outline),
                    const SizedBox(height: 8),
                    if (_fehler.isEmpty)
                      _leer('Kein einziger Fehler in diesem Zeitraum — jede '
                          'gemeldete Verbindung war verschlüsselt.')
                    else
                      for (final f in _fehler) ...[
                        _fehlerKarte(f),
                        const SizedBox(height: 8),
                      ],
                    const SizedBox(height: 12),
                    _abschnitt('Einzelne Berichte', Icons.description_outlined),
                    const SizedBox(height: 8),
                    if (_berichte.isEmpty)
                      _leer('Kein Bericht in diesem Zeitraum.')
                    else
                      for (final b in _berichte) ...[
                        _berichtKarte(b),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
      ),
    ]);
  }

  Widget _abschnitt(String titel, IconData ikone) => Row(children: [
        Icon(ikone, size: 17, color: F.h(Colors.grey, 600)),
        const SizedBox(width: 7),
        Text(titel,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: F.h(Colors.grey, 800))),
      ]);

  Widget _leer(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(text, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
      );

  Widget _uebersichtKarte() {
    final sitzungen = (_uebersicht['sitzungen'] as num?)?.toInt() ?? 0;
    final gut = (_uebersicht['erfolgreich'] as num?)?.toInt() ?? 0;
    final schlecht = (_uebersicht['fehlgeschlagen'] as num?)?.toInt() ?? 0;
    final quote = (_uebersicht['quote'] as num?)?.toDouble();
    final melder = (_uebersicht['melder'] as num?)?.toInt() ?? 0;
    final berichte = (_uebersicht['berichte'] as num?)?.toInt() ?? 0;
    final richtlinie = tlsrptMap(_uebersicht['richtlinie']);

    // ⚠️ „keine Daten" ist nicht „0 %". Ohne Bericht steht hier ein Strich,
    // nicht eine Null — eine Null hiesse, jede Verbindung sei gescheitert.
    final ok = schlecht == 0 && sitzungen > 0;
    final ton = sitzungen == 0
        ? Colors.grey
        : (ok ? Colors.green : Colors.orange);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: F.h(ton, 50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: F.h(ton, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(sitzungen == 0
              ? Icons.help_outline
              : (ok ? Icons.lock : Icons.warning_amber_rounded),
              size: 22, color: F.h(ton, 700)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              sitzungen == 0
                  ? 'Keine Meldung in diesem Zeitraum'
                  : (ok
                      ? 'Jede gemeldete Verbindung war verschlüsselt'
                      : '$schlecht von $sitzungen Verbindungen sind gescheitert'),
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: F.h(ton, 800)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 22, runSpacing: 12, children: [
          _zahl('Sitzungen', '$sitzungen'),
          _zahl('verschlüsselt', '$gut'),
          _zahl('gescheitert', '$schlecht'),
          _zahl('Quote', quote == null ? '–' : '${quote.toStringAsFixed(1)} %'),
          _zahl('Berichte', '$berichte'),
          _zahl('Melder', '$melder'),
        ]),
        if (richtlinie.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Zuletzt angewandte Richtlinie: '
            '${(richtlinie['typ'] ?? '?').toString().toUpperCase()}'
            '${(richtlinie['modus'] ?? '').toString().isEmpty ? '' : ' · ${richtlinie['modus']}'}'
            '${(richtlinie['mx'] ?? '').toString().isEmpty ? '' : ' · ${richtlinie['mx']}'}',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 800)),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Gezählt werden Sitzungen, nicht Nachrichten. Gescheitert heisst: ein '
          'fremder Server wollte uns Post bringen und konnte die verschlüsselte '
          'Verbindung nicht aufbauen — bei „enforce" liefert er dann gar nicht.',
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700), height: 1.35),
        ),
      ]),
    );
  }

  Widget _zahl(String titel, String wert) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(wert, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        Text(titel, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
      ]);

  /// Die Art des Fehlers ist das Einzige, woraus sich ableiten lässt, WAS zu
  /// reparieren ist. Ein unbekannter Schlüssel wird deshalb wörtlich gezeigt
  /// und nicht verschluckt — RFC 8460 lässt neue Werte zu.
  static const Map<String, String> _fehlerKlartext = {
    'starttls-not-supported': 'Der Gegenserver bekam kein STARTTLS angeboten',
    'certificate-host-mismatch': 'Zertifikat passt nicht zum Namen des Mailservers',
    'certificate-expired': 'Zertifikat war abgelaufen',
    'certificate-not-trusted': 'Zertifikat wurde nicht als vertrauenswürdig anerkannt',
    'validation-failure': 'TLS-Aufbau gescheitert (allgemein)',
    'sts-policy-fetch-error': 'Unsere MTA-STS-Richtlinie war nicht abrufbar',
    'sts-policy-invalid': 'Unsere MTA-STS-Richtlinie war fehlerhaft',
    'sts-webpki-invalid': 'Zertifikat des Richtlinien-Servers nicht anerkannt',
    'tlsa-invalid': 'DANE/TLSA-Eintrag passt nicht zum Zertifikat',
    'dnssec-invalid': 'DNSSEC-Prüfung fehlgeschlagen',
    'dane-required': 'DANE war erforderlich, aber nicht nutzbar',
    'sts-policy-mismatch': 'Mailserver passt nicht zur Richtlinie',
  };

  Widget _fehlerKarte(Map<String, dynamic> f) {
    final art = (f['ergebnis'] ?? '').toString();
    final anzahl = (f['anzahl'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(Colors.orange, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lock_open, size: 15, color: F.h(Colors.orange, 600)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(_fehlerKlartext[art] ?? (art.isEmpty ? 'Unbekannter Fehler' : art),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text('$anzahl', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            if (art.isNotEmpty) art,
            '${f['quellen'] ?? 0} Absender',
            if ((f['empfangender_mx'] ?? '').toString().isNotEmpty) '${f['empfangender_mx']}',
          ].join(' · '),
          style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
        ),
        if ((f['zusatz'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text((f['zusatz']).toString(),
              style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 700))),
        ],
      ]),
    );
  }

  Widget _berichtKarte(Map<String, dynamic> b) {
    final schlecht = (b['fehlgeschlagen'] as num?)?.toInt() ?? 0;
    final gut = (b['erfolgreich'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.randLeise),
      ),
      child: Row(children: [
        Icon(schlecht > 0 ? Icons.lock_open : Icons.lock_outline,
            size: 17,
            color: schlecht > 0 ? F.h(Colors.orange, 600) : F.h(Colors.green, 600)),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((b['org_name'] ?? '').toString(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              '${tlsrptZeit((b['zeit_von'] ?? '').toString())}'
              ' – ${tlsrptZeit((b['zeit_bis'] ?? '').toString())}'
              ' · ${(b['policy_typ'] ?? '?').toString().toUpperCase()}'
              '${(b['policy_modus'] ?? '').toString().isEmpty ? '' : ' ${b['policy_modus']}'}',
              style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
            ),
          ]),
        ),
        Text(schlecht > 0 ? '$gut / $schlecht' : '$gut',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

/// „2026-08-23 12:15:10" → „23.08.2026 12:15".
///
/// Die Zeitangaben aus einem Bericht sind UTC — der Server rechnet sie nicht
/// um, weil ein Berichtszeitraum ohnehin ein ganzer Tag in UTC ist und eine
/// Verschiebung um zwei Stunden nur so aussähe, als sei der Tag krumm.
String tlsrptZeit(String roh) {
  if (roh.length < 10) return roh;
  final d = roh.substring(0, 10).split('-');
  if (d.length != 3) return roh;
  final uhr = roh.length >= 16 ? ' ${roh.substring(11, 16)}' : '';
  return '${d[2]}.${d[1]}.${d[0]}$uhr';
}
