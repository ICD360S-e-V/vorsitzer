/// Die zwei SMS-Links zu einer Vollmacht — und was das Mitglied damit getan hat.
///
/// Gebaut für Mitglieder OHNE App. Am 18.08.2026 gemessen: von 44 aktiven
/// Mitgliedern haben 20 die App und 24 eine Mobilnummer — **zwölf** haben eine
/// Nummer, aber keine App und können sonst überhaupt nichts unterschreiben.
///
/// ⚠️ EINE Datei für beide Orte (Insolvenzverwaltung und Anwaltskanzlei).
/// Zwei Kopien wären zwei Stände: derselbe Knopf, der an einer Stelle die
/// Reihenfolge erzwingt und an der anderen nicht. Nur die beiden Aufrufe
/// unterscheiden sich, und die kommen als Rückrufe herein.
library;

import 'package:flutter/material.dart';
import '../utils/app_farben.dart';


/// Die Versandwege, ausgeschrieben.
///
/// ⚠️ Spiegelt `vollmacht_versand.weg` — die Aufzählung liegt in der
/// Datenbank, nicht hier. Kommt dort ein Weg dazu, gehört er auch hierher.
///
/// ⚠️ Sie steht in DIESER Datei, nicht in einem Behörden-Bildschirm: das
/// Versandprotokoll wird an mehreren Stellen gezeichnet, und zwei Tabellen
/// wären zwei Stände. Das Protokoll zeigte früher den ROHWERT — da stand
/// „fax an +49 731 …" und „email an …", kleingeschrieben und ohne
/// Präposition, wie ein Datenbankauszug.
const Map<String, String> kVollmachtVersandWege = {
  'chat': 'in den Chat',
  'email': 'per E-Mail',
  'bea': 'per beA',
  'fax': 'per Fax',
  'post': 'per Post',
  'persoenlich': 'persönlich übergeben',
};

/// Die Reihenfolge, in der die beiden Links gehen — und warum sie eine ist.
///
/// ⚠️ Zuerst LESEN, dann UNTERSCHREIBEN, und der zweite von Hand.
///
/// Unterschrieben wird die deutsche Fassung; sie bindet. Das Leseexemplar in
/// der Sprache des Mitglieds trägt kein Unterschriftsfeld. Wer beide Links
/// zugleich verschickt, lässt jemanden etwas unterschreiben, bevor er es
/// lesen konnte — und genau dafür gibt es die Übersetzung.
enum VollmachtLinkZweck { lesen, signieren }

/// Zwei Knöpfe unter einer Vollmacht.
///
/// [onSenden] bekommt den Zweck und gibt die Antwort des Servers zurück;
/// diese Klasse kennt weder ApiService noch das Modul.
class VollmachtLinkKnoepfe extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(String zweck) onSenden;

  /// Nach erfolgreichem Versand — damit die Liste sich neu lädt.
  final VoidCallback? onGesendet;

  /// Grau, solange die Vollmacht widerrufen ist. Der Server lehnt ohnehin ab;
  /// hier steht der Grund, statt ihn erst nach dem Klick zu zeigen.
  final bool widerrufen;

  final MaterialColor farbe;

  const VollmachtLinkKnoepfe({
    super.key,
    required this.onSenden,
    required this.farbe,
    this.onGesendet,
    this.widerrufen = false,
  });

  @override
  State<VollmachtLinkKnoepfe> createState() => _VollmachtLinkKnoepfeState();
}

class _VollmachtLinkKnoepfeState extends State<VollmachtLinkKnoepfe> {
  String? _laeuft;

  Future<void> _senden(BuildContext context, String zweck, String was) async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.sms_outlined, color: widget.farbe.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('$was per SMS schicken?', style: const TextStyle(fontSize: 15))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              zweck == 'lesen'
                  ? 'Das Mitglied bekommt einen Link auf sein Handy und kann die Vollmacht '
                    'in seiner Sprache lesen und herunterladen. Unterschrieben wird dabei '
                    'nichts.'
                  : 'Das Mitglied bekommt einen Link auf sein Handy und unterschreibt dort '
                    'mit dem Finger. Den Bestätigungscode bekommt es danach per SMS.',
              style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Text('⚠️ Der Link gilt 30 Minuten.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.orange, 900))),
            const SizedBox(height: 4),
            Text(
              'Danach ist er tot. Das Mitglied kann sich auf der Seite selbst einen '
              'neuen an dieselbe Nummer schicken lassen — Sie müssen dafür nichts tun.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
            if (zweck == 'signieren') ...[
              const SizedBox(height: 10),
              Text(
                'Unterschrieben wird die deutsche Fassung — sie ist die verbindliche. '
                'Schicken Sie diesen Link erst, wenn das Mitglied das Leseexemplar '
                'bestätigt hat.',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
            ],
          ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.farbe.shade700, foregroundColor: Colors.white),
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Schicken'),
            onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;

    setState(() => _laeuft = zweck);
    final r = await widget.onSenden(zweck);
    if (!mounted) return;
    setState(() => _laeuft = null);

    final ok = r['success'] == true;
    final ziel = (r['gesendet_an'] ?? '').toString();
    // ⚠️ `this.context` des States, nicht der übergebene: nur für den prüft
    // `mounted` oben tatsächlich mit.
    ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Link unterwegs an $ziel — gilt ${r['gueltig_minuten'] ?? 30} Minuten'
          : (r['message'] ?? 'Der Link konnte nicht geschickt werden').toString()),
      backgroundColor: ok ? Colors.green : Colors.red,
      duration: const Duration(seconds: 7)));
    if (ok) widget.onGesendet?.call();
  }

  Widget _knopf(String zweck, String beschriftung, IconData symbol, Color ton) {
    final laeuft = _laeuft == zweck;
    return OutlinedButton.icon(
      icon: laeuft
          ? const SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(symbol, size: 14),
      label: Text(beschriftung, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: ton,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      onPressed: (_laeuft != null || widget.widerrufen)
          ? null
          : () => _senden(context, zweck, beschriftung),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 4, children: [
      _knopf('lesen', 'Link zum Lesen', Icons.translate, Colors.teal.shade700),
      _knopf('signieren', 'Link zum Unterschreiben', Icons.draw, widget.farbe.shade700),
    ]);
  }
}

/// Eine Link-Zeile im Versandprotokoll.
///
/// ⚠️ Sie steht ABGESETZT von den Sendungen an die Gegenseite, nicht in
/// derselben Liste. Eine Fax- oder Mailzeile beantwortet „wann ging was an
/// wen"; diese beantwortet zusätzlich, was das Mitglied damit GETAN hat. In
/// eine Tabelle gepresst, deren Zeitspalte „gesendet" heißt, läse sich das
/// eine als das andere.
///
/// ⚠️ „geöffnet" heißt NICHT „gelesen". Jemand hat auf den Link getippt, mehr
/// sagt es nicht — und mehr steht hier deshalb auch nicht.
class VollmachtLinkZeile extends StatelessWidget {
  final Map<String, dynamic> link;
  const VollmachtLinkZeile({super.key, required this.link});

  static String _w(dynamic v) => (v ?? '').toString().trim();
  static bool _hat(dynamic v) => _w(v).isNotEmpty;

  /// Nur Datum und Uhrzeit, ohne Sekunden — im Protokoll zählt die Minute.
  static String _zeit(dynamic roh) {
    final s = _w(roh);
    if (s.length < 16) return s;
    final d = s.substring(0, 10).split('-');
    if (d.length != 3) return s;
    return '${d[2]}.${d[1]}.${d[0]} ${s.substring(11, 16)}';
  }

  @override
  Widget build(BuildContext context) {
    final zweck = _w(link['zweck']);
    final lesen = zweck == 'lesen';
    final erledigt = _hat(link['erledigt_am']);
    final abgelaufen = link['abgelaufen'] == true;

    final schritte = <(String, dynamic, IconData)>[
      ('geöffnet', link['geoeffnet_am'], Icons.visibility_outlined),
      ('heruntergeladen', link['geladen_am'], Icons.download_outlined),
      if (lesen) ('bestätigt', link['bestaetigt_am'], Icons.done_all),
      if (!lesen) ('unterschrieben', link['erledigt_am'], Icons.draw),
    ].where((s) => _hat(s.$2)).toList();

    final (Color ton, String stand) = erledigt
        ? (Colors.green.shade700, 'erledigt')
        : (abgelaufen ? Colors.grey : Colors.blue.shade700,
           abgelaufen ? 'abgelaufen' : 'offen');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(lesen ? Icons.translate : Icons.draw, size: 14, color: ton),
          const SizedBox(width: 6),
          Expanded(child: Text(
            '${_zeit(link['gesendet_am'])} · '
            '${lesen ? 'Leseexemplar' : 'deutsche Fassung'}'
            '${_hat(link['sprache']) && lesen ? ' (${_w(link['sprache'])})' : ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: ton.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4)),
            child: Text(stand, style: TextStyle(fontSize: 10, color: ton))),
        ]),
        Text('per SMS-Link an ${_w(link['gesendet_an'])}',
          style: const TextStyle(fontSize: 12)),
        if (_hat(link['gesendet_von_name']))
          Text('durch ${_w(link['gesendet_von_name'])}',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
        // Was das Mitglied getan hat — der eigentliche Grund für diese Zeile.
        for (var i = 0; i < schritte.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Row(children: [
              Text(i == schritte.length - 1 ? '└─ ' : '├─ ',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500),
                  fontFamily: 'monospace')),
              Icon(schritte[i].$3, size: 12, color: F.h(Colors.grey, 700)),
              const SizedBox(width: 4),
              Expanded(child: Text(
                '${_zeit(schritte[i].$2).split(' ').last}  ${schritte[i].$1}',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 800)))),
            ])),
        if ((int.tryParse(_w(link['codes_gesendet'])) ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text('   ${_w(link['codes_gesendet'])} Code(s) angefordert',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)))),
      ]),
    );
  }
}

/// Der Block „Links an das Mitglied" für einen Versandprotokoll-Dialog.
///
/// Gibt `null` zurück, wenn es keine gibt — dann soll gar keine Überschrift
/// erscheinen, statt einer leeren Rubrik.
Widget? vollmachtLinkBlock(List<Map<String, dynamic>> links) {
  if (links.isEmpty) return null;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Divider(height: 20),
    Row(children: [
      const Icon(Icons.sms_outlined, size: 15, color: Colors.teal),
      const SizedBox(width: 6),
      Text('Links an das Mitglied (${links.length})',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal)),
    ]),
    const SizedBox(height: 8),
    for (final l in links) VollmachtLinkZeile(link: l),
  ]);
}
