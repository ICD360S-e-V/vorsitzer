import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../services/global_chat_service.dart';
import '../services/secure_cloud_service.dart';
import '../widgets/cloud_file_picker.dart';

/// Zweiter Weg neben `FilePickerHelper`: Unterlagen nicht vom Gerät, sondern
/// aus dem Cloud holen — und zwar aus dem *richtigen* der beiden Speicher.
///
/// **Warum das Ergebnis ein [FilePickerResult] ist.** Alle Hochlade-Wege der
/// Behörden-Tabs sind über `filePath:` gebaut, geben also eine Datei auf der
/// Platte an den Server weiter. Cloud-Dateien liegen aber als Bytes vor (der
/// 50-GB-Speicher sogar nur verschlüsselt). Statt vier Dutzend Aufrufer auf
/// Bytes umzubauen, werden die Auswahl hier in temporäre Dateien geschrieben
/// und in genau der Form zurückgegeben, die der Geräte-Dialog liefert. Damit
/// bleibt hinter dem Knopf jede vorhandene Logik unangetastet — Grenzwerte,
/// Fortschritt, Nachfragen, Fehlermeldungen.
///
/// **Warum die Wahl des Speichers hier fällt und nicht beim Aufrufer.** Es gibt
/// zwei getrennte Speicher mit verschiedenen Regeln: `admin_cloud_files`
/// (50 GB, Ende-zu-Ende verschlüsselt) für die eigene Akte des angemeldeten
/// Vorsitzenden und `member_cloud_files` (1 GB) für Mitglieder. Ein an jeder
/// Stelle durchgereichtes Kennzeichen würde an der ersten vergessenen Stelle
/// still den falschen — und damit leeren — Speicher öffnen.
class CloudPickerHelper {
  CloudPickerHelper._();

  /// Mitgliedsnummer, falls für [memberId] der verschlüsselte 50-GB-Speicher
  /// zuständig ist; sonst null (dann gilt der 1-GB-Cloud des Mitglieds).
  ///
  /// Bearbeitet der angemeldete Vorsitzende seine EIGENE Akte, liegen seine
  /// Unterlagen im Speicher aus der Kopfzeile — im Mitglieder-Cloud wäre die
  /// Liste schlicht leer.
  static String? adminCloudFuer(int memberId) {
    final g = GlobalChatService();
    final nr = g.currentMitgliedernummer;
    final ich = g.currentAdminUserId;
    if (nr == null || nr.isEmpty || ich == null) return null;
    return memberId == ich ? nr : null;
  }

  /// Beschriftung/Sinnbild passend zum zuständigen Speicher, damit am Knopf
  /// erkennbar ist, welcher Cloud sich öffnet.
  static bool istVerschluesselt(int memberId) => adminCloudFuer(memberId) != null;

  /// Öffnet den zuständigen Cloud und legt die gewählten Dateien temporär ab.
  ///
  /// [allowedExtensions] wirkt als Nachfilter (ohne Punkt, klein geschrieben):
  /// die Cloud-Dialoge kennen keine Typfilter, ein hier nicht erlaubter Typ
  /// würde erst der Server abweisen. Aussortiertes wird dem Nutzer genannt.
  ///
  /// Gibt null zurück bei Abbruch oder wenn nichts übrig bleibt.
  static Future<FilePickerResult?> pickFiles(
    BuildContext context, {
    required ApiService apiService,
    required int memberId,
    List<String>? allowedExtensions,
    int? maxFiles,
  }) async {
    final adminNr = adminCloudFuer(memberId);
    final List<_CloudAuswahl>? auswahl;
    if (adminNr != null) {
      auswahl = await _ausAdminCloud(context,
          apiService: apiService,
          mitgliedernummer: adminNr,
          maxFiles: maxFiles,
          allowedExtensions: allowedExtensions);
    } else {
      auswahl = await _ausMitgliedCloud(context,
          apiService: apiService, memberId: memberId);
    }
    if (auswahl == null || auswahl.isEmpty) return null;

    var gewaehlt = auswahl;

    // Typfilter. Läuft vor der Obergrenze, damit kein Platz an eine Datei geht,
    // die gleich wieder aussortiert wird. Im verschlüsselten Cloud hat der
    // Dialog bereits gefiltert — dort bleibt hier nichts mehr übrig.
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      final erlaubt = allowedExtensions.map((e) => e.toLowerCase().replaceAll('.', '')).toSet();
      final passend = gewaehlt.where((d) => erlaubt.contains(d.filterEndung)).toList();
      final raus = gewaehlt.length - passend.length;
      if (raus > 0 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$raus Datei(en) übersprungen — hier sind nur '
              '${erlaubt.join(', ')} erlaubt.'),
          backgroundColor: Colors.orange,
        ));
      }
      gewaehlt = passend;
      if (gewaehlt.isEmpty) return null;
    }

    // Obergrenze des Ziels
    if (maxFiles != null && gewaehlt.length > maxFiles) {
      final raus = gewaehlt.length - maxFiles;
      gewaehlt = gewaehlt.take(maxFiles).toList();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Nur $maxFiles Datei(en) möglich — $raus übersprungen.'),
          backgroundColor: Colors.orange,
        ));
      }
    }

    if (!context.mounted) return null;
    final dateien = await showDialog<List<PlatformFile>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HolDialog(auswahl: gewaehlt, verschluesselt: adminNr != null),
    );
    if (dateien == null || dateien.isEmpty) return null;
    return FilePickerResult(dateien);
  }

  /// Übernahme aus dem zuständigen Cloud — kennt beide Speicher.
  ///
  /// Ersetzt `pickAndAttachFromCloud` an den Stellen, die auch der
  /// Vorsitzende in seiner eigenen Akte benutzt. Der Unterschied ist nicht
  /// bloß die Liste, sondern der ganze Weg:
  ///
  /// * **Mitglied (1 GB)** — [attach] kopiert serverseitig von Datensatz zu
  ///   Datensatz; die Datei berührt das Gerät nie. Schnell, also der Vorzug,
  ///   wo er möglich ist.
  /// * **Vorsitzender (50 GB, Ende-zu-Ende)** — [attach] wäre hier wertlos:
  ///   der Server kennt den Schlüssel nicht und würde einen unlesbaren Blob
  ///   weiterreichen. Deshalb wird lokal entschlüsselt und über [hochladen]
  ///   als gewöhnliche Datei abgelegt.
  ///
  /// Gibt die Zählung des Server-zu-Server-Weges zurück, damit vorhandene
  /// Aufrufer ihre Meldung behalten. Auf dem verschlüsselten Weg kommt null —
  /// dort meldet und lädt [hochladen] bereits selbst, eine zweite Meldung
  /// wäre doppelt.
  static Future<({int ok, int total})?> uebernehmen(
    BuildContext context, {
    required ApiService apiService,
    required int memberId,
    required Future<Map<String, dynamic>> Function(int cloudFileId) attach,
    required Future<void> Function(FilePickerResult) hochladen,
    List<String>? allowedExtensions,
    int? maxFiles,
  }) async {
    if (adminCloudFuer(memberId) != null) {
      final r = await pickFiles(context,
          apiService: apiService,
          memberId: memberId,
          allowedExtensions: allowedExtensions,
          maxFiles: maxFiles);
      if (r != null) await hochladen(r);
      return null;
    }
    // allowedExtensions muss auch hier mit: sonst filtert nur der verschlüsselte
    // Zweig, und derselbe Aufruf ließe über den Mitglieder-Cloud einen Typ durch,
    // den der Geräte-Knopf danebenan ablehnt.
    return pickAndAttachFromCloud(context,
        apiService: apiService,
        memberId: memberId,
        attach: attach,
        allowedExtensions: allowedExtensions,
        maxFiles: maxFiles);
  }

  // ── 50 GB, Ende-zu-Ende verschlüsselt ────────────────────────────────────
  //
  // Ein Server-zu-Server-Kopieren gibt es hier nicht: der Server kennt den
  // Schlüssel nicht und würde nur einen unlesbaren Blob weiterreichen. Also
  // wird lokal entschlüsselt und der Klartext hochgeladen.
  static Future<List<_CloudAuswahl>?> _ausAdminCloud(
    BuildContext context, {
    required ApiService apiService,
    required String mitgliedernummer,
    int? maxFiles,
    List<String>? allowedExtensions,
  }) async {
    final svc = SecureCloudService(apiService, mitgliedernummer);
    final gewaehlt = await showAdminCloudFilePicker(
      context,
      apiService: apiService,
      mitgliedernummer: mitgliedernummer,
      maxFiles: maxFiles,
      // Muss mit, weil der Dialog die Obergrenze selbst zieht: ohne den
      // Typfilter fiele sie auf Dateien, die danach aussortiert werden, und
      // der Nutzer bekäme weniger Anhänge als erlaubt.
      allowedExtensions: allowedExtensions,
    );
    if (gewaehlt == null) return null;
    return gewaehlt
        .map((f) => _CloudAuswahl(
              name: f.name,
              groesse: f.plainSize,
              lade: () => svc.downloadToMemory(f),
            ))
        .toList();
  }

  // ── 1 GB Mitglieder-Cloud ────────────────────────────────────────────────
  static Future<List<_CloudAuswahl>?> _ausMitgliedCloud(
    BuildContext context, {
    required ApiService apiService,
    required int memberId,
  }) async {
    final mnr = GlobalChatService().currentMitgliedernummer;
    if (mnr == null || mnr.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Kein Admin angemeldet'), backgroundColor: Colors.red));
      }
      return null;
    }
    final rows = await showCloudFilePickerFiles(
      context,
      apiService: apiService,
      memberId: memberId,
      mitgliedernummer: mnr,
    );
    if (rows == null) return null;
    return rows.map((r) {
      final id = (r['id'] as num).toInt();
      final ext =
          (r['extension']?.toString() ?? '').trim().replaceAll('.', '').toLowerCase();
      return _CloudAuswahl(
        name: r['filename']?.toString() ?? 'datei',
        // Nur für den Typfilter: der Name geht unverändert zum Server, sonst
        // entstünde aus „Bescheid.pdf" ein „Bescheid.pdf.pdf".
        endung: ext.isEmpty ? null : ext,
        groesse: (r['size'] as num?)?.toInt() ?? 0,
        lade: () async {
          final a = await apiService.downloadCloudFile(
              cloudFileId: id, mitgliedernummer: mnr);
          if (a['success'] != true || a['content'] == null) return null;
          return base64Decode(a['content'].toString());
        },
      );
    }).toList();
  }
}

/// Fertiger „Cloud"-Knopf als Geschwister des Geräte-Knopfes.
///
/// Sinnbild und Hinweistext richten sich nach dem zuständigen Speicher, damit
/// vor dem Klick erkennbar ist, was sich öffnet: Schloss/violett für den
/// verschlüsselten 50-GB-Speicher, Wolke/blau für den 1-GB-Cloud des Mitglieds.
class CloudPickButton extends StatelessWidget {
  final int memberId;
  final ApiService apiService;

  /// Wird mit den fertig abgelegten Dateien aufgerufen — dieselbe Form, die
  /// auch der Geräte-Dialog liefert, damit dahinter nichts angepasst werden muss.
  final ValueChanged<FilePickerResult> onPicked;

  final List<String>? allowedExtensions;
  final int? maxFiles;
  final bool enabled;

  /// Schmale Ausführung für enge Kopfzeilen neben einem kleinen Geräte-Knopf.
  final bool kompakt;

  const CloudPickButton({
    super.key,
    required this.memberId,
    required this.apiService,
    required this.onPicked,
    this.allowedExtensions,
    this.maxFiles,
    this.enabled = true,
    this.kompakt = false,
  });

  Future<void> _oeffne(BuildContext context) async {
    final r = await CloudPickerHelper.pickFiles(
      context,
      apiService: apiService,
      memberId: memberId,
      allowedExtensions: allowedExtensions,
      maxFiles: maxFiles,
    );
    if (r != null && r.files.isNotEmpty) onPicked(r);
  }

  @override
  Widget build(BuildContext context) {
    final e2e = CloudPickerHelper.istVerschluesselt(memberId);
    final farbe = e2e ? Colors.deepPurple : Colors.blue;
    return Tooltip(
      message: e2e
          ? 'Aus dem verschlüsselten 50-GB-Cloud wählen'
          : 'Aus dem 1-GB-Cloud des Mitglieds wählen',
      child: OutlinedButton.icon(
        onPressed: enabled ? () => _oeffne(context) : null,
        icon: Icon(e2e ? Icons.lock : Icons.cloud_download, size: kompakt ? 14 : 16),
        label: Text('Cloud', style: TextStyle(fontSize: kompakt ? 11 : 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: farbe.shade700,
          side: BorderSide(color: farbe.shade200),
          padding: EdgeInsets.symmetric(horizontal: kompakt ? 8 : 10, vertical: kompakt ? 4 : 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Eine im Cloud ausgewählte Datei samt Weg, an ihre Bytes zu kommen —
/// vereinheitlicht die beiden sehr verschiedenen Speicher für den Aufrufer.
class _CloudAuswahl {
  final String name;
  final int groesse;

  /// Endung laut Datensatz (klein, ohne Punkt), falls der Speicher sie getrennt
  /// vom Namen führt; sonst null.
  final String? endung;
  final Future<Uint8List?> Function() lade;
  const _CloudAuswahl(
      {required this.name, required this.groesse, required this.lade, this.endung});

  /// Endung für den Typfilter — die Spalte schlägt den Namen.
  ///
  /// Punkte kommen auch mitten im Namen vor („Bescheid_v1.2"); dort wäre die
  /// vermeintliche Endung „2" und eine gültige PDF verschwände still aus der
  /// Auswahl. [name] bleibt davon unberührt, denn er wandert als Dateiname mit
  /// zum Server.
  String get filterEndung {
    if (endung != null) return endung!;
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }
}

/// Holt die Auswahl und schreibt sie temporär auf die Platte.
///
/// Als Dialog und nicht als stiller Hintergrundlauf, weil je nach Größe und
/// Entschlüsselung spürbar Zeit vergeht; ohne Rückmeldung wirkt der Knopf tot
/// und wird ein zweites Mal gedrückt.
class _HolDialog extends StatefulWidget {
  final List<_CloudAuswahl> auswahl;
  final bool verschluesselt;
  const _HolDialog({required this.auswahl, required this.verschluesselt});
  @override
  State<_HolDialog> createState() => _HolDialogState();
}

class _HolDialogState extends State<_HolDialog> {
  int _fertig = 0;
  String _aktuell = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hole());
  }

  Future<void> _hole() async {
    final dateien = <PlatformFile>[];
    final fehler = <String>[];
    Directory? ordner;
    try {
      final tmp = await getTemporaryDirectory();
      // Eigener Ordner je Vorgang: zwei gleichnamige Cloud-Dateien würden sich
      // sonst gegenseitig überschreiben.
      ordner = Directory('${tmp.path}/cloud_pick_${identityHashCode(this)}');
      await ordner.create(recursive: true);
    } catch (e) {
      if (mounted) Navigator.of(context).pop(<PlatformFile>[]);
      return;
    }

    for (var i = 0; i < widget.auswahl.length; i++) {
      final d = widget.auswahl[i];
      if (mounted) setState(() => _aktuell = d.name);
      try {
        final bytes = await d.lade();
        if (bytes == null) {
          fehler.add(d.name);
        } else {
          final ziel = File('${ordner.path}/${i}_${_sicher(d.name)}');
          await ziel.writeAsBytes(bytes);
          dateien.add(PlatformFile(
            path: ziel.path,
            name: d.name,
            size: bytes.length,
            bytes: bytes,
          ));
        }
      } catch (_) {
        fehler.add(d.name);
      }
      if (mounted) setState(() => _fertig = i + 1);
    }

    if (!mounted) return;
    if (fehler.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${fehler.length} Datei(en) nicht lesbar: '
            '${fehler.take(3).join(', ')}${fehler.length > 3 ? ' …' : ''}'),
        backgroundColor: Colors.red,
      ));
    }
    Navigator.of(context).pop(dateien);
  }

  static String _sicher(String name) {
    final s = name.replaceAll(RegExp(r'[^\w\.\- ]'), '_').trim();
    return s.isEmpty ? 'datei' : s;
  }

  @override
  Widget build(BuildContext context) {
    final gesamt = widget.auswahl.length;
    return AlertDialog(
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(widget.verschluesselt ? Icons.lock : Icons.cloud_download,
                size: 18,
                color: widget.verschluesselt ? Colors.deepPurple.shade400 : Colors.blue.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.verschluesselt ? 'Wird entschlüsselt …' : 'Wird geladen …',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Text('$_fertig / $gesamt', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ]),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: gesamt == 0 ? null : _fertig / gesamt),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_aktuell,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ),
        ]),
      ),
    );
  }
}
