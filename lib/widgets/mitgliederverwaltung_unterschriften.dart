import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/user.dart';
import '../services/signatur_service.dart';
import '../utils/file_picker_helper.dart';

/// Reiter „Unterschriften" der Mitgliederverwaltung, direkt neben
/// Verifizierung — und das mit Absicht: die Unterschrift ist nur so viel wert
/// wie die Identität dahinter, und die steht im Reiter daneben. Wer hier eine
/// Unterschrift anfordert, sieht einen Klick weiter, ob der Ausweis dieses
/// Mitglieds je geprüft wurde.
///
/// Der Vorsitzer stellt hier ein PDF zur Unterschrift und liest hinterher das
/// Beweisbündel. Unterschreiben kann nur das Mitglied selbst, in seiner App,
/// mit dem Finger und einer TAN.
class MitgliederUnterschriftenTab extends StatefulWidget {
  final User user;
  final String adminMitgliedernummer;

  const MitgliederUnterschriftenTab({
    super.key,
    required this.user,
    required this.adminMitgliedernummer,
  });

  @override
  State<MitgliederUnterschriftenTab> createState() =>
      _MitgliederUnterschriftenTabState();
}

class _MitgliederUnterschriftenTabState
    extends State<MitgliederUnterschriftenTab> {
  final _service = SignaturService();

  List<Signaturvorgang> _vorgaenge = const [];
  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    if (mounted) setState(() => _laedt = true);
    final liste = await _service.liste(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      userId: widget.user.id,
    );
    if (!mounted) return;
    setState(() {
      _vorgaenge = liste;
      _laedt = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_laedt) {
      return const Center(child: CircularProgressIndicator());
    }

    final offen = _vorgaenge.where((v) => v.istOffen).length;

    return RefreshIndicator(
      onRefresh: _laden,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Kopfzeile(
            offen: offen,
            gesamt: _vorgaenge.length,
            onAnfordern: _anfordern,
          ),
          const SizedBox(height: 16),
          if (_vorgaenge.isEmpty)
            _LeererZustand(onAnfordern: _anfordern)
          else
            ..._vorgaenge.map((v) => _VorgangKachel(
                  vorgang: v,
                  onOeffnen: () => _detailZeigen(v),
                  onWiderrufen: v.istOffen ? () => _widerrufen(v) : null,
                )),
        ],
      ),
    );
  }

  // ── Anfordern ──

  Future<void> _anfordern() async {
    final auswahl = await FilePickerHelper.pickFiles(
      dialogTitle: 'PDF zur Unterschrift auswählen',
      allowedExtensions: const ['pdf'],
      type: FileType.custom,
    );
    final pfad = auswahl?.files.single.path;
    if (pfad == null || !mounted) return;

    final daten = await showDialog<_AnforderungsDaten>(
      context: context,
      builder: (_) => _AnfordernDialog(
        dateiname: auswahl!.files.single.name,
        mitglied: '${widget.user.vorname ?? ''} ${widget.user.nachname ?? ''}'.trim(),
      ),
    );
    if (daten == null || !mounted) return;

    _hinweis('PDF wird hochgeladen …');

    final ergebnis = await _service.anfordern(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      userId: widget.user.id,
      dokumentTyp: daten.typ,
      dokumentTitel: daten.titel,
      pdfPfad: pfad,
      fristBis: daten.fristBis,
    );

    if (!mounted) return;
    if (ergebnis.ok) {
      _hinweis('Zur Unterschrift gestellt. Das Mitglied wird benachrichtigt.',
          erfolg: true);
      await _laden();
    } else {
      _hinweis(ergebnis.fehler ?? 'Anforderung fehlgeschlagen', fehler: true);
    }
  }

  Future<void> _widerrufen(Signaturvorgang v) async {
    final grundController = TextEditingController();
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anforderung zurückziehen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('„${v.dokumentTitel}" wird nicht mehr zur Unterschrift '
                'angezeigt.'),
            const SizedBox(height: 12),
            TextField(
              controller: grundController,
              decoration: const InputDecoration(
                labelText: 'Grund (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Zurückziehen'),
          ),
        ],
      ),
    );

    if (bestaetigt != true || !mounted) return;

    final ok = await _service.widerrufen(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      signaturId: v.id,
      grund: grundController.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      await _laden();
    } else {
      _hinweis('Zurückziehen fehlgeschlagen', fehler: true);
    }
  }

  // ── Detail ──

  Future<void> _detailZeigen(Signaturvorgang v) async {
    final detail = await _service.detail(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      signaturId: v.id,
    );
    if (!mounted) return;

    if (detail == null) {
      _hinweis('Details konnten nicht geladen werden', fehler: true);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => _BeweisDialog(
        vorgang: v,
        detail: detail,
        onHerunterladen: v.istSigniert ? (welche) => _herunterladen(v, welche) : null,
      ),
    );
  }

  /// Speichert eine Fassung des Dokuments dort, wo der Vorsitzer sie hinlegt.
  Future<void> _herunterladen(Signaturvorgang v, String welche) async {
    final bytes = await _service.herunterladen(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      signaturId: v.id,
      welche: welche,
    );

    if (!mounted) return;
    if (bytes == null) {
      // Häufigster Fall ist nicht „kaputt", sondern „noch nicht fertig": das
      // Siegel entsteht im Minutentakt nach der Unterschrift.
      _hinweis(
        welche == 'signiert'
            ? 'Die gesiegelte Fassung wird noch erstellt — in etwa einer Minute erneut versuchen.'
            : 'Diese Fassung ist nicht verfügbar.',
        fehler: true,
      );
      return;
    }

    final stamm = v.dokumentTitel.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final name = switch (welche) {
      'original' => '$stamm.pdf',
      'tsr' => '${stamm}_zeitstempel.tsr',
      _ => '${stamm}_signiert.pdf',
    };

    final pfad = await FilePickerHelper.saveBytes(
      bytes: Uint8List.fromList(bytes),
      fileName: name,
    );

    if (!mounted) return;
    _hinweis(pfad == null ? 'Nicht gespeichert' : 'Gespeichert: $name',
        erfolg: pfad != null);
  }

  void _hinweis(String text, {bool erfolg = false, bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler
          ? Colors.red.shade700
          : erfolg
              ? Colors.green.shade700
              : null,
    ));
  }
}

// ───────────────────────────── Kopf + Liste ─────────────────────────────

class _Kopfzeile extends StatelessWidget {
  final int offen;
  final int gesamt;
  final VoidCallback onAnfordern;

  const _Kopfzeile({
    required this.offen,
    required this.gesamt,
    required this.onAnfordern,
  });

  @override
  Widget build(BuildContext context) {
    final wartet = offen > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: wartet ? Colors.orange.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: wartet ? Colors.orange.shade200 : Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            wartet ? Icons.pending_actions : Icons.check_circle,
            color: wartet ? Colors.orange.shade700 : Colors.green.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wartet
                      ? '$offen ${offen == 1 ? "Unterschrift steht aus" : "Unterschriften stehen aus"}'
                      : gesamt == 0
                          ? 'Noch nichts zur Unterschrift gestellt'
                          : 'Alles unterschrieben',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '$gesamt ${gesamt == 1 ? "Vorgang" : "Vorgänge"} insgesamt',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onAnfordern,
            icon: const Icon(Icons.draw, size: 18),
            label: const Text('Anfordern'),
          ),
        ],
      ),
    );
  }
}

class _LeererZustand extends StatelessWidget {
  final VoidCallback onAnfordern;
  const _LeererZustand({required this.onAnfordern});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.draw_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Das Mitglied unterschreibt in seiner App mit dem Finger\n'
            'und bestätigt mit einer TAN per SMS.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onAnfordern,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('PDF zur Unterschrift stellen'),
          ),
        ],
      ),
    );
  }
}

class _VorgangKachel extends StatelessWidget {
  final Signaturvorgang vorgang;
  final VoidCallback onOeffnen;
  final VoidCallback? onWiderrufen;

  const _VorgangKachel({
    required this.vorgang,
    required this.onOeffnen,
    this.onWiderrufen,
  });

  @override
  Widget build(BuildContext context) {
    final (farbe, symbol, text) = _status(vorgang);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onOeffnen,
        leading: CircleAvatar(
          backgroundColor: farbe.withValues(alpha: 0.15),
          child: Icon(symbol, color: farbe, size: 20),
        ),
        title: Text(vorgang.dokumentTitel,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(color: farbe, fontSize: 12)),
            if (vorgang.abgelehntGrund != null &&
                vorgang.abgelehntGrund!.isNotEmpty)
              Text('Begründung: ${vorgang.abgelehntGrund}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ],
        ),
        trailing: onWiderrufen == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                icon: const Icon(Icons.undo, size: 20),
                tooltip: 'Anforderung zurückziehen',
                onPressed: onWiderrufen,
              ),
      ),
    );
  }

  /// Farbe, Symbol und Klartext pro Zustand. Überfällig bekommt bewusst ein
  /// eigenes Aussehen: „offen seit drei Wochen" ist etwas anderes als
  /// „gestern angefordert", und beides nur grau zu zeigen verwischt genau die
  /// Fälle, die Aufmerksamkeit brauchen.
  (Color, IconData, String) _status(Signaturvorgang v) {
    if (v.istUeberfaellig) {
      return (
        Colors.red.shade700,
        Icons.schedule,
        'Frist abgelaufen — noch nicht unterschrieben'
      );
    }
    switch (v.status) {
      case 'signiert':
        return (
          Colors.green.shade700,
          Icons.verified,
          v.signedAtUtc != null
              ? 'Unterschrieben am ${_datum(v.signedAtUtc!)}'
              : 'Unterschrieben'
        );
      case 'abgelehnt':
        return (Colors.red.shade700, Icons.cancel, 'Vom Mitglied abgelehnt');
      case 'widerrufen':
        return (Colors.grey.shade600, Icons.undo, 'Zurückgezogen');
      case 'abgelaufen':
        return (Colors.grey.shade600, Icons.schedule, 'Abgelaufen');
      default:
        return (
          Colors.orange.shade700,
          Icons.pending,
          v.fristBis != null
              ? 'Offen — Frist bis ${_datum(v.fristBis!)}'
              : 'Offen'
        );
    }
  }
}

String _datum(DateTime d) {
  final l = d.toLocal();
  String zwei(int n) => n.toString().padLeft(2, '0');
  return '${zwei(l.day)}.${zwei(l.month)}.${l.year} ${zwei(l.hour)}:${zwei(l.minute)}';
}

// ───────────────────────────── Anfordern ─────────────────────────────

class _AnforderungsDaten {
  final String typ;
  final String titel;
  final DateTime? fristBis;
  const _AnforderungsDaten(this.typ, this.titel, this.fristBis);
}

class _AnfordernDialog extends StatefulWidget {
  final String dateiname;
  final String mitglied;

  const _AnfordernDialog({required this.dateiname, required this.mitglied});

  @override
  State<_AnfordernDialog> createState() => _AnfordernDialogState();
}

class _AnfordernDialogState extends State<_AnfordernDialog> {
  late final TextEditingController _titel =
      TextEditingController(text: widget.dateiname.replaceAll('.pdf', ''));
  String _typ = 'sonstiges';
  int _fristTage = 14;

  /// Welche Dokumente überhaupt über diesen Weg gehen, ist noch nicht
  /// entschieden — deshalb eine offene Liste statt einer festen Auswahl im
  /// Code. Der Server speichert den Typ als Text und nicht als ENUM, damit
  /// eine spätere Erweiterung kein ALTER TABLE auf einer Tabelle braucht, die
  /// dann schon Beweise trägt.
  static const _typen = <String, String>{
    'vereinbarung': 'Vereinbarung',
    'mitwirkungserklaerung': 'Mitwirkungserklärung',
    'einwilligung': 'Einwilligung',
    'vollmacht': 'Vollmacht',
    'sonstiges': 'Sonstiges',
  };

  @override
  void dispose() {
    _titel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Zur Unterschrift stellen'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Für ${widget.mitglied}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.picture_as_pdf, size: 16, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.dateiname,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titel,
              decoration: const InputDecoration(
                labelText: 'Titel',
                helperText: 'So sieht es das Mitglied in seiner App',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _typ,
              decoration: const InputDecoration(
                labelText: 'Art',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _typen.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _typ = v ?? 'sonstiges'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _fristTage,
              decoration: const InputDecoration(
                labelText: 'Frist',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 7, child: Text('7 Tage')),
                DropdownMenuItem(value: 14, child: Text('14 Tage')),
                DropdownMenuItem(value: 30, child: Text('30 Tage')),
                DropdownMenuItem(value: 0, child: Text('Ohne Frist')),
              ],
              onChanged: (v) => setState(() => _fristTage = v ?? 14),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _titel.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _AnforderungsDaten(
                      _typ,
                      _titel.text.trim(),
                      _fristTage > 0
                          ? DateTime.now().add(Duration(days: _fristTage))
                          : null,
                    ),
                  ),
          child: const Text('Anfordern'),
        ),
      ],
    );
  }
}

// ───────────────────────────── Beweisbündel ─────────────────────────────

/// Was zum Zeitpunkt der Unterschrift wahr war, auf einem Blatt.
///
/// Genau dafür ist der Reiter da: wenn jemand später bestreitet,
/// unterschrieben zu haben, muss der Vorsitzer das hier vorlegen können —
/// ohne in der Datenbank zu suchen und ohne dass jemand ihm erklären muss,
/// was die Felder bedeuten.
class _BeweisDialog extends StatelessWidget {
  final Signaturvorgang vorgang;
  final Map<String, dynamic> detail;

  /// Null, solange nichts unterschrieben ist — dann gibt es auch nichts
  /// herunterzuladen.
  final Future<void> Function(String welche)? onHerunterladen;

  const _BeweisDialog({
    required this.vorgang,
    required this.detail,
    this.onHerunterladen,
  });

  @override
  Widget build(BuildContext context) {
    final svg = (detail['signature_svg'] ?? '').toString();
    final ketteIntakt = detail['kette_intakt'];

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.fingerprint, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(vorgang.dokumentTitel)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ketteIntakt != null) _KetteBanner(intakt: ketteIntakt == true),
              if (ketteIntakt != null) const SizedBox(height: 12),

              if (vorgang.istSigniert) ...[
                const Text('Unterschrift',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: _unterschrift(svg),
                ),
                const SizedBox(height: 16),
              ],

              const Text('Beweisbündel',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              _Zeile('Dokument-Hash', _kurz(detail['pdf_hash'])),
              _Zeile('Unterschrieben (UTC)', detail['signed_at_utc']),
              _Zeile('Gerätezeit vor Ort', detail['signed_at_local']),
              _Zeile('IP-Adresse', detail['ip_address']),
              _Zeile('Hostname (Reverse-DNS)', detail['reverse_dns']),
              _Zeile('Provider', detail['isp']),
              _Zeile('Land', detail['country_iso']),
              _Zeile('Gerät', detail['device_hostname']),
              _Zeile('Geräteschlüssel', _kurz(detail['device_id'])),
              _Zeile('TAN gesendet an', detail['tan_an']),
              _Zeile('TAN bestätigt', detail['tan_verified_at']),
              _Zeile('Prüfcode', detail['verify_code']),
              _Zeile('Kettenhash', _kurz(detail['full_hash'])),
            ],
          ),
        ),
      ),
      actions: [
        if (onHerunterladen != null) ...[
          // Das Original bleibt abrufbar, nicht nur die gesiegelte Fassung:
          // FPDI baut die Seiten beim Siegeln neu auf, deshalb ist nur das
          // Original das, worauf `pdf_hash` passt.
          TextButton(
            onPressed: () => onHerunterladen!('original'),
            child: const Text('Original'),
          ),
          // Ohne den Token kann ein Dritter den Zeitstempel nicht nachrechnen —
          // und genau das ist der Sinn eines fremden Zeitstempels.
          TextButton(
            onPressed: () => onHerunterladen!('tsr'),
            child: const Text('Zeitstempel'),
          ),
          FilledButton.icon(
            onPressed: () => onHerunterladen!('signiert'),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Gesiegeltes PDF'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }

  Widget _unterschrift(String svg) {
    if (svg.trim().isEmpty) {
      return Center(
        child: Text('Keine Unterschrift hinterlegt',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      );
    }
    // Ein Pfad, der nicht als SVG ankommt, wird nicht an den Renderer
    // durchgereicht: der würde eine rote Fehlerfläche zeigen, die aussieht,
    // als sei die Unterschrift kaputt — dabei ist es die Übertragung.
    if (!svg.trimLeft().toLowerCase().contains('<svg')) {
      return Center(
        child: Text('Unlesbares Format (${svg.length} Bytes)',
            style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
      );
    }
    return SvgPicture.string(svg, fit: BoxFit.contain);
  }

  /// Hashes sind 64 Zeichen lang und in voller Länge im Dialog unlesbar. Für
  /// den Vergleich von Hand reichen Anfang und Ende — die vollständigen Werte
  /// stehen im signierten PDF und in der Datenbank.
  static String? _kurz(dynamic wert) {
    final s = wert?.toString() ?? '';
    if (s.isEmpty) return null;
    if (s.length <= 24) return s;
    return '${s.substring(0, 12)}…${s.substring(s.length - 8)}';
  }
}

class _KetteBanner extends StatelessWidget {
  final bool intakt;
  const _KetteBanner({required this.intakt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: intakt ? Colors.green.shade50 : Colors.red.shade50,
        border: Border.all(
            color: intakt ? Colors.green.shade200 : Colors.red.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(intakt ? Icons.link : Icons.link_off,
              size: 18,
              color: intakt ? Colors.green.shade700 : Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              intakt
                  ? 'Hash-Kette geprüft — der Datensatz ist seit der '
                      'Unterschrift unverändert.'
                  : 'Hash-Kette stimmt nicht. Der Datensatz wurde nach der '
                      'Unterschrift verändert.',
              style: TextStyle(
                fontSize: 12,
                color: intakt ? Colors.green.shade900 : Colors.red.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Zeile extends StatelessWidget {
  final String bezeichnung;
  final dynamic wert;
  const _Zeile(this.bezeichnung, this.wert);

  @override
  Widget build(BuildContext context) {
    final text = wert?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(bezeichnung,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(
              text.isEmpty ? '—' : text,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: text.isEmpty ? Colors.grey.shade400 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
